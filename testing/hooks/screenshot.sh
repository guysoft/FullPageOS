#!/bin/bash
set -e
export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-/output}"
source /test/scripts/ssh-helpers.sh
SCREENSHOT_URL="${SCREENSHOT_URL:-http://localhost/FullPageDashboard}"
# The FullPageOS desktop wallpaper / dashboard shell alone paints at stddev
# ~0.20, while the welcome dashboard with the QR code paints at ~0.31. Require
# the higher value so we don't accept the wallpaper after the kiosk restarts
# (e.g. following test_translation_disabled.sh), and wait for the welcome
# iframe content to actually render.
PAINT_STDDEV_THRESHOLD="${PAINT_STDDEV_THRESHOLD:-0.26}"
PAINT_STABLE_PASSES="${PAINT_STABLE_PASSES:-2}"

echo "Capturing X display screenshot from the running desktop..."

diagnose_screenshot_failure() {
    echo "Screenshot diagnostics:"
    ssh_cmd "echo '== fullpageos.txt =='; cat /boot/firmware/fullpageos.txt 2>/dev/null || true; echo; echo '== fullpagedashboard.txt =='; cat /boot/firmware/fullpagedashboard.txt 2>/dev/null || true; echo; echo '== chromium =='; ps ax -o pid= -o args= | grep -i '[c]hromium' || true; echo; echo '== lighttpd =='; systemctl is-active lighttpd 2>/dev/null || true; curl -sL -o /dev/null -w 'welcome=%{http_code}\n' http://localhost/welcome 2>/dev/null || true; echo; echo '== X titles =='; DISPLAY=:0 xdotool search --name . getwindowname 2>&1 || true; echo; echo '== start_gui log =='; tail -80 /tmp/start_gui.log 2>/dev/null || true; echo; echo '== xwd error =='; cat /tmp/display-capture.err 2>/dev/null || true" 2>/dev/null || true
}

wait_for_dashboard_kiosk() {
    local process=""

    echo "  Waiting for Chromium dashboard kiosk on ${SCREENSHOT_URL}..."
    for i in $(seq 1 60); do
        process=$(ssh_cmd "ps ax -o pid= -o args= | grep -F 'chromium' | grep -F -- '--kiosk' | grep -F -- '--app=${SCREENSHOT_URL}' | grep -v grep || true" 2>/dev/null || true)
        if [ -n "$process" ] && ssh_cmd "DISPLAY=:0 xdpyinfo >/dev/null 2>&1" 2>/dev/null; then
            echo "  Chromium dashboard kiosk ready (pid: $(echo "$process" | awk '{print $1}' | head -1)) after ${i}x2s"
            sleep 5
            return 0
        fi
        sleep 2
    done

    echo "  FAIL: Chromium dashboard kiosk was not ready"
    diagnose_screenshot_failure
    return 1
}

wait_for_dashboard_kiosk
mkdir -p "$ARTIFACTS_DIR"

capture_display_png() {
    local output_png="$1"
    local raw_xwd="${output_png}.xwd"
    local display_screenshot=false

    rm -f "$output_png" "$raw_xwd"
    ssh_cmd "rm -f /tmp/display.xwd /tmp/display-screenshot.png /tmp/display-capture.err /tmp/display-convert.err" 2>/dev/null || true

    ssh_cmd "DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xwd -root -out /tmp/display.xwd 2>/tmp/display-capture.err" 2>/dev/null && display_screenshot=true
    if [ "$display_screenshot" = false ]; then
        ssh_cmd "DISPLAY=:0 xwd -root -out /tmp/display.xwd 2>/tmp/display-capture.err" 2>/dev/null && display_screenshot=true
    fi

    if [ "$display_screenshot" = false ] || ! ssh_cmd "test -s /tmp/display.xwd" 2>/dev/null; then
        return 1
    fi

    ssh_cmd "convert /tmp/display.xwd /tmp/display-screenshot.png 2>/tmp/display-convert.err || true" 2>/dev/null || true
    if ssh_cmd "test -s /tmp/display-screenshot.png" 2>/dev/null; then
        scp_cmd "pi@${E2E_SSH_HOST}:/tmp/display-screenshot.png" "$output_png"
    else
        scp_cmd "pi@${E2E_SSH_HOST}:/tmp/display.xwd" "$raw_xwd"
        if command -v convert &>/dev/null; then
            convert "$raw_xwd" "$output_png" 2>/dev/null && rm -f "$raw_xwd"
        fi
    fi

    test -s "$output_png"
}

dashboard_is_painted() {
    local screenshot="$1"
    local stddev

    stddev=$(convert "$screenshot" -crop 1280x620+0+80 -colorspace Gray -format '%[fx:standard_deviation]' info: 2>/dev/null || echo 0)
    echo "  Candidate page-area stddev: ${stddev}"
    awk -v value="$stddev" -v threshold="$PAINT_STDDEV_THRESHOLD" 'BEGIN { exit !(value >= threshold) }'
}

echo "  Waiting for dashboard iframe content to paint..."
consecutive_passes=0
for i in $(seq 1 60); do
    if capture_display_png "$ARTIFACTS_DIR/screenshot-candidate.png"; then
        cp "$ARTIFACTS_DIR/screenshot-candidate.png" "$ARTIFACTS_DIR/screenshot-not-painted.png"
        if dashboard_is_painted "$ARTIFACTS_DIR/screenshot-candidate.png"; then
            consecutive_passes=$((consecutive_passes + 1))
            if [ "$consecutive_passes" -ge "$PAINT_STABLE_PASSES" ]; then
                mv "$ARTIFACTS_DIR/screenshot-candidate.png" "$ARTIFACTS_DIR/screenshot.png"
                rm -f "$ARTIFACTS_DIR/screenshot-not-painted.png"
                echo "Display screenshot saved after dashboard paint (${consecutive_passes} stable passes, ${i}x2s)"
                exit 0
            fi
            echo "  Painted but waiting for stabilization (${consecutive_passes}/${PAINT_STABLE_PASSES})"
            sleep 3
            continue
        else
            consecutive_passes=0
        fi
    else
        consecutive_passes=0
        echo "  Candidate capture failed (${i}x2s)"
    fi
    sleep 2
done

echo "  FAIL: Dashboard iframe content did not paint before screenshot timeout"
diagnose_screenshot_failure
if [ ! -s "$ARTIFACTS_DIR/screenshot-not-painted.png" ]; then
    echo "  FAIL: no candidate screenshot was produced"
    exit 1
fi
exit 1
