"""Kart body v2 for the "frame" chassis: one smooth sculpted shell, lofted
through cross-sections from a low, wide nose up over the cowl, dipping
round the cockpit and rising to the engine cover; front fenders over the
wheels, a bucket seat, a proper steering wheel, twin exhausts and a
number disc. Parts are named for how the game paints them:

  Paint*  chassis colour (glossy)   Accent* lighter chassis colour
  Trim*   dark charcoal             Metal*  warm gunmetal (not mirror
  Plate*  white                     chrome: chrome mirrored the sky and
                                    washed out to pale blue in game)

Godot axes (x right, y up, z back), fitted to Parts.CHASSIS["frame"]:
wheelbase 1.45, track 1.2, wheels at y 0.25.

    python3 racing/tools/blender/kart.py [preview.png]
"""
import os
import sys
import math
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c
import shapes as s

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "kart_frame.glb")
LOW = 0.07   # underside of the tub above the ground plane of the wheel mounts


def build(preview_wheels=False):
    paint = c.material("Paint", (0.92, 0.16, 0.14), 0.22, clearcoat=0.9)
    accent = c.material("Accent", (1.0, 0.85, 0.2), 0.3, clearcoat=0.6)
    trim = c.material("Trim", (0.15, 0.15, 0.18), 0.55)
    metal = c.material("Metal", (0.55, 0.5, 0.45), 0.35, metal=0.7)
    white = c.material("Plate", (0.97, 0.97, 0.95), 0.35)
    parts = []

    # The shell. (z, half width, bottom, top[, squareness])
    body = s.loft("Paint_body", [
        (-1.12, 0.30, LOW + 0.02, LOW + 0.12, 3.0),   # nose tip, low
        (-0.98, 0.42, LOW, LOW + 0.2, 3.5),
        (-0.72, 0.44, LOW - 0.01, LOW + 0.33, 4.0),   # cowl rising
        (-0.45, 0.40, LOW - 0.01, LOW + 0.42, 4.0),   # dash, behind the wheel
        (-0.25, 0.44, LOW - 0.01, LOW + 0.3, 4.5),
        (0.0, 0.47, LOW - 0.01, LOW + 0.2, 5.0),      # cockpit, low sides
        (0.3, 0.47, LOW - 0.01, LOW + 0.22, 5.0),
        (0.55, 0.44, LOW - 0.01, LOW + 0.4, 4.5),     # engine cover
        (0.82, 0.38, LOW, LOW + 0.36, 4.0),
        (0.98, 0.3, LOW + 0.04, LOW + 0.26, 3.5),     # tail
    ], around=28)
    c.subsurf(body, 2)
    c.smooth(body)
    parts.append((body, paint))
    # A yellow stripe down the nose and cowl.
    stripe = s.loft("Accent_stripe", [
        (-1.1, 0.06, LOW + 0.1, LOW + 0.14, 3.0),
        (-0.72, 0.08, LOW + 0.3, LOW + 0.345, 3.0),
        (-0.46, 0.08, LOW + 0.4, LOW + 0.435, 3.0),
    ], around=12)
    c.subsurf(stripe, 1)
    c.smooth(stripe)
    parts.append((stripe, accent))
    # Dark floor pan and skirts, so the shell sits on something.
    pan = s.loft("Trim_pan", [
        (-1.0, 0.36, LOW - 0.05, LOW + 0.03, 6.0),
        (0.0, 0.52, LOW - 0.05, LOW + 0.03, 6.0),
        (0.95, 0.36, LOW - 0.03, LOW + 0.05, 6.0),
    ], around=20)
    c.subsurf(pan, 1)
    c.smooth(pan)
    parts.append((pan, trim))
    # Front fenders over the wheels, on short struts.
    for sx in (-1, 1):
        f = s.loft("Paint_fender", [
            (-1.02, 0.17, 0.5, 0.56, 3.0),
            (-0.88, 0.2, 0.62, 0.7, 3.0),
            (-0.72, 0.2, 0.65, 0.73, 3.0),
            (-0.56, 0.2, 0.61, 0.69, 3.0),
            (-0.44, 0.16, 0.5, 0.55, 3.0),
        ], around=14)
        f.location = s.g(sx * 0.6, 0, 0)
        c.subsurf(f, 2)
        c.smooth(f)
        parts.append((f, paint))
        parts.append((s.tube("Trim_strut", [(sx * 0.38, LOW + 0.2, -0.72), (sx * 0.5, 0.64, -0.72)], 0.025), trim))
    # Bucket seat and a tall seat back with a head rest.
    seat = s.loft("Trim_seat", [
        (0.1, 0.22, LOW + 0.05, LOW + 0.18, 4.0),
        (0.35, 0.24, LOW + 0.05, LOW + 0.2, 4.0),
    ], around=16)
    c.subsurf(seat, 1)
    c.smooth(seat)
    parts.append((seat, trim))
    back = s.box("Trim_seatback", (0, LOW + 0.45, 0.43), (0.46, 0.52, 0.1), 0.045, 4)
    back.rotation_euler = (math.radians(-12), 0, 0)
    c.subsurf(back, 1)
    c.smooth(back)
    parts.append((back, trim))
    # Steering wheel on its column.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.025, major_segments=24, minor_segments=8, location=s.g(0, LOW + 0.55, -0.28))
    wheel = bpy.context.object
    wheel.name = "Trim_wheel"
    wheel.rotation_euler = (math.radians(90 - 30), 0, 0)
    c.smooth(wheel)
    parts.append((wheel, trim))
    hubw = s.cylinder("Accent_wheelhub", (0, LOW + 0.55, -0.28), 0.045, 0.04, "z", 16, 0.01)
    hubw.rotation_euler = (math.radians(-30), 0, 0)
    parts.append((hubw, accent))
    for k in range(3):
        a = math.tau * k / 3 + math.pi / 2
        sp = s.box("Trim_wheelspoke", (math.cos(a) * 0.07, LOW + 0.55 + math.sin(a) * 0.07 * math.cos(math.radians(30)), -0.28 - math.sin(a) * 0.07 * math.sin(math.radians(30))), (0.02, 0.02, 0.02), 0)
        parts.append((sp, trim))
    parts.append((s.tube("Trim_column", [(0, LOW + 0.3, -0.52), (0, LOW + 0.53, -0.3)], 0.022), trim))
    # Engine: a block with fins and two fat exhausts curling up and back.
    eng = s.box("Metal_engine", (0, LOW + 0.42, 0.72), (0.34, 0.16, 0.26), 0.04, 3)
    parts.append((eng, metal))
    for k in range(4):
        fin = s.box("Trim_fin", (0, LOW + 0.52 + k * 0.0, 0.62 + k * 0.065), (0.3, 0.04, 0.025), 0.008, 2)
        parts.append((fin, trim))
    for sx in (-1, 1):
        pipe = s.tube("Metal_exhaust", [(sx * 0.12, LOW + 0.4, 0.8), (sx * 0.17, LOW + 0.42, 1.0), (sx * 0.2, LOW + 0.55, 1.13)], 0.05, 5)
        parts.append((pipe, metal))
        tip = s.cylinder("Trim_exhaust_tip", (sx * 0.2, LOW + 0.58, 1.15), 0.065, 0.08, "z", 16, 0.01)
        tip.rotation_euler = (math.radians(-55), 0, 0)
        parts.append((tip, trim))
    # Number disc on the nose, and side discs.
    plate = s.cylinder("Plate_number", (0, LOW + 0.27, -0.84), 0.12, 0.03, "z", 28, 0.01)
    plate.rotation_euler = (math.radians(62), 0, 0)
    parts.append((plate, white))
    for sx in (-1, 1):
        d = s.cylinder("Plate_side", (sx * 0.475, LOW + 0.13, 0.15), 0.08, 0.02, "x", 24, 0.006)
        parts.append((d, white))
    # Bumpers: dark rubber, front and rear.
    parts.append((s.tube("Trim_frontbar", [(-0.36, LOW + 0.06, -1.06), (-0.22, LOW + 0.05, -1.2), (0.22, LOW + 0.05, -1.2), (0.36, LOW + 0.06, -1.06)], 0.04), trim))
    parts.append((s.tube("Trim_rearbar", [(-0.7, LOW + 0.1, 0.78), (-0.66, LOW + 0.1, 1.06), (0.66, LOW + 0.1, 1.06), (0.7, LOW + 0.1, 0.78)], 0.045), trim))
    objs = []
    for o, m in parts:
        c.assign(o, m)
        c.apply_all(o)
        objs.append(o)
    return objs


