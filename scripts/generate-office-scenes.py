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
"""Builds the 3D rooms for office mode, shared by both apps.

Office mode shows the terminal as the screen of a monitor on a desk in a 3D
room you can look around. This script writes, into app/qml/office/:

- office-<room>-<monitor>.json, for the 80s and 90s rooms with a standard
  (4:3) or widescreen (16:10) monitor: the rooms, as a list of simple shapes
  (boxes, cylinders, spheres and flat panels) with materials, plus the
  lights, the camera and where the screen is;
- the textures they use (wood, carpet, fabric, a poster and so on);
- office-<room>-<monitor>.jpg: the rooms seen straight on, used when
  3D isn't available or is turned off. These are rendered from the rooms by
  scripts/render-office-pictures.sh (with Qt Quick 3D), after this script.

The Qt app builds the rooms with Qt Quick 3D (app/qml/OfficeScene.qml) and
Cool Retro Term SE with SceneKit (macos/Sources/CoolRetroTerm/OfficeScene.swift),
both from these files, so the rooms look the same in each.

Everything is drawn by this script from shapes, gradients and noise, with a
fixed random seed (no photos or third-party artwork):

    python3 scripts/generate-office-scenes.py

Scene format: units are centimetres, Y is up, and the camera starts out
looking down -Z. Shapes are unit sized and scaled by "size": a box is
1 x 1 x 1, a cylinder is 1 across and 1 high, a sphere is 1 across, and a
"plane" is 1 x 1 in the XY plane, facing +Z. "rotation" is a quaternion
[x, y, z, w]. "opacity" (0 to 1, when present) makes an object see-through.
The object with "live": "calendar" is the wall calendar, which the apps
draw from the desk data (office-desk.json) instead of its texture, which is
kept for the 2D pictures. "noteSpots" are the places for sticky notes, in
the order they're filled (the desk has up to that many notes): position,
size (the note is square, lying in its XY plane, facing +Z) and rotation.
The first three have a "texture", the scribbled note drawn there in the 2D
pictures. Light intensities are in Qt Quick 3D's brightness units
(1 = its default).

Requires Pillow and numpy.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TEX = 512


# ---------------------------------------------------------------- helpers ---

def quat(x=0.0, y=0.0, z=0.0):
    """Quaternion [x, y, z, w]: rotate by x degrees about X, then y about Y,
    then z about Z (fixed axes)."""
    def axis(ax, deg):
        h = math.radians(deg) / 2
        q = [0.0, 0.0, 0.0, math.cos(h)]
        q[ax] = math.sin(h)
        return q

    def mul(a, b):
        ax, ay, az, aw = a
        bx, by, bz, bw = b
        return [aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz]

    q = mul(axis(2, z), mul(axis(1, y), axis(0, x)))
    return [round(v, 6) for v in q]


class Scene:
    def __init__(self, name):
        self.name = name
        self.objects = []
        self.lights = []
        self.spots = {}   # where sticky notes can go, by name

    def spot(self, name, position, size, rotation=(0, 0, 0), texture=None):
        """A place for a sticky note. `texture` is the scribbled note drawn
        there in the 2D pictures (only the first three places have one)."""
        spot = {"position": [round(float(v), 3) for v in position], "size": round(float(size), 2),
                "rotation": quat(*rotation)}
        if texture:
            spot["texture"] = texture
        self.spots[name] = spot

    def add(self, shape, position, size, color="#808080", rotation=(0, 0, 0), texture=None,
            repeat=(1, 1), roughness=0.7, metalness=0.0, emissive=None, shadows=True, group=None,
            live=None, opacity=None):
        obj = {"shape": shape,
               "position": [round(float(v), 3) for v in position],
               "size": [round(float(v), 3) for v in size],
               "rotation": quat(*rotation),
               "color": color,
               "roughness": roughness,
               "metalness": metalness,
               "shadows": shadows}
        if texture:
            obj["texture"] = texture
            obj["repeat"] = [round(float(v), 3) for v in repeat]
        if emissive:
            obj["emissive"] = emissive
        if opacity is not None:
            obj["opacity"] = opacity   # see-through: glass, water, bubbles
        if group:
            obj["group"] = group   # e.g. "sticky-notes", which can be turned off
        if live:
            obj["live"] = live     # drawn by the app from the desk data; see below
        self.objects.append(obj)
        return obj

    def box(self, center, size, color, **kw):
        return self.add("box", center, size, color, **kw)

    def cylinder(self, center, diameter, height, color, **kw):
        return self.add("cylinder", center, (diameter, height, diameter), color, **kw)

    def sphere(self, center, size, color, **kw):
        return self.add("sphere", center, size, color, **kw)

    def plane(self, center, width, height, color="#ffffff", **kw):
        return self.add("plane", center, (width, height, 1), color, **kw)


def tile_noise(size, cells, rng, amount):
    """Smooth noise that wraps around, for tiling textures."""
    base = rng.normal(0, 1, (cells, cells)).astype(np.float32)
    big = np.tile(base, (3, 3))
    img = Image.fromarray(np.clip(big * 40 + 128, 0, 255).astype(np.uint8))
    img = img.resize((size * 3, size * 3), Image.BICUBIC)
    a = np.asarray(img, np.float32)[size:2 * size, size:2 * size] - 128
    return a / 40 * amount


def from_array(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def save(img, out_dir, name):
    path = os.path.join(out_dir, name)
    if name.endswith(".png"):
        img.save(path, optimize=True)
    else:
        img.convert("RGB").save(path, quality=85, optimize=True)
    return name


# --------------------------------------------------------------- textures ---

def wood_panel(rng):
    """Vertical tongue-and-groove panelling, 4 planks; tiles."""
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array([112, 72, 42], np.float32)
    plank = TEX // 4
    xs = np.arange(TEX)[None, :] + tile_noise(TEX, 6, rng, 6)
    grain = np.sin(xs * 0.9 + tile_noise(TEX, 12, rng, 3)) * 5 + tile_noise(TEX, 64, rng, 4)
    a += grain[:, :, None] * np.array([1.0, 0.7, 0.45])
    for i in range(4):
        a[:, i * plank:(i + 1) * plank] += rng.uniform(-14, 10)
        a[:, i * plank:i * plank + 4] = [52, 30, 16]
        a[:, i * plank + 4:i * plank + 6] += 25
    return from_array(a)


def walnut(rng):
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array([104, 64, 36], np.float32)
    ys = np.arange(TEX)[:, None] + tile_noise(TEX, 4, rng, 10)
    grain = np.sin(ys * 0.35 + tile_noise(TEX, 8, rng, 2)) * 9 + tile_noise(TEX, 96, rng, 5)
    a += grain[:, :, None] * np.array([1.0, 0.65, 0.4])
    return from_array(a)


def carpet(rng, color):
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array(color, np.float32)
    fine = rng.normal(0, 16, (TEX, TEX)).astype(np.float32)
    fine = np.asarray(from_array(fine + 128).filter(ImageFilter.GaussianBlur(1.2)), np.float32) - 128
    a += (fine * 1.6 + tile_noise(TEX, 8, rng, 10))[:, :, None]
    return from_array(a)


def fabric(rng, color):
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array(color, np.float32)
    xs = np.arange(TEX)
    weave = (np.sin(xs * math.pi / 2)[None, :] * np.sin(xs * math.pi / 2)[:, None]) * 4
    a += (rng.normal(0, 7, (TEX, TEX)) + weave + tile_noise(TEX, 16, rng, 8))[:, :, None]
    return from_array(a)


def laminate(rng, color):
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array(color, np.float32)
    a += (rng.normal(0, 4, (TEX, TEX)) + tile_noise(TEX, 32, rng, 3))[:, :, None]
    return from_array(a)


def ceiling_tile(rng):
    a = np.zeros((TEX, TEX, 3), np.float32) + 222
    a[rng.random((TEX, TEX)) < 0.012] -= 70
    a = np.asarray(from_array(a).filter(ImageFilter.GaussianBlur(0.8)), np.float32)
    a[:6, :] -= 60
    a[:, :6] -= 60
    return from_array(a)


def poster_80s():
    w, h = 384, 512
    img = Image.new("RGB", (w, h), (236, 228, 210))
    x0, y0, x1, y1 = 32, 32, w - 32, h - 110
    t = np.linspace(0, 1, y1 - y0)[:, None, None]
    sky = np.array([40, 20, 80]) * (1 - t) + np.array([250, 120, 70]) * t
    img.paste(from_array(np.repeat(sky, x1 - x0, axis=1)), (x0, y0))
    d = ImageDraw.Draw(img)
    cx, cy, r = w / 2, y0 + (y1 - y0) * 0.6, 70
    for k in range(9):
        y = cy - r + k * (2 * r / 9)
        half = math.sqrt(max(r * r - (y + r / 18 - cy) ** 2, 0))
        d.rectangle([cx - half, y, cx + half, y + 2 * r / 9 - 5], fill=(255, 210, 80))
    hy = y0 + (y1 - y0) * 0.66
    d.rectangle([x0, hy, x1, y1], fill=(30, 10, 50))
    for k in range(7):
        y = hy + (y1 - hy) * (k / 6) ** 1.6
        d.line([(x0, y), (x1, y)], fill=(255, 60, 180), width=2)
    for k in range(-7, 8):
        d.line([(cx + k * 5, hy), (cx + k * 45, y1)], fill=(255, 60, 180), width=2)
    d.rectangle([x0, y0, x1, y1], outline=(236, 228, 210), width=1)
    img.paste((236, 228, 210), (0, 0, x0, h))
    img.paste((236, 228, 210), (x1, 0, w, h))
    d = ImageDraw.Draw(img)
    d.rectangle([w / 2 - 100, y1 + 30, w / 2 + 100, y1 + 46], fill=(60, 50, 60))
    d.rectangle([w / 2 - 70, y1 + 60, w / 2 + 70, y1 + 72], fill=(90, 80, 90))
    return img


def calendar_90s():
    w, h = 384, 480
    img = Image.new("RGB", (w, h), (244, 242, 236))
    d = ImageDraw.Draw(img)
    d.rectangle([16, 16, w - 16, 200], fill=(70, 120, 170))
    d.polygon([(16, 200), (130, 100), (210, 165), (270, 120), (w - 16, 180), (w - 16, 200)], fill=(60, 90, 70))
    d.ellipse([w - 100, 40, w - 54, 86], fill=(250, 230, 150))
    d.rectangle([16, 214, w - 16, 238], fill=(200, 60, 50))
    gw = (w - 32) / 7
    for row in range(5):
        for col in range(7):
            gx = 16 + col * gw
            gy = 250 + row * 44
            d.rectangle([gx + 2, gy, gx + gw - 2, gy + 40], outline=(190, 186, 178), width=2)
            if (row, col) in ((1, 3), (3, 5)):
                d.ellipse([gx + 6, gy + 3, gx + gw - 6, gy + 37], outline=(210, 40, 40), width=3)
    return img


def memo(rng):
    w, h = 256, 330
    img = Image.new("RGB", (w, h), (250, 250, 246))
    d = ImageDraw.Draw(img)
    d.rectangle([22, 18, 130, 30], fill=(40, 60, 120))
    for line in range(13):
        d.rectangle([22, 48 + line * 20, 22 + int(rng.integers(120, 210)), 54 + line * 20], fill=(150, 150, 160))
    return img


def sticky(rng, color):
    img = Image.new("RGB", (128, 128), color)
    d = ImageDraw.Draw(img)
    for line in range(3):
        d.line([(16, 36 + line * 26), (16 + int(rng.integers(60, 96)), 38 + line * 26)], fill=(60, 60, 140), width=4)
    return img


def keyboard_top(base, key, key_top):
    w, h = 512, 180
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    kw, gap = 22, 4
    for r in range(6):
        y = 12 + r * 27
        x = 12
        for i in range(15):
            if r == 5 and 5 < i < 9:
                continue
            ww = kw * 4 + gap * 3 if (r == 5 and i == 5) else kw
            d.rounded_rectangle([x, y, x + ww, y + 23], radius=3, fill=key)
            d.rounded_rectangle([x + 3, y + 2, x + ww - 3, y + 16], radius=3, fill=key_top)
            x += ww + gap
        for i in range(4):
            px = w - 12 - (4 - i) * (kw + gap)
            d.rounded_rectangle([px, y, px + kw, y + 23], radius=3, fill=key)
            d.rounded_rectangle([px + 3, y + 2, px + kw - 3, y + 16], radius=3, fill=key_top)
    return img


def floppy_label(color):
    img = Image.new("RGB", (128, 128), color)
    d = ImageDraw.Draw(img)
    d.rectangle([36, 0, 92, 40], fill=(175, 175, 182))
    d.rectangle([62, 6, 76, 34], fill=color)
    d.rectangle([18, 62, 110, 124], fill=(236, 232, 218))
    for k in range(3):
        d.line([(26, 78 + k * 14), (96, 78 + k * 14)], fill=(70, 70, 160), width=2)
    return img


def blinds():
    """Venetian blinds with daylight between the slats (used as a glow)."""
    img = Image.new("RGB", (256, 384), (255, 244, 220))
    d = ImageDraw.Draw(img)
    for k in range(0, 384, 16):
        d.rectangle([0, k, 256, k + 11], fill=(214, 204, 182))
        d.line([(0, k + 11), (256, k + 11)], fill=(150, 140, 120), width=2)
    return img


def carpet_tiles(rng):
    """Grey-blue commercial carpet tiles, two to a texture."""
    a = np.asarray(carpet(rng, (88, 94, 108)), np.float32).copy()
    half = TEX // 2
    for k in (0, half):
        a[:, k:k + 3] -= 18
        a[k:k + 3, :] -= 18
    a[:half, half:] += 6
    a[half:, :half] += 6
    return from_array(a)


def font(size):
    return ImageFont.load_default(size=size)


def whiteboard(rng):
    """A whiteboard with a meeting's leftovers in marker."""
    w, h = 768, 512
    img = Image.new("RGB", (w, h), (246, 247, 248))
    d = ImageDraw.Draw(img)
    for _ in range(6):   # ghosts of old writing
        x, y = int(rng.integers(30, w - 200)), int(rng.integers(30, h - 60))
        d.line([(x, y), (x + int(rng.integers(80, 200)), y + int(rng.integers(-8, 8)))], fill=(226, 228, 232), width=6)
    d.text((40, 30), "Q3 GOALS", fill=(30, 70, 180), font=font(48))
    for i, (label, value) in enumerate((("Sales", 0.6), ("Web", 0.85), ("Support", 0.45))):
        y = 120 + i * 70
        d.text((40, y), label, fill=(30, 70, 180), font=font(30))
        d.rectangle([200, y + 6, 200 + int(300 * value), y + 36], outline=(30, 70, 180), width=4)
    d.line([(560, 340), (600, 250), (650, 290), (720, 150)], fill=(200, 40, 40), width=6)
    d.polygon([(720, 150), (700, 160), (715, 175)], fill=(200, 40, 40))
    d.text((40, 360), "Ship it by Friday!", fill=(200, 40, 40), font=font(36))
    d.ellipse([470, 420, 520, 470], outline=(40, 140, 60), width=5)
    return img


