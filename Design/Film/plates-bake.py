# plates-bake.py <rendered dir> <out dir>: crops each plate around the bar, bakes its edges into
# black (bake.sh) and writes Plates.json with the bar's corners in the cropped image.
import json, os, subprocess, sys
src, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
quads = json.load(open(os.path.join(src, 'plates.json')))
# name: (crop top, crop height) in the 1920 × 820 render; Wide keeps the whole frame.
CROPS = {'Bar': (100, 560), 'Strip': (100, 600), 'Right': (83, 600), 'Wide': (0, 820)}
result = {}
for name, (top, height) in CROPS.items():
    q = quads[name]; w = q['size'][0]
    raw = os.path.join(out, f'raw-{name}.png')
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', os.path.join(src, f'Plate{name}.png'), '-vf', f'crop={int(w)}:{height}:0:{top}', raw], check=True)
    subprocess.run([os.path.join(here, 'bake.sh'), raw, os.path.join(out, f'Plate{name}.jpg'), '0.16', '0.25', '0.3', 'still'], check=True)
    os.remove(raw)
    shift = lambda p: [p[0], round(p[1] - top, 2)]
    result[name] = {'size': [w, height], **{k: shift(q[k]) for k in ('topLeft', 'topRight', 'bottomRight', 'bottomLeft')}}
json.dump(result, open(os.path.join(out, 'Plates.json'), 'w'), indent=1)
