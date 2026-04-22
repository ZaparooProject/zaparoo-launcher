// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "BrowseModel.h"
#include "CategoriesModel.h"
#include "GamesModel.h"
#include "SystemsCatalog.h"
#include "SystemsModel.h"
#include "ZaparooClient.h"

#include <QtQml/qqmlextensionplugin.h>
#include <QtQuickTest/quicktest.h>

Q_IMPORT_QML_PLUGIN(Zaparoo_AppPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_BrowsePlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_UiPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ThemePlugin)

// Creates all model singletons before any QML engine is constructed.
class SmokeSetup : public QObject
{
    Q_OBJECT

  public slots:
    void applicationAvailable()
    {
        m_client = new zaparoo::ZaparooClient(this); // NOLINT(cppcoreguidelines-owning-memory)
        m_catalog =
            new zaparoo::SystemsCatalog(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_browse =
            new zaparoo::BrowseModel(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_categories = new zaparoo::CategoriesModel(
            m_catalog, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_systems =
            new zaparoo::SystemsModel(m_catalog, this); // NOLINT(cppcoreguidelines-owning-memory)
        m_games =
            new zaparoo::GamesModel(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)

        zaparoo::BrowseModel::setInstance(m_browse);
        zaparoo::CategoriesModel::setInstance(m_categories);
        zaparoo::SystemsModel::setInstance(m_systems);
        zaparoo::GamesModel::setInstance(m_games);
    }

  private:                                       // NOLINT(readability-redundant-access-specifiers)
    zaparoo::ZaparooClient* m_client{nullptr};   // NOLINT(cppcoreguidelines-owning-memory)
    zaparoo::SystemsCatalog* m_catalog{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
    zaparoo::BrowseModel* m_browse{nullptr};     // NOLINT(cppcoreguidelines-owning-memory)
    zaparoo::CategoriesModel* m_categories{nullptr}; // NOLINT(cppcoreguidelines-owning-memory)
    zaparoo::SystemsModel* m_systems{nullptr};       // NOLINT(cppcoreguidelines-owning-memory)
    zaparoo::GamesModel* m_games{nullptr};           // NOLINT(cppcoreguidelines-owning-memory)
};

QUICK_TEST_MAIN_WITH_SETUP(zaparoo_ui_smoke, SmokeSetup)

#include "tst_main.moc"
