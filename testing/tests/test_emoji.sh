#!/bin/bash
set -e

export E2E_SSH_HOST="${1:-localhost}"
export E2E_SSH_PORT="${2:-2222}"
ARTIFACTS_DIR="${3:-}"
source /test/scripts/ssh-helpers.sh

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HTML_FILE="$TMP_DIR/emoji-cloud.html"
SCREENSHOT_FILE="$TMP_DIR/emoji-cloud.png"
COUNTS_FILE="$TMP_DIR/emoji-cloud-pixel-counts.txt"

cat > "$HTML_FILE" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    html,
    body {
      width: 400px;
      height: 240px;
      margin: 0;
      background: #101828;
    }

    body {
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .emoji {
      color: #ffffff;
      font-family: sans-serif;
      font-size: 144px;
      line-height: 1;
    }
  </style>
</head>
<body>
  <div class="emoji" aria-label="cloud emoji">&#x2601;&#xFE0F;</div>
</body>
</html>
HTML

echo "Test: Chromium renders the cloud emoji in color"

echo "  Checking Noto Color Emoji font availability..."
FONT_MATCH=$(ssh_cmd "fc-match 'Noto Color Emoji' || true" 2>/dev/null)
if ! echo "$FONT_MATCH" | grep -qi "NotoColorEmoji\|Noto Color Emoji"; then
    echo "  FAIL: Noto Color Emoji is not available to fontconfig"
    echo "  fc-match output: $FONT_MATCH"
    exit 1
fi

echo "  Rendering emoji fixture with Chromium headless..."
scp_cmd "$HTML_FILE" "pi@${E2E_SSH_HOST}:/tmp/emoji-cloud.html" >/dev/null
ssh_cmd "rm -rf /tmp/emoji-chromium-profile /tmp/emoji-cloud.png && sudo -u pi env HOME=/home/pi chromium --headless --disable-gpu --no-sandbox --disable-dev-shm-usage --hide-scrollbars --run-all-compositor-stages-before-draw --virtual-time-budget=1000 --user-data-dir=/tmp/emoji-chromium-profile --screenshot=/tmp/emoji-cloud.png --window-size=400,240 file:///tmp/emoji-cloud.html" >/dev/null
scp_cmd "pi@${E2E_SSH_HOST}:/tmp/emoji-cloud.png" "$SCREENSHOT_FILE" >/dev/null

if [ -n "$ARTIFACTS_DIR" ]; then
    mkdir -p "$ARTIFACTS_DIR"
    cp "$HTML_FILE" "$ARTIFACTS_DIR/emoji-cloud.html"
    cp "$SCREENSHOT_FILE" "$ARTIFACTS_DIR/emoji-cloud.png"
fi

read -r NON_BACKGROUND_PIXELS CHROMATIC_PIXELS < <(
    convert "$SCREENSHOT_FILE" -alpha off -depth 8 txt:- | awk -F'[(),]' '
      NR > 1 {
        r = $3 + 0
        g = $4 + 0
        b = $5 + 0

        dr = r - 16; if (dr < 0) dr = -dr
        dg = g - 24; if (dg < 0) dg = -dg
        db = b - 40; if (db < 0) db = -db

        max = r; if (g > max) max = g; if (b > max) max = b
        min = r; if (g < min) min = g; if (b < min) min = b

        if (dr > 8 || dg > 8 || db > 8) {
          non_background++
          if (max - min >= 25) {
            chromatic++
          }
        }
      }
      END {
        print non_background + 0, chromatic + 0
      }'
)

echo "non_background_pixels=$NON_BACKGROUND_PIXELS chromatic_pixels=$CHROMATIC_PIXELS" > "$COUNTS_FILE"
if [ -n "$ARTIFACTS_DIR" ]; then
    cp "$COUNTS_FILE" "$ARTIFACTS_DIR/emoji-cloud-pixel-counts.txt"
fi

if [ "$NON_BACKGROUND_PIXELS" -lt 1500 ]; then
    echo "  FAIL: Cloud emoji was not visibly rendered (non-background pixels: $NON_BACKGROUND_PIXELS)"
    exit 1
fi

if [ "$CHROMATIC_PIXELS" -lt 50 ]; then
    echo "  FAIL: Cloud emoji rendered without enough color pixels (chromatic pixels: $CHROMATIC_PIXELS)"
    exit 1
fi

echo "  PASS: Cloud emoji rendered visibly in color"
