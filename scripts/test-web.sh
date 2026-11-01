#!/bin/bash
# Run build/web/test.html in headless Firefox and Chrome (#14).
#
# The page draws the clear + triangle app on a canvas and checks its pixels
# (both as shown on the canvas and through the frame-capture hook), sends a DOM
# mouse event through to InputState, and runs the compute example's
# non-blocking read-back. It reports PASS/FAIL in document.title.
#
#   Firefox  (geckodriver, scripts/web_firefox.mjs)  every check
#   Chrome   (DevTools protocol, scripts/web_cdp.mjs) every check but the pixel
#            ones: headless Chrome destroys the device after a canvas draw.
# Each browser is skipped if not installed; at least one must run. Node >= 22.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f build/web/test.html ] || { echo "test-web: run 'pixi run build-web' first" >&2; exit 1; }

PORT="${PORT:-8765}"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web > /dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
for _ in $(seq 50); do curl -sf "http://127.0.0.1:$PORT/test.html" > /dev/null && break; sleep 0.1; done
URL="http://127.0.0.1:$PORT/test.html"

ran=0 failed=0
GECKO="${GECKODRIVER:-$(command -v geckodriver || command -v firefox.geckodriver || true)}"
if [ -n "$GECKO" ]; then
  ran=1
  node scripts/web_firefox.mjs "$GECKO" "$URL" 120 || failed=1
fi
CHROME="${CHROME:-$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || true)}"
if [ -n "$CHROME" ]; then
  ran=1
  "$CHROME" --version
  node scripts/web_cdp.mjs "$CHROME" "$URL?canvas-lost" 120 || failed=1
fi
[ "$ran" = 1 ] || { echo "test-web: neither Firefox (geckodriver) nor Chrome found" >&2; exit 1; }
exit "$failed"
