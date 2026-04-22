// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QString>
#include <QUrl>

namespace zaparoo
{

// Application configuration. All fields have defaults (ZAPAROO_DEV_BUILD
// overrides coreEndpoint to a developer host). Config files are optional —
// missing or malformed files leave all fields at their defaults.
struct Config
{
#ifdef ZAPAROO_DEV_BUILD
    QUrl coreEndpoint{"ws://10.0.0.107:7497/api/v0.1"};
#else
    QUrl coreEndpoint{"ws://127.0.0.1:7497/api/v0.1"};
#endif
    int videoWidth{1920};
    int videoHeight{1080};
};

// Loads config from path, returning defaults for missing or malformed files.
Config loadConfigFrom(const QString& path);

// Persists config to path, creating parent directories as needed.
void saveConfigTo(const QString& path, const Config& config);

// Loads config from the platform-specific config file path.
Config loadConfig();

// Persists config to the platform-specific config file path.
void saveConfig(const Config& config);

} // namespace zaparoo
