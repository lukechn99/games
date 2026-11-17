"""Roadside props, after the user's reference frames:

  tree_puffy   a round, puffy cartoon tree: clumps of leaves on a curvy trunk
  lamp_post    a curved street lamp on a tapered pole
  guardrail    one 4 m section of steel crash barrier on posts
  windmill     a little countryside windmill (sails are their own object)
  lantern      a stone garden lantern with a glowing window
  coin         a chunky gold coin with a raised rim and a stamped mark
  honey        a honey puddle: an irregular glossy pool with a rounded,
               raised rim, a domed middle and a few bubbles (2 m across)
  tumbleweed   a tangled ball of dry twigs (1.4 m across)
  snowball     a lumpy ball of packed snow with clumps stuck on (2 m across;
               the game scales it as it grows)
  cargo_pod    Series 2: a chunky rounded cargo container with ribs, a
               colour band and feet (3.4 x 2.4 x 2.4 m)
  reactor      Starliner Run: a reactor column, a glowing core ("Glow"
               material) held in three struts between a base and a cap (14 m)
  dish         Starliner Run: a hull antenna dish on a stubby mast (4 m)
  big_wheel    Funfair Frenzy: the big wheel's turning part, hub at the
               origin, axle along z: rim, spokes, twelve gondolas (60 m)
  big_wheel_stand  ... and the two A-frames and axle it turns on
  carousel     Funfair Frenzy: a striped canopy over poles and horses on a
               round deck (18 m across); the game turns it
  stall        Funfair Frenzy: a midway stall under a striped awning
  balloons     Funfair Frenzy: a bunch of balloons on strings
  bumper_car   Funfair Frenzy: a round bumper car with a rubber skirt
  train_car    Windy City Circuit: one car of the elevated train (14 m)
  city_car     Windy City Circuit: a parked car, rounded and chunky (4.4 m)
  street_lamp  Windy City Circuit: a lamp post with a glowing head (7 m)
  fan, palm, big_top, coaster_car, hot_air_balloon, umbrella, boat,
  tree_planter, traffic_light, water_tank, box_truck, shuttle, asteroid,
  antenna      Series 2 trackside dressing (design doc 8.5), each packed to
               one vertex-coloured surface so a kind is one draw call
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





# --- Series 2 (design doc 8.4): rounded and chunky, bevels everywhere --------

def cargo_pod():
    shell = c.material("Pod", (0.9, 0.925, 0.96), 0.5)
    band = c.material("Pod_band", (1.0, 0.7, 0.12), 0.45)
    dark = c.material("Pod_dark", (0.2, 0.24, 0.32), 0.6)
    parts = [(s.box("Pod", (0, 1.3, 0), (3.4, 2.3, 2.3), bevel=0.32, seg=4), shell)]
    parts.append((s.box("Band", (0, 1.3, 0), (0.7, 2.36, 2.36), bevel=0.3, seg=4), band))
    for x in (-1.25, 1.25):
        parts.append((s.box("Rib", (x, 1.3, 0), (0.16, 2.42, 2.42), bevel=0.07, seg=2), dark))
    for x in (-1.2, 1.2):
        for z in (-0.8, 0.8):
            parts.append((s.box("Foot", (x, 0.1, z), (0.5, 0.24, 0.5), bevel=0.08, seg=2), dark))
    parts.append((s.box("Hatch", (1.72, 1.3, 0), (0.08, 1.3, 1.3), bevel=0.03, seg=2), dark))
    return finish(parts), (0, 0, 1.2), 7.0


def reactor():
    metal = c.material("Reactor", (0.36, 0.4, 0.48), 0.45, metal=0.3)
    trim = c.material("Reactor_trim", (0.9, 0.925, 0.96), 0.5)
    core = c.material("Glow", (0.21, 0.88, 1.0), 0.3)
    parts = []
    base = s.lathe("Base", [(0.0, 0.0), (0.0, 2.6), (0.5, 2.6), (1.1, 2.0), (1.5, 1.9), (1.5, 0.0)], segs=28)
    cap = s.lathe("Cap", [(12.4, 0.0), (12.4, 1.9), (12.9, 2.0), (13.5, 2.6), (14.0, 2.6), (14.0, 0.0)], segs=28)
    glow = s.lathe("Core", [(1.4, 0.0), (1.4, 1.15), (4.0, 1.4), (7.0, 1.5), (10.0, 1.4), (12.5, 1.15), (12.5, 0.0)], segs=24)
    for o, m in ((base, metal), (cap, metal), (glow, core)):
        o.rotation_euler = (0, math.radians(-90), 0)    # lathe axis (x) up
        c.smooth(o)
        parts.append((o, m))
    for i in range(3):
        a = math.tau * i / 3
        x, z = math.cos(a) * 2.1, math.sin(a) * 2.1
        parts.append((s.tube("Strut", [(x, 1.4, z), (x * 1.12, 7.0, z * 1.12), (x, 12.6, z)], 0.2, 3, along=6), trim))
    for y in (4.2, 9.8):
        ring = s.lathe("Ring", [(y - 0.18, 2.1), (y - 0.18, 2.45), (y + 0.18, 2.45), (y + 0.18, 2.1)], segs=24, cap=False)
        ring.rotation_euler = (0, math.radians(-90), 0)
        parts.append((ring, trim))
    return finish(parts), (0, 0, 7.0), 24.0


def dish():
    white = c.material("Dish", (0.9, 0.925, 0.96), 0.5)
    dark = c.material("Dish_dark", (0.2, 0.24, 0.32), 0.6)
    lamp = c.material("Glow", (1.0, 0.7, 0.12), 0.3)
    parts = [(s.cylinder("Mast", (0, 1.0, 0), 0.22, 2.0, axis="y", verts=14, bevel=0.05), dark)]
    parts.append((s.box("Foot", (0, 0.15, 0), (1.2, 0.3, 1.2), bevel=0.1, seg=2), dark))
    bowl = s.lathe("Bowl", [(0.0, 0.0), (0.05, 0.6), (0.3, 1.3), (0.75, 1.75), (0.82, 1.78), (0.4, 1.3), (0.16, 0.6), (0.12, 0.0)], segs=28)
    bowl.rotation_euler = (0, math.radians(-55), 0)     # tipped up at the sky
    bowl.location = s.g(0, 2.1, 0)
    c.smooth(bowl)
    parts.append((bowl, white))
    parts.append((blob("Tip", (0.75, 3.15, 0), 0.16, seed=2, detail=1), lamp))
    parts.append((s.tube("Feed", [(0.1, 2.2, 0), (0.75, 3.1, 0)], 0.05, 2, along=3), dark))
    return finish(parts), (0, 0, 2.0), 8.0


RED = (0.91, 0.2, 0.29)
SUN = (1.0, 0.78, 0.16)
TEAL = (0.09, 0.65, 0.63)
CREAM = (1.0, 0.95, 0.85)
PINK = (1.0, 0.5, 0.71)


def big_wheel():
    rim_m = c.material("Wheel", CREAM, 0.5)
    spoke_m = c.material("Wheel_spoke", TEAL, 0.5)
    hub_m = c.material("Wheel_hub", RED, 0.45)
    pods = [c.material("Pod_%d" % i, col, 0.45) for i, col in enumerate((RED, SUN, TEAL, PINK))]
    R = 28.0
    parts = []
    for zoff in (-1.6, 1.6):
        ring = [(math.cos(a) * R, math.sin(a) * R, zoff) for a in [math.tau * i / 36 for i in range(37)]]
        parts.append((s.tube("Rim", ring, 0.55, 3, along=3), rim_m))
    for i in range(12):
        a = math.tau * i / 12
        x, y = math.cos(a), math.sin(a)
        parts.append((s.tube("Spoke", [(x * 2.0, y * 2.0, 0), (x * R, y * R, 0)], 0.3, 2, along=2), spoke_m))
        parts.append((s.box("Gondola", (x * (R + 0.2), y * (R + 0.2) - 2.2, 0), (3.2, 2.6, 2.8), bevel=0.6, seg=3), pods[i % 4]))
        parts.append((s.box("Roof", (x * (R + 0.2), y * (R + 0.2) - 0.7, 0), (3.5, 0.5, 3.1), bevel=0.2, seg=2), rim_m))
    parts.append((s.cylinder("Hub", (0, 0, 0), 3.0, 4.4, axis="z", verts=20, bevel=0.5), hub_m))
    return finish(parts), (0, 0, 0), 90.0


def big_wheel_stand():
    leg_m = c.material("Stand", CREAM, 0.5)
    base_m = c.material("Stand_base", TEAL, 0.5)
    parts = []
    H = 33.0
    for z in (-3.6, 3.6):
        for x in (-13.0, 13.0):
            parts.append((s.tube("Leg", [(x, 0.0, z * 1.5), (0.0, H, z)], 0.75, 2, along=2), leg_m))
            parts.append((s.box("Foot", (x, 0.6, z * 1.5), (4.0, 1.2, 4.0), bevel=0.4, seg=2), base_m))
    parts.append((s.cylinder("Axle", (0, H, 0), 1.3, 9.0, axis="z", verts=16, bevel=0.3), base_m))
    return finish(parts), (0, 0, 16.0), 80.0


def carousel():
    deck_m = c.material("Deck", CREAM, 0.5)
    red = c.material("Canopy_red", RED, 0.45)
    sun = c.material("Canopy_sun", SUN, 0.45)
    pole_m = c.material("Pole", SUN, 0.35, metal=0.5)
    horse_ms = [c.material("Horse_%d" % i, col, 0.45) for i, col in enumerate((PINK, TEAL, CREAM, RED))]
    parts = []
    deck = s.lathe("Deck", [(0.0, 0.0), (0.0, 9.0), (0.5, 9.0), (0.7, 8.6), (0.7, 0.0)], segs=36)
    deck.rotation_euler = (0, math.radians(-90), 0)
    parts.append((deck, deck_m))
    # The canopy: a shallow cone in alternating slices, with a scalloped edge.
    n = 12
    for i in range(n):
        a0, a1 = math.tau * i / n, math.tau * (i + 1) / n
        import bmesh
        me = bpy.data.meshes.new("Slice")
        bm = bmesh.new()
        top = bm.verts.new(s.g(0, 8.4, 0))
        e0 = bm.verts.new(s.g(math.cos(a0) * 9.6, 5.6, math.sin(a0) * 9.6))
        e1 = bm.verts.new(s.g(math.cos(a1) * 9.6, 5.6, math.sin(a1) * 9.6))
        am = (a0 + a1) / 2
        lip = bm.verts.new(s.g(math.cos(am) * 9.9, 4.9, math.sin(am) * 9.9))
        bm.faces.new((top, e1, e0))
        bm.faces.new((e0, e1, lip))
        bm.normal_update()
        if sum(f.normal.z for f in bm.faces) < 0:
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new("Slice", me)
        bpy.context.collection.objects.link(o)
        parts.append((o, red if i % 2 == 0 else sun))
    parts.append((s.cylinder("Mast", (0, 4.4, 0), 0.9, 8.0, axis="y", verts=14, bevel=0.2), red))
    parts.append((blob("Finial", (0, 8.9, 0), 0.7, seed=1, detail=2), pole_m))
    for i in range(8):
        a = math.tau * i / 8
        x, z = math.cos(a) * 6.6, math.sin(a) * 6.6
        parts.append((s.cylinder("Pole", (x, 3.2, z), 0.12, 5.2, axis="y", verts=8), pole_m))
        up = 1.9 + 0.5 * (i % 2)
        parts.append((s.box("Horse", (x, up, z), (0.8, 1.0, 2.0), bevel=0.35, seg=3), horse_ms[i % 4]))
        parts.append((s.box("Head", (x - math.sin(a) * 0.9, up + 0.75, z + math.cos(a) * 0.9), (0.55, 0.9, 0.6), bevel=0.22, seg=2), horse_ms[i % 4]))
    return finish(parts), (0, 0, 4.0), 30.0


def stall():
    wood = c.material("Stall", CREAM, 0.6)
    red = c.material("Awning_red", RED, 0.5)
    white = c.material("Awning_white", (1, 1, 1), 0.5)
    teal = c.material("Stall_trim", TEAL, 0.5)
    parts = [(s.box("Counter", (0, 0.7, 0), (5.0, 1.4, 2.6), bevel=0.2, seg=2), wood)]
    parts.append((s.box("Back", (0, 2.4, -1.1), (5.0, 2.2, 0.3), bevel=0.1, seg=2), teal))
    for x in (-2.35, 2.35):
        parts.append((s.cylinder("Post", (x, 2.2, 1.1), 0.12, 3.0, axis="y", verts=8), teal))
    for i in range(6):
        x = -2.5 + 5.0 * (i + 0.5) / 6
        slat = s.box("Slat", (x, 3.9, 0.2), (0.84, 0.16, 3.4), bevel=0.06, seg=2)
        slat.rotation_euler = (math.radians(-14), 0, 0)
        parts.append((slat, red if i % 2 == 0 else white))
    return finish(parts), (0, 0, 2.0), 11.0


def balloons():
    cols = (RED, SUN, TEAL, PINK, CREAM)
    string = c.material("String", (0.3, 0.3, 0.35), 0.8)
    parts = []
    rnd = random.Random(8)
    for i in range(6):
        a = math.tau * i / 6 + rnd.uniform(-0.3, 0.3)
        r = rnd.uniform(0.5, 1.0)
        top = (math.cos(a) * r, rnd.uniform(4.6, 6.2), math.sin(a) * r)
        b = blob("Balloon", top, 0.62, squash=1.18, seed=i, detail=2)
        parts.append((b, c.material("Balloon_%d" % i, cols[i % 5], 0.3)))
        parts.append((s.tube("String", [(0, 0.0, 0), (top[0] * 0.5, top[1] * 0.5, top[2] * 0.5), (top[0], top[1] - 0.7, top[2])], 0.025, 2, along=3), string))
    parts.append((s.box("Weight", (0, 0.2, 0), (0.6, 0.4, 0.6), bevel=0.12, seg=2), string))
    return finish(parts), (0, 0, 3.4), 12.0


def bumper_car():
    body = c.material("Car", RED, 0.35)
    skirt = c.material("Skirt", (0.14, 0.15, 0.2), 0.7)
    seat = c.material("Seat", CREAM, 0.5)
    pole = c.material("Car_pole", SUN, 0.4, metal=0.4)
    parts = []
    sk = s.lathe("Skirt", [(0.0, 0.0), (0.0, 1.5), (0.35, 1.62), (0.6, 1.5), (0.6, 0.0)], segs=28)
    sk.rotation_euler = (0, math.radians(-90), 0)
    sk.scale = (1.0, 1.25, 1.0)      # longer than it is wide
    c.smooth(sk)
    parts.append((sk, skirt))
    parts.append((s.box("Body", (0, 0.85, 0), (2.3, 0.9, 2.9), bevel=0.42, seg=4), body))
    parts.append((s.box("Seat", (0, 1.25, 0.5), (1.5, 0.7, 0.9), bevel=0.25, seg=3), seat))
    parts.append((s.cylinder("Pole", (0, 2.6, 1.2), 0.07, 3.4, axis="y", verts=8), pole))
    parts.append((blob("Lamp", (0, 1.25, -1.2), 0.22, seed=3, detail=1), c.material("Glow", SUN, 0.3)))
    return finish(parts), (0, 0, 1.2), 8.0


STEEL = (0.3, 0.42, 0.54)
STONE = (0.86, 0.84, 0.78)
ORANGE = (1.0, 0.6, 0.24)


def train_car():
    body = c.material("Train", (0.82, 0.85, 0.88), 0.4, metal=0.3)
    stripe = c.material("Train_stripe", (0.18, 0.65, 0.72), 0.45)
    glass = c.material("Train_glass", (0.12, 0.16, 0.24), 0.2)
    under = c.material("Train_under", (0.16, 0.18, 0.22), 0.7)
    parts = [(s.box("Body", (0, 2.3, 0), (3.0, 3.0, 14.0), bevel=0.55, seg=4), body)]
    parts.append((s.box("Stripe", (0, 1.45, 0), (3.06, 0.5, 14.05), bevel=0.2, seg=2), stripe))
    for z in (-4.6, -1.55, 1.55, 4.6):
        parts.append((s.box("Window", (0, 2.75, z), (3.08, 1.0, 2.3), bevel=0.25, seg=2), glass))
    parts.append((s.box("Front", (0, 2.6, -6.95), (2.2, 1.2, 0.2), bevel=0.08, seg=2), glass))
    parts.append((s.box("Under", (0, 0.5, 0), (2.4, 0.7, 12.0), bevel=0.2, seg=2), under))
    for x in (-0.8, 0.8):
        parts.append((blob("Lamp", (x, 1.5, -7.05), 0.2, seed=1, detail=1), c.material("Glow", (1.0, 0.92, 0.6), 0.3)))
    return finish(parts), (0, 0, 2.0), 22.0


def city_car():
    paint = c.material("Car_paint", (0.18, 0.65, 0.72), 0.3)
    glass = c.material("Car_glass", (0.12, 0.16, 0.24), 0.2)
    tyre = c.material("Car_tyre", (0.1, 0.1, 0.12), 0.8)
    parts = [(s.box("Body", (0, 0.75, 0), (1.9, 0.8, 4.4), bevel=0.36, seg=4), paint)]
    parts.append((s.box("Cabin", (0, 1.35, 0.2), (1.7, 0.75, 2.3), bevel=0.34, seg=4), paint))
    parts.append((s.box("Glass", (0, 1.38, 0.2), (1.74, 0.5, 1.9), bevel=0.2, seg=2), glass))
    for x in (-0.9, 0.9):
        for z in (-1.4, 1.4):
            parts.append((s.cylinder("Tyre", (x, 0.4, z), 0.4, 0.36, axis="x", verts=16, bevel=0.1), tyre))
    return finish(parts), (0, 0, 0.9), 8.0


def street_lamp():
    post = c.material("Lamp_post", (0.16, 0.2, 0.26), 0.5)
    parts = [(s.cylinder("Base", (0, 0.4, 0), 0.32, 0.8, axis="y", verts=12, bevel=0.08), post)]
    parts.append((s.tube("Post", [(0, 0.8, 0), (0, 5.8, 0), (0.25, 6.6, 0), (1.3, 6.9, 0)], 0.1, 3, along=6), post))
    parts.append((s.box("Head", (1.6, 6.82, 0), (0.9, 0.22, 0.5), bevel=0.1, seg=2), post))
    parts.append((s.box("Light", (1.6, 6.68, 0), (0.7, 0.1, 0.36), bevel=0.04, seg=2), c.material("Glow", (1.0, 0.9, 0.62), 0.3)))
    return finish(parts), (0, 0, 3.5), 11.0

def honey():
    import bmesh
    gold = c.material("Honey", (1.0, 0.62, 0.08), 0.15)
    light = c.material("Honey_light", (1.0, 0.82, 0.32), 0.15)
    rnd = random.Random(5)
    # An irregular outline: a circle pushed about by a few smooth waves.
    waves = [(rnd.uniform(0.04, 0.09), k, rnd.uniform(0, math.tau)) for k in (2, 3, 5, 7)]
    n = 48
    me = bpy.data.meshes.new("Honey")
    bm = bmesh.new()
    rings = [(1.0, 0.0), (0.97, 0.05), (0.9, 0.075), (0.6, 0.085), (0.0, 0.1)]   # (radius fraction, height): rim rolls over, middle domes
    verts = []
    for rf, h in rings:
        row = []
        for i in range(n):
            a = math.tau * i / n
            r = 2.0 * (1.0 + sum(w * math.sin(k * a + ph) for w, k, ph in waves)) * rf
            row.append(bm.verts.new(s.g(math.cos(a) * r, h, math.sin(a) * r)))
        verts.append(row)
    for j in range(len(rings) - 2):
        for i in range(n):
            bm.faces.new((verts[j][i], verts[j][(i + 1) % n], verts[j + 1][(i + 1) % n], verts[j + 1][i]))
    centre = bm.verts.new(s.g(0, rings[-1][1], 0))
    inner = verts[-2]
    for i in range(n):
        bm.faces.new((inner[i], inner[(i + 1) % n], centre))
    # Face up (Blender +z): seen from above, or the game culls it.
    bm.normal_update()
    if sum(f.normal.z for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    puddle = bpy.data.objects.new("Honey", me)
    bpy.context.collection.objects.link(puddle)
    c.subsurf(puddle, 1)
    c.smooth(puddle)
    parts = [(puddle, gold)]
    # Bubbles: little domes sitting in the honey.
    for i in range(6):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0.3, 1.4)
        r = rnd.uniform(0.07, 0.16)
        b = blob("Bubble", (math.cos(a) * d, 0.08, math.sin(a) * d), r, squash=0.6, seed=i, detail=2)
        parts.append((b, light))
    return finish(parts), (0, 0, 0.1), 4.2


def tumbleweed():
    straw = c.material("Twig", (0.72, 0.52, 0.28), 0.9)
    dry = c.material("Twig_dry", (0.86, 0.7, 0.42), 0.9)
    rnd = random.Random(11)
    parts = []
    for i in range(20):
        # A twig curling round the ball: a wobbly arc on a sphere.
        axis = (rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))
        L = math.sqrt(sum(v * v for v in axis)) or 1.0
        ax = [v / L for v in axis]
        # Two vectors at right angles to the axis.
        u = [ax[1], -ax[0], 0.0] if abs(ax[2]) < 0.9 else [0.0, ax[2], -ax[1]]
        Lu = math.sqrt(sum(v * v for v in u))
        u = [v / Lu for v in u]
        w = [ax[1] * u[2] - ax[2] * u[1], ax[2] * u[0] - ax[0] * u[2], ax[0] * u[1] - ax[1] * u[0]]
        start = rnd.uniform(0, math.tau)
        span = rnd.uniform(2.2, 4.4)
        pts = []
        for k in range(7):
            a = start + span * k / 6
            r = 0.6 + rnd.uniform(-0.12, 0.08)
            p = [math.cos(a) * u[j] + math.sin(a) * w[j] for j in range(3)]
            pts.append((p[0] * r, p[1] * r, p[2] * r))   # centred: it spins as it rolls
        t = s.tube("Twig", pts, rnd.uniform(0.018, 0.032), 2, along=3)
        parts.append((t, straw if i % 3 else dry))
    return finish(parts), (0, 0, 0.0), 3.0


def snowball():
    snow = c.material("Snow", (0.95, 0.97, 1.0), 0.85)
    shade = c.material("Snow_blue", (0.8, 0.88, 0.98), 0.85)
    parts = [(blob("Snowball", (0, 0, 0), 1.0, seed=21, detail=3), snow)]   # centred: it spins
    rnd = random.Random(4)
    # Clumps it picked up rolling: lumps half sunk into the surface.
    for i in range(16):
        # Spread evenly (a spiral over the sphere), each a little off.
        el = math.asin(-0.9 + 1.8 * (i + 0.5) / 16) + rnd.uniform(-0.12, 0.12)
        a = i * 2.4 + rnd.uniform(-0.3, 0.3)
        d = (math.cos(el) * math.cos(a), math.sin(el), math.cos(el) * math.sin(a))
        r = rnd.uniform(0.13, 0.22)
        parts.append((blob("Clump", (d[0] * 0.9, d[1] * 0.9, d[2] * 0.9), r, seed=40 + i, detail=1), shade if i % 3 == 0 else snow))
    return finish(parts), (0, 0, 0.0), 4.0

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


# Models other scripts make (kart.py, drivers.py, ...): a prop must never
# take one of their names. ("wheel" once did, and every kart drove on Ferris
# wheels.)
RESERVED = {"wheel", "item_box", "kart", "frame", "soapbox", "hauler", "racer"}

# --- Series 2 trackside dressing: packed to one vertex-coloured surface
# (see TREE_BUDGETS), so each kind is one draw call however many there are.

def fan():
    """A spectator: a round little creature with its arms up (1.5 m). White
    body so the game can tint each one; dark eyes."""
    body = c.material("Fan", (1, 1, 1), 0.6)
    dark = c.material("Fan_dark", (0.12, 0.12, 0.16), 0.6)
    parts = [(blob("Body", (0, 0.55, 0), 0.5, squash=1.15, seed=2, detail=1), body)]
    parts.append((blob("Head", (0, 1.2, 0), 0.36, seed=5, detail=1), body))
    for x in (-1, 1):
        parts.append((s.tube("Arm", [(x * 0.38, 0.8, 0), (x * 0.7, 1.25, 0), (x * 0.62, 1.7, 0)], 0.1, 1, along=2), body))
        parts.append((blob("Eye", (x * 0.14, 1.26, -0.31), 0.07, seed=1, detail=1), dark))
        parts.append((blob("Ear", (x * 0.26, 1.52, 0), 0.13, seed=3, detail=1), body))
    return finish(parts), (0, 0, 0.9), 4.5


def palm():
    trunk = c.material("Palm_trunk", (0.62, 0.45, 0.28), 0.8)
    leaf = c.material("Palm_leaf", (0.2, 0.68, 0.36), 0.6)
    nut = c.material("Palm_nut", (0.45, 0.3, 0.16), 0.7)
    parts = [(s.tube("Trunk", [(0, 0, 0), (0.5, 3.0, 0), (0.3, 6.0, 0), (-0.4, 8.6, 0)], 0.36, 2, along=5), trunk)]
    for i in range(7):
        a = math.tau * i / 7
        x, z = math.cos(a), math.sin(a)
        f = s.box("Frond", (-0.4 + x * 2.0, 8.5, z * 2.0), (4.2, 0.14, 1.2), bevel=0.05, seg=1)
        f.rotation_euler = (0, math.radians(22), -a)
        parts.append((f, leaf))
    for i in range(3):
        a = math.tau * i / 3
        parts.append((blob("Nut", (-0.4 + math.cos(a) * 0.4, 8.3, math.sin(a) * 0.4), 0.26, seed=i, detail=1), nut))
    return finish(parts), (0, 0, 5.0), 18.0


def big_top():
    """A striped circus tent (22 m across, 16 m to the flag)."""
    parts = []
    N = 16
    for i in range(N):
        a0 = math.tau * i / N
        a1 = math.tau * (i + 1) / N
        am = (a0 + a1) / 2
        col = c.material("Tent_%d" % (i % 2), RED if i % 2 == 0 else CREAM, 0.6)
        w = 2 * 11.0 * math.sin(math.pi / N) * 1.02
        wall = s.box("Wall", (math.cos(am) * 10.8, 2.5, math.sin(am) * 10.8), (0.3, 5.0, w), bevel=0.02, seg=1)
        wall.rotation_euler = (0, 0, -am)
        parts.append((wall, col))
        roof = s.box("Roof", (math.cos(am) * 5.6, 8.2, math.sin(am) * 5.6), (12.4, 0.3, w), bevel=0.02, seg=1)
        roof.scale = (1.0, 1.0, 1.0)
        roof.rotation_euler = (0, math.radians(32), -am)
        parts.append((roof, col))
    parts.append((s.cylinder("Pole", (0, 13.0, 0), 0.25, 6.0, axis="y", verts=8), c.material("Tent_pole", SUN, 0.5)))
    parts.append((s.box("Flag", (0.9, 15.4, 0), (1.8, 1.0, 0.08), bevel=0.02, seg=1), c.material("Tent_flag", TEAL, 0.5)))
    return finish(parts), (0, 0, 7.0), 36.0


def coaster_car():
    """One car of a coaster train (3 m), nose along -z."""
    parts = [(s.box("Body", (0, 0.8, 0), (1.7, 0.9, 2.8), bevel=0.35, seg=2), c.material("Coaster", RED, 0.4))]
    parts.append((s.box("Nose", (0, 0.75, -1.5), (1.3, 0.6, 0.8), bevel=0.28, seg=2), c.material("Coaster_nose", SUN, 0.4)))
    parts.append((s.box("Seat", (0, 1.3, 0.5), (1.3, 0.7, 0.5), bevel=0.15, seg=1), c.material("Coaster_seat", CREAM, 0.5)))
    for x in (-0.4, 0.4):
        parts.append((blob("Rider", (x, 1.55, -0.2), 0.3, seed=int(x * 10) + 7, detail=1), c.material("Rider_%d" % (x > 0), TEAL if x > 0 else PINK, 0.6)))
    return finish(parts), (0, 0, 1.0), 7.0


def hot_air_balloon():
    """A hot-air balloon with a coloured band and a basket (16 m tall)."""
    parts = [(blob("Envelope", (0, 10.4, 0), 5.6, squash=1.12, seed=11, detail=2), c.material("Hab", RED, 0.5))]
    parts.append((s.cylinder("Band", (0, 10.6, 0), 5.75, 2.2, axis="y", verts=16), c.material("Hab_band", SUN, 0.5)))
    parts.append((s.cylinder("Band2", (0, 13.6, 0), 4.5, 0.9, axis="y", verts=16), c.material("Hab_band2", CREAM, 0.5)))
    parts.append((s.cylinder("Neck", (0, 4.6, 0), 1.5, 1.4, axis="y", verts=10), c.material("Hab_neck", TEAL, 0.5)))
    parts.append((s.box("Basket", (0, 1.4, 0), (2.2, 1.6, 2.2), bevel=0.2, seg=1), c.material("Basket", (0.6, 0.42, 0.24), 0.8)))
    for x in (-1, 1):
        for z in (-1, 1):
            parts.append((s.tube("Rope", [(x * 1.0, 2.2, z * 1.0), (x * 1.3, 4.2, z * 1.3)], 0.06, 1, along=1), c.material("Rope", (0.3, 0.3, 0.3), 0.8)))
    return finish(parts), (0, 0, 8.0), 28.0


def umbrella():
    """A beach umbrella over a towel (3 m)."""
    parts = [(s.cylinder("Pole", (0, 1.3, 0), 0.06, 2.6, axis="y", verts=6), c.material("Umb_pole", CREAM, 0.5))]
    for i in range(8):
        a = math.tau * (i + 0.5) / 8
        seg = s.box("Seg", (math.cos(a) * 0.85, 2.45, math.sin(a) * 0.85), (1.75, 0.07, 1.4), bevel=0.0, seg=1)
        seg.rotation_euler = (0, math.radians(18), -a)
        parts.append((seg, c.material("Umb_%d" % (i % 2), PINK if i % 2 else CREAM, 0.5)))
    parts.append((s.box("Towel", (1.2, 0.04, 0.4), (1.0, 0.06, 2.0), bevel=0.0, seg=1), c.material("Towel", TEAL, 0.7)))
    return finish(parts), (0, 0, 1.4), 7.0


def boat():
    """A little sailing boat (7 m)."""
    hull = s.loft("Hull", [(-3.4, 0.05, 0.6, 1.0), (-2.0, 0.9, 0.0, 1.1), (0.5, 1.2, 0.0, 1.1), (3.2, 0.9, 0.2, 1.1)], around=10, power=3.0)
    parts = [(hull, c.material("Boat", (1, 1, 1), 0.4))]
    parts.append((s.box("Band", (0, 1.0, 0.3), (2.5, 0.2, 5.6), bevel=0.05, seg=1), c.material("Boat_band", RED, 0.5)))
    parts.append((s.cylinder("Mast", (0, 4.6, 0), 0.09, 7.4, axis="y", verts=6), c.material("Mast", (0.5, 0.36, 0.22), 0.7)))
    sail = s.box("Sail", (0, 4.9, 1.3), (0.06, 5.6, 2.6), bevel=0.0, seg=1)
    parts.append((sail, c.material("Sail", SUN, 0.6)))
    jib = s.box("Jib", (0, 4.0, -1.4), (0.06, 4.0, 1.8), bevel=0.0, seg=1)
    parts.append((jib, c.material("Jib", CREAM, 0.6)))
    return finish(parts), (0, 0, 3.5), 14.0


def tree_planter():
    """A street tree in a stone planter (7 m)."""
    parts = [(s.box("Planter", (0, 0.45, 0), (2.4, 0.9, 2.4), bevel=0.15, seg=1), c.material("Planter", STONE, 0.8))]
    parts.append((s.tube("Trunk", [(0, 0.8, 0), (0.1, 2.6, 0), (0, 4.2, 0)], 0.2, 1, along=3), c.material("Bark", (0.42, 0.3, 0.22), 0.8)))
    for i, (x, y, z, r) in enumerate([(0, 5.2, 0, 1.9), (1.0, 4.6, 0.4, 1.2), (-0.9, 4.7, -0.5, 1.3), (0.2, 6.3, -0.2, 1.2)]):
        parts.append((blob("Leaves", (x, y, z), r, seed=i + 20, detail=1), c.material("Leaves_%d" % (i % 2), (0.3, 0.7, 0.34) if i % 2 == 0 else (0.42, 0.78, 0.36), 0.7)))
    return finish(parts), (0, 0, 3.6), 13.0


def traffic_light():
    """A signal on a mast arm over the road (7 m tall, arm 6 m along +x)."""
    post = c.material("Signal_post", (0.16, 0.2, 0.26), 0.5)
    parts = [(s.cylinder("Post", (0, 3.4, 0), 0.16, 6.8, axis="y", verts=8), post)]
    parts.append((s.cylinder("Arm", (3.0, 6.5, 0), 0.1, 6.0, axis="x", verts=6), post))
    for x in (3.2, 5.6):
        parts.append((s.box("Head", (x, 5.8, 0), (0.55, 1.5, 0.5), bevel=0.08, seg=1), c.material("Signal_head", SUN, 0.5)))
        for k, col in enumerate(((0.95, 0.2, 0.2), (1.0, 0.75, 0.15), (0.25, 0.9, 0.4))):
            parts.append((blob("Lens", (x, 6.25 - k * 0.45, -0.27), 0.15, seed=k, detail=1), c.material("Lens_%d" % k, col, 0.3)))
    return finish(parts), (2.5, 0, 4.0), 13.0


def water_tank():
    """A rooftop water tank on legs (6 m)."""
    wood = c.material("Tank", (0.6, 0.4, 0.26), 0.8)
    steel = c.material("Tank_steel", (0.3, 0.33, 0.38), 0.6)
    parts = [(s.cylinder("Tank", (0, 3.8, 0), 1.7, 3.0, axis="y", verts=12), wood)]
    cone = s.lathe("Cap", [(0.0, 1.9), (1.1, 0.05)], segs=12)
    cone.rotation_euler = (0, math.radians(-90), 0)
    cone.location = s.g(0, 5.3, 0)
    parts.append((cone, steel))
    for x in (-1.1, 1.1):
        for z in (-1.1, 1.1):
            parts.append((s.box("Leg", (x, 1.15, z), (0.2, 2.3, 0.2), bevel=0.0, seg=1), steel))
    return finish(parts), (0, 0, 3.2), 11.0


def shuttle():
    """A chunky little spaceship (9 m), nose along -z."""
    body = s.loft("Body", [(-4.5, 0.25, -0.2, 0.4), (-2.5, 1.1, -0.7, 0.9), (1.0, 1.4, -0.8, 1.2), (4.0, 1.1, -0.6, 1.0)], around=12, power=3.0)
    parts = [(body, c.material("Ship", (0.9, 0.93, 0.97), 0.4))]
    parts.append((s.box("Canopy", (0, 0.85, -2.0), (1.3, 0.7, 2.0), bevel=0.3, seg=2), c.material("Ship_glass", (0.15, 0.6, 0.85), 0.2)))
    for x in (-1, 1):
        w = s.box("Wing", (x * 2.4, 0.0, 1.6), (3.2, 0.22, 2.6), bevel=0.08, seg=1)
        w.rotation_euler = (0, 0, x * math.radians(-18))
        parts.append((w, c.material("Ship_wing", (1.0, 0.7, 0.12), 0.45)))
        parts.append((s.cylinder("Engine", (x * 1.0, 0.2, 4.1), 0.55, 1.0, axis="z", verts=10), c.material("Ship_engine", (0.3, 0.34, 0.42), 0.5)))
        parts.append((blob("Flame", (x * 1.0, 0.2, 4.75), 0.42, seed=4, detail=1), c.material("Ship_flame", (0.3, 0.95, 1.0), 0.3)))
    parts.append((s.box("Fin", (0, 1.7, 3.0), (0.2, 1.6, 1.8), bevel=0.06, seg=1), c.material("Ship_fin", (0.69, 0.29, 0.88), 0.45)))
    return finish(parts), (0, 0, 0.5), 15.0


def asteroid():
    """A lumpy rock (about 6 m): the game scales and turns each one."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=3.0, location=s.g(0, 0, 0))
    o = bpy.context.object
    o.name = "Rock"
    rnd = random.Random(31)
    for v in o.data.vertices:
        v.co *= 1.0 + rnd.uniform(-0.28, 0.22)
    o.scale = (1.0, 0.8, 0.7)
    return finish([(o, c.material("Rock", (0.5, 0.46, 0.56), 0.9))]), (0, 0, 0), 12.0


