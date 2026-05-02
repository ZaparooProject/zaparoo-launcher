// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// In-memory cache of media images (boxart, screenshot, wheel, titleshot,
// map, marquee, fanart, generic image) keyed by `(systemId, path)` —
// the canonical `(system, path)` pair Core uses to identify a media row
// across `media.search`/`media.browse`/`media.image`/`media.meta`.
//
// Owns a single fetch driver task so concurrent enqueues (e.g. a
// freshly-loaded games page with 30 tiles) serialise into one
// outstanding `media.image` RPC at a time — Core's WebSocket has the
// same rate limit `apply_append_page` already calls out, and overlapping
// scrape requests are not the bottleneck we want to hit first.
//
// **Memory only — never disk.** Zaparoo Core is the canonical
// persistent store for media images and metadata; the launcher caches
// in process memory only and re-fetches what it needs after a cold
// start. MiSTer has under 512 MB of shared system RAM with the launcher
// competing against Core, the FPGA wrapper, and the active core for it,
// so the cache enforces a strict bytes cap (`CACHE_CAP_BYTES`) with LRU
// eviction that prefers read entries over still-unread prefetches.
//
// Negative results (Core returned "no image" or any client error) are
// memoised in a FIFO ring capped at 4096 entries — process-lifetime
// only, so a subsequently scraped game shows up after the next launcher
// restart without any eviction dance.
//
// QML reaches the cache through a `QQuickImageProvider` registered on
// the QML engine under the `media-image` scheme: a `coverKey` of
// `media-image/<base64url-no-pad>` becomes the URL
// `image://media-image/<...>`, which `requestImage` decodes back to
// `(systemId, path)` and looks up in the in-memory map.

use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::{c_char, c_void};
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use base64::engine::general_purpose::{STANDARD as BASE64_STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use tokio::runtime::Runtime;
use tokio::sync::{broadcast, Notify};
use tracing::{debug, info, warn};

use zaparoo_core::media_types::MediaImageParams;
use zaparoo_core::store::Store;

/// Field separator used inside the encoded key. Unit Separator (US,
/// 0x1F) — never appears in valid system ids or filesystem paths so the
/// split back to `(system_id, path)` is unambiguous.
const KEY_SEPARATOR: u8 = 0x1F;

/// Cap on the negative memo ring. Sized so a typical browse session
/// never trims it under normal flow (one page is ~30 entries; 4096
/// covers ~130 pages of misses), while the bytes cost stays bounded:
/// each entry is two `Arc<str>` so ~32 B header + the average
/// `system_id/path` pair (~64 B) → roughly 400 KiB worst-case.
const NEGATIVE_MEMO_CAP: usize = 4096;

/// Hard cap on cached image bytes. Sized to comfortably hold one or two
/// pages of typical Games tiles plus the occasional ~5 MiB boxart
/// outlier without LRU-evicting prefetched-but-not-yet-read entries.
/// On `MiSTer` (492 MiB total, no swap) this still leaves ~300 MiB for
/// Core, the FPGA wrapper, and a loaded game core; measured headroom
/// with the launcher running was 367 MiB available.
const CACHE_CAP_BYTES: usize = 64 * 1024 * 1024;

/// Maximum retries for a single key after a transient fetch failure
/// (RPC error, base64 decode error). Generous enough to ride through
/// one bad reconnect, small enough that a key genuinely broken on
/// Core's side stops thrashing the wire. The counter resets on the
/// next user-driven re-enqueue (a page revisit clears `pending` →
/// re-enters `enqueue` → resets `attempts`), so giving up is a
/// session-local "stop retrying right now" rather than a permanent
/// memo.
const MAX_FETCH_ATTEMPTS: u8 = 3;

/// Number of parallel fetch worker tasks pulling from the shared
/// LIFO queue. The Zaparoo Core WebSocket multiplexes JSON-RPC calls
/// by id so concurrent `media.image` requests are safe at the wire;
/// however, Core itself currently serializes its `media.image`
/// handler at roughly one response per 250–400 ms. Empirically all
/// four workers spend most of their time parked on `oneshot`
/// receivers waiting for Core's serial output — so the *immediate*
/// throughput floor is set by Core, not by us. Four workers is kept
/// as an upper bound that costs nothing under the current cadence
/// (idle workers parked on `Notify` are free) and turns into an
/// instant win the moment Core gains concurrency in its image
/// handler. Don't drop this back to 1.
const FETCH_DRIVER_WORKERS: usize = 4;

/// Hard cap on pending enqueues in the LIFO fetch queue. New pushes
/// spill the **oldest** entry off the front, on the assumption that
/// whatever the user enqueued ~2 pages ago is no longer interesting
/// (re-fetch on scroll-back is cheap, and the model's role-data path
/// re-enqueues uncached visible tiles automatically). Combined with
/// LIFO drain, this means the queue always reflects the user's recent
/// navigation, not their entire session — older requests neither
/// block the wire nor accumulate memory. Sized at 2× a typical
/// 30-tile page so a full look-ahead prefetch can overlap the
/// current page without dropping anything.
const MAX_QUEUE_LEN: usize = 60;

/// MIME content-type → on-disk extension for the formats we are willing
/// to cache. Falls back to inspecting `MediaImageResult.extension` when
/// `content_type` is missing or unknown — Core started populating the
/// `extension` field directly for exactly this reason.
const SUPPORTED_EXTS: &[(&str, &str)] = &[
    ("image/png", "png"),
    ("image/jpeg", "jpg"),
    ("image/jpg", "jpg"),
    ("image/webp", "webp"),
];

const SUPPORTED_PLAIN_EXTS: &[&str] = &["png", "jpg", "jpeg", "webp"];

fn ext_for_content_type(content_type: &str) -> Option<&'static str> {
    let head = content_type.split(';').next()?.trim().to_ascii_lowercase();
    SUPPORTED_EXTS
        .iter()
        .find_map(|(ct, ext)| (*ct == head).then_some(*ext))
}

/// Normalise a Core-supplied extension (e.g. `"jpeg"`, `".PNG"`) to
/// our canonical lowercase no-dot form (`"jpg"`, `"png"`). Returns
/// `None` for anything outside the supported set so callers fall
/// back to `content_type` resolution or the negative memo.
fn ext_from_extension_field(raw: &str) -> Option<&'static str> {
    let trimmed = raw.trim_start_matches('.').trim().to_ascii_lowercase();
    if !SUPPORTED_PLAIN_EXTS.iter().any(|e| *e == trimmed) {
        return None;
    }
    Some(match trimmed.as_str() {
        "jpeg" | "jpg" => "jpg",
        "png" => "png",
        "webp" => "webp",
        // Unreachable: filtered above.
        _ => return None,
    })
}

