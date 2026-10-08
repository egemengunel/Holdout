# What each agent allows

Researched October 2026 from each agent's docs, plus tests on a real Mac where noted.
"Idle chat" means a chat that isn't mid-turn.

| Agent | Status in Holdout | Prompt into an idle chat | While a turn runs | Deep links |
|---|---|---|---|---|
| Claude Code (CLI, desktop, IDE) | Hooks in `~/.claude/settings.json`; one entry covers all three | holdout-bridge plugin submits it; without the plugin, clipboard | bridge | `claude://code/new?q=&folder=` (desktop) and `claude-cli://open?q=&cwd=` (terminal) open a new session with the prompt pre-filled, never sent |
| Cursor | Reads Claude's hooks; native `~/.cursor/hooks.json` adds shell/MCP hooks | Accessibility paste into the chat input (`CursorChat`) | follow-up at Stop | `cursor.com/link/prompt?text=` pre-fills a new chat; nothing auto-runs, `&` handling is unreliable, 8,000 chars max |
| Codex (CLI + ChatGPT app) | `~/.codex/hooks.json`; **hooks must be trusted** (`/hooks`, or the app's prompt); CLI and app share it (verified) | none: clipboard, and `codex://threads/<id>` opens the chat | follow-up at Stop (`decision: block`) | `codex://threads/<id>`, `codex://settings/...`, `codex://review`; no prompt parameter found |
| Gemini CLI | `~/.gemini/settings.json` | none | `AfterAgent` `decision: deny` + `reason` becomes the next prompt | none |
| Antigravity | `~/.gemini/config/hooks.json`; **only the `agy` CLI runs hooks**, not the IDE (community reports) | none | Stop hook can continue (unverified wording) | none |
| OpenCode | plugin in `~/.config/opencode/plugins` | plugin submits into the TUI (`/tui/append-prompt`, `/tui/submit-prompt`, `prompt_async` also exist on its server) | same | none |

Takeaways

- Only OpenCode takes a prompt into an idle chat through an API; Cursor works through the UI. Everywhere else the options are: queue it for the end of the running turn (hooks), or copy it and open the chat.
- Deep links are deliberately inert: they pre-fill, never send. A pre-filled new chat is possible for Claude (desktop and CLI) and Cursor but is a new session, not the current one.
- Not tested yet because the apps aren't installed: Gemini CLI, Antigravity, OpenCode.

Ideas for apps that can't take prompts

- Show repo state the agent can't: branch, dirty file count, ahead/behind, last Xcode build (already there), and Build / Commit as copy-and-open buttons.
- Per-agent options in Settings: hide the agent, force clipboard delivery, edit the button prompts.
