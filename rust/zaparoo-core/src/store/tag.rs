// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Cache invalidation tags. Modeled on RTK Query: a value is tagged
// either with `Tag::any(K)` or `Tag::specific(K, id)`, and a mutation
// declares which tags it invalidates. Matching is implemented in
// `super::tags_match`; the rules are:
//
//   invalidate `Tag::any(K)`           → matches every entry tagged
//                                         with kind K, regardless of id
//   invalidate `Tag::specific(K, id)`  → matches entries tagged with
//                                         `Tag::any(K)` *or*
//                                         `Tag::specific(K, id)` only

#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub struct Tag {
    pub kind: &'static str,
    pub id: Option<String>,
}

impl Tag {
    /// Tag matching every entry of the given kind. Use this when an
    /// endpoint's data isn't keyed by an identifier (e.g. the catalog).
    #[must_use]
    pub const fn any(kind: &'static str) -> Self {
        Self { kind, id: None }
    }

    /// Tag matching an entry of the given kind and identifier. Use this
    /// for per-arg endpoints whose mutations may want to invalidate one
    /// specific entry without disturbing siblings.
    pub fn specific(kind: &'static str, id: impl Into<String>) -> Self {
        Self {
            kind,
            id: Some(id.into()),
        }
    }
}
