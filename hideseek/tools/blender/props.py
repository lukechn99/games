"""Hide and Seek props (design doc 9.3): textured low-poly models.

Each prop is one low-poly mesh with one material, so one draw call. Detail
lives in two 512 px textures baked here from procedural Blender materials:
  albedo   colour, with ambient occlusion multiplied in
  normal   surface relief (straw strands, grain, tread)
Both are JPEGs packed inside the .glb.
Origin is the bottom centre; sizes match Props.KINDS in scripts/props.gd.

    python3 hideseek/tools/blender/props.py [name ...] [--no-preview]

Writes hideseek/assets/models/<name>.glb and a preview sheet to
/tmp/hideseek-previews/<name>.png.
"""
import os
import sys
import math
import random
import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "racing", "tools", "blender"))
import common as c  # noqa: E402  (racing's helpers: materials, preview, export)

MODELS = os.path.join(HERE, "..", "..", "assets", "models")
PREVIEWS = "/tmp/hideseek-previews"
TEX = 512


# ---------------------------------------------------------------- baking --

def node(nt, kind, loc=(0, 0), **inputs):
    n = nt.nodes.new(kind)
    n.location = loc
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def bake(obj, name, samples=24):
    """Bake the object's procedural material into albedo (with AO) and a
    tangent-space normal map, then give it a plain material that uses them."""
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.light_settings.distance = 0.25
    mat = obj.data.materials[0]
    nt = mat.node_tree

    def target(label):
        img = bpy.data.images.new(name + "_" + label, TEX, TEX, alpha=False, float_buffer=False)
        img.colorspace_settings.name = "sRGB" if label == "albedo" else "Non-Color"
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        for other in nt.nodes:
            other.select = False
        n.select = True
        nt.nodes.active = n
        return img, n

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bk = sc.render.bake
    bk.margin = 6
    bk.use_pass_direct = False
    bk.use_pass_indirect = False
    bk.use_pass_color = True

    albedo, n1 = target("albedo")
    bpy.ops.object.bake(type="DIFFUSE")
    ao, n2 = target("ao")
    # A floor under the prop darkens its base, like standing on the ground.
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, -0.002))
    floor = bpy.context.object
    obj.select_set(True)
    floor.select_set(False)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO")
    bpy.data.objects.remove(floor, do_unlink=True)
    normal, n3 = target("normal")
    bk.normal_space = "TANGENT"
    bpy.ops.object.bake(type="NORMAL")

    a = np.array(albedo.pixels[:]).reshape(-1, 4)
    o = np.array(ao.pixels[:]).reshape(-1, 4)[:, :1]
    a[:, :3] *= 0.5 + 0.5 * o      # soft: creases darken, nothing goes black
    albedo.pixels.foreach_set(a.ravel().astype(np.float32))
    albedo.update()

    tmp = os.path.join("/tmp", "hideseek-bake")
    os.makedirs(tmp, exist_ok=True)
    out = {}
    for img, label in [(albedo, "albedo"), (normal, "normal")]:
        path = os.path.join(tmp, "%s_%s.jpg" % (name, label))
        img.filepath_raw = path
        img.file_format = "JPEG"
        sc.render.image_settings.quality = 90
        img.save()
        out[label] = path
    # The game material: the two baked maps, nothing else.
    final = bpy.data.materials.new(name)
    final.use_nodes = True
    ft = final.node_tree
    bsdf = ft.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    ta = ft.nodes.new("ShaderNodeTexImage")
    ta.image = bpy.data.images.load(out["albedo"])
    ft.links.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    tn = ft.nodes.new("ShaderNodeTexImage")
    tn.image = bpy.data.images.load(out["normal"])
    tn.image.colorspace_settings.name = "Non-Color"
    nm = ft.nodes.new("ShaderNodeNormalMap")
    ft.links.new(tn.outputs["Color"], nm.inputs["Color"])
    ft.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(final)
    return out


