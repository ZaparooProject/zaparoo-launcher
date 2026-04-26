Platform logos for the systems carousel.

Filename matches the Zaparoo Core system id, e.g. SNES.png, Genesis.png,
TurboGrafx16.png. The Tile delegate (src/ui/components/Tile.qml) resolves
these via qrc:/qt/qml/Zaparoo/App/resources/images/systems/<id>.png. Systems
without a curated logo here fall through to a procedural panel rendered in
the carousel.

Source and licence: src/LICENSES/console-logos-ATTRIBUTION.txt