def poster_synergy():
    """A framed motivational poster: a mountain at dawn and one big word."""
    w, h = 384, 512
    img = Image.new("RGB", (w, h), (14, 14, 16))
    x0, y0, x1, y1 = 28, 28, w - 28, h - 150
    t = np.linspace(0, 1, y1 - y0)[:, None, None]
    sky = np.array([30, 40, 90]) * (1 - t) + np.array([240, 150, 90]) * t
    img.paste(from_array(np.repeat(sky, x1 - x0, axis=1)), (x0, y0))
    d = ImageDraw.Draw(img)
    d.polygon([(x0, y1), (x0 + 90, y0 + 150), (x0 + 150, y0 + 200), (x0 + 210, y0 + 110), (x1, y1)], fill=(40, 34, 52))
    d.polygon([(x0 + 180, y0 + 150), (x0 + 210, y0 + 110), (x0 + 240, y0 + 150)], fill=(236, 236, 244))
    d.rectangle([x0, y0, x1, y1], outline=(200, 200, 206), width=2)
    title = font(44)
    tw = d.textlength("SYNERGY", font=title)
    d.text(((w - tw) / 2, y1 + 30), "SYNERGY", fill=(236, 236, 240), font=title)
    d.rectangle([w / 2 - 120, y1 + 96, w / 2 + 120, y1 + 102], fill=(150, 150, 156))
    d.rectangle([w / 2 - 90, y1 + 112, w / 2 + 90, y1 + 118], fill=(150, 150, 156))
    return img


def sky_window(rng):
    """The view out of a big window, as everyone remembers the 2000s: a
    deep blue sky, puffy clouds, a glossy green hill and a glowing sun."""
    w, h = 1024, 512
    t = np.linspace(0, 1, h)[:, None, None]
    sky = np.array([40, 120, 235]) * (1 - t) + np.array([190, 235, 255]) * t
    a = np.repeat(sky, w, axis=1).astype(np.float32)
    # Sun glow, top right.
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    glow = np.clip(1 - np.sqrt((xx - 820) ** 2 + (yy - 90) ** 2) / 260, 0, 1) ** 2
    a += glow[:, :, None] * np.array([120, 110, 60])
    img = from_array(a)
    clouds = Image.new("L", (w, h), 0)
    cd = ImageDraw.Draw(clouds)
    for _ in range(14):
        cx, cy = float(rng.uniform(0, w)), float(rng.uniform(40, 230))
        for _ in range(6):
            rx, ry = float(rng.uniform(30, 70)), float(rng.uniform(18, 34))
            ox, oy = float(rng.uniform(-60, 60)), float(rng.uniform(-14, 14))
            cd.ellipse([cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy + ry], fill=255)
    clouds = clouds.filter(ImageFilter.GaussianBlur(10))
    img = Image.composite(Image.new("RGB", (w, h), (255, 255, 255)), img, clouds.point(lambda v: v * 0.85))
    # A rolling green hill with a sheen along its crest.
    xs = np.arange(w)
    crest = 330 - 60 * np.sin(xs / w * math.pi * 1.2 + 0.3) - 14 * np.sin(xs / 90.0)
    a = np.asarray(img, np.float32).copy()
    for x in range(w):
        c = int(crest[x])
        depth = np.arange(h - c)[:, None]
        green = np.array([60, 170, 40]) * (1 - depth / (h - c) * 0.45) + np.array([0, 20, 0])
        a[c:, x] = green[:, :]
        a[c:c + 10, x] += np.linspace(70, 0, min(10, h - c))[:, None] * np.array([1, 1, 0.6])
    img = from_array(a)
    d = ImageDraw.Draw(img, "RGBA")
    for k, (fx, fy, fr) in enumerate(((700, 180, 30), (600, 260, 16), (520, 320, 40))):   # lens flare
        d.ellipse([fx - fr, fy - fr, fx + fr, fy + fr], fill=(255, 255, 255, 40 + 15 * k))
    return img


def aurora(rng):
    """Glowing green and blue swooshes on a dark teal panel."""
    w, h = 1024, 512
    a = np.zeros((h, w, 3), np.float32) + np.array([6, 40, 60], np.float32)
    xs = np.arange(w)[None, :]
    ys = np.arange(h)[:, None]
    for k, color in enumerate(([60, 255, 160], [60, 200, 255], [180, 255, 120], [120, 160, 255])):
        center = h * (0.35 + 0.12 * k) + 70 * np.sin(xs / w * math.pi * (1.3 + 0.3 * k) + k)
        band = np.exp(-((ys - center) / (18 + 8 * k)) ** 2)
        a += band[:, :, None] * np.array(color, np.float32) * 0.8
    return from_array(a).filter(ImageFilter.GaussianBlur(2))


def glossy_tiles():
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array([246, 250, 253], np.float32)
    a[:, :3] = [214, 230, 240]
    a[:3, :] = [214, 230, 240]
    return from_array(a)


def raised_floor():
    """Computer-room raised floor tiles: light grey, 60 cm square."""
    a = np.zeros((TEX, TEX, 3), np.float32) + np.array([200, 202, 198], np.float32)
    a[:, :4] = [140, 142, 138]
    a[:4, :] = [140, 142, 138]
    a[18:30, 18:30] = [170, 172, 168]   # the lifting point
    return from_array(a)


def greenbar():
    """Fan-fold printer paper with green bars and sprocket holes."""
    w, h = 256, 384
    img = Image.new("RGB", (w, h), (250, 250, 244))
    d = ImageDraw.Draw(img)
    for k in range(0, h, 48):
        d.rectangle([20, k, w - 20, k + 24], fill=(206, 234, 206))
    for k in range(8, h, 16):
        d.ellipse([5, k, 13, k + 8], fill=(220, 220, 214))
        d.ellipse([w - 13, k, w - 5, k + 8], fill=(220, 220, 214))
    for k in range(12):
        y = 10 + k * 30
        d.rectangle([30, y, 30 + int(80 + 100 * ((k * 37) % 7) / 7), y + 5], fill=(90, 90, 96))
    return img


