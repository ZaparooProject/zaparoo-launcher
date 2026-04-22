// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "MediaTypes.h"
#include "SystemsCatalog.h"

#include <QAbstractListModel>
#include <QQmlEngine>

namespace zaparoo
{

// QAbstractListModel exposing systems filtered by a chosen category.
// Call setCategory() to load a new category slice; the model resets synchronously
// from the already-cached catalog (no network round-trip).
class SystemsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString currentCategory READ currentCategory NOTIFY currentCategoryChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

  public:
    enum Roles : int // NOLINT(performance-enum-size,cppcoreguidelines-use-enum-class)
    {
        IdRole = Qt::UserRole + 1,
        NameRole,
        CategoryRole,
    };
    Q_ENUM(Roles)

    explicit SystemsModel(SystemsCatalog* catalog, QObject* parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex& index,
                                int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    static SystemsModel* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);
    static void setInstance(SystemsModel* instance);

    [[nodiscard]] QString currentCategory() const;

    Q_INVOKABLE void setCategory(const QString& category);
    Q_INVOKABLE [[nodiscard]] QString systemIdAt(int index) const;
    Q_INVOKABLE [[nodiscard]] QString systemNameAt(int index) const;

  signals:
    void currentCategoryChanged();
    void countChanged();

  private:
    void onCatalogChanged();

    SystemsCatalog* m_catalog;
    QVector<SystemInfo> m_systems;
    QString m_currentCategory;

    static SystemsModel* s_instance; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)
};

} // namespace zaparoo
