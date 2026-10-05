#!/bin/sh
# Holdout's agent hook. Records each session's latest state as a small JSON file
# that Holdout.app watches. It never blocks: it always exits 0 and prints nothing,
# except `{}` for agents that require JSON on stdout, and a Touch Bar button's prompt
# (see below) when a turn ends.
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
reply=
case "$agent" in
  gemini|antigravity) reply='{}' ;;
esac
trap 'printf "%s" "$reply"' EXIT

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

# A Touch Bar button pressed while Codex, Gemini or Antigravity was working leaves its
# prompt in commands/<session>.json; it becomes the agent's next step when the turn ends.
command="$HOME/Library/Application Support/Holdout/commands/$id.json"
# Cursor runs this hook once per registration (here and in ~/.claude/settings.json) and
# merges the replies, so its command stays, stamped with the Stop's `loop_count`, for every
# copy of that Stop to answer alike; the follow-up turn's own Stop (the next count) deletes it.
# A stamp older than a minute is a prompt Cursor never ran.
if [ "$event" = Stop ] && [ -s "$command" ]; then
  loop=$(printf '%s' "$payload" | /usr/bin/jq -r '.loop_count // 0' 2>/dev/null)
  case "$loop" in ''|*[!0-9]*) loop=0 ;; esac
  prompt=$(/usr/bin/jq -r --argjson now "$now" --argjson loop "$loop" \
    'select($now - (.at // 0) < 1800 and (.sentLoop // $loop) == $loop and (.sentAt // $now) + 60 >= $now) | .prompt // empty' "$command" 2>/dev/null)
  if [ -n "$prompt" ]; then
    case "$agent" in
      codex) reply=$(/usr/bin/jq -cn --arg prompt "$prompt" '{decision: "block", reason: $prompt}') ;;
      gemini) reply=$(/usr/bin/jq -cn --arg prompt "$prompt" '{decision: "deny", reason: $prompt}') ;;
      antigravity) reply=$(/usr/bin/jq -cn --arg prompt "$prompt" '{decision: "continue", reason: $prompt}') ;;
      cursor)
        if printf '%s' "$payload" | /usr/bin/jq -e '.status == "completed"' >/dev/null 2>&1; then
          reply=$(/usr/bin/jq -cn --arg prompt "$prompt" '{followup_message: $prompt}')
          /usr/bin/jq -c --argjson loop "$loop" --argjson now "$now" '.sentLoop //= $loop | .sentAt //= $now' "$command" > "$command.$$" 2>/dev/null &&
            mv -f "$command.$$" "$command"
        fi
        ;;
    esac
    if [ -n "$reply" ] && [ "$reply" != '{}' ]; then
      [ "$agent" = cursor ] || rm -f "$command"
      event=UserPromptSubmit
    fi
  else
    # An answered Cursor command, once the Stop that sent it is over.
    /usr/bin/jq -e 'has("sentLoop")' "$command" >/dev/null 2>&1 && rm -f "$command"
  fi
fi

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