def antenna():
    """A hull antenna mast with a blinking-light top (9 m)."""
    steel = c.material("Mast_steel", (0.75, 0.8, 0.88), 0.5)
    parts = [(s.box("Base", (0, 0.4, 0), (1.6, 0.8, 1.6), bevel=0.15, seg=1), c.material("Mast_base", (0.36, 0.4, 0.48), 0.6))]
    parts.append((s.cylinder("Mast", (0, 4.4, 0), 0.14, 7.4, axis="y", verts=6), steel))
    for y, w in ((3.0, 2.2), (5.0, 1.6), (6.6, 1.0)):
        parts.append((s.box("Bar", (0, y, 0), (w, 0.12, 0.12), bevel=0.0, seg=1), steel))
    parts.append((blob("Tip", (0, 8.3, 0), 0.32, seed=2, detail=1), c.material("Mast_tip", (1.0, 0.7, 0.12), 0.3)))
    return finish(parts), (0, 0, 4.5), 14.0


def box_truck():
    """A delivery truck backed up to a loading dock (8 m), cab along -z."""
    parts = [(s.box("Box", (0, 2.2, 1.2), (2.6, 3.0, 5.6), bevel=0.12, seg=1), c.material("Truck_box", (0.92, 0.92, 0.88), 0.6))]
    parts.append((s.box("Band", (0, 2.2, 1.2), (2.66, 0.7, 5.0), bevel=0.02, seg=1), c.material("Truck_band", ORANGE, 0.5)))
    parts.append((s.box("Cab", (0, 1.6, -2.7), (2.4, 2.0, 2.0), bevel=0.3, seg=2), c.material("Truck_cab", (0.18, 0.65, 0.72), 0.4)))
    parts.append((s.box("Glass", (0, 2.0, -3.3), (2.1, 0.8, 0.9), bevel=0.1, seg=1), c.material("Truck_glass", (0.12, 0.16, 0.24), 0.2)))
    for x in (-1.15, 1.15):
        for z in (-2.6, 0.6, 2.9):
            parts.append((s.cylinder("Tyre", (x, 0.5, z), 0.5, 0.4, axis="x", verts=8), c.material("Truck_tyre", (0.1, 0.1, 0.12), 0.8)))
    return finish(parts), (0, 0, 1.8), 13.0


