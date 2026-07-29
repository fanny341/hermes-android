# Moritzu Hermes — Switch to Release Builds & Remove Debug

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Replace the debug APK build with a properly optimized release APK, cutting size from 152 MB to ~25-35 MB while enabling full R8 optimization, ProGuard shrinking, and ABI splitting.

**Architecture:** The current CI builds `flutter build apk --debug --no-tree-shake-icons` producing an unoptimized 152 MB APK. Switching to `flutter build apk --release` enables: code shrinking (R8/ProGuard), resource shrinking, icon tree-shaking, DEX optimization, and native symbol stripping — all automatically. Combined with ABI splitting (arm64-v8a only), the release APK will be ~25-35 MB.

**Tech Stack:** Flutter 3.44.8, Dart 3.12, Android SDK 36, GitHub Actions CI, R8/ProGuard

---

## Task 1: Update CI workflow to build release APK

**Objective:** Replace `flutter build apk --debug` with `flutter build apk --release` in the CI workflow.

**Files:**
- Modify: `.github/workflows/build-apk.yml`

**Step 1: Edit the build step**

Change:
```yaml
      - name: Build debug APK
        run: flutter build apk --debug --no-tree-shake-icons
```
To:
```yaml
      - name: Build release APK (unsigned)
        run: flutter build apk --release --no-shrink
```

The `--no-shrink` flag is added temporarily to avoid ProGuard/R8 issues on first build. We'll enable shrinking in Task 2.

**Step 2: Update artifact name and path**

Change:
```yaml
      - name: Upload debug APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: build/app/outputs/flutter-apk/app-debug.apk
```
To:
```yaml
      - name: Upload release APK
        uses: actions/upload-artifact@v4
        with:
          name: moritzu-hermes-release
          path: build/app/outputs/flutter-apk/app-release.apk
```

**Step 3: Commit & verify**

```bash
git add .github/workflows/build-apk.yml
git commit -m "build: switch CI from debug to release APK"
git push
```

Check CI — the release APK should build successfully and be around 35-45 MB (without shrinking yet).

---

## Task 2: Add ABI split for arm64-v8a only

**Objective:** Split the APK to contain native libraries ONLY for arm64-v8a, cutting the APK size by ~60%.

**Files:**
- Modify: `android/app/build.gradle.kts`

**Step 1: Add `splits` block inside `android { }`**

Open `android/app/build.gradle.kts`. After the `buildTypes { }` closing brace, add:

```kotlin
    splits {
        abi {
            enable true
            reset()
            include "arm64-v8a"
            universalApk false
        }
    }
```

**Step 2: Update CI artifact path for split APK**

When ABI splits are enabled, the APK path changes. Update `.github/workflows/build-apk.yml`:

Change:
```yaml
          path: build/app/outputs/flutter-apk/app-release.apk
```
To:
```yaml
          path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

**Step 3: Verify**

Run on CI — APK should now be ~20-30 MB.

**Step 4: Commit**

```bash
git add android/app/build.gradle.kts .github/workflows/build-apk.yml
git commit -m "build: split APK to arm64-v8a only"
git push
```

---

## Task 3: Create ProGuard rules and enable R8 shrinking

**Objective:** Enable code shrinking, resource shrinking, and optimization to reduce APK size by an additional 10-15 MB.

**Files:**
- Create: `android/app/proguard-rules.pro`
- Modify: `android/app/build.gradle.kts`

**Step 1: Create ProGuard keep rules**

Write `android/app/proguard-rules.pro`:

```proguard
# Flutter engine native methods
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep serialization
-keepattributes *Annotation*, Signature
-keep class * extends java.util.List { *; }
-keep class * extends java.util.Map { *; }

# app models (json_serializable)
-keep class moritzu.hermes.** { *; }

# HTTP/networking
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# WebSocket
-keep class web_socket_channel.** { *; }

# Speech recognition & TTS native libs
-keep class com.speech_to_text.** { *; }
-keep class com.flutter_tts.** { *; }
```

**Step 2: Update build.gradle.kts to enable shrinking**

In `android/app/build.gradle.kts`, update the `release` build type:

```kotlin
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
```

**Step 3: Remove `--no-shrink` from CI**

Update `.github/workflows/build-apk.yml`:

```yaml
      - name: Build release APK
        run: flutter build apk --release
