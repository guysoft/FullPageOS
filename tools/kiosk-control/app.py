#!/usr/bin/env python3
"""Kiosk Control — a tiny local web UI to manage FullPageOS's rotating tab
list and rotation speed live, without a reboot for routine changes.

How it works:
  - The page list (order + labels) lives in pages.json next to this file.
    Saving regenerates /boot/firmware/fullpageos.txt (the single space-
    separated URL line get_url/start_chromium_browser already read at boot,
    kept in sync so a future reboot still comes up with the same set).
  - "Apply live" talks to Chromium's remote-debugging port (CDP) to open the
    new tab set and close the old one — see push_live() for the important
    ordering detail (new tabs open BEFORE old ones close, so the browser
    never hits zero tabs).
  - The rotation interval is a single number in interval.txt that
    rotate_tabs.sh re-reads every loop, so a new value takes effect within
    one cycle — no service restart needed.

Requires (see the accompanying README.md for exact one-time steps):
  - start_chromium_browser launched with --remote-debugging-port=9222
  - rotate_tabs.sh reading its interval from INTERVAL_FILE each loop
  - This directory and /boot/firmware/fullpageos.txt writable by the user
    this runs as (pi)

Stdlib only — no pip install needed on the Pi.
"""
import json
import os
import re
import subprocess
import urllib.request
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KIOSK_DIR = os.path.dirname(os.path.abspath(__file__))
PAGES_FILE = os.path.join(KIOSK_DIR, 'pages.json')
INTERVAL_FILE = os.path.join(KIOSK_DIR, 'interval.txt')
SCHEDULE_FILE = os.path.join(KIOSK_DIR, 'schedule.json')
FULLPAGEOS_TXT = '/boot/firmware/fullpageos.txt'
CDP_BASE = 'http://localhost:9222'
PORT = 7077

# screen_power.sh (see the accompanying file) handles the actual X11 DPMS
# on/off signaling. Its cron schedule (when it fires off/on automatically)
# is managed below by apply_schedule_to_cron() / schedule.json, editable
# from the "Screen" card in the UI — no SSH or manual crontab editing
# needed. The Sleep now / Wake now buttons are a manual override on top of
# whatever that schedule is, e.g. to turn the screen back on right away
# instead of waiting for the next scheduled time.
SCREEN_SCRIPT = '/home/pi/screen_power.sh'
DEFAULT_SLEEP_TIME = '22:00'
DEFAULT_WAKE_TIME = '06:00'
TIME_RE = re.compile(r'^([01]\d|2[0-3]):[0-5]\d$')

# Only used to guess a friendly label the very first time pages.json doesn't
# exist yet (seeded from whatever is actually in fullpageos.txt on this Pi at
# that moment) — never guessed/hardcoded ahead of time, so it can't drift
# from whatever URLs are really configured.
LABEL_HINTS = [
    (':61208', 'Glances'), (':5216', 'MySpeed'), ('8080/admin', 'Pi-hole'),
    ('mlb.html', 'MLB Scores'), ('nhl.html', 'NHL Scores'),
    ('weather-sun.html', 'Weather & Sun'), ('world-clock.html', 'World Clock'),
    ('stocks.html', 'Stocks'), ('news.html', 'News'),
    ('joke.html', 'Joke of the Moment'), ('fact.html', 'Useless Fact'),
    ('viewer.html', 'Tile Viewer'),
]


def guess_label(url):
    for needle, label in LABEL_HINTS:
        if needle in url:
            return label
    return url


def load_pages():
    if os.path.exists(PAGES_FILE):
        with open(PAGES_FILE) as f:
            return json.load(f)
    urls = []
    if os.path.exists(FULLPAGEOS_TXT):
        with open(FULLPAGEOS_TXT) as f:
            urls = f.readline().strip().split()
    pages = [{'label': guess_label(u), 'url': u} for u in urls]
    save_pages(pages)
    return pages


def save_pages(pages):
    os.makedirs(KIOSK_DIR, exist_ok=True)
    with open(PAGES_FILE, 'w') as f:
        json.dump(pages, f, indent=2)


def load_interval():
    if os.path.exists(INTERVAL_FILE):
        try:
            return max(3, int(open(INTERVAL_FILE).read().strip()))
        except ValueError:
            pass
    return 30


def save_interval(secs):
    os.makedirs(KIOSK_DIR, exist_ok=True)
    with open(INTERVAL_FILE, 'w') as f:
        f.write(str(secs))


