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
#include <stdint.h>
#include <stddef.h>

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
void* wgpu_mojo_get_adapter_callback(void)   { return (void*)_wgpu_mojo_adapter_cb; }
void* wgpu_mojo_get_device_callback(void)    { return (void*)_wgpu_mojo_device_cb; }
void* wgpu_mojo_get_buffer_map_callback(void){ return (void*)_wgpu_mojo_buffer_map_cb; }
void* wgpu_mojo_get_queue_done_callback(void){ return (void*)_wgpu_mojo_queue_done_cb; }
void* wgpu_mojo_get_pop_error_callback(void) { return (void*)_wgpu_mojo_pop_error_cb; }
