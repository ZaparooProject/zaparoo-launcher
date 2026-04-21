// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(zapApp)
Q_DECLARE_LOGGING_CATEGORY(zapCore)
Q_DECLARE_LOGGING_CATEGORY(zapNet)

namespace zaparoo
{

// Installs a unified qInstallMessageHandler and configures default
// per-category verbosity. Call once from main() before any Qt objects are
// created.
class Logger
{
  public:
    static void install();

    Logger() = delete;
};

} // namespace zaparoo
