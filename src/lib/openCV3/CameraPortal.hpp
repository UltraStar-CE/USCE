#pragma once

#include <atomic>
#include <gio/gio.h>
#include <gst/app/gstappsink.h>
#include <opencv2/core.hpp>

class CameraPortal {
public:
    CameraPortal() = default;
    ~CameraPortal();
    CameraPortal(const CameraPortal &) = delete;
    CameraPortal &operator=(const CameraPortal &) = delete;

    void cancel() { g_cancellable_cancel(cancellable); }
    bool failed() const { return failure.load(); }
    bool read(int index, cv::UMat &frame);
    int width = 0;
    int height = 0;

private:
    bool start(int index);
    int requestAccess();

    GCancellable *cancellable = g_cancellable_new();
    GstElement *pipeline = nullptr;
    GstAppSink *sink = nullptr;
    int fd = -1;
    gint64 firstFrameDeadline = 0;
    std::atomic<bool> failure{false};
};
