# Building

## Requirements

### Desktop

- Qt 6.7+ (Quick, QuickControls2, Qml)
- CMake 3.22+
- C++17 compiler (GCC 10+, Clang 12+, MSVC 2019+)
- Rust stable toolchain (`rustup install stable`)
- Ninja (required; pinned by `CMakePresets.json`)
- mold (used as linker on x86_64 Linux; pinned by `rust/.cargo/config.toml`)

On Fedora/RHEL: `sudo dnf install qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel cmake ninja-build mold`
On Ubuntu/Debian: `sudo apt install qt6-declarative-dev qt6-quick-controls2-dev cmake ninja-build mold`

Install Rust via rustup: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

### MiSTer ARM32 cross-build

- Docker (any recent version)
- x86_64 host (no emulation needed, pure cross-compilation)
- ~8 GB disk space for the toolchain image

The toolchain Docker image ships a cross-compiler-aware `rust/.cargo/config.toml`
that sets the correct linker (`arm-linux-gnueabihf-gcc`), target
(`armv7-unknown-linux-gnueabihf`), and `mold` on desktop for faster links.
No manual cargo config is needed.

## Desktop build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
./build/bin/launcher
```

For a Release build:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

### Skip tests (faster iteration)

```bash
cmake -S . -B build -DZAPAROO_BUILD_TESTS=OFF
```

### Sanitizers (Debug only)

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug \
    -DZAPAROO_ENABLE_ASAN=ON -DZAPAROO_ENABLE_UBSAN=ON
cmake --build build
./build/bin/launcher
```

### QML linting

```bash
cmake --build build --target all_qmllint
```

## MiSTer ARM32 cross-build

**First time (builds Qt 6.7.2 from source, ~45 min):**

```bash
./scripts/build-toolchain.sh
```

This creates the `zaparoo/qt6-arm32-mister:6.7.2` Docker image locally.

**Subsequent builds (< 1 min):**

```bash
./scripts/build-arm32.sh
# Output: output/launcher
```

If the toolchain image is missing, `build-arm32.sh` rebuilds it automatically.

### Verify the ARM binary

```bash
file output/launcher
# Should report: ELF 32-bit LSB executable, ARM, EABI5 ...
```

## Deploy desktop bundle

```bash
cmake --build build
./packaging/deploy-desktop.sh
./deploy/launcher/run.sh
```

The deploy script bundles Qt shared libraries alongside the binary. Qt
must be on your PATH (i.e. `qmake6` or `qmake` must be findable).

## Deploy to MiSTer

```bash
./scripts/deploy-mister.sh
```

The binary is self-contained on MiSTer: it sets `QT_QPA_PLATFORM=linuxfb` and
`QT_QUICK_BACKEND=software`, runs `vmode -r W H rgb32` (width/height from
config, defaulting to 1920×1080), and starts
`/media/fat/Scripts/zaparoo.sh -service start` automatically. Just run the
binary; no wrapper script required.

User-editable config lives at `/media/fat/zaparoo/launcher.toml`. Example:

```toml
[video]
width = 1280
height = 720

[logging]
debug = true
```

## Run on framebuffer (desktop headless)

```bash
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/launcher
```

## Running tests

```bash
ctest --test-dir build --output-on-failure
```

Rust unit tests (zaparoo-core):

```bash
cargo test --manifest-path rust/Cargo.toml
```

## Code quality

### Run all linters

```bash
cmake --build build --target lint
```

This runs clang-format (check only), clang-tidy, and qmllint in one shot.
`compile_commands.json` is always generated in `build/`, so no extra cmake flag is needed.

### Individual lint targets

```bash
cmake --build build --target format-check   # clang-format dry-run
cmake --build build --target tidy           # clang-tidy static analysis
cmake --build build --target all_qmllint    # QML linting
```

### Rust linting

```bash
cargo fmt --manifest-path rust/Cargo.toml --check   # format check
cargo clippy --manifest-path rust/Cargo.toml         # static analysis
```

### Auto-format C++ files

```bash
clang-format -i src/**/*.{cpp,h} tests/**/*.cpp
```

### Format all files (pre-commit)

```bash
pre-commit run --all-files
```
