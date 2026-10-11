import bpy, math, sys
argv = sys.argv[sys.argv.index('--') + 1:]
key = bpy.data.objects['Key']; key.location = (0.0, 0.40, 0.42); key.rotation_euler = (math.radians(-42), 0, 0)
key.data.size, key.data.size_y = 0.45, 0.25; key.data.spread = math.radians(50); key.data.energy = 5
fill = bpy.data.objects.get('Fill')
if not fill:
    d = bpy.data.lights.new('Fill', 'AREA'); fill = bpy.data.objects.new('Fill', d); bpy.context.scene.collection.objects.link(fill)
fill.location = (-0.35, -0.1, 0.25); fill.rotation_euler = (0, math.radians(-55), 0); fill.data.size = 0.3; fill.data.energy = 0.6; fill.data.color = (0.75, 0.82, 1.0)
bar = bpy.data.objects['Touch Bar Shot']; b = next(n for n in bar.data.materials[0].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
b.inputs['Coat Weight'].default_value = 0.25; b.inputs['Specular IOR Level'].default_value = 0.2
bpy.ops.wm.save_as_mainfile(filepath=argv[0])
