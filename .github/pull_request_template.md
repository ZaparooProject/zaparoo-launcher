<!-- Thanks for sending a pull request! Fill this out before requesting review. -->

## Summary

<!-- What does this PR change, and why? One or two sentences is usually enough. -->

## Motivation

<!-- Link to the issue being fixed or the discussion this came out of. Delete this section if neither applies. -->

## Screenshots / recordings

<!-- Required for any visual change. Include the FPS counter reading at 720p and, if possible, 240p. -->

## Test plan

<!-- How did you verify this works? Bullet list of manual steps or automated tests. -->

## Checklist

- [ ] `just lint` is green (zero warnings)
- [ ] `just test` passes
- [ ] If this touches QML, the FPS counter stays green (≥ 55) at 720p+ and ≥ 30 at 240p
- [ ] If this could affect the MiSTer build, I considered ARM32 implications (see `docs/architecture.md`)
- [ ] If this adds user-visible strings, they are wrapped in `qsTr()` (QML) or `tr()` (C++)
- [ ] I have signed the [CLA](../.github/CLA.md) (first-time contributors only)