def ceiling_light():
    img = Image.new("RGB", (256, 256), (255, 255, 250))
    d = ImageDraw.Draw(img)
    for k in range(0, 256, 16):
        d.line([(k, 0), (k, 256)], fill=(226, 230, 236), width=2)
        d.line([(0, k), (256, k)], fill=(226, 230, 236), width=2)
    d.rectangle([0, 0, 255, 255], outline=(190, 192, 196), width=8)
    return img


# -------------------------------------------------------------- the rooms ---

DESK_Y = 75                        # height of the desk surface


class Monitor:
    """The monitor on the desk: the screen's size and where it is, and the
    outline that must stay in view in the 2D picture."""

    def __init__(self, name, w, h, y, z, half_width, top, distance):
        self.name = name
        self.w, self.h = w, h          # visible tube
        self.y, self.z = y, z          # middle of the screen
        self.half_width = half_width   # of the casing
        self.top = top                 # top of the casing
        self.distance = distance       # starting camera distance


# A 14-inch 4:3 monitor on a swivel stand.
STANDARD = Monitor("standard", 29.6, 22.2, DESK_Y + 27.5, -41.6, 20, DESK_Y + 44, 95)
# A 24-inch 16:10 workstation monitor on a base plate: big, deep and heavy.
WIDE = Monitor("wide", 47.0, 29.4, DESK_Y + 31, -29.6, 29, DESK_Y + 53.5, 110)

# Flat panels for the 2000s rooms: a 17-inch 4:3 LCD and a 22-inch 16:10 one,
# thin, on a neck and a round foot.
LCD_STANDARD = Monitor("standard", 34.5, 25.9, DESK_Y + 9 + 4 + 25.9 / 2, -38, 19.5, DESK_Y + 9 + 4 + 25.9 + 2.5, 92)
LCD_STANDARD.lcd = (2.2, 2.5, 4)    # bezel: sides, top, bottom
LCD_WIDE = Monitor("wide", 47.4, 29.6, DESK_Y + 9 + 3.5 + 29.6 / 2, -38, 25.7, DESK_Y + 9 + 3.5 + 29.6 + 2.2, 106)
LCD_WIDE.lcd = (2.0, 2.2, 3.5)


# Video terminals for the 70s room: one smooth off-white piece with the
# keyboard built into a sloped deck at the front and the screen deep in a
# bevelled recess (Widescreen is a wide, 132-column-style model).
TERM_BEVEL, TERM_DEPTH, TERM_TOP = 5.0, 3.0, 7.0   # recess width and depth; face above it


def terminal_monitor(name, w, h, z, distance):
    sy = DESK_Y + 15 + h / 2          # screen bottom 15 cm above the desk, over the deck
    return Monitor(name, w, h, sy, z, (w + 20) / 2, sy + h / 2 + TERM_BEVEL + TERM_TOP, distance)


TERM_STANDARD = terminal_monitor("standard", 29.6, 22.2, -48, 98)
TERM_WIDE = terminal_monitor("wide", 47.0, 29.4, -48, 112)


def keyboard_terminal():
    """A terminal's built-in keyboard: grey keys, dark grey modifiers and a
    long dark space bar, a numeric keypad on the right."""
    w, h = 640, 240
    img = Image.new("RGB", (w, h), (226, 222, 210))
    d = ImageDraw.Draw(img)
    light, dark, top_light, top_dark = (150, 152, 150), (64, 66, 70), (176, 178, 176), (86, 88, 92)
    kw, gap = 24, 5
    for r in range(5):
        y = 14 + r * 34
        x = 14 + r * 6
        for i in range(14 - (r == 4) * 6):
            wide = 6 if (r == 4 and i == 2) else 1
            width = kw * wide + gap * (wide - 1)
            is_dark = r == 0 or i in (0, 13) or (r == 4 and i == 2) or (i > 10 and r % 2)
            d.rounded_rectangle([x, y, x + width, y + 28], radius=3, fill=dark if is_dark else light)
            d.rounded_rectangle([x + 3, y + 2, x + width - 3, y + 20], radius=3, fill=top_dark if is_dark else top_light)
            x += width + gap
        for i in range(4):   # keypad
            px = w - 14 - (4 - i) * (kw + gap)
            is_dark = r == 0 or i == 3
            d.rounded_rectangle([px, y, px + kw, y + 28], radius=3, fill=dark if is_dark else light)
            d.rounded_rectangle([px + 3, y + 2, px + kw - 3, y + 20], radius=3, fill=top_dark if is_dark else top_light)
    return img


def add_terminal(sc, mon, shell, recess, keys_texture, sticky_notes=()):
    """The terminal, screen facing +Z: a keyboard deck at the front, a body
    whose face sits in front of the screen with a bevelled recess round it,
    and a flat top with vents. Places for notes on the face's top corners
    and the body's sides."""
    sy, sz = mon.y, mon.z
    W = mon.w + 20
    B, D = TERM_BEVEL, TERM_DEPTH
    top = mon.top                      # top of the face and the body
    face_z = sz + D
    left, right = -mon.w / 2, mon.w / 2
    upper, lower = sy + mon.h / 2, sy - mon.h / 2

    # The body: a block from the back to the face, with its top and front
    # edges rounded off (cylinders along the edges, spheres at the corners).
    r = 3.0                            # radius of the rounded edges
    lid = top + 1.2                    # top of the lid
    back = sz - 34
    soft = dict(roughness=0.5)
    sc.box((0, (DESK_Y + lid - r) / 2, (back + sz - 1) / 2), (W, lid - r - DESK_Y, sz - 1 - back), shell, **soft)
    sc.box((0, lid - r / 2, (back + face_z) / 2), (W, r, face_z - back - 2 * r), shell, **soft)
    for z in (back + r, face_z - r):   # top edges, back and front
        sc.cylinder((0, lid - r, z), 2 * r, W - 2 * r, shell, rotation=(0, 0, 90), **soft)
    for sign in (-1, 1):
        x = sign * (W / 2 - r)
        for z in (back + r, face_z - r):
            sc.sphere((x, lid - r, z), (2 * r, 2 * r, 2 * r), shell, **soft)
        # The front corners, and the sides between the body and the face.
        sc.cylinder((x, (DESK_Y + lid - r) / 2, face_z - r), 2 * r, lid - r - DESK_Y, shell, **soft)
        sc.box((sign * W / 2 - sign * 0.005, (DESK_Y + lid - r) / 2, (sz - 1 + face_z - r) / 2),
               (0.01, lid - r - DESK_Y, face_z - r - sz + 1), shell, **soft)
    for group in (-1, 1):              # vents on the lid
        for row in range(4):
            for col in range(5):
                sc.box((group * W / 4 - W / 8 + col * W / 20 + 1, lid + 0.02, sz - 8 - row * 4), (W / 26, 0.06, 1.2),
                       "#6a6862", shadows=False)
    # The face in front of the screen: flat panels round a bevelled recess.
    t = 1.2
    fw = W - 2 * r
    sc.box((0, (upper + B + lid - r) / 2, face_z - t / 2), (fw, lid - r - upper - B, t), shell, **soft)
    face_bottom = lower - B
    sc.box((0, (face_bottom + DESK_Y + 9) / 2, face_z - t / 2), (fw, face_bottom - DESK_Y - 9, t), shell, **soft)
    side_w = fw / 2 - mon.w / 2 - B
    for sign in (-1, 1):
        sc.box((sign * (fw / 2 - side_w / 2), sy, face_z - t / 2), (side_w, mon.h + 2 * B, t), shell, **soft)
    # The recess: four gently sloping panels from the screen's edge out to the face.
    L = math.hypot(B, D)
    a = math.degrees(math.atan2(D, B))
    sc.box((0, upper + B / 2, sz + D / 2), (mon.w + 2 * B, L, 0.5), recess, rotation=(a, 0, 0), roughness=0.6)
    sc.box((0, lower - B / 2, sz + D / 2), (mon.w + 2 * B, L, 0.5), recess, rotation=(-a, 0, 0), roughness=0.6)
    sc.box((left - B / 2, sy, sz + D / 2), (L, mon.h, 0.5), recess, rotation=(0, a, 0), roughness=0.6)
    sc.box((right + B / 2, sy, sz + D / 2), (L, mon.h, 0.5), recess, rotation=(0, -a, 0), roughness=0.6)
    sc.box((0, sy, sz - 0.6), (mon.w + 1.4, mon.h + 1.4, 0.6), "#1a1a1a", roughness=0.3)
    # The keyboard deck, sloping down towards you, with the keys on top and
    # a rounded front lip.
    deck_len, slope, deck_h = 30, 6, 9
    deck_y = DESK_Y + deck_h / 2
    deck_z = face_z + deck_len / 2 - 1
    kx = math.radians(slope)
    sc.box((0, deck_y, deck_z), (W, deck_h, deck_len), shell, rotation=(slope, 0, 0), **soft)
    sc.cylinder((0, deck_y - deck_len / 2 * math.sin(kx), deck_z + deck_len / 2 * math.cos(kx)), deck_h, W, shell,
                rotation=(0, 0, 90), **soft)
    top_y = deck_y + deck_h / 2 * math.cos(kx) + 0.05
    sc.plane((0, top_y - 2 * math.tan(kx), face_z + deck_len / 2 + 1 + deck_h / 2 * math.sin(kx)), W - 8, deck_len - 9,
             rotation=(-90 + slope, 0, 0), texture=keys_texture, roughness=0.55, shadows=False)
    # A small badge under the screen, and the power lamp.
    sc.box((-mon.w / 4, lower - B - 3, face_z + 0.05), (8, 1.6, 0.2), "#4a4a52")
    sc.sphere((fw / 2 - 3, lower - B - 3, face_z + 0.1), (0.9, 0.9, 0.5), "#40ff60", emissive="#40ff60", shadows=False)

    textures = list(sticky_notes) + [None, None]
    size = 5
    note_y = upper + B + 3
    sc.spot("bezel-left", (left + size / 2, note_y, face_z + 0.05), size, (0, 0, 4), textures[0])
    sc.spot("right-side", (W / 2 + 0.05, sy - 2, sz - 8), 6, (0, 90, -5), textures[1])
    sc.spot("bezel-right", (right - size / 2, note_y, face_z + 0.05), size, (0, 0, -3))
    sc.spot("left-side", (-W / 2 - 0.05, sy - 4, sz - 12), 6, (0, -90, 4))