def load_schedule():
    if os.path.exists(SCHEDULE_FILE):
        try:
            with open(SCHEDULE_FILE) as f:
                data = json.load(f)
            sleep_time = data.get('sleep_time', DEFAULT_SLEEP_TIME)
            wake_time = data.get('wake_time', DEFAULT_WAKE_TIME)
            if TIME_RE.match(sleep_time) and TIME_RE.match(wake_time):
                return sleep_time, wake_time
        except Exception:
            pass
    return DEFAULT_SLEEP_TIME, DEFAULT_WAKE_TIME


def save_schedule(sleep_time, wake_time):
    os.makedirs(KIOSK_DIR, exist_ok=True)
    with open(SCHEDULE_FILE, 'w') as f:
        json.dump({'sleep_time': sleep_time, 'wake_time': wake_time}, f)


def write_fullpageos_txt(pages):
    line = ' '.join(p['url'] for p in pages)
    with open(FULLPAGEOS_TXT, 'w') as f:
        f.write(line + '\n')


def cdp(path, method='GET'):
    req = urllib.request.Request(f'{CDP_BASE}{path}', method=method)
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode())


def push_live(pages):
    """Open every new tab first, THEN close the old ones. If this closed the
    old tabs first, a moment could exist with zero tabs open — Chromium was
    launched without --app=, so its last tab closing would quit the whole
    window/process, and nothing currently respawns it (the auto-restart code
    in start_chromium_browser is unreachable dead code after `exit;`). Doing
    it new-then-old avoids that entirely."""
    try:
        old_tabs = [t for t in cdp('/json/list') if t.get('type') == 'page']
    except Exception as e:
        return False, (f"Saved to disk, but couldn't reach Chromium's debug port "
                        f"(localhost:9222): {e}. Changes will apply on the next reboot instead.")
    new_ids = []
    try:
        for p in pages:
            resp = cdp(f"/json/new?{urllib.parse.quote(p['url'], safe='')}", method='PUT')
            new_ids.append(resp['id'])
        if new_ids:
            cdp(f'/json/activate/{new_ids[0]}')
        for t in old_tabs:
            if t['id'] not in new_ids:
                try:
                    cdp(f"/json/close/{t['id']}")
                except Exception:
                    pass
    except Exception as e:
        return False, (f"Saved to disk, but the live tab update failed partway through: {e}. "
                        f"Check the kiosk screen — a reboot will fully resync it if anything looks off.")
    return True, 'Applied live — no reboot needed.'


def screen_power(action):
    """Run screen_power.sh on/off — a manual override of the cron sleep
    schedule, so the screen can be toggled from the web UI without SSH."""
    try:
        result = subprocess.run([SCREEN_SCRIPT, action], capture_output=True, text=True, timeout=10)
    except FileNotFoundError:
        return False, f"{SCREEN_SCRIPT} not found — is the screen sleep/wake script installed?"
    except Exception as e:
        return False, f"Failed to run {SCREEN_SCRIPT}: {e}"
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        return False, f"screen_power.sh exited with an error: {detail or f'code {result.returncode}'}"
    return True, ('Screen turned off.' if action == 'off' else 'Screen turned on.')


def apply_schedule_to_cron(sleep_time, wake_time):
    """Rewrite this user's crontab so screen_power.sh fires off/on at the
    given HH:MM (24-hour) times. Any existing crontab lines that call
    screen_power.sh are treated as ours to manage and replaced; every other
    line in the crontab is left untouched."""
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, timeout=10)
    except FileNotFoundError:
        return False, "crontab command not found — is cron installed?"
    except Exception as e:
        return False, f"Failed to read the current crontab: {e}"
    # A non-zero exit here usually just means this user has no crontab yet,
    # which is fine — we're about to create one.
    existing_lines = result.stdout.splitlines() if result.returncode == 0 else []
    kept_lines = [line for line in existing_lines if SCREEN_SCRIPT not in line]

    sleep_h, sleep_m = sleep_time.split(':')
    wake_h, wake_m = wake_time.split(':')
    kept_lines.append(f"{int(sleep_m)} {int(sleep_h)} * * * {SCREEN_SCRIPT} off")
    kept_lines.append(f"{int(wake_m)} {int(wake_h)} * * * {SCREEN_SCRIPT} on")
    new_crontab = '\n'.join(kept_lines) + '\n'

    try:
        proc = subprocess.run(['crontab', '-'], input=new_crontab, capture_output=True, text=True, timeout=10)
    except Exception as e:
        return False, f"Failed to write the new crontab: {e}"
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        return False, f"crontab exited with an error: {detail or f'code {proc.returncode}'}"
    return True, f"Schedule saved — sleep at {sleep_time}, wake at {wake_time}."


