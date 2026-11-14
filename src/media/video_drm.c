#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>

static enum AVPixelFormat select_drm(AVCodecContext *codec,
                                    const enum AVPixelFormat *formats)
{
    const enum AVPixelFormat *format;
    for (format = formats; *format != AV_PIX_FMT_NONE; ++format)
        if (*format == AV_PIX_FMT_DRM_PRIME && codec->hw_device_ctx)
            return *format;
    for (format = formats; *format != AV_PIX_FMT_NONE; ++format)
        if (sws_isSupportedInput(*format))
            return *format;
    return AV_PIX_FMT_NONE;
}

int usce_video_enable_drm(AVCodecContext *context, const AVCodec *codec)
{
    const AVCodecHWConfig *config;
    if (codec->id != AV_CODEC_ID_HEVC)
        return 0;
    for (int i = 0; (config = avcodec_get_hw_config(codec, i)); ++i) {
        if (config->pix_fmt != AV_PIX_FMT_DRM_PRIME ||
            config->device_type != AV_HWDEVICE_TYPE_DRM ||
            !(config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX))
            continue;
        if (av_hwdevice_ctx_create(&context->hw_device_ctx, AV_HWDEVICE_TYPE_DRM,
                                   NULL, NULL, 0) < 0)
            return 0;
        context->get_format = select_drm;
        return 1;
    }
    return 0;
}

int usce_video_transfer_drm(const AVFrame *source, AVFrame *target)
{
    if (source->format != AV_PIX_FMT_DRM_PRIME)
        return 0;
    av_frame_unref(target);
    target->format = AV_PIX_FMT_YUV420P;
    return av_hwframe_transfer_data(target, source, 0) < 0 ? -1 : 1;
}

struct SwsContext *usce_video_scaler(struct SwsContext *context,
                                   const AVFrame *frame, int width, int height,
                                   enum AVPixelFormat format)
{
    return sws_getCachedContext(context, frame->width, frame->height,
                                frame->format, width, height, format,
                                SWS_FAST_BILINEAR, NULL, NULL, NULL);
}
