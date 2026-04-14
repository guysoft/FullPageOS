#!/bin/bash
export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
source /test/scripts/ssh-helpers.sh

echo "Installing Xvfb and x11-apps..."
ssh_cmd "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb x11-apps 2>&1 | tail -5"

echo "Starting Xvfb virtual display..."
ssh_cmd "sudo nohup Xvfb :0 -screen 0 1280x720x24 -ac > /tmp/xvfb.log 2>&1 < /dev/null &"
sleep 3

echo "Verifying Xvfb is running..."
XVFB_PID=$(ssh_cmd "pgrep -f 'Xvfb :0' || true" 2>/dev/null)
if [ -z "$XVFB_PID" ]; then
    echo "  WARNING: Xvfb not running, checking log..."
    ssh_cmd "cat /tmp/xvfb.log 2>/dev/null || true" 2>/dev/null
else
    echo "  Xvfb running (pid: $XVFB_PID)"
fi

echo "Checking lighttpd status..."
ssh_cmd "systemctl is-active lighttpd 2>/dev/null || true" 2>/dev/null
ssh_cmd "curl -s -o /dev/null -w 'HTTP %{http_code}' http://localhost/ || true" 2>/dev/null
echo ""

echo "Starting GUI session (matchbox + chromium kiosk)..."
ssh_cmd "sudo -u pi nohup bash -c 'export DISPLAY=:0; export HOME=/home/pi; /opt/custompios/scripts/start_gui' > /tmp/start_gui.log 2>&1 < /dev/null &"

echo "Waiting for Chromium to start..."
for i in $(seq 1 60); do
    PGREP=$(ssh_cmd "pgrep -f 'chromium.*--kiosk' || true" 2>/dev/null)
    if [ -n "$PGREP" ]; then
        echo "  Chromium running (pid: $PGREP) after ${i}x5s"
        break
    fi
    if [ "$((i % 6))" -eq 0 ]; then
        echo "  ... still waiting (${i}x5s), diagnostics:"
        ssh_cmd "pgrep -a Xvfb || echo '  Xvfb: NOT RUNNING'" 2>/dev/null || true
        ssh_cmd "pgrep -a matchbox || echo '  matchbox: NOT RUNNING'" 2>/dev/null || true
        ssh_cmd "pgrep -a chromium || echo '  chromium: NOT RUNNING'" 2>/dev/null || true
        ssh_cmd "tail -5 /tmp/start_gui.log 2>/dev/null || true" 2>/dev/null || true
    fi
    sleep 5
done

if [ -z "$PGREP" ]; then
    echo "  WARNING: Chromium did not appear after 300s"
    echo "  start_gui log:"
    ssh_cmd "cat /tmp/start_gui.log 2>/dev/null || true" 2>/dev/null || true
    echo "  xvfb log:"
    ssh_cmd "cat /tmp/xvfb.log 2>/dev/null || true" 2>/dev/null || true
    echo "  Process list:"
    ssh_cmd "ps aux | head -30" 2>/dev/null || true
fi

echo "Waiting for page to render..."
sleep 15

echo "Post-boot display state:"
ssh_cmd "DISPLAY=:0 xdotool search --onlyvisible --name . getwindowname 2>/dev/null || echo '(no visible windows)'" 2>/dev/null || true

echo "Post-boot setup complete"
