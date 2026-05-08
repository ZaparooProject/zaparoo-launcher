# Building

Day-to-day builds, lints, and tests go through the
[`justfile`](../justfile). `just --list` shows the full menu.
`CMakePresets.json` and `rust/.cargo/config.toml` are written for those
recipes. If you need raw `cmake` or `cargo`, double-check that the justfile does
not already cover the job.

## Requirements

### Desktop

- Qt 6.7+ (Quick, QuickControls2, Qml, LinguistTools)
- CMake 3.22+
- C++17 compiler (GCC 10+, Clang 12+, MSVC 2019+)
- Rust stable toolchain (`rustup install stable`)
- Ninja (required; pinned by `CMakePresets.json`)
- mold (used as linker on x86_64 Linux; pinned by `rust/.cargo/config.toml`)
- `just`

Optional, but used by the lint and test recipes — install once after
cloning with `just install-tools`:

- `cargo-nextest` (test runner used by `just test` / `just test-rust`)
- `cargo-deny` (license/advisory check used by `just lint-rust`; the
  recipe skips it with a warning when not installed)
- Tooling for the Docker-based lint path is fetched at runtime when you
  use `just fmt-docker` / `just lint-docker` / `just fix-docker`

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

Install Rust via rustup, then run `just install-tools` after cloning the
launcher to install the optional cargo extensions:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# After cloning the launcher repo:
just install-tools
```

If `just` isn't packaged for your distro, install it the same way:
`cargo install --locked just`.

### MiSTer ARM32 cross-build

- Docker with Buildx (Docker Desktop includes it)
- x86_64 Linux Docker platform (`linux/amd64`)
- ~8 GB disk space for the toolchain image

The toolchain Docker image provides the ARM build environment. Cargo still gets
its target and linker settings from `rust/.cargo/config.toml`; the desktop
`mold` linker setting lives there too. You should not need to edit Cargo config
by hand.

macOS users only need Docker Desktop for the ARM32 path. The build scripts
default to Docker platform `linux/amd64`, including on Apple Silicon Macs,
because the MiSTer ARM GCC toolchain is the official x86_64 Linux release from
Arm. Apple Silicon hosts therefore build through Docker's amd64 emulation while
the project itself is still pure ARM32 cross-compilation inside the container.

## Desktop builds

```bash
just build           # debug build (default)
just build-release   # release build
just build-dev       # dev preset (relwithdebinfo + extra checks)
just build-san       # ASan + UBSan
just run             # build then ./build/bin/launcher
```

The first build pulls and compiles the Rust and Qt dependencies. Incremental
builds are much faster after that.

For a faster local build without tests, configure with
`-DZAPAROO_BUILD_TESTS=OFF`:

```bash
cmake --preset desktop-debug -DZAPAROO_BUILD_TESTS=OFF
cmake --build --preset desktop-debug
```

## MiSTer ARM32 cross-build

The default path uses the official prebuilt toolchain image published by this
repository:

```bash
./scripts/build-arm32.sh
```

This pulls
`ghcr.io/zaparooproject/qt6-arm32-mister:<toolchain/VERSION>` if it is not
already cached locally, builds the application in Docker, and writes the MiSTer
binary to `output/launcher`. It does not require `just`, Qt, CMake, Rust, or
the ARM toolchain on the host.

If GHCR asks for authentication, authorize the GitHub CLI with package-read
scope and log Docker in:

```bash
gh auth refresh -h github.com -s read:packages
gh auth token | docker login ghcr.io -u <github-user> --password-stdin
```

If you need to rebuild the toolchain image locally, building Qt from source
takes about 45 minutes:

```bash
./scripts/build-toolchain.sh
```

This creates the local `zaparoo/qt6-arm32-mister:<version>` Docker image. The
tag comes from `toolchain/VERSION`.

Use that local toolchain image for the application build with:

```bash
USE_LOCAL_TOOLCHAIN=1 ./scripts/build-arm32.sh
```

Later builds usually take under a minute because Docker reuses the toolchain
and application layers.

`DOCKER_PLATFORM` defaults to `linux/amd64`. Override it only if you are using
a different compatible toolchain image:

```bash
DOCKER_PLATFORM=linux/amd64 ./scripts/build-arm32.sh
```

Check the ARM binary:

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
just lint            # everything (rust + cpp + qml)
just lint-cpp        # clang-format check + clang-tidy
just lint-qml        # qmllint
just lint-rust       # rustfmt check + clippy + cargo-deny
```

