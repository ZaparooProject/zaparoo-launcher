Category logos for the categories carousel.

Filename matches the category name as emitted by upstream Zaparoo Core
(singular form, e.g. Console.png, Computer.png, Handheld.png, Arcade.png).
The Tile delegate (src/ui/components/Tile.qml) resolves these via
qrc:/qt/qml/Zaparoo/App/resources/images/categories/<Name>.png. Categories
without a curated logo here fall through to a procedural panel.

Favorites.png is reserved for a future top-of-list "Favorites" entry; it is
currently rendered for a non-functional placeholder injected by
CategoriesModel.

Source and licence: src/LICENSES/console-logos-ATTRIBUTION.txt
