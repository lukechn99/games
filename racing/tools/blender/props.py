"""Roadside props, after the user's reference frames:

  tree_puffy   a round, puffy cartoon tree: clumps of leaves on a curvy trunk
  lamp_post    a curved street lamp on a tapered pole
  guardrail    one 4 m section of steel crash barrier on posts
  windmill     a little countryside windmill (sails are their own object)
  lantern      a stone garden lantern with a glowing window
  coin         a chunky gold coin with a raised rim and a stamped mark
  sand_gun     Frosty Pass's sand blaster: a hopper heaped with sand on a
               chunky body, a flared nozzle forward (-z), a grip below

Each goes to assets/models/<name>.glb. Colours are strong and matte or
satin, never mirror-like, so they don't wash out under a bright sky.

    python3 racing/tools/blender/props.py OUTDIR [name ...] [--no-preview]
"""
import os
import sys
import math
import random
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c
import shapes as s

MODELS = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")


def finish(parts):
    out = []
    for o, m in parts:
        c.assign(o, m)
        c.apply_all(o)
        out.append(o)
    return out


def blob(name, center, radius, squash=1.0, seed=0, detail=2):
    """A lumpy ball: an icosphere nudged about, then smoothed."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=radius, location=s.g(*center))
    o = bpy.context.object
    o.name = name
    rnd = random.Random(seed)
    for v in o.data.vertices:
        v.co *= 1.0 + rnd.uniform(-0.08, 0.08)
        v.co.z *= squash
    c.subsurf(o, 1)
    c.smooth(o)
    return o


def tree_puffy():
    leaf = c.material("Leaf", (0.3, 0.68, 0.18), 0.8)
    leaf2 = c.material("Leaf_light", (0.45, 0.8, 0.22), 0.8)
    bark = c.material("Bark", (0.5, 0.32, 0.18), 0.85)
    parts = [(s.tube("Bark_trunk", [(0, 0, 0), (0.15, 1.2, 0.05), (-0.05, 2.4, 0), (0.1, 3.1, 0.0)], 0.28, 6), bark)]
    parts.append((s.tube("Bark_branch", [(0.0, 2.2, 0), (0.6, 2.8, 0.2), (0.9, 3.2, 0.25)], 0.12, 4), bark))
    parts.append((s.tube("Bark_branch", [(0.0, 2.5, 0), (-0.6, 3.0, -0.3), (-0.9, 3.3, -0.35)], 0.11, 4), bark))
    # Flared roots.
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        parts.append((s.tube("Bark_root", [(0, 0.5, 0), (math.cos(a) * 0.45, 0.05, math.sin(a) * 0.45)], 0.12, 3), bark))
    clumps = [((0, 4.2, 0), 1.7, 0), ((1.2, 3.6, 0.3), 1.2, 1), ((-1.2, 3.7, -0.3), 1.25, 2), ((0.3, 3.5, 1.1), 1.1, 3),
              ((-0.3, 3.6, -1.1), 1.15, 4), ((0.5, 5.2, -0.2), 1.1, 5), ((-0.6, 5.0, 0.4), 1.0, 6)]
    for (p, r, sd) in clumps:
        parts.append((blob("Leaf_clump", p, r, 0.85, sd), leaf if sd % 3 else leaf2))
    return finish(parts), (0, 0, 3.0), 13.0


def lamp_post():
    paint = c.material("Post", (0.2, 0.24, 0.3), 0.45)
    glass = c.material("Light", (1.0, 0.92, 0.65), 0.3, emit=(1.0, 0.9, 0.6), emit_strength=2.0)
    parts = [(s.cylinder("Post_base", (0, 0.25, 0), 0.22, 0.5, "y", 16, 0.04), paint)]
    parts.append((s.tube("Post_pole", [(0, 0.4, 0), (0, 4.5, 0), (0.1, 5.6, 0), (0.6, 6.1, 0), (1.3, 6.15, 0)], 0.08, 5), paint))
    head = s.loft("Post_head", [(0.0, 0.18, 5.85, 6.25, 3.0), (0.0, 0.18, 5.85, 6.25, 3.0)], around=12)
    head.data.vertices.foreach_set  # (placeholder for clarity)
    bpy.data.objects.remove(head, do_unlink=True)
    hood = s.box("Post_hood", (1.45, 6.1, 0), (0.7, 0.16, 0.36), 0.06, 3)
    parts.append((hood, paint))
    lens = s.box("Light_lens", (1.45, 5.99, 0), (0.6, 0.06, 0.28), 0.03, 2)
    parts.append((lens, glass))
    return finish(parts), (0.5, 0, 3.4), 12.0


def guardrail():
    steel = c.material("Rail", (0.72, 0.74, 0.78), 0.35, metal=0.3)
    post = c.material("Rail_post", (0.5, 0.52, 0.56), 0.5)
    stripe = c.material("Rail_stripe", (0.95, 0.75, 0.1), 0.5)
    parts = []
    # A W-beam: two rounded ridges along the rail.
    for k, y in enumerate((0.62, 0.78)):
        b = s.loft("Rail_beam", [(-2.0, 0.05, y - 0.08, y + 0.08, 2.0), (2.0, 0.05, y - 0.08, y + 0.08, 2.0)], around=16)
        parts.append((b, steel))
    parts.append((s.box("Rail_back", (0.0, 0.7, 0.04), (0.03, 0.3, 4.0), 0.005, 1), steel))
    for z in (-1.8, 0.0, 1.8):
        parts.append((s.box("Rail_post", (0.0, 0.42, z + 0.0), (0.1, 0.84, 0.1), 0.015, 2), post))
        parts.append((s.box("Rail_post", (0.08, 0.7, z), (0.12, 0.22, 0.16), 0.02, 2), post))
    # Reflector stripes.
    for z in (-1.0, 1.0):
        parts.append((s.box("Rail_stripe", (-0.06, 0.7, z), (0.02, 0.2, 0.3), 0.004, 1), stripe))
    return finish(parts), (0, 0, 0.6), 5.5


def _stand_up(o):
    """Lathes spin round Godot x; turn one to stand on its end (x -> up)."""
    o.rotation_euler = (0, math.radians(-90), 0)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    c.smooth(o)
    return o


def windmill():
    wall = c.material("Wall", (0.96, 0.93, 0.85), 0.8)
    roof = c.material("Roof", (0.82, 0.24, 0.16), 0.7)
    wood = c.material("Wood", (0.55, 0.36, 0.2), 0.8)
    sail = c.material("Sail", (0.98, 0.97, 0.94), 0.8)
    trim = c.material("Trim", (0.2, 0.42, 0.62), 0.6)
    parts = [(_stand_up(s.lathe("Wall_tower", [(0.0, 1.6), (4.5, 1.15), (4.5, 0.0)], segs=24)), wall)]
    parts.append((_stand_up(s.lathe("Roof_cap", [(4.35, 1.4), (5.3, 0.95), (6.2, 0.0)], segs=24)), roof))
    parts.append((s.box("Trim_door", (0, 0.8, -1.52), (0.8, 1.5, 0.12), 0.05, 3), trim))
    parts.append((s.box("Trim_window", (0, 2.6, -1.42), (0.55, 0.65, 0.12), 0.04, 2), trim))
    parts.append((s.box("Trim_window", (0, 3.7, -1.3), (0.5, 0.55, 0.12), 0.04, 2), trim))
    parts.append((s.cylinder("Wood_axle", (0, 5.0, -1.3), 0.16, 0.7, "z", 12, 0.03), wood))
    body = finish(parts)
    # Sails: four lattice blades on a hub, joined into one object ("Sails")
    # so the game can spin it. Each is built pointing up from the hub, then
    # turned about the axle.
    hub = s.g(0, 5.0, -1.7)
    sail_parts = []
    for k in range(4):
        ang = math.tau * k / 4 + 0.35
        for (name, size, off, mat) in (("Sails_arm", (0.14, 3.4, 0.1), (0.0, 1.7, 0.0), wood),
                                        ("Sails_blade", (0.75, 2.5, 0.04), (0.45, 2.05, 0.03), sail),
                                        ("Sails_slat", (0.8, 0.06, 0.06), (0.45, 1.0, -0.02), wood),
                                        ("Sails_slat", (0.8, 0.06, 0.06), (0.45, 2.0, -0.02), wood),
                                        ("Sails_slat", (0.8, 0.06, 0.06), (0.45, 3.0, -0.02), wood)):
            bpy.ops.mesh.primitive_cube_add(size=1.0)
            o = bpy.context.object
            o.name = name
            for v in o.data.vertices:
                v.co.x = v.co.x * size[0] + off[0]
                v.co.z = v.co.z * size[1] + off[1]
                v.co.y = v.co.y * size[2] - off[2]
            o.location = hub
            o.rotation_euler = (0, ang, 0)
            sail_parts.append((o, mat))
    sail_parts.append((s.cylinder("Sails_hub", (0, 5.0, -1.72), 0.32, 0.22, "z", 16, 0.05), roof))
    sail_objs = finish(sail_parts)
    bpy.ops.object.select_all(action="DESELECT")
    for o in sail_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = sail_objs[-1]
    bpy.ops.object.join()
    sails = bpy.context.view_layer.objects.active
    sails.name = "Sails"
    return body + [sails], (0, 0, 3.6), 16.0


def lantern():
    stone = c.material("Stone", (0.66, 0.64, 0.6), 0.9)
    stone2 = c.material("Stone_dark", (0.5, 0.49, 0.47), 0.9)
    glow = c.material("Glow", (1.0, 0.75, 0.3), 0.5, emit=(1.0, 0.7, 0.3), emit_strength=3.0)
    parts = [(s.box("Stone_base", (0, 0.15, 0), (0.9, 0.3, 0.9), 0.05, 3), stone2)]
    parts.append((s.cylinder("Stone_post", (0, 0.75, 0), 0.18, 0.9, "y", 12, 0.03), stone))
    parts.append((s.box("Stone_shelf", (0, 1.25, 0), (0.75, 0.14, 0.75), 0.04, 3), stone2))
    parts.append((s.box("Stone_box", (0, 1.58, 0), (0.55, 0.52, 0.55), 0.04, 3), stone))
    for (x, z, w, d) in ((0, -0.28, 0.3, 0.02), (0, 0.28, 0.3, 0.02), (-0.28, 0, 0.02, 0.3), (0.28, 0, 0.02, 0.3)):
        parts.append((s.box("Glow_window", (x, 1.6, z), (w, 0.28, d), 0.0, 1), glow))
    roof = s.loft("Stone_roof", [(-0.6, 0.6, 1.84, 1.94, 6.0), (0.0, 0.62, 1.84, 2.16, 6.0), (0.6, 0.6, 1.84, 1.94, 6.0)], around=16)
    c.subsurf(roof, 1)
    c.smooth(roof)
    parts.append((roof, stone2))
    parts.append((blob("Stone_knob", (0, 2.1, 0), 0.12, 1.0, 1, 1), stone))
    return finish(parts), (0, 0, 1.1), 4.0


def coin():
    gold = c.material("Gold", (1.0, 0.76, 0.1), 0.3, metal=0.5)
    gold_dark = c.material("Gold_dark", (0.9, 0.58, 0.05), 0.35, metal=0.5)
    body = s.lathe("Gold_coin", [(-0.08, 0.0), (-0.08, 0.36), (-0.1, 0.42), (-0.06, 0.48), (0.06, 0.48), (0.1, 0.42), (0.08, 0.36), (0.08, 0.0)], segs=40)
    c.smooth(body)
    parts = [(body, gold)]
    # A raised star on each face.
    import bmesh
    for sx in (-1, 1):
        bm = bmesh.new()
        pts = []
        for k in range(10):
            a = math.tau * k / 10 + math.pi / 2
            r = 0.27 if k % 2 == 0 else 0.12
            pts.append(bm.verts.new(s.g(sx * 0.07, math.sin(a) * r, math.cos(a) * r)))
        face = bm.faces.new(pts)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, verts=moved, vec=s.g(sx * 0.05, 0, 0))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        star = s.mesh_object("Gold_star", bm)
        m = star.modifiers.new("bevel", "BEVEL")
        m.width = 0.012
        m.segments = 2
        parts.append((star, gold_dark))
    for o, _ in parts:
        o.location.z += 0.0
    return finish(parts), (0, 0, 0.6), 2.2



def sand_gun():
    """Built along +x (lathe axis), then turned so the nozzle points -z."""
    body_c = c.material("Blaster", (1.0, 0.53, 0.24), 0.45)          # the approved frost orange
    trim = c.material("Blaster_trim", (0.16, 0.2, 0.3), 0.55)
    steel = c.material("Blaster_steel", (0.72, 0.76, 0.8), 0.35, metal=0.6)
    sand = c.material("Sand", (0.93, 0.8, 0.52), 0.9)
    parts = []
    # Barrel, flaring into a wide nozzle at the front.
    barrel = s.lathe("Barrel", [(0.12, 0.0), (0.12, 0.08), (0.36, 0.075), (0.44, 0.09), (0.54, 0.16), (0.57, 0.17), (0.57, 0.13), (0.5, 0.08)], segs=28)
    c.smooth(barrel)
    parts.append((barrel, steel))
    ring = s.lathe("Ring", [(0.26, 0.0), (0.26, 0.1), (0.32, 0.1), (0.32, 0.0)], segs=28)
    parts.append((ring, trim))
    # The body: a rounded block behind the barrel.
    body = s.box("Body", (-0.08, 0.0, 0.0), (0.48, 0.32, 0.3), bevel=0.06, seg=3)
    parts.append((body, body_c))
    stripe = s.box("Stripe", (-0.08, 0.0, 0.0), (0.12, 0.33, 0.31), bevel=0.02, seg=2)
    parts.append((stripe, trim))
    # Grip, raked back under the body.
    grip = s.box("Grip", (-0.17, -0.2, 0.0), (0.1, 0.24, 0.1), bevel=0.035, seg=2)
    grip.rotation_euler = (0, 0, math.radians(18))
    parts.append((grip, trim))
    # Hopper: a funnel on top, heaped with sand.
    hop = s.lathe("Hopper", [(0.0, 0.07), (0.05, 0.09), (0.16, 0.16), (0.2, 0.17), (0.2, 0.0)], segs=24)
    hop.rotation_euler = (0, math.radians(-90), 0)    # funnel axis up (Godot y)
    hop.location = s.g(-0.1, 0.13, 0.0)
    c.smooth(hop)
    parts.append((hop, body_c))
    heap = blob("Heap", (-0.1, 0.35, 0.0), 0.15, squash=0.5, seed=3, detail=2)
    parts.append((heap, sand))
    objs = finish(parts)
    for o in objs:
        o.select_set(True)
    return objs, (0, 0, 0.1), 2.0

def _pine(tiers, snowy=True):
    """A pine of stacked, slightly drooping tiers, each with a snow cap that
    hangs over its edge in a scalloped lip."""
    needles = c.material("Needles", (0.12, 0.38, 0.26), 0.85)
    needles2 = c.material("Needles_dark", (0.09, 0.3, 0.22), 0.85)
    snow = c.material("Snow", (0.95, 0.97, 1.0), 0.7)
    bark = c.material("Bark", (0.42, 0.27, 0.16), 0.85)
    parts = [(s.cylinder("Bark_trunk", (0, 0.7, 0), 0.26, 1.4, "y", 12, 0.03), bark)]
    for i, (h, R, H) in enumerate(tiers):
        tier = s.lathe("Needles_tier", [(h - 0.15, 0.25), (h, R), (h + 0.18, R * 0.9), (h + H * 0.6, R * 0.38), (h + H, 0.04)], segs=20,
                       tread=lambda k, j, R=R: 1.0 + (0.07 * math.sin(k * 2.6) if j == 1 else 0.0))
        parts.append((_stand_up(tier), needles if i % 2 == 0 else needles2))
        if not snowy:
            continue
        # The snow: the top of the tier, a little proud of it, scalloped
        # where it hangs over.
        cap = s.lathe("Snow_cap", [(h + H * 0.45, R * 0.6), (h + H * 0.5, R * 0.57), (h + H * 0.75, R * 0.3), (h + H + 0.07, 0.03)], segs=20,
                      tread=lambda k, j: 1.0 + (0.1 * max(0.0, math.sin(k * 3.14159 * 6 / 20)) if j == 0 else 0.0))
        parts.append((_stand_up(cap), snow))
    return finish(parts)


def snowpine_tall():
    return _pine([(1.0, 2.0, 2.0), (2.5, 1.6, 1.9), (3.9, 1.2, 1.7), (5.1, 0.8, 1.7)]), (0, 0, 3.4), 13.0


def snowpine_round():
    return _pine([(0.9, 2.5, 2.1), (2.3, 2.0, 1.9), (3.6, 1.4, 1.8)]), (0, 0, 2.8), 12.0


def pine_tall():
    return _pine([(1.0, 2.0, 2.0), (2.5, 1.6, 1.9), (3.9, 1.2, 1.7), (5.1, 0.8, 1.7)], snowy=False), (0, 0, 3.4), 13.0


def tree_round():
    """A lollipop tree: a straight trunk and one big soft crown."""
    leaf = c.material("Leaf", (0.36, 0.72, 0.22), 0.8)
    leaf2 = c.material("Leaf_light", (0.5, 0.82, 0.26), 0.8)
    bark = c.material("Bark", (0.5, 0.32, 0.18), 0.85)
    parts = [(s.tube("Bark_trunk", [(0, 0, 0), (0.05, 1.5, 0.0), (0.0, 2.8, 0)], 0.34, 6), bark)]
    parts.append((blob("Leaf_crown", (0, 3.9, 0), 1.75, 0.95, 11), leaf))
    parts.append((blob("Leaf_top", (0.35, 4.8, -0.2), 0.9, 0.9, 12), leaf2))
    return finish(parts), (0, 0, 2.8), 11.0


def bush():
    """Three soft clumps."""
    leaf = c.material("Leaf", (0.3, 0.64, 0.2), 0.8)
    leaf2 = c.material("Leaf_light", (0.42, 0.74, 0.24), 0.8)
    parts = [(blob("Leaf_a", (0, 0.45, 0), 0.62, 0.8, 21), leaf),
             (blob("Leaf_b", (0.55, 0.36, 0.2), 0.48, 0.8, 22), leaf2),
             (blob("Leaf_c", (-0.5, 0.34, -0.15), 0.45, 0.8, 23), leaf)]
    return finish(parts), (0, 0, 0.5), 3.5


def snowman():
    snow = c.material("Snow", (0.95, 0.97, 1.0), 0.7)
    coal = c.material("Coal", (0.08, 0.08, 0.1), 0.6)
    carrot = c.material("Carrot", (1.0, 0.48, 0.1), 0.6)
    scarf = c.material("Scarf", (0.85, 0.12, 0.12), 0.8)
    stick = c.material("Stick", (0.4, 0.26, 0.15), 0.9)
    parts = [(blob("Snow_base", (0, 0.85, 0), 0.95, 0.92, 1), snow),
             (blob("Snow_mid", (0, 2.05, 0), 0.68, 0.95, 2), snow),
             (blob("Snow_head", (0, 2.95, 0), 0.48, 1.0, 3), snow)]
    nose = s.lathe("Carrot_nose", [(0.0, 0.08), (0.4, 0.01)], segs=10)
    nose.rotation_euler = (0, 0, math.radians(90))   # lathe x (Godot) -> point forward (-z Godot is +y Blender)
    bpy.context.view_layer.objects.active = nose
    bpy.ops.object.select_all(action="DESELECT")
    nose.select_set(True)
    bpy.ops.object.transform_apply(rotation=True)
    nose.location = s.g(0, 2.93, -0.44)
    parts.append((nose, carrot))
    for sx in (-1, 1):
        parts.append((s.cylinder("Coal_eye", (sx * 0.16, 3.08, -0.41), 0.06, 0.05, "z", 10, 0.01), coal))
        parts.append((s.tube("Stick_arm", [(sx * 0.6, 2.15, 0), (sx * 1.15, 2.55, -0.05), (sx * 1.35, 2.85, -0.1)], 0.045, 2), stick))
    for k in range(3):
        parts.append((s.cylinder("Coal_button", (0, 1.8 + k * 0.26, -0.66 + abs(k - 1) * 0.04), 0.06, 0.05, "z", 10, 0.01), coal))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.46, minor_radius=0.1, location=s.g(0, 2.55, 0))
    ring = bpy.context.object
    ring.name = "Scarf_wrap"
    parts.append((ring, scarf))
    parts.append((s.box("Scarf_tail", (0.28, 2.3, -0.42), (0.18, 0.5, 0.06), 0.03, 2), scarf))
    return finish(parts), (0, 0, 1.7), 8.0


BUILDERS = {"sand_gun": sand_gun, "tree_puffy": tree_puffy, "lamp_post": lamp_post, "guardrail": guardrail,
            "windmill": windmill, "lantern": lantern, "coin": coin,
            "snowpine_tall": snowpine_tall, "pine_tall": pine_tall, "tree_round": tree_round, "bush": bush, "snowpine_round": snowpine_round, "snowman": snowman}

TREE_BUDGETS = {"tree_puffy": 900, "pine_tall": 750, "tree_round": 750,
                "snowpine_tall": 750, "snowpine_round": 650}


def pack_tree(obj, budget):
    """One opaque surface: bake the existing material colours into vertices.

    Decimate while material regions are still distinct, then paint corners so
    bark, needles and snow keep their own colours without extra draw calls.
    """
    total = c.tris([obj])
    if total > budget:
        mod = obj.modifiers.new("tree_budget", "DECIMATE")
        mod.ratio = (budget - 8) / total
        c.apply_all(obj)
    assert c.tris([obj]) <= budget, f"tree exceeds triangle budget: {obj.name}"
    mesh = obj.data
    tint = mesh.color_attributes.new("Tint", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = tint
    mesh.color_attributes.render_color_index = mesh.color_attributes.find("Tint")
    for poly in mesh.polygons:
        mat = mesh.materials[poly.material_index]
        color = mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
        for loop in poly.loop_indices:
            tint.data[loop].color = color
    mesh.materials.clear()
    mesh.materials.append(c.material("TreeVertex", (1, 1, 1), 1.0))
    for poly in mesh.polygons:
        poly.material_index = 0
    print("tree packed", obj.name, total, "->", c.tris([obj]), "triangles, one material")

if __name__ == "__main__":
    outdir = sys.argv[1]
    names = [n for n in sys.argv[2:] if n != "--no-preview"] or list(BUILDERS)
    for name in names:
        c.reset()
        objs, target, dist = BUILDERS[name]()
        # One mesh per prop (one surface per material), so the game can draw
        # hundreds of copies cheaply. The windmill's sails stay separate to spin.
        keep = [o for o in objs if o.name == "Sails"]
        rest = [o for o in objs if o.name != "Sails"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in rest:
            o.select_set(True)
        bpy.context.view_layer.objects.active = rest[0]
        bpy.ops.object.join()
        rest[0].name = name
        if name == "sand_gun":
            rest[0].rotation_euler.z += math.radians(90)   # +x (nozzle) -> Godot -z
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        objs = [rest[0]] + keep
        if name in TREE_BUDGETS:
            pack_tree(rest[0], TREE_BUDGETS[name])
        c.export(os.path.abspath(os.path.join(MODELS, name + ".glb")), objs,
                 max_tris=None if name in TREE_BUDGETS else 1500,
                 vertex_colors=name in TREE_BUDGETS)
        if name == "coin":
            for o in objs:
                o.location.z += 0.6
        if "--no-preview" not in sys.argv:
            c.sheet(os.path.join(outdir, name + ".png"), [(12, 30), (25, 150)], target=target, dist=dist, size=(480, 420), samples=32)
        print("done", name)