def add_lcd(sc, mon, bezel, back, stand, glossy=False, power="#40a0ff", sticky_notes=()):
    """A flat-panel monitor, screen facing +Z, and places for sticky notes
    on it: on the bezel's top corners and hanging off its sides, as people
    stuck them on LCDs."""
    sy, sz = mon.y, mon.z
    side, top_border, bottom = mon.lcd
    width = mon.w + 2 * side
    height = mon.h + top_border + bottom
    centre_y = sy - mon.h / 2 - bottom + height / 2
    rough = 0.12 if glossy else 0.45
    # Foot, neck and the hinge on the back.
    sc.cylinder((0, DESK_Y + 0.8, sz - 6), 24, 1.6, stand, metalness=0.8 if glossy else 0.4, roughness=0.25)
    sc.box((0, DESK_Y + (centre_y - height / 2 - DESK_Y) / 2 + 2, sz - 7), (7, centre_y - height / 2 - DESK_Y + 6, 3),
           stand, metalness=0.8 if glossy else 0.4, roughness=0.25)
    # Bezel and the slim body behind it.
    sc.box((0, centre_y, sz - 2.9), (width, height, 5), bezel, roughness=rough)
    sc.box((0, centre_y + 1, sz - 7.5), (width * 0.62, height * 0.62, 4.5), back, roughness=rough)
    sc.box((0, sy, sz - 0.5), (mon.w + 0.4, mon.h + 0.4, 0.3), "#0c0c0e", roughness=0.2)
    # Power button with its light, and a few buttons along the bottom.
    by = sy - mon.h / 2 - bottom / 2
    sc.cylinder((width / 2 - 3, by, sz - 0.3), 1.2, 0.4, power, rotation=(90, 0, 0), emissive=power, shadows=False)
    for i in range(4):
        sc.box((width / 2 - 7 - i * 2.6, by, sz - 0.35), (1.6, 0.6, 0.3), back, shadows=False)
    textures = list(sticky_notes) + [None, None]
    top = sy + mon.h / 2 + top_border
    sc.spot("bezel-left", (-mon.w / 2 + 2, top + 0.5, sz - 0.3), 6, (0, 0, 6), textures[0])
    sc.spot("right-side", (width / 2 + 1.5, sy - 2, sz - 0.3), 6, (0, 0, -8), textures[1])
    sc.spot("bezel-right", (mon.w / 2 - 2, top + 0.2, sz - 0.3), 6, (0, 0, -4))
    sc.spot("left-side", (-width / 2 - 1.5, sy - 6, sz - 0.3), 6, (0, 0, 7))


def add_monitor(sc, mon, casing, casing_dark, sticky_notes=()):
    """The monitor, screen facing +Z, and places for sticky notes on it: on
    the bezel above the screen's top corners and on both sides of the
    casing. `sticky_notes` are the textures of the first two (for the 2D
    pictures)."""
    sy, sz = mon.y, mon.z
    if mon is WIDE:
        # Dark base plate and swivel.
        sc.box((0, DESK_Y + 1.5, -52), (46, 3, 40), "#2a2a2c", roughness=0.45)
        sc.box((0, DESK_Y + 4, -50), (20, 3, 16), "#323234", roughness=0.45)
        # Bezel, then the long tapered back of the tube.
        sc.box((0, sy - 1.5, sz - 4.0), (58, 48, 7), casing, roughness=0.4)
        sc.box((0, sy - 1.5, sz - 14.4), (55, 45, 15.5), casing, roughness=0.45)
        sc.box((0, sy - 1.5, sz - 30), (47, 38, 16), casing, roughness=0.5)
        sc.box((0, sy - 1, sz - 44), (37, 29, 13), casing_dark, roughness=0.55)
        for i in range(14):
            sc.box((-19.5 + i * 3, sy + 22.6, sz - 14.4), (1.0, 0.3, 12), casing_dark, shadows=False)
        sc.box((0, sy, sz - 0.6), (mon.w + 3, mon.h + 3, 0.6), "#141412", roughness=0.3)
        chin = sy - mon.h / 2 - 5
        sc.box((-20, chin, sz - 0.4), (9, 1.2, 0.3), casing_dark)
        for i in range(4):
            sc.box((8 + i * 3.2, chin, sz - 0.3), (2.2, 1.2, 0.6), casing_dark)
        sc.box((23, chin, sz - 0.3), (3, 1.6, 0.8), casing_dark)
        sc.sphere((20, chin, sz - 0.3), (0.8, 0.8, 0.8), "#30ff60", emissive="#30ff60", shadows=False)
    else:
        sc.cylinder((0, DESK_Y + 1, -55), 24, 2, casing_dark, roughness=0.5)
        sc.box((0, DESK_Y + 4.5, -55), (12, 5, 12), casing_dark, roughness=0.5)
        sc.box((0, sy - 1.5, sz - 4.75), (40, 36, 8.5), casing, roughness=0.45)
        sc.box((0, sy - 0.5, sz - 15.4), (35, 31, 14), casing, roughness=0.5)
        sc.box((0, sy + 0.5, sz - 27.4), (27, 23, 12), casing_dark, roughness=0.55)
        for i in range(9):
            sc.box((-12 + i * 3, sy + 14.6, sz - 16.4), (1.0, 0.3, 9), casing_dark, shadows=False)
        sc.box((0, sy, sz - 0.6), (mon.w + 2.6, mon.h + 2.6, 0.6), "#141412", roughness=0.3)
        chin = sy - mon.h / 2 - 6
        sc.box((-13, chin, sz - 0.4), (7, 1.2, 0.3), casing_dark)
        sc.box((14, chin, sz - 0.3), (3, 1.6, 0.8), casing_dark)
        sc.sphere((10, chin, sz - 0.3), (0.8, 0.8, 0.8), "#30ff60", emissive="#30ff60", shadows=False)
    top_border = mon.top - (sy + mon.h / 2)   # bezel above the screen
    size = min(5.5, top_border - 0.8)
    textures = list(sticky_notes) + [None, None]
    bezel_y = sy + mon.h / 2 + top_border / 2
    sc.spot("bezel-left", (-mon.w / 2 + size / 2 + 1, bezel_y, sz - 0.45), size, (0, 0, 4), textures[0])
    sc.spot("right-side", (mon.half_width + 0.05, sy - 4, sz - 5), 6, (0, 90, -5), textures[1])
    sc.spot("bezel-right", (mon.w / 2 - size / 2 - 1, bezel_y, sz - 0.45), size, (0, 0, -3))
    sc.spot("left-side", (-mon.half_width - 0.05, sy - 2, sz - 8), 6, (0, -90, 4))


def add_keyboard(sc, base, tex):
    sc.box((0, DESK_Y + 1.4, -16), (46, 2.8, 17), base, rotation=(5, 0, 0), roughness=0.55)
    sc.plane((0, DESK_Y + 2.95, -16), 45, 15.8, rotation=(-85, 0, 0), texture=tex,
             roughness=0.5, shadows=False)
    sc.box((0, DESK_Y + 0.4, -33), (0.8, 0.8, 18), "#2a2826", shadows=False)   # cable


def room_80s(out, rng, mon):
    sc = Scene("80s")
    t_wall = save(wood_panel(rng), out, "wood-panel.jpg")
    t_desk = save(walnut(rng), out, "walnut.jpg")
    t_floor = save(carpet(rng, (120, 86, 52)), out, "shag-carpet.jpg")
    t_ceiling = save(laminate(rng, (226, 220, 206)), out, "ceiling-80s.jpg")
    t_poster = save(poster_80s(), out, "poster.jpg")
    t_keys = save(keyboard_top((200, 190, 164), (176, 166, 142), (226, 218, 196)), out, "keyboard-beige.png")
    t_blinds = save(blinds(), out, "blinds.jpg")
    t_floppies = [save(floppy_label(c), out, "floppy-%d.png" % i)
                  for i, c in enumerate([(30, 30, 34), (40, 60, 130), (150, 40, 40)])]

    # A 4 m square den: panelled walls, shag carpet, a window on the left.
    sc.plane((0, 0, 0), 400, 400, rotation=(-90, 0, 0), texture=t_floor, repeat=(6, 6), roughness=0.95)
    sc.plane((0, 240, 0), 400, 400, rotation=(90, 0, 0), texture=t_ceiling, repeat=(4, 4))
    for center, rot in (((0, 120, -90), 0), ((-200, 120, 110), 90), ((200, 120, 110), -90),
                        ((0, 120, 310), 180)):
        sc.plane(center, 400, 240, rotation=(0, rot, 0), texture=t_wall, repeat=(8, 2), roughness=0.6)
    sc.box((0, 5, -89), (400, 10, 2), "#4a2c18")
    sc.box((-199, 140, 20), (2, 96, 126), "#e8e0cc")
    sc.plane((-197.8, 140, 20), 116, 86, rotation=(0, 90, 0), texture=t_blinds,
             emissive="#ffffff", shadows=False)

    # Walnut desk with two pedestals of drawers.
    sc.box((0, DESK_Y - 2, -45), (150, 4, 86), "#ffffff", texture=t_desk, repeat=(2, 1), roughness=0.45)
    for x in (-56, 56):
        sc.box((x, (DESK_Y - 4) / 2, -45), (36, DESK_Y - 4, 78), "#ffffff", texture=t_desk, roughness=0.5)
        for k in range(3):
            sc.box((x, 16 + k * 19, -5.8), (32, 16, 1), "#5c371e", roughness=0.5)
            sc.box((x, 20 + k * 19, -5), (10, 1.4, 1.4), "#c8b27a", metalness=0.8, roughness=0.3)

    t_cal = save(calendar_90s(), out, "calendar.jpg")
    t_n1 = save(sticky(rng, (250, 236, 120)), out, "sticky-yellow.png")
    t_n2 = save(sticky(rng, (255, 170, 190)), out, "sticky-pink.png")
    t_n3 = save(sticky(rng, (180, 230, 160)), out, "sticky-green.png")
    add_monitor(sc, mon, "#d6ccb2", "#aaa088", sticky_notes=[t_n1, t_n2])
    sc.plane((-48, 158, -89.3), 30, 37.5, texture=t_cal, roughness=0.6, live="calendar")
    sc.spot("wall-1", (-14, 164, -89.3), 7, (0, 0, -6), t_n3)
    sc.spot("wall-2", (18, 168, -89.3), 7, (0, 0, 4))
    sc.spot("wall-3", (40, 176, -89.3), 7, (0, 0, -3))
    sc.spot("desk", (-34, DESK_Y + 0.06, -12), 7, (-90, 12, 0))
    add_keyboard(sc, "#c8bea4", t_keys)

    # Poster and a shelf with books and a cassette deck.
    sc.box((-110, 150, -89.4), (52, 70, 1.2), "#1e1a18")
    sc.plane((-110, 150, -88.7), 46, 64, texture=t_poster, roughness=0.3)
    sc.box((105, 140, -78), (80, 2.5, 22), "#5c371e")
    x = 70.0
    for c in ["#962820", "#284670", "#c8a03c", "#3c643c", "#783c6e", "#b45a28", "#323240", "#962820"]:
        bw = float(rng.uniform(3, 5.5))
        bh = float(rng.uniform(18, 26))
        sc.box((x + bw / 2, 141.25 + bh / 2, -80), (bw, bh, 16), c, roughness=0.8)
        x += bw + 0.4
    sc.box((128, 147, -80), (24, 11, 16), "#2a282a", roughness=0.4)
    sc.box((128, 149, -71.9), (18, 4, 0.2), "#101012")

    # Banker's lamp.
    sc.cylinder((55, DESK_Y + 1, -62), 16, 2, "#b89a50", metalness=0.9, roughness=0.3)
    sc.cylinder((55, DESK_Y + 15, -62), 1.6, 28, "#b89a50", metalness=0.9, roughness=0.3)
    sc.box((55, DESK_Y + 30, -57), (30, 5, 11), "#1e6a3a", rotation=(20, 0, 0), roughness=0.25)
    sc.sphere((55, DESK_Y + 27.5, -56), (24, 2.2, 6), "#fff2c8", emissive="#ffe8b0", shadows=False)
    sc.lights.append({"type": "point", "position": [55, DESK_Y + 24, -52], "color": "#ffd9a0",
                      "intensity": 1.4, "range": 160})

    # Potted plant: leaves are long, flat ellipsoids leaning out of the pot.
    sc.cylinder((-58, DESK_Y + 9, -62), 18, 18, "#96502f", roughness=0.8)
    sc.cylinder((-58, DESK_Y + 18.5, -62), 20, 2, "#af6240", roughness=0.8)
    for i in range(14):
        ang = math.radians(i * (360 / 14) + float(rng.uniform(-10, 10)))
        tilt = float(rng.uniform(25, 55))
        length = float(rng.uniform(22, 34))
        reach = math.sin(math.radians(tilt)) * length / 2
        sc.sphere((-58 + math.cos(ang) * reach, DESK_Y + 20 + math.cos(math.radians(tilt)) * length / 2,
                   -62 + math.sin(ang) * reach),
                  (3.2, length, 1.0), "#3c8a3c" if i % 2 else "#2c6e30",
                  rotation=(tilt * math.sin(ang), 0, -tilt * math.cos(ang)), roughness=0.6)

    # Coffee mug and floppy disks.
    sc.cylinder((42, DESK_Y + 5, -20), 8.5, 10, "#c84c2c", roughness=0.35)
    sc.cylinder((42, DESK_Y + 9.6, -20), 7.5, 0.4, "#3c2214", roughness=0.2, shadows=False)
    sc.box((47, DESK_Y + 5, -20), (2.4, 6, 1.2), "#c84c2c", roughness=0.35)
    for i, tex in enumerate(t_floppies):
        sc.box((32 + i * 1.2, DESK_Y + 0.2 + i * 0.35, -36 + i * 0.8), (9, 0.3, 9), "#ffffff",
               rotation=(0, 8 - i * 9, 0), texture=tex, roughness=0.5)

    sc.lights += [
        {"type": "directional", "rotation": quat(-50, -25, 0), "color": "#ffe6c8", "intensity": 0.55,
         "shadows": True},
        {"type": "directional", "rotation": quat(-15, -95, 0), "color": "#fff4e0", "intensity": 0.45,
         "shadows": False},
        {"type": "point", "position": [0, 220, 40], "color": "#ffe2b8", "intensity": 0.8, "range": 400},
    ]
    return finish(sc, mon, background="#1a120c", ambient=("#806048", 0.35), fill="#5a3a22")


