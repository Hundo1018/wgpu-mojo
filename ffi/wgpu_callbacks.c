/**
 * ffi/wgpu_callbacks.c — Callback bridge helpers for Mojo wgpu bindings.
 *
 * Provides C function pointers that Mojo can retrieve and pass to wgpu-native's
 * async APIs. Results are written through userdata1 pointers.
 *
 * Build:  gcc -shared -fPIC -o ffi/lib/libwgpu_mojo_cb.so ffi/wgpu_callbacks.c \
 *              -Iffi/include
 */
#include "include/webgpu/webgpu.h"
#include "include/webgpu/wgpu.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <pthread.h>

/* Struct mirrors: must match layout in wgpu/_ffi/lib.mojo */
typedef struct { void* adapter; uint32_t status; } MojoAdapterResult;
typedef struct { void* device;  uint32_t status; } MojoDeviceResult;
typedef struct { uint32_t status; }               MojoMapResult;
typedef struct { uint32_t status; }               MojoWorkDoneResult;
typedef struct { uint32_t status; uint32_t type; void* message_data; size_t message_len; } MojoPopErrorResult;

static void _wgpu_mojo_adapter_cb(
    WGPURequestAdapterStatus status,
    WGPUAdapter adapter,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoAdapterResult* r = (MojoAdapterResult*)ud1;
    if (r) { r->adapter = (void*)adapter; r->status = (uint32_t)status; }
}

static void _wgpu_mojo_device_cb(
    WGPURequestDeviceStatus status,
    WGPUDevice device,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoDeviceResult* r = (MojoDeviceResult*)ud1;
    if (r) { r->device = (void*)device; r->status = (uint32_t)status; }
}

static void _wgpu_mojo_buffer_map_cb(
    WGPUMapAsyncStatus status,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoMapResult* r = (MojoMapResult*)ud1;
    if (r) { r->status = (uint32_t)status; }
}

static void _wgpu_mojo_queue_done_cb(
    WGPUQueueWorkDoneStatus status,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoWorkDoneResult* r = (MojoWorkDoneResult*)ud1;
    if (r) { r->status = (uint32_t)status; }
}

static void _wgpu_mojo_pop_error_cb(
    WGPUPopErrorScopeStatus status,
    WGPUErrorType type,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoPopErrorResult* r = (MojoPopErrorResult*)ud1;
    if (r) {
        r->status = (uint32_t)status;
        r->type = (uint32_t)type;
        r->message_data = (void*)message.data;
        r->message_len = message.length;
    }
}

/* Public getter functions — Mojo calls these to obtain function pointers */
void* wgpu_mojo_get_adapter_callback(void)          { return (void*)_wgpu_mojo_adapter_cb; }
void* wgpu_mojo_get_device_callback(void)           { return (void*)_wgpu_mojo_device_cb; }
void* wgpu_mojo_get_buffer_map_callback(void)       { return (void*)_wgpu_mojo_buffer_map_cb; }
void* wgpu_mojo_get_queue_done_callback(void)       { return (void*)_wgpu_mojo_queue_done_cb; }
void* wgpu_mojo_get_pop_error_callback(void)        { return (void*)_wgpu_mojo_pop_error_cb; }


WGPUFuture wgpu_mojo_instance_request_adapter(
    WGPUInstance instance,
    const WGPURequestAdapterOptions* options,
    const WGPURequestAdapterCallbackInfo* cb_info
) {
    return wgpuInstanceRequestAdapter(instance, options, *cb_info);
}

WGPUFuture wgpu_mojo_adapter_request_device(
    WGPUAdapter adapter,
    const WGPUDeviceDescriptor* descriptor,
    const WGPURequestDeviceCallbackInfo* cb_info
) {
    return wgpuAdapterRequestDevice(adapter, descriptor, *cb_info);
}

WGPUFuture wgpu_mojo_buffer_map_async(
    WGPUBuffer buffer,
    WGPUMapMode mode,
    size_t offset,
    size_t size,
    const WGPUBufferMapCallbackInfo* cb_info
) {
    return wgpuBufferMapAsync(buffer, mode, offset, size, *cb_info);
}

WGPUFuture wgpu_mojo_queue_on_submitted_work_done(
    WGPUQueue queue,
    const WGPUQueueWorkDoneCallbackInfo* cb_info
) {
    return wgpuQueueOnSubmittedWorkDone(queue, *cb_info);
}

