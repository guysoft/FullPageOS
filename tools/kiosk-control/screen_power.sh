#!/bin/bash
# Sleep/wake the kiosk's display via X11 DPMS signaling.
#
# Usage: screen_power.sh [on|off]
#
# Intended to be run both manually (e.g. from Kiosk Control's "Sleep now" /
# "Wake now" buttons in app.py) and on a cron schedule for an overnight sleep,
# e.g.:
#   0 22 * * * /home/pi/screen_power.sh off
#   0 6  * * * /home/pi/screen_power.sh on
#
# Whether the physical screen actually honors this (drops to standby,
# backlight off) rather than just showing a black frame with the backlight
# still lit depends on the specific display's own DPMS support over HDMI —
# test manually with `screen_power.sh off` / `screen_power.sh on` before
# relying on the cron schedule.
export DISPLAY=:0
if [ -f /home/pi/.Xauthority ]; then
  export XAUTHORITY=/home/pi/.Xauthority
else
  export XAUTHORITY=$(find /home/*/.Xauthority /var/run/lightdm/*/xauthority 2>/dev/null | head -n1)
fi
xset +dpms
case "$1" in
  off) xset dpms force off ;;
  on)  xset dpms force on ;;
  *) echo "usage: $0 [on|off]"; exit 1 ;;
esac
