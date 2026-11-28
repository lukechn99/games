"""Tileable surface textures for Hide and Seek's buildings and ground.

Each surface is a seamless 512 px colour map (JPEG) and a matching normal
map (JPEG, OpenGL style, green = up), generated with numpy so they tile
exactly: every noise is built in the frequency domain, which wraps by
construction. TILE (metres covered by one copy) is what the game uses to
scale the UVs; keep the two in step (scripts/surfaces.gd).

    python3 hideseek/tools/textures.py [name ...] [--sheet]

Writes hideseek/assets/textures/<name>_albedo.jpg.bin and _normal.jpg.bin
(JPEGs; the .bin keeps Godot from importing and bloating them),
and with --sheet a preview (each tiled 2 x 2) to /tmp/hideseek-textures.png.
"""
import os
import sys
import numpy as np
from PIL import Image

N = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")

# Metres covered by one copy of each texture (mirrored in scripts/surfaces.gd).
TILE = {
    "barn_siding": 2.4, "trim": 1.2, "barn_roof": 2.0, "house_siding": 1.8,
    "shingles": 2.0, "silo_metal": 2.0, "floor": 2.4, "grass": 3.0,
    "dirt": 3.0, "concrete": 2.0, "straw": 2.0, "wallpaper": 1.2, "plaster": 2.0,
}

_y, _x = np.mgrid[0:N, 0:N] / N          # 0..1, row 0 at the top


def noise(seed, cells=8.0, stretch=(1.0, 1.0), beta=2.0):
    """Seamless fractal noise in 0..1. `cells` ~ feature count across the
    tile; stretch=(1, 8) gives streaks running vertically (wood grain)."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    f = np.sqrt((fx * stretch[0]) ** 2 + (fy * stretch[1]) ** 2)
    amp = 1.0 / np.maximum(f, cells * 0.5) ** beta
    amp[0, 0] = 0
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    n -= n.min()
    return n / n.max()


def strands(seed, cells, angle, ratio=10.0, beta=1.4):
    """Seamless noise streaked along `angle` (radians): straw lying that way."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    ca, sa = np.cos(angle), np.sin(angle)
    along = fx * ca + fy * sa
    across = -fx * sa + fy * ca
    f = np.sqrt((along * ratio) ** 2 + across ** 2)
    amp = 1.0 / np.maximum(f, cells * 0.5) ** beta
    amp[0, 0] = 0
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    n -= n.min()
    return n / n.max()


