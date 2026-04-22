// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "MiSterRuntime.h"

#ifdef ZAPAROO_MISTER

#include "Logger.h"

#include <QProcess>

namespace zaparoo::mister
{

void applyPreQtSetup(const zaparoo::Config& config)
{
    qputenv("QT_QPA_PLATFORM", "linuxfb");
    qputenv("QT_QUICK_BACKEND", "software");

    const QStringList vmodeArgs{"-r", QString::number(config.videoWidth),
                                QString::number(config.videoHeight), "rgb32"};
    const int result = QProcess::execute("vmode", vmodeArgs);
    if (result == -2)
    {
        qCWarning(zapApp) << "vmode not found or failed to start — display mode unchanged";
    }
    else if (result != 0)
    {
        qCWarning(zapApp) << "vmode exited with" << result << "— display mode may not have changed";
    }
}

void ensureCoreServiceRunning()
{
    if (!QProcess::startDetached("/media/fat/Scripts/zaparoo.sh", {"-service", "start"}))
    {
        qCWarning(zapApp) << "failed to start /media/fat/Scripts/zaparoo.sh";
    }
}

} // namespace zaparoo::mister

#else // !ZAPAROO_MISTER

namespace zaparoo::mister
{

void applyPreQtSetup(const zaparoo::Config& /*config*/) {}

void ensureCoreServiceRunning() {}

} // namespace zaparoo::mister

#endif
