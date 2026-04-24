// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub category: String,
}

#[derive(Debug, Clone, Default)]
pub struct MediaSearchParams {
    pub systems: Vec<String>,
    pub max_results: u32,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaItem {
    pub name: String,
    pub path: String,
    #[serde(default)]
    pub zap_script: String,
    #[serde(default)]
    pub system: SystemRef,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SystemRef {
    pub id: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaSearchResult {
    pub results: Vec<MediaItem>,
    #[serde(default)]
    pub has_next_page: bool,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct MediaBrowseParams {
    pub path: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowseEntry {
    pub name: String,
    pub path: String,
    #[serde(rename = "type", default)]
    pub entry_type: String,
    #[serde(default)]
    pub file_count: u32,
}

impl BrowseEntry {
    pub fn is_folder(&self) -> bool {
        self.entry_type == "folder" || self.entry_type == "directory"
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct MediaBrowseResult {
    pub entries: Vec<BrowseEntry>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct RunParams {
    pub text: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct RunResult {}

#[derive(Debug, Clone, Default, Serialize)]
pub struct SystemsParams {}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SystemsResult {
    pub systems: Vec<SystemInfo>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct VersionResult {
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub platform: String,
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        clippy::unwrap_used,
        clippy::panic,
        reason = "tests should fail-fast on unexpected errors"
    )]

    use super::{BrowseEntry, MediaSearchResult, SystemsResult, VersionResult};

    #[test]
    fn is_folder_accepts_both_spellings() {
        let folder = BrowseEntry {
            entry_type: "folder".into(),
            ..BrowseEntry::default()
        };
        let directory = BrowseEntry {
            entry_type: "directory".into(),
            ..BrowseEntry::default()
        };
        let file = BrowseEntry {
            entry_type: "file".into(),
            ..BrowseEntry::default()
        };
        assert!(folder.is_folder());
        assert!(directory.is_folder());
        assert!(!file.is_folder());
    }

    #[test]
    fn is_folder_unknown_type_is_false() {
        for entry_type in ["", "symlink", "archive", "unknown", "FOLDER"] {
            let entry = BrowseEntry {
                entry_type: entry_type.into(),
                ..BrowseEntry::default()
            };
            assert!(
                !entry.is_folder(),
                "entry_type={entry_type:?} should not be classified as folder"
            );
        }
    }

    #[test]
    fn systems_result_deserialises_camelcase_payload() {
        let json = r#"{"systems":[{"id":"nes","name":"Nintendo","category":"Consoles"}]}"#;
        let result: SystemsResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.systems.len(), 1);
        assert_eq!(result.systems[0].id, "nes");
        assert_eq!(result.systems[0].category, "Consoles");
    }

    #[test]
    fn system_info_category_defaults_to_empty_when_missing() {
        let json = r#"{"systems":[{"id":"x","name":"X"}]}"#;
        let result: SystemsResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.systems[0].category, "");
    }

    #[test]
    fn media_search_result_parses_has_next_page() {
        let json = r#"{
            "results": [
                {"name":"Game","path":"/p","zapScript":"s","system":{"id":"nes"}}
            ],
            "hasNextPage": true
        }"#;
        let result: MediaSearchResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.results.len(), 1);
        assert!(result.has_next_page);
        assert_eq!(result.results[0].system.id, "nes");
        assert_eq!(result.results[0].zap_script, "s");
    }

    #[test]
    fn media_search_result_defaults_has_next_page() {
        let json = r#"{"results":[]}"#;
        let result: MediaSearchResult = serde_json::from_str(json).expect("parse");
        assert!(!result.has_next_page);
    }

    #[test]
    fn version_result_parses_populated_payload() {
        let json = r#"{"version":"1.2.3","platform":"mister"}"#;
        let result: VersionResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.version, "1.2.3");
        assert_eq!(result.platform, "mister");
    }

    #[test]
    fn version_result_missing_fields_default_to_empty() {
        let result: VersionResult = serde_json::from_str("{}").expect("parse");
        assert_eq!(result.version, "");
        assert_eq!(result.platform, "");
    }
}
