# Zaparoo Launcher

A Qt/QML game launcher frontend for [Zaparoo Core](https://zaparoo.org), designed to run on MiSTer FPGA (Linux framebuffer, no GPU) and desktop systems. Built with Qt 6.7+, software rendering, and a retro carousel UI that scales from 240p CRT to 1080p.

## Building

See [docs/building.md](docs/building.md) for full instructions, including
first-run system dependencies.

Common tasks are wrapped in a [`justfile`](justfile); run `just --list` for the
full menu.

```bash
just build && just run    # desktop
just arm32                # MiSTer ARM32 cross-build (requires Docker)
just test                 # ctest + cargo nextest
just lint                 # clang-format, clang-tidy, qmllint, rustfmt, clippy, cargo-deny
```

`just test` and `just lint` require `cargo-nextest` and `cargo-deny`. Install
them once with:

```bash
cargo install --locked cargo-nextest cargo-deny
```

## Trademarks

This repository contains Zaparoo trademarks which are explicitly licensed to the project in this location by the trademark owner. These trademarks must be removed from the project or replaced if you intend to redistribute or adapt the project in any form. See the Zaparoo [Terms of Use](https://zaparoo.org/terms/) for further details.

## License

Copyright 2026 The Zaparoo Project Contributors.
Source available under the [PolyForm Noncommercial License 1.0.0](COPYING).
Non-commercial use only.

For commercial licensing, contact
[legal@zaparoo.org](mailto:legal@zaparoo.org) to discuss terms.

Third-party components:

- **Qt framework** — LGPLv3. Dynamically linked on desktop builds; statically
  linked on MiSTer ARM32. Object files for re-linking against a modified Qt
  are available on request at
  [legal@zaparoo.org](mailto:legal@zaparoo.org).
  See [`src/LICENSES/`](src/LICENSES/).
- **Press Start 2P** font — SIL Open Font License 1.1, © 2012 The Press Start 2P
  Project Authors. See [`src/LICENSES/OFL.txt`](src/LICENSES/OFL.txt) and
  [`src/LICENSES/PressStart2P-ATTRIBUTION.txt`](src/LICENSES/PressStart2P-ATTRIBUTION.txt).
