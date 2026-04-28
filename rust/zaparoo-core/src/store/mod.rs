// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Store` is the root of the data layer. It owns the `Client` and
// runtime, hands out shared `RemoteResource`s keyed by (endpoint, args),
// and routes mutations through to the same client. In RTK-Query terms
// this is the `api` slice's reducer + dispatcher. One `Store` per
// launcher process; QML singletons subscribe through it.
//
// Responsibilities: cache `(endpoint NAME, args hash) → RemoteResource`,
// hand back shared subscriptions, route mutations through to the same
// `Client`, and refetch every cache entry whose `provides` set
// intersects a successful mutation's `invalidates` list.

mod endpoint;
mod mutation;
mod tag;

pub use endpoint::Endpoint;
pub use mutation::Mutation;
pub use tag::Tag;

use crate::client::{Client, ClientError, Notification};
use crate::remote_resource::{RemoteResource, ResourceStatus};
use std::any::Any;
use std::collections::HashMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;
use tokio::sync::broadcast;

/// Cache lookup key for `Store::subscribe`. Combines the endpoint's
/// `NAME` with a hash of its `Args`. Endpoints are expected to choose
/// unique names, so cross-endpoint collisions are a programmer error;
/// within an endpoint a 64-bit `Args` hash collision is astronomically
/// unlikely for the cardinalities this launcher sees (one catalog,
/// tens of system ids).
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
struct CacheKey {
    name: &'static str,
    args_hash: u64,
}

impl CacheKey {
    fn new<E: Endpoint>(args: &E::Args) -> Self {
        let mut hasher = DefaultHasher::new();
        args.hash(&mut hasher);
        Self {
            name: E::NAME,
            args_hash: hasher.finish(),
        }
    }
}

/// Type-erased per-entry record. `resource` is an
/// `Arc<RemoteResource<E::Output>>` for the endpoint that owns the slot;
/// the `(NAME, args)` pair uniquely determines the concrete `Output`,
/// so the downcast on subscribe is infallible in practice. `provides`
/// is updated by a per-entry watcher each time the resource transitions
/// to `Ready`. `refetch` is a type-erased clone of
/// `RemoteResource::refetch` so the store can pulse invalidations
/// without naming `E::Output`.
struct CacheEntry {
    resource: Arc<dyn Any + Send + Sync>,
    provides: Vec<Tag>,
    refetch: Arc<dyn Fn() + Send + Sync>,
}

#[derive(Default)]
struct Inner {
    cache: HashMap<CacheKey, CacheEntry>,
}

pub struct Store {
    client: Arc<Client>,
    runtime: Arc<Runtime>,
    inner: Arc<Mutex<Inner>>,
}

impl std::fmt::Debug for Store {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Store").finish_non_exhaustive()
    }
}

impl Store {
    pub fn new(client: Arc<Client>, runtime: Arc<Runtime>) -> Arc<Self> {
        Arc::new(Self {
            client,
            runtime,
            inner: Arc::new(Mutex::new(Inner::default())),
        })
    }

    pub fn subscribe_notifications(&self) -> broadcast::Receiver<Notification> {
        self.client.subscribe_notifications()
    }

