# Zaparoo Launcher dev commands.
# `just --list` for the full menu.

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
