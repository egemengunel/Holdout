#!/bin/sh
# Registers holdout-hook.sh with coding agents so their sessions show on the Touch Bar.
#
#   Hooks/install.sh                  every agent found on this Mac
#   Hooks/install.sh codex gemini     just these (claude cursor codex gemini antigravity opencode)
#
# Safe to re-run: earlier Holdout entries are replaced, everything else is kept.

set -u
hooks_dir=$(cd "$(dirname "$0")" && pwd)
hook="$hooks_dir/holdout-hook.sh"
quoted="\"$hook\""
chmod +x "$hook"

has() { command -v "$1" >/dev/null 2>&1; }

# Rewrites a JSON config through a jq filter, keeping the original if anything fails.
update() {
  file=$1; shift
  mkdir -p "$(dirname "$file")" || return
  [ -s "$file" ] || echo '{}' > "$file"
  if /usr/bin/jq "$@" "$file" > "$file.holdout-tmp" 2>/dev/null; then
    mv -f "$file.holdout-tmp" "$file"
    echo "  updated $file"
  else
    rm -f "$file.holdout-tmp"
    echo "  could not parse $file; left it unchanged" >&2
  fi
}

# Claude Code, Codex and Gemini CLI share one shape: hooks.<Event>[].hooks[].command.
register() {
  file=$1 command=$2 timeout=$3 events=$4
  update "$file" --arg command "$command" --argjson timeout "$timeout" --argjson events "$events" '
    .hooks //= {}
    | reduce $events[] as $event (.;
        .hooks[$event] = ([.hooks[$event][]?
                            | .hooks |= map(select(.command | tostring | contains("holdout-hook.sh") | not))
                            | select(.hooks | length > 0)]
                          + [{hooks: [{type: "command", command: $command, timeout: $timeout}]}]))'
}

install_claude() {
  echo "Claude Code"
  register "$HOME/.claude/settings.json" "$quoted" 5 \
    '["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Notification","Stop","SessionEnd"]'
}

# Cursor also runs the hooks in ~/.claude/settings.json (Settings > Hooks > third-party
# hooks), so the native registration only needs the events Claude Code has no name for:
# the shell and MCP hooks that fire before an approval prompt. Without Claude Code it
# registers everything.
install_cursor() {
  echo "Cursor"
  events='["sessionStart","beforeSubmitPrompt","preToolUse","postToolUse","postToolUseFailure","stop","sessionEnd","beforeShellExecution","beforeMCPExecution"]'
  if [ -f "$HOME/.claude/settings.json" ] && grep -q holdout-hook.sh "$HOME/.claude/settings.json"; then
    events='["beforeShellExecution","beforeMCPExecution"]'
  fi
  update "$HOME/.cursor/hooks.json" --arg command "$quoted cursor" --argjson events "$events" '
    .version //= 1
    | .hooks //= {}
    | reduce $events[] as $event (.;
        .hooks[$event] = ([.hooks[$event][]? | select(.command | tostring | contains("holdout-hook.sh") | not)]
                          + [{command: $command, timeout: 5}]))'
}

install_codex() {
  echo "Codex"
  register "$HOME/.codex/hooks.json" "$quoted codex" 3 \
    '["SessionStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Stop","Interrupt","SessionEnd"]'
  echo "  run /hooks in Codex once to review and trust it"
}

install_gemini() {
  echo "Gemini CLI"
  register "$HOME/.gemini/settings.json" "$quoted gemini" 5000 \
    '["SessionStart","BeforeAgent","BeforeTool","AfterTool","Notification","AfterAgent","SessionEnd"]'
}

# Antigravity's payloads don't name their event, so each one passes it. No PreToolUse:
# its reply must be a permission decision, and Holdout never makes one.
install_antigravity() {
  echo "Antigravity"
  update "$HOME/.gemini/config/hooks.json" --arg command "$quoted antigravity" '
    def run($event): {type: "command", command: "\($command) \($event)", timeout: 5};
    .holdout = {
      PreInvocation: [run("PreInvocation")],
      PostToolUse: [{matcher: "*", hooks: [run("PostToolUse")]}],
      Stop: [run("Stop")]
    }'
}

install_opencode() {
  echo "OpenCode"
  plugin="$HOME/.config/opencode/plugins/holdout.js"
  mkdir -p "$(dirname "$plugin")"
  printf 'export * from "%s"\n' "$hooks_dir/opencode/holdout.js" > "$plugin"
  echo "  wrote $plugin"
}

if [ $# -eq 0 ]; then
  { [ -d "$HOME/.claude" ] || has claude; } && set -- "$@" claude
  [ -d "$HOME/.cursor" ] && set -- "$@" cursor
  { [ -d "$HOME/.codex" ] || has codex; } && set -- "$@" codex
  { [ -f "$HOME/.gemini/settings.json" ] || has gemini; } && set -- "$@" gemini
  { has agy || [ -d /Applications/Antigravity.app ] || ls -d "$HOME"/.gemini/antigravity* >/dev/null 2>&1; } && set -- "$@" antigravity
  { [ -d "$HOME/.config/opencode" ] || has opencode; } && set -- "$@" opencode
fi
[ $# -gt 0 ] || { echo "No supported agents found."; exit 0; }

for agent in "$@"; do
  case "$agent" in
    claude|cursor|codex|gemini|antigravity|opencode) "install_$agent" ;;
    *) echo "Unknown agent: $agent (claude cursor codex gemini antigravity opencode)" >&2 ;;
  esac
done
