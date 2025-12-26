#include <stdint.h>

// Minimal ABI probe for Mojo def callback interoperability.
typedef int64_t (*mojo_probe_cb_t)(int64_t);

int64_t mojo_probe_invoke(mojo_probe_cb_t cb, int64_t value) {
    if (cb == 0) {
        return -1;
    }
    return cb(value);
}

// ---------------------------------------------------------------
// Phase 4 extended probes: struct-parameter callbacks
// ---------------------------------------------------------------

// WGPUStringView-equivalent (16 bytes: ptr + size_t)
typedef struct {
    const char* data;
    uint64_t    length;
} StringView16;

// Two-field result struct (16 bytes)
typedef struct {
    uint64_t handle;
    uint32_t status;
} AdapterResult;

// Probe 1: callback receives a 16-byte struct by value
// Mimics simplified wgpu adapter callback:
//   void(uint32_t status, void* adapter, StringView16 message, void* ud1, void* ud2)
typedef void (*mojo_adapter_like_cb)(uint32_t status, void* adapter,
                                      StringView16 message,
                                      void* ud1, void* ud2);

void mojo_probe_adapter_callback(mojo_adapter_like_cb cb) {
    if (cb == 0) return;
    StringView16 msg = { "hello", 5 };
    AdapterResult result = { 0, 0 };
    // Call the Mojo callback exactly like wgpu would
    cb(42,                          // status
       (void*)(uintptr_t)0xBEEF,   // adapter handle
       msg,                         // 16-byte struct by value
       (void*)&result,              // userdata1
       (void*)0);                   // userdata2
    // After callback, result should be filled
}

// Probe 2: callback receives only scalar args (decomposed StringView)
typedef void (*mojo_scalar_cb)(uint32_t status, void* adapter,
                                const char* msg_data, uint64_t msg_len,
                                void* ud1, void* ud2);

void mojo_probe_scalar_callback(mojo_scalar_cb cb) {
    if (cb == 0) return;
    AdapterResult result = { 0, 0 };
    cb(42, (void*)(uintptr_t)0xBEEF, "hello", 5, (void*)&result, (void*)0);
}

// Probe 3: return the result from C side for Mojo to verify
// This calls the callback and returns the result struct
uint64_t mojo_probe_adapter_result_handle(mojo_adapter_like_cb cb) {
    AdapterResult result = { 0, 0 };
    StringView16 msg = { "hello", 5 };
    cb(42, (void*)(uintptr_t)0xBEEF, msg, (void*)&result, (void*)0);
    return result.handle;
}

uint32_t mojo_probe_adapter_result_status(mojo_adapter_like_cb cb) {
    AdapterResult result = { 0, 0 };
    StringView16 msg = { "hello", 5 };
    cb(42, (void*)(uintptr_t)0xBEEF, msg, (void*)&result, (void*)0);
    return result.status;
}

uint64_t mojo_probe_scalar_result_handle(mojo_scalar_cb cb) {
    AdapterResult result = { 0, 0 };
    cb(42, (void*)(uintptr_t)0xBEEF, "hello", 5, (void*)&result, (void*)0);
    return result.handle;
}

uint32_t mojo_probe_scalar_result_status(mojo_scalar_cb cb) {
    AdapterResult result = { 0, 0 };
    cb(42, (void*)(uintptr_t)0xBEEF, "hello", 5, (void*)&result, (void*)0);
    return result.status;
}

// Probe 4: accept a raw function pointer (void*) and invoke it as a callback
// This tests if we can pass a Mojo def as an OpaquePtr and C can invoke it
uint64_t mojo_probe_invoke_raw_fnptr(void* fnptr) {
    if (fnptr == 0) return 0xDEAD;
    mojo_adapter_like_cb cb = (mojo_adapter_like_cb)fnptr;
    AdapterResult result = { 0, 0 };
    StringView16 msg = { "test", 4 };
    cb(99, (void*)(uintptr_t)0xCAFE, msg, (void*)&result, (void*)0);
    return result.handle;
}
