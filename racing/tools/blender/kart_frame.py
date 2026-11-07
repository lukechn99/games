"""The go-kart body ("frame" chassis): smooth, rounded bodywork in place of
the boxes and tubes the game used to build in code. Wheels, exhausts, the
steering wheel and the driver are still added by kart_visual.gd.

Objects are named by what colour the game paints them:
  Paint*   the chassis colour      Trim*  dark grey
  Chrome*  polished metal          Plate* the white number plate

Godot axes: x right, y up, z back. Blender is (x, -z, y), so the nose
points to +Y here. Sizes fit Parts.CHASSIS["frame"] (wheelbase 1.45,
track 1.2).

    python3 racing/tools/blender/kart_frame.py [preview.png]
"""
import os
import sys
import math
import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as c

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "kart_frame.glb")


def g(x, y, z):
    """Godot (x, y, z) to Blender."""
    return Vector((x, -z, y))


def rounded(name, center, size, bevel=0.08, seg=4, taper_front=1.0, taper_top=1.0, lift_front=0.0, sub=1, drop_front=0.0, taper_back=1.0):
    """A box in Godot sizes (x, y, z), rounded off. taper_front narrows the
    front end (-z) in x; taper_top narrows the top in x; lift_front raises
    the front bottom edge (a nose that rakes up)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g(*center))
    o = bpy.context.object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        front = v.co.y > 0          # +Y is the nose
        top = v.co.z > 0
        if front:
            v.co.x *= taper_front
            if not top:
                v.co.z += lift_front
            else:
                v.co.z -= drop_front
        else:
            v.co.x *= taper_back
        if top:
            v.co.x *= taper_top
    bm.to_mesh(o.data)
    bm.free()
    c.bevel(o, bevel, seg)
    if sub:
        c.subsurf(o, sub)
    c.smooth(o)
    return o


def tube(name, points, radius):
    """A smooth bent tube through Godot points."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    sp = curve.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]
        bp.co = g(*p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    c.smooth(o)
    return o


c.reset()
paint = c.material("Paint", (0.9, 0.2, 0.18), 0.25, clearcoat=0.8)
trim = c.material("Trim", (0.12, 0.12, 0.14), 0.6)
chrome = c.material("Chrome", (0.85, 0.86, 0.9), 0.15, metal=1.0)
white = c.material("Plate", (0.96, 0.96, 0.96), 0.4)

parts = []
low = 0.01
# Floor tub, running the length of the kart.
parts.append((rounded("Trim_floor", (0, low + 0.05, 0.0), (0.66, 0.1, 1.7), 0.04, 3), trim))
# Nose cone: wide at the back, narrow and raked up at the front.
parts.append((rounded("Paint_nose", (0, low + 0.19, -0.78), (0.86, 0.32, 0.72), 0.12, 4, taper_front=0.7, taper_top=0.82, lift_front=0.06, drop_front=0.13, sub=2), paint))
# A raised cowl from the nose back to the steering wheel.
parts.append((rounded("Paint_cowl", (0, low + 0.3, -0.36), (0.42, 0.18, 0.5), 0.08, 4, taper_front=0.8, drop_front=0.08, taper_top=0.75, sub=2), paint))
# A front spoiler lip under the nose.
parts.append((rounded("Trim_lip", (0, low + 0.04, -1.08), (0.92, 0.06, 0.2), 0.03, 3), trim))
# Side pods between the wheels, with a little wing on top.
for sx in (-1, 1):
    parts.append((rounded("Paint_pod%d" % sx, (sx * 0.47, low + 0.12, 0.0), (0.34, 0.17, 0.86), 0.07, 4, taper_front=0.8, taper_back=0.9, taper_top=0.78, drop_front=0.04, sub=2), paint))
    parts.append((rounded("Trim_podbase%d" % sx, (sx * 0.5, low + 0.03, 0.0), (0.3, 0.05, 0.84), 0.02, 2), trim))
# Bucket seat: a scooped shell with a tall back.
parts.append((rounded("Trim_seat", (0, low + 0.2, 0.27), (0.42, 0.18, 0.42), 0.09, 4, sub=2), trim))
parts.append((rounded("Trim_seatback", (0, low + 0.44, 0.47), (0.46, 0.5, 0.12), 0.055, 4, taper_top=0.82, sub=2), trim))
parts.append((rounded("Paint_seatstripe", (0, low + 0.62, 0.53), (0.36, 0.1, 0.04), 0.02, 2, sub=1), paint))
# Engine block beside the seat, with a rounded air box on top.
parts.append((rounded("Chrome_engine", (0.3, low + 0.2, 0.58), (0.22, 0.22, 0.26), 0.04, 3), chrome))
parts.append((rounded("Paint_airbox", (0.3, low + 0.36, 0.58), (0.2, 0.1, 0.22), 0.05, 3, sub=2), paint))
# Number plate on the nose: a rounded white disc tipped back.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.13, depth=0.03, location=g(0, low + 0.33, -0.66))
plate = bpy.context.object
plate.name = "Plate_number"
plate.rotation_euler = (math.radians(90 - 28), 0, 0)
c.bevel(plate, 0.012, 2)
c.smooth(plate)
parts.append((plate, white))
# Bumpers: a front loop under the nose and a wide bar wrapping the back.
parts.append((tube("Chrome_frontbar", [(-0.42, low + 0.06, -0.95), (-0.3, low + 0.06, -1.18), (0.3, low + 0.06, -1.18), (0.42, low + 0.06, -0.95)], 0.03), chrome))
parts.append((tube("Chrome_rearbar", [(-0.72, low + 0.1, 0.72), (-0.7, low + 0.1, 1.12), (0.7, low + 0.1, 1.12), (0.72, low + 0.1, 0.72)], 0.035), chrome))
for sx in (-1, 1):
    parts.append((tube("Chrome_strut%d" % sx, [(sx * 0.3, low + 0.05, 0.75), (sx * 0.32, low + 0.1, 1.12)], 0.025), chrome))
    # Nerf bars along the sides, under the pods.
    parts.append((tube("Chrome_nerf%d" % sx, [(sx * 0.4, low + 0.05, -0.4), (sx * 0.72, low + 0.08, -0.3), (sx * 0.72, low + 0.08, 0.3), (sx * 0.4, low + 0.05, 0.4)], 0.025), chrome))

objs = []
for o, m in parts:
    c.assign(o, m)
    c.apply_all(o)
    objs.append(o)

c.export(os.path.abspath(OUT), objs)
print("wrote", os.path.abspath(OUT))

if len(sys.argv) > 1:
    # Preview with stand-in wheels, so the proportions can be judged.
    for (x, z) in [(-0.6, -0.725), (0.6, -0.725), (-0.6, 0.725), (0.6, 0.725)]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.3, depth=0.36, location=g(x, 0.3, z))
        w = bpy.context.object
        w.rotation_euler = (0, math.radians(90), 0)
        c.bevel(w, 0.08, 3)
        c.smooth(w)
        c.assign(w, c.material("tyre", (0.08, 0.08, 0.09), 0.8))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.location.z += 0.0
    c.preview(sys.argv[1], target=(0, 0, 0.3), dist=3.8, elev=22, azim=215)
