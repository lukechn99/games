"""Kart bodies for the other three chassis, in the same style as kart.py's
frame (one sculpted shell plus named parts the game paints):

  soapbox  a gravity racer: a teardrop shell on wooden axle beams, a
           brake lever and a tail fin; no engine
  hauler   a chunky work truck: boxy body, grille and headlights, bull
           bar, black wheel arches, roll cage and stack exhausts
  racer    a long, low single-seater: needle nose, front and rear wings,
           sidepods and an airbox

Part prefixes: Paint (chassis colour), Accent, Trim (charcoal), Metal
(gunmetal), Plate (white), Wood (varnished plank). Godot axes (x right,
y up, z back); wheel centres at y 0.3, fitted to Parts.CHASSIS.

    python3 racing/tools/blender/kart_bodies.py [soapbox|hauler|racer] [preview.png]
"""
import os
import sys
import math
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c
import shapes as s

MODELS = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")
# wheelbase, track, wheel radius front/rear (Parts.CHASSIS)
FIT = {
    "soapbox": (1.15, 1.0, 0.22, 0.3),
    "hauler": (1.7, 1.45, 0.3, 0.42),
    "racer": (1.9, 1.15, 0.24, 0.32),
}


def mats(paint_rgb):
    return {
        "Paint": c.material("Paint", paint_rgb, 0.22, clearcoat=0.9),
        "Accent": c.material("Accent", (1.0, 0.85, 0.2), 0.3, clearcoat=0.6),
        "Trim": c.material("Trim", (0.15, 0.15, 0.18), 0.55),
        "Metal": c.material("Metal", (0.55, 0.5, 0.45), 0.35, metal=0.7),
        "Plate": c.material("Plate", (0.97, 0.97, 0.95), 0.35),
        "Wood": c.material("Wood", (0.62, 0.42, 0.25), 0.6),
    }


def soft(o, levels=2):
    c.subsurf(o, levels)
    c.smooth(o)
    return o


def tilted(o, deg_x=0.0, deg_z=0.0):
    o.rotation_euler = (math.radians(deg_x), math.radians(deg_z), 0)
    return o


def soapbox():
    P = []
    body = soft(s.loft("Paint_body", [
        (-0.98, 0.1, 0.24, 0.34, 2.2),    # rounded nose
        (-0.88, 0.22, 0.15, 0.44, 2.4),
        (-0.62, 0.3, 0.11, 0.52, 2.6),
        (-0.36, 0.32, 0.1, 0.55, 2.8),    # cowl in front of the driver
        (-0.2, 0.32, 0.1, 0.4, 3.0),      # cockpit opening
        (0.22, 0.32, 0.1, 0.36, 3.0),
        (0.45, 0.3, 0.11, 0.46, 2.8),     # hump behind the driver
        (0.7, 0.24, 0.14, 0.43, 2.6),
        (0.9, 0.14, 0.2, 0.35, 2.4),
        (1.02, 0.04, 0.26, 0.3, 2.2),     # tail point
    ], around=28))
    P.append(body)
    # A white band round the waist and a stripe over the top.
    P.append(soft(s.loft("Accent_stripe", [
        (-0.9, 0.05, 0.42, 0.455, 3.0),
        (-0.62, 0.07, 0.51, 0.535, 3.0),
        (-0.37, 0.07, 0.545, 0.565, 3.0),
    ], around=12), 1))
    P.append(soft(s.loft("Accent_tailstripe", [
        (0.45, 0.06, 0.455, 0.475, 3.0),
        (0.72, 0.05, 0.42, 0.44, 3.0),
        (0.92, 0.03, 0.335, 0.35, 3.0),
    ], around=12), 1))
    # Tail fin.
    P.append(soft(s.loft("Accent_fin", [
        (0.55, 0.02, 0.44, 0.47, 2.0),
        (0.8, 0.025, 0.4, 0.66, 2.0),
        (0.95, 0.02, 0.33, 0.62, 2.0),
    ], around=10), 1))
    # Wooden axle beams the wheels hang off, and a plank bumper.
    for z in (-0.575, 0.575):
        P.append(s.box("Wood_axle", (0, 0.3, z), (0.92, 0.09, 0.12), 0.015, 2))
        for sx in (-1, 1):
            P.append(s.cylinder("Metal_hub", (sx * 0.46, 0.3, z), 0.045, 0.06, "x", 12, 0.01))
    P.append(s.box("Wood_bumper", (0, 0.24, -1.0), (0.42, 0.1, 0.07), 0.02, 2))
    # A brake lever on the right, and a little windscreen.
    P.append(s.tube("Wood_brake", [(0.3, 0.32, 0.05), (0.37, 0.52, -0.02), (0.39, 0.66, -0.06)], 0.025))
    P.append(s.cylinder("Trim_brake_knob", (0.39, 0.68, -0.06), 0.04, 0.06, "y", 12, 0.01))
    P.append(tilted(s.box("Trim_screen", (0, 0.6, -0.34), (0.38, 0.13, 0.02), 0.01, 2), -35))
    # Seat back.
    P.append(soft(tilted(s.box("Trim_seatback", (0, 0.42, 0.33), (0.4, 0.34, 0.07), 0.04, 3), -15), 1))
    # Number discs.
    P.append(tilted(s.cylinder("Plate_number", (0, 0.43, -0.76), 0.1, 0.03, "z", 24, 0.01), 55))
    for sx in (-1, 1):
        P.append(s.cylinder("Plate_side", (sx * 0.322, 0.31, 0.05), 0.09, 0.02, "x", 24, 0.006))
    return P, {"seat": (0.2, 0.15), "wheel_at": (0, 0.56, -0.32), "exhausts": []}


