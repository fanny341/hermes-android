# Moritzu Hermes 🤖

A Flutter chat client for [Hermes AI](https://hermes-agent.nousresearch.com) — run your agent from a phone or tablet.

## Features

- **Chat with your Hermes agent** via the built-in API server (port 8642)
- **Session management** — rename, fork, delete sessions; switch between them
- **Session switcher** — quickly jump between conversations from within the chat screen
- **Toolsets & Runs** — view available toolsets, submit and monitor agent runs
- **Auto-discovery** — scan your local network for Hermes servers
- **Auto-login** — one-tap reconnect with saved credentials (localhost:8642, API key, dashboard)
- **AMOLED-ready** — dark theme optimized for OLED screens
- **Loading indicators** — spinner on running sessions, progress bar during streaming

## Quick Start

1. **Enable the API server on your Hermes agent:**
   ```yaml
   # ~/.hermes/config.yaml
   api_server:
     enabled: true
     host: 0.0.0.0
     port: 8642
   ```

2. **Install the APK** (download from [Releases](https://github.com/fanny341/hermes-android/releases))

3. **Open the app** — tap the **Quick Setup** button
   - Host: `127.0.0.1` (same device) or your LAN IP
   - Port: `8642`
   - API key: from your `~/.hermes/.env`
   - Dashboard: `admin` / `admin`

4. **Chat away!**

## Build from Source

```bash
flutter pub get
flutter build apk --debug   # or --release
```

Requires Flutter SDK 3.44+ and Android SDK 34+.

## Tech Stack

- **Framework:** Flutter 3.44 (Dart 3.12)
- **State:** Riverpod (minimal usage)
- **Storage:** SharedPreferences (plaintext — P0 issue, PRs welcome)
- **API:** Hermes REST API (sessions, chat, memory, cron, skills, toolsets, runs)

## License

Forked from [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android). License unknown — upstream did not specify one.
