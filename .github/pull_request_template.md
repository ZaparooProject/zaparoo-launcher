<!-- Thanks for the pull request. Please fill this out before requesting review. -->

## Summary

<!-- What changed, and why? One or two sentences is usually enough. -->

## Motivation

<!-- Link the issue or discussion that led to this. Delete this section if it does not apply. -->

## Screenshots / recordings

<!-- Required for visual changes. Include the FPS counter at 720p and, if possible, 240p. -->

## Test plan

<!-- How did you verify this? Manual steps and automated tests are both fine. -->

## Checklist

- [ ] `just lint` is green (zero warnings)
- [ ] `just test` passes
- [ ] If this touches QML, the FPS counter stays green (≥ 55) at 720p+ and ≥ 30 at 240p
- [ ] If this could affect the MiSTer build, I considered ARM32 implications (see `docs/architecture.md`)
- [ ] If this adds user-visible strings, they are wrapped in `qsTr()` (QML) or `tr()` (C++)
- [ ] I have signed the [CLA](../.github/CLA.md) (first-time contributors only)
