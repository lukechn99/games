"""Shape builders for the asset scripts: lofted bodies and lathed wheels.
Coordinates are Godot's (x right, y up, z back); `g()` converts."""
import math
import bpy
import bmesh
from mathutils import Vector


def g(x, y, z):
    return Vector((x, -z, y))


def mesh_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    return o


def loft(name, sections, around=24, power=4.0):
    """A smooth closed body through cross-sections along z. Each section is
    (z, half_width, bottom_y, top_y[, top_power]): a rounded rectangle (a
    superellipse, `power` 2 = ellipse, higher = boxier)."""
    bm = bmesh.new()
    rings = []
    for sec in sections:
        z, hw, y0, y1 = sec[:4]
        pw = sec[4] if len(sec) > 4 else power
        cy = (y0 + y1) * 0.5
        hh = (y1 - y0) * 0.5
        ring = []
        for k in range(around):
            a = math.tau * k / around
            ca, sa = math.cos(a), math.sin(a)
            x = math.copysign(abs(ca) ** (2.0 / pw), ca) * hw
            y = math.copysign(abs(sa) ** (2.0 / pw), sa) * hh + cy
            ring.append(bm.verts.new(g(x, y, z)))
        rings.append(ring)
    for r in range(len(rings) - 1):
        for k in range(around):
            k2 = (k + 1) % around
            bm.faces.new((rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k]))
    # Close the ends with fans (subdivision rounds them off).
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        c = Vector((0, 0, 0))
        for v in ring:
            c += v.co
        cv = bm.verts.new(c / len(ring))
        for k in range(around):
            k2 = (k + 1) % around
            f = (ring[k], ring[k2], cv) if flip else (ring[k2], ring[k], cv)
            bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm)


def lathe(name, profile, segs=40, tread=None, cap=True):
    """Spin a profile [(x_along_axle, radius), ...] round the x axis.
    `tread(k, i)` may return a radius scale for ring i at segment k."""
    bm = bmesh.new()
    rings = []
    for i, (x, r) in enumerate(profile):
        ring = []
        for k in range(segs):
            a = math.tau * k / segs
            s = tread(k, i) if tread else 1.0
            ring.append(bm.verts.new(g(x, math.cos(a) * r * s, math.sin(a) * r * s)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    for ring, flip in (((rings[0], True), (rings[-1], False)) if cap else ()):
        c = Vector((0, 0, 0))
        for v in ring:
            c += v.co
        cv = bm.verts.new(c / len(ring))
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((ring[k], ring[k2], cv) if flip else (ring[k2], ring[k], cv))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm)


def box(name, center, size, bevel=0.02, seg=3):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g(*center))
    o = bpy.context.object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = seg
    return o


def tube(name, points, radius, res=4):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = res
    curve.use_fill_caps = True
    sp = curve.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]
        bp.co = g(*p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return o


def cylinder(name, center, radius, depth, axis="x", verts=24, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=g(*center))
    o = bpy.context.object
    o.name = name
    if axis == "x":
        o.rotation_euler = (0, math.radians(90), 0)
    elif axis == "z":
        o.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if bevel:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
    return o
