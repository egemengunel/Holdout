# quiet.py: shows every real session as idle until its next hook event, so a recording starts on
# the plain hand. (The session running the recording is "working" for as long as it runs.)
import json, os, glob
for p in glob.glob(os.path.expanduser('~/Library/Application Support/Nudge/sessions/*.json')):
    if os.path.basename(p).startswith('nudge-demo-'): continue
    b = json.load(open(p)); b['event'] = 'SessionStart'
    json.dump(b, open(p + '.tmp', 'w')); os.rename(p + '.tmp', p)
