# Moritzu Hermes — Additional Fixes & Improvements Plan

> **For Hermes:** Execute this plan task-by-task.

**Goal:** Address code quality issues, dead code, potential rendering bugs, and missing UX polish found during codebase audit.

**Architecture:** Incremental improvements across chat screen, settings, and core services. Each task is independent.

**Tech Stack:** Flutter 3.44.8, Dart 3.12

---

## Task 1: Delete dead WebSocket client (312 lines)

**Objective:** Remove `lib/core/services/ws_client.dart` — it's never imported anywhere.

**Files:**
- Delete: `lib/core/services/ws_client.dart`

**Verification:**
```bash
grep -rn "ws_client" lib/ --include="*.dart"
# Should return nothing
flutter analyze lib/
```

**Commit:**
```bash
git rm lib/core/services/ws_client.dart
git commit -m "chore: remove dead WebSocket client (unused)"
```

---

## Task 2: Limit message history to prevent memory bloat

**Objective:** The `_messages` list in chat_screen.dart grows forever. After hundreds of messages, the app becomes sluggish. Cap it at 200 messages with a sliding window.

**Files:**
- Modify: `lib/core/screens/chat_screen.dart`

**Step 1: Add constant near the top of the state class**

```dart
static const int _maxMessages = 200;
```

**Step 2: Trim messages after adding a new one**

In `_sendMessage`, right after `setState` that adds the user message, add:

```dart
if (_messages.length > _maxMessages) {
  // Keep only the last _maxMessages, but always keep the first system message
  final systemMsgs = _messages.where((m) => m['role'] == 'system').toList();
  final recentMsgs = _messages.reversed.take(_maxMessages - systemMsgs.length).toList().reversed.toList();
  _messages = [...systemMsgs, ...recentMsgs];
}
```

**Verification:** Open a chat, send many messages, verify the list doesn't grow past 200.

**Commit:**
```bash
git add lib/core/screens/chat_screen.dart
git commit -m "perf: limit chat message history to 200 messages"
```

---

## Task 3: Add network timeout to all API calls

**Objective:** If the Hermes gateway is unreachable, the app currently hangs forever showing "Connecting…". Add a 15-second timeout.

**Files:**
- Modify: `lib/core/services/connection_manager.dart`

**Step 1: Add timeout wrapper**

In `ApiClient`, wrap the HTTP client calls:

```dart
static const Duration _requestTimeout = Duration(seconds: 15);

Future<http.Response> _getWithTimeout(Uri url) {
  return _http.get(url, headers: _headers).timeout(_requestTimeout);
}

Future<http.Response> _postWithTimeout(Uri url, {Object? body}) {
  return _http.post(url, headers: _headers, body: body).timeout(_requestTimeout);
}
```

Or if `_http` is shared, add timeout to the client itself:
```dart
final _http = http.Client();
// In constructor or init:
_http = http.Client()..post(/* ... */).timeout(Duration(seconds: 15));
```

Alternatively, set a global timeout when creating the `http.Client` by wrapping with `.timeout()` on each call.

**Step 2: Update all call sites**

Replace direct `_http.get(...)` and `_http.post(...)` calls with the timeout-wrapped versions.

**Verification:** Stop the gateway and try opening the app → error shows in < 15 seconds instead of hanging forever.

**Commit:**
```bash
git add lib/core/services/connection_manager.dart
git commit -m "fix: add 15s timeout to all API requests"
```

---

## Task 4: Make verbose metadata default-off

**Objective:** The debug metadata (role, id, session_id) confuses normal users. It should default to OFF.

**Files:**
- Modify: `lib/core/screens/chat_screen.dart`

**Step 1: Change default to false**

Find the `_verboseMode` initialization (around line 486):
```dart
bool _verboseMode = true;  // Change to false
```

Or if it loads from SharedPreferences:
```dart
_prefs.getBool('verbose_mode') ?? false  // No need to change — already defaults to false
```

Check line ~81 where it's initialized. Make sure `false` is the default.

