// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// SPDX-FileCopyrightText: 2026 Callan Barrett
#pragma once

#include <QObject>
#include <QString>
#include <QUrl>

namespace zaparoo
{

// Asynchronous interface to Zaparoo Core.
// Connect to signals to receive events; call connect() to start the session.
// Stub — transport not yet implemented.
class ZaparooClient : public QObject
{
    Q_OBJECT

  public:
    explicit ZaparooClient(QObject* parent = nullptr);
    ~ZaparooClient() override;

    void connectToCore(const QUrl& endpoint);
    void disconnectFromCore();

    [[nodiscard]] bool isConnected() const;

  signals:
    void connected();
    void disconnected();
    void errorOccurred(const QString& message);

    // Emitted when Zaparoo Core reports a card/tag scan event.
    void scanReceived(const QString& uid, const QString& text);

  private:
    bool m_connected{false};
};

} // namespace zaparoo
