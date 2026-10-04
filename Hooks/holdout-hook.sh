#!/bin/sh
# Holdout's Claude Code hook. Records each session's latest state as a small
# JSON file that Holdout.app watches. It prints nothing and always exits 0,
# so it can never block or change what a Claude Code session does.

dir="$HOME/Library/Application Support/Holdout/sessions"
mkdir -p "$dir" || exit 0

payload=$(cat)
id=$(printf '%s' "$payload" | /usr/bin/jq -r '.session_id // empty' 2>/dev/null)
[ -n "$id" ] || exit 0
file="$dir/$id.json"

event=$(printf '%s' "$payload" | /usr/bin/jq -r '.hook_event_name // empty' 2>/dev/null)
if [ "$event" = "SessionEnd" ]; then
  rm -f "$file"
  exit 0
fi

now=$(date +%s)
previous=$(/usr/bin/jq -c . "$file" 2>/dev/null) || previous='{}'
[ -n "$previous" ] || previous='{}'

# __CFBundleIdentifier is the app hosting the session (Claude, Terminal, Ghostty…),
# so Holdout can bring the right window forward.
printf '%s' "$payload" | /usr/bin/jq -c \
  --arg app "${__CFBundleIdentifier:-}" --argjson now "$now" --argjson previous "$previous" '{
    session: .session_id,
    event: .hook_event_name,
    cwd: (.cwd // $previous.cwd),
    tool: .tool_name,
    detail: ((.tool_input.file_path // .tool_input.command // .tool_input.pattern // .tool_input.url // .message)
             | if . == null then null else tostring | .[0:120] end),
    notification: .notification_type,
    app: (if $app == "" then $previous.app else $app end),
    updatedAt: $now,
    turnStartedAt: (if .hook_event_name == "UserPromptSubmit" then $now else ($previous.turnStartedAt // $now) end)
  }' > "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"

exit 0
