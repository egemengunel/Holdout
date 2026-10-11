# demo.py <id> <agent> <event> [project] [tool] [detail] [notification]: writes a demo session the way nudge-hook.sh does
import json, os, sys, time
d = os.path.expanduser('~/Library/Application Support/Nudge/sessions')
a = sys.argv[1:] + [None] * 7
sid, agent, event, project, tool, detail, note = a[:7]
if event == 'remove':
    for f in os.listdir(d):
        if f.startswith('nudge-demo-'): os.remove(os.path.join(d, f))
    sys.exit()
now = time.time()
body = dict(session='nudge-demo-' + sid, agent=agent, event=event, cwd='/Users/demo/Developer/' + (project or 'Weather'),
            tool=tool, detail=detail, notification=note, app=None, edited=[], updatedAt=now, turnStartedAt=now - 40)
tmp = os.path.join(d, '.tmp-demo')
json.dump(body, open(tmp, 'w')); os.rename(tmp, os.path.join(d, body['session'] + '.json'))
