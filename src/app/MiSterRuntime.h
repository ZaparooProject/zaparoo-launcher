// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "Config.h"

namespace zaparoo::mister
{

// Sets QT_QPA_PLATFORM=linuxfb and QT_QUICK_BACKEND=software, then runs
// `vmode -r W H rgb32` to configure the framebuffer. Must be called before
// QGuiApplication is constructed. No-op on non-MiSTer builds.
void applyPreQtSetup(const zaparoo::Config& config);

// Fire-and-forget `zaparoo.sh -service start`. The ZaparooClient reconnect
// timer handles the brief service startup window. No-op on non-MiSTer builds.
void ensureCoreServiceRunning();

} // namespace zaparoo::mister
