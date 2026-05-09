// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

#include "native_video_writer.h"

#if defined(ZAPAROO_EMBEDDED_BUILD) && defined(__linux__)

#include <QLoggingCategory>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <thread>
#include <unistd.h>

namespace
{

constexpr uintptr_t kNativeVideoBase = 0x3A000000u;
constexpr size_t kNativeVideoRegionSize = 0x000A0000u;
constexpr size_t kControlOffset = 0x00000000u;
constexpr size_t kBuffer0Offset = 0x00000100u;
constexpr int kOutputWidth = 320;
constexpr int kOutputHeight = 240;
constexpr size_t kSourceBytesPerPixel = 4;
constexpr int kOutputBytes = kOutputWidth * kOutputHeight * kSourceBytesPerPixel;
constexpr size_t kBuffer1Offset = 0x0004B100u;
constexpr size_t kOutputRowBytes = kOutputWidth * kSourceBytesPerPixel;

std::atomic<bool> g_running{false};
std::thread g_thread;

bool validateFramebufferWindow(const fb_fix_screeninfo& fixed, const fb_var_screeninfo& var,
                               size_t fbSize)
{
    if (var.bits_per_pixel != 32 || var.xres < kOutputWidth || var.yres < kOutputHeight ||
        fixed.line_length < kOutputRowBytes)
    {
        qWarning("native video writer: unsupported fb0 mode %ux%u %u bpp; expected at least "
                 "320x240 32 bpp",
                 var.xres, var.yres, var.bits_per_pixel);
        return false;
    }

    if (var.xres_virtual < var.xoffset || var.yres_virtual < var.yoffset ||
        var.xres_virtual - var.xoffset < kOutputWidth ||
        var.yres_virtual - var.yoffset < kOutputHeight)
    {
        qWarning("native video writer: visible fb0 window %u,%u in %ux%u cannot cover 320x240",
                 var.xoffset, var.yoffset, var.xres_virtual, var.yres_virtual);
        return false;
    }

    const size_t sourceRowBytes =
        (static_cast<size_t>(var.xoffset) + kOutputWidth) * kSourceBytesPerPixel;
    if (fixed.line_length < sourceRowBytes)
    {
        qWarning("native video writer: fb0 stride %u too small for visible 320x240 window",
                 fixed.line_length);
        return false;
    }

    const size_t visibleOffset = static_cast<size_t>(var.yoffset) * fixed.line_length +
                                 static_cast<size_t>(var.xoffset) * kSourceBytesPerPixel;
    const size_t lastByte = visibleOffset +
                            static_cast<size_t>(kOutputHeight - 1) * fixed.line_length +
                            static_cast<size_t>(kOutputWidth) * kSourceBytesPerPixel;
    if (lastByte > fbSize)
    {
        qWarning("native video writer: visible fb0 window exceeds mapped framebuffer");
        return false;
    }

    return true;
}

class Fd
{
  public:
    explicit Fd(const char* path, int flags) : m_fd(open(path, flags)) {}

    ~Fd()
    {
        if (m_fd >= 0)
        {
            close(m_fd);
        }
    }

    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;

    int get() const
    {
        return m_fd;
    }
    bool ok() const
    {
        return m_fd >= 0;
    }

