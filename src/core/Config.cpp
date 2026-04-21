// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "Config.h"

#include "Logger.h"
#include "PlatformPaths.h"

namespace zaparoo
{

Config loadConfig()
{
    // TODO: read from PlatformPaths::configFilePath() using QSettings or TOML.
    qCDebug(zapCore) << "loadConfig: returning defaults (not yet implemented)";
    return Config{};
}

void saveConfig(const Config& config)
{
    // TODO: write to PlatformPaths::configFilePath() using QSettings or TOML.
    qCDebug(zapCore) << "saveConfig: not yet implemented";
    Q_UNUSED(config)
}

} // namespace zaparoo