WGPUFuture wgpu_mojo_device_pop_error_scope(
    WGPUDevice device,
    const WGPUPopErrorScopeCallbackInfo* cb_info
) {
    return wgpuDevicePopErrorScope(device, *cb_info);
}

void wgpu_mojo_surface_capabilities_free_members(
    const WGPUSurfaceCapabilities* caps
) {
    wgpuSurfaceCapabilitiesFreeMembers(*caps);
}


/* ---------------------------------------------------------------------------
 * Log bridge.
 *
 * wgpuSetLogCallback takes a stored C function pointer, which Mojo cannot
 * produce (see tests/abi_probes and tests/test_callback_abi.mojo). wgpu-native
 * also calls it from its own threads, at arbitrary times, so the message cannot
 * be handed straight to Mojo.
 *
 * Instead the callback appends into a fixed-size ring buffer under a mutex, and
 * Mojo drains it with wgpu_mojo_log_take(). Oldest messages are dropped when the
 * ring is full — a dropped-message count is reported so callers can tell.
 * ------------------------------------------------------------------------- */

#define MOJO_LOG_SLOTS 256
#define MOJO_LOG_MSG_CAP 512

typedef struct { uint32_t level; uint32_t len; char text[MOJO_LOG_MSG_CAP]; } MojoLogSlot;

static MojoLogSlot     _mojo_log_ring[MOJO_LOG_SLOTS];
static size_t          _mojo_log_head = 0;   /* next write */
static size_t          _mojo_log_tail = 0;   /* next read  */
static uint64_t        _mojo_log_dropped = 0;
static pthread_mutex_t _mojo_log_lock = PTHREAD_MUTEX_INITIALIZER;

static void _wgpu_mojo_log_cb(WGPULogLevel level, WGPUStringView message, void* userdata) {
    (void)userdata;
    size_t n = message.length;
    /* WGPU_STRLEN means "NUL-terminated, length not supplied". */
    if (n == WGPU_STRLEN) n = message.data ? strlen(message.data) : 0;
    if (n > MOJO_LOG_MSG_CAP - 1) n = MOJO_LOG_MSG_CAP - 1;

    pthread_mutex_lock(&_mojo_log_lock);
    size_t next = (_mojo_log_head + 1) % MOJO_LOG_SLOTS;
    if (next == _mojo_log_tail) {          /* full: drop the oldest */
        _mojo_log_tail = (_mojo_log_tail + 1) % MOJO_LOG_SLOTS;
        _mojo_log_dropped++;
    }
    MojoLogSlot* slot = &_mojo_log_ring[_mojo_log_head];
    slot->level = (uint32_t)level;
    slot->len   = (uint32_t)n;
    if (n && message.data) memcpy(slot->text, message.data, n);
    slot->text[n] = 0;
    _mojo_log_head = next;
    pthread_mutex_unlock(&_mojo_log_lock);
}

/* Install the ring-buffer callback. */
void wgpu_mojo_log_install(void) {
    wgpuSetLogCallback(_wgpu_mojo_log_cb, NULL);
}

/* Pop one message. Returns its byte length, or -1 when the ring is empty.
 * `out` receives the text (NUL-terminated), `out_level` the WGPULogLevel. */
int32_t wgpu_mojo_log_take(char* out, size_t cap, uint32_t* out_level) {
    int32_t written = -1;
    pthread_mutex_lock(&_mojo_log_lock);
    if (_mojo_log_tail != _mojo_log_head) {
        MojoLogSlot* slot = &_mojo_log_ring[_mojo_log_tail];
        size_t n = slot->len;
        if (cap == 0) { n = 0; }
        else if (n > cap - 1) { n = cap - 1; }
        if (out) { if (n) memcpy(out, slot->text, n); out[n] = 0; }
        if (out_level) *out_level = slot->level;
        _mojo_log_tail = (_mojo_log_tail + 1) % MOJO_LOG_SLOTS;
        written = (int32_t)n;
    }
    pthread_mutex_unlock(&_mojo_log_lock);
    return written;
}

/* Number of messages dropped because the ring was full. */
uint64_t wgpu_mojo_log_dropped(void) {
    pthread_mutex_lock(&_mojo_log_lock);
    uint64_t d = _mojo_log_dropped;
    pthread_mutex_unlock(&_mojo_log_lock);
    return d;
}
