# Zaparoo Launcher

A Qt/QML game launcher frontend for [Zaparoo Core](https://zaparoo.org), designed to run on MiSTer FPGA (Linux framebuffer, no GPU) and desktop systems. Built with Qt 6.7+, software rendering, and a retro carousel UI that scales from 240p CRT to 1080p.

## Building

See [docs/building.md](docs/building.md) for full instructions.

**Desktop (quick start):**

```bash
cmake -S . -B build && cmake --build build
./build/bin/launcher
```

**MiSTer ARM32 (requires Docker):**

```bash
./scripts/build-arm32.sh
# output/launcher
```

## Running on framebuffer

```bash
QT_QPA_PLATFORM=linuxfb QT_QUICK_BACKEND=software ./build/bin/launcher
```

On MiSTer, the binary sets `vmode` and starts the Zaparoo Core service automatically. Configure resolution via `/media/fat/zaparoo/launcher.toml`.

## Controls

| Key | Action |
|---|---|
| ← → | Browse games / navigate menu |
| ↓ | Open menu |
| ↑ / Esc | Back to carousel |
| Enter | Select / confirm |
| Esc | Quit (carousel mode) |

## Architecture

See [docs/architecture.md](docs/architecture.md) for module layout, QML URIs, and rendering constraints.

## License

Copyright 2026 Callan Barrett.
Source available under the [PolyForm Noncommercial License 1.0.0](COPYING).
Non-commercial use only.

This software uses the [Qt framework](https://www.qt.io/) under LGPLv3.
Qt is dynamically linked on desktop builds; statically linked on MiSTer
(object files available on request per LGPL §4(d)(1)).
See `src/LICENSES/` for the full Qt license texts.
