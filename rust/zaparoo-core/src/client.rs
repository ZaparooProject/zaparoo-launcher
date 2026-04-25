// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Async WebSocket JSON-RPC 2.0 client. Mirrors ZaparooClient.{cpp,h}.
// Runs on a tokio runtime; auto-reconnects with exponential backoff
// (1→2→4→8→16s, capped at 30s). After RETRY_ERROR_THRESHOLD consecutive
// connect failures the client publishes ConnectionState::Error so the UI
// can surface "Core unreachable" instead of a transient "Disconnected"
// banner. Public methods are async and safe to call from any tokio task.

use crate::media_types::{
    MediaBrowseParams, MediaBrowseResult, MediaSearchParams, MediaSearchResult, RunParams,
    SystemsParams, SystemsResult, VersionResult,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{oneshot, watch};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Consecutive connect failures after which the client advertises
/// `ConnectionState::Error` to subscribers. The outer loop keeps retrying
/// past this point — the threshold exists so the UI can escalate a
/// transient drop into a "Core unreachable" banner rather than cycling
/// endlessly through "Connecting…".
const RETRY_ERROR_THRESHOLD: u32 = 10;

/// Ceiling on reconnect backoff. Chosen so a laptop waking from sleep
/// after hours still reconnects within half a minute.
const MAX_BACKOFF_SECS: u64 = 30;

/// Rolling state of the WebSocket link, published via `watch` so late
/// subscribers (QML singletons whose `initialize()` runs after the QML
/// engine boots, post-connect) read the current value rather than
/// silently missing transitions. UI code derives its connection banner
/// from this plus the catalog RPC status; other tasks (catalog,
/// platform) trigger work on `Connected`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConnectionState {
    /// No active ws link — either never connected yet or briefly
    /// between retry attempts.
    Disconnected,
    /// `connect_async` in flight. Published at the head of every retry
    /// loop so the UI can show a "connecting" hint even before the first
    /// connect succeeds.
    Connecting,
    /// ws link up and service loop running.
    Connected,
    /// Consecutive connect failures exceeded `RETRY_ERROR_THRESHOLD`.
    /// Inner string is the last connect error. The task keeps retrying;
    /// recovery is signalled by a later `Connected`.
    Error(String),
}

#[derive(Debug, Clone, Serialize)]
struct RpcRequest<'a, T: Serialize> {
    jsonrpc: &'a str,
    method: &'a str,
    params: &'a T,
    id: String,
}

#[derive(Debug, Deserialize)]
struct RpcResponse {
    id: Option<String>,
    result: Option<Value>,
    error: Option<RpcError>,
}

#[derive(Debug, Deserialize, Clone)]
struct RpcError {
    message: String,
}

#[derive(Debug)]
pub struct ClientError {
    pub message: String,
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ClientError {}

type PendingMap = Arc<Mutex<HashMap<String, oneshot::Sender<Result<Value, ClientError>>>>>;

#[derive(Clone, Debug)]
pub struct Client {
    tx: tokio::sync::mpsc::UnboundedSender<String>,
    pending: PendingMap,
    pub connection: Arc<watch::Sender<ConnectionState>>,
}

impl Client {
    pub fn new(endpoint: String, runtime: &Arc<tokio::runtime::Runtime>) -> Arc<Self> {
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<String>();
        let (connection_tx, _) = watch::channel(ConnectionState::Disconnected);
        let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));
        let pending_clone = pending.clone();
        let connection_arc = Arc::new(connection_tx);
        let connection_clone = connection_arc.clone();

        let client = Arc::new(Self {
            tx: msg_tx,
            pending,
            connection: connection_arc,
        });

