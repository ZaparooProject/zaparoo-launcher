// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `ReadersEndpoint` — connected reader status from Zaparoo Core.
// The launcher uses this only when Core is local, so the NFC HUD icon
// describes hardware attached to the same machine as the launcher.

use crate::client::{Client, ClientError};
use crate::media_types::ReadersResult;
use crate::store::Endpoint;
use futures_util::future::BoxFuture;
use std::sync::Arc;

#[derive(Debug)]
pub struct ReadersEndpoint;

impl Endpoint for ReadersEndpoint {
    type Args = ();
    type Output = ReadersResult;
    const NAME: &'static str = "Readers";

    fn fetch(
        client: Arc<Client>,
        _args: Self::Args,
    ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
        Box::pin(async move { client.readers().await })
    }
}
