# Contributing to Zaparoo Launcher

Thanks for your interest. This doc covers the practical bits: signing
the CLA, getting a dev environment running, and what we expect before
you open a pull request.

## Contributor License Agreement

Every contributor signs a one-time [CLA](.github/CLA.md). It grants
**Wizzo Pty Ltd** (the legal entity behind the project) a broad license
to use and sublicense your contribution. You keep the copyright; this
is a license, not a transfer. The CLA exists so the company can grant
commercial licenses to friendly partners without renegotiating with
every past contributor each time.

To sign, open your first pull request and post this exact comment on
it:

> I have read the CLA Document and I hereby sign the CLA

The CLA Assistant Lite bot records your signature in
`.github/contributors/signatures.json`. You only need to sign once;
future PRs are recognized automatically.

## Development setup

See [`docs/quickstart.md`](docs/quickstart.md) for the fastest path
from a fresh clone to a running launcher. You do not need MiSTer
hardware: the repo ships a mock Zaparoo Core you can run locally with
`just mock-core`.

For full build details (MiSTer ARM32 cross-build, sanitizer builds,
deployment), see [`docs/building.md`](docs/building.md).

### Supported host platforms

- **Linux (x86_64)** is the primary development target and fully
  supported.
- **macOS** is best-effort. It should work, but CI does not cover it.
  Report breakage; patches welcome.
- **Windows** is not tested or actively supported. Use WSL2.

## Before you open a pull request

Run these locally. CI runs the same checks and will block merge if
they fail.

```bash
just lint    # clang-format, clang-tidy, qmllint, rustfmt, clippy, cargo-deny
just test    # ctest + cargo nextest
```

Zero lint warnings is the bar. If a rule is wrong for your change,
don't disable it; raise it in the PR and we'll discuss.

## Pull request conventions

The [PR template](.github/pull_request_template.md) prompts for
everything we want to see. The two things worth calling out up front:

- **Explain the why, not just the what.** The diff already shows the
  what.
- **Screenshots or recordings for visual changes**, with the FPS
  counter reading at 720p and, ideally, 240p. It must stay green
  (≥55) at 720p+ and not go red (<30) at 240p.

### Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` for a new user-visible feature
- `fix:` for a bug fix
- `refactor:` for a code change that neither fixes a bug nor adds a feature
- `docs:` for documentation-only changes
- `test:` for adding or updating tests
- `chore:` for build, tooling, deps, or other housekeeping

Scopes are optional but encouraged when they sharpen the summary:
`feat(ui): add settings screen`, `fix(rust): handle empty catalog`.

### Branch naming

`feat/<short-description>`, `fix/<short-description>`,
`docs/<short-description>`, etc. Keep it readable; hyphens not
underscores.

## Main branch is protected

`main` accepts changes only via pull request. Every PR needs:

1. All CI jobs green (`rust-lint`, `rust-test`, `desktop-build`,
   `arm32-build`, and the CLA check).
2. A CLA signature recorded for the PR author.
3. At least one approving review from a maintainer other than the PR
   author.
4. The branch up to date with `main`.

Force-pushing and direct pushes to `main` are blocked.

## Bugs and feature requests

Open a GitHub issue. For bugs, include repro steps, expected vs actual
behavior, whether it reproduces on desktop and/or MiSTer, and a log
excerpt (`~/.local/share/zaparoo/logs/launcher.log` on desktop;
`/tmp/zaparoo/launcher.log` on MiSTer). For features, say what you
want and why; if you plan to implement it yourself, say so and we'll
align on scope first.

## Questions?

- Architecture or design questions: open a GitHub Discussion (or
  issue) so the answer is searchable for the next person.
- CLA or licensing: [legal@zaparoo.org](mailto:legal@zaparoo.org).
