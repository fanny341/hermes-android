
**Step 4: Insert the info bar into the chat screen layout**

In `ChatScreen.build()`, add the session info bar between the `LinearProgressIndicator` and the `Expanded(body)`:

Current structure (lines 556-576):
```dart
body: Column(
  children: [
    // Loading bar
    if (_streaming)
      const LinearProgressIndicator(...),
    Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: ...,
          child: Column(
            children: [
              if (_error != null && _messages.isNotEmpty)
                MaterialBanner(...),
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    ),
  ],
),
```

Change to:
```dart
body: Column(
  children: [
    // Loading bar
    if (_streaming)
      const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
    // Session info bar
    _buildSessionInfoBar(),
    Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.isTablet(context) ? 800 : double.infinity,
          ),
          child: Column(
            children: [
              if (_error != null && _messages.isNotEmpty)
                MaterialBanner(...),
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    ),
  ],
),
```

This places a compact horiztonal-scrolling info chip bar right below the progress bar, showing model, source, message count, token count, and time.

**Step 5: Verify**

Run `flutter analyze lib/` — 0 errors.
Open a chat — the session info bar should appear showing model name, source, message count, tokens, and time.

**Step 6: Commit**

```bash
git add lib/core/screens/chat_screen.dart lib/core/services/connection_manager.dart
git commit -m "feat: add session info header bar showing model, source, tokens"
```

---

## Task 4: Ensure API returns `is_running` field

**Objective:** The Hermes Gateway API may not return `is_running` yet. Verify the endpoint and add fallback logic.

**Files:**
- Check: Hermes API server `GET /api/sessions/{session_id}` response

**Step 1: Check API response format**

Run from Termux:
```bash
API_KEY=$(grep API_SERVER_KEY ~/.hermes/.env | cut -d= -f2-)
curl -s http://127.0.0.1:8642/api/sessions?limit=1 \
  -H "Authorization: Bearer ${API_KEY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d[0] if isinstance(d,list) else d, indent=2))" 2>/dev/null | head -30
```

Check if `is_running` exists or if we should infer it from `isActive` + last activity timestamp.

**Step 2: Add fallback logic**

If the API doesn't have `is_running`, infer it:
- A session is "running" if it is `isActive` AND it has been updated within the last 60 seconds
- Or keep `isRunning` defaulting to false and accept that the spinner only shows for truly running sessions

Update `Session.fromJson` if needed:
```dart
isRunning: json['is_running'] ?? (endedAt == null && json['updated_at'] != null
    ? (DateTime.now().millisecondsSinceEpoch / 1000 - (json['updated_at'] as num).toDouble()) < 60
    : false),
```

**Step 3: Commit**

```bash
git add lib/core/models/session.dart
git commit -m "fix: session isRunning fallback logic"
```

---

## Task 5: Test all changes end-to-end

**Objective:** Verify the full user flow works correctly.

**Step 1: Build and deploy**

Push to GitHub and download the new APK.

**Step 2: Test session list loading**

- Open app → session list loads
- Active sessions show yellow chat icon
- If a session is actively streaming → shows spinning indicator
- Pull-to-refresh works

**Step 3: Test chat screen info bar**

- Open a session → session info bar visible below app bar
- Shows model name, source, message count, timestamp
- Horizontal scroll works on narrow screens
- Info bar doesn't overlap messages

**Step 4: Test polling stops**

- When no sessions are running, periodic polling stops (check with debug logs)

---

## Validation Summary

| Check | How | Target |
|-------|-----|--------|
| Session list spinner | Visual check | Running sessions show spinning indicator |
| Session list icons | Visual check | Finished/inactive show yellow/grey chat icon |
| Session info bar | Visual check | Model, source, count, time shown in chat |
| Info bar scroll | Visual check | Horizontally scrollable |
| Polling stops | DevTools/logs | No network calls when no running sessions |
| Flutter analyze | CI check | 0 errors |

## Risks & Tradeoffs

1. **API compatibility** — If the Gateway API doesn't have `is_running`, the fallback heuristic (last activity < 60s) may show false positives. Configurable threshold.
2. **Polling overhead** — 5-second polling while a session is running adds slight network traffic. Negligible for a single user.
3. **Info bar height** — The info bar takes vertical space. On small screens, the message area gets slightly smaller. The compact design (24px height) minimizes impact.
4. **Token counts** — Token usage may not be available from the API. The info bar gracefully hides the token chip if data is missing.

## Open Questions

- Should the info bar be collapsible (tap to hide/show)?
- Should the session info use a bottom sheet instead of a persistent bar?

---

**Plan complete and saved at `.hermes/plans/2026-07-29_132000-session-loading-header.md`**

Ready to execute using subagent-driven-development — I'll dispatch a fresh subagent per task with two-stage review. Shall I proceed?
