# Zaparoo Launcher

Zaparoo Launcher is the game launcher frontend for
[Zaparoo Core](https://zaparoo.org).

## Build

Start with [docs/building.md](docs/building.md). It covers the packages you
need on a fresh machine and the MiSTer cross-build path.

Most commands go through the [`justfile`](justfile). Run `just --list` if you
need the full menu.

```bash
just build && just run    # desktop
just arm32                # MiSTer ARM32 cross-build (requires Docker)
just test                 # ctest + cargo nextest
just lint                 # clang-format, clang-tidy, qmllint, rustfmt, clippy, cargo-deny
```

`just test` and `just lint` need `cargo-nextest` and `cargo-deny`:

```bash
cargo install --locked cargo-nextest cargo-deny
```

## Trademarks

This repository includes Zaparoo trademarks used here with permission from the
trademark owner. If you redistribute or adapt the project, remove or replace
those marks first. See the Zaparoo [Terms of Use](https://zaparoo.org/terms/)
for the details.

## License

Copyright 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
Source available under the [PolyForm Noncommercial License 1.0.0](COPYING).
Non-commercial use only. For commercial licensing, contact
[legal@zaparoo.org](mailto:legal@zaparoo.org).

Third-party components:

- **Qt framework**: LGPLv3. Dynamically linked on desktop builds; statically
  linked on MiSTer ARM32. Object files for re-linking against a modified Qt
  are available on request at
  [legal@zaparoo.org](mailto:legal@zaparoo.org).
  See [`src/LICENSES/`](src/LICENSES/).
- **Press Start 2P** font: SIL Open Font License 1.1, © 2012 The Press Start 2P
  Project Authors. See [`src/LICENSES/OFL.txt`](src/LICENSES/OFL.txt) and
  [`src/LICENSES/PressStart2P-ATTRIBUTION.txt`](src/LICENSES/PressStart2P-ATTRIBUTION.txt).