def hauler():
    P = []
    P.append(soft(s.loft("Paint_body", [
        (-1.24, 0.48, 0.2, 0.5, 6.0),     # front face
        (-1.12, 0.55, 0.13, 0.6, 6.0),
        (-0.72, 0.57, 0.1, 0.66, 6.0),    # bonnet
        (-0.46, 0.57, 0.1, 0.62, 6.0),
        (-0.3, 0.55, 0.1, 0.44, 6.0),     # cab, open
        (0.35, 0.55, 0.1, 0.44, 6.0),
        (0.52, 0.57, 0.1, 0.62, 6.0),     # engine box
        (1.05, 0.57, 0.12, 0.62, 6.0),
        (1.2, 0.5, 0.18, 0.54, 6.0),
    ], around=32), 1))
    # Grille, bars and headlights.
    P.append(s.box("Trim_grille", (0, 0.36, -1.255), (0.62, 0.22, 0.04), 0.015, 2))
    for k in range(4):
        P.append(s.box("Metal_grillebar", (0, 0.28 + k * 0.055, -1.275), (0.58, 0.02, 0.02), 0.005, 1))
    for sx in (-1, 1):
        P.append(s.cylinder("Plate_lamp", (sx * 0.4, 0.47, -1.245), 0.075, 0.04, "z", 20, 0.01))
        P.append(s.cylinder("Trim_lampring", (sx * 0.4, 0.47, -1.235), 0.09, 0.03, "z", 20, 0.01))
    # Bull bar.
    P.append(s.tube("Metal_bullbar", [(-0.52, 0.18, -1.2), (-0.52, 0.5, -1.36), (0.52, 0.5, -1.36), (0.52, 0.18, -1.2)], 0.04, 6))
    P.append(s.tube("Metal_bullbar_low", [(-0.52, 0.26, -1.31), (0.52, 0.26, -1.31)], 0.03))
    # Black arches over all four fat wheels.
    wb, tr, rf, rr = FIT["hauler"]
    for z, r in ((-wb / 2, rf), (wb / 2, rr)):
        for sx in (-1, 1):
            top = 0.3 + r + 0.07
            arch = soft(s.loft("Trim_arch", [
                (z - r - 0.12, 0.2, top - 0.22, top - 0.14, 3.0),
                (z - r * 0.55, 0.22, top - 0.05, top + 0.03, 3.0),
                (z, 0.22, top, top + 0.08, 3.0),
                (z + r * 0.55, 0.22, top - 0.05, top + 0.03, 3.0),
                (z + r + 0.12, 0.2, top - 0.22, top - 0.14, 3.0),
            ], around=14))
            arch.location = s.g(sx * tr / 2, 0, 0)
            P.append(arch)
    # Roll cage behind the driver, braced to the back.
    P.append(s.tube("Metal_cage", [(-0.44, 0.44, 0.46), (-0.4, 1.05, 0.42), (0.4, 1.05, 0.42), (0.44, 0.44, 0.46)], 0.035, 6))
    for sx in (-1, 1):
        P.append(s.tube("Metal_brace", [(sx * 0.4, 1.0, 0.44), (sx * 0.46, 0.62, 1.0)], 0.028))
    # Stack exhausts up the sides of the engine box, kinked back at the top.
    for sx in (-1, 1):
        P.append(s.tube("Metal_stack", [(sx * 0.5, 0.58, 0.66), (sx * 0.5, 1.02, 0.66), (sx * 0.5, 1.1, 0.76)], 0.05, 6))
        P.append(tilted(s.cylinder("Trim_stacktip", (sx * 0.5, 1.12, 0.8), 0.065, 0.08, "z", 16, 0.01), -30))
    # Engine louvres on the box, a seat back, mud flaps and door numbers.
    for k in range(4):
        P.append(s.box("Trim_louvre", (0, 0.625, 0.66 + k * 0.1), (0.5, 0.02, 0.04), 0.005, 1))
    P.append(soft(tilted(s.box("Trim_seatback", (0, 0.6, 0.38), (0.48, 0.42, 0.08), 0.04, 3), -12), 1))
    for sx in (-1, 1):
        P.append(s.box("Trim_flap", (sx * tr / 2, 0.36, wb / 2 + rr + 0.1), (0.3, 0.3, 0.03), 0.01, 2))
        P.append(s.cylinder("Plate_side", (sx * 0.572, 0.3, -0.05), 0.12, 0.02, "x", 24, 0.006))
    P.append(s.box("Accent_bonnetstripe", (0, 0.665, -0.8), (0.24, 0.012, 0.66), 0.004, 1))
    return P, {"seat": (0.32, 0.22), "wheel_at": (0, 0.74, -0.3), "exhausts": [(-0.5, 1.16, 0.84), (0.5, 1.16, 0.84)]}


