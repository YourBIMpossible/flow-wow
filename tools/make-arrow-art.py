"""Render the modern nav arrow's pictures (Modules/Nav/Art/*.tga).

The arrow is a faceted, bevelled chevron floating a little above the ground,
seen from behind and above like the game camera, lit from the upper left.
It is rendered at 128 headings into sprite sheets; the add-on shows the cell
nearest the heading it needs (Nav.lua: N.ArrowCell).

  ArrowBody.tga    1024x512, 16x8 cells of 64 px. Grey shading + a dark
                   outline. The game tints it (SetVertexColor), so the shading
                   keeps its depth in any colour.
  ArrowShine.tga   1024x512, same cells. White highlights only, drawn with
                   ADD blending on top so they stay white whatever the tint.
  ArrowShadow.tga  512x256, 16x8 cells of 32 px. The soft shadow on the ground
                   (its own picture so the arrow can bob over it).
  ArrowGlow.tga    64x64, a soft round light pool (tinted, ADD).
  ArrowRing.tga    128x128, a glowing ring for "you're here" (tinted, ADD).
  ArrowBeam.tga    32x128, a column of light rising from the ring (tinted, ADD).

Needs Python 3 with numpy and Pillow:  python -I tools/make-arrow-art.py
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

FRAMES, COLS, ROWS = 128, 16, 8
CELL, SHADOW_CELL = 64, 32
SS = 4                                  # supersampling (anti-aliasing)
RES = CELL * SS

# Arrow outline on the ground (x right, z forward), tip forward.
CHEVRON = np.array([(0.0, 0.94), (-0.54, -0.58), (0.0, -0.30), (0.54, -0.58)])
ROUND = 0.05                            # corner rounding
LIFT, WALL, ROOF, ROOF_W = 0.10, 0.09, 0.11, 0.24
ELEVATION = np.radians(50)              # camera height angle
CAM_DIST, VIEW = 6.0, 1.08              # camera distance, half-size of the view (world units)
LIGHT = np.array([-0.55, 1.0, 0.30])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Modules", "Nav", "Art")


def polygon_sdf(px, pz, poly):
    """Signed distance from points to a polygon (negative inside)."""
    d = np.full(px.shape, np.inf)
    sign = np.ones(px.shape)
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        ex, ez = bx - ax, bz - az
        wx, wz = px - ax, pz - az
        t = np.clip((wx * ex + wz * ez) / (ex * ex + ez * ez), 0, 1)
        dx, dz = wx - ex * t, wz - ez * t
        d = np.minimum(d, dx * dx + dz * dz)
        c1 = pz >= az
        c2 = pz < bz
        c3 = ex * wz > ez * wx
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        sign = np.where(flip, -sign, sign)
    return sign * np.sqrt(d)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# Height field of the arrow over the ground, on a grid.
GRID = 640
_g = np.linspace(-1.2, 1.2, GRID)
_gx, _gz = np.meshgrid(_g, _g)               # [z, x]
INNER = ROUND - polygon_sdf(_gx, _gz, CHEVRON)   # distance in from the edge (>0 inside)
HEIGHT = WALL * smoothstep(0.0, 0.018, INNER) + ROOF * smoothstep(0.0, 1.0, np.minimum(INNER, ROOF_W) / ROOF_W)
HEIGHT = np.where(INNER > 0, HEIGHT, 0.0)
_step = _g[1] - _g[0]
DH_DZ, DH_DX = np.gradient(HEIGHT, _step)


def sample(grid, x, z):
    """Bilinear sample of a grid at ground points (outside: 0)."""
    fx = (x + 1.2) / _step
    fz = (z + 1.2) / _step
    ok = (fx >= 0) & (fx < GRID - 1) & (fz >= 0) & (fz < GRID - 1)
    fx = np.clip(fx, 0, GRID - 1.001)
    fz = np.clip(fz, 0, GRID - 1.001)
    ix, iz = fx.astype(int), fz.astype(int)
    tx, tz = fx - ix, fz - iz
    v = (grid[iz, ix] * (1 - tx) * (1 - tz) + grid[iz, ix + 1] * tx * (1 - tz)
         + grid[iz + 1, ix] * (1 - tx) * tz + grid[iz + 1, ix + 1] * tx * tz)
    return np.where(ok, v, 0.0)


def camera_rays(res):
    cam = np.array([0.0, CAM_DIST * np.sin(ELEVATION), -CAM_DIST * np.cos(ELEVATION)])
    target = np.array([0.0, LIFT + 0.05, 0.0])
    fwd = target - cam
    fwd /= np.linalg.norm(fwd)
    right = np.array([1.0, 0.0, 0.0])
    up = np.cross(fwd, right)
    tan_h = VIEW / np.linalg.norm(target - cam)
    s = (np.arange(res) + 0.5) / res * 2 - 1
    px, py = np.meshgrid(s, -s)                  # row 0 = top of the picture
    d = fwd[None, None, :] + tan_h * (px[..., None] * right + py[..., None] * up)
    d /= np.linalg.norm(d, axis=2, keepdims=True)
    return cam, d.reshape(-1, 3)


CAM, DIRS = camera_rays(RES)


def render(angle):
    """Shade, highlight and coverage of the arrow turned by `angle` (CCW on screen)."""
    c, s = np.cos(angle), np.sin(angle)
    top = LIFT + WALL + ROOF + 0.01
    t0 = (CAM[1] - top) / -DIRS[:, 1]
    t1 = (CAM[1] - LIFT) / -DIRS[:, 1]
    steps = 260
    hit_t = np.full(len(DIRS), np.nan)
    prev_t = t0.copy()
    for k in range(1, steps + 1):
        t = t0 + (t1 - t0) * k / steps
        p = CAM[None, :] + DIRS * t[:, None]
        lx = p[:, 0] * c + p[:, 2] * s           # world -> arrow (turn back by angle)
        lz = -p[:, 0] * s + p[:, 2] * c
        inside = (sample(INNER, lx, lz) > 0) & (p[:, 1] <= LIFT + sample(HEIGHT, lx, lz))
        new = inside & np.isnan(hit_t)
        hit_t[new] = t[new]
        if k < steps:
            prev_t = np.where(np.isnan(hit_t), t, prev_t)
    hit = ~np.isnan(hit_t)
    # Refine the hits (binary search between the last miss and the hit).
    lo, hi = prev_t[hit], hit_t[hit]
    d = DIRS[hit]
    for _ in range(10):
        mid = (lo + hi) / 2
        p = CAM[None, :] + d * mid[:, None]
        lx = p[:, 0] * c + p[:, 2] * s
        lz = -p[:, 0] * s + p[:, 2] * c
        inside = (sample(INNER, lx, lz) > 0) & (p[:, 1] <= LIFT + sample(HEIGHT, lx, lz))
        hi = np.where(inside, mid, hi)
        lo = np.where(inside, lo, mid)
    p = CAM[None, :] + d * hi[:, None]
    lx = p[:, 0] * c + p[:, 2] * s
    lz = -p[:, 0] * s + p[:, 2] * c
    gx, gz = sample(DH_DX, lx, lz), sample(DH_DZ, lx, lz)
    # Normal in arrow space, then turned back into the world.
    nl = np.stack([-gx, np.ones_like(gx), -gz], axis=1)
    nw = np.stack([nl[:, 0] * c - nl[:, 2] * s, nl[:, 1], nl[:, 0] * s + nl[:, 2] * c], axis=1)
    nw /= np.linalg.norm(nw, axis=1, keepdims=True)
    ndl = np.clip(nw @ LIGHT, 0, 1)
    height_up = np.clip((p[:, 1] - LIFT) / WALL, 0, 1)
    wall = nw[:, 1] < 0.5
    shade = 0.30 + 0.70 * ndl
    shade = np.where(wall, shade * (0.55 + 0.45 * height_up), shade)
    view = -d
    half = LIGHT[None, :] + view
    half /= np.linalg.norm(half, axis=1, keepdims=True)
    spec = np.clip(np.sum(nw * half, axis=1), 0, 1) ** 36 * 0.85
    # A thin bright line where the bevel meets the top edge (catches the light).
    rim = np.clip(1 - np.abs(nw[:, 1] - 0.62) / 0.12, 0, 1) * np.clip(ndl - 0.3, 0, 1) * 0.45
    spec = np.clip(spec + rim, 0, 1)

    shade_img = np.zeros(len(DIRS))
    spec_img = np.zeros(len(DIRS))
    cov = hit.astype(float)
    shade_img[hit] = shade
    spec_img[hit] = spec
    return (shade_img.reshape(RES, RES), spec_img.reshape(RES, RES), cov.reshape(RES, RES))


def ground_shadow(angle):
    """Coverage of the arrow's shadow on the ground, cast along the light."""
    c, s = np.cos(angle), np.sin(angle)
    t = CAM[1] / -DIRS[:, 1]
    p = CAM[None, :] + DIRS * t[:, None]
    off = LIFT * LIGHT[[0, 2]] / LIGHT[1]
    x, z = p[:, 0] + off[0], p[:, 2] + off[1]
    lx = x * c + z * s
    lz = -x * s + z * c
    return (sample(INNER, lx, lz) > 0).astype(float).reshape(RES, RES)


