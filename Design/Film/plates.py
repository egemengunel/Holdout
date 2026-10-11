# plates.py -- <outdir> [percent]: renders each framing with the Touch Bar switched off, and
# writes where the bar's screen lands in each image (its four corners, in pixels), so the app
# can draw live content onto it in perspective.
import bpy, json, math, mathutils, os, sys
from bpy_extras.object_utils import world_to_camera_view
argv = sys.argv[sys.argv.index('--') + 1:]
outdir = argv[0]; pct = int(argv[1]) if len(argv) > 1 else 100
only = argv[2].split(',') if len(argv) > 2 else None
s = bpy.context.scene; cam = s.camera
BAR = (0.0025, 0.0859, 0.0107)
FRAMINGS = {
    # The whole bar from above, with the bezel and the number row.
    'Bar':   ((0.0025, 0.083, 0.0), (0, -0.03, 0.36), 50, 8.0),
    # The bar's right end: the Control Strip, Touch ID and the delete key.
    'Right': ((0.05, 0.085, 0.0), (0, -0.03, 0.25), 55, 6.0),
    # The strip's content (sessions, the project, its buttons), closer: the bar's left two thirds.
    'Strip': ((-0.029, 0.083, 0.0), (0, -0.025, 0.235), 50, 8.0),
    # The whole deck from high above.
    'Wide':  ((0.0, 0.05, 0.0), (0, -0.045, 0.44), 46, 8.0),
}
bar = bpy.data.objects['Touch Bar Shot']
b = next(n for n in bar.data.materials[0].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
b.inputs['Emission Strength'].default_value = 0.0
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'; prefs.get_devices()
for d in prefs.devices: d.use = True
s.render.engine = 'CYCLES'; s.cycles.device = 'GPU'; s.cycles.samples = 128; s.cycles.use_denoising = True
s.render.resolution_percentage = pct
quads = {}
for name, (look, off, lens, fstop) in FRAMINGS.items():
    if only and name not in only: continue
    look = mathutils.Vector(look)
    cam.location = look + mathutils.Vector(off)
    d = look - cam.location
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, 0)
    cam.data.lens = lens
    cam.data.dof.use_dof = True; cam.data.dof.aperture_fstop = fstop
    cam.data.dof.focus_distance = (mathutils.Vector(BAR) - cam.location).length
    bpy.context.view_layer.update()
    w = s.render.resolution_x * pct / 100; h = s.render.resolution_y * pct / 100
    # The bar's screen is the plane's face; its UVs run left to right, bottom to top.
    me = bar.data
    uv = me.uv_layers.active.data
    corners = {}
    for poly in me.polygons:
        for li in poly.loop_indices:
            u, v = uv[li].uv
            key = ('l' if u < 0.5 else 'r') + ('b' if v < 0.5 else 't')
            p = world_to_camera_view(s, cam, bar.matrix_world @ me.vertices[me.loops[li].vertex_index].co)
            corners[key] = (round(p.x * w, 2), round((1 - p.y) * h, 2))
    quads[name] = {'size': [w, h], 'topLeft': corners['lt'], 'topRight': corners['rt'], 'bottomRight': corners['rb'], 'bottomLeft': corners['lb']}
    s.render.filepath = os.path.join(outdir, f'Plate{name}.png')
    bpy.ops.render.render(write_still=True)
path = os.path.join(outdir, 'plates.json')
quads = {**(json.load(open(path)) if os.path.exists(path) else {}), **quads}
json.dump(quads, open(path, 'w'), indent=1)
print('QUADS', json.dumps(quads))