def room_90s(out, rng, mon):
    sc = Scene("90s")
    t_fabric = save(fabric(rng, (96, 104, 122)), out, "fabric.jpg")
    t_desk = save(laminate(rng, (194, 192, 186)), out, "laminate.jpg")
    t_floor = save(carpet(rng, (70, 74, 84)), out, "office-carpet.jpg")
    t_ceiling = save(ceiling_tile(rng), out, "ceiling-tile.jpg")
    t_wall = save(laminate(rng, (204, 198, 184)), out, "office-wall.jpg")
    t_light = save(ceiling_light(), out, "ceiling-light.jpg")
    t_calendar = save(calendar_90s(), out, "calendar.jpg")
    t_memo = save(memo(rng), out, "memo.jpg")
    t_keys = save(keyboard_top((190, 188, 180), (168, 166, 158), (214, 212, 204)), out, "keyboard-grey.png")
    t_yellow = save(sticky(rng, (250, 236, 120)), out, "sticky-yellow.png")
    t_pink = save(sticky(rng, (255, 170, 190)), out, "sticky-pink.png")
    t_green = save(sticky(rng, (180, 230, 160)), out, "sticky-green.png")

    # Open-plan floor with fluorescent panels in a tiled ceiling.
    sc.plane((0, 0, 0), 1200, 1200, rotation=(-90, 0, 0), texture=t_floor, repeat=(20, 20), roughness=0.95)
    sc.plane((0, 260, 0), 1200, 1200, rotation=(90, 0, 0), texture=t_ceiling, repeat=(20, 20))
    for center, length, rot in (((0, 130, -500), 1200, 0), ((0, 130, 500), 1200, 180),
                                ((-600, 130, 0), 1000, 90), ((600, 130, 0), 1000, -90)):
        sc.plane(center, length, 260, rotation=(0, rot, 0), texture=t_wall, repeat=(length / 200, 1))
    for x in (-300, 0, 300):
        for z in (-300, 0, 300):
            sc.plane((x, 259.5, z), 60, 120, rotation=(90, 0, 0), texture=t_light,
                     emissive="#ffffff", shadows=False)

    # Fabric partitions with aluminium trim: this cubicle and the neighbours.
    def partition(center, length, rot):
        sc.box(center, (length, 150, 6), "#ffffff", rotation=(0, rot, 0), texture=t_fabric,
               repeat=(length / 60, 2.5), roughness=0.95)
        x, _, z = center
        sc.box((x, 151, z), (length + 1, 3, 7), "#b4b8be", rotation=(0, rot, 0), metalness=0.7, roughness=0.35)
    partition((0, 75, -92), 190, 0)
    partition((-95, 75, -10), 170, 90)
    partition((95, 75, -10), 170, 90)
    for x in (-290, 290):
        partition((x, 75, -92), 190, 0)
        partition((x, 75, -280), 190, 0)
    for x in (-190, 190):
        partition((x, 75, -186), 170, 90)
    partition((0, 75, -280), 190, 0)

    # Laminate desk on metal legs, and a PC tower on the floor.
    sc.box((0, DESK_Y - 1.5, -45), (186, 3, 90), "#ffffff", texture=t_desk, repeat=(2, 1), roughness=0.4)
    sc.box((0, DESK_Y - 4, -0.5), (186, 2, 1), "#3c3c40", roughness=0.5)
    for x in (-88, 88):
        sc.box((x, (DESK_Y - 3) / 2, -45), (4, DESK_Y - 3, 84), "#5a5c62", metalness=0.6, roughness=0.4)
    sc.box((60, 22, -60), (20, 44, 45), "#cbc7b8", roughness=0.5)
    sc.box((60, 36, -37.4), (14, 3, 0.4), "#3a3a3c")
    sc.box((60, 28, -37.4), (10, 1.5, 0.4), "#3a3a3c")

    add_monitor(sc, mon, "#d8d6cc", "#a8a69e",
                sticky_notes=[t_yellow, t_pink])
    # A desk lamp and small beige speakers.
    sc.cylinder((80, DESK_Y + 1, -66), 13, 2, "#1c1c1e", roughness=0.35)
    sc.cylinder((80, DESK_Y + 16, -66), 1.4, 30, "#1c1c1e", metalness=0.6, roughness=0.3)
    sc.sphere((80, DESK_Y + 31, -62), (14, 9, 14), "#1c1c1e", roughness=0.3)
    sc.sphere((80, DESK_Y + 27.5, -61), (8, 1.5, 8), "#fff6e0", emissive="#fff0d0", shadows=False)
    sc.lights.append({"type": "point", "position": [80, DESK_Y + 24, -58], "color": "#fff0d8",
                      "intensity": 0.6, "range": 90})
    for x in (-mon.half_width - 7, mon.half_width + 7):
        sc.box((x, DESK_Y + 7, -40), (9, 14, 11), "#d2ccb8", roughness=0.5)
        sc.cylinder((x, DESK_Y + 9, -34.4), 5, 0.4, "#8c8674", rotation=(90, 0, 0), roughness=0.8)
    add_keyboard(sc, "#bebcb4", t_keys)

    # Calendar, memos and a note pinned to the partitions.
    sc.plane((-55, 115, -88.8), 34, 42.5, texture=t_calendar, roughness=0.6, live="calendar")
    sc.plane((50, 118, -88.8), 21, 27, rotation=(0, 0, 3), texture=t_memo, roughness=0.6)
    sc.plane((72, 110, -88.8), 21, 27, rotation=(0, 0, -4), texture=t_memo, roughness=0.6)
    sc.spot("wall-1", (-91.8, 110, -40), 7, (0, 90, 0), t_green)
    sc.spot("wall-2", (-15, 142, -88.8), 7, (0, 0, -4))
    sc.spot("wall-3", (26, 140, -88.8), 7, (0, 0, 5))
    sc.spot("desk", (-34, DESK_Y + 0.06, -12), 7, (-90, 12, 0))

    # Mouse mat and mouse, phone, styrofoam cup and a stack of paper.
    sc.box((36, DESK_Y + 0.2, -20), (22, 0.4, 18), "#6a5aa8", roughness=0.8)
    sc.sphere((36, DESK_Y + 1.6, -20), (6, 3.2, 10), "#d6d4cc", roughness=0.4)
    sc.box((36, DESK_Y + 0.6, -36), (0.5, 0.5, 22), "#3c3c3c", shadows=False)
    sc.box((-70, DESK_Y + 3, -31), (22, 6, 20), "#343438", rotation=(0, 10, 0), roughness=0.45)
    sc.box((-74, DESK_Y + 7, -33), (8, 4, 20), "#3c3c40", rotation=(0, 10, 0), roughness=0.45)
    sc.box((-64, DESK_Y + 6.2, -25), (8, 0.5, 6), "#788c6c", rotation=(0, 10, 0), roughness=0.3)
    sc.cylinder((60, DESK_Y + 5.5, -30), 8, 11, "#f4f2ec", roughness=0.7)
    sc.cylinder((60, DESK_Y + 10.6, -30), 7.2, 0.4, "#4a2c18", roughness=0.2, shadows=False)
    for k in range(6):
        sc.box((-46 + (k % 2) * 0.6, DESK_Y + 0.3 + k * 0.4, -40), (21, 0.4, 29.7), "#f2f2ee",
               rotation=(0, k * 2, 0))

    sc.lights += [
        {"type": "directional", "rotation": quat(-70, 10, 0), "color": "#eef4ff", "intensity": 0.7,
         "shadows": True},
        {"type": "directional", "rotation": quat(-20, 160, 0), "color": "#e8eef8", "intensity": 0.25,
         "shadows": False},
        {"type": "point", "position": [0, 240, -20], "color": "#f0f6ff", "intensity": 1.0, "range": 500},
    ]
    return finish(sc, mon, background="#202228", ambient=("#7c8494", 0.4), fill="#4e5566")