**Verification:** Open any chat → no debug metadata visible. Toggle via menu → metadata appears.

**Commit:**
```bash
git add lib/core/screens/chat_screen.dart
git commit -m "fix: verbose metadata default off"
```

---

## Task 5: Fix tool progress card rendering gap

**Objective:** In `_buildBody` (line 750-757), the `currentGroup` list collects tool messages but is never flushed to `displayMessages` at the end of the loop. If the last messages in the list are tool messages, they won't render.

**Files:**
- Modify: `lib/core/screens/chat_screen.dart`

**Step 1: Flush remaining tool group after the loop**

After the main `for` loop in `_buildBody`, add:

```dart
// Flush any remaining tool group
if (currentGroup.isNotEmpty) {
  displayMessages.add([...currentGroup]);
  currentGroup.clear();
}
```

This ensures tool messages at the end of the list are rendered.

**Verification:** Send a message that triggers tool calls. Verify the tool progress card appears even if it's the last item.

**Commit:**
```bash
git add lib/core/screens/chat_screen.dart
git commit -m "fix: flush tool progress group when messages end with tool calls"
```

---

## Task 6: Add "Clear local cache" to settings

**Objective:** Let users clear SharedPreferences cache (connection history, auto-login data) from the settings screen.

**Files:**
- Modify: `lib/core/screens/settings_screen.dart`

**Step 1: Add a "Clear Cache" button**

Add a ListTile at the bottom of the settings list:
```dart
ListTile(
  leading: const Icon(Icons.delete_sweep),
  title: const Text('Clear local cache'),
  subtitle: const Text('Remove saved connections and preferences'),
  onTap: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'This will remove saved connection history and preferences. '
          'Remote sessions on the gateway are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared. Restart to take effect.')),
      );
    }
  },
)
```

**Verification:** Open Settings → tap "Clear local cache" → confirm → snackbar shows → restart app → connection list is empty.

**Commit:**
```bash
git add lib/core/screens/settings_screen.dart
git commit -m "feat: add clear local cache button to settings"
```

---

## Task 7: Show loading indicator on session list FIRST load

**Objective:** When the app starts, the session list shows "Connecting…" while checking health, but there's no progress indicator while actually fetching sessions. Add a loading state.

**Files:**
- Already exists at line 472: `if (_loading) return const Center(child: CircularProgressIndicator());`

**Check:** This already exists. The user may have been experiencing a stale connection where `_loading` was never set to true. Verify that `_fetchSessions` is actually called.

Add a RefreshIndicator wrapper if not present (line 526 already has it).

This task may already be done — verify.

**Commit:** Only if changes needed.

---

## Summary of Suggested Fixes

| # | Issue | Severity | Effort |
|---|-------|----------|--------|
| 1 | Dead ws_client.dart (312 lines) cleanup | Low | 1 min |
| 2 | Unbounded message history (memory leak) | Medium | 5 min |
| 3 | No network timeout (hangs forever) | High | 10 min |
| 4 | Verbose metadata ON by default (confusing) | Medium | 1 min |
| 5 | Tool progress card may not render at end of list | Medium | 2 min |
| 6 | No clear cache in settings | Low | 5 min |
| 7 | Session list loading check | Verify | 1 min |

## Risk Assessment

- **Network timeout** could break existing working calls if 15s is too short. Set to 30s for safety, 15s for UX.
- **Message trimming** could drop messages if history exceeds 200. Since the Hermes API paginates, this is safe.
- **Verbose default-off** doesn't break anything — just changes a UX default.

## Open Questions

- Should the app show a "Cache: 2.1 MB" size indicator before clearing?
- Should we add a "Report bug" / feedback button in the drawer?
- Should the app auto-refresh when coming back from background (restore connectivity)?
- Do we need a "Send feedback" / "Logs" screen for diagnostics?

---

**Plan saved at `.hermes/plans/2026-07-29_133500-additional-fixes.md`**

Ready to execute. Shall I proceed?
