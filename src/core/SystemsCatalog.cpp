// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "SystemsCatalog.h"

#include "Logger.h"

#include <QSet>
#include <algorithm>

namespace zaparoo
{

SystemsCatalog::SystemsCatalog(ZaparooClient* client, QObject* parent)
    : QObject(parent), m_client(client)
{
    connect(m_client, &ZaparooClient::connected, this, &SystemsCatalog::refresh);
}

QVector<SystemInfo> SystemsCatalog::all() const
{
    return m_systems;
}

QStringList SystemsCatalog::categories() const
{
    return m_categories;
}

QVector<SystemInfo> SystemsCatalog::byCategory(const QString& category) const
{
    QVector<SystemInfo> result;
    const bool isOther = category.compare(QLatin1String("Other"), Qt::CaseInsensitive) == 0;
    for (const SystemInfo& s : m_systems)
    {
        const bool matches = (isOther && s.category.isEmpty()) ||
                             (!isOther && s.category.compare(category, Qt::CaseInsensitive) == 0);
        if (matches)
        {
            result.append(s);
        }
    }
    return result;
}

void SystemsCatalog::refresh()
{
    if (!m_client->isConnected())
    {
        return;
    }

    const quint64 seq = ++m_seq;
    m_client->systems(SystemsParams{},
                      [this, seq](const SystemsResult& result, const JsonRpcError& error)
                      {
                          if (seq != m_seq)
                          {
                              return;
                          }
                          if (error.isError)
                          {
                              qCWarning(zapCore) << "systems RPC failed:" << error.message;
                              return;
                          }

                          m_systems = result.systems;

                          // Sort systems by name case-insensitively.
                          std::sort(m_systems.begin(), m_systems.end(),
                                    [](const SystemInfo& a, const SystemInfo& b)
                                    { return a.name.compare(b.name, Qt::CaseInsensitive) < 0; });

                          // Derive deduped, sorted category list. Empty category → "Other".
                          QSet<QString> seen;
                          QStringList cats;
                          for (const SystemInfo& s : m_systems)
                          {
                              const QString cat =
                                  s.category.isEmpty() ? QStringLiteral("Other") : s.category;
                              const QString lower = cat.toLower();
                              if (!seen.contains(lower))
                              {
                                  seen.insert(lower);
                                  cats.append(cat);
                              }
                          }
                          std::sort(cats.begin(), cats.end(), [](const QString& a, const QString& b)
                                    { return a.compare(b, Qt::CaseInsensitive) < 0; });
                          m_categories = cats;

                          qCInfo(zapCore) << "systems catalog loaded:" << m_systems.size()
                                          << "systems," << m_categories.size() << "categories";
                          emit catalogChanged();
                      });
}

} // namespace zaparoo
