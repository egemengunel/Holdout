#!/bin/zsh
# record-strip.sh [Nudge.app]: records the scenes that need Nudge's strip open or a state that
# can't happen on demand, into recordings/. Takes about two minutes. The Touch Bar switches off
# when the Mac is idle and only a real touch wakes it, so keep touching the trackpad meanwhile.
#
# It quits your running Nudge, launches the given build (default: Xcode's Debug build) with
# `-NudgeDemoControl YES` and a demo project's buttons passed as a launch argument (your saved
# settings aren't touched), sets your real sessions aside so only demo ones show, and puts
# everything back when it finishes or is interrupted.
F=${0:A:h}; cd $F
APP=${1:-$(ls -d ~/Library/Developer/Xcode/DerivedData/Nudge-*/Build/Products/Debug/Nudge.app | head -1)}
DEMO=$APP/Contents/MacOS/Nudge
SESS=~/Library/Application\ Support/Nudge/sessions; ASIDE=$(mktemp -d)
[[ -x nudge-demo ]] || swiftc -O nudge-demo.swift -o nudge-demo
[[ -x wake ]] || swiftc -O wake.swift -o wake
USER_APP=$(ps -axo command | grep -m1 "Nudge.app/Contents/MacOS/Nudge" | grep -v grep | sed 's|/Contents/MacOS/Nudge.*||')

cleanup() {
  [[ -n $DEMOPID ]] && kill $DEMOPID 2>/dev/null
  python3 demo.py x x remove; python3 feed.py remove
  mv $ASIDE/*.json "$SESS"/ 2>/dev/null; rmdir $ASIDE
  [[ -n $USER_APP ]] && open -a "$USER_APP"
}
trap cleanup EXIT INT TERM HUP

[[ -n $USER_APP ]] && { pkill -f "$USER_APP/Contents/MacOS/Nudge"; sleep 1; }
mv "$SESS"/*.json $ASIDE/ 2>/dev/null
actions=$(python3 -c '
import json, uuid
p = [("Test","checkmark.diamond"),("Explain","text.magnifyingglass"),("Tidy","wand.and.stars"),("Continue","forward"),("Push","arrow.up.circle")]
print("<" + json.dumps([{"id": str(uuid.uuid4()).upper(), "title": t, "symbol": s, "prompt": t} for t, s in p], separators=(",", ":")).encode().hex() + ">")')
"$DEMO" -NudgeDemoControl YES -didOnboard YES -project.customActions "$actions" >/dev/null 2>&1 &
DEMOPID=$!; sleep 4
d() { ./nudge-demo "$@"; }
R=./record.sh

echo "Agents arriving"
osascript -e 'tell application "TextEdit" to make new document' -e 'tell application "TextEdit" to set text of document 1 to "Hey, the new build looks great. I think we should "' -e 'tell application "TextEdit" to activate'; sleep 2
d open; sleep 1; d tab 0; sleep 2
( sleep 1.2; python3 demo.py w claude PreToolUse Weather Edit "WeatherView.swift"; python3 feed.py w Weather main 2
  sleep 1.6; python3 demo.py c cursor PreToolUse Atlas Edit "Checkout.tsx"
  sleep 1.6; python3 demo.py x codex PermissionRequest Notes Bash "xcodebuild test"
  sleep 1.6; python3 demo.py o opencode PreToolUse Ledger Bash "cargo test"
  sleep 2.2; python3 demo.py w claude Stop Weather ) &
helper=$!; $R agents-arrive 12; wait $helper

echo "Project tab"
python3 demo.py w claude PreToolUse Weather Edit "WeatherView.swift"
d tab 2; sleep 3; d scroll start; sleep 1.5; screencapture -b -x recordings/project-start.png
d scroll end; sleep 1.5; screencapture -b -x recordings/project-end.png

echo "Memory alert and CPU heads-up"
python3 demo.py x x remove; python3 feed.py remove; d close; sleep 2
osascript -e 'tell application "TextEdit" to activate'; sleep 2
( sleep 1.5; d pulse alert ) & helper=$!; $R textedit-alert 8; wait $helper; d pulse off
osascript -e 'tell application "Finder" to make new Finder window to (path to documents folder)' -e 'tell application "Finder" to activate'; sleep 3
( sleep 1.5; d pulse cpu ) & helper=$!; $R finder-cpu 8; wait $helper; d pulse off
osascript -e 'tell application "TextEdit" to close (every document whose path is missing value) saving no' >/dev/null 2>&1
osascript -e 'tell application "Finder" to close Finder window "Documents"' >/dev/null 2>&1
echo "Done: recordings/"
