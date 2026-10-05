#!/bin/sh
# Holdout's agent hook. Records each session's latest state as a small JSON file
# that Holdout.app watches. It never blocks or changes what an agent does: it always
# exits 0 and prints nothing, except `{}` for agents that require JSON on stdout.
#
# Usage: holdout-hook.sh [agent] [event]
#   agent: claude (default), cursor, codex, gemini, antigravity, opencode
#   event: for agents whose payload doesn't name its event (Antigravity)
#
# Every agent's events are translated to Claude Code's names (SessionStart,
# UserPromptSubmit, PreToolUse, PostToolUse, Notification, PermissionRequest, Stop,
# SessionEnd, plus Interrupt), which is what the app reads.

agent=${1:-}
event_arg=${2:-}
case "$agent" in
  gemini|antigravity) trap 'printf "{}"' EXIT ;;
esac

dir="$HOME/Library/Application Support/Holdout/sessions"
mkdir -p "$dir" || exit 0

payload=$(cat)
id=$(printf '%s' "$payload" | /usr/bin/jq -r '.session_id // .conversation_id // .conversationId // empty' 2>/dev/null)
[ -n "$id" ] || exit 0
case "$id" in */*) exit 0 ;; esac
file="$dir/$id.json"

# Cursor's subagents report under their own id; the parent's Task tool already shows them.
if printf '%s' "$payload" | /usr/bin/jq -e '(.parent_tool_call_id // "") != ""' >/dev/null 2>&1; then
  exit 0
fi

# Cursor runs the hooks in ~/.claude/settings.json too, sending its own event names.
if [ -z "$agent" ]; then
  if printf '%s' "$payload" | /usr/bin/jq -e 'has("cursor_version")' >/dev/null 2>&1; then
    agent=cursor
  else
    agent=claude
  fi
fi

event=${event_arg:-$(printf '%s' "$payload" | /usr/bin/jq -r '.hook_event_name // empty' 2>/dev/null)}
case "$event" in
  sessionStart) event=SessionStart ;;
  beforeSubmitPrompt|BeforeAgent) event=UserPromptSubmit ;;
  preToolUse|BeforeTool) event=PreToolUse ;;
  postToolUse|postToolUseFailure|AfterTool) event=PostToolUse ;;
  stop|AfterAgent) event=Stop ;;
  sessionEnd) event=SessionEnd ;;
esac

# A turn you cancel in Cursor ends quietly rather than flashing done.
if [ "$agent" = cursor ] && [ "$event" = Stop ] &&
  printf '%s' "$payload" | /usr/bin/jq -e '.status == "aborted"' >/dev/null 2>&1; then
  event=Interrupt
fi

# Antigravity stops with background commands still running; it's still working then.
if [ "$agent" = antigravity ] && [ "$event" = Stop ] &&
  printf '%s' "$payload" | /usr/bin/jq -e '.fullyIdle == false' >/dev/null 2>&1; then
  event=PostToolUse
fi

if [ "$event" = "SessionEnd" ]; then
  rm -f "$file"
  exit 0
fi

now=$(date +%s)
previous=$(/usr/bin/jq -c . "$file" 2>/dev/null) || previous='{}'
[ -n "$previous" ] || previous='{}'

# Cursor's hooks that fire before a shell or MCP approval prompt. They only add whether
# the command runs sandboxed, which never asks; the Pre/PostToolUse pair does the rest.
case "$event" in
  beforeShellExecution|beforeMCPExecution)
    [ -s "$file" ] || exit 0
    printf '%s' "$payload" | /usr/bin/jq -c --argjson previous "$previous" \
      '$previous + {sandboxed: (.sandbox // false)}' > "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"
    exit 0
    ;;
esac

# Cursor's hooks that fire before a shell or MCP approval prompt. They only add whether
# the command runs sandboxed, which never asks; the Pre/PostToolUse pair does the rest.
case "$event" in
  beforeShellExecution|beforeMCPExecution)
    [ -s "$file" ] || exit 0
    printf '%s' "$payload" | /usr/bin/jq -c --argjson previous "$previous" \
      '$previous + {sandboxed: (.sandbox // false)}' > "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"
    exit 0
    ;;
esac

# __CFBundleIdentifier is the app hosting the session (Claude, Cursor, Terminal, Ghostty…),
# so Holdout can bring the right window forward.
printf '%s' "$payload" | /usr/bin/jq -c \
  --arg id "$id" --arg agent "$agent" --arg event "$event" \
  --arg app "${__CFBundleIdentifier:-}" --argjson now "$now" --argjson previous "$previous" '
  (.tool_input // .toolCall.args // {}) as $input
  | (.tool_name // .toolCall.name) as $tool
  | (if $event == "PostToolUse" and ($tool // "" | test("^(write|edit|multiedit|strreplace|apply_patch|write_file|replace|patch|write_to_file|replace_file_content|multi_replace_file_content)$"; "i"))
     then if ($input | type) != "object" then []
          elif $tool == "apply_patch" then
            [$input.command // "" | tostring | scan("\\*\\*\\* (?:Update|Add) File: ([^\\n]+)") | .[0]]
          else [$input.file_path // $input.filePath // $input.TargetFile | select(type == "string")]
          end
     else [] end) as $edits
  | {
    session: $id,
    agent: $agent,
    event: $event,
    cwd: ([.cwd, .workspace_roots[0]?, .workspacePaths[0]?, $previous.cwd]
          | map(select(type == "string" and . != "")) | first),
    tool: $tool,
    detail: ((if $tool == "apply_patch" then
                ($input.command // "" | tostring | capture("\\*\\*\\* (Update|Add|Delete) File: (?<file>[^\\n]+)").file?)
              else null end)
             // (if ($input | type) == "object" then
                   $input.file_path // $input.filePath // $input.command // $input.CommandLine
                   // $input.TargetFile // $input.AbsolutePath // $input.pattern // $input.Query
                   // $input.url // $input.Url // $input.query
                 else null end)
             // .message
             | if . == null then null else tostring | .[0:120] end),
    notification: (.notification_type | if . == "ToolPermission" then "permission_prompt" else . end),
    app: (if $app == "" then $previous.app else $app end),
    edited: (($previous.edited // []) - $edits + $edits | .[-50:]),
    updatedAt: $now,
    turnStartedAt: (if $event == "UserPromptSubmit"
                       or (($previous.event // "SessionStart") | IN("SessionStart", "Stop", "Interrupt"))
                    then $now else ($previous.turnStartedAt // $now) end)
  }' > "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"

exit 0
