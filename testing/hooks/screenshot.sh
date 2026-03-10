#!/bin/bash
set -e
SSH_HOST="${1:-localhost}"
SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-/output}"

SSH_CMD="sshpass -p raspberry ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT pi@$SSH_HOST"
SCP_CMD="sshpass -p raspberry scp -o StrictHostKeyChecking=no -P $SSH_PORT"

echo "Capturing X display screenshot from the running desktop..."

# Wait for Chromium to be rendering on the display (give the page time to load)
echo "  Waiting for Chromium to settle..."
sleep 10

# Capture the actual X display using xwd (part of x11-apps, installed with xterm)
DISPLAY_SCREENSHOT=false
$SSH_CMD "DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xwd -root -out /tmp/display.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true

if [ "$DISPLAY_SCREENSHOT" = false ]; then
    # Try alternative Xauthority paths
    $SSH_CMD "DISPLAY=:0 xwd -root -out /tmp/display.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true
fi

if [ "$DISPLAY_SCREENSHOT" = true ] && $SSH_CMD "test -s /tmp/display.xwd" 2>/dev/null; then
    # Convert xwd to png inside the guest (ImageMagick's convert may not be there, try import)
    $SSH_CMD "convert /tmp/display.xwd /tmp/display-screenshot.png 2>/dev/null || cp /tmp/display.xwd /tmp/display-screenshot.xwd" || true

    if $SSH_CMD "test -f /tmp/display-screenshot.png" 2>/dev/null; then
        $SCP_CMD "pi@${SSH_HOST}:/tmp/display-screenshot.png" "$ARTIFACTS_DIR/screenshot.png"
        echo "Display screenshot saved (PNG)"
    elif $SSH_CMD "test -f /tmp/display-screenshot.xwd" 2>/dev/null; then
        $SCP_CMD "pi@${SSH_HOST}:/tmp/display-screenshot.xwd" "$ARTIFACTS_DIR/screenshot.xwd"
        # Convert on the host side if imagemagick is available
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
    $SSH_CMD "chromium --headless --disable-gpu --no-sandbox --screenshot=/tmp/chromium-screenshot.png --window-size=1280,720 '$SCREENSHOT_URL'" 2>/dev/null || true
    sleep 2
    if $SSH_CMD "test -f /tmp/chromium-screenshot.png" 2>/dev/null; then
        $SCP_CMD "pi@${SSH_HOST}:/tmp/chromium-screenshot.png" "$ARTIFACTS_DIR/screenshot.png"
        echo "Chromium headless screenshot saved (fallback)"
    else
        echo "All screenshot methods failed"
        exit 1
    fi
fi
