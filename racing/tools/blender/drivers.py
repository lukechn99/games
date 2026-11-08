"""Drivers: the four animals, sculpted as one smooth surface each.

Each body part is a soft primitive (ellipsoid, capsule, tapered cone) as a
signed distance field, and the parts are joined with a smooth union, so an
ear grows out of the head with a rounded fillet instead of a cone stuck on a
sphere. The surface comes out with marching cubes. Colour patches (belly,
muzzle, cheeks, inner ears, tail tip) are painted into the vertex colours,
multiplied by baked ambient occlusion. Eyes, nose and mouth are separate
little glossy pieces, and the fox's tail and the deer's antlers are their
own objects so the game can still let them wobble.

Objects in each drivers_<animal>.glb (Godot axes, metres, driver space with
the seat at the origin, as KartVisual._build_driver used):
  Body_seated, Body_standing   torso + arms (+ legs standing), origin 0
  Head                         head with ears/snout/horns, origin at the
                               head pivot (0, 0.72, 0)
  Eye*, Sparkle*, Nose*, Mouth*  on the head
  Tail / Antler_L, Antler_R    wobbly parts, origin at their pivots

    python3 racing/tools/blender/drivers.py [fox|frog|rhino|deer] [preview.png]
"""
import os
import sys
import math
import numpy as np
import bpy
import bmesh
from skimage.measure import marching_cubes

sys.path.insert(0, os.path.dirname(__file__))
import common as c
import shapes as s

MODELS = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")
HEAD = np.array([0.0, 0.72, 0.0])
VOX = 0.009

COLORS = {
    "fox": {"body": (0.96, 0.5, 0.16), "belly": (1.0, 0.96, 0.9)},
    "frog": {"body": (0.35, 0.8, 0.3), "belly": (0.85, 0.95, 0.55)},
    "rhino": {"body": (0.55, 0.58, 0.64), "belly": (0.72, 0.74, 0.78)},
    "deer": {"body": (0.76, 0.52, 0.32), "belly": (0.98, 0.9, 0.78)},
}
PINK = (1.0, 0.55, 0.62)
EAR_PINK = (1.0, 0.75, 0.75)
IVORY = (0.95, 0.93, 0.86)
ANTLER = (0.6, 0.42, 0.25)
SNOUT = {"fox": 0.17, "deer": 0.15, "rhino": 0.13, "frog": 0.13}   # muzzle length (z radius)


# --- Distance fields (points P: (N, 3), Godot axes) ------------------------

def ellipsoid(cen, r):
    cen = np.array(cen, float)
    r = np.array(r, float)

    def f(P):
        q = P - cen
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    return f