def racer():
    P = []
    P.append(soft(s.loft("Paint_body", [
        (-1.62, 0.05, 0.2, 0.25, 2.5),    # needle nose
        (-1.32, 0.12, 0.16, 0.31, 2.8),
        (-0.95, 0.18, 0.13, 0.38, 3.0),   # over the front axle
        (-0.55, 0.25, 0.1, 0.44, 3.5),    # cockpit front
        (-0.22, 0.29, 0.1, 0.35, 4.0),    # cockpit opening
        (0.24, 0.29, 0.1, 0.37, 4.0),
        (0.44, 0.27, 0.1, 0.64, 3.5),     # airbox behind the head
        (0.75, 0.23, 0.12, 0.5, 3.0),
        (1.05, 0.17, 0.16, 0.37, 3.0),
        (1.26, 0.09, 0.2, 0.3, 3.0),
    ], around=28)))
    for sx in (-1, 1):
        pod = soft(s.loft("Paint_pod", [
            (-0.42, 0.05, 0.14, 0.22, 3.0),
            (-0.25, 0.12, 0.1, 0.32, 4.0),
            (0.35, 0.12, 0.1, 0.3, 4.0),
            (0.62, 0.05, 0.13, 0.22, 3.0),
        ], around=16))
        pod.location = s.g(sx * 0.36, 0, 0)
        P.append(pod)
        P.append(s.box("Trim_podmouth", (sx * 0.36, 0.22, -0.27), (0.18, 0.12, 0.03), 0.01, 2))
        P.append(s.cylinder("Plate_side", (sx * 0.485, 0.21, 0.1), 0.08, 0.02, "x", 24, 0.006))
    # Stripe down the nose.
    P.append(soft(s.loft("Accent_stripe", [
        (-1.6, 0.03, 0.24, 0.255, 3.0),
        (-0.95, 0.06, 0.375, 0.39, 3.0),
        (-0.56, 0.07, 0.435, 0.45, 3.0),
    ], around=12), 1))
    # Front wing with end plates.
    P.append(s.box("Accent_frontwing", (0, 0.12, -1.52), (1.08, 0.035, 0.24), 0.01, 2))
    P.append(s.box("Accent_flap", (0, 0.16, -1.45), (0.95, 0.025, 0.12), 0.008, 2))
    for sx in (-1, 1):
        P.append(s.box("Trim_endplate", (sx * 0.55, 0.16, -1.52), (0.025, 0.14, 0.28), 0.006, 2))
    # Rear wing on struts, with end plates.
    P.append(tilted(s.box("Accent_rearwing", (0, 0.74, 1.18), (0.92, 0.04, 0.28), 0.01, 2), 8))
    P.append(tilted(s.box("Accent_rearflap", (0, 0.81, 1.27), (0.9, 0.025, 0.12), 0.008, 2), 18))
    for sx in (-1, 1):
        P.append(s.box("Trim_endplate", (sx * 0.47, 0.72, 1.2), (0.025, 0.26, 0.36), 0.006, 2))
        P.append(s.tube("Trim_strut", [(sx * 0.12, 0.34, 1.02), (sx * 0.12, 0.73, 1.16)], 0.022))
    # Airbox intake, seat back and number on the nose.
    P.append(s.box("Trim_intake", (0, 0.57, 0.39), (0.16, 0.12, 0.04), 0.02, 2))
    P.append(soft(tilted(s.box("Trim_seatback", (0, 0.36, 0.3), (0.36, 0.28, 0.06), 0.03, 3), -20), 1))
    P.append(tilted(s.cylinder("Plate_number", (0, 0.335, -1.05), 0.09, 0.025, "z", 24, 0.01), 70))
    # Twin exhausts under the rear wing.
    for sx in (-1, 1):
        P.append(s.tube("Metal_exhaust", [(sx * 0.1, 0.3, 1.08), (sx * 0.1, 0.38, 1.3)], 0.04, 5))
        P.append(tilted(s.cylinder("Trim_exhaust_tip", (sx * 0.1, 0.39, 1.36), 0.05, 0.08, "z", 16, 0.01), -15))
    return P, {"seat": (0.18, 0.12), "wheel_at": (0, 0.5, -0.4), "exhausts": [(-0.1, 0.41, 1.42), (0.1, 0.41, 1.42)]}


