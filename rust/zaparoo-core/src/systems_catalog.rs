// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Fetches the systems list once on every connection event and publishes
// a parsed CatalogData to subscribers (the QObject models).

use crate::client::{Client, ConnectionState};
use crate::media_types::{SystemInfo, SystemsParams};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::watch;
use tracing::{info, warn};

#[derive(Debug, Clone)]
pub struct CatalogData {
    pub systems: Vec<SystemInfo>,
    pub categories: Vec<String>,
}

/// Lifecycle of the catalog fetch, published alongside `CatalogData` so the
/// UI can distinguish "waiting for Core" from "Core returned an error."
#[derive(Debug, Clone, Default)]
pub enum CatalogStatus {
    #[default]
    Idle,
    Loading,
    Ready,
    Errored(String),
}

#[derive(Debug)]
pub struct CatalogChannels {
    pub data: watch::Sender<Option<CatalogData>>,
    pub status: watch::Sender<CatalogStatus>,
}

impl CatalogData {
    pub fn systems_by_category(&self, category: &str) -> Vec<SystemInfo> {
        let is_other = category.eq_ignore_ascii_case("Other");
        self.systems
            .iter()
            .filter(|s| {
                if is_other {
                    s.category.is_empty()
                } else {
                    s.category.eq_ignore_ascii_case(category)
                }
            })
            .cloned()
            .collect()
    }
}

fn derive_categories(systems: &[SystemInfo]) -> Vec<String> {
    let mut seen: HashSet<String> = HashSet::new();
    let mut cats: Vec<String> = Vec::new();
    for s in systems {
        let cat = if s.category.is_empty() {
            "Other".to_string()
        } else {
            s.category.clone()
        };
        let lower = cat.to_lowercase();
        if seen.insert(lower) {
            cats.push(cat);
        }
    }
    cats.sort_by_key(|a| a.to_lowercase());
    cats
}

pub fn spawn(client: Arc<Client>, runtime: &Arc<tokio::runtime::Runtime>) -> CatalogChannels {
    let (data_tx, _) = watch::channel(None::<CatalogData>);
    let (status_tx, _) = watch::channel(CatalogStatus::Idle);
    let data = data_tx.clone();
    let status = status_tx.clone();
    let mut connection_rx = client.connection.subscribe();

    runtime.spawn(async move {
        // Seed from the watch's current value so we react if Core is
        // already Connected at subscription time, then loop on changes.
        let mut state = connection_rx.borrow_and_update().clone();
        loop {
            if matches!(state, ConnectionState::Connected) {
                status.send_replace(CatalogStatus::Loading);
                let seq_client = client.clone();
                match seq_client.systems(SystemsParams {}).await {
                    Ok(result) => {
                        let mut systems = result.systems;
                        systems.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
                        let categories = derive_categories(&systems);
                        info!(
                            "catalog loaded: {} systems, {} categories",
                            systems.len(),
                            categories.len()
                        );
                        data.send_replace(Some(CatalogData {
                            systems,
                            categories,
                        }));
                        status.send_replace(CatalogStatus::Ready);
                    }
                    Err(e) => {
                        warn!("systems RPC failed: {}", e.message);
                        status.send_replace(CatalogStatus::Errored(e.message));
                    }
                }
            }
            if connection_rx.changed().await.is_err() {
                break;
            }
            state = connection_rx.borrow_and_update().clone();
        }
    });

    CatalogChannels {
        data: data_tx,
        status: status_tx,
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{derive_categories, CatalogData};
    use crate::media_types::SystemInfo;

    fn sys(id: &str, name: &str, category: &str) -> SystemInfo {
        SystemInfo {
            id: id.into(),
            name: name.into(),
            category: category.into(),
        }
    }

    #[test]
    fn derive_categories_sorts_case_insensitively() {
        let systems = vec![
            sys("a", "A", "Handhelds"),
            sys("b", "B", "arcade"),
            sys("c", "C", "Consoles"),
        ];
        assert_eq!(
            derive_categories(&systems),
            vec!["arcade", "Consoles", "Handhelds"],
        );
    }

    #[test]
    fn derive_categories_dedupes_case_insensitively() {
        let systems = vec![
            sys("a", "A", "Arcade"),
            sys("b", "B", "arcade"),
            sys("c", "C", "ARCADE"),
        ];
        let cats = derive_categories(&systems);
        assert_eq!(cats.len(), 1);
        assert_eq!(cats[0], "Arcade"); // first encountered casing wins
    }

    #[test]
    fn derive_categories_synthesises_other_for_empty() {
        let systems = vec![sys("a", "A", ""), sys("b", "B", "Consoles")];
        assert_eq!(derive_categories(&systems), vec!["Consoles", "Other"]);
    }

    #[test]
    fn systems_by_category_filters_case_insensitively() {
        let data = CatalogData {
            systems: vec![
                sys("a", "A", "Arcade"),
                sys("b", "B", "Consoles"),
                sys("c", "C", "arcade"),
            ],
            categories: vec!["Arcade".into(), "Consoles".into()],
        };
        let arcade = data.systems_by_category("Arcade");
        assert_eq!(arcade.len(), 2);
        assert!(arcade
            .iter()
            .all(|s| s.category.eq_ignore_ascii_case("arcade")));
    }

    #[test]
    fn systems_by_category_other_selects_uncategorised() {
        let data = CatalogData {
            systems: vec![
                sys("a", "A", ""),
                sys("b", "B", "Consoles"),
                sys("c", "C", ""),
            ],
            categories: vec!["Consoles".into(), "Other".into()],
        };
        let other = data.systems_by_category("Other");
        assert_eq!(other.len(), 2);
        assert!(other.iter().all(|s| s.category.is_empty()));
    }

    #[test]
    fn systems_by_category_missing_returns_empty() {
        let data = CatalogData {
            systems: vec![sys("a", "A", "Arcade")],
            categories: vec!["Arcade".into()],
        };
        assert!(data.systems_by_category("Handhelds").is_empty());
    }

    #[test]
    fn catalog_snapshot_matches_fixture() {
        let mut systems = vec![
            sys("snes", "Super Nintendo", "Consoles"),
            sys("nes", "Nintendo", "Consoles"),
            sys("gb", "Game Boy", "Handhelds"),
            sys("mame", "MAME", "arcade"),
            sys("odd", "Odd One", ""),
        ];
        // Match the sort applied by spawn() before publishing.
        systems.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        let categories = derive_categories(&systems);
        insta::assert_debug_snapshot!(CatalogData {
            systems,
            categories
        });
    }
}
