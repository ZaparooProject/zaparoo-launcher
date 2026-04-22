// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QString>

namespace zaparoo
{

// Returns platform-appropriate paths for config, cache, and deployment.
// On MiSTer, paths live under /media/fat/zaparoo/.
// On desktop, standard XDG / platform paths are used.
class PlatformPaths
{
  public:
    PlatformPaths() = delete;

    // Path to the user config file (e.g. ~/.config/zaparoo/launcher.conf).
    static QString configFilePath();

    // Directory for cached data (cover art, metadata).
    static QString cacheDir();

    // Returns true when running on a MiSTer FPGA (/media/fat is present).
    static bool isMiSTer();
};

} // namespace zaparoo
