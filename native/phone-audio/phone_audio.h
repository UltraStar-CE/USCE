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
USCE_PA int32_t usce_pa_status(void *context, char *json, int32_t capacity);
// Optional external signaling: create with "ipc://". Bounded queues, no socket.
USCE_PA int32_t usce_pa_signal(void *context, const char *json);
USCE_PA int32_t usce_pa_event(void *context, char *json, int32_t capacity);
#ifdef __cplusplus
}
#endif
