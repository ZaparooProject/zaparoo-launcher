// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// One `Endpoint` (or `Mutation`) impl per file. See `crate::store` for
// the trait surface and how endpoints participate in the cache + tag
// invalidation system.

pub mod catalog;
pub mod media_search;
pub mod readers;
pub mod readers_write;
pub mod run;
