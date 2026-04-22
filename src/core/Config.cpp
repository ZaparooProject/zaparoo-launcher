// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "Config.h"

#include "Logger.h"
#include "PlatformPaths.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <sstream>

// toml++ emits -Wunused-result on internal constructors under GCC 10 (ARM32
// cross-compiler). Suppress for this header only; Clang honours GCC pragmas.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-result"
#include <tomlplusplus/toml.hpp>
#pragma GCC diagnostic pop

namespace zaparoo
{

Config loadConfigFrom(const QString& path)
{
    Config config;

    if (!QFileInfo::exists(path))
    {
        qCDebug(zapCore) << "loadConfig: no config file at" << path;
        return config;
    }

    try
    {
        const auto table = toml::parse_file(path.toStdString());

        if (const auto v = table["core"]["url"].value<std::string>())
        {
            const QUrl url(QString::fromStdString(*v));
            if (url.isValid())
            {
                config.coreEndpoint = url;
            }
            else
            {
                qCWarning(zapCore) << "loadConfig: invalid core.url" << *v << "— using default";
            }
        }
        auto loadDim = [&](const char* key, int& target)
        {
            if (const auto v = table["video"][key].value<int>())
            {
                if (*v > 0)
                {
                    target = *v;
                }
                else
                {
                    qCWarning(zapCore)
                        << "loadConfig: invalid video." << key << *v << "— using default";
                }
            }
        };
        loadDim("width", config.videoWidth);
        loadDim("height", config.videoHeight);
        qCInfo(zapCore) << "loadConfig: loaded from" << path;
    }
    catch (const toml::parse_error& e)
    {
        qCWarning(zapCore) << "loadConfig: parse error in" << path << "—" << e.what()
                           << "— using defaults";
    }
    return config;
}

void saveConfigTo(const QString& path, const Config& config)
{
    QDir().mkpath(QFileInfo(path).absolutePath());

    auto table = toml::table{
        {"core", toml::table{{"url", config.coreEndpoint.toString().toStdString()}}},
        {"video", toml::table{{"width", config.videoWidth}, {"height", config.videoHeight}}},
    };

    std::ostringstream oss;
    oss << table;

    const QString tmpPath = path + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        qCWarning(zapCore) << "saveConfig: cannot write to" << tmpPath;
        return;
    }
    tmp.write(QByteArray::fromStdString(oss.str()));
    tmp.close();

    QFile::remove(path);
    if (!QFile::rename(tmpPath, path))
    {
        qCWarning(zapCore) << "saveConfig: rename failed for" << path;
        QFile::remove(tmpPath);
        return;
    }
    qCInfo(zapCore) << "saveConfig: saved to" << path;
}

Config loadConfig()
{
    return loadConfigFrom(PlatformPaths::configFilePath());
}

void saveConfig(const Config& config)
{
    saveConfigTo(PlatformPaths::configFilePath(), config);
}

} // namespace zaparoo