        runtime.spawn(async move {
            // Consecutive connect failures since the last successful
            // handshake. Drives `backoff_delay` and the error-surfacing
            // threshold; reset on `Ok`.
            let mut failures: u32 = 0;
            loop {
                connection_clone.send_replace(ConnectionState::Connecting);
                match connect_async(&endpoint).await {
                    Ok((ws_stream, _)) => {
                        failures = 0;
                        info!("connected to core at {endpoint}");
                        connection_clone.send_replace(ConnectionState::Connected);
                        let (mut write, mut read) = ws_stream.split();

                        loop {
                            tokio::select! {
                                msg = msg_rx.recv() => {
                                    match msg {
                                        Some(text) => {
                                            if let Err(e) = write.send(Message::Text(text)).await {
                                                warn!("ws send error: {e}");
                                                break;
                                            }
                                        }
                                        None => return, // Client dropped
                                    }
                                }
                                msg = read.next() => {
                                    match msg {
                                        Some(Ok(Message::Text(text))) => {
                                            if let Ok(resp) = serde_json::from_str::<RpcResponse>(text.as_str()) {
                                                if let Some(id) = resp.id {
                                                    #[allow(clippy::unwrap_used, reason = "mutex poisoning is unrecoverable")]
                                                    let sender = pending_clone.lock().unwrap().remove(&id);
                                                    if let Some(tx) = sender {
                                                        let result = if let Some(err) = resp.error {
                                                            Err(ClientError { message: err.message })
                                                        } else {
                                                            Ok(resp.result.unwrap_or(Value::Null))
                                                        };
                                                        let _ = tx.send(result);
                                                    }
                                                }
                                            }
                                        }
                                        Some(Ok(Message::Close(_))) | None => {
                                            debug!("ws closed");
                                            break;
                                        }
                                        Some(Err(e)) => {
                                            warn!("ws read error: {e}");
                                            break;
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }

                        connection_clone.send_replace(ConnectionState::Disconnected);
                        // Fail all pending requests
                        #[allow(clippy::unwrap_used, reason = "mutex poisoning is unrecoverable")]
                        let drained: Vec<_> = pending_clone.lock().unwrap().drain().collect();
                        for (_, tx) in drained {
                            let _ = tx.send(Err(ClientError { message: "disconnected".into() }));
                        }
                    }
                    Err(e) => {
                        failures = failures.saturating_add(1);
                        let state = if failures >= RETRY_ERROR_THRESHOLD {
                            ConnectionState::Error(e.to_string())
                        } else {
                            ConnectionState::Disconnected
                        };
                        connection_clone.send_replace(state);
                        debug!("ws connect failed (attempt {failures}): {e}");
                    }
                }
                tokio::time::sleep(backoff_delay(failures)).await;
            }
        });

        client
    }

    async fn call<P: Serialize>(&self, method: &str, params: &P) -> Result<Value, ClientError> {
        let id = Uuid::new_v4().to_string();
        let req = RpcRequest {
            jsonrpc: "2.0",
            method,
            params,
            id: id.clone(),
        };
        let text = serde_json::to_string(&req).map_err(|e| ClientError {
            message: e.to_string(),
        })?;

        let (resp_tx, resp_rx) = oneshot::channel();
        #[allow(clippy::unwrap_used, reason = "mutex poisoning is unrecoverable")]
        {
            self.pending.lock().unwrap().insert(id, resp_tx);
        }

        self.tx.send(text).map_err(|_| ClientError {
            message: "not connected".into(),
        })?;

        resp_rx.await.map_err(|_| ClientError {
            message: "channel closed".into(),
        })?
    }

    pub async fn systems(&self, params: SystemsParams) -> Result<SystemsResult, ClientError> {
        #[derive(Serialize)]
        struct P {}
        let _ = params;
        let val = self.call("systems", &P {}).await?;
        serde_json::from_value(val).map_err(|e| ClientError {
            message: e.to_string(),
        })
    }

    pub async fn media_search(
        &self,
        params: MediaSearchParams,
    ) -> Result<MediaSearchResult, ClientError> {
        #[derive(Serialize)]
        struct P {
            systems: Vec<String>,
            #[serde(rename = "maxResults")]
            max_results: u32,
        }
        let val = self
            .call(
                "media.search",
                &P {
                    systems: params.systems,
                    max_results: params.max_results,
                },
            )
            .await?;
        serde_json::from_value(val).map_err(|e| ClientError {
            message: e.to_string(),
        })
    }

    pub async fn media_browse(
        &self,
        params: MediaBrowseParams,
    ) -> Result<MediaBrowseResult, ClientError> {
        #[derive(Serialize)]
        struct P {
            path: String,
        }
        let val = self.call("media.browse", &P { path: params.path }).await?;
        serde_json::from_value(val).map_err(|e| ClientError {
            message: e.to_string(),
        })
    }

    pub async fn run(&self, params: RunParams) -> Result<(), ClientError> {
        #[derive(Serialize)]
        struct P {
            text: String,
        }
        // Upstream returns null on success; the launcher has no use for
        // the result body either way, so swallow it.
        self.call("run", &P { text: params.text }).await?;
        Ok(())
    }

    pub async fn version(&self) -> Result<VersionResult, ClientError> {
        #[derive(Serialize)]
        struct P {}
        let val = self.call("version", &P {}).await?;
        serde_json::from_value(val).map_err(|e| ClientError {
            message: e.to_string(),
        })
    }
}

/// Exponential backoff between connect attempts, capped at
/// `MAX_BACKOFF_SECS`. `failures == 0` represents "we just disconnected
/// from a successful session" and yields a 1 s retry so a brief drop
/// doesn't feel sluggish; each subsequent consecutive failure doubles
/// the delay until the cap.
///
/// Sequence: 0→1, 1→1, 2→2, 3→4, 4→8, 5→16, 6→30, 7+→30 (seconds).
fn backoff_delay(failures: u32) -> Duration {
    let exp = failures.saturating_sub(1).min(5);
    let secs = 1u64 << exp;
    Duration::from_secs(secs.min(MAX_BACKOFF_SECS))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_follows_exponential_curve_then_caps() {
        assert_eq!(backoff_delay(0), Duration::from_secs(1));
        assert_eq!(backoff_delay(1), Duration::from_secs(1));
        assert_eq!(backoff_delay(2), Duration::from_secs(2));
        assert_eq!(backoff_delay(3), Duration::from_secs(4));
        assert_eq!(backoff_delay(4), Duration::from_secs(8));
        assert_eq!(backoff_delay(5), Duration::from_secs(16));
        assert_eq!(backoff_delay(6), Duration::from_secs(MAX_BACKOFF_SECS));
        assert_eq!(backoff_delay(7), Duration::from_secs(MAX_BACKOFF_SECS));
        assert_eq!(
            backoff_delay(u32::MAX),
            Duration::from_secs(MAX_BACKOFF_SECS)
        );
    }
}