def lerp(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (b - a) * t


def rgb(*c):
    return np.array(c, dtype=float)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def normals(h, strength):
    """Height (0..1, larger = raised) to an OpenGL normal map."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def boards(count, axis_vals, seed, gap=0.06):
    """Which board each pixel is in, and position across it (0..1)."""
    p = axis_vals * count
    idx = np.floor(p).astype(int) % count
    across = p - np.floor(p)
    return idx, across


# ---------------------------------------------------------------- surfaces --

def barn_siding():
    """Red board-and-batten: wide vertical boards, narrow battens over the
    seams, grain showing through worn paint."""
    count = 8
    idx, across = boards(count, _x, 1)
    grain = noise(11, cells=6, stretch=(1, 14), beta=1.6)
    fine = noise(12, cells=40, stretch=(1, 20), beta=1.2)
    per_board = np.random.default_rng(3).uniform(-0.06, 0.06, count)[idx]
    batten = smooth(0.09, 0.06, np.minimum(across, 1 - across))      # 1 on battens
    wear = smooth(0.7, 0.85, noise(13, cells=10, stretch=(1, 5), beta=1.8) * 0.7 + fine * 0.3)
    paint = rgb(0.6, 0.15, 0.11) * (0.88 + 0.24 * grain[..., None] + per_board[..., None])
    paint = lerp(paint, rgb(0.66, 0.2, 0.15), batten * 0.6)
    wood = rgb(0.5, 0.42, 0.33) * (0.7 + 0.5 * grain[..., None])
    col = lerp(paint, wood, wear * 0.75)
    col *= (0.92 + 0.12 * fine[..., None])
    h = 0.35 * grain + 0.15 * fine + 0.9 * batten - 0.25 * wear
    edge = smooth(0.13, 0.085, np.minimum(across, 1 - across)) * (1 - batten)
    col *= (1 - 0.5 * edge[..., None])                             # shade beside each batten
    return col, normals(h, 5.0)


def trim():
    """White painted boards (barn trim, window frames)."""
    grain = noise(21, cells=6, stretch=(1, 12), beta=1.6)
    fine = noise(22, cells=40, stretch=(1, 16), beta=1.2)
    col = rgb(0.9, 0.88, 0.83) * (0.94 + 0.08 * grain[..., None] + 0.04 * fine[..., None])
    return col, normals(0.3 * grain + 0.1 * fine, 3.0)


def barn_roof():
    """Weathered corrugated steel roof: ridges run down the slope (across v)."""
    ridges = 0.5 + 0.5 * np.cos(_y * 2 * np.pi * 10)
    mottle = noise(31, cells=4, beta=2.0)
    streak = noise(32, cells=10, stretch=(1, 0.1), beta=1.4)
    rust = smooth(0.66, 0.85, mottle * 0.6 + streak * 0.4)
    base = rgb(0.42, 0.44, 0.46) * (0.85 + 0.25 * ridges[..., None] + 0.15 * mottle[..., None])
    col = lerp(base, rgb(0.45, 0.26, 0.15), rust * 0.6)
    seam = smooth(0.006, 0.0, np.abs(((_x * 2) % 1) - 0.5) - 0.495)    # panel overlaps every 1 m
    col *= (1 - 0.3 * seam[..., None])
    return col, normals(ridges * 0.6 + seam * 0.3, 6.0)


def house_siding():
    """White lap siding: each board a shallow wedge with a shadow under its lip."""
    count = 12
    p = _y * count
    t = p - np.floor(p)                    # 0 at a board's top, 1 at its lip
    grain = noise(41, cells=6, stretch=(10, 1), beta=1.6)
    dirt = noise(42, cells=3, beta=2.2)
    col = rgb(0.93, 0.91, 0.86) * (0.9 + 0.1 * t[..., None]) * (0.95 + 0.05 * grain[..., None])
    col *= (1 - 0.04 * smooth(0.6, 0.9, dirt)[..., None])
    shadow = smooth(0.1, 0.0, t)           # just under the board above
    col *= (1 - 0.32 * shadow[..., None])
    h = t * 0.8 + 0.1 * grain
    return col, normals(h, 4.0)


def shingles():
    """Asphalt shingles: staggered rows of tabs, granular, slight colour variety."""
    rows = 8
    p = _y * rows
    row = np.floor(p).astype(int) % rows
    t = p - np.floor(p)
    tabs = 6
    q = _x * tabs + (row % 2) * 0.5
    tab = (np.floor(q).astype(int) + row * 7) % 97
    u = q - np.floor(q)
    shade = np.random.default_rng(5).uniform(0.8, 1.15, 97)[tab]
    grit = noise(51, cells=120, beta=0.6)
    base = rgb(0.3, 0.29, 0.3) * shade[..., None] * (0.85 + 0.3 * grit[..., None])
    gap = smooth(0.02, 0.0, np.minimum(u, 1 - u))
    under = smooth(0.12, 0.0, t)          # shadow under the row above
    col = base * (1 - 0.5 * under[..., None]) * (1 - 0.6 * gap[..., None])
    h = t * 0.7 + grit * 0.1 - gap * 0.4
    return col, normals(h, 4.0)


def silo_metal():
    """Galvanized corrugated steel: fine vertical ridges, spangle mottling,
    a ring seam with rivets every metre."""
    ridges = 0.5 + 0.5 * np.cos(_x * 2 * np.pi * 26)
    spangle = noise(61, cells=60, beta=0.9)
    mottle = noise(62, cells=4, beta=2.0)
    v = (_y * 2) % 1
    seam = smooth(0.012, 0.0, np.abs(v - 0.5))
    rivx = (_x * 26 * 2) % 1
    rd = np.hypot(((rivx - 0.5) / 52), (v - 0.53) / 2)
    rivet = smooth(0.004, 0.002, rd)
    col = rgb(0.72, 0.75, 0.78) * (0.78 + 0.3 * ridges[..., None]) * (0.9 + 0.14 * spangle[..., None]) * (0.92 + 0.12 * mottle[..., None])
    col *= (1 - 0.25 * seam[..., None])
    h = ridges * 0.7 + seam * 0.4 + rivet * 0.6 + spangle * 0.03
    return col, normals(h, 7.0)


def floor():
    """Worn plank floor: planks run along v, staggered butt joints."""
    count = 12
    idx, across = boards(count, _x, 7)
    off = np.random.default_rng(8).uniform(0, 1, count)[idx]
    along = (_y + off) % 1
    plank = (idx * 31 + (np.floor((_y + off) * 2)).astype(int) * 7) % 50
    tone = np.random.default_rng(9).uniform(0.82, 1.12, 50)[plank]
    grain = noise(71, cells=6, stretch=(1, 14), beta=1.6)
    fine = noise(72, cells=50, stretch=(1, 16), beta=1.1)
    scuff = noise(73, cells=3, beta=2.2)
    col = rgb(0.5, 0.38, 0.26) * tone[..., None] * (0.75 + 0.4 * grain[..., None]) * (0.92 + 0.1 * fine[..., None])
    col *= (0.9 + 0.18 * scuff[..., None])
    gap = smooth(0.03, 0.0, np.minimum(across, 1 - across))
    butt = smooth(0.006, 0.0, np.minimum((_y * 2 + off) % 1, 1 - (_y * 2 + off) % 1))
    col *= (1 - 0.6 * np.maximum(gap, butt)[..., None])
    h = 0.3 * grain + 0.1 * fine - 0.6 * np.maximum(gap, butt)
    return col, normals(h, 4.0)


def grass():
    """Lawn grass seen from standing height: dense blade speckle over
    soft patches of lighter and darker green."""
    blades = noise(81, cells=180, stretch=(1, 2.2), beta=0.5)
    clumps = noise(82, cells=14, beta=1.6)
    patches = noise(83, cells=3, beta=2.2)
    dry = smooth(0.62, 0.85, noise(84, cells=5, beta=2.0))
    g = lerp(rgb(0.16, 0.3, 0.09), rgb(0.48, 0.66, 0.25), smooth(0.25, 0.8, blades * 0.75 + clumps * 0.25))
    g = lerp(g, rgb(0.55, 0.58, 0.28), dry * 0.45)
    g *= (0.85 + 0.25 * patches[..., None])
    h = blades * 0.7 + clumps * 0.3
    return g, normals(h, 3.0)


def dirt():
    """Packed farmyard dirt with pebbles."""
    base = noise(91, cells=6, beta=2.0)
    grit = noise(92, cells=150, beta=0.6)
    peb = smooth(0.8, 0.86, noise(93, cells=70, beta=1.0))
    col = lerp(rgb(0.42, 0.33, 0.24), rgb(0.6, 0.5, 0.38), base * 0.7 + grit * 0.3)
    col = lerp(col, rgb(0.68, 0.64, 0.58), peb * 0.8)
    h = base * 0.3 + grit * 0.2 + peb * 0.6
    return col, normals(h, 4.0)


def concrete():
    base = noise(101, cells=5, beta=2.0)
    grit = noise(102, cells=160, beta=0.5)
    col = rgb(0.62, 0.61, 0.58) * (0.85 + 0.18 * base[..., None] + 0.1 * grit[..., None])
    return col, normals(grit * 0.3 + base * 0.1, 2.0)


def straw():
    """Loose straw bedding: stalks lying every which way over darker litter."""
    layers = [strands(111 + i, cells=60, angle=a) for i, a in enumerate((0.3, 1.4, 2.4, 3.0))]
    top = np.maximum.reduce(layers)
    stalk = smooth(0.55, 0.85, top)
    litter = noise(115, cells=8, beta=1.8)
    col = lerp(rgb(0.42, 0.32, 0.16) * (0.8 + 0.3 * litter[..., None]), rgb(0.93, 0.8, 0.46), stalk)
    col *= (0.85 + 0.2 * noise(116, cells=3, beta=2.2)[..., None])
    return col, normals(top * 0.8 + litter * 0.2, 4.0)


def wallpaper():
    """Farmhouse wallpaper: soft cream with sage stripes and a tiny sprig
    pattern between them."""
    stripes = 0.5 + 0.5 * np.cos(_x * 2 * np.pi * 8)
    band = smooth(0.82, 0.9, stripes)
    col = lerp(rgb(0.93, 0.89, 0.8), rgb(0.72, 0.8, 0.68), band * 0.55)
    gx = (_x * 8 + 0.5) % 1
    gy = (_y * 16) % 1
    dot = smooth(0.06, 0.03, np.hypot(gx - 0.5, gy - 0.5) * np.array(1.0))
    col = lerp(col, rgb(0.86, 0.55, 0.5), dot * 0.6)
    col *= (0.96 + 0.05 * noise(121, cells=4, beta=2.2)[..., None])
    return col, normals(noise(122, cells=60, beta=1.0) * 0.2, 1.5)


def plaster():
    """Painted plaster: warm white with a faint trowel texture."""
    base = noise(131, cells=6, beta=2.0)
    fine = noise(132, cells=90, beta=0.9)
    col = rgb(0.92, 0.9, 0.85) * (0.95 + 0.05 * base[..., None] + 0.03 * fine[..., None])
    return col, normals(base * 0.3 + fine * 0.1, 1.5)


SURFACES = {f.__name__: f for f in [barn_siding, trim, barn_roof, house_siding, shingles, silo_metal, floor, grass, dirt, concrete, straw, wallpaper, plaster]}


def save(name):
    col, nrm = SURFACES[name]()
    os.makedirs(OUT, exist_ok=True)
    a = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    n = Image.fromarray((np.clip(nrm, 0, 1) * 255).astype(np.uint8))
    a.save(os.path.join(OUT, name + "_albedo.jpg.bin"), format="JPEG", quality=88)
    n.save(os.path.join(OUT, name + "_normal.jpg.bin"), format="JPEG", quality=92)
    return a, n


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(SURFACES)
    tiles = []
    for nm in names:
        a, n = save(nm)
        tiles.append((nm, a, n))
        print("wrote", nm)
    if "--sheet" in sys.argv:
        cell = 256
        sheet = Image.new("RGB", (cell * 4, cell * len(tiles)), "white")
        for i, (_, a, n) in enumerate(tiles):
            small = a.resize((cell // 2, cell // 2))
            for dx in (0, 1):
                for dy in (0, 1):
                    sheet.paste(small, (dx * cell // 2, i * cell + dy * cell // 2))
            sheet.paste(a.resize((cell, cell)), (cell, i * cell))
            sheet.paste(n.resize((cell, cell)), (cell * 2, i * cell))
        sheet.save("/tmp/hideseek-textures.png")
        print("sheet /tmp/hideseek-textures.png")
