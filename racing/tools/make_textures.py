"""Makes the tiling detail textures in assets/textures (design doc 9.4).

They are greyscale and average close to white, because the game multiplies
them over our palette colours: the colour comes from the palette, the
texture only adds grain, seams, tufts, blocks and creases. Every texture
tiles seamlessly. Run: python3 racing/tools/make_textures.py
"""
import numpy as np
from PIL import Image
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
rng = np.random.default_rng(7)


def noise(n, scale, seed_shift=0):
    """Tileable smooth noise: white noise low-passed in frequency space."""
    w = rng.standard_normal((n, n))
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx ** 2 + fy ** 2)
    g = np.exp(-(r * n / scale) ** 2 * 0.5) if scale > 0 else 1
    out = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    return (out - out.mean()) / (out.std() + 1e-9)


def wrap_line(img, x0, y0, x1, y1, value, width=1):
    """Draw a soft line that wraps around the edges."""
    n = img.shape[0]
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for t in np.linspace(0, 1, steps):
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        for dx in range(-width, width + 1):
            for dy in range(-width, width + 1):
                d = np.hypot(dx, dy)
                if d <= width:
                    xi, yi = int(round(x + dx)) % n, int(round(y + dy)) % n
                    a = 1.0 - d / (width + 1)
                    img[yi, xi] = min(img[yi, xi], 1.0 - (1.0 - value) * a)


def save(name, a):
    a = np.clip(a, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8), "L").save(OUT / f"{name}.png", optimize=True)
    print(name, a.shape, round(float(a.mean()), 3))


def asphalt():
    n = 512  # covers 14 x 14 m of road: across the road and the same along it
    a = 0.93 + 0.035 * noise(n, 2.5) + 0.03 * noise(n, 40) + 0.025 * noise(n, 9)
    # Aggregate: light and dark specks.
    specks = rng.random((n, n))
    a[specks > 0.985] += 0.07
    a[specks < 0.02] -= 0.08
    # A repaired patch: a slightly darker, smoother rectangle with a seam.
    x0, y0, w, h = 300, 60, 150, 110
    patch = np.zeros((n, n), bool)
    patch[y0:y0 + h, x0:x0 + w] = True
    a[patch] = a[patch] * 0.94 - 0.01
    seam = np.ones((n, n))
    for (p, q) in [((x0, y0), (x0 + w, y0)), ((x0 + w, y0), (x0 + w, y0 + h)), ((x0 + w, y0 + h), (x0, y0 + h)), ((x0, y0 + h), (x0, y0))]:
        wrap_line(seam, *p, *q, 0.88, 1)
    # Sealed cracks: thin dark wandering lines.
    for _ in range(3):
        x, y = rng.random() * n, rng.random() * n
        ang = rng.random() * np.pi
        for _ in range(26):
            ang += rng.normal(0, 0.5)
            nx, ny = x + np.cos(ang) * 7, y + np.sin(ang) * 7
            wrap_line(seam, x, y, nx, ny, 0.84, 1)
            x, y = nx, ny
    a *= seam
    # A worn, lighter band where the wheels run (racing line), across u.
    u = np.linspace(0, 1, n, endpoint=False)
    a += 0.025 * np.exp(-((u - 0.32) / 0.08) ** 2)[None, :] + 0.025 * np.exp(-((u - 0.68) / 0.08) ** 2)[None, :]
    save("asphalt", a)


def grass():
    n = 256  # 8 x 8 m
    a = 0.9 + 0.05 * noise(n, 30) + 0.03 * noise(n, 6)
    # Tufts: little clusters of blades, a bright tip over a dark base.
    for _ in range(900):
        cx, cy = rng.random() * n, rng.random() * n
        for _ in range(rng.integers(3, 7)):
            ang = -np.pi / 2 + rng.normal(0, 0.5)
            ln = rng.uniform(3, 7)
            ex, ey = cx + np.cos(ang) * ln, cy + np.sin(ang) * ln
            m = np.ones((n, n))
            wrap_line(m, cx, cy + 1, ex, ey + 1, 0.82, 0)
            a = np.minimum(a, a * m + (1 - m) * 0.0)
            ix, iy = int(ex) % n, int(ey) % n
            a[iy, ix] = min(1.0, a[iy, ix] + 0.12)
    save("grass", a)