  private:
    int m_fd = -1;
};

void writerLoop()
{
    Fd fbFd("/dev/fb0", O_RDONLY | O_CLOEXEC);
    if (!fbFd.ok())
    {
        qWarning("native video writer: failed to open /dev/fb0");
        return;
    }

    fb_fix_screeninfo fixed = {};
    fb_var_screeninfo var = {};
    if (ioctl(fbFd.get(), FBIOGET_FSCREENINFO, &fixed) < 0 ||
        ioctl(fbFd.get(), FBIOGET_VSCREENINFO, &var) < 0)
    {
        qWarning("native video writer: failed to inspect /dev/fb0");
        return;
    }
    const size_t fbSize = fixed.smem_len != 0
                              ? fixed.smem_len
                              : static_cast<size_t>(fixed.line_length) * var.yres_virtual;
    if (!validateFramebufferWindow(fixed, var, fbSize))
    {
        return;
    }

    auto* fb = static_cast<uint8_t*>(mmap(nullptr, fbSize, PROT_READ, MAP_SHARED, fbFd.get(), 0));
    if (fb == MAP_FAILED)
    {
        qWarning("native video writer: failed to map /dev/fb0");
        return;
    }

    Fd memFd("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
    if (!memFd.ok())
    {
        munmap(fb, fbSize);
        qWarning("native video writer: failed to open /dev/mem");
        return;
    }

    auto* nativeBase =
        static_cast<volatile uint8_t*>(mmap(nullptr, kNativeVideoRegionSize, PROT_READ | PROT_WRITE,
                                            MAP_SHARED, memFd.get(), kNativeVideoBase));
    if (nativeBase == MAP_FAILED)
    {
        munmap(fb, fbSize);
        qWarning("native video writer: failed to map native video DDR");
        return;
    }

    memset(const_cast<uint8_t*>(nativeBase + kBuffer0Offset), 0, kOutputBytes);
    memset(const_cast<uint8_t*>(nativeBase + kBuffer1Offset), 0, kOutputBytes);
    *reinterpret_cast<volatile uint32_t*>(const_cast<uint8_t*>(nativeBase + kControlOffset)) = 0;

    qInfo("native video writer: copying top-left 320x240 RGB8888 from /dev/fb0 %ux%u to native DDR",
          var.xres, var.yres);

    uint32_t frame = 0;
    int active = 0;
    auto nextFrame = std::chrono::steady_clock::now();
    while (g_running.load(std::memory_order_relaxed))
    {
        if (ioctl(fbFd.get(), FBIOGET_VSCREENINFO, &var) < 0)
        {
            qWarning("native video writer: failed to refresh /dev/fb0 state");
            break;
        }
        if (!validateFramebufferWindow(fixed, var, fbSize))
        {
            break;
        }

        const auto* visible = fb + static_cast<size_t>(var.yoffset) * fixed.line_length +
                              static_cast<size_t>(var.xoffset) * kSourceBytesPerPixel;
        const size_t dstOffset = active == 0 ? kBuffer0Offset : kBuffer1Offset;
        const size_t dstAddress = kNativeVideoBase + dstOffset;
        auto* dst = const_cast<uint8_t*>(nativeBase + dstOffset);

        for (int y = 0; y < kOutputHeight; ++y)
        {
            const auto* srcRow = visible + static_cast<size_t>(y) * fixed.line_length;
            auto* dstRow = dst + static_cast<size_t>(y) * kOutputRowBytes;
            memcpy(dstRow, srcRow, kOutputRowBytes);
        }

        std::atomic_thread_fence(std::memory_order_seq_cst);
        ++frame;
        *reinterpret_cast<volatile uint32_t*>(const_cast<uint8_t*>(nativeBase + kControlOffset)) =
            (frame << 2) | static_cast<uint32_t>(active);
        if (frame % 59 == 0)
        {
            qInfo("Copying frame buffer content to 0x%08zx", dstAddress);
        }
        active ^= 1;

        nextFrame += std::chrono::microseconds(16667);
        std::this_thread::sleep_until(nextFrame);
    }

    *reinterpret_cast<volatile uint32_t*>(const_cast<uint8_t*>(nativeBase + kControlOffset)) = 0;
    munmap(const_cast<uint8_t*>(nativeBase), kNativeVideoRegionSize);
    munmap(fb, fbSize);
}

} // namespace

void startNativeVideoWriter()
{
    bool expected = false;
    if (!g_running.compare_exchange_strong(expected, true))
    {
        qInfo("native video writer: start requested but writer already running");
        return;
    }
    qInfo("native video writer: start requested, launching writer thread");
    g_thread = std::thread(writerLoop);
}

void stopNativeVideoWriter()
{
    qInfo("native video writer: stop requested");
    g_running.store(false);
    if (g_thread.joinable())
    {
        g_thread.join();
        qInfo("native video writer: writer thread joined");
    }
    else
    {
        qInfo("native video writer: no running thread to join");
    }
}

#else

#include <QLoggingCategory>

void startNativeVideoWriter()
{
    qInfo("native video writer: start requested on unsupported build/platform");
}
void stopNativeVideoWriter()
{
    qInfo("native video writer: stop requested on unsupported build/platform");
}

#endif