    /// Get (or create) the shared `RemoteResource` for endpoint `E`
    /// with `args`. Subsequent calls with equal args return the same
    /// `Arc`, so multiple QML singletons binding the same endpoint
    /// share one fetch task and one publish channel.
    #[allow(
        clippy::unwrap_used,
        reason = "mutex poisoning signals another thread panicked with the lock held; state is unrecoverable"
    )]
    pub fn subscribe<E: Endpoint>(&self, args: E::Args) -> Arc<RemoteResource<E::Output>> {
        let key = CacheKey::new::<E>(&args);
        let mut inner = self.inner.lock().unwrap();
        if let Some(existing) = inner.cache.get(&key) {
            if let Ok(resource) = existing
                .resource
                .clone()
                .downcast::<RemoteResource<E::Output>>()
            {
                return resource;
            }
            // Same NAME but a different `Output` type — programmer
            // error (two endpoints sharing a NAME). Fall through and
            // overwrite so behavior is deterministic, but surface
            // the misuse loudly in dev and at least log it in release
            // so it doesn't go unnoticed.
            tracing::error!(
                name = E::NAME,
                "endpoint NAME collision: cache entry has a different Output type; \
                 the prior entry is being orphaned"
            );
            debug_assert!(
                false,
                "endpoint NAME collision: two endpoints share NAME = {:?} but disagree on Output",
                E::NAME
            );
        }
        // Cache entries live for the lifetime of the `Store` (which is
        // the lifetime of the launcher process). No reclamation path:
        // total cardinality is bounded by `endpoints × distinct args` —
        // a handful of endpoints times a few dozen system IDs in the
        // worst case — and each entry holds one `tokio::sync::watch`
        // plus one watcher task, both cheap. The `Client` and `Runtime`
        // outlive every entry by construction. Add eviction (most
        // likely `Arc::strong_count`-driven on the per-entry watcher's
        // drop branch) only if RAM growth shows up in the field.
        let runtime = self.runtime.clone();
        let args_for_fetch = args.clone();
        let resource = Arc::new(RemoteResource::driven_by(
            self.client.clone(),
            &runtime,
            move |c| E::fetch(c, args_for_fetch.clone()),
        ));
        let resource_for_refetch = resource.clone();
        let refetch: Arc<dyn Fn() + Send + Sync> = Arc::new(move || resource_for_refetch.refetch());
        let entry = CacheEntry {
            resource: resource.clone(),
            // `provides` starts empty; the per-entry watcher below
            // populates it on the first `Ready`. A mutation that fires
            // before the resource has produced a value can't have
            // anything meaningful to invalidate yet — refetching an
            // entry that hasn't fetched once is a no-op for callers.
            provides: Vec::new(),
            refetch,
        };
        inner.cache.insert(key.clone(), entry);
        drop(inner);

        // Spawn a per-entry watcher that keeps `provides` in sync with
        // the resource's last `Ready` value. Held weakly so the
        // watcher exits as soon as the store is dropped (process
        // teardown), without forming a cycle that would keep `Inner`
        // alive forever.
        //
        // `tokio::sync::watch` is intentionally lossy — a rapid
        // `Ready → Loading → Ready` collapses into one wake-up that
        // observes the later state — so the watcher is *not*
        // guaranteed to see every `Ready` transition. This is fine
        // because (a) `Ready` is sticky, so subsequent fetches
        // re-emit `Ready` and the watcher catches up, and (b) every
        // current `Endpoint::provides` is output-independent. See
        // the doc comment on `Endpoint::provides` for the constraint
        // future endpoints must respect.
        let inner_weak = Arc::downgrade(&self.inner);
        let mut status_rx = resource.subscribe();
        let key_for_watcher = key;
        runtime.spawn(async move {
            loop {
                let snapshot = status_rx.borrow_and_update().clone();
                if let ResourceStatus::Ready(output) = snapshot {
                    let new_provides = E::provides(&args, &output);
                    let Some(inner_arc) = inner_weak.upgrade() else {
                        return;
                    };
                    let lock_result = inner_arc.lock();
                    if let Ok(mut inner) = lock_result {
                        if let Some(entry) = inner.cache.get_mut(&key_for_watcher) {
                            entry.provides = new_provides;
                        }
                    }
                }
                if status_rx.changed().await.is_err() {
                    return;
                }
            }
        });

        resource
    }

    /// Invoke a mutation. On success, every cache entry whose
    /// `provides` set matches any of `M::invalidates(args, result)` is
    /// refetched in place — the underlying `RemoteResource` keeps the
    /// same `Arc`, so existing subscribers see the new value through
    /// their existing watch channel without re-binding.
    pub async fn run_mutation<M: Mutation>(&self, args: M::Args) -> Result<M::Output, ClientError> {
        let args_for_invalidate = args.clone();
        let result = M::run(self.client.clone(), args).await?;
        for tag in M::invalidates(&args_for_invalidate, &result) {
            self.invalidate(&tag);
        }
        Ok(result)
    }

    /// Invalidate every cache entry whose `provides` set matches `tag`.
    /// Matching is RTK-Query-shaped: kinds must agree, and a `None` id
    /// (the "any" tag) on either side matches any id on the other.
    #[allow(
        clippy::unwrap_used,
        reason = "mutex poisoning signals another thread panicked with the lock held; state is unrecoverable"
    )]
    pub fn invalidate(&self, tag: &Tag) {
        let inner = self.inner.lock().unwrap();
        let to_refetch: Vec<Arc<dyn Fn() + Send + Sync>> = inner
            .cache
            .values()
            .filter(|entry| entry.provides.iter().any(|p| tags_match(p, tag)))
            .map(|entry| entry.refetch.clone())
            .collect();
        drop(inner);
        for refetch in to_refetch {
            refetch();
        }
    }
}