if __name__ == "__main__":
    c.reset()
    objs = build()
    c.export(os.path.abspath(OUT), objs, max_tris=7000, ao=True)
    print("wrote", os.path.abspath(OUT))
    if len(sys.argv) > 1:
        bpy.ops.import_scene.gltf(filepath=os.path.abspath(os.path.join(os.path.dirname(OUT), "wheel.glb")))
        wheel_objs = [o for o in bpy.context.selected_objects]
        # Place four copies at the mounts (radius 0.3 from 0.5: scale 0.6).
        import mathutils
        root = bpy.data.objects.new("wheelroot", None)
        bpy.context.collection.objects.link(root)
        for o in wheel_objs:
            if o.parent is None:
                o.parent = root
        for i, (x, z) in enumerate([(-0.6, -0.725), (0.6, -0.725), (-0.62, 0.725), (0.62, 0.725)]):
            for o in wheel_objs:
                if o.type != "MESH":
                    continue
                d = o.copy()
                d.parent = None
                d.matrix_world = mathutils.Matrix.Translation(s.g(x, 0.3, z)) @ mathutils.Matrix.Scale(0.6 if i < 2 else 0.66, 4) @ o.matrix_world
                bpy.context.collection.objects.link(d)
        for o in wheel_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.objects.remove(root, do_unlink=True)
        c.sheet(sys.argv[1], [(18, 215), (12, 150), (30, 0)], target=(0, 0, 0.3), dist=3.6)
