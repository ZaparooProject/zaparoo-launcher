// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "CategoriesModel.h"

namespace zaparoo
{

CategoriesModel* CategoriesModel::s_instance =
    nullptr; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

CategoriesModel* CategoriesModel::create(QQmlEngine*, QJSEngine*)
{
    Q_ASSERT_X(s_instance, "CategoriesModel::create",
               "CategoriesModel::setInstance() must be called before the QML engine is created");
    QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    return s_instance;
}

void CategoriesModel::setInstance(CategoriesModel* instance)
{
    s_instance = instance;
}

CategoriesModel::CategoriesModel(SystemsCatalog* catalog, QObject* parent)
    : QAbstractListModel(parent), m_catalog(catalog)
{
    Q_ASSERT(catalog != nullptr);
    connect(m_catalog, &SystemsCatalog::catalogChanged, this, &CategoriesModel::onCatalogChanged);
}

int CategoriesModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return static_cast<int>(m_categories.size());
}

QVariant CategoriesModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_categories.size()))
    {
        return {};
    }
    if (role == NameRole)
    {
        return m_categories[index.row()];
    }
    return {};
}

QHash<int, QByteArray> CategoriesModel::roleNames() const
{
    return {{NameRole, "name"}};
}

QString CategoriesModel::categoryAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_categories.size()))
    {
        return {};
    }
    return m_categories[index];
}

void CategoriesModel::onCatalogChanged()
{
    beginResetModel();
    m_categories = m_catalog->categories();
    endResetModel();
    emit countChanged();
}

} // namespace zaparoo
