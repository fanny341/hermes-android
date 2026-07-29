# Hermes Android — Termux Bridge + API Improvements

Forked from [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android)
with enhancements for Termux users and broader Hermes API coverage.

## What Changed

### 1. Termux Auto-Discovery (zero-config connect)

No more typing IP addresses. The app scans the local network for Hermes
API servers automatically:

- Tap the **wifi-find** FAB on the home screen
- Probes `127.0.0.1:8642` (same device), then entire /24 subnet,
  then common gateway IPs
- Found servers show version + whether a saved key validates
- Tap a result → fields pre-filled → Connect

### 2. Native API Server (no bridge script needed)

Hermes' built-in `api_server` (port 8642) exposes everything the app
needs without the dashboard. The old `hermes_bridge.py` raw-socket hack
is obsolete — killed and replaced with native HTTP API calls.

### 3. New Screens

**Toolsets** (drawer → Toolsets)
- All 25+ Hermes toolsets with enabled/configured/disabled status
- Tool count + individual tool names per toolset
- Uses `GET /v1/toolsets` (no dashboard needed)

**Async Runs** (drawer → Async Runs)
- Submit async agent tasks via `POST /v1/runs`
- Auto-polls status every 2s until completed/failed
- View markdown output in expandable cards
- Stop running tasks via `POST /v1/runs/{id}/stop`

### 4. Session Forking

Long-press any session → **Fork** to branch it.
Uses `POST /api/sessions/{id}/fork`.

## Termux Setup (on the phone running Hermes)

```bash
# 1. Generate an API key
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# 2. Add to ~/.hermes/.env
cat >> ~/.hermes/.env << 'EOF'
API_SERVER_KEY=<paste-key-here>
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
EOF

# 3. Enable api_server platform in config
python3 -c "
import yaml
path = '$HOME/.hermes/config.yaml'
with open(path) as f: cfg = yaml.safe_load(f)
cfg.setdefault('platforms', {})['api_server'] = {
    'enabled': True,
    'extra': {'host': '0.0.0.0', 'port': 8642, 'cors_origins': '*'}
}
with open(path, 'w') as f: yaml.dump(cfg, f, default_flow_style=False)
"

# 4. Start the gateway
hermes gateway run

# 5. Kill old bridge script if running
pkill -f hermes_bridge.py
```

### Verify

```bash
curl http://127.0.0.1:8642/health
# → {"status": "ok", "platform": "hermes-agent", "version": "0.19.0"}
```

### Connect from the app

1. Open Hermes Android app
2. Tap the **wifi-find** (scan) button
3. Select your device from the discovered list
4. Enter API key if not auto-detected → Connect

## New API Methods (ApiClient)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `getToolsets()` | `GET /v1/toolsets` | List all agent toolsets |
| `getApiSkills()` | `GET /v1/skills` | Skills without dashboard |
| `getCapabilities()` | `GET /v1/capabilities` | Feature detection |
| `forkSession(id)` | `POST /api/sessions/{id}/fork` | Branch a session |
| `submitRun(input:)` | `POST /v1/runs` | Start async agent task |
| `getRunStatus(id)` | `GET /v1/runs/{id}` | Poll run status |
| `stopRun(id)` | `POST /v1/runs/{id}/stop` | Interrupt a run |

## Files Added

- `lib/core/services/termux_discovery.dart` — LAN auto-discovery scanner
- `lib/core/screens/toolsets_screen.dart` — toolsets browser
- `lib/core/screens/runs_screen.dart` — async run submission + polling

## Files Modified

- `lib/main.dart` — scan dialog, FAB, pre-fill from discovery
- `lib/core/services/connection_manager.dart` — 7 new API methods
- `lib/core/screens/session_list_screen.dart` — toolsets/runs drawer, fork

## Verified

- 18/18 ad-hoc checks pass (brace balance, imports, methods, screens)
- Live API tested: `/health`, `/v1/toolsets`, `/v1/skills`,
  `/v1/capabilities`, `/api/sessions`, `/v1/models`, `/v1/runs` lifecycle,
  `/api/sessions/{id}/fork` — all return 200 with correct data
- `flutter analyze` / `flutter test` NOT run (no Flutter SDK on Termux).
  CI on push will validate.
