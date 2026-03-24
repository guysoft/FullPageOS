#!/bin/bash
set -e

HOST="${1:-localhost}"
PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-}"
USER="pi"
PASS="raspberry"

SSH_CMD="sshpass -p $PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o LogLevel=ERROR -p $PORT ${USER}@${HOST}"

echo "Test: Chromium is displaying FullPageDashboard"

# 1. Verify the Chromium kiosk process is running
echo "  Checking for Chromium kiosk process..."
CHROMIUM_FOUND=0
for i in $(seq 1 60); do
    PGREP=$($SSH_CMD "pgrep -f 'chromium.*--kiosk' || true" 2>/dev/null)
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
    $SSH_CMD "ps aux" 2>/dev/null | tail -20
    exit 1
fi
echo "  Chromium kiosk running (pid: $PGREP)"

# 2. Verify the X display is active and Chromium has a visible window
echo "  Checking X display window title..."
WINDOW_TITLE=$($SSH_CMD "DISPLAY=:0 xdotool search --onlyvisible --name . getwindowname 2>/dev/null || true" 2>/dev/null)

if [ -n "$ARTIFACTS_DIR" ]; then
    $SSH_CMD "ps aux | grep -i chromium" > "$ARTIFACTS_DIR/chromium-processes.txt" 2>/dev/null || true
    echo "$WINDOW_TITLE" > "$ARTIFACTS_DIR/window-title.txt" 2>/dev/null || true
fi

if [ -z "$WINDOW_TITLE" ]; then
    echo "  No windows found with --onlyvisible, trying without visibility filter..."
    WINDOW_TITLE=$($SSH_CMD "DISPLAY=:0 xdotool search --name . getwindowname 2>&1 || true" 2>/dev/null)
    if [ -n "$ARTIFACTS_DIR" ]; then
        echo "$WINDOW_TITLE" > "$ARTIFACTS_DIR/window-title.txt" 2>/dev/null || true
    fi
fi

if [ -z "$WINDOW_TITLE" ]; then
    echo "  Diagnosing X display access..."
    $SSH_CMD "DISPLAY=:0 xdpyinfo 2>&1 | head -5 || echo 'xdpyinfo failed'" 2>/dev/null || true
    $SSH_CMD "DISPLAY=:0 xdotool search --name . 2>&1 || echo 'xdotool search failed'" 2>/dev/null || true
    echo "  FAIL: No window on X display (display pipeline not working)"
    exit 1
fi

echo "  Window title: '$WINDOW_TITLE'"

# 3. Verify the window title matches the expected FullPageDashboard page
if echo "$WINDOW_TITLE" | grep -qi "Full Page Dashboard\|FullPageDashboard\|FullPageOS"; then
    echo "  PASS: Chromium is displaying FullPageDashboard on the screen"
    exit 0
else
    echo "  FAIL: Window title '$WINDOW_TITLE' does not match expected FullPageDashboard"
    exit 1
fi
