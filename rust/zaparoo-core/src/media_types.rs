// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
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
pub struct TagInfo {
    pub tag: String,
    #[serde(rename = "type", default)]
    pub tag_type: String,
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
    #[serde(default)]
    pub tags: Vec<TagInfo>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SystemRef {
    pub id: String,
}

/// Cursor-based pagination envelope shared by `media.search` and
/// `media.browse`. Fields are all defaulted so an absent envelope (e.g.
/// browse-root response with no file results) deserializes to "no more
/// pages."
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Pagination {
    #[serde(default)]
    pub has_next_page: bool,
    #[serde(default)]
    pub page_size: u32,
    #[serde(default)]
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct MediaSearchResult {
    pub results: Vec<MediaItem>,
    #[serde(default)]
    pub pagination: Pagination,
}

impl MediaSearchResult {
    pub fn has_next_page(&self) -> bool {
        self.pagination.has_next_page
    }
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
    #[serde(default)]
    pub system_id: String,
    #[serde(default)]
    pub zap_script: String,
    #[serde(default)]
    pub relative_path: String,
    #[serde(default)]
    pub group: String,
}

impl BrowseEntry {
    /// Upstream entry types are `root`, `directory`, and `media`. Both
    /// roots and directories are navigable containers; media entries are
    /// leaves.
    pub fn is_folder(&self) -> bool {
        self.entry_type == "directory" || self.entry_type == "root"
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaBrowseResult {
    #[serde(default)]
    pub path: String,
    pub entries: Vec<BrowseEntry>,
    #[serde(default)]
    pub total_files: u32,
    #[serde(default)]
    pub pagination: Option<Pagination>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct RunParams {
    pub text: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct ReadersWriteParams {
    pub text: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct SystemsParams {}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SystemsResult {
    pub systems: Vec<SystemInfo>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReaderInfo {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub reader_id: String,
    #[serde(default)]
    pub driver: String,
    #[serde(default)]
    pub info: String,
    #[serde(default)]
    pub connected: bool,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

impl ReaderInfo {
    pub fn is_nfc_reader(&self) -> bool {
        if !self.connected {
            return false;
        }
        let driver = self.driver.to_lowercase();
        let info = self.info.to_lowercase();
        let has_nfc_capability = self
            .capabilities
            .iter()
            .any(|capability| capability.eq_ignore_ascii_case("nfc"));
        has_nfc_capability
            || driver.contains("pn532")
            || driver.contains("acr122")
            || driver.contains("rc522")
            || info.contains("pn532")
            || info.contains("acr122")
            || info.contains("rc522")
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ReadersResult {
    #[serde(default)]
    pub readers: Vec<ReaderInfo>,
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

    use super::{
        BrowseEntry, MediaBrowseResult, MediaSearchResult, ReaderInfo, ReadersResult,
        SystemsResult, VersionResult,
    };

    #[test]
    fn is_folder_accepts_directory_and_root() {
        let directory = BrowseEntry {
            entry_type: "directory".into(),
            ..BrowseEntry::default()
        };
        let root = BrowseEntry {
            entry_type: "root".into(),
            ..BrowseEntry::default()
        };
        let media = BrowseEntry {
            entry_type: "media".into(),
            ..BrowseEntry::default()
        };
        assert!(directory.is_folder());
        assert!(root.is_folder());
        assert!(!media.is_folder());
    }

    #[test]
    fn is_folder_unknown_type_is_false() {
        for entry_type in ["", "folder", "file", "symlink", "archive", "DIRECTORY"] {
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
        let json = r#"{"systems":[{"id":"NES","name":"Nintendo","category":"Consoles"}]}"#;
        let result: SystemsResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.systems.len(), 1);
        assert_eq!(result.systems[0].id, "NES");
        assert_eq!(result.systems[0].category, "Consoles");
    }

    #[test]
    fn system_info_category_defaults_to_empty_when_missing() {
        let json = r#"{"systems":[{"id":"x","name":"X"}]}"#;
        let result: SystemsResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.systems[0].category, "");
    }

    #[test]
    fn media_search_result_parses_nested_pagination() {
        let json = r#"{
            "results": [
                {"name":"Game","path":"/p","zapScript":"s","system":{"id":"NES"},"tags":[]}
            ],
            "total": -1,
            "pagination": {
                "hasNextPage": true,
                "pageSize": 100,
                "nextCursor": "abc"
            }
        }"#;
        let result: MediaSearchResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.results.len(), 1);
        assert!(result.has_next_page());
        assert_eq!(result.pagination.page_size, 100);
        assert_eq!(result.pagination.next_cursor.as_deref(), Some("abc"));
        assert_eq!(result.results[0].system.id, "NES");
        assert_eq!(result.results[0].zap_script, "s");
    }

    #[test]
    fn media_search_result_defaults_pagination_when_missing() {
        let json = r#"{"results":[]}"#;
        let result: MediaSearchResult = serde_json::from_str(json).expect("parse");
        assert!(!result.has_next_page());
        assert_eq!(result.pagination.page_size, 0);
        assert!(result.pagination.next_cursor.is_none());
    }

    #[test]
    fn media_search_item_defaults_tags_when_missing() {
        let json =
            r#"{"results":[{"name":"G","path":"/p","zapScript":"s","system":{"id":"NES"}}]}"#;
        let result: MediaSearchResult = serde_json::from_str(json).expect("parse");
        assert!(result.results[0].tags.is_empty());
    }

    #[test]
    fn readers_result_deserialises_current_shape() {
        let json = r#"{
            "readers": [
                {
                    "id": "/dev/ttyUSB0",
                    "readerId": "pn532-ujqixjv6",
                    "driver": "pn532",
                    "info": "PN532 (1-2.3.1)",
                    "capabilities": ["read", "write"],
                    "connected": true
                }
            ]
        }"#;
        let result: ReadersResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.readers.len(), 1);
        assert_eq!(result.readers[0].id, "/dev/ttyUSB0");
        assert_eq!(result.readers[0].reader_id, "pn532-ujqixjv6");
        assert!(result.readers[0].is_nfc_reader());
    }

    #[test]
    fn nfc_reader_detection_requires_connection() {
        let connected = ReaderInfo {
            driver: "acr122usb".into(),
            connected: true,
            ..ReaderInfo::default()
        };
        let disconnected = ReaderInfo {
            driver: "pn532".into(),
            connected: false,
            ..ReaderInfo::default()
        };
        assert!(connected.is_nfc_reader());
        assert!(!disconnected.is_nfc_reader());
    }

    #[test]
    fn media_browse_result_parses_envelope_and_pagination() {
        let json = r#"{
            "path": "/games",
            "entries": [
                {"name":"NES","path":"/games/NES","type":"directory","fileCount":42},
                {"name":"SMB","path":"/games/NES/smb.nes","type":"media","systemId":"NES","zapScript":"@NES/smb","relativePath":"NES/smb.nes"}
            ],
            "totalFiles": 150,
            "pagination": {"hasNextPage": true, "pageSize": 100, "nextCursor": "x"}
        }"#;
        let result: MediaBrowseResult = serde_json::from_str(json).expect("parse");
        assert_eq!(result.path, "/games");
        assert_eq!(result.entries.len(), 2);
        assert!(result.entries[0].is_folder());
        assert!(!result.entries[1].is_folder());
        assert_eq!(result.entries[1].system_id, "NES");
        assert_eq!(result.entries[1].relative_path, "NES/smb.nes");
        assert_eq!(result.total_files, 150);
        let pagination = result.pagination.expect("pagination present");
        assert!(pagination.has_next_page);
        assert_eq!(pagination.next_cursor.as_deref(), Some("x"));
    }

    #[test]
    fn media_browse_result_omits_pagination_when_no_files() {
        let json = r#"{"entries":[{"name":"/","path":"","type":"root","fileCount":0}]}"#;
        let result: MediaBrowseResult = serde_json::from_str(json).expect("parse");
        assert!(result.pagination.is_none());
        assert_eq!(result.path, "");
        assert_eq!(result.total_files, 0);
        assert!(result.entries[0].is_folder());
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