PAGE_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kiosk Control</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #0a0e1a; color: #f3efe8;
         font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
  .wrap { max-width: 720px; margin: 0 auto; padding: 24px 18px 80px; }
  h1 { font-size: 22px; font-weight: 700; margin: 0 0 4px; }
  .sub { color: rgba(243,239,232,0.5); font-size: 14px; margin-bottom: 24px; }
  .card { background: rgba(243,239,232,0.06); border: 1px solid rgba(243,239,232,0.14);
          border-radius: 14px; padding: 16px; margin-bottom: 18px; }
  .card h2 { font-size: 15px; letter-spacing: 0.08em; text-transform: uppercase;
             color: rgba(243,239,232,0.55); margin: 0 0 14px; }
  .row { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; }
  .row input[type=text] { flex: 1; min-width: 0; background: rgba(243,239,232,0.08);
        border: 1px solid rgba(243,239,232,0.18); color: #f3efe8; border-radius: 8px;
        padding: 9px 10px; font-size: 14px; }
  .row .label-input { flex: 0 0 34%; }
  .btn { background: rgba(243,239,232,0.1); border: 1px solid rgba(243,239,232,0.2);
         color: #f3efe8; border-radius: 8px; padding: 9px 12px; font-size: 15px;
         cursor: pointer; line-height: 1; }
  .btn:hover { background: rgba(243,239,232,0.18); }
  .btn:disabled { opacity: 0.3; cursor: default; }
  .btn.danger:hover { background: rgba(232,103,103,0.25); border-color: rgba(232,103,103,0.5); }
  .btn.primary { background: rgba(232,177,63,0.25); border-color: rgba(232,177,63,0.6); color: #f3cd7a;
                 width: 100%; padding: 14px; font-size: 16px; font-weight: 600; }
  .btn.primary:hover { background: rgba(232,177,63,0.38); }
  #add-row input { margin-right: 8px; }
  .interval-row { display: flex; align-items: center; gap: 12px; }
  .interval-row input[type=number] { width: 90px; background: rgba(243,239,232,0.08);
        border: 1px solid rgba(243,239,232,0.18); color: #f3efe8; border-radius: 8px;
        padding: 9px 10px; font-size: 15px; }
  .presets { display: flex; gap: 8px; margin-top: 10px; flex-wrap: wrap; }
  .presets button { font-size: 13px; padding: 6px 10px; }
  .time-row { display: flex; gap: 12px; }
  .time-field { flex: 1; }
  .time-field label { display: block; font-size: 13px; color: rgba(243,239,232,0.55); margin-bottom: 4px; }
  .time-field input[type=time] { width: 100%; background: rgba(243,239,232,0.08);
        border: 1px solid rgba(243,239,232,0.18); color: #f3efe8; border-radius: 8px;
        padding: 9px 10px; font-size: 15px; }
  #status { margin-top: 14px; font-size: 14px; padding: 10px 12px; border-radius: 8px; display: none; }
  #status.ok { display: block; background: rgba(120,200,140,0.15); color: #a8e0b8; }
  #status.err { display: block; background: rgba(232,103,103,0.18); color: #f0a898; }
  .empty { color: rgba(243,239,232,0.4); font-size: 14px; padding: 6px 0; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Kiosk <span style="color:#e8b13f;">Control</span></h1>
  <div class="sub">Add, remove, reorder the kiosk's pages and set how fast it cycles — changes apply live, no reboot.</div>

  <div class="card">
    <h2>Rotation speed</h2>
    <div class="interval-row">
      <input type="number" id="interval" min="3" step="1">
      <span style="color:rgba(243,239,232,0.55); font-size:14px;">seconds per page</span>
    </div>
    <div class="presets">
      <button class="btn" data-secs="10">10s</button>
      <button class="btn" data-secs="15">15s</button>
      <button class="btn" data-secs="30">30s</button>
      <button class="btn" data-secs="60">1 min</button>
      <button class="btn" data-secs="120">2 min</button>
    </div>
  </div>

  <div class="card">
    <h2>Pages (top = first shown)</h2>
    <div id="pages"></div>
    <div class="empty" id="empty-msg" style="display:none;">No pages yet — add one below.</div>
    <div id="add-row" class="row" style="margin-top: 14px;">
      <input type="text" class="label-input" id="new-label" placeholder="Label (optional)">
      <input type="text" id="new-url" placeholder="https://...">
      <button class="btn" id="btn-add">+ Add</button>
    </div>
  </div>

  <button class="btn primary" id="btn-save">Save &amp; Apply Live</button>
  <div id="status"></div>

  <div class="card" style="margin-top: 18px;">
    <h2>Screen</h2>
    <div class="sub" style="margin: 0 0 12px;">Sleeps and wakes automatically on the schedule below. Use these to override right now, without waiting for the next scheduled time.</div>
    <div style="display: flex; gap: 8px; margin-bottom: 18px;">
      <button class="btn" id="btn-screen-off" style="flex: 1;">Sleep now</button>
      <button class="btn" id="btn-screen-on" style="flex: 1;">Wake now</button>
    </div>
    <div class="time-row">
      <div class="time-field">
        <label for="sleep-time">Sleep at</label>
        <input type="time" id="sleep-time">
      </div>
      <div class="time-field">
        <label for="wake-time">Wake at</label>
        <input type="time" id="wake-time">
      </div>
    </div>
    <button class="btn" id="btn-save-schedule" style="width: 100%; margin-top: 10px;">Save schedule</button>
  </div>
</div>

<script>
let pages = [];

function render() {
  const el = document.getElementById('pages');
  document.getElementById('empty-msg').style.display = pages.length ? 'none' : 'block';
  el.innerHTML = pages.map((p, i) => `
    <div class="row" data-i="${i}">
      <input type="text" class="label-input label-field" value="${esc(p.label)}" placeholder="Label">
      <input type="text" class="url-field" value="${esc(p.url)}" placeholder="https://...">
      <button class="btn up" ${i === 0 ? 'disabled' : ''} title="Move up">&uarr;</button>
      <button class="btn down" ${i === pages.length - 1 ? 'disabled' : ''} title="Move down">&darr;</button>
      <button class="btn danger remove" title="Remove">&times;</button>
    </div>
  `).join('');
  el.querySelectorAll('.row').forEach(row => {
    const i = parseInt(row.dataset.i, 10);
    row.querySelector('.label-field').addEventListener('input', e => pages[i].label = e.target.value);
    row.querySelector('.url-field').addEventListener('input', e => pages[i].url = e.target.value);
    row.querySelector('.up').addEventListener('click', () => { swap(i, i - 1); });
    row.querySelector('.down').addEventListener('click', () => { swap(i, i + 1); });
    row.querySelector('.remove').addEventListener('click', () => { pages.splice(i, 1); render(); });
  });
}
function swap(a, b) {
  if (b < 0 || b >= pages.length) return;
  [pages[a], pages[b]] = [pages[b], pages[a]];
  render();
}
function esc(s) {
  return (s || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

document.getElementById('btn-add').addEventListener('click', () => {
  const urlEl = document.getElementById('new-url'), labelEl = document.getElementById('new-label');
  const url = urlEl.value.trim();
  if (!url) return;
  pages.push({ label: labelEl.value.trim() || url, url });
  urlEl.value = ''; labelEl.value = '';
  render();
});

document.querySelectorAll('.presets button').forEach(b => {
  b.addEventListener('click', () => { document.getElementById('interval').value = b.dataset.secs; });
});

async function load() {
  const r = await fetch('/api/state');
  const data = await r.json();
  pages = data.pages;
  document.getElementById('interval').value = data.interval;
  if (data.schedule) {
    document.getElementById('sleep-time').value = data.schedule.sleep_time;
    document.getElementById('wake-time').value = data.schedule.wake_time;
  }
  render();
}

document.getElementById('btn-save').addEventListener('click', async () => {
  const statusEl = document.getElementById('status');
  const btn = document.getElementById('btn-save');
  btn.disabled = true; btn.textContent = 'Applying…';
  statusEl.className = ''; statusEl.style.display = 'none';
  try {
    const interval = parseInt(document.getElementById('interval').value, 10) || 30;
    const r = await fetch('/api/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pages, interval }),
    });
    const data = await r.json();
    statusEl.textContent = data.message;
    statusEl.className = data.ok ? 'ok' : 'err';
  } catch (e) {
    statusEl.textContent = 'Request failed: ' + e;
    statusEl.className = 'err';
  }
  statusEl.style.display = 'block';
  btn.disabled = false; btn.textContent = 'Save & Apply Live';
});

async function screenAction(action, btn) {
  const statusEl = document.getElementById('status');
  const label = btn.textContent;
  btn.disabled = true; btn.textContent = '…';
  statusEl.className = ''; statusEl.style.display = 'none';
  try {
    const r = await fetch('/api/screen', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action }),
    });
    const data = await r.json();
    statusEl.textContent = data.message;
    statusEl.className = data.ok ? 'ok' : 'err';
  } catch (e) {
    statusEl.textContent = 'Request failed: ' + e;
    statusEl.className = 'err';
  }
  statusEl.style.display = 'block';
  btn.disabled = false; btn.textContent = label;
}
document.getElementById('btn-screen-off').addEventListener('click', e => screenAction('off', e.target));
document.getElementById('btn-screen-on').addEventListener('click', e => screenAction('on', e.target));

