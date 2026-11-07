"""Baked road surfaces (design doc 9.4), after the Blender samples in
tools/blender/terrain.py: the detailed relief is worked out as a height
map here, then "baked" into two tiling images per surface, so the road
stays flat (cheap) but lights as if it had real bumps:

  surf_<name>.png     greyscale detail with ambient occlusion in the dips
  surf_<name>_n.png   normal map (the bumps, for the lighting)

Each tile is 4 m square, 1024 px, and tiles seamlessly. Surfaces:
asphalt (grit, sealed patch seams, hairline cracks), planks (boards with
gaps and nails, grain, ends staggered), dirt (lumps and pebbles; the wheel
ruts are added by the road shader, along the lanes) and cobbles.

    python3 racing/tools/make_surfaces.py
"""
import numpy as np
from PIL import Image
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
N = 1024
M = 4.0                 # metres per tile
PX = N / M              # pixels per metre
rng = np.random.default_rng(11)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


def noise(scale_px, seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((N, N))
    f = np.fft.fftfreq(N)
    fx, fy = np.meshgrid(f, f)
    g = np.exp(-((fx ** 2 + fy ** 2) * (N / scale_px) ** 2) * 0.5 * (N / N) * N * N / (N * N)) if False else np.exp(-(np.sqrt(fx ** 2 + fy ** 2) * scale_px) ** 2 * 2.0)
    out = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    return (out - out.mean()) / (out.std() + 1e-9)


def blur(a, k):
    f = np.fft.fftfreq(N)
    fx, fy = np.meshgrid(f, f)
    g = np.exp(-(fx ** 2 + fy ** 2) * (k * np.pi) ** 2 * 2.0)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def cells(n_per_tile, seed):
    """Wrap-around Voronoi: distance to nearest and second-nearest point."""
    r = np.random.default_rng(seed)
    pts = r.random((n_per_tile, 2)) * N
    d1 = np.full((N, N), 1e9, np.float32)
    d2 = np.full((N, N), 1e9, np.float32)
    idx = np.zeros((N, N), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, N - dx)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, i, idx)
        d1 = np.where(closer, d, d1)
    return d1, d2, idx


def bake(name, h, depth_m, detail):
    """h: height in metres. depth_m scales the normal strength."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * PX * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * PX * 0.5
    nz = np.ones_like(h)
    n = np.stack([-gx, gy, nz], -1)   # OpenGL-style green up (Godot)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgb = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(OUT / f"surf_{name}_n.png", optimize=True)
    # Ambient occlusion: darker where a spot sits below its surroundings.
    ao = np.clip(1.0 - np.maximum(blur(h, 6) - h, 0) / depth_m * 1.4, 0.35, 1.0)
    a = np.clip(detail * ao, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8), "L").save(OUT / f"surf_{name}.png", optimize=True)
    print(name, "mean", round(float(a.mean()), 2))


def asphalt():
    h = noise(4) * 0.0008 + noise(14) * 0.0014
    # Sealed patches: slightly raised plates with a soft ridge round them.
    d1, d2, idx = cells(10, 3)
    seam = np.exp(-((d2 - d1) / 4.0) ** 2)
    patch = (np.random.default_rng(4).random(10)[idx] > 0.6).astype(np.float32)
    h += patch * 0.003 + seam * patch * 0.004
    # A few hairline cracks.
    c = noise(90, 8)
    crack = np.exp(-(c / 0.05) ** 2) * (noise(200, 9) > 0.3)
    h -= crack * 0.004
    tone = 0.9 + 0.05 * noise(6) - 0.1 * patch
    detail = np.clip(tone - crack * 0.35, 0, 1)
    bake("asphalt", h, 0.006, detail)


def planks():
    # Boards run across the tile (along x); 12 boards per 4 m.
    n_b = 12
    b = yy / N * n_b
    board = np.floor(b).astype(int)
    v = b - board
    r = np.random.default_rng(5)
    shift = r.random(n_b) * N            # stagger the board ends
    lengths = np.array([N, N / 2, N, N / 3, N, N / 2, N, N, N / 2, N, N / 3, N])
    u = (xx + shift[board]) % N
    end = np.minimum(u % lengths[board], lengths[board] - u % lengths[board])
    gap = np.minimum(v, 1 - v) * (N / n_b)          # pixels to the board edge
    h = np.where(gap < 3.0, -0.02, 0.0)
    h += np.where(end < 2.5, -0.012, 0.0)
    # Rounded board edges, a little warp per board, wood grain.
    h += np.clip(gap / 8.0, 0, 1) * 0.004 - 0.004
    h += (r.random(n_b)[board] - 0.5) * 0.004
    grain = noise(1.2, 6)[:, :]
    grain = np.sin((yy * 0.9 + noise(30, 7) * 18.0) * 0.6) * 0.5 + 0.3 * grain
    h += grain * 0.0006
    # Nails near each board end and every metre.
    for k in range(n_b):
        cy = (k + 0.5) * N / n_b
        for cx in np.arange(0, N, PX) + shift[k] % PX:
            d = np.sqrt(np.minimum(np.abs(xx - cx), N - np.abs(xx - cx)) ** 2 + (yy - cy) ** 2)
            h += np.where(d < 4.5, 0.002, 0.0)
    tone = 0.86 + 0.12 * (r.random(n_b)[board] - 0.5) + 0.05 * grain
    detail = np.where(gap < 3.0, 0.25, tone)
    bake("planks", h, 0.02, np.clip(detail, 0, 1))


def dirt():
    h = noise(40, 12) * 0.012 + noise(12) * 0.002
    # Pebbles: small rounded bumps, lighter than the earth round them.
    d1, d2, idx = cells(140, 13)
    keep = np.random.default_rng(14).random(140)[idx] > 0.5
    size = 6.0 + 8.0 * np.random.default_rng(15).random(140)[idx]
    peb = np.clip(1.0 - d1 / size, 0, 1) ** 0.5 * keep
    h += peb * 0.035
    detail = 0.86 + 0.05 * noise(10) - 0.07 * noise(40, 15) + peb * 0.14
    bake("dirt", h, 0.02, np.clip(detail, 0, 1))


def cobbles():
    # Staggered rows of rounded stones, 10 per 4 m, with mortar between.
    n = 10
    row = np.floor(yy / N * n).astype(int)
    xo = (xx / N * n + (row % 2) * 0.5) % 1.0
    yo = (yy / N * n) % 1.0
    col = np.floor(xx / N * n + (row % 2) * 0.5).astype(int) % n
    r = np.random.default_rng(16).random((n, n))
    # Each stone a rounded square ("superellipse"), a little different in size.
    sz = 0.93 + 0.06 * np.random.default_rng(17).random((n, n))[row % n, col]
    px = np.abs(xo - 0.5) * 2 / sz
    py = np.abs(yo - 0.5) * 2 / sz
    rr = (px ** 3 + py ** 3) ** (1 / 3)
    dome = np.clip(1.0 - rr, 0, 1)
    edge = dome * (N / n) * 0.5                    # pixels in from the stone edge
    h = np.sqrt(np.clip(dome / 0.35, 0, 1)) * 0.03 - 0.02
    tone = 0.8 + 0.2 * r[row % n, col]
    h += noise(3) * 0.002
    detail = np.where(edge < 3.0, 0.45, tone + 0.04 * noise(4))
    bake("cobbles", h, 0.03, np.clip(detail, 0, 1))


if __name__ == "__main__":
    asphalt()
    planks()
    dirt()
    cobbles()
