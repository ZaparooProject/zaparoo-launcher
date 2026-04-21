// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "Logger.h"

#include <QDateTime>
#include <QtGlobal>

Q_LOGGING_CATEGORY(zapApp, "zap.app")
Q_LOGGING_CATEGORY(zapCore, "zap.core")
Q_LOGGING_CATEGORY(zapNet, "zap.net")

namespace zaparoo
{

static void messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg)
{
    const QString timestamp = QDateTime::currentDateTime().toString("hh:mm:ss.zzz");
    const char* level = nullptr;
    switch (type)
    {
    case QtDebugMsg:
        level = "D";
        break;
    case QtInfoMsg:
        level = "I";
        break;
    case QtWarningMsg:
        level = "W";
        break;
    case QtCriticalMsg:
        level = "E";
        break;
    case QtFatalMsg:
        level = "F";
        break;
    }
    fprintf(stderr, "[%s %s] %s\n", timestamp.toLocal8Bit().constData(), level,
            msg.toLocal8Bit().constData());
    Q_UNUSED(ctx)
    if (type == QtFatalMsg)
    {
        abort();
    }
}

void Logger::install()
{
    qInstallMessageHandler(messageHandler);
}

} // namespace zaparoo