/// Canonical media identifier: `(systemId, path)` pair used everywhere
/// downstream. `Arc<str>` so cloning into broadcast frames /
/// `MediaImageUpdate` is cheap and the encoded URL key keeps a single
/// allocation.
#[derive(Clone, Debug)]
pub struct MediaKey {
    pub system_id: Arc<str>,
    pub path: Arc<str>,
}

impl MediaKey {
    pub fn new(system_id: impl Into<Arc<str>>, path: impl Into<Arc<str>>) -> Self {
        Self {
            system_id: system_id.into(),
            path: path.into(),
        }
    }

    /// Encode `(system_id, path)` as a single URL path segment using
    /// base64url-no-pad over `system_id || 0x1F || path`. Reversible
    /// via `decode`; lossless even for paths containing slashes.
    pub fn encode(&self) -> String {
        let mut buf = Vec::with_capacity(self.system_id.len() + 1 + self.path.len());
        buf.extend_from_slice(self.system_id.as_bytes());
        buf.push(KEY_SEPARATOR);
        buf.extend_from_slice(self.path.as_bytes());
        URL_SAFE_NO_PAD.encode(&buf)
    }

    pub fn decode(encoded: &str) -> Option<Self> {
        let bytes = URL_SAFE_NO_PAD.decode(encoded.as_bytes()).ok()?;
        let sep = bytes.iter().position(|b| *b == KEY_SEPARATOR)?;
        let (sys, rest) = bytes.split_at(sep);
        let path = &rest[1..]; // skip the separator
        let system_id = std::str::from_utf8(sys).ok()?;
        let path = std::str::from_utf8(path).ok()?;
        Some(Self::new(system_id.to_string(), path.to_string()))
    }
}

impl PartialEq for MediaKey {
    fn eq(&self, other: &Self) -> bool {
        *self.system_id == *other.system_id && *self.path == *other.path
    }
}
impl Eq for MediaKey {}

impl std::hash::Hash for MediaKey {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        (*self.system_id).hash(state);
        (*self.path).hash(state);
    }
}

/// Update event published when the cache state changes for one media
/// key. `ext` is `Some` after a successful fetch and `None` after a
/// negative resolution; subscribers use this to invalidate row
/// `dataChanged(coverKey)` on the Qt thread.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MediaImageUpdate {
    pub key: MediaKey,
    pub ext: Option<&'static str>,
}

#[derive(Debug)]
struct MediaImageEntry {
    bytes: Vec<u8>,
    #[allow(dead_code, reason = "ext is informational; provider only needs bytes")]
    ext: &'static str,
    /// Monotonically increasing usage counter used as the LRU clock.
    /// `u64` is overkill but guarantees no wraparound across any
    /// realistic process lifetime.
    last_used: u64,
    /// `true` once `get_bytes` has handed these bytes to `QtQuick` at
    /// least once. Eviction prefers read entries — unread entries are
    /// the prefetcher's bet that QML is about to ask for them, and
    /// dropping them under pressure causes the tile to render as
    /// fallback text even though Core already returned the bytes.
    read: bool,
}

#[derive(Default, Debug)]
struct NegativeMemo {
    order: VecDeque<MediaKey>,
    set: HashSet<MediaKey>,
}

impl NegativeMemo {
    fn contains(&self, key: &MediaKey) -> bool {
        self.set.contains(key)
    }

    fn insert(&mut self, key: MediaKey) {
        if !self.set.insert(key.clone()) {
            return;
        }
        self.order.push_back(key);
        while self.order.len() > NEGATIVE_MEMO_CAP {
            if let Some(dropped) = self.order.pop_front() {
                self.set.remove(&dropped);
            }
        }
    }
}

#[derive(Debug)]
struct CacheState {
    map: HashMap<MediaKey, MediaImageEntry>,
    total_bytes: usize,
    negative: NegativeMemo,
    pending: HashSet<MediaKey>,
    /// Per-key retry counter for transient fetch failures. Bumped in
    /// the fetch driver before each re-enqueue; cleared on Success,
    /// `NoImage`, or final give-up after `MAX_FETCH_ATTEMPTS`. Lives
    /// inside the locked state so the read/bump/decision happens
    /// atomically with the `pending` mutation that drives the retry.
    attempts: HashMap<MediaKey, u8>,
    /// Strictly increasing LRU clock. Bumped on every successful read
    /// or insert; the entry with the smallest value is the LRU.
    clock: u64,
}

impl CacheState {
    fn new() -> Self {
        Self {
            map: HashMap::new(),
            total_bytes: 0,
            negative: NegativeMemo::default(),
            pending: HashSet::new(),
            attempts: HashMap::new(),
            clock: 0,
        }
    }

    fn next_clock(&mut self) -> u64 {
        self.clock = self.clock.saturating_add(1);
        self.clock
    }

    /// Drop entries until `total_bytes` fits under `cap_bytes`. Two-pass:
    /// pick the LRU among **read** entries first, fall back to the LRU
    /// among unread entries only when nothing has been read yet. This
    /// means QML-consumed entries are eligible for eviction before
    /// prefetched-but-not-yet-painted ones — without that ordering, a
    /// page-fill burst that overshoots the cap can drop entries before
    /// the `QtQuick` provider's first paint pass reads them. Linear scan
    /// over `map`; the cache holds at most a few hundred entries so
    /// the O(N) pass per evicted entry is well below noise.
    fn evict_until_fits(&mut self, cap_bytes: usize) {
        while self.total_bytes > cap_bytes {
            let victim = self
                .map
                .iter()
                .filter(|(_, e)| e.read)
                .min_by_key(|(_, e)| e.last_used)
                .map(|(k, _)| k.clone())
                .or_else(|| {
                    self.map
                        .iter()
                        .min_by_key(|(_, e)| e.last_used)
                        .map(|(k, _)| k.clone())
                });
            let Some(victim) = victim else {
                break;
            };
            if let Some(entry) = self.map.remove(&victim) {
                self.total_bytes = self.total_bytes.saturating_sub(entry.bytes.len());
                debug!(
                    system_id = %victim.system_id,
                    path = %victim.path,
                    bytes = entry.bytes.len(),
                    read = entry.read,
                    total_bytes = self.total_bytes,
                    "media_image_cache: evicted entry"
                );
            }
        }
    }
}