def stone():
    n = 256  # 2 x 2 m of wall
    a = np.full((n, n), 0.62)  # mortar
    rows = 6
    rh = n // rows
    for r in range(rows):
        x = rng.integers(0, 30) if r % 2 else 0
        x += (r % 2) * 20
        while x < n + 40:
            w = int(rng.integers(34, 64))
            shade = rng.uniform(0.84, 1.0)
            y0, y1 = r * rh + 3, (r + 1) * rh - 3
            for yy in range(y0, y1):
                for xx in range(x + 3, x + w - 3):
                    # Rounded edges: darker near the edge of each block.
                    e = min(yy - y0, y1 - 1 - yy, xx - x - 3, x + w - 4 - xx)
                    a[yy % n, xx % n] = shade * (0.82 + 0.18 * min(1.0, e / 5.0))
            x += w
    a += 0.04 * noise(n, 20) + 0.03 * noise(n, 4)
    save("stone", a)


def rock():
    n = 256  # 6 x 6 m, used on cliffs and boulders (triplanar)
    a = 0.88 + 0.06 * noise(n, 12) + 0.04 * noise(n, 3)
    # Strata: soft horizontal bands.
    y = np.linspace(0, 1, n, endpoint=False)
    a += 0.05 * np.sin(y * np.pi * 2 * 5 + 0.8 * noise(n, 10))[...]
    # Creases: dark ridged lines where light doesn't reach.
    ridge = np.abs(noise(n, 7))
    a -= 0.3 * (np.clip(0.45 - ridge, 0, 1) / 0.45) ** 1.5
    a -= 0.12 * (np.clip(0.6 - np.abs(noise(n, 22)), 0, 1) / 0.6) ** 2
    save("rock", a)


def wood():
    n = 256  # 2 x 2 m of planks
    a = np.zeros((n, n))
    planks = 8
    pw = n // planks
    for p in range(planks):
        shade = rng.uniform(0.86, 1.0)
        x0 = p * pw
        grain = noise(n, 3)[:, :pw] * 0.02 + 0.04 * np.sin(np.linspace(0, 40, n)[:, None] + 3 * noise(n, 8)[:, :pw])
        a[:, x0:x0 + pw] = shade + grain
        a[:, x0:x0 + 2] *= 0.7  # gap between planks
        cut = int(rng.integers(0, n))
        a[cut:cut + 2, x0:x0 + pw] *= 0.72  # plank end
    save("wood", a)


def dirt():
    n = 256  # 8 x 8 m
    a = 0.9 + 0.06 * noise(n, 16) + 0.04 * noise(n, 3)
    for _ in range(500):
        x, y = rng.integers(0, n, 2)
        r = rng.uniform(0.8, 2.2)
        yy, xx = np.ogrid[-3:4, -3:4]
        m = (xx ** 2 + yy ** 2) <= r * r
        sub = a[np.ix_((np.arange(-3, 4) + y) % n, (np.arange(-3, 4) + x) % n)]
        sub[m] += rng.choice([-0.12, 0.08])
        a[np.ix_((np.arange(-3, 4) + y) % n, (np.arange(-3, 4) + x) % n)] = sub
    save("dirt", a)


def ice():
    n = 256  # 8 x 8 m
    a = 0.95 + 0.03 * noise(n, 20)
    m = np.ones((n, n))
    for _ in range(10):
        x, y = rng.random() * n, rng.random() * n
        ang = rng.random() * np.pi * 2
        for _ in range(12):
            ang += rng.normal(0, 0.7)
            nx, ny = x + np.cos(ang) * 6, y + np.sin(ang) * 6
            wrap_line(m, x, y, nx, ny, 0.86, 0)
            x, y = nx, ny
    save("ice", a * m)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for f in (asphalt, grass, stone, rock, wood, dirt, ice):
        f()
