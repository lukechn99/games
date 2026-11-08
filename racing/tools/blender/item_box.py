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


def question_outline():
    """The "?" drawn as one thick stroke and a dot, so the hook can curl
    well round and down on the left, as in Mario Kart (the font's hook
    stopped short). Returns outline polygons in the XY plane, ~0.68 tall."""
    from shapely.geometry import LineString, Point
    pts = []
    cx, cy, r = 0.0, 0.17, 0.25
    # Over the top, clockwise: from down on the left (215 deg) round to
    # the lower right, ...
    for k in range(41):
        a = math.radians(215 - k * (255 / 40))
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    # ... then curving back in to a short upright stem.
    p0 = pts[-1]
    tan = (math.sin(math.radians(-40)), -math.cos(math.radians(-40)))
    ctrl = (p0[0] + tan[0] * 0.13, p0[1] + tan[1] * 0.13)
    end = (0.0, -0.13)
    for k in range(1, 13):
        u = k / 12
        pts.append(((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * ctrl[0] + u * u * end[0],
                    (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * ctrl[1] + u * u * end[1]))
    pts.append((0.0, -0.165))
    stroke = LineString(pts).buffer(0.072, quad_segs=10)
    dot = Point(0.0, -0.37).buffer(0.08, quad_segs=10)
    s = 0.75
    out = []
    for poly in (stroke, dot):
        # A little lean, more lively.
        out.append([((x + 0.12 * y) * s, y * s) for x, y in list(poly.exterior.coords)[:-1]])
    return out


def question(name, extrude, offset, color, emit):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = extrude
    cu.offset = offset          # grows the outline: the orange rim
    cu.bevel_depth = 0.012
    cu.bevel_resolution = 2
    for ring in question_outline():
        sp = cu.splines.new("POLY")
        sp.points.add(len(ring) - 1)
        for i, (x, y) in enumerate(ring):
            sp.points[i].co = (x, y, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    m = bpy.context.object
    m.name = name
    m.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    c.smooth(m)
    c.assign(m, c.material(name, color, 0.35, emit=emit, emit_strength=0.6))
    return m


mark = question("Mark", 0.08, 0.0, (1.0, 0.86, 0.2), (1.0, 0.86, 0.2))
edge = question("MarkEdge", 0.06, 0.038, (1.0, 0.5, 0.1), (1.0, 0.5, 0.1))
mark.location.y -= 0.025   # the yellow face sits just in front of the rim

c.export(os.path.abspath(OUT), [shell, mark, edge], max_tris=2500)
print("wrote", os.path.abspath(OUT))
if len(sys.argv) > 1:
    for o in (shell, mark, edge):
        o.location.z += 0.9
        o.rotation_euler.z += math.radians(-12)
    c.sheet(sys.argv[1], [(10, 0), (25, 40)], target=(0, 0, 0.9), dist=3.0)