pub struct MediaImageCache {
    state: Arc<RwLock<CacheState>>,
    /// LIFO queue of pending fetches. `enqueue` pushes to the back,
    /// the fetch driver pops from the back: newest enqueues drain
    /// first, while enqueues from a page the user has already
    /// navigated past wait at the front rather than blocking the
    /// work the user can see. Plain `std::sync::Mutex` because every
    /// critical section is a single `push_back`/`pop_back` with no
    /// awaits in between.
    ///
    /// **Look-ahead intentionally rides the same queue at the same
    /// priority.** Under Core's current ~250–400 ms serial cadence
    /// for `media.image`, the LIFO drain order ends up servicing
    /// page N+1's prefetched covers between page N's first burst
    /// (the visual top of the page, enqueued in reverse so it pops
    /// first) and page N's tail (the bottom rows the user is least
    /// likely to read before paginating). By the time the user
    /// navigates forward, page N+1 is warm; the few unfilled tiles
    /// at the bottom of page N continue to land in the background.
    /// Treating look-ahead as a "low priority" lane that drains
    /// *after* the visible page strictly worsens the experience: the
    /// visible page consumes the entire serial throughput in front
    /// of the user (which reads as "covers loading slowly one at a
    /// time"), and page N+1 doesn't start until the visible page is
    /// fully cached, which is well after a fast-moving user has
    /// already paginated. Don't reintroduce a priority split here.
    queue: Arc<Mutex<VecDeque<MediaKey>>>,
    /// Single-permit signal that wakes the driver when a fresh key
    /// hits the queue. Drained by `notified().await` and rearmed by
    /// `notify_one()` per enqueue.
    queue_notify: Arc<Notify>,
    updates_tx: broadcast::Sender<MediaImageUpdate>,
}

impl MediaImageCache {
    fn new<F>(cap_bytes: usize, runtime: &Arc<Runtime>, store_factory: F) -> Self
    where
        F: Fn() -> Arc<Store> + Send + Sync + 'static,
    {
        info!(cap_bytes, "media_image_cache: initialised (in-memory)");
        let state = Arc::new(RwLock::new(CacheState::new()));
        let queue: Arc<Mutex<VecDeque<MediaKey>>> = Arc::new(Mutex::new(VecDeque::new()));
        let queue_notify = Arc::new(Notify::new());
        let (updates_tx, _) = broadcast::channel::<MediaImageUpdate>(64);

        spawn_fetch_driver(
            runtime,
            cap_bytes,
            &state,
            &updates_tx,
            &queue,
            &queue_notify,
            store_factory,
        );

        Self {
            state,
            queue,
            queue_notify,
            updates_tx,
        }
    }

    /// Bytes for `key`, if cached. Bumps `last_used` so the entry's
    /// LRU position reflects the read. Returns a clone — encoded
    /// images are 30–80 KiB, the clone cost is below the cost of
    /// holding a lock across Qt code on the requester thread.
    pub fn get_bytes(&self, key: &MediaKey) -> Option<Vec<u8>> {
        #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
        let mut guard = self.state.write().unwrap();
        let next = guard.next_clock();
        let entry = guard.map.get_mut(key)?;
        entry.last_used = next;
        entry.read = true;
        Some(entry.bytes.clone())
    }

    /// True iff `key` has bytes in the cache. Unlike `get_bytes`,
    /// this does **not** bump `last_used` or flip `read` — it's a
    /// pure existence query for callers (e.g. role-data lookups in
    /// `GamesModel`) that need to choose a URL without their lookup
    /// contaminating the LRU clock. The clock should track actual
    /// paints (provider calls from
    /// `QQuickImageProvider::requestImage`), not role-data lookups,
    /// so read-pinning eviction stays meaningful.
    pub fn is_cached(&self, key: &MediaKey) -> bool {
        #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
        let guard = self.state.read().unwrap();
        guard.map.contains_key(key)
    }

    /// True iff `key` is in the negative memo (Core said "no image",
    /// or returned an unsupported format / oversize payload). Used
    /// by callers that drive miss-recovery enqueues to suppress
    /// re-fetch attempts for keys we've already learned have nothing
    /// to fetch.
    pub fn is_negative(&self, key: &MediaKey) -> bool {
        #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
        let guard = self.state.read().unwrap();
        guard.negative.contains(key)
    }

    /// Subscribe to cache updates. Used by `GamesModel` to bridge image
    /// completions onto `dataChanged(coverKey)` on the Qt thread.
    pub fn subscribe(&self) -> broadcast::Receiver<MediaImageUpdate> {
        self.updates_tx.subscribe()
    }

    /// Schedule a fetch for `key` if it isn't already cached, in the
    /// negative memo, or already pending. Idempotent: callers can spam
    /// this from `apply_initial_page`/`apply_append_page` without
    /// filtering, the cache deduplicates internally.
    ///
    /// When the queue exceeds `MAX_QUEUE_LEN`, the oldest entries at
    /// the front are dropped and released from `pending` — they were
    /// most likely enqueued for a page the user has already navigated
    /// past, and a future role-data lookup (or an explicit re-enqueue)
    /// can re-add them if they become relevant again.
    pub fn enqueue(&self, key: MediaKey) {
        if key.system_id.is_empty() || key.path.is_empty() {
            return;
        }
        let should_send = {
            #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
            let mut guard = self.state.write().unwrap();
            if guard.map.contains_key(&key)
                || guard.negative.contains(&key)
                || guard.pending.contains(&key)
            {
                false
            } else {
                // Reset the retry counter — a fresh user-driven
                // enqueue (e.g. a page revisit after a previous
                // give-up) deserves another bounded run of attempts.
                guard.attempts.remove(&key);
                guard.pending.insert(key.clone());
                true
            }
        };
        if !should_send {
            return;
        }
        let dropped = {
            #[allow(clippy::unwrap_used, reason = "Mutex poisoning is unrecoverable")]
            let mut q = self.queue.lock().unwrap();
            q.push_back(key);
            // Keep only the freshest MAX_QUEUE_LEN entries; the rest
            // (oldest enqueues at the front) get dropped. The dropped
            // keys must also leave `pending` so a later `enqueue` can
            // re-add them — otherwise the `pending` short-circuit
            // would silently suppress them forever.
            let mut dropped: Vec<MediaKey> = Vec::new();
            while q.len() > MAX_QUEUE_LEN {
                let Some(stale) = q.pop_front() else { break };
                dropped.push(stale);
            }
            dropped
        };
        if !dropped.is_empty() {
            #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
            let mut guard = self.state.write().unwrap();
            for stale in &dropped {
                guard.pending.remove(stale);
            }
            debug!(
                dropped = dropped.len(),
                queue_cap = MAX_QUEUE_LEN,
                "media_image_cache: queue cap hit, dropped stale enqueues"
            );
        }
        self.queue_notify.notify_one();
    }

