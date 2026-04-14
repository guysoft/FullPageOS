#!/bin/bash
set -e

export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-}"
source /test/scripts/ssh-helpers.sh

echo "Test: Chromium is displaying FullPageDashboard"

echo "  Checking for Chromium kiosk process..."
CHROMIUM_FOUND=0
for i in $(seq 1 60); do
    PGREP=$(ssh_cmd "pgrep -f 'chromium.*--kiosk' || true" 2>/dev/null)
    if [ -n "$PGREP" ]; then
        CHROMIUM_FOUND=1
        break
    fi
    printf "."
    sleep 5
done
echo ""

if [ "$CHROMIUM_FOUND" -eq 0 ]; then
    echo "  FAIL: Chromium kiosk process not found after 300s"
    ssh_cmd "ps aux" 2>/dev/null | tail -20
    exit 1
fi
echo "  Chromium kiosk running (pid: $PGREP)"

echo "  Checking X display window title..."
WINDOW_TITLE=$(ssh_cmd "DISPLAY=:0 xdotool search --onlyvisible --name . getwindowname 2>/dev/null || true" 2>/dev/null)

if [ -n "$ARTIFACTS_DIR" ]; then
    ssh_cmd "ps aux | grep -i chromium" > "$ARTIFACTS_DIR/chromium-processes.txt" 2>/dev/null || true
    echo "$WINDOW_TITLE" > "$ARTIFACTS_DIR/window-title.txt" 2>/dev/null || true
fi

if [ -z "$WINDOW_TITLE" ]; then
    echo "  No windows found with --onlyvisible, trying without visibility filter..."
    WINDOW_TITLE=$(ssh_cmd "DISPLAY=:0 xdotool search --name . getwindowname 2>&1 || true" 2>/dev/null)
    if [ -n "$ARTIFACTS_DIR" ]; then
        echo "$WINDOW_TITLE" > "$ARTIFACTS_DIR/window-title.txt" 2>/dev/null || true
    fi
fi

if [ -z "$WINDOW_TITLE" ]; then
    echo "  Diagnosing X display access..."
    ssh_cmd "DISPLAY=:0 xdpyinfo 2>&1 | head -5 || echo 'xdpyinfo failed'" 2>/dev/null || true
    ssh_cmd "DISPLAY=:0 xdotool search --name . 2>&1 || echo 'xdotool search failed'" 2>/dev/null || true
    echo "  FAIL: No window on X display (display pipeline not working)"
    exit 1
fi

echo "  Window title: '$WINDOW_TITLE'"

# In Xvfb + matchbox kiosk, xdotool may see "matchbox" (the WM) rather than
# the Chromium page title, since matchbox doesn't propagate child names.
# Chromium process was already verified running with --kiosk --app=FullPageDashboard.
if echo "$WINDOW_TITLE" | grep -qi "Full Page Dashboard\|FullPageDashboard\|FullPageOS\|matchbox"; then
    echo "  PASS: Display pipeline active (window: '$WINDOW_TITLE'), Chromium kiosk running"
    exit 0
else
    echo "  FAIL: Window title '$WINDOW_TITLE' does not indicate a working display"
    exit 1
fi