document.getElementById('btn-save-schedule').addEventListener('click', async () => {
  const statusEl = document.getElementById('status');
  const btn = document.getElementById('btn-save-schedule');
  const sleepTime = document.getElementById('sleep-time').value;
  const wakeTime = document.getElementById('wake-time').value;
  if (!sleepTime || !wakeTime) {
    statusEl.textContent = 'Set both a sleep time and a wake time.';
    statusEl.className = 'err';
    statusEl.style.display = 'block';
    return;
  }
  btn.disabled = true; btn.textContent = 'Saving…';
  statusEl.className = ''; statusEl.style.display = 'none';
  try {
    const r = await fetch('/api/schedule', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sleep_time: sleepTime, wake_time: wakeTime }),
    });
    const data = await r.json();
    statusEl.textContent = data.message;
    statusEl.className = data.ok ? 'ok' : 'err';
  } catch (e) {
    statusEl.textContent = 'Request failed: ' + e;
    statusEl.className = 'err';
  }
  statusEl.style.display = 'block';
  btn.disabled = false; btn.textContent = 'Save schedule';
});

load();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype='application/json'):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            self._send(200, PAGE_HTML, 'text/html; charset=utf-8')
        elif self.path == '/api/state':
            sleep_time, wake_time = load_schedule()
            self._send(200, json.dumps({
                'pages': load_pages(),
                'interval': load_interval(),
                'schedule': {'sleep_time': sleep_time, 'wake_time': wake_time},
            }))
        else:
            self._send(404, json.dumps({'error': 'not found'}))

    def do_POST(self):
        if self.path == '/api/save':
            length = int(self.headers.get('Content-Length', 0))
            try:
                body = json.loads(self.rfile.read(length) or b'{}')
            except json.JSONDecodeError:
                self._send(400, json.dumps({'ok': False, 'message': 'Malformed request body.'}))
                return
            pages = [
                {'label': (p.get('label') or p.get('url', '')).strip(), 'url': p.get('url', '').strip()}
                for p in body.get('pages', []) if p.get('url', '').strip()
            ]
            interval = max(3, int(body.get('interval', 30) or 30))
            save_pages(pages)
            save_interval(interval)
            try:
                write_fullpageos_txt(pages)
                disk_msg = ''
            except Exception as e:
                disk_msg = f"Warning: couldn't write {FULLPAGEOS_TXT} ({e}) — check its permissions (see README.md). "
            live_ok, live_msg = push_live(pages)
            self._send(200, json.dumps({'ok': not disk_msg and live_ok, 'message': disk_msg + live_msg}))
        elif self.path == '/api/screen':
            length = int(self.headers.get('Content-Length', 0))
            try:
                body = json.loads(self.rfile.read(length) or b'{}')
            except json.JSONDecodeError:
                self._send(400, json.dumps({'ok': False, 'message': 'Malformed request body.'}))
                return
            action = body.get('action')
            if action not in ('on', 'off'):
                self._send(400, json.dumps({'ok': False, 'message': "action must be 'on' or 'off'."}))
                return
            ok, msg = screen_power(action)
            self._send(200, json.dumps({'ok': ok, 'message': msg}))
        elif self.path == '/api/schedule':
            length = int(self.headers.get('Content-Length', 0))
            try:
                body = json.loads(self.rfile.read(length) or b'{}')
            except json.JSONDecodeError:
                self._send(400, json.dumps({'ok': False, 'message': 'Malformed request body.'}))
                return
            sleep_time = (body.get('sleep_time') or '').strip()
            wake_time = (body.get('wake_time') or '').strip()
            if not TIME_RE.match(sleep_time) or not TIME_RE.match(wake_time):
                self._send(400, json.dumps({'ok': False, 'message': 'Times must be 24-hour HH:MM.'}))
                return
            ok, msg = apply_schedule_to_cron(sleep_time, wake_time)
            if ok:
                save_schedule(sleep_time, wake_time)
            self._send(200, json.dumps({'ok': ok, 'message': msg}))
        else:
            self._send(404, json.dumps({'error': 'not found'}))

    def log_message(self, fmt, *args):
        pass  # keep the systemd journal quiet — errors surface in the UI response instead


if __name__ == '__main__':
    server = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print(f'kiosk-control listening on :{PORT}')
    server.serve_forever()
