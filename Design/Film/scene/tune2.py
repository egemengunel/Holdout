import bpy, math, mathutils, sys
argv = sys.argv[sys.argv.index('--') + 1:]
s = bpy.context.scene
bar = bpy.data.objects['Touch Bar Shot']
bb = [bar.matrix_world @ mathutils.Vector(c) for c in bar.bound_box]
xmin = min(v.x for v in bb); xmax = max(v.x for v in bb); yc = sum(v.y for v in bb)/8; zc = max(v.z for v in bb)
icon = mathutils.Vector((xmin + 0.74*(xmax-xmin), yc, zc))
cam = s.camera
target = icon + mathutils.Vector((0.03, -0.01, 0))
cam.location = target + mathutils.Vector((0.0, -0.12, 0.26))
d = target - cam.location
pitch = math.atan2(math.hypot(d.y, 0), -d.z)  # tilt away from straight down
cam.rotation_euler = (pitch, 0, 0)
cam.data.dof.focus_distance = (icon - cam.location).length
b = next(n for n in bar.data.materials[0].node_tree.nodes if n.type == 'BSDF_PRINCIPLED'); b.inputs['Emission Strength'].default_value = 4.5
# The display: our own dark gradient, dimmed, instead of the model author's screenshot.
m = bpy.data.materials['Material.002']; nt = m.node_tree
tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE'); tex.image = bpy.data.images.load(argv[1])
p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
for l in list(p.inputs['Base Color'].links): nt.links.remove(l)
p.inputs['Base Color'].default_value = (0, 0, 0, 1)
nt.links.new(tex.outputs['Color'], p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value = 1.2
p.inputs['Roughness'].default_value = 0.05
bpy.ops.wm.save_as_mainfile(filepath=argv[0])