def room_70s(out, rng, mon):
    """A 70s computer room: the mainframe's cabinets behind the desk, tape
    drives, banks of lights, a line printer, and a video terminal."""
    sc = Scene("70s")
    t_floor = save(raised_floor(), out, "raised-floor.png")
    t_wall = save(laminate(rng, (196, 208, 186)), out, "paint-70s.jpg")
    t_desk = save(laminate(rng, (132, 146, 130)), out, "steel-desk.jpg")
    t_ceiling = save(ceiling_tile(rng), out, "ceiling-tile.jpg")
    t_light = save(ceiling_light(), out, "ceiling-light.jpg")
    t_paper = save(greenbar(), out, "greenbar.jpg")
    t_cal = save(calendar_90s(), out, "calendar.jpg")
    t_n1 = save(sticky(rng, (250, 236, 120)), out, "sticky-yellow.png")
    t_n2 = save(sticky(rng, (255, 170, 190)), out, "sticky-pink.png")
    t_n3 = save(sticky(rng, (180, 230, 160)), out, "sticky-green.png")

    # The machine room: raised floor, institutional green walls, fluorescent tubes.
    sc.plane((0, 0, 0), 700, 700, rotation=(-90, 0, 0), texture=t_floor, repeat=(12, 12), roughness=0.5)
    sc.plane((0, 250, 0), 700, 700, rotation=(90, 0, 0), texture=t_ceiling, repeat=(12, 12))
    for x in (-180, 0, 180):
        for z in (-140, 40):
            sc.plane((x, 249.5, z), 60, 120, rotation=(90, 0, 0), texture=t_light, emissive="#ffffff", shadows=False)
    for center, length, rot in (((0, 125, -200), 700, 0), ((0, 125, 350), 700, 180),
                                ((-350, 125, 75), 550, 90), ((350, 125, 75), 550, -90)):
        sc.plane(center, length, 250, rotation=(0, rot, 0), texture=t_wall, repeat=(length / 150, 2))

    # A row of the mainframe's cabinets behind the desk.
    kinds = ["tape", "cpu", "cpu", "tape", "tape", "console", "cpu", "tape"]
    lamp_colours = ["#ff3020", "#ffb020", "#40ff60", "#ffe080"]
    for i, kind in enumerate(kinds):
        x = -210 + i * 60
        sc.box((x, 92, -125), (58, 184, 50), "#e6dcc4", roughness=0.5)
        sc.box((x, 184.5, -125), (58, 3, 50), "#6a4a2e", roughness=0.5)
        sc.box((x, 4, -100.5), (58, 8, 1), "#3a3a3a")
        if kind == "tape":
            # Two reels behind smoked glass, and the controls below.
            sc.box((x, 132, -100.2), (50, 76, 0.6), "#2a2a2e", roughness=0.4)
            for ry in (150, 116):
                sc.cylinder((x, ry, -99.5), 26, 1.4, "#c8ccd0", rotation=(90, 0, 0), metalness=0.4, roughness=0.3)
                sc.cylinder((x, ry, -99.0), 9, 1.6, "#3a3a3e", rotation=(90, 0, 0))
                sc.cylinder((x, ry, -98.9), 20, 0.4, "#5a3a20", rotation=(90, 0, 0), shadows=False)   # the tape
            sc.box((x, 132, -98.4), (50, 76, 0.4), "#90a0b0", roughness=0.05, opacity=0.25, shadows=False)
            for k in range(4):
                sc.box((x - 15 + k * 10, 82, -99.6), (6, 4, 1.4), "#d0d0c8")
        else:
            # A panel of lights, and switches below it.
            sc.box((x, 150, -100.2), (50, 44, 0.6), "#26303a", roughness=0.4)
            for row in range(7):
                for col in range(9):
                    if rng.random() < 0.55:
                        c = lamp_colours[int(rng.integers(0, len(lamp_colours)))]
                        sc.sphere((x - 20 + col * 5, 134 + row * 5, -99.7), (1.6, 1.6, 0.8), c, emissive=c, shadows=False)
                    else:
                        sc.sphere((x - 20 + col * 5, 134 + row * 5, -99.7), (1.6, 1.6, 0.8), "#4a4a48", shadows=False)
            for k in range(12):
                sc.box((x - 22 + k * 4, 120, -99.4), (1.6, 4, 1.6), "#e04020" if k % 4 == 0 else "#d8d4c8")
            if kind == "console":
                # The operator's ledge, with a row of buttons.
                sc.box((x, 96, -93), (56, 4, 16), "#d8ccb0", roughness=0.5)
                sc.box((x, 98.2, -93), (48, 0.6, 10), "#26303a", roughness=0.4)
                for k in range(8):
                    sc.box((x - 21 + k * 6, 98.8, -93), (3.4, 0.8, 3.4), "#e04020" if k in (0, 7) else "#f0ecd8",
                           shadows=False)

    # The calendar and notes on the cabinets.
    sc.plane((-90, 108, -99.3), 34, 42.5, texture=t_cal, roughness=0.6, live="calendar")
    sc.spot("wall-1", (-60, 116, -99.3), 7, (0, 0, -5), t_n3)
    sc.spot("wall-2", (60, 112, -99.3), 7, (0, 0, 4))
    sc.spot("wall-3", (100, 104, -99.3), 7, (0, 0, -3))
    sc.spot("desk", (-48, DESK_Y + 0.06, -8), 7, (-90, 12, 0))

    # A steel tanker desk.
    sc.box((0, DESK_Y - 1.5, -45), (156, 3, 82), "#ffffff", texture=t_desk, repeat=(2, 1), roughness=0.4)
    for x in (-58, 58):
        sc.box((x, (DESK_Y - 3) / 2, -45), (38, DESK_Y - 3, 76), "#8a9a88", roughness=0.4, metalness=0.2)
        for k in range(3):
            sc.box((x, 14 + k * 20, -6.6), (34, 17, 1), "#7a8a78", roughness=0.4)
            sc.box((x, 19 + k * 20, -5.8), (12, 1.6, 1.4), "#c8c8c0", metalness=0.6, roughness=0.3)

    t_terminal_keys = save(keyboard_terminal(), out, "keyboard-terminal.png")
    add_terminal(sc, mon, "#e6e2d6", "#dad5c7", t_terminal_keys, sticky_notes=[t_n1, t_n2])

    # Punch cards, a box of them, an orange mug and a pen holder.
    for k in range(5):
        sc.box((-52 + (k % 2) * 0.4, DESK_Y + 0.2 + k * 0.4, -22), (19, 0.4, 8.3), "#efe6c8", rotation=(0, 8, 0))
    sc.box((-62, DESK_Y + 4, -50), (21, 8, 32), "#c8b48a", roughness=0.8)
    sc.cylinder((46, DESK_Y + 5, -22), 8.5, 10, "#e07020", roughness=0.35)
    sc.box((51, DESK_Y + 5, -22), (2.4, 6, 1.2), "#e07020", roughness=0.35)
    sc.cylinder((62, DESK_Y + 6, -50), 7, 12, "#7a8a78", metalness=0.3, roughness=0.4)
    for k in range(3):
        sc.cylinder((60 + k * 2, DESK_Y + 14, -50), 0.8, 10, ["#1840a0", "#c02020", "#202020"][k])

    # A line printer with its fan-fold paper.
    sc.box((150, 55, -30), (80, 110, 55), "#d8d0bc", rotation=(0, -25, 0), roughness=0.5)
    sc.box((150, 112, -30), (76, 4, 50), "#5a3a24", rotation=(0, -25, 0), roughness=0.5)
    sc.plane((140, 118, -16), 36, 54, rotation=(-60, -25, 0), texture=t_paper, roughness=0.8)
    sc.box((150, 8, 12), (40, 16, 28), "#f4f4ee", rotation=(0, -25, 0), roughness=0.9)

    sc.lights += [
        {"type": "directional", "rotation": quat(-70, 10, 0), "color": "#f0f6f0", "intensity": 0.7, "shadows": True},
        {"type": "directional", "rotation": quat(-20, 160, 0), "color": "#e8f0e8", "intensity": 0.25, "shadows": False},
        # A soft fill from the left, so the terminal's side isn't lost in shadow.
        {"type": "directional", "rotation": quat(-25, -70, 0), "color": "#f2f4ee", "intensity": 0.3, "shadows": False},
        {"type": "point", "position": [0, 230, -40], "color": "#f4fff4", "intensity": 1.0, "range": 450},
    ]
    return finish(sc, mon, background="#202420", ambient=("#8a9688", 0.4), fill="#6a7466")


