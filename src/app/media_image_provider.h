// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// QQuickImageProvider that serves media image bytes (boxart, screenshot,
// wheel, titleshot, map, marquee, fanart, generic image — anything Core
// returns from `media.image`) from the Rust-side in-memory cache
// (`media_image_cache.rs`). QML loads `image://media-image/<key>` URLs;
// QtQuick calls `requestImage` with `<key>` (the bit after the scheme +
// host); we hand the encoded key to the Rust C ABI which looks the
// bytes up in the LRU cache and copies them into a QByteArray. Empty
// bytes → null QImage, and Tile.qml's fallback text stays visible.

#pragma once

#include <QImage>
#include <QQuickImageProvider>
#include <QSize>
#include <QString>

class MediaImageProvider : public QQuickImageProvider
{
  public:
    MediaImageProvider();
    ~MediaImageProvider() override = default;

    QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override;
};
