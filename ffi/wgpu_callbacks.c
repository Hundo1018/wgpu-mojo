/**
 * ffi/wgpu_callbacks.c — wgpu-native log bridge for the Mojo bindings.
 *
 * Until Mojo 1.1.0 this file also held the async completion callbacks
 * (adapter, device, buffer map, queue done, error scope) and pointer-taking
 * wrappers for every entry point that takes a struct by value. Those are pure
 * Mojo now: wgpu/_backend/wgpu_native/callbacks.mojo.
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


/* ---------------------------------------------------------------------------
 * Log bridge.
 *
 * Why this one is still C (re-checked on Mojo 1.1.0): the log callback is
 * process-wide and wgpu-native calls it from its own threads, so the queue it
 * feeds must be reachable without userdata from whichever thread drains it.
 * That needs a global, and Mojo 1.1.0 rejects module-level variables
 * ("global variables are not supported"). A stored Mojo function pointer is
 * no longer the obstacle — see callbacks.mojo.
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