`just lint` is the zero-warnings gate before a PR. `compile_commands.json` is
always generated in `build/`, so clang-tidy and qmllint have the project
metadata they need.

### Auto-fix

When CI complains about formatting or a fixable clippy lint, run:

```bash
just fix             # cargo clippy --fix, then all formatters
just fmt             # only the formatters (cargo fmt + clang-format +
                     # qmlformat + cmake-format) on tracked files
```

`just fix` runs `cargo clippy --fix` first because its rewrites may not be
pre-formatted; the formatters are the cleanup pass. The recipes invoke each
underlying tool directly — there is no `pre-commit` or other Python
orchestrator in the loop.

### Docker-based lint and fix

If you do not want to install Qt, clang-format, clang-tidy, qmlformat,
qmllint, cmake-format, or cargo-deny on the host, every lint and format
recipe has a Docker variant. They run the published `Dockerfile.lint`
image from GHCR — tag is read from `lint/VERSION` so a single source of
truth drives both the publish workflow and your local pulls.

```bash
just fmt-docker         # just fmt inside the image
just fix-docker         # just fix inside the image
just lint-docker        # rust + cpp + qml lints inside the image
just lint-cpp-docker    # only the cmake `lint` target (clang-format + clang-tidy + qmllint)
just lint-qml-docker    # only the qmllint subset
```

The lint image carries Rust, rustfmt, clippy, cargo-deny, clang-format,
clang-tidy, qmlformat, qmllint, cmake-format, and Qt6 dev libraries
(cargo clippy and the cmake lint target both need Qt to link cxx-qt-lib
and to generate `compile_commands.json` plus the cxx-qt qmldir). The
image is published multi-arch (linux/amd64, linux/arm64), so Apple
Silicon Mac contributors get a native image with no Rosetta translation.

The Docker recipes that build (cpp/qml/full `lint-docker`, `fix-docker`)
configure CMake into `build-docker/`, not `build/`, so they never stomp
the artifacts from a host `just build`. First run is slow (full Qt-linked
build inside the container). Subsequent runs reuse `build-docker/` via
the bind mount and are fast.

## Deploy desktop bundle

```bash
just build
./packaging/deploy-desktop.sh
./deploy/launcher/run.sh
```

The deploy script copies Qt shared libraries next to the binary. Qt must be on
your PATH (`qmake6` or `qmake` must be findable).

## Deploy to MiSTer

```bash
echo 'MISTER_IP=<your-mister-ip>' > .env
./scripts/deploy-mister.sh
```

To copy and restart an already-built `output/launcher` without rebuilding:

```bash
./scripts/deploy-mister.sh --skip-build
```

The MiSTer binary is self-contained. It sets `QT_QPA_PLATFORM=linuxfb` and
`QT_QUICK_BACKEND=software`, runs `vmode -r W H rgb32` using the configured
width and height (default `1920×1080`), and starts
`/media/fat/Scripts/zaparoo.sh -service start`. No wrapper script is needed.

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

Use this to reproduce the MiSTer rendering path on a desktop:

```bash
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/launcher
```

## Underlying mechanics

Use these only when debugging the build itself or doing something the justfile
does not cover.

`just build` resolves to:

```bash
cmake --preset desktop-debug
cmake --build --preset desktop-debug
```

`just lint-cpp` resolves to `cmake --build build --target lint`. That runs
clang-format (check only), clang-tidy, and qmllint together. The individual
targets are:

```bash
cmake --build build --target format-check   # clang-format dry-run
cmake --build build --target tidy           # clang-tidy
cmake --build build --target all_qmllint    # QML linting
```

`just test` resolves to `ctest --preset desktop-debug` plus
`cargo nextest run --workspace`. Nextest needs the Rust workspace path, so the
justfile runs that command from `rust/`. Plain ctest works too:

```bash
ctest --test-dir build --output-on-failure
```
