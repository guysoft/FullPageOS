# Kiosk Control

A small, dependency-free web UI for managing FullPageOS's rotating page list
and rotation speed **live**, without needing a reboot for every routine
change.

Out of the box, editing `/boot/firmware/fullpageos.txt` (FullPageOS's list of
kiosk tabs) and its rotation interval both require an SSH session and a
reboot to take effect. Kiosk Control adds a small local web page — reachable
from your phone or laptop on the same network — where you can add, remove,
reorder pages, and change how fast the kiosk cycles, with the change pushed
to the running Chromium session immediately and written back to
`fullpageos.txt` so it survives the next reboot too.

Requires nothing beyond Python 3's standard library — no `pip install`
needed on the Pi.

## How it works

- The page list (order + labels) lives in `pages.json` next to `app.py`.
  Saving regenerates `/boot/firmware/fullpageos.txt` (the file
  `get_url`/`start_chromium_browser` already read at boot), so a future
  reboot still comes up with the same set.
- "Save & Apply Live" talks to Chromium's remote-debugging port (CDP) to
  open the new tab set and close the old one — see `push_live()` in
  `app.py` for an important ordering detail: new tabs open *before* old
  ones close, so the browser never briefly hits zero tabs (which would
  otherwise quit the whole Chromium process, since it's launched without
  `--app=`).
- The rotation interval is a single number in `interval.txt` that
  `rotate_tabs.sh` re-reads every loop, so a new value takes effect within
  one cycle — no service restart needed.

## Requirements

- `start_chromium_browser` launched with `--remote-debugging-port=9222`
  (see the patched copy in this folder — the only change from stock is
  that one flag; every existing flag is untouched).
- `rotate_tabs.sh` reading its interval from an `INTERVAL_FILE` each loop
  (see the patched copy in this folder).
- This directory and `/boot/firmware/fullpageos.txt` writable by the user
  this runs as (typically `pi`).

## Install (one-time; exactly one reboot required)

After this setup there is **exactly one required reboot** (needed so
Chromium picks up the new startup flag). Everything after that is live via
the web UI, no more reboot-per-change.

### 1. Copy these files onto the kiosk Pi

