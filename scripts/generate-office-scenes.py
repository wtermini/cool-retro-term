#!/usr/bin/env python3
#
# Copyright (c) 2026 cool-retro-term contributors
# https://github.com/Swordfish90/cool-retro-term
#
# This file is part of cool-retro-term.
#
# cool-retro-term is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
"""Draws the office mode backgrounds used by both apps.

Office mode shows the terminal as the screen of a monitor sitting on a desk.
The scenes are drawn entirely by this script from simple shapes, gradients
and noise (no photos or third-party artwork), with a fixed random seed so the
output is reproducible:

    python3 scripts/generate-office-scenes.py

writes app/qml/images/office-80s.jpg and office-90s.jpg, which the Qt app
loads from its resources and Cool Retro Term SE copies into its bundle.

Both scenes share one layout. If you change SCREEN or MONITOR, update the
same numbers in app/qml/OfficeScene.qml and
macos/Sources/CoolRetroTerm/OfficeScene.swift.

Requires Pillow and numpy.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 2400, 1500
SS = 2  # drawn at twice the size, then scaled down for smooth edges

# Where the terminal goes (x, y, width, height), a 4:3 opening.
SCREEN = (720, 250, 960, 720)
# The monitor and its stand: always kept fully in view.
MONITOR = (620, 150, 1160, 1000)
DESK_TOP = 1090      # far edge of the desk surface
DESK_FRONT = 1385    # front edge of the desk surface


def s(v):
    return int(round(v * SS))


def box(x0, y0, x1, y1):
    return [s(x0), s(y0), s(x1), s(y1)]


def noise(w, h, amount, rng, blur=0):
    n = rng.normal(0, amount, (h, w)).astype(np.float32)
    if blur:
        img = Image.fromarray(np.clip(n + 128, 0, 255).astype(np.uint8))
        img = img.filter(ImageFilter.GaussianBlur(blur))
        n = np.asarray(img, dtype=np.float32) - 128
    return n


def add(img, arr):
    a = np.asarray(img, dtype=np.float32)
    if arr.ndim == 2:
        arr = arr[:, :, None]
    return Image.fromarray(np.clip(a + arr, 0, 255).astype(np.uint8))


def vertical_gradient(w, h, top, bottom):
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    top = np.array(top, np.float32)
    bottom = np.array(bottom, np.float32)
    g = top * (1 - t) + bottom * t
    return Image.fromarray(np.repeat(g, w, axis=1).astype(np.uint8))


def shadow(base, shape_box, radius, blur, opacity, offset=(0, 0)):
    """Darkens `base` under a soft rounded rectangle."""
    mask = Image.new("L", base.size, 0)
    d = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = shape_box
    d.rounded_rectangle([x0 + s(offset[0]), y0 + s(offset[1]),
                         x1 + s(offset[0]), y1 + s(offset[1])],
                        radius=s(radius), fill=int(255 * opacity))
    mask = mask.filter(ImageFilter.GaussianBlur(s(blur)))
    black = Image.new("RGB", base.size, (0, 0, 0))
    return Image.composite(black, base, mask)


def light(base, center, radius, color, strength):
    """Adds a soft pool of light."""
    w, h = base.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.sqrt((xx - s(center[0])) ** 2 + (yy - s(center[1])) ** 2) / s(radius)
    fall = np.clip(1 - dist, 0, 1) ** 2 * strength
    return add(base, fall[:, :, None] * np.array(color, np.float32)[None, None, :])


def vignette(base, strength):
    w, h = base.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xx / w - 0.5) * 2
    dy = (yy / h - 0.5) * 2
    v = 1 - strength * np.clip(dx * dx * 0.6 + dy * dy * 0.8, 0, 1)
    a = np.asarray(base, np.float32) * v[:, :, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


# ---------------------------------------------------------------- monitor ---

def draw_monitor(img, casing, casing_dark, casing_light, rng):
    d = ImageDraw.Draw(img)
    mx, my, mw, mh = MONITOR
    sx, sy, sw, sh = SCREEN
    cx0, cy0, cx1, cy1 = mx + 20, my, mx + mw - 20, my + 925
    # Stand and foot.
    foot = box(mx + mw / 2 - 260, my + 950, mx + mw / 2 + 260, my + 995)
    img.paste(shadow(img, foot, 30, 18, 0.55, (0, 14)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box(mx + mw / 2 - 170, my + 900, mx + mw / 2 + 170, my + 970),
                        radius=s(20), fill=casing_dark)
    d.rounded_rectangle(foot, radius=s(26), fill=casing)
    d.rounded_rectangle(box(mx + mw / 2 - 255, my + 952, mx + mw / 2 + 255, my + 962),
                        radius=s(6), fill=casing_light)

    # Casing, with a soft shadow on the wall behind it.
    body = box(cx0, cy0, cx1, cy1)
    img.paste(shadow(img, body, 50, 40, 0.5, (16, 26)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(body, radius=s(46), fill=casing_dark)
    d.rounded_rectangle(box(cx0 + 6, cy0 + 4, cx1 - 6, cy1 - 12), radius=s(42), fill=casing)

    # Light from above: brighter top edge, darker towards the bottom.
    shade = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(shade)
    sd.rounded_rectangle(box(cx0 + 6, cy0 + 4, cx1 - 6, cy1 - 12), radius=s(42), fill=255)
    grad = vertical_gradient(img.size[0], img.size[1], (255, 255, 255), (0, 0, 0)).convert("L")
    top_light = Image.composite(Image.new("RGB", img.size, casing_light), img,
                                Image.fromarray((np.asarray(grad, np.float32) / 255 *
                                                 np.asarray(shade, np.float32) / 255 *
                                                 90).astype(np.uint8)))
    img.paste(top_light, (0, 0))
    d = ImageDraw.Draw(img)

    # Recessed bezel around the tube.
    bz = 34
    d.rounded_rectangle(box(sx - bz - 6, sy - bz - 6, sx + sw + bz + 6, sy + sh + bz + 6),
                        radius=s(30), fill=casing_light)
    d.rounded_rectangle(box(sx - bz, sy - bz, sx + sw + bz, sy + sh + bz),
                        radius=s(26), fill=casing_dark)
    d.rounded_rectangle(box(sx - 10, sy - 10, sx + sw + 10, sy + sh + 10),
                        radius=s(18), fill=(18, 18, 16))
    # The tube itself (covered by the terminal in the app).
    d.rectangle(box(sx, sy, sx + sw, sy + sh), fill=(12, 14, 12))

    # Chin: badge, power button and LED.
    chin_y = sy + sh + bz + 18
    d.rounded_rectangle(box(sx, chin_y, sx + 150, chin_y + 26), radius=s(5), fill=casing_dark)
    for i in range(5):
        d.rectangle(box(sx + 14 + i * 26, chin_y + 9, sx + 30 + i * 26, chin_y + 17),
                    fill=casing_light)
    bx = sx + sw - 70
    d.rounded_rectangle(box(bx, chin_y - 4, bx + 60, chin_y + 30), radius=s(8), fill=casing_dark)
    d.rounded_rectangle(box(bx + 4, chin_y, bx + 56, chin_y + 26), radius=s(6), fill=casing_light)
    d.ellipse(box(bx - 40, chin_y + 6, bx - 24, chin_y + 22), fill=(60, 220, 90))
    img = light(img, (bx - 32, chin_y + 14), 40, (40, 160, 60), 0.8)
    d = ImageDraw.Draw(img)

    # Ventilation slots along the top.
    for i in range(18):
        x = mx + 300 + i * 32
        d.rounded_rectangle(box(x, cy0 + 26, x + 14, cy0 + 70), radius=s(5), fill=casing_dark)
    return img


def draw_keyboard(img, base, keys, key_top, rng):
    kx0, ky0, kx1, ky1 = 760, 1165, 1640, 1315
    img.paste(shadow(img, box(kx0, ky0, kx1, ky1), 20, 16, 0.55, (6, 16)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box(kx0, ky0, kx1, ky1), radius=s(18), fill=base)
    d.rounded_rectangle(box(kx0 + 4, ky0 + 2, kx1 - 4, ky0 + 10), radius=s(6),
                        fill=tuple(min(255, c + 25) for c in base))
    # Rows of keys, narrowing slightly towards the back for perspective.
    rows = 5
    for r in range(rows):
        t = r / (rows - 1)
        y0 = ky0 + 22 + r * 26
        inset = 30 - 12 * t
        x = kx0 + inset
        x_end = kx1 - inset - 190
        count = 15
        kw = (x_end - x) / count
        for i in range(count):
            w = kw * (2 if (r == 4 and i == 5) else 1)
            if r == 4 and i > 5 and i < 7:
                continue
            d.rounded_rectangle(box(x + i * kw + 2, y0, x + i * kw + w - 3, y0 + 21),
                                radius=s(4), fill=keys)
            d.rounded_rectangle(box(x + i * kw + 5, y0 + 2, x + i * kw + w - 6, y0 + 14),
                                radius=s(3), fill=key_top)
        # Number pad.
        for i in range(4):
            px = kx1 - inset - 170 + i * 40
            d.rounded_rectangle(box(px, y0, px + 36, y0 + 21), radius=s(4), fill=keys)
            d.rounded_rectangle(box(px + 3, y0 + 2, px + 33, y0 + 14), radius=s(3), fill=key_top)
    # Cable to the monitor.
    d.line([(s(1200), s(ky0)), (s(1205), s(1130)), (s(1230), s(1095))],
           fill=(40, 38, 36), width=s(7))
    return img


# ------------------------------------------------------------ 80s den ---

def scene_80s(rng):
    W, H = s(WIDTH), s(HEIGHT)
    # Wood panelling: vertical planks with grain and grooves.
    img = Image.new("RGB", (W, H), (110, 70, 40))
    a = np.zeros((H, W, 3), np.float32)
    plank = s(150)
    xs = np.arange(W)
    for i, x0 in enumerate(range(0, W, plank)):
        tone = rng.uniform(-14, 14)
        a[:, x0:x0 + plank] += tone
    grain_x = rng.normal(0, 1, W).astype(np.float32)
    grain_x = np.convolve(grain_x, np.ones(s(3)) / s(3), mode="same")
    wobble = noise(W // 8, H // 8, 1, rng, blur=4)
    wobble = np.asarray(Image.fromarray(np.clip(wobble * 40 + 128, 0, 255).astype(np.uint8))
                        .resize((W, H), Image.BILINEAR), np.float32) - 128
    shifted = (xs[None, :] + wobble * 0.6).astype(np.int32) % W
    grain = grain_x[shifted] * 9
    a += grain[:, :, None] * np.array([1.0, 0.75, 0.5])
    img = add(img, a)
    d = ImageDraw.Draw(img)
    for x0 in range(0, W, plank):
        d.line([(x0, 0), (x0, H)], fill=(52, 30, 16), width=s(4))
        d.line([(x0 + s(4), 0), (x0 + s(4), H)], fill=(140, 95, 60), width=s(1))

    # A framed poster of a sunset grid, upper left.
    px0, py0, px1, py1 = 150, 140, 520, 600
    img.paste(shadow(img, box(px0, py0, px1, py1), 6, 14, 0.6, (8, 12)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle(box(px0, py0, px1, py1), fill=(30, 26, 24))
    d.rectangle(box(px0 + 18, py0 + 18, px1 - 18, py1 - 18), fill=(236, 228, 210))
    ix0, iy0, ix1, iy1 = px0 + 44, py0 + 44, px1 - 44, py1 - 120
    pw, ph = ix1 - ix0, iy1 - iy0
    art = vertical_gradient(s(pw), s(ph), (40, 20, 80), (250, 120, 70))
    ad = ImageDraw.Draw(art)
    cx, cy, r = pw / 2, ph * 0.62, 70
    for k in range(9):
        y = cy - r + k * (2 * r / 9)
        half = np.sqrt(max(r * r - (y + r / 18 - cy) ** 2, 0))
        ad.rectangle(box(cx - half, y, cx + half, y + 2 * r / 9 - 5), fill=(255, 210, 80))
    hy = ph * 0.66
    ad.rectangle(box(0, hy, pw, ph), fill=(30, 10, 50))
    for k in range(7):
        y = hy + (ph - hy) * (k / 6) ** 1.6
        ad.line([(0, s(y)), (s(pw), s(y))], fill=(255, 60, 180), width=s(2))
    for k in range(-6, 7):
        ad.line([(s(cx + k * 6), s(hy)), (s(cx + k * 60), s(ph))], fill=(255, 60, 180), width=s(2))
    img.paste(art, (s(ix0), s(iy0)))
    d = ImageDraw.Draw(img)
    for k, w in enumerate((200, 150)):
        d.rectangle(box((ix0 + ix1) / 2 - w / 2, iy1 + 26 + k * 34, (ix0 + ix1) / 2 + w / 2,
                        iy1 + 40 + k * 34), fill=(60, 50, 60))

    # A shelf with books and a cassette player, upper right.
    sx0, sx1, sy = 1840, 2300, 470
    d.rectangle(box(sx0, sy, sx1, sy + 26), fill=(72, 44, 24))
    d.rectangle(box(sx0, sy, sx1, sy + 6), fill=(120, 80, 48))
    x = sx0 + 20
    book_colors = [(150, 40, 30), (40, 70, 110), (200, 160, 60), (60, 100, 60),
                   (120, 60, 110), (180, 90, 40), (50, 50, 60)]
    for i in range(9):
        bw = rng.integers(24, 40)
        bh = rng.integers(150, 210)
        c = book_colors[i % len(book_colors)]
        d.rectangle(box(x, sy - bh, x + bw, sy), fill=c)
        d.rectangle(box(x + 4, sy - bh + 20, x + bw - 4, sy - bh + 28), fill=(220, 200, 150))
        x += bw + 3
    d.rounded_rectangle(box(x + 30, sy - 120, sx1 - 10, sy), radius=s(10), fill=(40, 38, 40))
    d.rectangle(box(x + 50, sy - 100, sx1 - 30, sy - 60), fill=(20, 20, 22))
    for k in range(4):
        d.rectangle(box(x + 50 + k * 34, sy - 45, x + 76 + k * 34, sy - 22), fill=(170, 170, 175))

    # Warm lamp light on the wall.
    img = light(img, (1200, 300), 1500, (60, 40, 15), 0.6)

    # Desk: walnut top with grain and a darker front.
    desk = np.zeros((H, W, 3), np.float32)
    top = vertical_gradient(W, s(DESK_FRONT - DESK_TOP), (96, 58, 32), (128, 80, 46))
    img.paste(top, (0, s(DESK_TOP)))
    g = noise(W // 2, s(DESK_FRONT - DESK_TOP) // 12, 1, rng, blur=1)
    g = np.asarray(Image.fromarray(np.clip(g * 30 + 128, 0, 255).astype(np.uint8))
                   .resize((W, s(DESK_FRONT - DESK_TOP)), Image.BILINEAR), np.float32) - 128
    desk[s(DESK_TOP):s(DESK_FRONT)] = g[:, :, None] * np.array([0.5, 0.35, 0.2])
    img = add(img, desk)
    d = ImageDraw.Draw(img)
    d.rectangle(box(0, DESK_TOP - 6, WIDTH, DESK_TOP), fill=(60, 34, 18))
    d.rectangle(box(0, DESK_FRONT, WIDTH, HEIGHT), fill=(70, 40, 22))
    d.rectangle(box(0, DESK_FRONT, WIDTH, DESK_FRONT + 10), fill=(150, 98, 60))
    img = light(img, (1200, 1150), 1100, (50, 32, 12), 0.5)

    # Beige monitor and keyboard.
    img = draw_monitor(img, (214, 204, 178), (170, 160, 136), (232, 225, 204), rng)
    img = draw_keyboard(img, (200, 190, 164), (176, 166, 142), (226, 218, 196), rng)
    d = ImageDraw.Draw(img)

    # Floppy disks on the right.
    for k, c in enumerate([(30, 30, 34), (40, 60, 130), (150, 40, 40)]):
        fx, fy = 1780 + k * 22, 1180 - k * 14
        poly = [(fx, fy), (fx + 190, fy - 10), (fx + 205, fy + 110), (fx + 12, fy + 122)]
        sh = Image.new("L", img.size, 0)
        ImageDraw.Draw(sh).polygon([(s(x + 6), s(y + 10)) for x, y in poly], fill=130)
        img = Image.composite(Image.new("RGB", img.size, 0), img, sh.filter(ImageFilter.GaussianBlur(s(8))))
        d = ImageDraw.Draw(img)
        d.polygon([(s(x), s(y)) for x, y in poly], fill=c)
        d.polygon([(s(fx + 50), s(fy - 2)), (s(fx + 130), s(fy - 7)), (s(fx + 133), s(fy + 30)),
                   (s(fx + 53), s(fy + 35))], fill=(175, 175, 180))
        d.polygon([(s(fx + 40), s(fy + 62)), (s(fx + 175), s(fy + 55)), (s(fx + 181), s(fy + 104)),
                   (s(fx + 44), s(fy + 112))], fill=(235, 230, 215))

    # Coffee mug.
    mx, my = 2030, 1010
    img.paste(shadow(img, box(mx - 10, my + 150, mx + 140, my + 185), 40, 12, 0.6), (0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse(box(mx + 100, my + 40, mx + 175, my + 125), outline=(190, 70, 40), width=s(16))
    d.rounded_rectangle(box(mx, my, mx + 130, my + 170), radius=s(16), fill=(200, 76, 44))
    d.rectangle(box(mx + 14, my + 8, mx + 30, my + 160), fill=(225, 110, 75))
    d.ellipse(box(mx, my - 14, mx + 130, my + 18), fill=(150, 50, 28))
    d.ellipse(box(mx + 10, my - 8, mx + 120, my + 12), fill=(60, 34, 18))

    # Potted plant on the left.
    img = draw_plant(img, 330, 1180, rng, pot=(150, 80, 50), pot_rim=(175, 98, 64),
                     leaf=((50, 110, 50), (80, 150, 70)))
    # Desk lamp light pool plus a gentle vignette.
    img = vignette(img, 0.45)
    return img


def draw_plant(img, x, base_y, rng, pot, pot_rim, leaf):
    img.paste(shadow(img, box(x - 120, base_y - 10, x + 120, base_y + 30), 40, 14, 0.6), (0, 0))
    d = ImageDraw.Draw(img)
    # Leaves: long ellipses rotated around the stem.
    leaves = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for i in range(26):
        ang = rng.uniform(-150, -30)
        length = rng.uniform(220, 380)
        width = length * 0.22
        layer = Image.new("RGBA", (s(length * 2), s(length * 2)), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        c = leaf[i % 2]
        ld.ellipse([s(length), s(length - width / 2), s(length * 2), s(length + width / 2)],
                   fill=c + (255,))
        ld.line([s(length), s(length), s(length * 2), s(length)],
                fill=tuple(min(255, v + 30) for v in c) + (255,), width=s(3))
        layer = layer.rotate(-ang, resample=Image.BICUBIC)
        leaves.alpha_composite(layer, (s(x - length), s(base_y - 220 - length)))
    img = img.convert("RGBA")
    img.alpha_composite(leaves)
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    d.polygon([(s(x - 110), s(base_y - 230)), (s(x + 110), s(base_y - 230)),
               (s(x + 85), s(base_y)), (s(x - 85), s(base_y))], fill=pot)
    d.rectangle(box(x - 122, base_y - 250, x + 122, base_y - 215), fill=pot_rim)
    return img


# --------------------------------------------------------- 90s cubicle ---

def scene_90s(rng):
    W, H = s(WIDTH), s(HEIGHT)
    # Fabric partition: blue-grey with a fine woven texture.
    img = vertical_gradient(W, H, (104, 112, 128), (86, 94, 110))
    fine = noise(W, H, 9, rng)
    weave = (np.sin(np.arange(W) * 2.2)[None, :] * np.sin(np.arange(H) * 2.2)[:, None]) * 3
    img = add(img, fine + weave.astype(np.float32))
    # Soft, large-scale mottling of the fabric.
    blotch = noise(W // 16, H // 16, 1, rng, blur=2)
    blotch = Image.fromarray(np.clip(blotch * 30 + 128, 0, 255).astype(np.uint8))
    blotch = blotch.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(s(8)))
    img = add(img, (np.asarray(blotch, np.float32) - 128) * 0.6)
    d = ImageDraw.Draw(img)
    # Panel seams and the aluminium trim along the top.
    for x in (790, 1610):
        d.rectangle(box(x - 7, 0, x + 7, DESK_TOP), fill=(150, 154, 160))
        d.rectangle(box(x - 7, 0, x - 3, DESK_TOP), fill=(190, 194, 200))
    d.rectangle(box(0, 0, WIDTH, 36), fill=(160, 164, 170))
    d.rectangle(box(0, 30, WIDTH, 40), fill=(110, 114, 120))

    # A pinned calendar, upper left.
    cx0, cy0, cx1, cy1 = 160, 140, 560, 640
    img.paste(shadow(img, box(cx0, cy0, cx1, cy1), 4, 10, 0.5, (6, 10)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle(box(cx0, cy0, cx1, cy1), fill=(244, 242, 236))
    d.rectangle(box(cx0 + 20, cy0 + 20, cx1 - 20, cy0 + 220), fill=(70, 120, 170))
    d.polygon([(s(cx0 + 20), s(cy0 + 220)), (s(cx0 + 150), s(cy0 + 110)), (s(cx0 + 240), s(cy0 + 180)),
               (s(cx0 + 300), s(cy0 + 130)), (s(cx1 - 20), s(cy0 + 200)), (s(cx1 - 20), s(cy0 + 220))],
              fill=(60, 90, 70))
    d.ellipse(box(cx1 - 110, cy0 + 50, cx1 - 60, cy0 + 100), fill=(250, 230, 150))
    d.rectangle(box(cx0 + 20, cy0 + 238, cx1 - 20, cy0 + 262), fill=(200, 60, 50))
    gw = (cx1 - cx0 - 40) / 7
    for row in range(5):
        for col in range(7):
            gx = cx0 + 20 + col * gw
            gy = cy0 + 276 + row * 42
            d.rectangle(box(gx + 2, gy, gx + gw - 2, gy + 38), outline=(190, 186, 178), width=s(2))
            if (row, col) in ((1, 3), (3, 5)):
                d.ellipse(box(gx + 8, gy + 3, gx + gw - 8, gy + 35), outline=(210, 40, 40), width=s(4))
    d.ellipse(box((cx0 + cx1) / 2 - 10, cy0 + 4, (cx0 + cx1) / 2 + 10, cy0 + 24), fill=(220, 40, 40))

    # A company memo and a phone list on the right partition.
    for k, (x0, y0, rot) in enumerate(((1850, 160, 3), (2080, 300, -4))):
        page = Image.new("RGBA", (s(230), s(300)), (250, 250, 246, 255))
        pd = ImageDraw.Draw(page)
        for line in range(12):
            w = rng.integers(110, 190)
            pd.rectangle([s(20), s(40 + line * 20), s(20 + w), s(46 + line * 20)], fill=(150, 150, 160, 255))
        pd.rectangle([s(20), s(14), s(120), s(26)], fill=(40, 60, 120, 255))
        page = page.rotate(rot, expand=True, resample=Image.BICUBIC)
        sh = Image.new("L", img.size, 0)
        sh.paste(page.split()[3].point(lambda v: v * 0.5), (s(x0 + 6), s(y0 + 10)))
        img = Image.composite(Image.new("RGB", img.size, 0), img, sh.filter(ImageFilter.GaussianBlur(s(8))))
        img = img.convert("RGBA")
        img.alpha_composite(page, (s(x0), s(y0)))
        img = img.convert("RGB")
        d = ImageDraw.Draw(img)
        d.ellipse(box(x0 + 100, y0 + 4, x0 + 118, y0 + 22), fill=(40, 120, 220))

    # Cool fluorescent light from above.
    img = light(img, (1200, -200), 1700, (40, 46, 56), 0.7)

    # Light grey laminate desk with a dark edge band.
    top = vertical_gradient(W, s(DESK_FRONT - DESK_TOP), (176, 174, 168), (204, 202, 196))
    img.paste(top, (0, s(DESK_TOP)))
    speck = noise(W, s(DESK_FRONT - DESK_TOP), 5, rng)
    full = np.zeros((H, W), np.float32)
    full[s(DESK_TOP):s(DESK_FRONT)] = speck
    img = add(img, full)
    d = ImageDraw.Draw(img)
    d.rectangle(box(0, DESK_TOP - 5, WIDTH, DESK_TOP), fill=(120, 118, 114))
    d.rectangle(box(0, DESK_FRONT, WIDTH, HEIGHT), fill=(60, 60, 64))
    d.rectangle(box(0, DESK_FRONT, WIDTH, DESK_FRONT + 8), fill=(110, 110, 116))

    # Mouse mat and mouse, right of the keyboard.
    mm = box(1700, 1180, 2010, 1340)
    img.paste(shadow(img, mm, 14, 8, 0.4, (2, 6)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(mm, radius=s(14), fill=(40, 70, 130))
    d.rounded_rectangle(box(1715, 1192, 1995, 1328), radius=s(10), outline=(80, 120, 190), width=s(3))
    img.paste(shadow(img, box(1820, 1210, 1900, 1320), 40, 8, 0.6, (4, 8)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box(1820, 1210, 1900, 1320), radius=s(38), fill=(214, 212, 204))
    d.line([(s(1860), s(1212)), (s(1860), s(1255))], fill=(170, 168, 160), width=s(3))
    d.line([(s(1860), s(1210)), (s(1850), s(1150)), (s(1700), s(1110))], fill=(60, 60, 60), width=s(5))

    # Platinum monitor and keyboard.
    img = draw_monitor(img, (200, 198, 190), (156, 154, 148), (224, 222, 214), rng)
    img = draw_keyboard(img, (190, 188, 180), (168, 166, 158), (214, 212, 204), rng)
    d = ImageDraw.Draw(img)

    # Sticky notes on the monitor casing and the partition.
    for x0, y0, rot, c in ((640, 300, 6, (250, 236, 120)), (1700, 640, -5, (250, 236, 120)),
                           (1700, 820, 3, (255, 170, 190)), (300, 760, -3, (180, 230, 160))):
        note = Image.new("RGBA", (s(110), s(110)), c + (255,))
        nd = ImageDraw.Draw(note)
        for line in range(3):
            nd.line([s(14), s(30 + line * 22), s(14 + rng.integers(50, 85)), s(32 + line * 22)],
                    fill=(60, 60, 140, 255), width=s(3))
        note = note.rotate(rot, expand=True, resample=Image.BICUBIC)
        img = img.convert("RGBA")
        img.alpha_composite(note, (s(x0), s(y0)))
        img = img.convert("RGB")

    # A desk phone on the left and a stack of paper.
    px, py = 220, 1150
    img.paste(shadow(img, box(px, py, px + 330, py + 190), 30, 14, 0.6, (6, 14)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box(px, py, px + 330, py + 190), radius=s(30), fill=(52, 52, 56))
    d.rounded_rectangle(box(px + 10, py - 40, px + 320, py + 40), radius=s(36), fill=(66, 66, 70))
    for r in range(4):
        for c in range(3):
            d.rounded_rectangle(box(px + 160 + c * 48, py + 64 + r * 30, px + 196 + c * 48, py + 86 + r * 30),
                                radius=s(5), fill=(190, 190, 196))
    d.rectangle(box(px + 30, py + 70, px + 130, py + 110), fill=(120, 150, 110))
    for k in range(8):
        y = 1290 - k * 7
        d.rectangle(box(560 + (k % 3) * 3, y, 690 + (k % 3) * 3, y + 6), fill=(242, 242, 238))
        d.line([(s(560), s(y + 6)), (s(693), s(y + 6))], fill=(200, 200, 196), width=s(1))

    img = vignette(img, 0.35)
    return img


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(repo, "app", "qml", "images")
    os.makedirs(out_dir, exist_ok=True)
    for name, painter, seed in (("office-80s.jpg", scene_80s, 1984),
                                ("office-90s.jpg", scene_90s, 1995)):
        rng = np.random.default_rng(seed)
        img = painter(rng).resize((WIDTH, HEIGHT), Image.LANCZOS)
        path = os.path.join(out_dir, name)
        img.save(path, quality=86, optimize=True, progressive=True)
        print("wrote", os.path.relpath(path, repo), file=sys.stderr)


if __name__ == "__main__":
    main()
