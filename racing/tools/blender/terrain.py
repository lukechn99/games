"""Terrain and surface samples (for review before they go in the game):

  boulder_wall  rounded boulders stacked into a wall, moss on top
  cliff         a chunky layered cliff: slabs of rock stepping back
  rocks         four loose rock variants, faceted
  surfaces      4 m tiles of real relief: asphalt, wood planks, dirt, cobbles

Each renders to OUTDIR/<name>.png; models also go to assets/models/terrain_*.glb.

    python3 racing/tools/blender/terrain.py OUTDIR [name ...]
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


def tex(kind, size, **kw):
    t = bpy.data.textures.new(kind + str(size), kind)
    t.noise_scale = size
    for k, v in kw.items():
        setattr(t, k, v)
    return t


def displace(o, texture, strength, mid=0.5, coords="GLOBAL"):
    m = o.modifiers.new("disp", "DISPLACE")
    m.texture = texture
    m.strength = strength
    m.mid_level = mid
    m.texture_coords = coords
    return m


def rock(name, center, size, seed, facets=True, color=(0.6, 0.55, 0.5), ratio=0.12):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0, location=s.g(*center))
    o = bpy.context.object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    rnd = random.Random(seed)
    o.rotation_euler = (rnd.uniform(0, 3), rnd.uniform(0, 3), rnd.uniform(0, 3))
    t = tex("VORONOI", 0.6 + rnd.uniform(0, 0.4))
    t.distance_metric = "DISTANCE"
    displace(o, t, 0.35, 0.5, "OBJECT")
    displace(o, tex("CLOUDS", 0.25), 0.08, 0.5, "OBJECT")
    if facets:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = ratio   # flat chiselled faces, cartoon-rock style
    c.apply_all(o)
    for p in o.data.polygons:
        p.use_smooth = not facets
    return o


def mat_rock(name, col):
    return c.material(name, col, 0.9)


def boulder_wall():
    stone = [mat_rock("Stone_a", (0.66, 0.58, 0.48)), mat_rock("Stone_b", (0.56, 0.5, 0.44)), mat_rock("Stone_c", (0.74, 0.66, 0.55))]
    moss = c.material("Moss", (0.34, 0.6, 0.2), 0.9)
    rnd = random.Random(4)
    parts = []
    # Three courses of chunky, chiselled boulders, each sitting into the
    # one below, smaller as they go up.
    for course, (y0, rmin, rmax) in enumerate([(0.0, 0.75, 1.05), (1.35, 0.6, 0.85), (2.45, 0.45, 0.65)]):
        x = -4.2 + course * 0.4
        while x < 4.2 - course * 0.4:
            r = rnd.uniform(rmin, rmax)
            o = rock("Wall", (x + r * 0.9, y0 + r * 0.75, rnd.uniform(-0.15, 0.15) + course * 0.25), (r, r * 0.8, r * 0.85), rnd.randint(0, 999), True, ratio=0.18)
            parts.append((o, rnd.choice(stone)))
            if course == 2 or rnd.random() < 0.25:
                # Moss creeping over the top: a thin lumpy shell.
                m = rock("Moss", (x + r * 0.9, y0 + r * 1.35, course * 0.25), (r * 0.8, r * 0.28, r * 0.7), rnd.randint(0, 999), True, ratio=0.25)
                parts.append((m, moss))
            x += r * 1.6
    return parts, (0, 0, 1.6), 11.0, [(10, -10), (25, 35)]


def cliff():
    tones = [(0.78, 0.6, 0.42), (0.68, 0.52, 0.38), (0.6, 0.45, 0.34), (0.74, 0.58, 0.44)]
    grass = c.material("Grass", (0.36, 0.66, 0.24), 0.9)
    rnd = random.Random(7)
    parts = []
    y = 0.0
    depth = 0.0
    k = 0
    while y < 8.0:
        h = rnd.uniform(1.0, 1.8)
        # One slab per layer, stepped back as it rises, its front chipped.
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=s.g(0, y + h * 0.5, depth))
        o = bpy.context.object
        o.name = "Cliff"
        o.scale = (10.0, 3.0, h)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        sub = o.modifiers.new("sub", "SUBSURF")
        sub.levels = 3
        sub.subdivision_type = "SIMPLE"
        t = tex("VORONOI", 0.9)
        displace(o, t, 0.6, 0.5)
        displace(o, tex("CLOUDS", 0.4), 0.25)
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = 0.2
        c.apply_all(o)
        parts.append((o, mat_rock("Cliff%d" % k, tones[k % len(tones)])))
        # Grass along each ledge's lip.
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=s.g(0, y + h + 0.06, depth - 1.0))
        g = bpy.context.object
        g.scale = (10.0, 1.0, 0.12)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        sub = g.modifiers.new("sub", "SUBSURF")
        sub.levels = 2
        displace(g, tex("CLOUDS", 0.3), 0.15)
        c.apply_all(g)
        c.smooth(g)
        parts.append((g, grass))
        y += h
        depth += rnd.uniform(0.6, 1.3)
        k += 1
    return parts, (0, 0, 3.8), 17.0, [(8, -20), (20, 30)]


def rocks():
    cols = [(0.62, 0.58, 0.52), (0.72, 0.56, 0.42), (0.5, 0.5, 0.52), (0.66, 0.62, 0.56)]
    parts = []
    for i, (x, sz) in enumerate([(-3.0, (1.1, 0.9, 1.0)), (-0.9, (0.7, 1.3, 0.7)), (1.1, (1.0, 0.6, 1.2)), (3.0, (0.6, 0.5, 0.6))]):
        parts.append((rock("Rock%d" % i, (x, sz[1] * 0.75, 0), sz, 10 + i), mat_rock("Rock%d" % i, cols[i])))
    return parts, (0, 0, 0.8), 8.0, [(12, 0), (30, 40)]


LIFT = 0.3   # tiles sit above the preview floor


def tile(name, x, z):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=160, y_subdivisions=160, size=4.0, location=s.g(x, LIFT, z))
    o = bpy.context.object
    o.name = name
    return o


def surfaces():
    parts = []
    rnd = random.Random(3)
    A, W, D, C = (-2.2, -2.2), (2.2, -2.2), (-2.2, 2.2), (2.2, 2.2)
    # Asphalt: coarse grit, slightly raised patch seams, a few cracks.
    a = tile("Asphalt", *A)
    displace(a, tex("CLOUDS", 0.02, noise_depth=2), 0.02)
    displace(a, tex("VORONOI", 0.7, distance_metric="DISTANCE"), 0.025, 0.9)
    parts.append((a, c.material("Asphalt", (0.3, 0.3, 0.31), 0.85)))
    # Wood planks: separate boards with gaps, each its own tone and warp.
    under = tile("Under", *W)
    under.location.z -= 0.08
    parts.append((under, c.material("Under", (0.1, 0.08, 0.06), 1.0)))
    z = W[1] - 2.0
    while z < W[1] + 2.0 - 0.2:
        w = rnd.uniform(0.28, 0.36)
        b = s.box("Plank", (W[0], LIFT + 0.0 + rnd.uniform(-0.012, 0.012), z + w / 2), (4.0, 0.1, w - 0.035), 0.012, 2)
        b.rotation_euler = (rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), 0)
        sub = b.modifiers.new("sub", "SUBSURF")
        sub.levels = 2
        sub.subdivision_type = "SIMPLE"
        displace(b, tex("WOOD", 0.4, wood_type="BANDNOISE", turbulence=4.0), 0.01, 0.5, "OBJECT")
        tone = rnd.uniform(-0.07, 0.07)
        parts.append((b, c.material("Wood", (0.62 + tone, 0.42 + tone, 0.25 + tone * 0.5), 0.8)))
        for nx in (-1.75, 1.75):
            n = s.cylinder("Nail", (W[0] + nx, LIFT + 0.055, z + w / 2), 0.022, 0.02, "y", 8)
            parts.append((n, c.material("Nail", (0.28, 0.28, 0.3), 0.5)))
        z += w
    # Dirt: two ruts where wheels run, lumps and pebbles.
    d = tile("Dirt", *D)
    displace(d, tex("CLOUDS", 0.5), 0.12)
    displace(d, tex("CLOUDS", 0.06), 0.03)
    c.apply_all(d)
    for v in d.data.vertices:
        gx = v.co.x - D[0]
        for rx in (-0.9, 0.9):
            v.co.z -= 0.09 * math.exp(-((gx - rx) / 0.22) ** 2)
    parts.append((d, c.material("Dirt", (0.62, 0.45, 0.3), 0.95)))
    for i in range(45):
        p = rock("Pebble", (D[0] + rnd.uniform(-1.9, 1.9), LIFT + 0.04, D[1] + rnd.uniform(-1.9, 1.9)), (rnd.uniform(0.05, 0.12),) * 3, 100 + i)
        parts.append((p, c.material("Pebble", (0.55, 0.5, 0.45), 0.9)))
    # Cobbles: rounded stones, staggered rows, on a dark bed.
    bed = tile("Bed", *C)
    parts.append((bed, c.material("Bed", (0.3, 0.27, 0.24), 1.0)))
    for row in range(10):
        for col in range(11):
            ox = 0.2 if row % 2 else 0.0
            cx = C[0] - 2.0 + col * 0.4 + ox
            cz = C[1] - 2.0 + 0.2 + row * 0.4
            if cx < C[0] - 1.95 or cx > C[0] + 1.95:
                continue
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=s.g(cx, LIFT + 0.05, cz))
            st = bpy.context.object
            st.name = "Cobble"
            st.scale = (0.36, 0.36, 0.14)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            bev = st.modifiers.new("bev", "BEVEL")
            bev.width = 0.06
            bev.segments = 3
            sub = st.modifiers.new("sub", "SUBSURF")
            sub.levels = 1
            st.rotation_euler = (0, 0, rnd.uniform(-0.1, 0.1))
            c.smooth(st)
            tone = rnd.uniform(-0.07, 0.07)
            parts.append((st, c.material("Cobble", (0.62 + tone, 0.58 + tone, 0.53 + tone), 0.85)))
    return parts, (0, 0, 0), 9.0, None


BUILDERS = {"boulder_wall": boulder_wall, "cliff": cliff, "rocks": rocks, "surfaces": surfaces}

if __name__ == "__main__":
    outdir = sys.argv[1]
    for name in (sys.argv[2:] or list(BUILDERS)):
        c.reset()
        parts, target, dist, angles = BUILDERS[name]()
        objs = []
        for o, m in parts:
            c.assign(o, m)
            if o.modifiers:
                c.apply_all(o)
            objs.append(o)
        def join(group, label):
            bpy.ops.object.select_all(action="DESELECT")
            for o in group:
                o.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            bpy.ops.object.join()
            group[0].name = label
            # Bake the object's own turn and size into the mesh (the game
            # uses the mesh alone), then put the origin on the ground.
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            bpy.context.scene.cursor.location = (0, 0, 0)
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
            return group[0]
        if name == "rocks":
            # One file per rock, each sitting on its own origin.
            for i in range(4):
                o = [x for x in objs if x.name.startswith("Rock%d" % i)][0]
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.select_all(action="DESELECT")
                o.select_set(True)
                bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
                bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
                lo = min((o.matrix_world @ v.co).z for v in o.data.vertices)
                o.location = (0, 0, o.location.z - lo - 0.1)   # a little sunk in
                bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
                c.export(os.path.abspath(os.path.join(MODELS, "terrain_rock%d.glb" % i)), [o], max_tris=400)
                o.location.x = (i - 1.5) * 2.2
        elif name != "surfaces":
            one = join(objs, name)
            c.export(os.path.abspath(os.path.join(MODELS, "terrain_" + name + ".glb")), [one], max_tris=3000)
            objs = [one]
        if name != "surfaces":
            c.sheet(os.path.join(outdir, name + ".png"), angles, target=target, dist=dist, size=(640, 420), samples=32)
        else:
            # Low, like the race camera, looking along the four tiles.
            c.preview(os.path.join(outdir, "surfaces.png"), target=(0, 0, 0.2), dist=11.0, elev=38, azim=0, size=(1100, 760), samples=40)
        print("done", name)