def room_2000s(out, rng, mon):
    sc = Scene("2000s")
    t_floor = save(carpet_tiles(rng), out, "carpet-tiles.jpg")
    t_wall = save(laminate(rng, (214, 214, 210)), out, "paint-2000s.jpg")
    t_desk = save(laminate(rng, (52, 54, 58)), out, "charcoal.jpg")
    t_ceiling = save(ceiling_tile(rng), out, "ceiling-tile.jpg")
    t_light = save(ceiling_light(), out, "ceiling-light.jpg")
    t_board = save(whiteboard(rng), out, "whiteboard.jpg")
    t_poster = save(poster_synergy(), out, "poster-synergy.jpg")
    t_keys = save(keyboard_top((34, 34, 38), (52, 52, 58), (74, 74, 80)), out, "keyboard-black.png")
    t_cal = save(calendar_90s(), out, "calendar.jpg")
    t_n1 = save(sticky(rng, (250, 236, 120)), out, "sticky-yellow.png")
    t_n2 = save(sticky(rng, (255, 170, 190)), out, "sticky-pink.png")
    t_n3 = save(sticky(rng, (180, 230, 160)), out, "sticky-green.png")

    # An office with painted walls, carpet tiles and a tiled ceiling.
    sc.plane((0, 0, 0), 600, 600, rotation=(-90, 0, 0), texture=t_floor, repeat=(10, 10), roughness=0.95)
    sc.plane((0, 250, 0), 600, 600, rotation=(90, 0, 0), texture=t_ceiling, repeat=(10, 10))
    for x in (-150, 0, 150):
        sc.plane((x, 249.5, -20), 60, 120, rotation=(90, 0, 0), texture=t_light, emissive="#ffffff", shadows=False)
    for center, length, rot in (((0, 125, -90), 600, 0), ((0, 125, 300), 600, 180),
                                ((-300, 125, 100), 600, 90), ((300, 125, 100), 600, -90)):
        sc.plane(center, length, 250, rotation=(0, rot, 0), texture=t_wall, repeat=(length / 150, 2))
    sc.box((0, 4, -89), (600, 8, 2), "#5a5c60")
    # Whiteboard, a motivational poster and the calendar.
    sc.box((75, 140, -89.2), (92, 62, 1.6), "#c4c8cc", metalness=0.6, roughness=0.3)
    sc.plane((75, 140, -88.3), 88, 58, texture=t_board, roughness=0.2)
    sc.box((75, 108.5, -86.5), (60, 1.5, 5), "#c4c8cc", metalness=0.6, roughness=0.3)
    for i, c in enumerate(("#2050c0", "#c03030", "#208040")):
        sc.cylinder((60 + i * 6, 109.8, -86.5), 1.4, 10, c, rotation=(0, 0, 90), roughness=0.4)
    sc.box((-125, 145, -89.4), (42, 56, 1.4), "#101012")
    sc.plane((-125, 145, -88.6), 40, 53.3, texture=t_poster, roughness=0.3)
    sc.plane((-60, 132, -89.2), 34, 42.5, texture=t_cal, roughness=0.6, live="calendar")
    sc.spot("wall-1", (-28, 150, -89.2), 7, (0, 0, -5), t_n3)
    sc.spot("wall-2", (20, 160, -89.2), 7, (0, 0, 4))
    sc.spot("wall-3", (42, 160, -88.2), 7, (0, 0, -3))
    sc.spot("desk", (-34, DESK_Y + 0.06, -12), 7, (-90, 12, 0))

    # A charcoal desk on chrome legs, with a modesty panel.
    sc.box((0, DESK_Y - 1.5, -45), (170, 3, 90), "#ffffff", texture=t_desk, repeat=(2, 1), roughness=0.35)
    for x in (-80, 80):
        for z in (-8, -82):
            sc.cylinder((x, (DESK_Y - 3) / 2, z), 4, DESK_Y - 3, "#cfd3d8", metalness=0.4, roughness=0.25)
    sc.box((0, 42, -86), (156, 46, 1.5), "#3a3c40", roughness=0.6)

    add_lcd(sc, mon, "#1c1c1e", "#b8bcc2", "#b8bcc2", sticky_notes=[t_n1, t_n2])
    add_keyboard(sc, "#2a2a2e", t_keys)
    # Webcam on top of the monitor.
    side, top_border, bottom = mon.lcd
    top = mon.y + mon.h / 2 + top_border
    sc.box((0, top + 0.6, mon.z - 2.5), (4, 1.2, 5), "#2a2a2e")
    sc.sphere((0, top + 3.2, mon.z - 1.5), (4.6, 4.6, 4.6), "#c8ccd0", metalness=0.5, roughness=0.3)
    sc.sphere((0, top + 3.2, mon.z + 0.7), (1.8, 1.8, 0.6), "#101828", roughness=0.1, shadows=False)

    # Black mouse mat and an optical mouse; speakers; a tower with a blue light.
    sc.box((38, DESK_Y + 0.2, -20), (22, 0.4, 18), "#18181a", roughness=0.8)
    sc.sphere((38, DESK_Y + 1.6, -20), (6, 3.2, 10), "#b8bcc2", metalness=0.4, roughness=0.3)
    sc.sphere((38, DESK_Y + 0.6, -24), (1.2, 0.6, 1.2), "#ff3030", emissive="#ff3030", shadows=False)
    for x in (-mon.half_width - 8, mon.half_width + 8):
        sc.box((x, DESK_Y + 8, -45), (8, 16, 9), "#202024", roughness=0.5)
        sc.cylinder((x, DESK_Y + 10, -40.4), 5, 0.3, "#9ea2a8", rotation=(90, 0, 0), metalness=0.6, roughness=0.4)
    sc.box((65, 23, -55), (20, 46, 46), "#1a1a1c", roughness=0.4)
    sc.box((65, 30, -31.9), (17, 30, 0.4), "#b8bcc2", metalness=0.5, roughness=0.3)
    sc.box((65, 40, -31.6), (14, 3, 0.4), "#2a2a2e")
    sc.sphere((65, 20, -31.5), (1.2, 1.2, 0.6), "#3080ff", emissive="#3080ff", shadows=False)

    # Paper coffee cup, a flip phone and a spindle of CDs.
    sc.cylinder((55, DESK_Y + 6, -25), 8, 12, "#f4f2ee", roughness=0.7)
    sc.cylinder((55, DESK_Y + 5, -25), 8.4, 5, "#8a5a32", roughness=0.9)
    sc.cylinder((55, DESK_Y + 12.4, -25), 8.6, 0.8, "#f8f8f6", roughness=0.5)
    sc.box((-48, DESK_Y + 0.8, -22), (5, 1.6, 9), "#a8acb2", rotation=(0, 15, 0), metalness=0.7, roughness=0.3)
    sc.cylinder((-64, DESK_Y + 0.5, -55), 13, 1, "#1a1a1c")
    sc.cylinder((-64, DESK_Y + 4, -55), 12, 6, "#d8dce4", metalness=0.9, roughness=0.15)
    sc.cylinder((-64, DESK_Y + 5, -55), 13.4, 8.6, "#e8f0ff", roughness=0.05, opacity=0.25, shadows=False)
    # A small plant.
    sc.cylinder((-78, DESK_Y + 5, -75), 11, 10, "#f2f2f0", roughness=0.4)
    for i in range(9):
        ang = math.radians(i * 40 + float(rng.uniform(-10, 10)))
        tilt = float(rng.uniform(15, 40))
        length = float(rng.uniform(12, 18))
        reach = math.sin(math.radians(tilt)) * length / 2
        sc.sphere((-78 + math.cos(ang) * reach, DESK_Y + 10 + math.cos(math.radians(tilt)) * length / 2,
                   -75 + math.sin(ang) * reach), (2.2, length, 0.8), "#3c9a46",
                  rotation=(tilt * math.sin(ang), 0, -tilt * math.cos(ang)), roughness=0.6)

    sc.lights += [
        {"type": "directional", "rotation": quat(-65, 15, 0), "color": "#f2f6ff", "intensity": 0.7, "shadows": True},
        {"type": "directional", "rotation": quat(-20, 160, 0), "color": "#e8eef8", "intensity": 0.25, "shadows": False},
        {"type": "point", "position": [0, 230, -20], "color": "#f4f8ff", "intensity": 0.9, "range": 450},
    ]
    return finish(sc, mon, background="#202226", ambient=("#8a8e98", 0.4), fill="#5c5e62")


