import bpy, math, sys
argv = sys.argv[sys.argv.index('--') + 1:]
t = bpy.data.objects['BezelText']
# Lid-local units (the lid is scaled 0.2747). The display faces local -z; its black chin sits at
# z 0.0093 between the hinge (y 0) and the screen's bottom edge (y -0.0587).
t.location = (0, -0.030, 0.0091)
t.rotation_euler = (math.radians(180), 0, 0)
t.data.size = 0.019
bpy.ops.wm.save_as_mainfile(filepath=argv[0])
