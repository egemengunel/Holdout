# stage.py -- <out.blend>: black surface under the Mac, a pooled key light, black world.
import bpy, math, mathutils, sys
argv = sys.argv[sys.argv.index('--') + 1:]
s = bpy.context.scene
body = bpy.data.objects['Main Body']
zmin = min((body.matrix_world @ mathutils.Vector(c)).z for c in body.bound_box)
bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, zmin - 0.0002))
g = bpy.context.active_object; g.name = 'Surface'
m = bpy.data.materials.new('Surface'); m.use_nodes = True
p = m.node_tree.nodes['Principled BSDF']; p.inputs['Base Color'].default_value = (0.004, 0.004, 0.005, 1); p.inputs['Roughness'].default_value = 0.32; p.inputs['Specular IOR Level'].default_value = 0.35
g.data.materials.append(m)
bg = next(n for n in s.world.node_tree.nodes if n.type == 'BACKGROUND'); bg.inputs['Color'].default_value = (0, 0, 0, 1)
key = bpy.data.objects['Key']; key.location = (0.02, 0.03, 0.55); key.rotation_euler = (0, 0, 0)
key.data.size, key.data.size_y = 0.35, 0.25; key.data.spread = math.radians(35); key.data.energy = 6
rim = bpy.data.objects['Rim']; rim.data.energy = 0.8
print("SURFACE z", zmin)
bpy.ops.wm.save_as_mainfile(filepath=argv[0])
