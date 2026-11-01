// The browser side's view of a callback pointer (issue #13): emdawnwebgpu is C
// compiled by clang for wasm64 and calls WGPUBufferMapCallback through the
// function table with clang's wasm C ABI. This reproduces that call.
// Copied from ffi/include/webgpu/webgpu.h, which needs a hosted libc (math.h)
// that a freestanding wasm build doesn't have.
#include <stddef.h>
#include <stdint.h>
typedef struct WGPUStringView { char const *data; size_t length; } WGPUStringView;
typedef enum WGPUMapAsyncStatus { WGPUMapAsyncStatus_Success = 0x00000001 } WGPUMapAsyncStatus;
typedef void (*WGPUBufferMapCallback)(WGPUMapAsyncStatus status, WGPUStringView message,
                                      void *userdata1, void *userdata2);

__attribute__((export_name("call_int_cb")))
int call_int_cb(int (*cb)(int), int x) { return cb(x); }

__attribute__((export_name("call_map_cb")))
void call_map_cb(WGPUBufferMapCallback cb, void *userdata1) {
    WGPUStringView msg = { 0, 0 };
    cb(WGPUMapAsyncStatus_Success, msg, userdata1, 0);
}

// Where a callback's userdata1 points: a _MapResult-sized slot in wasm memory.
static uint32_t slot[4];

__attribute__((export_name("slot_addr")))
uint32_t *slot_addr(void) { return slot; }

__attribute__((export_name("slot_status")))
uint32_t slot_status(void) { return slot[0]; }
