// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "BrowseModel.h"
#include "CategoriesModel.h"
#include "Config.h"
#include "GamesModel.h"
#include "Logger.h"
#include "MiSterRuntime.h"
#include "SystemsCatalog.h"
#include "SystemsModel.h"
#include "ZaparooClient.h"

#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QtQml/qqmlextensionplugin.h>

// Pull static QML plugin symbols into the final binary so the linker
// doesn't strip them as unreferenced.
Q_IMPORT_QML_PLUGIN(Zaparoo_AppPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_UiPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ThemePlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_BrowsePlugin)

// For static Qt builds (MiSTer ARM32): the QtQuick.Controls plugin chain and
// platform plugins are embedded in the binary and not found on disk, so they
// must be explicitly imported. On dynamic (desktop) Qt these are loaded
// automatically and the symbols don't exist as static functions.
#ifdef QT_STATIC
#include <QtPlugin>
Q_IMPORT_QML_PLUGIN(QtQuickControls2Plugin)
Q_IMPORT_QML_PLUGIN(QtQuickControls2BasicStylePlugin)
Q_IMPORT_QML_PLUGIN(QtQuickControls2ImplPlugin)
Q_IMPORT_QML_PLUGIN(QtQuickTemplates2Plugin)
Q_IMPORT_QML_PLUGIN(QtQuick_WindowPlugin)
Q_IMPORT_PLUGIN(QLinuxFbIntegrationPlugin)
#endif

int main(int argc, char* argv[])
{
    // These static setters must come before loadConfig() so that
    // QStandardPaths::AppConfigLocation resolves the correct org/app name
    // on desktop (otherwise it falls back to the binary filename).
    QGuiApplication::setApplicationName("Zaparoo Launcher");
    QGuiApplication::setApplicationVersion(QStringLiteral(ZAPAROO_VERSION));
    QGuiApplication::setOrganizationName("Zaparoo");
    QGuiApplication::setOrganizationDomain("zaparoo.org");

    // Logger and config load before QGuiApplication so that MiSTer pre-Qt
    // setup (env vars, vmode) can read the config. Neither Logger::install()
    // nor loadConfig() requires a QCoreApplication instance.
    zaparoo::Logger::install();
    const zaparoo::Config config = zaparoo::loadConfig();
    zaparoo::Logger::applyConfig(config);

    // On MiSTer: sets QT_QPA_PLATFORM/QT_QUICK_BACKEND and calls vmode.
    // Must run before QGuiApplication so Qt reads the env vars on init.
    // No-op on desktop.
    zaparoo::mister::applyPreQtSetup(config);

    // Start the Zaparoo Core service early so it has time to initialise
    // while Qt is loading. ZaparooClient will reconnect once it's up.
    // No-op on desktop.
    zaparoo::mister::ensureCoreServiceRunning();

    QGuiApplication app(argc, argv);

    zaparoo::ZaparooClient client;
    zaparoo::BrowseModel browseModel(&client);
    zaparoo::BrowseModel::setInstance(&browseModel);
    zaparoo::SystemsCatalog systemsCatalog(&client);
    zaparoo::CategoriesModel categoriesModel(&systemsCatalog);
    zaparoo::CategoriesModel::setInstance(&categoriesModel);
    zaparoo::SystemsModel systemsModel(&systemsCatalog);
    zaparoo::SystemsModel::setInstance(&systemsModel);
    zaparoo::GamesModel gamesModel(&client);
    zaparoo::GamesModel::setInstance(&gamesModel);

    // Fonts are embedded inside the Zaparoo.App QML module's resource bundle.
    QFontDatabase::addApplicationFont(":/qt/qml/Zaparoo/App/resources/fonts/DejaVuSans.ttf");
    QFontDatabase::addApplicationFont(":/qt/qml/Zaparoo/App/resources/fonts/PressStart2P.ttf");

    // Basic style is mandatory: it is the only style compatible with software
    // rendering on MiSTer (no GPU, no shaders, no platform-specific effects).
    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;
#ifndef ZAPAROO_DEV_BUILD
    // Full-screen for all release builds — MiSTer requires it and desktop
    // release builds should behave the same way.
    engine.setInitialProperties({{"fullScreen", true}});
#endif
    engine.loadFromModule("Zaparoo.App", "Main");

    if (engine.rootObjects().isEmpty())
    {
        return EXIT_FAILURE;
    }

    client.connectToCore(config.coreEndpoint);

    return QGuiApplication::exec();
}
