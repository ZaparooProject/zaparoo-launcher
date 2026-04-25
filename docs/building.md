# Building

Day-to-day builds, lints, and tests are wrapped in
[`justfile`](../justfile). `just --list` shows the full menu.
`CMakePresets.json` and `rust/.cargo/config.toml` are tuned to the
recipes; if you find yourself reaching for raw `cmake` or `cargo`,
something is probably off.

## Requirements

### Desktop

- Qt 6.7+ (Quick, QuickControls2, Qml, LinguistTools)
- CMake 3.22+
- C++17 compiler (GCC 10+, Clang 12+, MSVC 2019+)
- Rust stable toolchain (`rustup install stable`)
- Ninja (required; pinned by `CMakePresets.json`)
- mold (used as linker on x86_64 Linux; pinned by `rust/.cargo/config.toml`)
- `just`, `cargo-nextest`, `cargo-deny`

Fedora / RHEL:
```bash
sudo dnf install qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel \
    qt6-qttools-devel cmake ninja-build mold clang-tools-extra just
```

Ubuntu / Debian:
```bash
sudo apt install qt6-declarative-dev qt6-quick-controls2-dev \
    qt6-tools-dev qt6-l10n-tools cmake ninja-build mold \
    clang-tidy clang-format just
```

Install Rust via rustup, then the cargo extensions:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install --locked cargo-nextest cargo-deny
```

If `just` isn't packaged for your distro, install it the same way:
`cargo install --locked just`.

### MiSTer ARM32 cross-build

- Docker (any recent version)
- x86_64 host (no emulation needed; pure cross-compilation)
- ~8 GB disk space for the toolchain image

The toolchain Docker image ships a cross-compiler-aware
`rust/.cargo/config.toml` that sets the linker
(`arm-linux-gnueabihf-gcc`), target
(`armv7-unknown-linux-gnueabihf`), and `mold` on desktop for faster
links. No manual cargo config is needed.

## Desktop builds

```bash
just build           # debug build (default)
just build-release   # release build
just build-dev       # dev preset (relwithdebinfo + extra checks)
just build-san       # ASan + UBSan
just run             # build then ./build/bin/launcher
```

The first build pulls and compiles Rust + Qt dependencies. Incremental
builds after that are fast.

To skip tests for faster iteration, configure with
`-DZAPAROO_BUILD_TESTS=OFF`:

```bash
cmake --preset desktop-debug -DZAPAROO_BUILD_TESTS=OFF
cmake --build --preset desktop-debug
```

## MiSTer ARM32 cross-build

First time (builds Qt 6.7.2 from source, ~45 min):

```bash
./scripts/build-toolchain.sh
```

This creates the `zaparoo/qt6-arm32-mister:6.7.2` Docker image
locally.

Subsequent builds (under a minute):

```bash
just arm32           # output/launcher
```

If the toolchain image is missing, `build-arm32.sh` rebuilds it
automatically.

Verify the ARM binary:

```bash
file output/launcher
# Should report: ELF 32-bit LSB executable, ARM, EABI5 ...
```

## Tests

```bash
just test            # ctest + cargo nextest
just test-qml        # only the Qt/QML tests
just test-rust       # only cargo nextest
just test-san        # ASan/UBSan suite
```

## Lints

```bash
just lint            # everything
just lint-cpp        # clang-format check + clang-tidy
just lint-qml        # qmllint
just lint-rust       # rustfmt check + clippy + cargo-deny
just fmt             # auto-apply: pre-commit + cargo fmt
```

`just lint` is the zero-warnings gate before opening a PR.
`compile_commands.json` is generated unconditionally in `build/`, so
clang-tidy and qmllint always have what they need.

## Deploy desktop bundle

```bash
just build
./packaging/deploy-desktop.sh
./deploy/launcher/run.sh
```

The deploy script bundles Qt shared libraries alongside the binary.
Qt must be on your PATH (`qmake6` or `qmake` must be findable).

## Deploy to MiSTer

```bash
just deploy-mister
```

The binary is self-contained on MiSTer: it sets
`QT_QPA_PLATFORM=linuxfb` and `QT_QUICK_BACKEND=software`, runs `vmode
-r W H rgb32` (width and height from config, defaulting to
1920×1080), and starts `/media/fat/Scripts/zaparoo.sh -service start`
automatically. No wrapper script required.

User-editable config lives at `/media/fat/zaparoo/launcher.toml`.
Example:

```toml
[video]
width = 1280
height = 720

[logging]
debug = true
```

## Run on framebuffer (desktop headless)

Useful for reproducing MiSTer rendering paths on a desktop:

```bash
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/launcher
```

## Underlying mechanics

Reach for these only when debugging the build itself or running
something not in the justfile.

`just build` resolves to:

```bash
cmake --preset desktop-debug
cmake --build --preset desktop-debug
```

`just lint-cpp` resolves to `cmake --build build --target lint`,
which runs clang-format (check only), clang-tidy, and qmllint in one
shot. Individual targets:

```bash
cmake --build build --target format-check   # clang-format dry-run
cmake --build build --target tidy           # clang-tidy
cmake --build build --target all_qmllint    # QML linting
```

`just test` resolves to `ctest --preset desktop-debug` plus
`cargo nextest run --workspace` (run from inside `rust/` because
nextest needs a workspace path; that's what the justfile does for
you). Plain ctest works too:

```bash
ctest --test-dir build --output-on-failure
```
