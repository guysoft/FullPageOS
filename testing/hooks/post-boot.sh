#!/bin/bash
set -e
SSH_HOST="${1:-localhost}"
SSH_PORT="${2:-2222}"

SSH_CMD="sshpass -p raspberry ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT pi@$SSH_HOST"

echo "Installing Xvfb and configuring virtual display..."

# Install xvfb and x11-apps (for xwd screenshot capture)
$SSH_CMD "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb x11-apps 2>&1 | tail -3"

# In QEMU virt, logind's seat0 has CanGraphical=no (no real display device),
# so lightdm won't start an X session. Start Xvfb and the GUI session directly.
echo "Starting Xvfb virtual display..."
$SSH_CMD "sudo Xvfb :0 -screen 0 1280x720x24 &"
sleep 2

echo "Starting GUI session (matchbox + chromium kiosk)..."
$SSH_CMD "sudo -u pi bash -c 'export DISPLAY=:0; export HOME=/home/pi; /opt/custompios/scripts/start_gui' &"

# Wait for Chromium to appear on the display
echo "Waiting for Chromium to start..."
for i in $(seq 1 30); do
    PGREP=$($SSH_CMD "pgrep -f 'chromium.*--kiosk' || true" 2>/dev/null)
    if [ -n "$PGREP" ]; then
        echo "  Chromium running on display (pid: $PGREP)"
        break
    fi
    sleep 5
done

# Give the page time to render
echo "  Waiting for page to load..."
sleep 15

echo "Post-boot setup complete"
