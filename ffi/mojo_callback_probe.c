#include <stdint.h>

// Minimal ABI probe for Mojo def callback interoperability.
typedef int64_t (*mojo_probe_cb_t)(int64_t);

int64_t mojo_probe_invoke(mojo_probe_cb_t cb, int64_t value) {
    if (cb == 0) {
        return -1;
    }
    return cb(value);
}
