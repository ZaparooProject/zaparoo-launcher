// Zaparoo Launcher
// Copyright (c) 2026 The Zaparoo Project Contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Thin C++ entry point for the Rust launcher. Domain logic lives in the
// zaparoo_launcher_rs staticlib; Qt plugin wiring is handled here so that
// Qt's CMake (qt_import_qml_plugins) can emit the correct link flags.

#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QtQml/qqmlextensionplugin.h>
#include <cstddef>
#include <cstdint>

extern "C" int zaparoo_rust_init();
extern "C" void zaparoo_rust_post_qt_start();
extern "C" void zaparoo_log_qt(uint8_t level, const char* msg, size_t len);

// Pull Zaparoo QML plugin symbols into the final binary so the linker does
// not strip their static-initializer registration functions.
Q_IMPORT_QML_PLUGIN(Zaparoo_AppPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_UiPlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_ThemePlugin)
Q_IMPORT_QML_PLUGIN(Zaparoo_Browse_plugin)

// For static Qt builds (MiSTer ARM32): the QtQuick.Controls plugin chain and
// platform plugin are embedded in the binary, not found on disk, so they
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

// Forward all Qt log messages to the Rust tracing registry (same sinks as
// Rust-side log output: stderr + launcher.log). Installed after
// zaparoo_rust_init() so the tracing subscriber is already alive.
static void qtMessageHandler(QtMsgType type, const QMessageLogContext& /*ctx*/, const QString& msg)
{
    const QByteArray utf8 = msg.toUtf8();
    zaparoo_log_qt(static_cast<uint8_t>(type), utf8.constData(), static_cast<size_t>(utf8.size()));
}

int main(int argc, char* argv[])
{
    QGuiApplication::setApplicationName("Zaparoo Launcher");
    QGuiApplication::setApplicationVersion("0.1.0");
    QGuiApplication::setOrganizationName("Zaparoo");
    QGuiApplication::setOrganizationDomain("zaparoo.org");

    if (zaparoo_rust_init() != 0)
    {
        return EXIT_FAILURE;
    }

    // Install after zaparoo_rust_init() so tracing is live before any Qt
    // messages are emitted.
    qInstallMessageHandler(qtMessageHandler);

    QGuiApplication app(argc, argv);
    QFontDatabase::addApplicationFont(":/qt/qml/Zaparoo/App/resources/fonts/PressStart2P.ttf");
    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;
#ifndef ZAPAROO_DEV_BUILD
    engine.setInitialProperties({{"fullScreen", true}});
#endif
    engine.loadFromModule("Zaparoo.App", "Main");

    if (engine.rootObjects().isEmpty())
    {
        return EXIT_FAILURE;
    }

    zaparoo_rust_post_qt_start();
    return QGuiApplication::exec();
}