    /// `coverKey` value for QML: `"media-image/<encoded>"`. The
    /// `Resources.qml` helper rewrites this to
    /// `image://media-image/<encoded>` so the `QQuickImageProvider`
    /// resolves the cached bytes.
    pub fn image_key_for(key: &MediaKey) -> String {
        format!("media-image/{}", key.encode())
    }
}

fn spawn_fetch_driver<F>(
    runtime: &Arc<Runtime>,
    cap_bytes: usize,
    state: &Arc<RwLock<CacheState>>,
    updates_tx: &broadcast::Sender<MediaImageUpdate>,
    queue: &Arc<Mutex<VecDeque<MediaKey>>>,
    queue_notify: &Arc<Notify>,
    store_factory: F,
) where
    F: Fn() -> Arc<Store> + Send + Sync + 'static,
{
    // One Arc'd factory shared across the worker pool — `F` is only
    // `Fn`, not `Clone`, so wrapping it once and cloning the Arc gives
    // every worker a cheap handle into the same underlying closure.
    let store_factory: Arc<F> = Arc::new(store_factory);
    for _ in 0..FETCH_DRIVER_WORKERS {
        let state = state.clone();
        let updates_tx = updates_tx.clone();
        let queue = queue.clone();
        let queue_notify = queue_notify.clone();
        let store_factory = store_factory.clone();
        runtime.spawn(async move {
            loop {
                let next_key = {
                    #[allow(clippy::unwrap_used, reason = "Mutex poisoning is unrecoverable")]
                    let mut q = queue.lock().unwrap();
                    q.pop_back()
                };
                let Some(key) = next_key else {
                    queue_notify.notified().await;
                    continue;
                };
                let store = store_factory();
                let outcome = fetch_one(&store, &key).await;
                let is_transient = matches!(outcome, FetchOutcome::Transient);
                let update = finish_fetch(&state, cap_bytes, &key, outcome);
                if is_transient {
                    let attempts = {
                        #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
                        let mut s = state.write().unwrap();
                        let entry = s.attempts.entry(key.clone()).or_insert(0);
                        *entry = entry.saturating_add(1);
                        *entry
                    };
                    if attempts < MAX_FETCH_ATTEMPTS {
                        // Re-enter `pending` and re-enqueue at the back.
                        // Fresh-page enqueues that arrive in the meantime
                        // still drain ahead because we always pop from
                        // the back; this retry waits behind anything the
                        // user is actively looking at.
                        {
                            #[allow(
                                clippy::unwrap_used,
                                reason = "RwLock poisoning is unrecoverable"
                            )]
                            let mut s = state.write().unwrap();
                            s.pending.insert(key.clone());
                        }
                        {
                            #[allow(
                                clippy::unwrap_used,
                                reason = "Mutex poisoning is unrecoverable"
                            )]
                            let mut q = queue.lock().unwrap();
                            q.push_back(key);
                        }
                        queue_notify.notify_one();
                    } else {
                        // Bounded give-up: clear the counter, no negative
                        // memo. The next user-driven enqueue (page
                        // revisit) gets a fresh `MAX_FETCH_ATTEMPTS`
                        // budget via `enqueue`'s `attempts.remove`.
                        #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
                        state.write().unwrap().attempts.remove(&key);
                        info!(
                            system_id = %key.system_id,
                            path = %key.path,
                            attempts,
                            "media_image_cache: giving up after transient failures",
                        );
                    }
                    continue;
                }
                // Success or NoImage: clear the attempts counter and
                // broadcast the resolved state.
                {
                    #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
                    let mut s = state.write().unwrap();
                    s.attempts.remove(&key);
                }
                if let Some(update) = update {
                    if let Some(ext) = update.ext {
                        info!(
                            system_id = %key.system_id,
                            path = %key.path,
                            ext,
                            "media_image_cache: cached image",
                        );
                    } else {
                        info!(
                            system_id = %key.system_id,
                            path = %key.path,
                            "media_image_cache: no image (negative memo)",
                        );
                    }
                    let _ = updates_tx.send(update);
                }
            }
        });
    }
}

#[derive(Debug)]
enum FetchOutcome {
    Success {
        bytes: Vec<u8>,
        ext: &'static str,
    },
    /// Core gave a definitive "no image" answer for this `(system_id,
    /// path)` — empty payload, unsupported format. Caller memoises so
    /// page revisits do not re-issue a guaranteed-miss RPC.
    NoImage,
    /// Local or RPC-level failure that may not repeat: socket flap,
    /// rate-limit during fast flicking, base64 wire corruption, generic
    /// `media.image` error from Core. Caller clears `pending` and lets
    /// the next `enqueue` retry; never memoised, because the *next*
    /// time the user looks at this row Core may answer cleanly.
    Transient,
}

async fn fetch_one(store: &Arc<Store>, key: &MediaKey) -> FetchOutcome {
    let result = store
        .client()
        .media_image(MediaImageParams::for_media(
            key.system_id.as_ref(),
            key.path.as_ref(),
        ))
        .await;
    let response = match result {
        Ok(r) => r,
        Err(e) => {
            info!(
                system_id = %key.system_id,
                path = %key.path,
                "media_image_cache: media.image failed: {} (transient, will retry on next enqueue)",
                e.message,
            );
            return FetchOutcome::Transient;
        }
    };
    let bytes = match BASE64_STANDARD.decode(response.data.as_bytes()) {
        Ok(b) => b,
        Err(e) => {
            warn!(
                system_id = %key.system_id,
                path = %key.path,
                "media_image_cache: base64 decode failed: {e} (transient, will retry on next enqueue)",
            );
            return FetchOutcome::Transient;
        }
    };
    // Defensive: a zero-length payload would land in the cache as a
    // valid-looking entry, the provider would hand 0 bytes to QtQuick,
    // and `QImage::loadFromData` would fail silently. Core already
    // skips empty binaries (see `media_image.go:176`), but treating
    // empty bytes as a negative result here closes the foot-gun
    // permanently — the negative memo absorbs `(system_id, path)` so
    // we don't refetch on every page revisit.
    if bytes.is_empty() {
        warn!(
            system_id = %key.system_id,
            path = %key.path,
            "media_image_cache: media.image returned 0 bytes after base64 decode, treating as no image",
        );
        return FetchOutcome::NoImage;
    }
    // Prefer `extension` (Core derives it from MIME or source path),
    // fall back to `content_type`. No magic-byte sniffing — Core
    // started populating both fields for exactly this reason.
    let ext = response
        .extension
        .as_deref()
        .and_then(ext_from_extension_field)
        .or_else(|| ext_for_content_type(&response.content_type));
    let Some(ext) = ext else {
        warn!(
            system_id = %key.system_id,
            path = %key.path,
            extension = ?response.extension,
            content_type = response.content_type,
            bytes_len = bytes.len(),
            "media_image_cache: unsupported extension/content_type, skipping cache",
        );
        return FetchOutcome::NoImage;
    };
    FetchOutcome::Success { bytes, ext }
}

