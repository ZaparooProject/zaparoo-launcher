// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett

#include "GamesModel.h"

#include "Logger.h"

namespace zaparoo
{

GamesModel* GamesModel::s_instance =
    nullptr; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

GamesModel* GamesModel::create(QQmlEngine*, QJSEngine*)
{
    Q_ASSERT_X(s_instance, "GamesModel::create",
               "GamesModel::setInstance() must be called before the QML engine is created");
    QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    return s_instance;
}

void GamesModel::setInstance(GamesModel* instance)
{
    s_instance = instance;
}

GamesModel::GamesModel(ZaparooClient* client, QObject* parent)
    : QAbstractListModel(parent), m_client(client)
{
}

int GamesModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
    {
        return 0;
    }
    return static_cast<int>(m_items.size());
}

QVariant GamesModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_items.size()))
    {
        return {};
    }
    const MediaItem& item = m_items[index.row()];
    switch (role)
    {
    case NameRole:
        return item.name;
    case PathRole:
        return item.path;
    case ZapScriptRole:
        return item.zapScript;
    case SystemIdRole:
        return item.system.id;
    default:
        return {};
    }
}

QHash<int, QByteArray> GamesModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {ZapScriptRole, "zapScript"},
        {SystemIdRole, "systemId"},
    };
}

bool GamesModel::loading() const
{
    return m_loading;
}

QString GamesModel::errorMessage() const
{
    return m_errorMessage;
}

bool GamesModel::hasNextPage() const
{
    return m_hasNextPage;
}

QString GamesModel::currentSystemId() const
{
    return m_currentSystemId;
}

void GamesModel::setLoadingState(bool loading)
{
    if (m_loading == loading)
    {
        return;
    }
    m_loading = loading;
    emit loadingChanged();
}

void GamesModel::setErrorMessageState(const QString& msg)
{
    if (m_errorMessage == msg)
    {
        return;
    }
    m_errorMessage = msg;
    emit errorMessageChanged();
}

void GamesModel::setHasNextPage(bool value)
{
    if (m_hasNextPage == value)
    {
        return;
    }
    m_hasNextPage = value;
    emit hasNextPageChanged();
}

void GamesModel::setSystem(const QString& systemId)
{
    if (!m_client->isConnected())
    {
        return;
    }
    if (systemId == m_currentSystemId && !m_items.isEmpty())
    {
        return;
    }
    setLoadingState(true);
    setErrorMessageState({});

    const bool systemChanged = (systemId != m_currentSystemId);
    if (systemChanged)
    {
        m_currentSystemId = systemId;
        emit currentSystemIdChanged();
    }

    const quint64 seq = ++m_seq;
    MediaSearchParams params;
    params.systems = {systemId};
    params.maxResults = 100;

    m_client->mediaSearch(
        params,
        [this, seq, systemId](const MediaSearchResult& result, const JsonRpcError& error)
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
            if (result.hasNextPage)
            {
                qCWarning(zapCore) << "games list for" << systemId
                                   << "has more than 100 results; only the first page is shown";
            }
            beginResetModel();
            m_items = result.results;
            endResetModel();
            emit countChanged();
            setHasNextPage(result.hasNextPage);
        });
}

void GamesModel::launchAt(int index)
{
    if (index < 0 || index >= static_cast<int>(m_items.size()))
    {
        return;
    }
    const MediaItem& item = m_items[index];
    if (item.zapScript.isEmpty())
    {
        return;
    }
    RunParams params;
    params.text = item.zapScript;
    const QString name = item.name;
    m_client->run(params,
                  [name](const RunResult&, const JsonRpcError& error)
                  {
                      if (error.isError)
                      {
                          qCWarning(zapCore) << "run failed for" << name << ":" << error.message;
                      }
                  });
}

QString GamesModel::nameAt(int index) const
{
    if (index < 0 || index >= static_cast<int>(m_items.size()))
    {
        return {};
    }
    return m_items[index].name;
}

void GamesModel::setSelectedIndex(int index)
{
    m_selectedIndex = index;
}

} // namespace zaparoo
