// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "BrowseModel.h"
#include "ZaparooClient.h"

#include <QtQml/qqmlextensionplugin.h>
#include <QtQuickTest/quicktest.h>

Q_IMPORT_QML_PLUGIN(Zaparoo_AppPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_BrowsePlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_UiPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ThemePlugin)

// Creates the BrowseModel singleton before any QML engine is constructed.
class SmokeSetup : public QObject
{
    Q_OBJECT

  public slots:
    void applicationAvailable()
    {
        m_client = new zaparoo::ZaparooClient(this); // NOLINT(cppcoreguidelines-owning-memory)
        m_model =
            new zaparoo::BrowseModel(m_client, this); // NOLINT(cppcoreguidelines-owning-memory)
        zaparoo::BrowseModel::setInstance(m_model);
    }

  private:
    zaparoo::ZaparooClient* m_client{nullptr};
    zaparoo::BrowseModel* m_model{nullptr};
};

QUICK_TEST_MAIN_WITH_SETUP(zaparoo_ui_smoke, SmokeSetup)

#include "tst_main.moc"
