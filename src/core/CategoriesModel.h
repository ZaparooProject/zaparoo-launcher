// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "SystemsCatalog.h"

#include <QAbstractListModel>
#include <QQmlEngine>

namespace zaparoo
{

// QAbstractListModel exposing the deduped, sorted list of system categories.
// Populated from SystemsCatalog; updates when the catalog refreshes on connect.
class CategoriesModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

  public:
    enum Roles : int // NOLINT(performance-enum-size,cppcoreguidelines-use-enum-class)
    {
        NameRole = Qt::UserRole + 1,
    };
    Q_ENUM(Roles)

    explicit CategoriesModel(SystemsCatalog* catalog, QObject* parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex& index,
                                int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    static CategoriesModel* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);
    static void setInstance(CategoriesModel* instance);

    Q_INVOKABLE [[nodiscard]] QString categoryAt(int index) const;

  signals:
    void countChanged();

  private:
    void onCatalogChanged();

    SystemsCatalog* m_catalog;
    QStringList m_categories;

    static CategoriesModel*
        s_instance; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)
};

} // namespace zaparoo
