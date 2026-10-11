# film.py -- <shot> <percent> <outdir>: renders one shot of the Nudge film with EEVEE.
# Each shot plays one real Touch Bar recording on the model and moves the camera from A to B.
import bpy, math, mathutils, sys, os
argv = sys.argv[sys.argv.index('--') + 1:]
name, pct, outdir = argv[0], int(argv[1]), argv[2]
CLIPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'clips') + '/'
BX0, BX1, BY, BZ = -0.1105, 0.1155, 0.0859, 0.0107
def bar(u, dy=0.0): return (BX0 + u * (BX1 - BX0), BY + dy, BZ)
ICON = 0.74
# shot: clip, seconds, camera A and B as (look-at, offset from it, lens, f-stop, focus point)
SHOTS = {
    # Establishing: high overhead on the deck, pushing in while the hand pulses amber.
    'open': ('1-typing-needs-you.mp4', 5.4,
             ((0.0, 0.05, 0.0), (0, -0.05, 0.52), 40, 8.0, bar(ICON)),
             ((0.02, 0.07, 0.0), (0, -0.04, 0.34), 46, 5.6, bar(ICON))),
    # Tracking left to right along the bar, over the scrubber, arriving on the working count.
    'track': ('3-video-agents-working.mp4', 6.0,
              (bar(0.12, 0.002), (0, -0.028, 0.15), 55, 2.4, bar(0.12)),
              (bar(0.78, 0.002), (0, -0.028, 0.15), 55, 2.4, bar(0.78))),
    # Close on the icon, slow push, as the build lands green.
    'build': ('2-finder-build-succeeded.mp4', 5.5,
              (bar(0.80, -0.01), (0, -0.045, 0.21), 60, 2.8, bar(ICON)),
              (bar(0.76, -0.006), (0, -0.032, 0.15), 60, 2.8, bar(ICON))),
    # Tracking right to left from Touch ID, crossing the icon as the session finishes.
    'finish': ('4-safari-session-finished.mp4', 5.5,
               (bar(1.08, 0.0), (0, -0.03, 0.16), 55, 2.4, bar(1.08)),
               (bar(0.40, 0.0), (0, -0.03, 0.16), 55, 2.4, bar(0.40))),
    # Low and long: focus pulls from the number row up to the icon as the build fails.
    'fail': ('5-xcode-build-failed.mp4', 5.5,
             (bar(0.70, -0.004), (0.01, -0.11, 0.13), 85, 2.0, (bar(0.70)[0], 0.062, 0.006)),
             (bar(0.74, 0.0), (0.0, -0.10, 0.13), 85, 2.0, bar(ICON))),
    # Pull back to the whole deck, everything quiet again.
    'close': ('6-finder-idle.mp4', 5.0,
              ((0.04, 0.075, 0.0), (0, -0.035, 0.30), 46, 5.6, bar(ICON)),
              ((0.0, 0.05, 0.0), (0, -0.05, 0.54), 40, 8.0, bar(ICON))),
}
clip, seconds, A, B = SHOTS[name]
s = bpy.context.scene
s.render.fps = 30
frames = int(round(seconds * 30))
s.frame_start, s.frame_end = 1, frames
tex = next(n for n in bpy.data.objects['Touch Bar Shot'].data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE')
img = bpy.data.images.load(CLIPS + clip); img.source = 'MOVIE'; tex.image = img
iu = tex.image_user; iu.frame_duration = img.frame_duration; iu.frame_start = 1; iu.frame_offset = 0; iu.use_auto_refresh = True; iu.use_cyclic = True
cam = s.camera
def ease(t): return t * t * (3 - 2 * t)
def lerp(a, b, t): return mathutils.Vector(a).lerp(mathutils.Vector(b), t)
def place(scene, *_):
    t = ease((scene.frame_current - 1) / max(frames - 1, 1))
    look = lerp(A[0], B[0], t); off = lerp(A[1], B[1], t)
    cam.location = look + off
    d = look - cam.location
    # Pitch toward the look-at point, and yaw for any sideways offset, with no roll.
    cam.rotation_euler = (math.atan2(math.hypot(d.x, d.y), -d.z), 0, math.atan2(-d.x, d.y) if (abs(d.x) > 1e-6) else 0)
    cam.data.lens = A[2] + (B[2] - A[2]) * t
    cam.data.dof.use_dof = True
    cam.data.dof.aperture_fstop = A[3] + (B[3] - A[3]) * t
    cam.data.dof.focus_distance = (lerp(A[4], B[4], t) - cam.location).length
place(s)
bpy.app.handlers.frame_change_pre.append(place)
s.render.engine = 'BLENDER_EEVEE'; s.eevee.taa_render_samples = 48
s.render.resolution_percentage = pct
s.render.image_settings.file_format = 'PNG'
s.render.filepath = os.path.join(outdir, name + '_')
if len(argv) > 3:  # a single test frame
    s.frame_set(int(argv[3])); s.render.filepath = os.path.join(outdir, f'{name}-{argv[3]}.png'); bpy.ops.render.render(write_still=True)
else:
    bpy.ops.render.render(animation=True)
