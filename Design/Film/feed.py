# feed.py <session> <project> <branch> <hours since build> | remove: a demo project feed, as the nudge-bridge mod writes.
import json, os, sys, time
d = os.path.expanduser('~/Library/Application Support/Nudge/feeds'); os.makedirs(d, exist_ok=True)
if sys.argv[1] == 'remove':
    for f in os.listdir(d):
        if f.startswith('nudge-demo-'): os.remove(os.path.join(d, f))
    sys.exit()
sid, name, branch, hours = 'nudge-demo-' + sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
now = time.time(); root = '/Users/demo/Developer/' + name
body = dict(session=sid, cwd=root, updatedAt=now, buildAt=now - hours * 3600,
            repo=dict(name=name, root=root, branch=branch), project=dict(name=name, root=root, branch=branch),
            build=dict(project=name, isOk=True, seconds=14.2, errorCount=0, firstError=None, warningCount=0))
json.dump(body, open(os.path.join(d, sid + '.json'), 'w'))
