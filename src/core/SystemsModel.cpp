// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "SystemsModel.h"

namespace zaparoo
{

SystemsModel* SystemsModel::s_instance =
    nullptr; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

SystemsModel* SystemsModel::create(QQmlEngine*, QJSEngine*)
{
    Q_ASSERT_X(s_instance, "SystemsModel::create",
               "SystemsModel::setInstance() must be called before the QML engine is created");
    QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    return s_instance;
}

void SystemsModel::setInstance(SystemsModel* instance)
{
    s_instance = instance;
}

SystemsModel::SystemsModel(SystemsCatalog* catalog, QObject* parent)
    : QAbstractListModel(parent), m_catalog(catalog)
{
    Q_ASSERT(catalog != nullptr);
    connect(m_catalog, &SystemsCatalog::catalogChanged, this, &SystemsModel::onCatalogChanged);
}

int SystemsModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return static_cast<int>(m_systems.size());
}

QVariant SystemsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_systems.size()))
    {
        return {};
    }
    const SystemInfo& s = m_systems[index.row()];
    switch (role)
    {
    case IdRole:
        return s.id;
    case NameRole:
        return s.name;
    case CategoryRole:
        return s.category;
    default:
        return {};
    }
}

QHash<int, QByteArray> SystemsModel::roleNames() const
{
    return {
        {IdRole, "id"},
        {NameRole, "name"},
        {CategoryRole, "category"},
    };
}

QString SystemsModel::currentCategory() const
{
    return m_currentCategory;
}

void SystemsModel::setCategory(const QString& category)
{
    beginResetModel();
    m_systems = m_catalog->byCategory(category);
    m_currentCategory = category;
    endResetModel();
    emit countChanged();
    emit currentCategoryChanged();
}

QString SystemsModel::systemIdAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_systems.size()))
    {
        return {};
    }
    return m_systems[index].id;
}

QString SystemsModel::systemNameAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_systems.size()))
    {
        return {};
    }
    return m_systems[index].name;
}

void SystemsModel::onCatalogChanged()
{
    if (m_currentCategory.isEmpty())
    {
        return;
    }
    beginResetModel();
    m_systems = m_catalog->byCategory(m_currentCategory);
    endResetModel();
    emit countChanged();
}

} // namespace zaparoo