/// RTK-Query tag matching. Two tags match iff their kinds agree and at
/// least one side has a `None` id (the "any" wildcard) or both sides
/// share the same specific id. Used for both directions:
/// `provided.matches(invalidating)` and the reverse have the same
/// truth table, so we don't need to track which is which here.
fn tags_match(a: &Tag, b: &Tag) -> bool {
    if a.kind != b.kind {
        return false;
    }
    match (&a.id, &b.id) {
        (None, _) | (_, None) => true,
        (Some(left), Some(right)) => left == right,
    }
}

#[cfg(test)]
#[allow(clippy::expect_used, reason = "tests should fail-fast on setup errors")]
mod tests {
    use super::*;
    use futures_util::future::BoxFuture;

    /// Endpoint stand-in that doesn't touch the `Client`. Used by the
    /// cache-key and subscribe tests below where end-to-end fetch
    /// behavior is out of scope; real endpoints have their own
    /// integration tests.
    struct DummyEndpoint;
    impl Endpoint for DummyEndpoint {
        type Args = String;
        type Output = i32;
        const NAME: &'static str = "Dummy";

        fn fetch(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(0) })
        }
    }

    struct OtherEndpoint;
    impl Endpoint for OtherEndpoint {
        type Args = String;
        type Output = i32;
        const NAME: &'static str = "Other";

        fn fetch(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(0) })
        }
    }

    struct UnitEndpoint;
    impl Endpoint for UnitEndpoint {
        type Args = ();
        type Output = i32;
        const NAME: &'static str = "Unit";

        fn fetch(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(0) })
        }
    }

    #[test]
    fn cache_key_equal_for_equal_args() {
        let a = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let b = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        assert_eq!(a, b);
    }

    #[test]
    fn cache_key_differs_for_different_args() {
        let a = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let b = CacheKey::new::<DummyEndpoint>(&"beta".to_string());
        assert_ne!(a, b);
    }

    #[test]
    fn cache_key_differs_for_different_endpoint_names() {
        let a = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let b = CacheKey::new::<OtherEndpoint>(&"alpha".to_string());
        // Same args produce the same hash — the NAME is the
        // distinguishing field.
        assert_eq!(a.args_hash, b.args_hash);
        assert_ne!(a, b);
    }

    #[test]
    fn unit_args_collapse_to_a_single_key() {
        let a = CacheKey::new::<UnitEndpoint>(&());
        let b = CacheKey::new::<UnitEndpoint>(&());
        assert_eq!(a, b);
    }

    fn test_store() -> Arc<Store> {
        let runtime = Arc::new(
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("build runtime"),
        );
        // The Client spawns a reconnect task against this endpoint; the
        // test never lets the task connect, so the URL just needs to
        // parse. `subscribe` itself doesn't await anything network-y.
        let client = Client::new("ws://127.0.0.1:1/never".to_string(), &runtime);
        Store::new(client, runtime)
    }

    #[test]
    fn subscribe_with_equal_args_returns_same_arc() {
        let store = test_store();
        let a = store.subscribe::<DummyEndpoint>("alpha".to_string());
        let b = store.subscribe::<DummyEndpoint>("alpha".to_string());
        // Pointer equality — the cache must hand back the same
        // resource Arc, not a fresh `RemoteResource` per call.
        assert!(Arc::ptr_eq(&a, &b));
    }

    #[test]
    fn subscribe_with_different_args_returns_different_arcs() {
        let store = test_store();
        let a = store.subscribe::<DummyEndpoint>("alpha".to_string());
        let b = store.subscribe::<DummyEndpoint>("beta".to_string());
        assert!(!Arc::ptr_eq(&a, &b));

        // Each args value should occupy its own cache slot — two
        // entries with the expected keys means the cache really did
        // distinguish them, not just hand back fresh Arcs from one
        // shared slot.
        let cache = &store.inner.lock().expect("lock store inner").cache;
        assert_eq!(cache.len(), 2);
        let key_a = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let key_b = CacheKey::new::<DummyEndpoint>(&"beta".to_string());
        assert!(cache.contains_key(&key_a));
        assert!(cache.contains_key(&key_b));

        // Independent watch channels: each resource has its own
        // status sender, so subscribing to one yields a receiver
        // that is not aliased to the other's sender. Both seed to
        // Idle (the connection is never established by the test
        // client).
        let mut rx_a = a.subscribe();
        let mut rx_b = b.subscribe();
        assert!(matches!(*rx_a.borrow_and_update(), ResourceStatus::Idle));
        assert!(matches!(*rx_b.borrow_and_update(), ResourceStatus::Idle));
    }

    // RTK-Query tag matching parity. See `tags_match` in this module.

    #[test]
    fn any_matches_any_of_same_kind() {
        assert!(tags_match(&Tag::any("X"), &Tag::any("X")));
    }

    #[test]
    fn any_matches_specific_of_same_kind() {
        // A mutation invalidating Tag::any("X") refetches both entries
        // tagged Tag::any("X") and Tag::specific("X", id) — the broad
        // tag invalidates everything in the namespace.
        assert!(tags_match(&Tag::any("X"), &Tag::specific("X", "a")));
        assert!(tags_match(&Tag::specific("X", "a"), &Tag::any("X")));
    }

    #[test]
    fn specific_matches_specific_only_for_same_id() {
        assert!(tags_match(
            &Tag::specific("X", "a"),
            &Tag::specific("X", "a"),
        ));
        assert!(!tags_match(
            &Tag::specific("X", "a"),
            &Tag::specific("X", "b"),
        ));
    }

    #[test]
    fn cross_kind_never_matches() {
        assert!(!tags_match(&Tag::any("X"), &Tag::any("Y")));
        assert!(!tags_match(
            &Tag::specific("X", "a"),
            &Tag::specific("Y", "a"),
        ));
        assert!(!tags_match(&Tag::any("X"), &Tag::specific("Y", "a")));
    }

    // run_mutation / invalidate end-to-end behavior. These bypass
    // `Store::subscribe`'s connection-driven resource lifecycle by
    // populating cache entries directly, so the tests stay deterministic
    // regardless of the `Client`'s reconnect task.

    use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};

    fn install_entry_with_provides(
        store: &Arc<Store>,
        key: CacheKey,
        provides: Vec<Tag>,
    ) -> Arc<AtomicUsize> {
        let counter = Arc::new(AtomicUsize::new(0));
        let counter_for_closure = counter.clone();
        let refetch: Arc<dyn Fn() + Send + Sync> = Arc::new(move || {
            counter_for_closure.fetch_add(1, AtomicOrdering::SeqCst);
        });
        let dummy_resource: Arc<dyn Any + Send + Sync> = Arc::new(());
        let entry = CacheEntry {
            resource: dummy_resource,
            provides,
            refetch,
        };
        store
            .inner
            .lock()
            .expect("lock store inner")
            .cache
            .insert(key, entry);
        counter
    }

    /// Mutation whose `invalidates` matches `Tag::any("Dummy")` — used to
    /// drive the refetch path under test.
    struct InvalidatingMutation;
    impl Mutation for InvalidatingMutation {
        type Args = ();
        type Output = ();
        fn run(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(()) })
        }
        fn invalidates(_args: &Self::Args, _result: &Self::Output) -> Vec<Tag> {
            vec![Tag::any("Dummy")]
        }
    }

    /// Mutation with no invalidates — the no-op default. Confirms that
    /// `run_mutation` does not refetch entries when nothing is asked.
    struct InertMutation;
    impl Mutation for InertMutation {
        type Args = ();
        type Output = ();
        fn run(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(()) })
        }
    }

    /// Mutation whose `invalidates` targets one specific id rather than
    /// the whole kind. Used to drive the discriminating-match path.
    struct SpecificInvalidatingMutation;
    impl Mutation for SpecificInvalidatingMutation {
        type Args = ();
        type Output = ();
        fn run(
            _client: Arc<Client>,
            _args: Self::Args,
        ) -> BoxFuture<'static, Result<Self::Output, ClientError>> {
            Box::pin(async { Ok(()) })
        }
        fn invalidates(_args: &Self::Args, _result: &Self::Output) -> Vec<Tag> {
            vec![Tag::specific("Dummy", "id1")]
        }
    }

    #[test]
    fn run_mutation_refetches_entry_with_matching_provides() {
        let store = test_store();
        let key = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let counter = install_entry_with_provides(&store, key, vec![Tag::any("Dummy")]);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<InvalidatingMutation>(())
                .await
                .expect("mutation runs");
        });

        assert_eq!(counter.load(AtomicOrdering::SeqCst), 1);
    }

    #[test]
    fn run_mutation_skips_entry_with_unrelated_provides() {
        let store = test_store();
        let key = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        // Provides a tag from a different kind — `InvalidatingMutation`
        // invalidates `Tag::any("Dummy")` so this entry must not match.
        let counter = install_entry_with_provides(&store, key, vec![Tag::any("Other")]);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<InvalidatingMutation>(())
                .await
                .expect("mutation runs");
        });

        assert_eq!(counter.load(AtomicOrdering::SeqCst), 0);
    }

    #[test]
    fn run_mutation_succeeds_when_provides_not_yet_populated() {
        let store = test_store();
        let key = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        // Empty provides simulates a cache entry whose resource has not
        // yet emitted `Ready`. The mutation still runs, and the entry
        // is correctly skipped because no provides match.
        let counter = install_entry_with_provides(&store, key, Vec::new());

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<InvalidatingMutation>(())
                .await
                .expect("mutation runs");
        });

        assert_eq!(counter.load(AtomicOrdering::SeqCst), 0);
    }

    #[test]
    fn run_mutation_refetches_every_matching_entry_at_once() {
        // Per-entry matching is unit-tested above; this asserts the
        // dispatch loop in `Store::invalidate` invokes *every* matching
        // entry's `refetch` closure (across endpoints) for a single
        // mutation, and leaves non-matching entries alone. The closure
        // is the test fixture's counter bump, not the real
        // `RemoteResource::refetch` notify pulse — covered separately.
        let store = test_store();

        let key_match_any = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let key_match_specific = CacheKey::new::<OtherEndpoint>(&"alpha".to_string());
        let key_unrelated = CacheKey::new::<DummyEndpoint>(&"beta".to_string());

        let counter_match_any =
            install_entry_with_provides(&store, key_match_any, vec![Tag::any("Dummy")]);
        let counter_match_specific = install_entry_with_provides(
            &store,
            key_match_specific,
            vec![Tag::specific("Dummy", "id1")],
        );
        let counter_unrelated =
            install_entry_with_provides(&store, key_unrelated, vec![Tag::any("Other")]);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<InvalidatingMutation>(())
                .await
                .expect("mutation runs");
        });

        // `InvalidatingMutation::invalidates` returns `Tag::any("Dummy")`,
        // which matches both `Tag::any("Dummy")` and
        // `Tag::specific("Dummy", _)` via the wildcard rule in
        // `tags_match`.
        assert_eq!(counter_match_any.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(counter_match_specific.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(counter_unrelated.load(AtomicOrdering::SeqCst), 0);
    }

    #[test]
    fn specific_mutation_refetches_only_same_id_and_any_of_kind() {
        // Companion to `run_mutation_refetches_every_matching_entry_at_once`:
        // exercises the discriminating-match side of `tags_match` through
        // the dispatch loop. A `Tag::specific("Dummy","id1")` mutation
        // should hit the same-id entry and any `Tag::any("Dummy")` entry,
        // but skip a sibling `Tag::specific("Dummy","id2")` entry.
        let store = test_store();

        let key_same_id = CacheKey::new::<DummyEndpoint>(&"id1".to_string());
        let key_other_id = CacheKey::new::<DummyEndpoint>(&"id2".to_string());
        let key_any_of_kind = CacheKey::new::<OtherEndpoint>(&"alpha".to_string());

        let counter_same_id =
            install_entry_with_provides(&store, key_same_id, vec![Tag::specific("Dummy", "id1")]);
        let counter_other_id =
            install_entry_with_provides(&store, key_other_id, vec![Tag::specific("Dummy", "id2")]);
        let counter_any_of_kind =
            install_entry_with_provides(&store, key_any_of_kind, vec![Tag::any("Dummy")]);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<SpecificInvalidatingMutation>(())
                .await
                .expect("mutation runs");
        });

        assert_eq!(counter_same_id.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(counter_any_of_kind.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(counter_other_id.load(AtomicOrdering::SeqCst), 0);
    }

    #[test]
    fn run_mutation_with_no_invalidates_never_refetches() {
        let store = test_store();
        let key = CacheKey::new::<DummyEndpoint>(&"alpha".to_string());
        let counter = install_entry_with_provides(&store, key, vec![Tag::any("Dummy")]);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("build runtime");
        runtime.block_on(async {
            store
                .run_mutation::<InertMutation>(())
                .await
                .expect("mutation runs");
        });

        assert_eq!(counter.load(AtomicOrdering::SeqCst), 0);
    }
}
