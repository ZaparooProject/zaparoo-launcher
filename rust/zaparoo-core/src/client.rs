// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Async WebSocket JSON-RPC 2.0 client. Mirrors ZaparooClient.{cpp,h}.
// Runs on a tokio runtime; auto-reconnects every second on disconnect.
// Public methods are async and safe to call from any tokio task.

use crate::media_types::{
    MediaBrowseParams, MediaBrowseResult, MediaSearchParams, MediaSearchResult, RunParams,
    RunResult, SystemsParams, SystemsResult, VersionResult,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{broadcast, oneshot};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, info, warn};
use uuid::Uuid;

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
    pub connected: Arc<broadcast::Sender<bool>>,
}

impl Client {
    pub fn new(endpoint: String, runtime: &Arc<tokio::runtime::Runtime>) -> Arc<Self> {
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<String>();
        let (connected_tx, _) = broadcast::channel::<bool>(16);
        let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));
        let pending_clone = pending.clone();
        let connected_arc = Arc::new(connected_tx);
        let connected_clone = connected_arc.clone();

        let client = Arc::new(Self {
            tx: msg_tx,
            pending,
            connected: connected_arc,
        });

        runtime.spawn(async move {
            loop {
                match connect_async(&endpoint).await {
                    Ok((ws_stream, _)) => {
                        info!("connected to core at {endpoint}");
                        let _ = connected_clone.send(true);
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

                        let _ = connected_clone.send(false);
                        // Fail all pending requests
                        #[allow(clippy::unwrap_used, reason = "mutex poisoning is unrecoverable")]
                        let drained: Vec<_> = pending_clone.lock().unwrap().drain().collect();
                        for (_, tx) in drained {
                            let _ = tx.send(Err(ClientError { message: "disconnected".into() }));
                        }
                    }
                    Err(e) => {
                        debug!("ws connect failed: {e}");
                    }
                }
                tokio::time::sleep(Duration::from_secs(1)).await;
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

    pub async fn run(&self, params: RunParams) -> Result<RunResult, ClientError> {
        #[derive(Serialize)]
        struct P {
            text: String,
        }
        let val = self.call("run", &P { text: params.text }).await?;
        serde_json::from_value(val).map_err(|e| ClientError {
            message: e.to_string(),
        })
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
