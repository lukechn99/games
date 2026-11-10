"""Shared helpers for the Animal Karts Blender scripts (run with python3, bpy).

Each asset script builds its model from scratch, exports a .glb into
racing/assets/models/ and can render a preview PNG to look at.
"""
import math
import os
import bpy
import bmesh


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb(r, g, b):
    """Pick colours as the game (and a paint program) does; Blender wants linear."""
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


def material(name, color, rough=0.5, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0, clearcoat=0.0, transmission=0.0):
    """`color` is sRGB (as in the game)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(*color), 1.0)
    if transmission:
        b.inputs["Transmission Weight"].default_value = transmission
        b.inputs["IOR"].default_value = 1.3
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if clearcoat:
        b.inputs["Coat Weight"].default_value = clearcoat
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(*emit), 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
    return m


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def bevel(obj, width, segments=3):
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return mod


def subsurf(obj, levels=2):
    mod = obj.modifiers.new("subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    return mod


def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def apply_all(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def tris(objects):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects if o.type == "MESH")


def bake_ao(objs, distance=0.16, samples=64, ground=True):
    """Bake ambient occlusion into each mesh's vertex colours (attribute "AO",
    exported as COLOR_0): creases, undersides and parts tucked behind others
    come out darker. The game multiplies its paint by it, so models get the
    soft contact shading of a full render for free at run time."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.light_settings.distance = distance
    plane = None
    if ground:
        bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0, 0, 0))
        plane = bpy.context.object
    meshes = [o for o in objs if o.type == "MESH"]
    for o in meshes:
        me = o.data
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        attr = me.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
        me.color_attributes.active_color = attr
        me.color_attributes.render_color_index = 0
        if not me.materials:
            me.materials.append(bpy.data.materials.new("bake"))
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    if plane:
        bpy.data.objects.remove(plane, do_unlink=True)


def export(path, objects=None, max_tris=None, ao=False, vertex_colors=False):
    """Write a .glb. With `max_tris`, thin the meshes down to about that many
    triangles first (phones draw many copies of these; design doc 14). With
    `ao`, bake ambient occlusion into the vertex colours (bake_ao). Set
    `vertex_colors` to retain an already painted active colour attribute."""
    objs = list(objects or bpy.context.scene.objects)
    if max_tris:
        total = tris(objs)
        if total > max_tris:
            ratio = max(0.08, max_tris / total)
            for o in objs:
                if o.type == "MESH" and len(o.data.polygons) > 40:
                    d = o.modifiers.new("budget", "DECIMATE")
                    d.ratio = ratio
                    apply_all(o)
        print("tris", os.path.basename(path), total, "->", tris(objs))
    if ao:
        bake_ao(objs)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE" if ao or vertex_colors else "MATERIAL")


def preview(path, target=(0, 0, 0.5), dist=4.0, elev=22.0, azim=35.0, size=(640, 480), samples=48, bg=(0.55, 0.75, 0.95)):
    """Render a preview with Cycles on the CPU: a key light, a sky, a floor."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"   # true colours, like the game
    world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb(*bg), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    # Floor
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    floor = bpy.context.object
    floor.name = "_preview_floor"
    assign(floor, material("_floor", (0.72, 0.72, 0.7), 0.9))
    # Sun
    bpy.ops.object.light_add(type="SUN", location=(4, -4, 8))
    sun = bpy.context.object
    sun.name = "_preview_sun"
    sun.data.energy = 4.0
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    bpy.ops.object.light_add(type="AREA", location=(-4, 3, 3))
    fill = bpy.context.object
    fill.name = "_preview_fill"
    fill.data.energy = 250
    fill.data.size = 4
    # Camera
    e, a = math.radians(elev), math.radians(azim)
    tx, ty, tz = target
    loc = (tx + dist * math.cos(e) * math.sin(a), ty - dist * math.cos(e) * math.cos(a), tz + dist * math.sin(e))
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.name = "_preview_cam"
    direction = (tx - loc[0], ty - loc[1], tz - loc[2])
    import mathutils
    cam.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for name in ["_preview_floor", "_preview_sun", "_preview_cam", "_preview_fill"]:
        o = bpy.data.objects.get(name)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)


def sheet(path, angles, target=(0, 0, 0.5), dist=4.0, size=(560, 420), samples=40, bg=(0.62, 0.8, 0.98)):
    """Render several views and put them side by side in one PNG."""
    import os
    from PIL import Image
    files = []
    for i, (elev, azim) in enumerate(angles):
        f = path.replace(".png", "_%d.png" % i)
        preview(f, target=target, dist=dist, elev=elev, azim=azim, size=size, samples=samples, bg=bg)
        files.append(f)
    ims = [Image.open(f) for f in files]
    out = Image.new("RGB", (size[0] * len(ims), size[1]))
    for i, im in enumerate(ims):
        out.paste(im.convert("RGB"), (i * size[0], 0))
    out.save(path)
    for f in files:
        os.remove(f)
