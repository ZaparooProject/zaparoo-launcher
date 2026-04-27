Category logos for the categories carousel.

Filename matches the category name as emitted by upstream Zaparoo Core
(singular: Console.png, Computer.png, Handheld.png, Arcade.png).
HubCategoryTile resolves these via
qrc:/qt/qml/Zaparoo/App/resources/images/categories/<Name>.png. Categories
without a curated logo here fall through to a procedural panel.

Favorites.png matches the synthetic "Favorites" category injected by
CategoriesModel (see FAVORITES_CATEGORY in models/categories.rs).

Source and licence: src/LICENSES/console-logos-ATTRIBUTION.txt