def round_cone(a, b, r1, r2):
    """A capsule that tapers from radius r1 at a to r2 at b (iq's sdRoundCone)."""
    a = np.array(a, float)
    b = np.array(b, float)

    def f(P):
        ba = b - a
        l2 = ba @ ba
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = P - a
        y = pa @ ba
        z = y - l2
        w = pa * l2 - np.outer(y, ba)
        x2 = np.sum(w * w, axis=1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d_end = np.sqrt(x2 + z2) * il2 - r2
        d_start = np.sqrt(x2 + y2) * il2 - r1
        d_mid = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
        return np.where(np.sign(z) * a2 * z2 > k, d_end, np.where(np.sign(y) * a2 * y2 < k, d_start, d_mid))
    return f


def capsule(a, b, r):
    return round_cone(a, b, r, r * 0.999)


def smin(d1, d2, k):
    if k <= 0:
        return np.minimum(d1, d2)
    h = np.clip(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0)
    return d2 * (1 - h) + d1 * h - k * h * (1 - h)


def sculpt(parts, lo, hi):
    """parts: [(sdf, blend k)] joined in order. Returns (verts, faces) in
    Godot space."""
    lo = np.array(lo, float)
    hi = np.array(hi, float)
    n = np.ceil((hi - lo) / VOX).astype(int) + 1
    xs = [lo[i] + np.arange(n[i]) * VOX for i in range(3)]
    X, Y, Z = np.meshgrid(*xs, indexing="ij")
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
    d = None
    for f, k in parts:
        v = f(P)
        d = v if d is None else smin(d, v, k)
    vol = d.reshape(n)
    verts, faces, _, _ = marching_cubes(vol, 0.0, spacing=(VOX, VOX, VOX))
    return verts + lo, faces


def paint(verts, base, patches):
    """Colour each vertex: the base colour, then each patch [(sdf, rgb)] in
    order wherever the vertex is inside it."""
    col = np.tile(np.array(base, float), (len(verts), 1))
    for f, rgb in patches:
        # A soft edge a centimetre or so wide, so patches don't look ragged.
        w = np.clip(0.5 - f(verts) / 0.014, 0.0, 1.0)[:, None]
        col = col * (1.0 - w) + np.array(rgb, float) * w
    return col


def srgb_to_linear(x):
    x = np.asarray(x, float)
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def make_object(name, verts, faces, colors, pivot, max_tris):
    """A Blender object from Godot-space geometry, origin at `pivot`."""
    pv = np.array(pivot, float)
    me = bpy.data.meshes.new(name)
    bv = [s.g(*(v - pv)) for v in verts]
    me.from_pydata(bv, [], [tuple(f) for f in faces])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location = s.g(*pv)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if len(me.polygons) > max_tris:
        d = ob.modifiers.new("budget", "DECIMATE")
        d.ratio = max_tris / len(me.polygons)
        c.apply_all(ob)
    c.smooth(ob)
    # Remember each vertex's paint (by nearest original vertex after decimating).
    from mathutils.kdtree import KDTree
    kd = KDTree(len(verts))
    for i, v in enumerate(verts):
        kd.insert(v, i)
    kd.balance()
    paint_v = []
    for v in ob.data.vertices:
        gp = np.array(pv) + np.array([v.co.x, v.co.z, -v.co.y])
        _, idx, _ = kd.find(gp)
        paint_v.append(colors[idx])
    ob["paint"] = [float(x) for x in np.array(paint_v).ravel()]
    return ob


def piece(name, kind, center, size, color):
    """A small separate piece (eye, sparkle, nose): an ellipsoid."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=12, ring_count=8, location=s.g(*center))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[2], size[1])
    c.apply_all(ob)
    c.smooth(ob)
    c.assign(ob, c.material(name, color, 0.3))
    return ob


def tube_piece(name, pts, r, color, res=1):
    ob = s.tube(name, [tuple(p) for p in pts], r, res, along=3)
    c.smooth(ob)
    c.assign(ob, c.material(name, color, 0.5))
    return ob


# --- The animals ----------------------------------------------------------

def body(animal, standing):
    col = COLORS[animal]
    P = [(ellipsoid((0, 0.27, 0), (0.25, 0.33, 0.23)), 0),
         (ellipsoid((0, 0.12, 0.02), (0.27, 0.2, 0.25)), 0.08)]
    patches = [(ellipsoid((0, 0.22, -0.17), (0.18, 0.25, 0.15)), col["belly"])]
    for sx in (-1, 1):
        if not standing:
            a, b = (sx * 0.19, 0.44, -0.04), (sx * 0.25, 0.31, -0.35)
        elif sx < 0:
            a, b = (-0.2, 0.44, 0.0), (-0.3, 0.2, -0.03)
        else:
            a, b = (0.2, 0.44, 0.0), (0.38, 0.7, -0.04)   # waving
        P.append((round_cone(a, b, 0.08, 0.068), 0.06))
        bb = np.array(b) + (np.array(b) - np.array(a)) / np.linalg.norm(np.array(b) - np.array(a)) * 0.04
        P.append((ellipsoid(bb, (0.085, 0.085, 0.085)), 0.03))
        patches.append((ellipsoid(bb, (0.1, 0.1, 0.1)), col["belly"]))
        if standing:
            P.append((round_cone((sx * 0.12, 0.06, 0), (sx * 0.13, -0.34, 0), 0.1, 0.085), 0.06))
            P.append((ellipsoid((sx * 0.13, -0.4, -0.05), (0.11, 0.07, 0.15)), 0.04))
            dark = tuple(np.array(col["body"]) * 0.85)
            patches.append((ellipsoid((sx * 0.13, -0.4, -0.05), (0.13, 0.09, 0.17)), dark))
    lo, hi = (-0.5, -0.5 if standing else -0.12, -0.5), (0.52, 0.82, 0.4)
    v, f = sculpt(P, lo, hi)
    return v, f, paint(v, col["body"], patches)


def head(animal):
    """Head-space parts, translated to driver space at the end."""
    col = COLORS[animal]
    body_c, belly_c = col["body"], col["belly"]
    P = []
    patches = []
    if animal == "frog":
        P.append((ellipsoid((0, 0, 0), (0.4, 0.27, 0.34)), 0))
        for sx in (-1, 1):
            P.append((ellipsoid((sx * 0.17, 0.2, -0.08), (0.14, 0.14, 0.14)), 0.07))
        patches.append((ellipsoid((0, -0.17, -0.1), (0.34, 0.12, 0.28)), belly_c))
    else:
        if animal == "rhino":
            P.append((ellipsoid((0, 0, 0), (0.38, 0.31, 0.35)), 0))
            P.append((ellipsoid((0, -0.12, -0.27), (0.2, 0.14, 0.16)), 0.07))
            P.append((round_cone((0, -0.02, -0.36), (0, 0.2, -0.48), 0.08, 0.015), 0.04))
            patches.append((ellipsoid((0, -0.13, -0.3), (0.2, 0.12, 0.14)), tuple(min(1.0, x * 1.12) for x in body_c)))
            # The horn alone: from just above where it meets the snout.
            patches.append((round_cone((0, 0.02, -0.39), (0, 0.2, -0.48), 0.085, 0.02), IVORY))
        else:
            P.append((ellipsoid((0, 0, 0), (0.36, 0.32, 0.33)), 0))
            L = SNOUT[animal]
            P.append((ellipsoid((0, -0.11, -0.25), (0.14, 0.1, L)), 0.06))
            patches.append((ellipsoid((0, -0.12, -0.25 - L * 0.4), (0.16, 0.12, L)), belly_c))
    for sx in (-1, 1):
        if animal == "fox":
            a, b = (sx * 0.17, 0.2, 0.02), (sx * 0.3, 0.52, 0.04)
            P.append((round_cone(a, b, 0.12, 0.025), 0.07))
            patches.append((ellipsoid((sx * 0.235, 0.36, -0.07), (0.06, 0.11, 0.05)), belly_c))
            patches.append((ellipsoid((sx * 0.29, 0.5, 0.04), (0.06, 0.06, 0.07)), (0.32, 0.18, 0.12)))
        elif animal == "rhino":
            P.append((ellipsoid((sx * 0.24, 0.27, 0.04), (0.07, 0.11, 0.05)), 0.05))
            patches.append((ellipsoid((sx * 0.24, 0.29, -0.01), (0.045, 0.07, 0.04)), EAR_PINK))
        elif animal == "deer":
            P.append((ellipsoid((sx * 0.36, 0.13, 0.03), (0.16, 0.065, 0.045)), 0.05))
            patches.append((ellipsoid((sx * 0.38, 0.13, -0.01), (0.11, 0.045, 0.035)), EAR_PINK))
    v, f = sculpt(P, (-0.58, -0.4, -0.6), (0.58, 0.62, 0.42))
    colors = paint(v, body_c, patches)
    return v + HEAD, f, colors


def snout_z(animal, dy):
    """How far forward the muzzle's surface is, dy below its middle."""
    L = SNOUT[animal]
    return -(0.25 + L * math.sqrt(max(0.0, 1.0 - (dy / 0.1) ** 2)))


def head_pieces(animal):
    """Racer's face: narrowed eyes under heavy lids and a hard brow, one
    sharp glint, a smirk; goggles pushed up on the forehead (the frog, whose
    eyes are on top, wears a headband). In driver space."""
    H = HEAD
    out = []
    dark = (0.07, 0.05, 0.09)
    fur = COLORS[animal]["body"]
    brow_c = tuple(x * 0.72 for x in fur)
    for sx in (-1, 1):
        if animal == "frog":
            e, k = np.array((sx * 0.17, 0.2, -0.205)), 1.2
        else:
            e, k = np.array((sx * 0.135, 0.035, -0.29)), 1.0
        out.append(piece("Eye", "eye", H + e, (0.056 * k, 0.07 * k, 0.04 * k), dark))
        out.append(piece("Sparkle", "s", H + e + np.array((0.02 * sx, 0.012, -0.035)) * k, (0.015 * k,) * 3, (1, 1, 1)))
        # The lid: body-coloured, over the top of the eye, slanting down
        # toward the nose for a focused glare.
        lid = piece("Lid", "lid", H + e + np.array((0.0, 0.045, -0.006)) * k, (0.075 * k, 0.045 * k, 0.05 * k), fur)
        lid.rotation_euler = (0, -sx * 0.38, 0)   # (Blender y is Godot -z: tilts in the face plane)
        c.apply_all(lid)
        out.append(lid)
        brow_in = H + e + np.array((-0.045 * sx, 0.085, -0.03)) * k
        brow_out = H + e + np.array((0.06 * sx, 0.115, -0.005)) * k
        out.append(tube_piece("Brow", [brow_in, brow_out], 0.017 * k, brow_c))
    mouth = (0.18, 0.1, 0.12)
    if animal == "frog":
        pts = []
        for i in range(9):
            x = -0.2 + 0.4 * i / 8
            y = -0.13 - 0.03 * (1 - (x / 0.2) ** 2) + 0.035 * max(0.0, x / 0.2) ** 2   # one corner up
            z = -0.34 * math.sqrt(max(0.0, 1 - (x / 0.4) ** 2 - (y / 0.27) ** 2)) - 0.004
            pts.append(H + np.array((x, y, z)))
        out.append(tube_piece("Mouth", pts, 0.012, mouth))
        # Racing headband round the brow.
        band = []
        for i in range(17):
            a = math.tau * i / 16
            band.append(H + np.array(((0.4 * 0.929 + 0.014) * math.cos(a), 0.1, (0.34 * 0.929 + 0.014) * math.sin(a))))
        out.append(tube_piece("Band", band, 0.026, (0.9, 0.15, 0.12)))
    else:
        if animal == "rhino":
            for sx in (-1, 1):
                out.append(piece("Nose", "n", H + np.array((sx * 0.07, -0.13, -0.418)), (0.024, 0.016, 0.014), (0.12, 0.08, 0.1)))
            mz = -0.41
        else:
            out.append(piece("Nose", "n", H + np.array((0, -0.065, snout_z(animal, 0.045) - 0.002)), (0.055, 0.036, 0.036), (0.12, 0.08, 0.1)))
            mz = snout_z(animal, -0.06) - 0.004
        # A smirk: flat on one side, curling up at the other.
        pts = [H + np.array((x, -0.17 + 0.03 * max(0.0, x / 0.06) ** 2, mz + 0.03 * abs(x))) for x in np.linspace(-0.055, 0.06, 6)]
        out.append(tube_piece("Mouth", pts, 0.011, mouth))
        # Goggles pushed up on the forehead: a strap round the head and two
        # rimmed amber lenses.
        gy = 0.19
        rx, rz = 0.36 * math.sqrt(1 - (gy / 0.32) ** 2) + 0.012, 0.33 * math.sqrt(1 - (gy / 0.32) ** 2) + 0.012
        if animal == "rhino":
            rx, rz = 0.38 * math.sqrt(1 - (gy / 0.31) ** 2) + 0.012, 0.35 * math.sqrt(1 - (gy / 0.31) ** 2) + 0.012
        strap = [H + np.array((rx * math.cos(a), gy, rz * math.sin(a))) for a in np.linspace(0, math.tau, 17)]
        out.append(tube_piece("Strap", strap, 0.022, (0.15, 0.15, 0.18)))
        for sx in (-1, 1):
            ang = -math.pi / 2 + sx * 0.38
            lc = H + np.array((rx * math.cos(ang), gy + 0.01, rz * math.sin(ang))) * np.array((1.0, 1.0, 1.0))
            fwd = np.array((math.cos(ang), 0.25, math.sin(ang)))
            fwd /= np.linalg.norm(fwd)
            out.append(tube_piece("Rim", [lc - fwd * 0.012, lc + fwd * 0.03], 0.062, (0.55, 0.5, 0.45)))
            out.append(tube_piece("Lens", [lc + fwd * 0.025, lc + fwd * 0.036], 0.05, (1.0, 0.62, 0.12)))
    return out


def tail():
    pivot = np.array((0, 0.12, 0.3))
    P = [(round_cone(pivot, pivot + (0, 0.22, 0.34), 0.08, 0.15), 0),
         (ellipsoid(pivot + (0, 0.31, 0.46), (0.13, 0.15, 0.13)), 0.06)]
    v, f = sculpt(P, pivot + (-0.25, -0.15, -0.15), pivot + (0.25, 0.55, 0.7))
    colors = paint(v, COLORS["fox"]["body"], [(ellipsoid(pivot + (0, 0.34, 0.5), (0.17, 0.12, 0.17)), (1.0, 0.97, 0.92))])
    return v, f, colors, pivot


def antler(sx):
    pivot = HEAD + np.array((sx * 0.13, 0.3, 0.04))
    p = pivot
    P = [(round_cone(p, p + (sx * 0.1, 0.34, 0.02), 0.04, 0.026), 0),
         (round_cone(p + (sx * 0.05, 0.15, 0.0), p + (sx * 0.22, 0.27, -0.06), 0.032, 0.02), 0.03),
         (round_cone(p + (sx * 0.03, 0.08, 0.0), p + (sx * -0.06, 0.2, -0.05), 0.028, 0.018), 0.03),
         (round_cone(p + (sx * 0.08, 0.27, 0.01), p + (sx * 0.02, 0.43, 0.0), 0.027, 0.018), 0.03)]
    v, f = sculpt(P, p + (-0.25, -0.08, -0.15), p + (0.25, 0.5, 0.15))
    return v, f, paint(v, ANTLER, []), pivot


def finish_colors(objs):
    """Bake AO, then write paint x occlusion into the exported colours."""
    c.bake_ao(objs, distance=0.12, samples=48, ground=False)
    for ob in objs:
        me = ob.data
        ao = me.color_attributes["AO"]
        paint_v = np.array(ob["paint"]).reshape(-1, 3)
        col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for li, loop in enumerate(me.loops):
            a = ao.data[li].color[0]
            shade = 0.5 + 0.5 * min(1.0, a / 0.75)
            rgb = srgb_to_linear(paint_v[loop.vertex_index]) * shade
            col.data[li].color = (rgb[0], rgb[1], rgb[2], 1.0)
        me.color_attributes.remove(me.color_attributes["AO"])
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = 0
        del ob["paint"]


def build(animal):
    c.reset()
    fused = []
    seated_v, seated_f, seated_c = body(animal, False)
    fused.append(make_object("Body_seated", seated_v, seated_f, seated_c, (0, 0, 0), 1600))
    hv, hf, hc = head(animal)
    fused.append(make_object("Head", hv, hf, hc, HEAD, 2400))
    if animal == "fox":
        tv, tf, tc, tp = tail()
        fused.append(make_object("Tail", tv, tf, tc, tp, 700))
    if animal == "deer":
        for sx, nm in ((-1, "Antler_L"), (1, "Antler_R")):
            av, af, ac, ap = antler(sx)
            fused.append(make_object(nm, av, af, ac, ap, 500))
    pieces = head_pieces(animal)
    finish_colors(fused)
    # The standing pose (lobby), baked on its own with the same head.
    bv, bf, bc = body(animal, True)
    standing = make_object("Body_standing", bv, bf, bc, (0, 0, 0), 1800)
    seated = fused[0]
    seated.hide_render = True
    finish_colors([standing])
    seated.hide_render = False
    return fused + [standing] + pieces


if __name__ == "__main__":
    args = sys.argv[1:]
    animals = [a for a in args if a in COLORS] or list(COLORS)
    out_png = next((a for a in args if a.endswith(".png")), None)
    for animal in animals:
        objs = build(animal)
        path = os.path.abspath(os.path.join(MODELS, "driver_%s.glb" % animal))
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_vertex_color="ACTIVE")
        print("wrote", path, c.tris(objs), "tris")
        if out_png:
            for o in objs:
                if o.name.startswith("Body_standing"):
                    o.hide_render = True
            for o in objs:
                if o.data.color_attributes:
                    m = bpy.data.materials.new("vc_" + o.name)
                    m.use_nodes = True
                    nt = m.node_tree
                    attr = nt.nodes.new("ShaderNodeVertexColor")
                    attr.layer_name = "Col"
                    bsdf = nt.nodes["Principled BSDF"]
                    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
                    bsdf.inputs["Roughness"].default_value = 0.8
                    o.data.materials.clear()
                    o.data.materials.append(m)
            c.sheet(out_png.replace(".png", "_%s.png" % animal), [(10, 200), (8, 160), (15, 270)], target=(0, 0, 0.75), dist=2.0)