fn finish_fetch(
    state: &Arc<RwLock<CacheState>>,
    cap_bytes: usize,
    key: &MediaKey,
    outcome: FetchOutcome,
) -> Option<MediaImageUpdate> {
    #[allow(clippy::unwrap_used, reason = "RwLock poisoning is unrecoverable")]
    let mut guard = state.write().unwrap();
    guard.pending.remove(key);
    match outcome {
        FetchOutcome::Success { bytes, ext } => {
            if bytes.len() > cap_bytes {
                warn!(
                    system_id = %key.system_id,
                    path = %key.path,
                    bytes = bytes.len(),
                    cap_bytes,
                    "media_image_cache: payload exceeds cache cap, recording as negative",
                );
                guard.negative.insert(key.clone());
                return Some(MediaImageUpdate {
                    key: key.clone(),
                    ext: None,
                });
            }
            let bytes_len = bytes.len();
            let next = guard.next_clock();
            let entry = MediaImageEntry {
                bytes,
                ext,
                last_used: next,
                read: false,
            };
            if let Some(prev) = guard.map.insert(key.clone(), entry) {
                guard.total_bytes = guard.total_bytes.saturating_sub(prev.bytes.len());
            }
            guard.total_bytes = guard.total_bytes.saturating_add(bytes_len);
            guard.evict_until_fits(cap_bytes);
            Some(MediaImageUpdate {
                key: key.clone(),
                ext: Some(ext),
            })
        }
        FetchOutcome::NoImage => {
            guard.negative.insert(key.clone());
            Some(MediaImageUpdate {
                key: key.clone(),
                ext: None,
            })
        }
        // Transient: drop the pending guard and let the next enqueue
        // retry. No map insert, no negative memo, no broadcast — the
        // row's `coverKey` is unchanged so subscribers have nothing to
        // act on.
        FetchOutcome::Transient => None,
    }
}

static GLOBAL_MEDIA_IMAGE_CACHE: OnceLock<Arc<MediaImageCache>> = OnceLock::new();

/// Lazily initialise the process-wide media image cache and return a
/// handle.
/// Constructed on first call from any thread; subsequent calls return
/// the same `Arc` so subscribers see the same broadcast channel.
pub fn global_media_image_cache() -> Arc<MediaImageCache> {
    GLOBAL_MEDIA_IMAGE_CACHE
        .get_or_init(|| {
            let runtime = crate::models::global_runtime();
            let cache =
                MediaImageCache::new(CACHE_CAP_BYTES, &runtime, crate::models::global_store);
            Arc::new(cache)
        })
        .clone()
}

