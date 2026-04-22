// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "MediaTypes.h"
#include "ZaparooClient.h"

#include <QObject>
#include <QStringList>
#include <QVector>

namespace zaparoo
{

// Internal store for the systems RPC response. Fetched once on connect;
// CategoriesModel and SystemsModel subscribe to catalogChanged() to update.
class SystemsCatalog : public QObject
{
    Q_OBJECT

  public:
    explicit SystemsCatalog(ZaparooClient* client, QObject* parent = nullptr);

    [[nodiscard]] QVector<SystemInfo> all() const;
    // Sorted case-insensitively; empty category is bucketed under "Other".
    [[nodiscard]] QStringList categories() const;
    [[nodiscard]] QVector<SystemInfo> byCategory(const QString& category) const;

  signals:
    void catalogChanged();

  private:
    void refresh();

    ZaparooClient* m_client;
    QVector<SystemInfo> m_systems;
    QStringList m_categories;
    quint64 m_seq{0};
};

} // namespace zaparoo
