#include "CameraPortal.hpp"

#include <gio/gunixfdlist.h>
#include <gst/video/video.h>
#include <unistd.h>

namespace {
constexpr auto desktop = "org.freedesktop.portal.Desktop";
constexpr auto desktopPath = "/org/freedesktop/portal/desktop";
constexpr auto camera = "org.freedesktop.portal.Camera";
constexpr auto request = "org.freedesktop.portal.Request";

GVariant *cameraOptions(const char *token = nullptr)
{
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    if (token)
        g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token));
    return g_variant_new("(a{sv})", &options);
}
}

int CameraPortal::requestAccess()
{
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, cancellable, nullptr);
    if (!bus)
        return -1;

    GMainContext *context = g_main_context_new();
    g_main_context_push_thread_default(context);
    gchar *sender = g_strdup(g_dbus_connection_get_unique_name(bus) + 1);
    g_strdelimit(sender, ".", '_');
    gchar *token = g_strdup_printf("usce_%08x_%08x", g_random_int(), g_random_int());
    gchar *path = g_strdup_printf("/org/freedesktop/portal/desktop/request/%s/%s", sender, token);
    int response = -1;
    guint subscription = g_dbus_connection_signal_subscribe(bus, desktop, request, "Response",
        path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, const gchar *, const gchar *,
           GVariant *values, gpointer data) {
            guint32 status;
            g_variant_get_child(values, 0, "u", &status);
            *static_cast<int *>(data) = status;
        }, &response, nullptr);
    GVariant *handle = g_dbus_connection_call_sync(bus, desktop, desktopPath, camera,
        "AccessCamera", cameraOptions(token), G_VARIANT_TYPE("(o)"),
        G_DBUS_CALL_FLAGS_NONE, 5000, cancellable, nullptr);

    bool requestOpen = false;
    if (handle) {
        const gchar *actualPath;
        g_variant_get(handle, "(&o)", &actualPath);
        requestOpen = g_str_equal(path, actualPath);
    }
    const gint64 deadline = g_get_monotonic_time() + 120 * G_TIME_SPAN_SECOND;
    while (requestOpen && response < 0 && !g_cancellable_is_cancelled(cancellable) &&
           g_get_monotonic_time() < deadline) {
        if (!g_main_context_iteration(context, FALSE))
            g_usleep(20000);
    }
    if (response < 0 && (requestOpen || g_cancellable_is_cancelled(cancellable))) {
        GVariant *closed = g_dbus_connection_call_sync(bus, desktop, path, request, "Close",
            nullptr, nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, nullptr, nullptr);
        g_clear_pointer(&closed, g_variant_unref);
    }
    g_dbus_connection_signal_unsubscribe(bus, subscription);
    g_main_context_pop_thread_default(context);
    g_main_context_unref(context);
    g_clear_pointer(&handle, g_variant_unref);
    g_free(path);
    g_free(token);
    g_free(sender);

    int remote = -1;
    if (response == 1)
        failure = Failure::Permission;
    if (response == 0 && !g_cancellable_is_cancelled(cancellable)) {
        GUnixFDList *fds = nullptr;
        GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(bus, desktop,
            desktopPath, camera, "OpenPipeWireRemote", cameraOptions(), G_VARIANT_TYPE("(h)"),
            G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &fds, cancellable, nullptr);
        if (reply && fds) {
            gint descriptor;
            g_variant_get(reply, "(h)", &descriptor);
            if (descriptor >= 0 && descriptor < g_unix_fd_list_get_length(fds))
                remote = g_unix_fd_list_get(fds, descriptor, nullptr);
        }
        g_clear_pointer(&reply, g_variant_unref);
        g_clear_object(&fds);
    }
    g_object_unref(bus);
    return remote;
}

CameraPortal::~CameraPortal()
{
    if (pipeline)
        gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_clear_object(&sink);
    gst_clear_object(&pipeline);
    if (fd >= 0)
        close(fd);
    g_object_unref(cancellable);
}