From a machine with `scp` (Windows 10/11's built-in OpenSSH client works):

```
scp app.py kiosk-control.service pi@<kiosk-ip>:/home/pi/
scp start_chromium_browser pi@<kiosk-ip>:/home/pi/scripts/start_chromium_browser.new
scp rotate_tabs.sh pi@<kiosk-ip>:/home/pi/rotate_tabs.sh.new
```

(Sent as `.new` for the two files that already exist on a stock FullPageOS
install, so the swap-in step below can back up the originals first.)

### 2. SSH in and finish the install

```
ssh pi@<kiosk-ip>
mkdir -p /home/pi/kiosk-control
mv /home/pi/app.py /home/pi/kiosk-control/app.py

# Back up the two files being replaced
cp /home/pi/scripts/start_chromium_browser /home/pi/scripts/start_chromium_browser.bak-$(date +%Y%m%d)
cp /home/pi/rotate_tabs.sh /home/pi/rotate_tabs.sh.bak-$(date +%Y%m%d)

mv /home/pi/scripts/start_chromium_browser.new /home/pi/scripts/start_chromium_browser
mv /home/pi/rotate_tabs.sh.new /home/pi/rotate_tabs.sh
chmod +x /home/pi/scripts/start_chromium_browser /home/pi/rotate_tabs.sh

# Let the web UI write fullpageos.txt directly, without needing sudo each save.
#
# NOTE: `sudo chown pi:pi /boot/firmware/fullpageos.txt` does NOT work on a
# Bookworm-based FullPageOS nightly and fails with "Operation not permitted"
# even as root — /boot/firmware there is a FAT32 (vfat) partition, and FAT
# has no concept of per-file Unix ownership at all. Every file on it just
# reports whatever uid/gid the *partition* was mounted with, so `chown` has
# nothing to change. Set ownership via the mount options instead:
id pi   # confirm pi's uid/gid — normally 1000:1000; use the real numbers below
sudo nano /etc/fstab
# Find the /boot/firmware line (looks like:
#   PARTUUID=xxxx-xxxx  /boot/firmware  vfat  defaults  0  2
# ) and add uid=1000,gid=1000 (or whatever `id pi` showed) to the options:
#   PARTUUID=xxxx-xxxx  /boot/firmware  vfat  defaults,uid=1000,gid=1000  0  2
sudo mount -o remount /boot/firmware
ls -la /boot/firmware/fullpageos.txt   # should now show pi:pi — confirm before moving on

# Install and start the control service
sudo mv /home/pi/kiosk-control.service /etc/systemd/system/kiosk-control.service
sudo systemctl daemon-reload
sudo systemctl enable --now kiosk-control.service

# Confirm it's up
curl -s http://localhost:7077/api/state
```

That last command should print JSON with your current pages and an
`"interval"` value. If it errors, check
`sudo systemctl status kiosk-control.service` and
`sudo journalctl -u kiosk-control -n 50`.

(On an older, non-Bookworm FullPageOS image where `/boot` is a regular
ext4 partition rather than `/boot/firmware` on vfat, the plain
`sudo chown pi:pi /boot/fullpageos.txt` approach works fine and the fstab
workaround above isn't needed — check which applies to your image first.)

### 3. The one required reboot

```
sudo reboot
```

This is needed once so Chromium actually launches with the new
`--remote-debugging-port=9222` flag.

### 4. Verify after reboot

```
curl -s http://localhost:9222/json/version   # should return Chromium version JSON, not a connection error
```

Then from your phone or laptop (same network), open:

**`http://<kiosk-ip>:7077/`**

You should see your current pages listed. Try changing the interval to
something obviously different (e.g. 10s) and hitting **Save & Apply Live**
— the kiosk should visibly speed up within a few seconds, with no reboot.

## From here on

- **Add a page:** fill in the label + URL fields at the bottom, click **+ Add**, then **Save & Apply Live**.
- **Remove a page:** click the **×** next to it, then save.
- **Reorder:** the **↑ / ↓** buttons next to each row, then save.
- **Speed:** the seconds field (or a preset button) at the top, then save.

Every save also rewrites `/boot/firmware/fullpageos.txt`, so the change
survives a future reboot too — the live push and the persisted file are
always kept in sync in one action.

## Screen sleep/wake (optional)

`screen_power.sh` (also in this folder) sleeps or wakes the display via X11
DPMS signaling — useful if you don't want an always-on kiosk lit up all
night. Copy it over and make it executable:

```
scp screen_power.sh pi@<kiosk-ip>:/home/pi/
ssh pi@<kiosk-ip> chmod +x /home/pi/screen_power.sh
```

Test it manually first — whether the physical screen actually honors DPMS
(drops to standby, backlight off) rather than just showing a black frame
with the backlight still lit depends on the specific display:

```
ssh pi@<kiosk-ip> /home/pi/screen_power.sh off   # screen should go dark
ssh pi@<kiosk-ip> /home/pi/screen_power.sh on    # and come back
```

Once confirmed, schedule it with cron for an overnight sleep (adjust the
times to taste):

```
ssh pi@<kiosk-ip>
(crontab -l 2>/dev/null; echo "0 22 * * * /home/pi/screen_power.sh off"; echo "0 6 * * * /home/pi/screen_power.sh on") | crontab -
```

Kiosk Control's web UI also has **Sleep now** / **Wake now** buttons (in the
"Screen" card) that call `screen_power.sh` directly via a new `/api/screen`
endpoint — a manual override so you can flip the screen back on immediately
instead of waiting for the next scheduled cron time or needing to SSH in.
This is optional: if `screen_power.sh` isn't installed, those buttons will
just report an error rather than break anything else in the UI.

Note that `rotate_tabs.sh` keeps sending its `ctrl+Next` on schedule
regardless of screen power state — X still processes those events with the
display powered off, so tab rotation continues silently in the background.
That's harmless, just something to be aware of.

## Rolling back, if anything looks wrong

```
sudo systemctl disable --now kiosk-control.service
cp /home/pi/scripts/start_chromium_browser.bak-<date> /home/pi/scripts/start_chromium_browser
cp /home/pi/rotate_tabs.sh.bak-<date> /home/pi/rotate_tabs.sh
sudo reboot
```