```

**Step 4: Verify**

Run CI — APK should be ~15-25 MB.

If the build fails (ProGuard stripping something needed), add more `-keep` rules to `proguard-rules.pro` and retry.

**Step 5: Commit**

```bash
git add android/app/proguard-rules.pro android/app/build.gradle.kts .github/workflows/build-apk.yml
git commit -m "build: enable R8 shrinking + ProGuard rules"
git push
```

---

## Task 4: Remove debug tools and verbose mode cruft

**Objective:** Clean up leftover debug UI features that add code weight and complexity.

**Files:**
- Modify: `lib/core/screens/chat_screen.dart`
- Modify: `lib/main.dart`

**Step 1: Remove verbose debug metadata feature entirely**

In `lib/core/screens/chat_screen.dart`:
- Remove `_verboseMode` field, its SharedPreferences loading (line ~81), and the PopupMenuButton that toggles it (added in recent commit)
- Remove the `verbose` parameter and conditional metadata rendering from `_MessageBubble`
- Remove `verbose` parameter from `_ToolProgressCard`

The debug metadata was a development tool, not useful for end users. Removing it simplifies the code and removes ~20 lines of widget code.

**Step 2: Remove any dev/debug-only UI in main.dart**

Check `lib/core/screens/settings_screen.dart` for any "Enable debug mode" or "Verbose mode" toggles. Remove them.

**Step 3: Verify**

Run `flutter analyze lib/` — 0 errors, 0 warnings.

**Step 4: Commit**

```bash
git add lib/core/screens/chat_screen.dart lib/main.dart
git commit -m "refactor: remove debug verbose metadata feature"
git push
```

---

## Task 5: Remove unused dependencies

**Objective:** Remove packages from pubspec.yaml that are no longer used, reducing APK size and dependency tree.

**Files:**
- Modify: `pubspec.yaml`
- Check: `lib/core/services/ws_client.dart` (312 lines, dead WebSocket client)

**Step 1: Check which packages are actually imported**

Run:
```bash
grep -rn "^import.*package:" lib/ | sort | uniq
```

**Step 2: Remove unused packages**

Likely candidates:
- `web_socket_channel` — only used by `ws_client.dart` which is dead code
- `highlight` — markdown syntax highlighting; check if used in chat_screen.dart
- `flutter_riverpod` — check if any file imports it
- `cupertino_icons` — only used if `CupertinoIcons` appear in code

For each unused package:
```yaml
# Remove the dependency line from pubspec.yaml
```

**Step 3: Delete dead WebSocket client**

If `ws_client.dart` is truly dead (no imports reference it), delete it:
```bash
rm lib/core/services/ws_client.dart
```

**Step 4: Verify**

```bash
flutter pub get
flutter analyze lib/
```

**Step 5: Commit**

```bash
git add pubspec.yaml
git rm lib/core/services/ws_client.dart
git commit -m "chore: remove unused deps and dead WebSocket client"
git push
```

---

## Task 6: Mark release APK as downloadable artifact

**Objective:** Users can download the optimized release APK directly from GitHub Actions.

**Files:**
- No changes needed — CI already uploads artifact

**Step 1: Verify final CI run**

Check that the Build APK workflow completes successfully with:
- APK size: ~15-25 MB
- Workflow: green
- Artifact: downloadable as `moritzu-hermes-release`

**Step 2: Tell user where to get it**

```
Download from: https://github.com/fanny341/hermes-android/actions
→ Latest "Build APK" run → Artifacts → moritzu-hermes-release
```

---

## Validation Summary

| Check | How | Target |
|-------|-----|--------|
| APK size | CI artifact | 15-25 MB |
| Flutter analyze | CI check | 0 errors |
| Chat send | Manual test | streaming works |
| Voice features | Manual test | speech in/out works |
| GitHub Actions | CI pipeline | all green |

## Risks & Tradeoffs

1. **Unsigned release APK** — Release APKs signed with Flutter's debug keystore won't install over the old debug APK (signature mismatch). User needs to uninstall old app first.
2. **R8/ProGuard** — May break Flutter plugin code. The `--no-shrink` escape hatch lets us verify the base build first, then enable shrinking incrementally by adding keep rules.
3. **ABI split** — Only arm64-v8a supported. Virtually all modern Android phones are arm64-v8a, so this is safe.
4. **Dead code removal** — If `ws_client.dart` is truly unused, deleting it is safe. Verify no imports reference it.

## Open Questions

- User needs to uninstall the old debug APK before installing the new release APK (signing conflict). Should we add a note in the README?
- Should we also add a debug APK job as a CI option for development testing (triggered manually via workflow_dispatch)?

---

**Plan complete and saved.** Ready to execute using subagent-driven-development — I'll dispatch a fresh subagent per task with two-stage review. Shall I proceed?