# --- The space track (design doc 8.6): a glider for the jumps between
# worlds, and the red planet's dust devils and rocks.

def glider():
    """A kart's glider: a curved two-colour wing on struts, 4 m across. Sits
    above the kart (origin at the kart's seat), nose along -z."""
    a = c.material("Glider_a", RED, 0.5)
    b = c.material("Glider_b", CREAM, 0.5)
    strut = c.material("Glider_strut", (0.25, 0.27, 0.32), 0.5)
    parts = []
    n = 6
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        x = u * 4.2
        y = 2.25 - (u * u) * 2.2
        p = s.box("Panel", (x, y, 0.1), (4.2 / n + 0.04, 0.12, 1.5), bevel=0.04, seg=1)
        p.rotation_euler = (math.radians(8), u * 1.1, 0)
        parts.append((p, a if i % 2 == 0 else b))
    for x in (-0.55, 0.55):
        parts.append((s.tube("Strut", [(x, 0.6, 0.15), (x * 1.6, 1.4, 0.15), (x * 2.2, 2.1, 0.15)], 0.05, 1, along=2), strut))
    return finish(parts), (0, 0, 1.4), 7.0


def dust_devil():
    """A whirl of red dust, 9 m tall: rings widening upwards."""
    parts = []
    for i in range(7):
        y = 0.6 + i * 1.25
        r = 0.7 + i * 0.42
        ring = s.lathe("Ring", [(0.0, r * 0.75), (0.35, r), (0.7, r * 0.9)], segs=12, cap=False)
        ring.location = s.g(math.sin(i * 1.3) * 0.35, y, math.cos(i * 1.3) * 0.35)
        ring.rotation_euler = (math.radians(6 * math.sin(i)), math.radians(90), 0)
        shade = (0.78, 0.42, 0.26) if i % 2 == 0 else (0.88, 0.55, 0.36)
        parts.append((ring, c.material("Devil_%d" % (i % 2), shade, 0.9)))
    return finish(parts), (0, 0, 4.5), 16.0