bool CameraPortal::start(int index)
{
    if (!gst_init_check(nullptr, nullptr, nullptr))
        return false;

    GstDeviceProvider *provider = gst_device_provider_factory_get_by_name("pipewiredeviceprovider");
    if (!provider)
        return false;

    fd = requestAccess();
    if (fd < 0) {
        gst_object_unref(provider);
        return false;
    }

    g_object_set(provider, "fd", fd, nullptr);
    GstElement *source = nullptr;
    const char *input = nullptr;
    bool started = gst_device_provider_start(provider);
    if (started) {
        GList *devices = gst_device_provider_get_devices(provider);
        for (GList *entry = devices; entry; entry = entry->next) {
            auto *device = GST_DEVICE(entry->data);
            if (gst_device_has_classes(device, "Video/Source") && index-- == 0) {
                GstCaps *formats = gst_device_get_caps(device);
                GstCaps *raw = gst_caps_new_empty_simple("video/x-raw");
                GstCaps *jpeg = gst_caps_new_empty_simple("image/jpeg");
                if (!formats || gst_caps_can_intersect(formats, raw))
                    input = "capsfilter caps=video/x-raw";
                else if (gst_caps_can_intersect(formats, jpeg))
                    input = "capsfilter caps=image/jpeg ! jpegdec";
                gst_caps_unref(jpeg);
                gst_caps_unref(raw);
                gst_clear_caps(&formats);
                if (input)
                    source = gst_device_create_element(device, nullptr);
                break;
            }
        }
        g_list_free_full(devices, gst_object_unref);
    }

    bool playing = false;
    if (source && !g_cancellable_is_cancelled(cancellable)) {
        gchar *description = g_strdup_printf(
            "%s ! videoconvert ! videoscale ! video/x-raw,format=BGR,width=%d,height=%d "
            "! appsink name=frames max-buffers=1 drop=true sync=false async=false", input, width, height);
        GError *error = nullptr;
        GstElement *output = gst_parse_bin_from_description(description, TRUE, &error);
        g_free(description);
        if (output && !error) {
            pipeline = gst_pipeline_new(nullptr);
            sink = GST_APP_SINK(gst_bin_get_by_name(GST_BIN(output), "frames"));
            gst_bin_add_many(GST_BIN(pipeline), source, output, nullptr);
            playing = sink && gst_element_link(source, output) &&
                gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE;
            source = nullptr;
        } else {
            gst_clear_object(&output);
        }
        g_clear_error(&error);
    }
    gst_clear_object(&source);
    if (started)
        gst_device_provider_stop(provider);
    gst_object_unref(provider);
    firstFrameDeadline = g_get_monotonic_time() + 10 * G_TIME_SPAN_SECOND;
    return playing;
}

bool CameraPortal::read(int index, cv::UMat &frame)
{
    if (error() != Failure::None || g_cancellable_is_cancelled(cancellable))
        return false;
    if (!pipeline && !start(index)) {
        if (error() == Failure::None)
            failure = Failure::Capture;
        return false;
    }

    GstBus *bus = gst_element_get_bus(pipeline);
    GstMessage *message = gst_bus_pop_filtered(bus, GstMessageType(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
    gst_object_unref(bus);
    if (message) {
        gst_message_unref(message);
        failure = Failure::Capture;
        return false;
    }

    GstSample *sample = gst_app_sink_try_pull_sample(sink, 0);
    if (!sample) {
        if (firstFrameDeadline && g_get_monotonic_time() >= firstFrameDeadline)
            failure = Failure::Capture;
        return false;
    }

    GstVideoInfo info;
    GstVideoFrame video;
    bool received = gst_video_info_from_caps(&info, gst_sample_get_caps(sample)) &&
                    gst_video_frame_map(&video, &info, gst_sample_get_buffer(sample), GST_MAP_READ);
    if (received) {
        const int stride = GST_VIDEO_FRAME_PLANE_STRIDE(&video, 0);
        try {
            if (stride <= 0)
                received = false;
            else
                cv::Mat(info.height, info.width, CV_8UC3, GST_VIDEO_FRAME_PLANE_DATA(&video, 0),
                        stride).copyTo(frame);
        } catch (...) {
            received = false;
        }
        gst_video_frame_unmap(&video);
    }
    gst_sample_unref(sample);
    if (received)
        firstFrameDeadline = 0;
    else if (firstFrameDeadline && g_get_monotonic_time() >= firstFrameDeadline)
        failure = Failure::Capture;
    return received;
}
