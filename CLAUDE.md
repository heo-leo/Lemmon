# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Memmon is a small macOS menu-bar daemon (Swift, no external dependencies) that saves window positions and restores them when the monitor configuration changes (e.g. unplugging an external display, closing the lid). The whole app is intentionally a single Swift file under ~300 lines (`src/main.swift`) — keep it that way unless the user explicitly asks to split things up.

Bundle id: `de.relikd.Memmon`. Min macOS: 10.10. Targets a universal (x86_64 + arm64) binary.

## Build / run

- `make` — build a universal `Memmon.app` bundle (release optimization). Compiles `src/main.swift` twice (one per arch), `lipo`s them, copies `src/Info.plist` and `img/AppIcon.icns`, then code-signs.
- `make CONFIG=debug` — same build with `-Onone -g`.
- `make release` — build the bundle and zip it as `Memmon_<version>.zip` (version pulled from `CFBundleShortVersionString` in Info.plist).
- `make clean` — remove `Memmon.app` and intermediate `bin_x64` / `bin_arm64`.
- `swift src/main.swift` — quickest way to run the daemon directly without bundling, for iteration.

Code signing is automatic in the Makefile: it uses an "Apple Development" identity if one is present in the keychain, otherwise falls back to ad-hoc (`codesign -s -`). The `-` prefix on `-codesign` / `-spctl` lets the build continue even if signing/assessment fails.

There is no test suite, no linter, and no package manager — `swiftc` from the Xcode command-line tools is the only toolchain.

## Architecture

The app is one `AppDelegate` driving two related state machines: window-state tracking and Mission Control space tracking. Both rely on undocumented behavior, so changes need care.

**Window state — `WinConf = [AppPID: [(WinNum, CGRect)]]`**, keyed by *number of attached screens* (`state[numScreens]`). Saving uses `CGWindowListCopyWindowInfo` (read-only, works across spaces); restoring uses the Accessibility API (`AXUIElement*`) because only AX can move windows. This split is fundamental — don't try to unify them.

**Trigger flow:** `applicationDidChangeScreenParameters` fires on monitor add/remove → `saveState()` snapshots windows for the *previous* `numScreens`, then `restoreState()` applies the snapshot for the new `numScreens`. The per-screen-count keying is what lets "1 monitor" and "2 monitor" layouts both be remembered.

**Spaces are tracked by planting an invisible `NSWindow` per space** (`currentSpace()`), since macOS gives no public API to enumerate Mission Control spaces. Each space's `NSWindow.windowNumber` becomes its `SpaceId`. The `spacesAll` / `spacesVisited` / `spacesNeedRestore` sets coordinate which spaces still need a restore pass — `restoreState()` only acts on the current space, and `activeSpaceChanged` re-fires it as the user switches spaces. Hence the README's caveat that windows on un-visited spaces only restore once that space is activated.

**Save-time subtlety in `saveState()`:** when a window is on a space we haven't visited, we deliberately copy the *old* saved bounds rather than the freshly-read ones, because un-visited windows often report as minimized and would otherwise corrupt the snapshot. The `dummy = (0, .zero)` placeholder is filtered out at restore time via `pt.isEmpty`.

**Status bar icon** is configured via `defaults write de.relikd.Memmon icon -int <0|1|2>` (0=hidden, 1=dots, 2=monitor; default 2). `enableInvisbleMode` only hides the icon for the current run — persistence requires `defaults`. The two icons are drawn programmatically in `NSImage` extensions at the bottom of `main.swift`; no asset catalog.

## Required entitlement

The app needs Accessibility permission (System Settings → Privacy & Security → Accessibility) to move windows. `applicationDidFinishLaunching` triggers the prompt via `AXIsProcessTrustedWithOptions`. Without it, save still works but restore silently no-ops.

## Versioning

Version lives in `src/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`) **and** in the menu title literal `"Memmon (v1.5)"` inside `main.swift`. Bump both when releasing.