def mars_rock():
    """A rust-red boulder (about 5 m): the game scales and turns each one."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=2.5, location=s.g(0, 1.2, 0))
    o = bpy.context.object
    o.name = "Rock"
    rnd = random.Random(53)
    for v in o.data.vertices:
        v.co *= 1.0 + rnd.uniform(-0.3, 0.2)
    o.scale = (1.0, 0.65, 0.85)
    top = blob("Dust", (0.3, 2.3, 0.2), 1.2, squash=0.5, seed=4, detail=1)
    return finish([(o, c.material("Mars_rock", (0.62, 0.3, 0.19), 0.9)), (top, c.material("Mars_dust", (0.8, 0.46, 0.3), 0.9))]), (0, 0, 1.2), 10.0

BUILDERS = {"train_car": train_car, "city_car": city_car, "street_lamp": street_lamp, "big_wheel": big_wheel, "big_wheel_stand": big_wheel_stand, "carousel": carousel, "stall": stall, "balloons": balloons, "bumper_car": bumper_car, "cargo_pod": cargo_pod, "reactor": reactor, "dish": dish, "honey": honey, "tumbleweed": tumbleweed, "snowball": snowball, "sand_gun": sand_gun, "tree_puffy": tree_puffy, "lamp_post": lamp_post, "guardrail": guardrail,
            "windmill": windmill, "lantern": lantern, "coin": coin,
            "snowpine_tall": snowpine_tall, "pine_tall": pine_tall, "tree_round": tree_round, "bush": bush, "snowpine_round": snowpine_round, "snowman": snowman}

# Packed to one vertex-coloured surface, with a triangle budget each: trees,
# and Series 2 trackside dressing.
TREE_BUDGETS = {"tree_puffy": 900, "pine_tall": 750, "tree_round": 750,
                "snowpine_tall": 750, "snowpine_round": 650,
                "fan": 110, "palm": 300, "big_top": 500, "coaster_car": 420,
                "hot_air_balloon": 900, "umbrella": 160, "boat": 360,
                "tree_planter": 420, "traffic_light": 420, "water_tank": 260,
                "shuttle": 700, "asteroid": 180, "antenna": 220, "box_truck": 320,
                "glider": 260, "dust_devil": 420, "mars_rock": 200}
BUILDERS.update({"fan": fan, "palm": palm, "big_top": big_top, "coaster_car": coaster_car,
                 "hot_air_balloon": hot_air_balloon, "umbrella": umbrella, "boat": boat,
                 "tree_planter": tree_planter, "traffic_light": traffic_light, "water_tank": water_tank,
                 "shuttle": shuttle, "asteroid": asteroid, "antenna": antenna, "box_truck": box_truck,
                 "glider": glider, "dust_devil": dust_devil, "mars_rock": mars_rock})


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
        assert name not in RESERVED, "'%s' is another script's model: pick a different name" % name
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
