Platform logos for the paged systems grid.

Filename matches the Zaparoo Core system id, e.g. SNES.png, Genesis.png,
TurboGrafx16.png. The Tile delegate (src/ui/components/Tile.qml) resolves
these via the Resources singleton's coverUrl helper. Systems without a
curated logo here fall through to a procedural panel rendered in the
paged grid.

Source and licence: src/LICENSES/console-logos-ATTRIBUTION.txt
