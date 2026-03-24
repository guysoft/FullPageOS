#!/bin/bash
set -e

HOST="${1:-localhost}"
PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-}"
USER="pi"
PASS="raspberry"

SSH_CMD="sshpass -p $PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o LogLevel=ERROR -p $PORT ${USER}@${HOST}"

echo "Test: lighttpd serves FullPageOS dashboard"

DASHBOARD_URL="http://localhost/FullPageDashboard"

LIGHTTPD_READY=0
for i in $(seq 1 60); do
    HTTP_CODE=$($SSH_CMD "curl -sL -o /dev/null -w '%{http_code}' '$DASHBOARD_URL'" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        LIGHTTPD_READY=1
        break
    fi
    if [ "$((i % 12))" -eq 0 ]; then
        echo " (HTTP $HTTP_CODE after ${i}x5s)"
        $SSH_CMD "systemctl is-active lighttpd || true" 2>/dev/null || true
        $SSH_CMD "curl -sL -o /dev/null -w 'root=%{http_code}' http://localhost/ || true" 2>/dev/null || true
        echo ""
    else
        printf "."
    fi
    sleep 5
done
echo ""

if [ "$LIGHTTPD_READY" -eq 0 ]; then
    echo "  FAIL: FullPageDashboard did not return HTTP 200 within 300s (last code: $HTTP_CODE)"
    $SSH_CMD "curl -sLI '$DASHBOARD_URL' 2>/dev/null | head -10" 2>/dev/null || true
    $SSH_CMD "ls -la /var/www/html/FullPageDashboard/ 2>/dev/null || echo 'FullPageDashboard dir not found'" 2>/dev/null || true
    exit 1
fi

BODY=$($SSH_CMD "curl -sL '$DASHBOARD_URL'" 2>/dev/null)

if [ -n "$ARTIFACTS_DIR" ]; then
    echo "$BODY" > "$ARTIFACTS_DIR/lighttpd-index.html" 2>/dev/null || true
fi

if echo "$BODY" | grep -qi "FullPage\|dashboard\|welcome"; then
    echo "  PASS: lighttpd is serving FullPageOS dashboard at $DASHBOARD_URL"
    exit 0
else
    echo "  FAIL: Response did not contain expected FullPageOS content"
    echo "  HTTP body (first 500 chars): $(echo "$BODY" | head -c 500)"
    exit 1
fi
