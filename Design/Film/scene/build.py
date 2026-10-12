# build.py: turns the downloaded MacBook model into Nudge's Touch Bar shot.
# args after --: <clip.mp4> <out.blend>
import bpy, math, sys, mathutils
argv = sys.argv[sys.argv.index('--') + 1:]
clip, out = argv[0], argv[1]
s = bpy.context.scene

# Lid open, rotated about its hinge (its origin).
lid = bpy.data.objects['Bevels']
mw = lid.matrix_world.copy()
for c in list(lid.constraints): lid.constraints.remove(c)
lid.parent = None
lid.matrix_world = mw
lid.rotation_euler[0] = math.radians(-112)

# The Touch Bar plays the clip, lit from within.
bar = bpy.data.objects['Touch Bar Shot']
mat = bar.data.materials[0]
nt = mat.node_tree
tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
img = bpy.data.images.load(clip)
img.source = 'MOVIE'
tex.image = img
tex.image_user.frame_duration = img.frame_duration
tex.image_user.use_auto_refresh = True
tex.image_user.use_cyclic = True
tex.interpolation = 'Smart'
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
for l in list(bsdf.inputs['Base Color'].links): nt.links.remove(l)
bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
bsdf.inputs['Emission Strength'].default_value = 2.2
bsdf.inputs['Roughness'].default_value = 0.08
bsdf.inputs['Coat Weight'].default_value = 1.0
bsdf.inputs['Coat Roughness'].default_value = 0.05

# Dark studio: near-black world, one big soft key from above and behind, a faint rim.
w = s.world; wt = w.node_tree
for n in list(wt.nodes):
    if n.type != 'OUTPUT_WORLD': wt.nodes.remove(n)
bg = wt.nodes.new('ShaderNodeBackground'); bg.inputs['Color'].default_value = (0.012, 0.013, 0.016, 1); bg.inputs['Strength'].default_value = 1
wt.links.new(bg.outputs[0], next(n for n in wt.nodes if n.type == 'OUTPUT_WORLD').inputs['Surface'])
s.render.film_transparent = False

def area(name, loc, rot, size, energy, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA'); d.shape = 'RECTANGLE'; d.size, d.size_y = size; d.energy = energy; d.color = color
    o = bpy.data.objects.new(name, d); s.collection.objects.link(o); o.location = loc; o.rotation_euler = [math.radians(a) for a in rot]
    return o
area('Key', (0.05, -0.05, 0.45), (0, 0, 0), (0.6, 0.3), 9)
area('Rim', (0.0, 0.35, 0.12), (-70, 0, 0), (0.5, 0.05), 2.5, (0.8, 0.85, 1.0))

# Camera: above and in front, looking down at the bar's right end, shallow focus on Nudge's icon.
bb = [bar.matrix_world @ mathutils.Vector(c) for c in bar.bound_box]
xmin = min(v.x for v in bb); xmax = max(v.x for v in bb)
yc = sum(v.y for v in bb) / 8; zc = max(v.z for v in bb)
icon = mathutils.Vector((xmin + 0.74 * (xmax - xmin), yc, zc))
print("BAR", xmin, xmax, yc, zc, "ICON", tuple(icon))
cam = s.camera
cam.parent = None; cam.constraints.clear() if hasattr(cam.constraints, 'clear') else None
target = icon + mathutils.Vector((-0.02, -0.005, 0))
cam.location = target + mathutils.Vector((0.0, -0.16, 0.20))
direction = target - cam.location
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 85
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = (icon - cam.location).length
cam.data.dof.aperture_fstop = 2.0

s.render.resolution_x, s.render.resolution_y = 1920, 820
s.render.fps = 30
s.view_settings.view_transform = 'AgX'
s.view_settings.look = 'AgX - Punchy'
bpy.ops.wm.save_as_mainfile(filepath=out)