def down(img):
    """Supersampled -> cell size (box filter)."""
    h, w = img.shape
    return img.reshape(h // SS, SS, w // SS, SS).mean(axis=(1, 3))


def blur(img, radius):
    im = Image.fromarray(np.uint8(np.clip(img, 0, 1) * 255), "L").filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(im, dtype=float) / 255


def margin(a, px):
    """Clear the cell's border so neighbouring cells never bleed in."""
    a = a.copy()
    a[:px, :] = 0
    a[-px:, :] = 0
    a[:, :px] = 0
    a[:, -px:] = 0
    return a


def rgba(gray, alpha):
    g = np.uint8(np.clip(gray, 0, 1) * 255)
    a = np.uint8(np.clip(alpha, 0, 1) * 255)
    return np.dstack([g, g, g, a])


def cells():
    body = np.zeros((ROWS * CELL, COLS * CELL, 4), np.uint8)
    shine = np.zeros_like(body)
    shadow = np.zeros((ROWS * SHADOW_CELL, COLS * SHADOW_CELL, 4), np.uint8)
    for i in range(FRAMES):
        angle = i / FRAMES * 2 * np.pi
        shade, spec, cov = render(angle)
        a = down(cov)
        lit = np.where(a > 0, down(shade * cov) / np.maximum(a, 1e-6), 0)
        hl = down(spec * cov)
        # Dark outline just outside the arrow, so it reads on snow and on night grass.
        ring = np.clip(blur(cov, SS * 1.1) * 2.2, 0, 1)
        ring_small = down(ring) * 0.75
        alpha = a + ring_small * (1 - a)
        gray = np.where(alpha > 0, lit * a / np.maximum(alpha, 1e-6), 0)
        alpha = margin(alpha, 2)
        sh = down(blur(ground_shadow(angle), SS * 2.2)) * 0.45
        sh_small = np.asarray(Image.fromarray(np.uint8(sh * 255), "L").resize((SHADOW_CELL, SHADOW_CELL), Image.LANCZOS),
                              dtype=float) / 255
        r, col = divmod(i, COLS)
        body[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL] = rgba(gray, alpha)
        shine[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL] = rgba(np.ones_like(hl), margin(hl, 2))
        shadow[r * SHADOW_CELL:(r + 1) * SHADOW_CELL, col * SHADOW_CELL:(col + 1) * SHADOW_CELL] = \
            rgba(np.zeros_like(sh_small), margin(sh_small, 1))
        sys.stdout.write("\r%d/%d" % (i + 1, FRAMES))
        sys.stdout.flush()
    print()
    return body, shine, shadow


def radial(size, fn):
    s = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(s, s)
    return fn(np.sqrt(x * x + y * y), x, y)


def glow():
    a = radial(64, lambda r, x, y: np.clip(1 - r, 0, 1) ** 2.2)
    return rgba(np.ones_like(a), margin(a, 1))


def ring():
    def f(r, x, y):
        core = np.exp(-((r - 0.78) / 0.035) ** 2)
        halo = np.exp(-((r - 0.78) / 0.12) ** 2) * 0.45
        return np.clip(core + halo, 0, 1)
    a = radial(128, f)
    return rgba(np.ones_like(a), margin(a, 1))


def beam():
    w, h = 32, 128
    x = (np.arange(w) + 0.5) / w * 2 - 1
    y = (np.arange(h) + 0.5) / h                 # 0 = top
    across = np.exp(-(x / 0.38) ** 2)
    up = y ** 1.6                                # bright at the bottom, gone at the top
    a = np.outer(up, across)
    a = a / a.max()
    return rgba(np.ones_like(a), margin(a, 1))


def save(name, arr):
    path = os.path.join(OUT, name + ".tga")
    Image.fromarray(arr, "RGBA").save(path)
    print("wrote", os.path.normpath(path), arr.shape[1], "x", arr.shape[0])


def main():
    os.makedirs(OUT, exist_ok=True)
    body, shine, shadow = cells()
    save("ArrowBody", body)
    save("ArrowShine", shine)
    save("ArrowShadow", shadow)
    save("ArrowGlow", glow())
    save("ArrowRing", ring())
    save("ArrowBeam", beam())


if __name__ == "__main__":
    main()
