// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QString>
#include <QStringList>
#include <QVector>

namespace zaparoo
{

struct SystemInfo
{
    QString id;
    QString name;
    QString category;
};

struct MediaTag
{
    QString tag;
    QString type;
};

struct MediaItem
{
    SystemInfo system;
    QString name;
    QString path;
    QString zapScript;
    QVector<MediaTag> tags;
};

struct MediaSearchParams
{
    QString query;
    QStringList systems;
    int maxResults{100};
    QString cursor;
};

struct MediaSearchResult
{
    QVector<MediaItem> results;
    QString nextCursor;
    bool hasNextPage{false};
    int pageSize{0};
};

struct MediaBrowseParams
{
    QString path;
    int maxResults{100};
    QString cursor;
    QString sort;
};

struct BrowseEntry
{
    QString name;
    QString path;
    QString type;
    QString systemId;
    QString zapScript;
    int fileCount{0};
    QVector<MediaTag> tags;
};

struct MediaBrowseResult
{
    QString path;
    QVector<BrowseEntry> entries;
    int totalFiles{0};
    QString nextCursor;
    bool hasNextPage{false};
};

struct RunParams
{
    QString text;
};

struct RunResult
{
};

struct SystemsParams
{
};

struct SystemsResult
{
    QVector<SystemInfo> systems;
};

} // namespace zaparoo
