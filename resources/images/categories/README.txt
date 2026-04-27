Category logos for the categories carousel.

Filename matches the category name as emitted by upstream Zaparoo Core
(plural form for collective categories, e.g. Consoles.png, Computers.png,
Handhelds.png; Arcade.png stays singular per Core's canonical form).
The Tile delegate (src/ui/components/Tile.qml) resolves these via
qrc:/qt/qml/Zaparoo/App/resources/images/categories/<Name>.png. Categories
without a curated logo here fall through to a procedural panel.

Favorites.png is reserved for a future top-of-list "Favorites" entry; it is
currently rendered for a non-functional placeholder injected by
CategoriesModel.

Source and licence: src/LICENSES/console-logos-ATTRIBUTION.txt