def room_gloss(out, rng, mon):
    """The 2000s as people remember them: glass, gloss, bubbles, water, a
    bright blue sky and a green hill, all turned up to eleven."""
    sc = Scene("gloss")
    t_sky = save(sky_window(rng), out, "gloss-sky.jpg")
    t_aurora = save(aurora(rng), out, "gloss-aurora.jpg")
    t_floor = save(glossy_tiles(), out, "gloss-tiles.png")
    t_wall = save(laminate(rng, (244, 248, 251)), out, "gloss-wall.jpg")
    t_keys = save(keyboard_top((236, 240, 245), (212, 222, 232), (252, 253, 255)), out, "keyboard-white.png")
    t_cal = save(calendar_90s(), out, "calendar.jpg")
    t_n1 = save(sticky(rng, (250, 236, 120)), out, "sticky-yellow.png")
    t_n2 = save(sticky(rng, (255, 170, 190)), out, "sticky-pink.png")
    t_n3 = save(sticky(rng, (180, 230, 160)), out, "sticky-green.png")

    # A bright white room; the whole back wall is a window onto the sky.
    sc.plane((0, 0, 0), 600, 600, rotation=(-90, 0, 0), texture=t_floor, repeat=(12, 12), roughness=0.12)
    sc.plane((0, 260, 0), 600, 600, rotation=(90, 0, 0), color="#f6fbff")
    sc.cylinder((0, 259, 0), 90, 1, "#ffffff", emissive="#e8f6ff", shadows=False)
    sc.plane((0, 130, -92), 600, 260, texture=t_sky, emissive="#ffffff", shadows=False)
    for x in (-200, -100, 0, 100, 200):
        sc.box((x, 130, -90), (3, 260, 3), "#ffffff", roughness=0.15)
    sc.box((0, 210, -90), (600, 3, 3), "#ffffff", roughness=0.15)
    for center, rot in (((-300, 130, 100), 90), ((300, 130, 100), -90), ((0, 130, 300), 180)):
        sc.plane(center, 600, 260, rotation=(0, rot, 0), texture=t_wall, repeat=(4, 2), roughness=0.2)
    sc.plane((-299, 140, 40), 200, 100, rotation=(0, 90, 0), texture=t_aurora, emissive="#ffffff", shadows=False)

    # A glossy white panel behind the desk, for the calendar and notes.
    sc.box((-82, 135, -86), (62, 112, 3), "#ffffff", roughness=0.1)
    sc.plane((-82, 135, -84.4), 34, 42.5, texture=t_cal, roughness=0.3, live="calendar")
    sc.spot("wall-1", (-62, 104, -84.4), 7, (0, 0, -5), t_n3)
    sc.spot("wall-2", (-60, 172, -84.4), 7, (0, 0, 4))
    sc.spot("wall-3", (-104, 110, -84.4), 7, (0, 0, -3))
    sc.spot("desk", (-34, DESK_Y + 0.06, -12), 7, (-90, 12, 0))

    # A glass desk on chrome legs.
    sc.box((0, DESK_Y - 1, -45), (160, 2, 82), "#a8e4ff", roughness=0.05, metalness=0.1, opacity=0.35)
    sc.box((0, DESK_Y - 2.4, -45), (162, 0.8, 84), "#dff4ff", roughness=0.05, metalness=0.9, opacity=0.5, shadows=False)
    for x in (-76, 76):
        for z in (-10, -80):
            sc.cylinder((x, (DESK_Y - 2) / 2, z), 4, DESK_Y - 2, "#eef4f8", metalness=0.35, roughness=0.18)

    # A glossy white monitor with a glowing halo behind it.
    add_lcd(sc, mon, "#f6f9fc", "#ffffff", "#e6eef4", glossy=True, power="#40e0ff", sticky_notes=[t_n1, t_n2])
    sc.plane((0, mon.y + 2, mon.z - 10), mon.w + 40, mon.h + 34, "#60d8ff", emissive="#3ab8ff", opacity=0.3, shadows=False)
    add_keyboard(sc, "#eef2f6", t_keys)
    sc.box((0, DESK_Y + 0.3, -9), (44, 0.4, 1.2), "#60e0ff", emissive="#40d0ff", shadows=False)
    # Translucent blue mouse mat and a glossy mouse with a glow.
    sc.box((38, DESK_Y + 0.2, -20), (22, 0.4, 18), "#5ac8ff", roughness=0.1, opacity=0.45)
    sc.sphere((38, DESK_Y + 1.6, -20), (6, 3.2, 10), "#ffffff", roughness=0.08)
    sc.sphere((38, DESK_Y + 0.6, -20), (6.6, 0.5, 10.6), "#40d8ff", emissive="#30c8ff", opacity=0.6, shadows=False)
    # Orb speakers on chrome stems.
    for x in (-mon.half_width - 10, mon.half_width + 10):
        sc.cylinder((x, DESK_Y + 0.5, -45), 9, 1, "#eef4f8", metalness=0.35, roughness=0.18)
        sc.cylinder((x, DESK_Y + 5, -45), 1.2, 9, "#eef4f8", metalness=0.35, roughness=0.18)
        sc.sphere((x, DESK_Y + 15, -45), (13, 13, 13), "#ffffff", roughness=0.08)
        sc.cylinder((x, DESK_Y + 15, -38.6), 8, 0.4, "#40d8ff", rotation=(90, 0, 0), emissive="#30c8ff", shadows=False)

    # An aquarium, with fish, weeds and bubbles.
    ax, ay, az = -60, DESK_Y + 12.5, -62
    sc.box((ax, DESK_Y + 0.6, az), (36, 1.2, 22), "#eef4f8", metalness=0.35, roughness=0.18)
    sc.box((ax, ay - 9, az), (32, 4, 18), "#e8d8a8", roughness=0.9)
    sc.box((ax, ay, az), (34, 24, 20), "#2aa8ff", roughness=0.05, opacity=0.3, shadows=False)
    sc.box((ax, ay + 12.3, az), (35, 0.6, 21), "#bfeaff", roughness=0.05, opacity=0.5, shadows=False)
    for i in range(5):
        sc.cylinder((ax - 12 + i * 6, ay - 4, az - 5 + (i % 2) * 6), 1.2, float(rng.uniform(8, 14)), "#30b040",
                    rotation=(float(rng.uniform(-10, 10)), 0, float(rng.uniform(-10, 10))))
    for i, (fx, fy, fz, c) in enumerate(((-6, 3, 0, "#ff8a1e"), (6, -1, 3, "#ffd02a"), (0, 5, -4, "#ff5a8a"))):
        sc.sphere((ax + fx, ay + fy, az + fz), (5, 2.6, 1.8), c, rotation=(0, 20 * i - 15, 0), roughness=0.3)
        sc.sphere((ax + fx + 3, ay + fy, az + fz), (2, 2.8, 0.6), c, roughness=0.3)
    for i in range(10):
        sc.sphere((ax + float(rng.uniform(-14, 14)), ay + float(rng.uniform(-8, 10)), az + float(rng.uniform(-6, 6))),
                  (0.9, 0.9, 0.9), "#ffffff", roughness=0.05, opacity=0.6, shadows=False)

    # Bamboo in a glossy white pot.
    sc.cylinder((92, 16, -62), 24, 32, "#ffffff", roughness=0.08)
    for i in range(5):
        x, z = 92 + float(rng.uniform(-6, 6)), -62 + float(rng.uniform(-6, 6))
        height = float(rng.uniform(90, 140))
        sc.cylinder((x, 32 + height / 2, z), 2.4, height, "#5ab83c", roughness=0.4)
        for k in range(int(height // 22)):
            sc.cylinder((x, 40 + k * 22, z), 2.8, 0.8, "#3e8e2a", roughness=0.4)
        for k in range(3):
            ang = float(rng.uniform(0, 360))
            sc.sphere((x + 5 * math.cos(math.radians(ang)), 32 + height - 6 - k * 9, z + 5 * math.sin(math.radians(ang))),
                      (2.6, 12, 0.8), "#4caa30", rotation=(0, -ang, 50), roughness=0.5)

    # Bubbles everywhere, kept out of the way of the screen.
    placed = 0
    while placed < 18:
        x, y, z = float(rng.uniform(-150, 150)), float(rng.uniform(DESK_Y + 5, 220)), float(rng.uniform(-85, 10))
        size = float(rng.uniform(4, 18))
        in_front_of_screen = abs(x) < mon.half_width + size and y < mon.y + mon.h / 2 + 16 + size and z > mon.z - 12
        on_desk = y < DESK_Y + 18 and abs(x) < 85 and -90 < z < 0
        if in_front_of_screen or on_desk:
            continue
        sc.sphere((x, y, z), (size, size, size), "#c8f2ff" if placed % 2 else "#9ae0ff", roughness=0.03,
                  emissive="#123848", opacity=0.3, shadows=False)
        placed += 1
    # Lens flare orbs by the window.
    for i, (x, y, s) in enumerate(((120, 200, 14), (95, 180, 8), (70, 165, 20))):
        sc.sphere((x, y, -84), (s, s, s), "#ffffff", emissive="#fff8e0", opacity=0.25 + 0.05 * i, shadows=False)

    sc.lights += [
        {"type": "directional", "rotation": quat(-45, 20, 0), "color": "#ffffff", "intensity": 0.8, "shadows": True},
        {"type": "directional", "rotation": quat(-20, 180, 0), "color": "#bfe8ff", "intensity": 0.5, "shadows": False},
        {"type": "point", "position": [0, 230, 0], "color": "#f0faff", "intensity": 1.0, "range": 500},
    ]
    return finish(sc, mon, background="#bfe8ff", ambient=("#d8f0ff", 0.55), fill="#9ed6f2")


# The 2D picture: the room from straight in front of the monitor, so the
# screen is an upright rectangle in it.
PICTURE_W, PICTURE_H = 2400, 1500
PICTURE_FOV = 40


def picture(name, mon, fill, has_notes):
    target = (0, 95, mon.z)
    distance = mon.distance - 10

    def project(x, y, z):
        """Where a point lands in the picture, in pixels from the top left."""
        focal = (PICTURE_H / 2) / math.tan(math.radians(PICTURE_FOV / 2))
        depth = (target[2] + distance) - z
        return (PICTURE_W / 2 + (x - target[0]) * focal / depth,
                PICTURE_H / 2 - (y - target[1]) * focal / depth)

    x0, y0 = project(-mon.w / 2, mon.y + mon.h / 2, mon.z)
    x1, y1 = project(mon.w / 2, mon.y - mon.h / 2, mon.z)
    # The monitor and its stand, which stay in view however the window is shaped.
    mx0, my0 = project(-mon.half_width - 2, mon.top + 1, mon.z)
    mx1, my1 = project(mon.half_width + 2, DESK_Y, mon.z - 1)
    info = {"image": "office-%s-%s.jpg" % (name, mon.name),
            "size": [PICTURE_W, PICTURE_H], "fill": fill,
            "camera": {"target": list(target), "distance": distance, "yaw": 0, "pitch": 0},
            "screen": [round(x0, 1), round(y0, 1), round(x1 - x0, 1), round(y1 - y0, 1)],
            "monitor": [round(mx0, 1), round(my0, 1), round(mx1 - mx0, 1), round(my1 - my0, 1)]}
    if has_notes:
        # The same picture with the sticky notes turned off.
        info["imageWithoutNotes"] = "office-%s-%s-nonotes.jpg" % (name, mon.name)
    return info


# The order notes are placed in: the first one on the monitor's bezel, and so on.
NOTE_SPOT_ORDER = ["bezel-left", "right-side", "wall-1", "bezel-right", "wall-2", "wall-3", "desk", "left-side"]


def finish(sc, mon, background, ambient, fill):
    return {
        "name": sc.name,
        "background": background,
        "ambient": {"color": ambient[0], "intensity": ambient[1]},
        # An orbit camera around the middle of the screen; angles in degrees,
        # yaw turns left/right, negative pitch looks down from above.
        "camera": {"target": [0, mon.y, mon.z], "distance": mon.distance, "yaw": 0, "pitch": -10,
                   "fov": 40, "near": 5, "far": 3000,
                   "minDistance": 30, "maxDistance": 280,
                   "minYaw": -80, "maxYaw": 80, "minPitch": -55, "maxPitch": 30},
        "screen": {"position": [0, mon.y, mon.z], "size": [mon.w, mon.h], "rotation": quat()},
        "picture": picture(sc.name, mon, fill, any("texture" in s for s in sc.spots.values())),
        # Light cast by the screen, in the profile's text colour.
        "screenGlow": {"position": [0, mon.y, mon.z + 15], "intensity": 0.6, "range": 120},
        "lights": sc.lights,
        "objects": sc.objects,
        "noteSpots": [sc.spots[name] for name in NOTE_SPOT_ORDER],
    }


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(repo, "app", "qml", "office")
    os.makedirs(out, exist_ok=True)
    # The picture at the top of the live calendar, which the apps draw
    # under the month name.
    save(calendar_90s().crop((16, 16, 368, 200)), out, "calendar-picture.jpg")
    for room, builder, seed, monitors in (("70s", room_70s, 1975, (TERM_STANDARD, TERM_WIDE)),
                                          ("80s", room_80s, 1984, (STANDARD, WIDE)),
                                          ("90s", room_90s, 1995, (STANDARD, WIDE)),
                                          ("2000s", room_2000s, 2004, (LCD_STANDARD, LCD_WIDE)),
                                          ("gloss", room_gloss, 2007, (LCD_STANDARD, LCD_WIDE))):
        for mon in monitors:
            scene = builder(out, np.random.default_rng(seed), mon)
            name = "office-%s-%s.json" % (room, mon.name)
            with open(os.path.join(out, name), "w", encoding="utf-8") as f:
                json.dump(scene, f, indent=1)
                f.write("\n")
            print("wrote %s: %d objects" % (name, len(scene["objects"])), file=sys.stderr)


if __name__ == "__main__":
    main()
