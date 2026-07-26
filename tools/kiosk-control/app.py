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

Requires (see the accompanying SETUP.md for exact one-time steps):
  - start_chromium_browser launched with --remote-debugging-port=9222
  - rotate_tabs.sh reading its interval from INTERVAL_FILE each loop
  - This directory and /boot/firmware/fullpageos.txt writable by the user
    this runs as (pi)

Stdlib only — no pip install needed on the Pi.
"""
import json
import os
import urllib.request
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KIOSK_DIR = os.path.dirname(os.path.abspath(__file__))
PAGES_FILE = os.path.join(KIOSK_DIR, 'pages.json')
INTERVAL_FILE = os.path.join(KIOSK_DIR, 'interval.txt')
FULLPAGEOS_TXT = '/boot/firmware/fullpageos.txt'
CDP_BASE = 'http://localhost:9222'
PORT = 7077

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
            self._send(200, json.dumps({'pages': load_pages(), 'interval': load_interval()}))
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
                disk_msg = f"Warning: couldn't write {FULLPAGEOS_TXT} ({e}) — check its permissions (see SETUP.md). "
            live_ok, live_msg = push_live(pages)
            self._send(200, json.dumps({'ok': not disk_msg and live_ok, 'message': disk_msg + live_msg}))
        else:
            self._send(404, json.dumps({'error': 'not found'}))

    def log_message(self, fmt, *args):
        pass  # keep the systemd journal quiet — errors surface in the UI response instead


if __name__ == '__main__':
    server = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print(f'kiosk-control listening on :{PORT}')
    server.serve_forever()
