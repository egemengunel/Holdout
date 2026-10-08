# Holdout

Your coding agents, iOS Simulator, Xcode builds and Mac health, on the Touch Bar.

Holdout adds a ✋ to the Control Strip. Tap it and a strip opens beside the Control Strip with four tabs:

- **Agents**: live sessions from Claude Code, Cursor, Codex (CLI and the ChatGPT app), Antigravity CLI and OpenCode. Working, waiting on you, done.
- **Sim**: dark mode, Dynamic Type, screenshots, status bar, push, location, boot.
- **Project**: Xcode build results, git state, and Build / Commit buttons that prompt the current agent.
- **Mac**: memory pressure, swap and CPU, with alerts only when you'd feel it.

The Control Strip icon flashes green when a session finishes, a hammer for builds, amber when an agent needs you, and red when memory is critical.

## Requirements

- A MacBook Pro with a Touch Bar, macOS 14 or later.
- Xcode to build it. There is no notarized download yet.

## Install

```bash
git clone https://github.com/egemengunel/Holdout.git
cd Holdout
xcodebuild -project Holdout.xcodeproj -scheme Holdout -configuration Release build
```

Copy the built `Holdout.app` to `/Applications` and open it (Product ▸ Archive ▸ Copy App also works). Then open **Settings…** from the menu bar icon and **Connect** the agents you use. Restart them afterwards.

## How it works

Holdout uses Apple's private Touch Bar APIs (DFRFoundation and `NSTouchBar` system-modal presentation), looked up at runtime so a future macOS that removes them fails soft. That also means it can't ship on the Mac App Store.

Agents report through a small hook script, `Hooks/holdout-hook.sh`, which writes one JSON file per session to `~/Library/Application Support/Holdout/`. Nothing leaves your Mac.

See `CLAUDE.md` for the architecture.

## License

MIT