COLORS = {"soapbox": (0.1, 0.45, 0.95), "hauler": (1.0, 0.68, 0.05), "racer": (0.15, 0.72, 0.28)}
BUILD = {"soapbox": soapbox, "hauler": hauler, "racer": racer}


def build(kind):
    m = mats(COLORS[kind])
    parts, meta = BUILD[kind]()
    for o in parts:
        c.assign(o, m[o.name.split("_")[0].split(".")[0]])
        c.apply_all(o)
    return parts, meta


def preview_wheels(kind):
    import mathutils
    wb, tr, rf, rr = FIT[kind]
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(os.path.join(MODELS, "wheel.glb")))
    wheel_objs = [o for o in bpy.context.selected_objects]
    for i, (x, z) in enumerate([(-tr / 2, -wb / 2), (tr / 2, -wb / 2), (-tr / 2, wb / 2), (tr / 2, wb / 2)]):
        r = rf if i < 2 else rr
        for o in wheel_objs:
            if o.type != "MESH":
                continue
            d = o.copy()
            d.parent = None
            d.matrix_world = mathutils.Matrix.Translation(s.g(x, 0.3, z)) @ mathutils.Matrix.Scale(r / 0.5, 4) @ o.matrix_world
            bpy.context.collection.objects.link(d)
    for o in wheel_objs:
        bpy.data.objects.remove(o, do_unlink=True)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    kinds = [a for a in args if a in BUILD] or list(BUILD)
    out_png = next((a for a in args if a.endswith(".png")), None)
    import json
    for kind in kinds:
        c.reset()
        objs, meta = build(kind)
        path = os.path.abspath(os.path.join(MODELS, "kart_%s.glb" % kind))
        c.export(path, objs, max_tris=7000, ao=True)
        print("wrote", path, json.dumps(meta))
        if out_png:
            preview_wheels(kind)
            c.sheet(out_png.replace(".png", "_%s.png" % kind), [(18, 215), (12, 150), (30, 0)], target=(0, 0, 0.3), dist=3.8)
