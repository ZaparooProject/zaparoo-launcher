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
    ./build-dev/bin/launcher

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
    cd rust && cargo deny check

# --- format (auto-apply) ---
fmt:
    pre-commit run --all-files
    cd rust && cargo fmt --all

# --- deploy ---
deploy-mister:
    ./scripts/deploy-mister.sh

# --- clean ---
clean:
    rm -rf build build-release build-dev build-san output
    cd rust && cargo clean
