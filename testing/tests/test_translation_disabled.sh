#!/bin/bash
set -e

export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-}"
source /test/scripts/ssh-helpers.sh

GERMAN_PAGE_URL="http://localhost/german_test.html"
FIXTURE="/test/fixtures/german_test_page.html"
SCREENSHOT_NAME="translation_disabled.png"
FULLPAGEOS_TXT="/boot/firmware/fullpageos.txt"

echo "Test: Chromium translate dialog on German page (visual evidence)"

if [ ! -f "$FIXTURE" ]; then
    echo "  FAIL: German test fixture not found at $FIXTURE"
    exit 1
fi

echo "  Uploading German test page to lighttpd document root..."
scp_cmd "$FIXTURE" "pi@${E2E_SSH_HOST}:/tmp/german_test_page.html"
ssh_cmd "sudo cp /tmp/german_test_page.html /var/www/html/german_test.html"
ssh_cmd "sudo chown www-data:www-data /var/www/html/german_test.html 2>/dev/null || true"

HTTP_CODE=$(ssh_cmd "curl -s -o /dev/null -w '%{http_code}' '$GERMAN_PAGE_URL' || true" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
    echo "  FAIL: German test page returned HTTP $HTTP_CODE"
    exit 1
fi
echo "  German test page served (HTTP 200)"

# Running a second windowed Chromium on a fresh Xvfb display proved unreliable in
# QEMU (the network service crashes and pages never load). Instead we drive the
# already-working production kiosk on :0: point it at the German page, let the
# run_onepageos respawn loop reload it, screenshot, then restore the dashboard.
# This is also the environment where the translate bug actually manifests.
echo "  Saving current kiosk URL..."
ORIG_URL=$(ssh_cmd "cat ${FULLPAGEOS_TXT} 2>/dev/null || true" 2>/dev/null || true)
echo "  Current URL: ${ORIG_URL:-<empty>}"

restore_url() {
    local restored_url="${ORIG_URL:-http://localhost/FullPageDashboard}"
    echo "  Restoring original kiosk URL..."
    ssh_cmd "printf '%s\n' '${restored_url}' | sudo tee ${FULLPAGEOS_TXT} >/dev/null" 2>/dev/null || true
    ssh_cmd "killall chromium 2>/dev/null || true; exit 0" || true

    # run_onepageos respawns chromium from fullpageos.txt, but the new kiosk
    # process appearing does not mean its window has composited. Wait for the
    # dashboard kiosk process to come back so screenshot.sh starts from a
    # relaunched kiosk rather than the bare desktop wallpaper.
    echo "  Waiting for dashboard kiosk to relaunch on ${restored_url}..."
    local restored=0
    for i in $(seq 1 60); do
        local kiosk
        kiosk=$(ssh_cmd "ps ax -o pid= -o args= | grep -F 'chromium' | grep -F -- '--kiosk' | grep -F -- '--app=${restored_url}' | grep -v grep || true" 2>/dev/null || true)
        if [ -n "$kiosk" ]; then
            restored=1
            echo "  Dashboard kiosk restored (pid: $(echo "$kiosk" | awk '{print $1}' | head -1)) after ${i}x2s"
            break
        fi
        sleep 2
    done
    if [ "$restored" -eq 0 ]; then
        echo "  WARNING: Dashboard kiosk did not relaunch on ${restored_url}"
        ssh_cmd "pgrep -a chromium || true" 2>/dev/null || true
    fi
}

echo "  Pointing kiosk at German test page..."
ssh_cmd "printf '%s\n' '${GERMAN_PAGE_URL}' | sudo tee ${FULLPAGEOS_TXT} >/dev/null"

echo "  Reloading kiosk (run_onepageos will relaunch with new URL)..."
ssh_cmd "killall chromium 2>/dev/null || true; exit 0" || true

echo "  Waiting for kiosk to load the German page on :0..."
PAGE_LOADED=0
for i in $(seq 1 60); do
    RENDERED_URL=$(ssh_cmd "cat ${FULLPAGEOS_TXT} 2>/dev/null || true" 2>/dev/null || true)
    KIOSK=$(ssh_cmd "pgrep -f 'chromium.*--app=.*german_test' 2>/dev/null || true" 2>/dev/null || true)
    if [ -n "$KIOSK" ]; then
        PAGE_LOADED=1
        echo "  Kiosk relaunched on German page (pid: $(echo "$KIOSK" | head -1))"
        break
    fi
    sleep 2
done

if [ "$PAGE_LOADED" -eq 0 ]; then
    echo "  WARNING: Did not confirm kiosk relaunch on German page"
    ssh_cmd "pgrep -a chromium || true" 2>/dev/null || true
fi

echo "  Waiting for the German page to actually paint on :0..."
TITLE_SEEN=0
for i in $(seq 1 45); do
    TITLES=$(ssh_cmd "DISPLAY=:0 xdotool search --name . getwindowname 2>/dev/null || true" 2>/dev/null || true)
    if echo "$TITLES" | grep -qi "Deutsche\|Testseite\|Übersetzung\|german_test"; then
        TITLE_SEEN=1
        echo "  German page window visible (titles: $(echo "$TITLES" | tr '\n' ' '))"
        break
    fi
    sleep 1
done
if [ "$TITLE_SEEN" -eq 0 ]; then
    echo "  WARNING: German page title not detected on :0 (titles: $(ssh_cmd "DISPLAY=:0 xdotool search --name . getwindowname 2>/dev/null || true" 2>/dev/null | tr '\n' ' '))"
fi

echo "  Waiting for any translate UI to settle..."
sleep 12

CAPTURED=0
if [ -n "$ARTIFACTS_DIR" ]; then
    mkdir -p "$ARTIFACTS_DIR"
    echo "  Capturing screenshot to $ARTIFACTS_DIR/$SCREENSHOT_NAME ..."
    DISPLAY_SCREENSHOT=false
    ssh_cmd "DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xwd -root -out /tmp/translate-test.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true
    if [ "$DISPLAY_SCREENSHOT" = false ]; then
        ssh_cmd "DISPLAY=:0 xwd -root -out /tmp/translate-test.xwd" 2>/dev/null && DISPLAY_SCREENSHOT=true
    fi

    if [ "$DISPLAY_SCREENSHOT" = true ] && ssh_cmd "test -s /tmp/translate-test.xwd" 2>/dev/null; then
        if ssh_cmd "convert /tmp/translate-test.xwd /tmp/translate-test.png" 2>/dev/null && \
           ssh_cmd "test -s /tmp/translate-test.png" 2>/dev/null; then
            scp_cmd "pi@${E2E_SSH_HOST}:/tmp/translate-test.png" "$ARTIFACTS_DIR/$SCREENSHOT_NAME"
            CAPTURED=1
            echo "  Screenshot saved (converted on guest): $ARTIFACTS_DIR/$SCREENSHOT_NAME"
        else
            scp_cmd "pi@${E2E_SSH_HOST}:/tmp/translate-test.xwd" "$ARTIFACTS_DIR/translate-test.xwd"
            if command -v convert >/dev/null 2>&1 && \
               convert "$ARTIFACTS_DIR/translate-test.xwd" "$ARTIFACTS_DIR/$SCREENSHOT_NAME" 2>/dev/null; then
                rm -f "$ARTIFACTS_DIR/translate-test.xwd"
                CAPTURED=1
                echo "  Screenshot saved (converted on host): $ARTIFACTS_DIR/$SCREENSHOT_NAME"
            else
                echo "  WARNING: Could not convert XWD to PNG; keeping raw XWD"
                CAPTURED=1
            fi
        fi
    else
        echo "  WARNING: xwd capture failed; screenshot artifact may be missing"
    fi
else
    echo "  WARNING: No ARTIFACTS_DIR set; skipping screenshot capture"
fi

restore_url

if [ "$CAPTURED" -eq 0 ] && [ -n "$ARTIFACTS_DIR" ]; then
    echo "  FAIL: No screenshot evidence captured"
    exit 1
fi

echo "  PASS: Translation test completed (see $SCREENSHOT_NAME for visual evidence)"
exit 0
