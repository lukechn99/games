"""Item box: a squishy pink jelly cube with soft, rounded edges and a fat
yellow question mark inside, edged in orange (after the user's reference
frames). Parts: Shell, Mark (yellow face), MarkEdge (orange rim).

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
# The shell: soft and pillowy. A cube rounded off, then puffed out a touch
# so the faces bulge like jelly.
bpy.ops.mesh.primitive_cube_add(size=1.0)
shell = bpy.context.object
shell.name = "Shell"
c.bevel(shell, 0.24, 4)
c.subsurf(shell, 2)
cast = shell.modifiers.new("puff", "CAST")
cast.factor = 0.12
c.smooth(shell)
c.apply_all(shell)
c.assign(shell, c.material("shell", (1.0, 0.3, 0.74), 0.1, alpha=0.38, transmission=0.1))


def question(name, extrude, offset, color, emit):
    bpy.ops.object.text_add()
    t = bpy.context.object
    t.data.body = "?"
    t.data.extrude = extrude
    t.data.offset = offset          # grows the outline: the orange rim
    t.data.bevel_depth = 0.02
    t.data.bevel_resolution = 2
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.size = 0.92
    t.data.shear = 0.12             # a little lean, more lively
    bpy.ops.object.convert(target="MESH")
    m = bpy.context.object
    m.name = name
    m.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    c.smooth(m)
    c.assign(m, c.material(name, color, 0.35, emit=emit, emit_strength=0.6))
    return m


mark = question("Mark", 0.08, 0.028, (1.0, 0.86, 0.2), (1.0, 0.86, 0.2))
edge = question("MarkEdge", 0.06, 0.07, (1.0, 0.5, 0.1), (1.0, 0.5, 0.1))
mark.location.y -= 0.025   # the yellow face sits just in front of the rim

c.export(os.path.abspath(OUT), [shell, mark, edge], max_tris=2500)
print("wrote", os.path.abspath(OUT))
if len(sys.argv) > 1:
    for o in (shell, mark, edge):
        o.location.z += 0.9
        o.rotation_euler.z += math.radians(-12)
    c.sheet(sys.argv[1], [(10, 0), (25, 40)], target=(0, 0, 0.9), dist=3.0)
