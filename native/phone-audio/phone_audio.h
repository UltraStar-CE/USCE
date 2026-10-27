#pragma once
#include <stdint.h>
#ifdef _WIN32
#ifdef USCE_PHONE_AUDIO_BUILD
#define USCE_PA __declspec(dllexport)
#else
#define USCE_PA __declspec(dllimport)
#endif
#else
#define USCE_PA __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// ABI v1: opaque context, fixed-width scalars, caller-owned UTF-8 / PCM buffers.
USCE_PA int32_t usce_pa_version(void);
USCE_PA void *usce_pa_create(const char *relay_url, const char *ice_server);
USCE_PA void usce_pa_destroy(void *context);
// Called on the game thread. Performs signaling, drains fresh mono S16/48k PCM.
USCE_PA int32_t usce_pa_poll(void *context, int16_t *samples, int32_t capacity);
// Separate digital test input. These samples must never enter singing/scoring.
USCE_PA int32_t usce_pa_poll_calibration(void *context, int16_t *samples, int32_t capacity);
USCE_PA int32_t usce_pa_status(void *context, char *json, int32_t capacity);
// Optional external signaling: create with "ipc://". Bounded queues, no socket.
USCE_PA int32_t usce_pa_signal(void *context, const char *json);
USCE_PA int32_t usce_pa_event(void *context, char *json, int32_t capacity);
// Independent text WebSocket for the Pascal relay client. TLS verification is
// enabled by libdatachannel. No room/game logic runs in native callbacks.
USCE_PA void *usce_relay_create(const char *url);
USCE_PA void usce_relay_destroy(void *context);
// 0 connecting, 1 open, 2 closed, 3 failed (including receive overflow).
USCE_PA int32_t usce_relay_state(void *context);
// UTF-8 text <= 1 MiB. 1 accepted, 0 backpressure/not open, -1 invalid/error.
USCE_PA int32_t usce_relay_send(void *context, const char *text);
// Returns bytes, 0 empty, -1 invalid/error, -2 caller buffer too small.
// A short buffer does not consume the message. Text is NUL-terminated.
USCE_PA int32_t usce_relay_receive(void *context, char *text, int32_t capacity);
#ifdef __cplusplus
}
#endif
