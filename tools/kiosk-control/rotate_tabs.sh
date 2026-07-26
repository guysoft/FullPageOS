#!/bin/bash
export DISPLAY=:0
INTERVAL_FILE="/home/pi/kiosk-control/interval.txt"
DEFAULT_INTERVAL=30

sleep 25
while true; do
  interval="$DEFAULT_INTERVAL"
  if [ -f "$INTERVAL_FILE" ]; then
    val=$(tr -d '[:space:]' < "$INTERVAL_FILE" 2>/dev/null)
    case "$val" in
      ''|*[!0-9]*) ;;                 # empty or non-numeric — keep default
      *) [ "$val" -ge 3 ] && interval="$val" ;;  # guard against a too-small value spamming ctrl+Next
    esac
  fi
  sleep "$interval"
  xdotool key ctrl+Next
done
