import bpy, math, mathutils, sys
argv = sys.argv[sys.argv.index('--') + 1:]
lid = bpy.data.objects['Bevels']; me = lid.data
screen_idx = [i for i, m in enumerate(me.materials) if m and m.name == 'Material.002']
sv = [me.vertices[v].co for p in me.polygons if p.material_index in screen_idx for v in p.vertices]
zmin = min(v.co.z for v in me.vertices)
screen_ymax = max(v.y for v in sv); screen_z = min(v.z for v in sv)
print("SCREEN local y max", screen_ymax, "screen z", screen_z, "lid zmin", zmin)
# The chin runs from the hinge (local y ~ 0) to the screen's bottom edge.
old = bpy.data.objects['Macbook Pro']; old.hide_render = True
font = bpy.data.fonts.load(argv[1])
cu = bpy.data.curves.new('BezelText', 'FONT'); cu.body = 'MacBook Pro'; cu.font = font; cu.align_x = 'CENTER'; cu.align_y = 'CENTER'
cu.size = 0.0042
t = bpy.data.objects.new('BezelText', cu); bpy.context.scene.collection.objects.link(t)
t.parent = lid
t.location = (0, screen_ymax / 2, zmin - 0.00005)
t.rotation_euler = (math.radians(180), 0, 0)
mat = bpy.data.materials.new('BezelText'); mat.use_nodes = True
p = mat.node_tree.nodes['Principled BSDF']; p.inputs['Base Color'].default_value = (0.42, 0.42, 0.44, 1); p.inputs['Metallic'].default_value = 0.6; p.inputs['Roughness'].default_value = 0.35
cu.materials.append(mat)
bpy.context.view_layer.update()
print("TEXT dims", tuple(t.dimensions))
bpy.ops.wm.save_as_mainfile(filepath=argv[0])
