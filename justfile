# Zaparoo Launcher dev commands.
# `just --list` for the full menu.

# Use sccache as the rustc wrapper when it's installed. sccache caches
# compiled crates across `target/` directories — biggest win when round-
# tripping between desktop and arm32 targets, but also speeds up CI and
# any clean build. Falls back to no wrapper if sccache isn't on PATH so
# contributors who haven't installed it still get working builds.
export RUSTC_WRAPPER := `command -v sccache || true`

default:
    @just --list

# --- build ---
build:
    cmake --preset desktop-debug
    cmake --build --preset desktop-debug

build-release:
    cmake --preset desktop-release
    cmake --build --preset desktop-release

# Release build with provenance markers baked in. Sets
# ZAPAROO_OFFICIAL_BUILD=1 so the launcher reports
# `channel = "official"` in About / License and the startup log,
# distinguishing distributed packages from local dev builds. Use this
# (not `build-release`) when producing binaries you intend to ship.
# Produces both shippable artifacts: desktop release in build-release/bin
# and the MiSTer ARM32 binary in output/launcher.
release:
    ZAPAROO_OFFICIAL_BUILD=1 cmake --preset desktop-release
    ZAPAROO_OFFICIAL_BUILD=1 cmake --build --preset desktop-release
    ZAPAROO_OFFICIAL_BUILD=1 ./scripts/build-arm32.sh

build-dev:
    cmake --preset desktop-dev
    cmake --build --preset desktop-dev

build-san:
    cmake --preset desktop-sanitized
    cmake --build --preset desktop-sanitized

arm32:
    ./scripts/build-arm32.sh

# --- run ---
run: build
    ./build/bin/launcher

run-dev: build-dev
    ZAPAROO_CORE_ENDPOINT=ws://127.0.0.1:27497/api/v0.1 ./build-dev/bin/launcher

# Run a local mock Zaparoo Core (ws://127.0.0.1:27497/api/v0.1).
# Deliberately offset from the real Core's 7497 so dev never collides
# with a running Core. `just run-dev` automatically points the launcher
# here via ZAPAROO_CORE_ENDPOINT. See docs/quickstart.md.
mock-core:
    cd rust && cargo run --bin mock-core

# --- test ---
test: build
    ctest --preset desktop-debug
    cd rust && cargo nextest run --workspace

test-qml: build
    ctest --preset desktop-debug -R ui

test-rust:
    cd rust && cargo nextest run --workspace

test-san: build-san
    ctest --preset desktop-sanitized

# --- lint ---
lint: lint-cpp lint-rust

lint-cpp: build
    cmake --build build --target lint

lint-qml: build
    cmake --build build --target all_qmllint

lint-rust:
    cd rust && cargo fmt --all --check
    cd rust && cargo clippy --workspace --all-targets -- -D warnings
    @if command -v cargo-deny >/dev/null 2>&1; then \
        cd rust && cargo deny check; \
    else \
        echo "warning: cargo-deny not installed; skipping (run 'just install-tools')"; \
    fi

# --- format / autofix (auto-apply) ---
# Tools are invoked directly so contributors only need the formatters they
# actually touch (no Python orchestrator). `xargs -r` skips the invocation
# when the list is empty (GNU and macOS 10.15+ xargs).
fmt:
    cd rust && cargo fmt --all
    git ls-files '*.cpp' '*.h' '*.hpp' '*.cc' | xargs -r clang-format -i
    git ls-files '*.qml' | xargs -r qmlformat --inplace
    git ls-files 'CMakeLists.txt' '*.cmake' | xargs -r cmake-format -i

# Autofix everything CI would reject. clippy --fix runs first because its
# rewrites may not be pre-formatted; fmt is the cleanup pass.
fix:
    cd rust && cargo clippy --fix --workspace --all-targets --allow-dirty --allow-staged
    just fmt

# Install the optional cargo extensions referenced by lint/test recipes.
install-tools:
    cargo install --locked cargo-nextest cargo-deny

# --- docker lint/fmt ---
# `lint/VERSION` is the source of truth for the published image tag.
# CI publishes ghcr.io/zaparooproject/zaparoo-lint:<version> when that
# file or `Dockerfile.lint` changes. These recipes pull and run it so
# contributors do not need rustfmt, clippy, cargo-deny, clang-format,
# clang-tidy, qmlformat, qmllint, cmake-format, or Qt on the host.
_LINT_IMAGE := "ghcr.io/zaparooproject/zaparoo-lint:" + trim(`cat lint/VERSION`)

_docker-lint *cmd:
    docker run --rm \
        -v "$PWD":/workdir \
        -u "$(id -u):$(id -g)" \
        {{_LINT_IMAGE}} \
        {{cmd}}

# Container-internal: configure + build using the desktop-docker-debug
# preset so artifacts go to build-docker/ instead of stomping build/.
# Underscore-prefixed recipes are private (hidden from `just --list`).
_build-docker:
    cmake --preset desktop-docker-debug
    cmake --build --preset desktop-docker-debug

# Container-internal: cmake `lint` target (clang-format dry-run +
# clang-tidy + all_qmllint). Mirrors `just lint-cpp` semantics for the
# host but runs against build-docker/.
_lint-cmake: _build-docker
    cmake --build build-docker --target lint

# Container-internal: only the qmllint subset.
_lint-qmllint: _build-docker
    cmake --build build-docker --target all_qmllint

# Container-internal aggregate: rust + cpp + qml lints. Mirrors host
# `just lint`.
_lint-all: lint-rust _lint-cmake

fmt-docker:
    just _docker-lint just fmt

# Full lint surface (rust + cpp + qml) inside the container.
lint-docker:
    just _docker-lint just _lint-all

# Just the cmake `lint` target inside the container (format-check +
# clang-tidy + all_qmllint).
lint-cpp-docker:
    just _docker-lint just _lint-cmake

# Just the qmllint subset inside the container.
lint-qml-docker:
    just _docker-lint just _lint-qmllint

fix-docker:
    just _docker-lint just fix

# --- deploy ---
deploy-mister:
    ./scripts/deploy-mister.sh

# --- clean ---
clean:
    rm -rf build build-release build-dev build-san build-docker output
    cd rust && cargo clean