/// C ABI bridge to the `QQuickImageProvider` on the C++ side. The
/// provider passes the URL id (the bit after `image://media-image/`) and a
/// callback that copies bytes into a `QByteArray`. The callback is
/// invoked exactly once with the bytes (or with an empty slice when the
/// key has no cached entry).
///
/// # Safety
///
/// `encoded` must point to `encoded_len` bytes that remain live
/// for the duration of this call. UTF-8 validity is checked
/// internally — non-UTF-8 input is reported via the warn log and
/// returns no bytes. `callback` is invoked exactly once before
/// this function returns; the `data` pointer it receives is valid
/// for the duration of the callback only.
#[no_mangle]
pub unsafe extern "C" fn zaparoo_media_image_bytes_for(
    encoded: *const c_char,
    encoded_len: usize,
    callback: extern "C" fn(user_data: *mut c_void, data: *const u8, len: usize),
    user_data: *mut c_void,
) {
    if encoded.is_null() {
        callback(user_data, std::ptr::null(), 0);
        return;
    }
    // SAFETY: caller guarantees `encoded` points to `encoded_len`
    // bytes live for this call. Qt's `QString::toUtf8()` is documented
    // to produce valid UTF-8, so `from_utf8` should always succeed —
    // but validate anyway to keep this FFI seam free of UB if a future
    // caller or a Qt regression ever sends bad bytes.
    let encoded_bytes = unsafe { std::slice::from_raw_parts(encoded.cast::<u8>(), encoded_len) };
    let Ok(encoded_str) = std::str::from_utf8(encoded_bytes) else {
        warn!(
            encoded_len,
            "media_image_cache: provider id is not valid UTF-8 (Qt invariant violated)"
        );
        callback(user_data, std::ptr::null(), 0);
        return;
    };
    let Some(key) = MediaKey::decode(encoded_str) else {
        warn!(
            encoded_len,
            "media_image_cache: MediaKey::decode failed (malformed image://media-image/ id)"
        );
        callback(user_data, std::ptr::null(), 0);
        return;
    };
    let cache = global_media_image_cache();
    if let Some(bytes) = cache.get_bytes(&key) {
        info!(
            system_id = %key.system_id,
            path = %key.path,
            cache_hit = true,
            bytes_len = bytes.len(),
            "media_image_cache: provider lookup",
        );
        callback(user_data, bytes.as_ptr(), bytes.len());
    } else {
        info!(
            system_id = %key.system_id,
            path = %key.path,
            cache_hit = false,
            "media_image_cache: provider lookup",
        );
        callback(user_data, std::ptr::null(), 0);
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

    use super::{
        ext_for_content_type, ext_from_extension_field, finish_fetch, CacheState, FetchOutcome,
        MediaImageCache, MediaImageUpdate, MediaKey, NegativeMemo, MAX_QUEUE_LEN,
        NEGATIVE_MEMO_CAP,
    };
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex, RwLock};
    use tokio::sync::{broadcast, Notify};

    /// Build a `MediaImageCache` without spawning the fetch driver.
    /// Lets tests exercise `enqueue` / `is_cached` / `is_negative`
    /// against the public surface without needing a tokio runtime or
    /// a live `Store`. The driver-less queue accumulates indefinitely
    /// (no consumer), which is exactly what these tests want.
    fn cache_for_test() -> MediaImageCache {
        let state = Arc::new(RwLock::new(CacheState::new()));
        let queue: Arc<Mutex<VecDeque<MediaKey>>> = Arc::new(Mutex::new(VecDeque::new()));
        let queue_notify = Arc::new(Notify::new());
        let (updates_tx, _) = broadcast::channel::<MediaImageUpdate>(64);
        MediaImageCache {
            state,
            queue,
            queue_notify,
            updates_tx,
        }
    }

    #[test]
    fn ext_for_content_type_handles_known_mimes() {
        assert_eq!(ext_for_content_type("image/png"), Some("png"));
        assert_eq!(ext_for_content_type("image/PNG"), Some("png"));
        assert_eq!(ext_for_content_type("image/jpeg"), Some("jpg"));
        assert_eq!(ext_for_content_type("image/jpg"), Some("jpg"));
        assert_eq!(ext_for_content_type("image/webp"), Some("webp"));
    }

    #[test]
    fn ext_for_content_type_strips_charset_suffix() {
        assert_eq!(
            ext_for_content_type("image/png; charset=binary"),
            Some("png")
        );
    }

    #[test]
    fn ext_for_content_type_rejects_unsupported() {
        assert_eq!(ext_for_content_type("image/gif"), None);
        assert_eq!(ext_for_content_type("application/octet-stream"), None);
        assert_eq!(ext_for_content_type(""), None);
    }

    #[test]
    fn ext_from_extension_field_normalises_aliases() {
        assert_eq!(ext_from_extension_field("png"), Some("png"));
        assert_eq!(ext_from_extension_field("PNG"), Some("png"));
        assert_eq!(ext_from_extension_field(".png"), Some("png"));
        assert_eq!(ext_from_extension_field("jpg"), Some("jpg"));
        assert_eq!(ext_from_extension_field("jpeg"), Some("jpg"));
        assert_eq!(ext_from_extension_field("JPEG"), Some("jpg"));
        assert_eq!(ext_from_extension_field("webp"), Some("webp"));
    }

    #[test]
    fn ext_from_extension_field_rejects_unsupported() {
        assert_eq!(ext_from_extension_field("gif"), None);
        assert_eq!(ext_from_extension_field("bmp"), None);
        assert_eq!(ext_from_extension_field(""), None);
        assert_eq!(ext_from_extension_field("."), None);
    }

    #[test]
    fn media_key_round_trips_through_url_encoding() {
        // Path with slashes, punctuation, and unicode — all of which
        // would corrupt a naive `system|path` encoding without proper
        // base64.
        let key = MediaKey::new("SNES", "/roms/snes/Super Mario World (USA).sfc");
        let encoded = key.encode();
        // No padding, only URL-safe chars, no separators that would
        // confuse a single-segment URL path.
        assert!(!encoded.contains('='), "no padding: {encoded}");
        assert!(!encoded.contains('+'), "url-safe: {encoded}");
        assert!(!encoded.contains('/'), "url-safe: {encoded}");
        let decoded = MediaKey::decode(&encoded).expect("round-trip");
        assert_eq!(decoded, key);
    }

    #[test]
    fn media_key_handles_paths_with_separator_byte() {
        // Defence in depth: a path containing 0x1F should not corrupt
        // the split — base64 decodes the original bytes back exactly,
        // and we split on the *first* separator (the one we inserted).
        let path_with_us = format!("/x/{}/y", char::from(0x1F));
        let key = MediaKey::new("SNES", path_with_us.as_str());
        let decoded = MediaKey::decode(&key.encode()).expect("round-trip");
        assert_eq!(decoded.system_id.as_ref(), "SNES");
        assert_eq!(decoded.path.as_ref(), path_with_us.as_str());
    }

    #[test]
    fn image_key_for_returns_media_image_prefix() {
        let key = MediaKey::new("SNES", "/p");
        let s = MediaImageCache::image_key_for(&key);
        assert!(s.starts_with("media-image/"), "got {s}");
        let encoded = &s["media-image/".len()..];
        let back = MediaKey::decode(encoded).expect("decode");
        assert_eq!(back, key);
    }

    fn key(s: &str, p: &str) -> MediaKey {
        MediaKey::new(s, p)
    }

    #[test]
    fn finish_fetch_success_records_and_clears_pending() {
        let state = Arc::new(RwLock::new(CacheState::new()));
        let k = key("SNES", "/p");
        state.write().unwrap().pending.insert(k.clone());
        let update = finish_fetch(
            &state,
            usize::MAX,
            &k,
            FetchOutcome::Success {
                bytes: vec![1, 2, 3],
                ext: "png",
            },
        )
        .expect("Success returns Some(update)");
        assert_eq!(update.key, k);
        assert_eq!(update.ext, Some("png"));
        let guard = state.read().unwrap();
        assert!(guard.map.contains_key(&k));
        assert_eq!(guard.total_bytes, 3);
        assert!(!guard.pending.contains(&k));
        assert!(!guard.negative.contains(&k));
    }

    #[test]
    fn fetch_one_treats_empty_bytes_as_no_image() {
        // `fetch_one` short-circuits to `FetchOutcome::NoImage` when
        // base64 decoding yields zero bytes (defensive guard against a
        // future Core regression that lets empty payloads through).
        // We can't call `fetch_one` directly without a live Store, so
        // exercise the downstream contract: NoImage → negative memo,
        // no map entry, pending cleared. This locks in the behaviour
        // that empty payloads do not pollute the cache and the
        // `(system_id, path)` is suppressed from refetch.
        let state = Arc::new(RwLock::new(CacheState::new()));
        let k = key("SNES", "/empty");
        state.write().unwrap().pending.insert(k.clone());
        let update = finish_fetch(&state, usize::MAX, &k, FetchOutcome::NoImage)
            .expect("NoImage returns Some(update)");
        assert_eq!(update.key, k);
        assert!(update.ext.is_none());
        let guard = state.read().unwrap();
        assert!(
            !guard.map.contains_key(&k),
            "empty bytes must not enter the cache map"
        );
        assert_eq!(guard.total_bytes, 0);
        assert!(!guard.pending.contains(&k));
        assert!(
            guard.negative.contains(&k),
            "empty bytes must be absorbed by the negative memo so we do not refetch"
        );
    }

    #[test]
    fn finish_fetch_no_image_records_negative() {
        let state = Arc::new(RwLock::new(CacheState::new()));
        let k = key("SNES", "/p");
        state.write().unwrap().pending.insert(k.clone());
        let update = finish_fetch(&state, usize::MAX, &k, FetchOutcome::NoImage)
            .expect("NoImage returns Some(update)");
        assert_eq!(update.key, k);
        assert!(update.ext.is_none());
        let guard = state.read().unwrap();
        assert!(!guard.map.contains_key(&k));
        assert!(!guard.pending.contains(&k));
        assert!(guard.negative.contains(&k));
    }

    fn ok_png(state: &Arc<RwLock<CacheState>>, cap: usize, k: &MediaKey, n: usize) {
        let _ = finish_fetch(
            state,
            cap,
            k,
            FetchOutcome::Success {
                bytes: vec![0; n],
                ext: "png",
            },
        );
    }

    #[test]
    fn eviction_drops_oldest_when_over_cap() {
        let state = Arc::new(RwLock::new(CacheState::new()));
        // Cap fits exactly two 100-byte entries; a third must evict
        // the oldest.
        let cap = 200;
        let a = key("SNES", "/a");
        let b = key("SNES", "/b");
        let c = key("SNES", "/c");
        ok_png(&state, cap, &a, 100);
        ok_png(&state, cap, &b, 100);
        // Both fit so far.
        {
            let g = state.read().unwrap();
            assert_eq!(g.map.len(), 2);
            assert_eq!(g.total_bytes, 200);
        }
        ok_png(&state, cap, &c, 100);
        let g = state.read().unwrap();
        assert_eq!(g.map.len(), 2);
        assert_eq!(g.total_bytes, 200);
        // `a` was the oldest insert and has not been touched, so it
        // gets evicted ahead of `b` and `c`.
        assert!(!g.map.contains_key(&a), "a should be evicted");
        assert!(g.map.contains_key(&b));
        assert!(g.map.contains_key(&c));
    }

    #[test]
    fn eviction_respects_recent_get_bumps() {
        let state = Arc::new(RwLock::new(CacheState::new()));
        let cap = 200;
        let a = key("SNES", "/a");
        let b = key("SNES", "/b");
        let c = key("SNES", "/c");
        ok_png(&state, cap, &a, 100);
        ok_png(&state, cap, &b, 100);
        // Touch `a` so it becomes the most recent entry — `b` is
        // now the LRU and should be evicted next.
        {
            let mut g = state.write().unwrap();
            let next = g.next_clock();
            g.map.get_mut(&a).expect("a present").last_used = next;
        }
        ok_png(&state, cap, &c, 100);
        let g = state.read().unwrap();
        assert!(g.map.contains_key(&a), "a was touched, should survive");
        assert!(!g.map.contains_key(&b), "b was LRU, should be evicted");
        assert!(g.map.contains_key(&c));
    }

    #[test]
    fn negative_memo_caps_at_4096_with_fifo() {
        let mut memo = NegativeMemo::default();
        // Insert N+5 entries; the first 5 must be dropped FIFO.
        for i in 0..(NEGATIVE_MEMO_CAP + 5) {
            memo.insert(key("SNES", &format!("/p/{i}")));
        }
        assert_eq!(memo.set.len(), NEGATIVE_MEMO_CAP);
        assert_eq!(memo.order.len(), NEGATIVE_MEMO_CAP);
        // First 5 should have been popped.
        for i in 0..5 {
            assert!(
                !memo.contains(&key("SNES", &format!("/p/{i}"))),
                "entry {i} should have been evicted"
            );
        }
        // Last entry is still present.
        assert!(memo.contains(&key("SNES", &format!("/p/{}", NEGATIVE_MEMO_CAP + 4))));
    }

    #[test]
    fn negative_memo_dedupes_duplicate_inserts() {
        let mut memo = NegativeMemo::default();
        let k = key("SNES", "/p");
        memo.insert(k.clone());
        memo.insert(k.clone());
        memo.insert(k.clone());
        assert_eq!(memo.set.len(), 1);
        assert_eq!(memo.order.len(), 1);
    }

    #[test]
    fn eviction_prefers_read_entries_over_unread() {
        // Three unread entries fill the cap exactly. Mark the oldest
        // (`a`) as read; inserting `d` must evict `a` even though it is
        // the only entry QtQuick has consumed, because the unread
        // entries `b` and `c` are still waiting on their first paint
        // pass — dropping them would surface as
        // "Failed to get image from provider".
        let state = Arc::new(RwLock::new(CacheState::new()));
        let cap = 300;
        let a = key("SNES", "/a");
        let b = key("SNES", "/b");
        let c = key("SNES", "/c");
        let d = key("SNES", "/d");
        for k in [&a, &b, &c] {
            ok_png(&state, cap, k, 100);
        }
        // Mark `a` as read. Mirrors what `get_bytes` would do: bump
        // `last_used` and flip the read flag.
        {
            let mut state_w = state.write().unwrap();
            let next = state_w.next_clock();
            let entry = state_w.map.get_mut(&a).expect("a present");
            entry.last_used = next;
            entry.read = true;
        }
        ok_png(&state, cap, &d, 100);
        let state_r = state.read().unwrap();
        assert!(
            !state_r.map.contains_key(&a),
            "read entry a should be evicted"
        );
        assert!(state_r.map.contains_key(&b), "unread b should be pinned");
        assert!(state_r.map.contains_key(&c), "unread c should be pinned");
        assert!(state_r.map.contains_key(&d));
        assert_eq!(state_r.total_bytes, 300);
    }

    #[test]
    fn eviction_falls_back_to_unread_when_no_reads() {
        // No `get_bytes` calls means every entry stays unread. The
        // two-pass eviction must still make progress via the
        // unread-fallback path; otherwise total_bytes climbs unbounded.
        let state = Arc::new(RwLock::new(CacheState::new()));
        let cap = 200;
        let a = key("SNES", "/a");
        let b = key("SNES", "/b");
        let c = key("SNES", "/c");
        for k in [&a, &b, &c] {
            ok_png(&state, cap, k, 100);
        }
        let g = state.read().unwrap();
        assert_eq!(g.map.len(), 2, "fallback path must evict to fit cap");
        assert_eq!(g.total_bytes, 200);
        // `a` was inserted first and never read, so the fallback
        // (LRU by insert clock) drops it.
        assert!(!g.map.contains_key(&a));
        assert!(g.map.contains_key(&b));
        assert!(g.map.contains_key(&c));
    }

    #[test]
    fn oversize_payload_routes_to_negative_memo() {
        // Payloads larger than the entire cap can never fit; let
        // `finish_fetch` divert them to the negative memo instead of
        // inserting and then thrashing `evict_until_fits` trying to
        // make room. The tile renders fallback text and the
        // `(system_id, path)` is suppressed from refetch this session.
        let state = Arc::new(RwLock::new(CacheState::new()));
        let cap = 100;
        let k = key("SNES", "/huge");
        state.write().unwrap().pending.insert(k.clone());
        let update = finish_fetch(
            &state,
            cap,
            &k,
            FetchOutcome::Success {
                bytes: vec![0; cap + 1],
                ext: "png",
            },
        )
        .expect("oversize Success returns Some(update) with ext=None");
        assert_eq!(update.key, k);
        assert!(update.ext.is_none(), "oversize must report as no image");
        let g = state.read().unwrap();
        assert!(
            !g.map.contains_key(&k),
            "oversize must not enter the cache map"
        );
        assert_eq!(g.total_bytes, 0);
        assert!(!g.pending.contains(&k), "pending must be cleared");
        assert!(
            g.negative.contains(&k),
            "oversize must be absorbed by the negative memo"
        );
    }

    #[test]
    fn finish_fetch_transient_returns_none_and_clears_pending() {
        // Transient is the "may not repeat" outcome (socket flap, RPC
        // error, base64 corruption). The unit-level contract:
        // `finish_fetch` clears `pending`, does NOT memo, does NOT
        // insert, and returns None — the driver-level retry loop
        // re-inserts `pending` and re-enqueues from there.
        let state = Arc::new(RwLock::new(CacheState::new()));
        let k = key("SNES", "/p");
        state.write().unwrap().pending.insert(k.clone());
        let update = finish_fetch(&state, usize::MAX, &k, FetchOutcome::Transient);
        assert!(update.is_none(), "Transient must not broadcast");
        let g = state.read().unwrap();
        assert!(!g.map.contains_key(&k), "no insert on Transient");
        assert!(!g.negative.contains(&k), "no negative memo on Transient");
        assert!(!g.pending.contains(&k), "pending must be cleared");
        assert_eq!(g.total_bytes, 0);
    }

    #[test]
    fn lifo_drains_newest_first() {
        // The cache's queue is a `VecDeque`; the driver drains via
        // `pop_back`. Exercise that ordering directly: pushing A, B,
        // C must drain as C, B, A so the page the user just landed on
        // is serviced ahead of older enqueues.
        use std::collections::VecDeque;
        let mut q: VecDeque<MediaKey> = VecDeque::new();
        let a = key("SNES", "/a");
        let b = key("SNES", "/b");
        let c = key("SNES", "/c");
        q.push_back(a.clone());
        q.push_back(b.clone());
        q.push_back(c.clone());
        assert_eq!(q.pop_back(), Some(c));
        assert_eq!(q.pop_back(), Some(b));
        assert_eq!(q.pop_back(), Some(a));
        assert_eq!(q.pop_back(), None);
    }

    #[test]
    fn enqueue_drops_oldest_when_queue_full() {
        // Enqueueing more than MAX_QUEUE_LEN distinct keys must spill
        // the oldest entries off the front of the queue and release
        // them from `pending`, so they can be re-enqueued later when
        // the user navigates back to a page whose enqueues we
        // truncated. Locks in the queue-bound contract end-to-end:
        // queue length capped, pending matches the queue, dropped
        // keys are re-enqueueable.
        let cache = cache_for_test();
        // Push MAX_QUEUE_LEN + 5 distinct keys; the first 5 must be
        // the ones that get dropped.
        for i in 0..(MAX_QUEUE_LEN + 5) {
            cache.enqueue(key("SNES", &format!("/p/{i}")));
        }
        let queue_len = cache.queue.lock().unwrap().len();
        assert_eq!(
            queue_len, MAX_QUEUE_LEN,
            "queue must truncate to MAX_QUEUE_LEN"
        );
        let guard = cache.state.read().unwrap();
        assert_eq!(
            guard.pending.len(),
            MAX_QUEUE_LEN,
            "pending must mirror the queue (truncated keys released)"
        );
        for i in 0..5 {
            let stale = key("SNES", &format!("/p/{i}"));
            assert!(
                !guard.pending.contains(&stale),
                "oldest key /p/{i} should have been released from pending"
            );
        }
        for i in 5..(MAX_QUEUE_LEN + 5) {
            let live = key("SNES", &format!("/p/{i}"));
            assert!(
                guard.pending.contains(&live),
                "key /p/{i} should still be pending"
            );
        }
        drop(guard);
        // Re-enqueueing a previously-dropped key must succeed (it's
        // no longer in pending). Verify by checking the queue grows.
        let revived = key("SNES", "/p/0");
        cache.enqueue(revived.clone());
        let queue_len = cache.queue.lock().unwrap().len();
        // Pushing one extra back into a full queue truncates one
        // *other* old entry off the front, so length stays at cap.
        assert_eq!(queue_len, MAX_QUEUE_LEN);
        let guard = cache.state.read().unwrap();
        assert!(
            guard.pending.contains(&revived),
            "re-enqueued key must be pending again"
        );
    }

    #[test]
    fn is_cached_does_not_bump_lru() {
        // Contract: `is_cached` is a side-effect-free existence
        // query. It must NOT touch `last_used` or `read`, so that
        // role-data lookups (which call it on every QML rebind) do
        // not contaminate the LRU clock. Only `get_bytes` bumps the
        // clock, because only `get_bytes` corresponds to an actual
        // paint pass.
        let cache = cache_for_test();
        let k = key("SNES", "/p");
        ok_png(&cache.state, usize::MAX, &k, 100);
        let last_used_before = cache.state.read().unwrap().map[&k].last_used;
        for _ in 0..10 {
            assert!(cache.is_cached(&k));
        }
        let last_used_after = cache.state.read().unwrap().map[&k].last_used;
        assert_eq!(
            last_used_before, last_used_after,
            "is_cached must not bump last_used"
        );
        assert!(
            !cache.state.read().unwrap().map[&k].read,
            "is_cached must not flip read"
        );
        // get_bytes is the paint signal — it MUST bump.
        let _ = cache.get_bytes(&k);
        let last_used_after_get = cache.state.read().unwrap().map[&k].last_used;
        assert!(
            last_used_after_get > last_used_after,
            "get_bytes must bump last_used"
        );
        assert!(
            cache.state.read().unwrap().map[&k].read,
            "get_bytes must flip read"
        );
    }

    #[test]
    fn is_negative_reports_memo_membership() {
        // Locks in the contract that `is_negative` reflects the
        // negative memo without false positives — the miss-driven
        // re-enqueue path uses this to skip refetching keys Core
        // has definitively said have nothing to fetch.
        let cache = cache_for_test();
        let absent = key("SNES", "/never-fetched");
        let memoised = key("SNES", "/no-image");
        cache
            .state
            .write()
            .unwrap()
            .pending
            .insert(memoised.clone());
        let _ = finish_fetch(&cache.state, usize::MAX, &memoised, FetchOutcome::NoImage);
        assert!(
            cache.is_negative(&memoised),
            "NoImage outcome must populate the negative memo"
        );
        assert!(
            !cache.is_negative(&absent),
            "unrelated keys must not appear negative"
        );
    }
}
