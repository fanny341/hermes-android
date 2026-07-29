# Moritzu Hermes 🤖

[![Build APK](https://github.com/fanny341/hermes-android/actions/workflows/build-apk.yml/badge.svg)](https://github.com/fanny341/hermes-android/actions/workflows/build-apk.yml)

A Flutter chat client for [Hermes AI](https://hermes-agent.nousresearch.com) — run your agent from a phone or tablet.

## Features

- **Chat with your Hermes agent** via the built-in API server (port 8642)
- **Streaming responses** with thinking indicator, cancel/stop button, and regenerate
- **Session management** — rename, fork, delete; search sessions by title
- **Session info header** — shows model, source, message count, token usage, timestamps
- **Toolsets & Runs** — view available toolsets, submit and monitor agent runs
- **Auto-discovery** — scan your local network for Hermes servers
- **Auto-login** — one-tap reconnect with saved credentials
- **Dark/Light theme** — switchable from settings
- **Debug metadata** — optional toggle for raw message fields (role, id, session_id)
- **Message actions** — long-press to copy, timestamps on every message
- **Loading indicators** — spinner on running sessions, progress bar during streaming
- **Arm64-v8a optimized** — small APK size (~25 MB)

## Quick Start

1. **Enable the API server on your Hermes agent:**
   ```yaml
   # ~/.hermes/config.yaml
   api_server:
     enabled: true
     host: 0.0.0.0
     port: 8642
   ```

2. **Install the APK** — download the latest from:
   ```
   https://github.com/fanny341/hermes-android/actions
   ```
   Click the latest **Build APK** run → **Artifacts** → download the versioned APK zip.

3. **Open the app** — tap the **Quick Setup** button
   - Host: `127.0.0.1` (same device) or your LAN IP
   - Port: `8642`
   - API key: from your `~/.hermes/.env`
   - Dashboard: `admin` / `admin`

4. **Chat away!**

## Download the Latest APK

Every push to `main` triggers an automated build. Download from:
```
https://github.com/fanny341/hermes-android/actions/workflows/build-apk.yml
```

APK naming: `moritzu-hermes-v<version>.zip` (e.g. `moritzu-hermes-v1.0.14+114`)
Version format: `1.0.<GitHub Run Number>+<Run Number>`

## Build from Source

```bash
flutter pub get
flutter build apk --release   # or --debug
```

Requires Flutter SDK 3.44+ and Android SDK 34+.

## Tech Stack

- **Framework:** Flutter 3.44 (Dart 3.12)
- **State:** Riverpod (minimal usage)
- **Storage:** SharedPreferences
- **API:** Hermes REST API (sessions, chat, memory, cron, skills, toolsets, runs)
- **Build:** GitHub Actions CI with auto-versioning

## Version History

| APK Version | Date | Changes |
|-------------|------|---------|
| 1.0.14+114 | 2026-07-29 | Release build (arm64-v8a), auto-versioning, ProGuard, dead code cleanup |
| 1.0.13+113 | 2026-07-29 | Thinking indicator, verbose toggle, error banner, debug metadata fix |
| earlier | — | Initial rebrand, auto-login, session management, CI setup |

## License

Forked from [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android). License unknown — upstream did not specify one.