def unwrap(obj, margin=0.02):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=margin)
    bpy.ops.uv.pack_islands(margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# ----------------------------------------------------------------- props --

def bale():
    """A small square hay bale, 1.0 x 0.5 x 0.55 m: soft puffy sides, straw
    lying along its length with the faint seams of its flakes, cut stalk
    ends on the ends, and two orange twines running lengthwise over the
    top and around the ends (as on a real bale)."""
    L, H, W = 1.0, 0.5, 0.55
    TW = 0.14                       # twines at y = +-TW
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.object
    o.name = "bale"
    o.scale = (L, W, H)
    bpy.ops.object.transform_apply(scale=True)
    o.location.z = H / 2
    bpy.ops.object.transform_apply(location=True)
    c.bevel(o, 0.06, 3)
    c.apply_all(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    cut = lambda co, no: bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    for x in (-0.3, -0.1, 0.1, 0.3):
        cut((x, 0, 0), (1, 0, 0))
    for y in (-TW - 0.03, -TW, -TW + 0.03, TW - 0.03, TW, TW + 0.03):
        cut((0, y, 0), (0, 1, 0))
    cut((0, 0, H / 2), (0, 0, 1))
    rnd = random.Random(4)
    for v in bm.verts:
        x, y, z = v.co
        # Puffy between the twines, pulled in under them.
        d = abs(abs(y) - TW)
        pinch = 1.0 - math.exp(-(d / 0.035) ** 2)
        if z > H - 0.07 or z < 0.07:
            v.co.z += (0.016 * pinch - 0.006) * (1 if z > H / 2 else 0)
        if abs(x) > L / 2 - 0.07:
            v.co.x += math.copysign(0.014 * pinch - 0.004 + rnd.uniform(-0.006, 0.006), x)
        if abs(y) > W / 2 - 0.07:
            bulge = 1.0 - (abs(x) / (L / 2)) ** 4
            v.co.y += math.copysign(0.014 * bulge + rnd.uniform(-0.004, 0.004), y)
    bm.to_mesh(o.data)
    bm.free()
    o.data.shade_smooth()

    m = bpy.data.materials.new("straw_proc")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    L_ = nt.links.new
    tc = node(nt, "ShaderNodeTexCoord", (-1600, 0))
    sep = node(nt, "ShaderNodeSeparateXYZ", (-1400, -500))
    L_(tc.outputs["Object"], sep.inputs["Vector"])
    # Strands: noise stretched along x (thin across, long along).
    mp = node(nt, "ShaderNodeMapping", (-1400, 0))
    mp.inputs["Scale"].default_value = (1.2, 32.0, 32.0)
    L_(tc.outputs["Object"], mp.inputs["Vector"])
    strands = node(nt, "ShaderNodeTexNoise", (-1200, 150), Scale=1.0, Detail=8.0, Roughness=0.72, Distortion=0.3)
    L_(mp.outputs["Vector"], strands.inputs["Vector"])
    mp2 = node(nt, "ShaderNodeMapping", (-1400, 250))
    mp2.inputs["Scale"].default_value = (0.6, 90.0, 90.0)
    L_(tc.outputs["Object"], mp2.inputs["Vector"])
    hairs = node(nt, "ShaderNodeTexNoise", (-1200, 400), Scale=1.0, Detail=3.0)
    L_(mp2.outputs["Vector"], hairs.inputs["Vector"])
    mixs = node(nt, "ShaderNodeMix", (-1000, 250))
    mixs.inputs["Factor"].default_value = 0.4
    L_(strands.outputs["Fac"], mixs.inputs["A"])
    L_(hairs.outputs["Fac"], mixs.inputs["B"])
    ramp = node(nt, "ShaderNodeValToRGB", (-800, 250))
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.36, (*c.srgb(0.5, 0.36, 0.14), 1)
    el[1].position, el[1].color = 0.64, (*c.srgb(1.0, 0.9, 0.58), 1)
    e = el.new(0.5)
    e.color = (*c.srgb(0.86, 0.68, 0.3), 1)
    L_(mixs.outputs["Result"], ramp.inputs["Fac"])
    # Flakes: faint darker seams across the length every ~9 cm.
    wave = node(nt, "ShaderNodeTexWave", (-1200, -150), Scale=3.2, Distortion=1.2, Detail=0.0)
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    L_(tc.outputs["Object"], wave.inputs["Vector"])
    seam = node(nt, "ShaderNodeMapRange", (-1000, -150))
    seam.inputs["From Min"].default_value = 0.0
    seam.inputs["From Max"].default_value = 0.05
    seam.inputs["To Min"].default_value = 0.86
    seam.inputs["To Max"].default_value = 1.0
    L_(wave.outputs["Fac"], seam.inputs["Value"])
    patch = node(nt, "ShaderNodeTexNoise", (-1200, -350), Scale=3.0, Detail=2.0)
    L_(tc.outputs["Object"], patch.inputs["Vector"])
    pr = node(nt, "ShaderNodeValToRGB", (-1000, -350))
    pr.color_ramp.elements[0].color = (*c.srgb(0.86, 0.9, 0.72), 1)
    pr.color_ramp.elements[1].color = (*c.srgb(1.0, 0.96, 0.88), 1)
    L_(patch.outputs["Fac"], pr.inputs["Fac"])
    t1 = node(nt, "ShaderNodeMix", (-600, 150))
    t1.data_type = "RGBA"
    t1.blend_type = "MULTIPLY"
    t1.inputs["Factor"].default_value = 1.0
    L_(ramp.outputs["Color"], t1.inputs["A"])
    L_(pr.outputs["Color"], t1.inputs["B"])
    t2 = node(nt, "ShaderNodeMix", (-400, 150))
    t2.data_type = "RGBA"
    t2.blend_type = "MULTIPLY"
    t2.inputs["Factor"].default_value = 1.0
    L_(t1.outputs["Result"], t2.inputs["A"])
    L_(seam.outputs["Result"], t2.inputs["B"])
    # Twine mask: | |y| - TW | < 0.016 with a slight wander.
    wob = node(nt, "ShaderNodeTexNoise", (-1200, -700), Scale=3.0)
    L_(tc.outputs["Object"], wob.inputs["Vector"])
    wobs = node(nt, "ShaderNodeMath", (-1000, -700))
    wobs.operation = "MULTIPLY_ADD"
    wobs.inputs[1].default_value = 0.012
    wobs.inputs[2].default_value = -0.006
    L_(wob.outputs["Fac"], wobs.inputs[0])
    ay = node(nt, "ShaderNodeMath", (-1200, -550))
    ay.operation = "ABSOLUTE"
    L_(sep.outputs["Y"], ay.inputs[0])
    off = node(nt, "ShaderNodeMath", (-1000, -550))
    off.operation = "SUBTRACT"
    off.inputs[1].default_value = TW
    L_(ay.outputs[0], off.inputs[0])
    off2 = node(nt, "ShaderNodeMath", (-850, -600))
    off2.operation = "ADD"
    L_(off.outputs[0], off2.inputs[0])
    L_(wobs.outputs[0], off2.inputs[1])
    ad = node(nt, "ShaderNodeMath", (-700, -600))
    ad.operation = "ABSOLUTE"
    L_(off2.outputs[0], ad.inputs[0])
    band = node(nt, "ShaderNodeMapRange", (-550, -600))
    band.inputs["From Min"].default_value = 0.017
    band.inputs["From Max"].default_value = 0.011
    L_(ad.outputs[0], band.inputs["Value"])
    twist = node(nt, "ShaderNodeTexWave", (-850, -850), Scale=45.0, Distortion=0.5)
    twist.wave_type = "BANDS"
    twist.bands_direction = "DIAGONAL"
    L_(tc.outputs["Object"], twist.inputs["Vector"])
    tcol = node(nt, "ShaderNodeMix", (-350, -700))
    tcol.data_type = "RGBA"
    tcol.inputs["A"].default_value = (*c.srgb(0.95, 0.45, 0.14), 1)
    tcol.inputs["B"].default_value = (*c.srgb(0.7, 0.27, 0.07), 1)
    L_(twist.outputs["Fac"], tcol.inputs["Factor"])
    final = node(nt, "ShaderNodeMix", (-150, 100))
    final.data_type = "RGBA"
    L_(band.outputs["Result"], final.inputs["Factor"])
    L_(t2.outputs["Result"], final.inputs["A"])
    L_(tcol.outputs["Result"], final.inputs["B"])
    L_(final.outputs["Result"], bsdf.inputs["Base Color"])
    # Relief: strands, flake seams, and the twine standing proud.
    h1 = node(nt, "ShaderNodeMath", (-400, -250))
    h1.operation = "MULTIPLY"
    L_(mixs.outputs["Result"], h1.inputs[0])
    L_(seam.outputs["Result"], h1.inputs[1])
    h = node(nt, "ShaderNodeMath", (-300, -350))
    h.operation = "MULTIPLY_ADD"
    h.inputs[1].default_value = 0.5
    L_(band.outputs["Result"], h.inputs[0])
    L_(h1.outputs[0], h.inputs[2])
    bump = node(nt, "ShaderNodeBump", (-150, -300), Strength=1.0, Distance=0.02)
    L_(h.outputs[0], bump.inputs["Height"])
    L_(bump.outputs["Normal"], bsdf.inputs["Normal"])
    o.data.materials.append(m)
    unwrap(o)
    return o, dict(target=(0, 0, 0.25), dist=2.6)


BUILDERS = {"bale": bale}


def build(name, show=True):
    c.reset()
    obj, view = BUILDERS[name]()
    print("tris", name, tris(obj))
    bake(obj, name)
    os.makedirs(MODELS, exist_ok=True)
    path = os.path.join(MODELS, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_image_format="AUTO")
    print("wrote", path, os.path.getsize(path) // 1024, "KB")
    if show:
        os.makedirs(PREVIEWS, exist_ok=True)
        c.sheet(os.path.join(PREVIEWS, name + ".png"), [(18, 35), (30, 150), (8, 90)], **view)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in args or list(BUILDERS):
        build(n, show="--no-preview" not in sys.argv)
