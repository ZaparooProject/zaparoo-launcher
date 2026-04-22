// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include "MediaTypes.h"
#include "ZaparooClient.h"

#include <QAbstractListModel>
#include <QQmlEngine>

namespace zaparoo
{

// QAbstractListModel exposing games for a chosen system via media.search.
// Call setSystem() to load; loading/errorMessage/hasNextPage are observable.
// Pagination loads the first page only (maxResults=100); hasNextPage is exposed
// so a future PR can add a loadNextPage() invokable without changing the model API.
class GamesModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(bool hasNextPage READ hasNextPage NOTIFY hasNextPageChanged)
    Q_PROPERTY(QString currentSystemId READ currentSystemId NOTIFY currentSystemIdChanged)

  public:
    enum Roles : int // NOLINT(performance-enum-size,cppcoreguidelines-use-enum-class)
    {
        NameRole = Qt::UserRole + 1,
        PathRole,
        ZapScriptRole,
        SystemIdRole,
    };
    Q_ENUM(Roles)

    explicit GamesModel(ZaparooClient* client, QObject* parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex& index,
                                int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    static GamesModel* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);
    static void setInstance(GamesModel* instance);

    [[nodiscard]] bool loading() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] bool hasNextPage() const;
    [[nodiscard]] QString currentSystemId() const;

    Q_INVOKABLE void setSystem(const QString& systemId);
    Q_INVOKABLE void launchAt(int index);
    Q_INVOKABLE [[nodiscard]] QString nameAt(int index) const;
    Q_INVOKABLE void setSelectedIndex(int index);

  signals:
    void loadingChanged();
    void errorMessageChanged();
    void countChanged();
    void hasNextPageChanged();
    void currentSystemIdChanged();

  private:
    void setLoadingState(bool loading);
    void setErrorMessageState(const QString& msg);
    void setHasNextPage(bool value);

    ZaparooClient* m_client;
    QVector<MediaItem> m_items;
    QString m_currentSystemId;
    quint64 m_seq{0};
    bool m_loading{false};
    QString m_errorMessage;
    bool m_hasNextPage{false};
    int m_selectedIndex{0};

    static GamesModel* s_instance; // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)
};

} // namespace zaparoo
