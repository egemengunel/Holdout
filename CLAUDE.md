# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Holdout is a personal macOS menu bar app (AppKit, no windows) for the 13" M2 MacBook Pro Touch Bar. It puts an icon in the Control Strip that opens a system-wide strip with four tabs: Agents (coding agent sessions: Claude Code, Cursor, Codex, Gemini CLI, Antigravity, OpenCode), Sim (iOS Simulator controls), Project (Xcode builds and Claude Code mod state), and Mac (a memory and CPU watchdog).

## Build and run

```bash
xcodebuild -project Holdout.xcodeproj -scheme Holdout build
claude plugin validate Mods/holdout-bridge
Hooks/install.sh            # register the agent hook with every agent found (or name them)
```

There are no tests. Run from Xcode with ⌘R; the shared scheme has **Debug executable off** on purpose, because Xcode's debugger takes over the Control Strip slot.

To inspect the Touch Bar without the user: `screencapture -b out.png` captures it, and launching with `-HoldoutOpenOnLaunch YES` opens the strip and logs the content view tree after 2 s (`TouchBarController.dumpLayout()`). Only one Holdout can own the Control Strip item, so ask before quitting the user's running copy.

## Architecture

MV: models are value types, stores own and watch state, each tab is an AppKit strip view drawn from them, and `TouchBar/TouchBarController` coordinates (tab switching, the Control Strip icon, refresh on a 1 s ticker and on store changes). Files are grouped by feature under `Holdout/Features/`; the app target uses synchronized folders, so new files need no project edits. Default actor isolation is `MainActor` (Swift 5 mode).

### Private Touch Bar API

`TouchBar/SystemTouchBar` wraps private DFRFoundation / `NSTouchBar` calls, looked up at runtime (`dlsym`, `class_getClassMethod`) so their removal fails soft. The app is unsandboxed and an `LSUIElement` agent. Behaviors verified on device that the code depends on:

- Presented with placement `0` the strip sits beside the Control Strip and the system draws its native ✕ whenever another app is frontmost, which is why Holdout must stay a background agent. There is deliberately no custom close button.
- Closing the strip drops Holdout's Control Strip item; `TouchBarController` observes `NSTouchBar.isVisible` and re-calls `showInControlStrip`. Xcode's debugger takes the slot whenever it debugs any app, so the controller reclaims it on every app switch and every 5 s while the strip is closed (a no-op when already held).
- Items are sized purely from `intrinsicContentSize`, and an item that doesn't fit is **hidden, not clipped**. The bar is ~1004 pt wide. `FlexibleWidthView` starts at a small minimum and grows into the measured free space; never give tab content a fixed width. Overflowing rows scroll horizontally inside it.
- Background apps can't `activate()` others on macOS 14+; bring apps forward with `NSWorkspace.openApplication`.

`TouchBar/IconPulse` maps status to the Control Strip icon's symbol, color and motion; `StatusIconView` plays it, entirely in layers: the background color is Core Animation (animating a bordered `NSButton`'s `bezelColor` from a timer re-rendered its bezel in software, ~35% CPU vs ~0.3% now), and the symbol is a pre-rendered white bitmap, because template symbols in a custom Touch Bar view (`NSImageView`, borderless `NSButton`) draw dimmed gray. An invisible borderless button takes the taps. Priority: red alert (failed build or Mac distress) > amber waiting > brief flashes (orange heads-up, then green done/build) play over working > blue working.

### Data flow from outside the app

All of it lands in `~/Library/Application Support/Holdout/`:

- `sessions/<session>.json`: written by `Hooks/holdout-hook.sh [agent] [event]`, registered by `Hooks/install.sh` in `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/settings.json` (Gemini CLI), `~/.gemini/config/hooks.json` (Antigravity), and via the `Hooks/opencode/holdout.js` plugin for OpenCode, which has no command hooks. It translates every agent's events to Claude Code's names (SessionStart, UserPromptSubmit, Pre/PostToolUse, Notification, PermissionRequest, Stop, SessionEnd, plus Interrupt for a cancelled turn), which is all `AgentSession` reads, and records `agent`. It must never block: always exit 0 and print nothing, except `{}` for Gemini and Antigravity, which parse stdout as JSON. It writes atomically by rename, so `SessionStore` uses a directory `DispatchSource`. SessionEnd deletes the file; the Claude desktop app only ends a session when its chat is deleted, so "file present" means "chat still exists".
  - Cursor runs the hooks in `~/.claude/settings.json` itself, with its own camelCase names (`beforeSubmitPrompt`, `stop` with `status`…), `workspace_roots` instead of `cwd`, and `cursor_version`, which is how the hook tells it apart. Its subagents report under their own id with `parent_tool_call_id` and are skipped. It also fires `sessionStart` for empty draft chats, which is why SessionStart must stay idle. It has no approval-prompt hook, but `preToolUse` fires before the prompt and `postToolUse` only after the answer (its `duration` excludes the wait), so `AgentSession` shows "needs you" when a Shell or MCP tool has been pending for 8 s. Long unsandboxed builds trip it too. `beforeShellExecution` / `beforeMCPExecution` (no Claude Code equivalent, so `Hooks/install.sh` registers them natively in `~/.cursor/hooks.json`) only record `sandboxed`: sandboxed commands never ask, so they are exempt. Their reply must stay empty (verified: Cursor doesn't block on it). Cursor's `permission: "ask"` is a known no-op, so Holdout can't force prompts either.
  - Antigravity's payloads are camelCase and name no event, so each registration passes it. Holdout doesn't register its `PreToolUse`: the reply must be a permission decision. On current builds only the `agy` CLI runs hooks, not the IDE or desktop app. Codex skips new hooks until trusted in `/hooks`.
- `feeds/<session>.json`: written by the `Mods/holdout-bridge` Claude Code mod (loaded via `CLAUDE_CODE_PLUGIN_DIRS`), which mirrors the user's `ios-dock` and `swift-design-lint` mods' `$.state` every 2 s. Mods write in place, so `ProjectFeedStore` polls modification dates. The Project tab shows the feed of the live session (per `SessionStore`) touched most recently. `ios-dock`'s build result has no timestamp, so the bridge adds `buildAt` (when it last changed) to compare it with Xcode's own builds.
- `commands/<session>.json`: written by Holdout's Project tab buttons; the bridge picks each command up once (by `id`) and submits the matching prompt, kept in step with `ios-dock`'s `ACTIONS`.
- Xcode builds come from `~/Library/Developer/Xcode/DerivedData/*/Logs/Build/LogStoreManifest.plist`, polled by `XcodeBuildWatcher`.

The bridge's `types/index.d.ts` copies the slices of the other mods' state contracts it reads; update it if those mods change. Mod hook functions that receive `$` must be top-level functions or `claude plugin validate` refuses them.

### Simulator

`Features/Simulator/Simulator` shells out to `xcrun simctl` (via `Shared/Shell`). Xcode 27 replaced Simulator.app with DeviceHub.app (`com.apple.dt.Devices`); both bundle IDs are tried when bringing it forward.

## Conventions

- Tabs show news, not placeholders: a chip appears only when it has something to say (the Project tab drops "no build yet"-style chips, puts failures first, and groups actions in one segmented control).
- Prefer native AppKit Touch Bar controls and SF Symbols over custom drawing; tab bar icons are outline symbols.
- `Features/Mac` samples every 5 s through sysctl, Mach host statistics and `proc_pid_rusage` (CPU times are Mach ticks; convert with the timebase). Processes are summed by name.
- The Mac tab's watchdog must be generic for low-RAM Macs, with no per-machine baselines or hardcoded process lists. Alert on what the user would feel, not on size: swap of 10–20 GB and kernel "warning" pressure are normal on 8 GB and never alert. Red (distress, until the tab is opened): critical pressure for 60 s, i.e. when Activity Monitor's graph turns red. Swap-in rate is shown, not alerted on: 20+ MB/s is normal heavy use on 8 GB. An alert that returns within 10 min is the same alert and doesn't flash again once seen. Orange heads-up (two soft flashes, at most every 30 min per kind): a process above 80% of a core for 3 min.
