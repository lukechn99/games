"""A fat cartoon kart wheel: a chunky tyre with rounded shoulders and tread
blocks, a coloured dished rim with five spokes and a hub cap. Radius 0.5,
width 0.46, axle along x; the game scales it to each tyre.
Parts: Tyre (rubber), Rim (painted), Hub (metal), Nut (dark).

    python3 racing/tools/blender/wheel.py [preview.png]
"""
import os
import sys
import math
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c
import shapes as s

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "wheel.glb")


def build():
    W = 0.23   # half width
    # Tyre: inner lip, sidewall bulge, rounded shoulder, flat tread.
    prof = [(-W * 0.75, 0.3), (-W, 0.34), (-W * 1.02, 0.42), (-W * 0.95, 0.47), (-W * 0.78, 0.5),
            (-W * 0.45, 0.505), (0.0, 0.505), (W * 0.45, 0.505),
            (W * 0.78, 0.5), (W * 0.95, 0.47), (W * 1.02, 0.42), (W, 0.34), (W * 0.75, 0.3)]
    tread_rings = {4, 5, 6, 7, 8}

    def tread(k, i):
        if i not in tread_rings:
            return 1.0
        # Chevron blocks: alternate sides offset by half a block.
        side = 0 if i < 6 else 1
        return 1.0 if ((k + side * 2) // 2) % 2 == 0 else 0.955
    tyre = s.lathe("Tyre", prof, segs=48, cap=False)
    c.smooth(tyre)
    rubber = c.material("Tyre", (0.13, 0.13, 0.15), 0.75)
    blocks = []
    n = 22
    for k in range(n):
        for side in (-1, 1):
            a = math.tau * (k + (0.5 if side > 0 else 0.0)) / n
            r = 0.505
            b = s.box("Tyre_block", (side * W * 0.42, math.cos(a) * r, math.sin(a) * r), (W * 0.6, 0.045, 0.1), 0.016, 2)
            b.rotation_euler = (a, 0, 0)   # stand it on the tread
            bpy.context.view_layer.objects.active = b
            bpy.ops.object.select_all(action="DESELECT")
            b.select_set(True)
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
            blocks.append(b)
    rim_mat = c.material("Rim", (1.0, 0.8, 0.12), 0.3, clearcoat=0.6)
    spoke_mat = c.material("Rim_dark", (0.92, 0.55, 0.05), 0.3, clearcoat=0.6)
    hub_mat = c.material("Hub", (0.62, 0.6, 0.58), 0.3, metal=0.6)
    nut_mat = c.material("Nut", (0.2, 0.2, 0.22), 0.5)
    objs = [(tyre, rubber)] + [(b, rubber) for b in blocks]
    for sd in (-1, 1):
        # A dish: the lip stands proud, the face sinks in toward the hub.
        prof_r = [(-W * 0.52, 0.0), (-W * 0.56, 0.16), (-W * 0.7, 0.27), (-W * 0.86, 0.315), (-W * 0.86, 0.335), (-W * 0.6, 0.345), (-W * 0.4, 0.3), (-W * 0.4, 0.0)]
        rim = s.lathe("Rim", [(x * -sd, r) for x, r in prof_r], segs=40)
        c.smooth(rim)
        objs.append((rim, rim_mat))
        for k in range(5):
            a = math.tau * k / 5
            sp = s.box("Rim_spoke", (sd * W * 0.66, math.cos(a) * 0.17, math.sin(a) * 0.17), (0.045, 0.25, 0.075), 0.015)
            sp.rotation_euler = (a, 0, 0)
            bpy.context.view_layer.objects.active = sp
            bpy.ops.object.select_all(action="DESELECT")
            sp.select_set(True)
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
            objs.append((sp, spoke_mat))
        hub = s.cylinder("Hub", (sd * W * 0.68, 0, 0), 0.085, 0.1, "x", 20, 0.02)
        objs.append((hub, hub_mat))
        for k in range(5):
            a = math.tau * k / 5 + 0.6
            n = s.cylinder("Nut", (sd * W * 0.9, math.cos(a) * 0.05, math.sin(a) * 0.05), 0.016, 0.03, "x", 8)
            objs.append((n, nut_mat))
    out = []
    for o, m in objs:
        c.assign(o, m)
        c.apply_all(o)
        out.append(o)
    # The other side of the rim too (wheels are seen from both sides).
    return out


if __name__ == "__main__":
    c.reset()
    objs = build()
    c.export(os.path.abspath(OUT), objs)
    print("wrote", os.path.abspath(OUT))
    if len(sys.argv) > 1:
        for o in objs:
            o.location.z += 0.52
        c.sheet(sys.argv[1], [(8, 80), (8, -80), (20, 40)], target=(0, 0, 0.52), dist=2.0)
