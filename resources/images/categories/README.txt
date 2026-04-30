Category logos for the categories carousel.

Filename matches the category name as emitted by upstream Zaparoo Core
(singular: Console.svg, Computer.svg, Handheld.svg, Arcade.svg).
HubCategoryTile resolves these via
qrc:/qt/qml/Zaparoo/App/resources/images/categories/<Name>.svg. Categories
without a curated logo here fall through to a procedural panel.

Favorites.svg matches the synthetic "Favorites" category injected by
CategoriesModel (see FAVORITES_CATEGORY in models/categories.rs).

Media.svg is bundled ahead of the Media screen (tracked in #21). The
"Media" category is currently filtered from the carousel via
HIDDEN_CATEGORIES in models/categories.rs.

Iconography: Handheld is from streamlinehq.com; the rest are from iconoir.com.
See src/LICENSES/ for upstream attribution.
