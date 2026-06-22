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
typedef struct { uint32_t status; const WGPUCompilationInfo* info; } MojoCompilationResult;
typedef struct { uint32_t status; void* pipeline; } MojoComputePipelineAsyncResult;
typedef struct { uint32_t status; void* pipeline; } MojoRenderPipelineAsyncResult;

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

static void _wgpu_mojo_compilation_info_cb(
    WGPUCompilationInfoRequestStatus status,
    WGPUCompilationInfo const* info,
    void* ud1, void* ud2
) {
    MojoCompilationResult* r = (MojoCompilationResult*)ud1;
    if (r) {
        r->status = (uint32_t)status;
        r->info   = info;
    }
}

static void _wgpu_mojo_compute_pipeline_async_cb(
    WGPUCreatePipelineAsyncStatus status,
    WGPUComputePipeline pipeline,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoComputePipelineAsyncResult* r = (MojoComputePipelineAsyncResult*)ud1;
    if (r) { r->status = (uint32_t)status; r->pipeline = (void*)pipeline; }
}

static void _wgpu_mojo_render_pipeline_async_cb(
    WGPUCreatePipelineAsyncStatus status,
    WGPURenderPipeline pipeline,
    WGPUStringView message,
    void* ud1, void* ud2
) {
    MojoRenderPipelineAsyncResult* r = (MojoRenderPipelineAsyncResult*)ud1;
    if (r) { r->status = (uint32_t)status; r->pipeline = (void*)pipeline; }
}

/* Public getter functions — Mojo calls these to obtain function pointers */
void* wgpu_mojo_get_adapter_callback(void)          { return (void*)_wgpu_mojo_adapter_cb; }
void* wgpu_mojo_get_device_callback(void)           { return (void*)_wgpu_mojo_device_cb; }
void* wgpu_mojo_get_buffer_map_callback(void)       { return (void*)_wgpu_mojo_buffer_map_cb; }
void* wgpu_mojo_get_queue_done_callback(void)       { return (void*)_wgpu_mojo_queue_done_cb; }
void* wgpu_mojo_get_pop_error_callback(void)        { return (void*)_wgpu_mojo_pop_error_cb; }
void* wgpu_mojo_get_compilation_info_callback(void)         { return (void*)_wgpu_mojo_compilation_info_cb; }
void* wgpu_mojo_get_compute_pipeline_async_callback(void)   { return (void*)_wgpu_mojo_compute_pipeline_async_cb; }
void* wgpu_mojo_get_render_pipeline_async_callback(void)    { return (void*)_wgpu_mojo_render_pipeline_async_cb; }


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

WGPUFuture wgpu_mojo_shader_get_compilation_info(
    WGPUShaderModule module,
    const WGPUCompilationInfoCallbackInfo* cb_info
) {
    return wgpuShaderModuleGetCompilationInfo(module, *cb_info);
}

WGPUFuture wgpu_mojo_device_create_compute_pipeline_async(
    WGPUDevice device,
    const WGPUComputePipelineDescriptor* descriptor,
    const WGPUCreateComputePipelineAsyncCallbackInfo* cb_info
) {
    return wgpuDeviceCreateComputePipelineAsync(device, descriptor, *cb_info);
}

WGPUFuture wgpu_mojo_device_create_render_pipeline_async(
    WGPUDevice device,
    const WGPURenderPipelineDescriptor* descriptor,
    const WGPUCreateRenderPipelineAsyncCallbackInfo* cb_info
) {
    return wgpuDeviceCreateRenderPipelineAsync(device, descriptor, *cb_info);
}

void wgpu_mojo_surface_capabilities_free_members(
    const WGPUSurfaceCapabilities* caps
) {
    wgpuSurfaceCapabilitiesFreeMembers(*caps);
}
