// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "BrowseModel.h"

#include "Logger.h"

#include <algorithm>

namespace zaparoo
{

BrowseModel* BrowseModel::s_instance =
    nullptr; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

BrowseModel* BrowseModel::create(QQmlEngine*, QJSEngine*)
{
    Q_ASSERT_X(s_instance, "BrowseModel::create",
               "BrowseModel::setInstance() must be called before the QML engine is created");
    QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    return s_instance;
}

void BrowseModel::setInstance(BrowseModel* instance)
{
    s_instance = instance;
}

BrowseModel::BrowseModel(ZaparooClient* client, QObject* parent)
    : QAbstractListModel(parent), m_client(client)
{
}

int BrowseModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return static_cast<int>(m_entries.size());
}

QVariant BrowseModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_entries.size()))
    {
        return {};
    }
    const BrowseEntry& entry = m_entries[index.row()];
    switch (role)
    {
    case NameRole:
        return entry.name;
    case PathRole:
        return entry.path;
    case TypeRole:
        return entry.type;
    case FileCountRole:
        return entry.fileCount;
    case IsFolderRole:
        return entry.zapScript.isEmpty();
    default:
        return {};
    }
}

QHash<int, QByteArray> BrowseModel::roleNames() const
{
    return {
        {NameRole, "name"},           {PathRole, "path"},         {TypeRole, "type"},
        {FileCountRole, "fileCount"}, {IsFolderRole, "isFolder"},
    };
}

QString BrowseModel::currentPath() const
{
    return m_currentPath;
}

bool BrowseModel::canGoBack() const
{
    return !m_stack.isEmpty();
}

bool BrowseModel::loading() const
{
    return m_loading;
}

QString BrowseModel::errorMessage() const
{
    return m_errorMessage;
}

void BrowseModel::setLoadingState(bool loading)
{
    if (m_loading == loading)
    {
        return;
    }
    m_loading = loading;
    emit loadingChanged();
}

void BrowseModel::setErrorMessageState(const QString& msg)
{
    if (m_errorMessage == msg)
    {
        return;
    }
    m_errorMessage = msg;
    emit errorMessageChanged();
}

void BrowseModel::enter(int index)
{
    if (m_loading)
    {
        return;
    }
    if (index < 0 || index >= static_cast<int>(m_entries.size()))
    {
        return;
    }
    if (!isFolderAt(index))
    {
        return;
    }
    browse(m_entries[index].path, -1, Frame{m_currentPath, index});
}

void BrowseModel::goBack()
{
    if (m_stack.isEmpty())
    {
        return;
    }
    const Frame frame = m_stack.takeLast();
    if (m_stack.isEmpty())
    {
        emit canGoBackChanged();
    }
    browse(frame.path, frame.selectedIndex);
}

void BrowseModel::refresh()
{
    browse(m_currentPath, m_selectedIndex);
}

void BrowseModel::setSelectedIndex(int index)
{
    m_selectedIndex = index;
}

QString BrowseModel::nameAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_entries.size()))
    {
        return {};
    }
    return m_entries[index].name;
}

bool BrowseModel::isFolderAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_entries.size()))
    {
        return false;
    }
    return m_entries[index].zapScript.isEmpty();
}

void BrowseModel::launchAt(int index)
{
    if (index < 0 || index >= static_cast<int>(m_entries.size()))
    {
        return;
    }
    const BrowseEntry& entry = m_entries[index];
    if (entry.zapScript.isEmpty())
    {
        return;
    }
    RunParams params;
    params.text = entry.zapScript;
    const QString name = entry.name;
    m_client->run(params,
                  [name](const RunResult&, const JsonRpcError& error)
                  {
                      if (error.isError)
                      {
                          qCWarning(zapCore) << "run failed for" << name << ":" << error.message;
                      }
                  });
}

void BrowseModel::browse(const QString& path, int restoreIndex,
                         const std::optional<Frame>& pushOnSuccess)
{
    if (!m_client->isConnected())
    {
        return;
    }
    setLoadingState(true);
    setErrorMessageState({});

    const quint64 seq = ++m_seq;
    MediaBrowseParams params;
    params.path = path;

    m_client->mediaBrowse(
        params,
        [this, seq, path, restoreIndex, pushOnSuccess](const MediaBrowseResult& result,
                                                       const JsonRpcError& error)
        {
            if (seq != m_seq)
            {
                return;
            }
            setLoadingState(false);
            if (error.isError)
            {
                setErrorMessageState(error.message);
                return;
            }
            if (pushOnSuccess)
            {
                const bool wasEmpty = m_stack.isEmpty();
                m_stack.push_back(*pushOnSuccess);
                if (wasEmpty)
                {
                    emit canGoBackChanged();
                }
            }
            const bool pathActuallyChanged = (path != m_currentPath);
            beginResetModel();
            m_entries = result.entries;
            m_entries.erase(std::remove_if(m_entries.begin(), m_entries.end(),
                                           [](const BrowseEntry& e)
                                           { return e.zapScript.isEmpty() && e.fileCount == 0; }),
                            m_entries.end());
            m_currentPath = path;
            endResetModel();
            emit countChanged();
            if (pathActuallyChanged)
            {
                emit currentPathChanged();
            }
            if (restoreIndex >= 0)
            {
                const int clamped =
                    qBound(0, restoreIndex, qMax(0, static_cast<int>(m_entries.size()) - 1));
                emit indexRestored(clamped);
            }
        });
}

} // namespace zaparoo
