#!/bin/bash
set -e
export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-/output}"
source /test/scripts/ssh-helpers.sh

echo "Capturing X display screenshot from the running desktop..."

echo "  Waiting for Chromium to settle..."
sleep 10

DISPLAY_SCREENSHOT=false
ssh_cmd "DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xwd -root -out /tmp/display.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true

if [ "$DISPLAY_SCREENSHOT" = false ]; then
    ssh_cmd "DISPLAY=:0 xwd -root -out /tmp/display.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true
fi

if [ "$DISPLAY_SCREENSHOT" = true ] && ssh_cmd "test -s /tmp/display.xwd" 2>/dev/null; then
    ssh_cmd "convert /tmp/display.xwd /tmp/display-screenshot.png 2>/dev/null || cp /tmp/display.xwd /tmp/display-screenshot.xwd" || true

    if ssh_cmd "test -f /tmp/display-screenshot.png" 2>/dev/null; then
        scp_cmd "pi@${E2E_SSH_HOST}:/tmp/display-screenshot.png" "$ARTIFACTS_DIR/screenshot.png"
        echo "Display screenshot saved (PNG)"
    elif ssh_cmd "test -f /tmp/display-screenshot.xwd" 2>/dev/null; then
        scp_cmd "pi@${E2E_SSH_HOST}:/tmp/display-screenshot.xwd" "$ARTIFACTS_DIR/screenshot.xwd"
        if command -v convert &>/dev/null; then
            convert "$ARTIFACTS_DIR/screenshot.xwd" "$ARTIFACTS_DIR/screenshot.png" 2>/dev/null && \
                rm -f "$ARTIFACTS_DIR/screenshot.xwd" && \
                echo "Display screenshot saved (converted to PNG on host)" || \
                echo "Display screenshot saved (XWD format)"
        else
            echo "Display screenshot saved (XWD format)"
        fi
    fi
else
    echo "  xwd capture failed, falling back to Chromium headless..."
    SCREENSHOT_URL="${SCREENSHOT_URL:-http://localhost/FullPageDashboard}"
    ssh_cmd "chromium --headless --disable-gpu --no-sandbox --screenshot=/tmp/chromium-screenshot.png --window-size=1280,720 '$SCREENSHOT_URL'" 2>/dev/null || true
    sleep 2
    if ssh_cmd "test -f /tmp/chromium-screenshot.png" 2>/dev/null; then
        scp_cmd "pi@${E2E_SSH_HOST}:/tmp/chromium-screenshot.png" "$ARTIFACTS_DIR/screenshot.png"
        echo "Chromium headless screenshot saved (fallback)"
    else
        echo "All screenshot methods failed"
        exit 1
    fi
fi
