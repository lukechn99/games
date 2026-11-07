"""Item box: a rounded glassy cube with a chunky question mark floating
inside, after the classic kart-racer item box (user's reference video).

    python3 racing/tools/blender/item_box.py [preview.png]
"""
import os
import sys
import math
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "item_box.glb")

c.reset()
# The shell: a cube with generously rounded edges and corners.
bpy.ops.mesh.primitive_cube_add(size=1.1)
shell = bpy.context.object
shell.name = "Shell"
c.bevel(shell, 0.2, 5)
c.smooth(shell)
c.apply_all(shell)
c.assign(shell, c.material("shell", (0.55, 0.95, 1.0), 0.05, alpha=0.45))

# The question mark: thick, bevelled, centred.
bpy.ops.object.text_add()
txt = bpy.context.object
txt.data.body = "?"
txt.data.extrude = 0.09
txt.data.bevel_depth = 0.035
txt.data.bevel_resolution = 3
txt.data.align_x = "CENTER"
txt.data.align_y = "CENTER"
txt.data.size = 0.85
bpy.ops.object.convert(target="MESH")
mark = bpy.context.object
mark.name = "Mark"
mark.rotation_euler = (math.radians(90), 0, 0)   # stand it up, facing -Y (front)
bpy.ops.object.transform_apply(rotation=True)
c.smooth(mark)
c.assign(mark, c.material("mark", (1.0, 1.0, 1.0), 0.3, emit=(1.0, 1.0, 1.0), emit_strength=0.6))

c.export(os.path.abspath(OUT), [shell, mark])
print("wrote", os.path.abspath(OUT))
if len(sys.argv) > 1:
    for o in (shell, mark):
        o.location.z += 0.9
    c.preview(sys.argv[1], target=(0, 0, 0.9), dist=3.2, elev=12, azim=25)
