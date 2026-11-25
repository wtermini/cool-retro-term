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
[x, y, z, w]. Objects with "group": "sticky-notes" are hidden when the
sticky notes are turned off. Objects with "live" are drawn by the apps
from the desk data (office-desk.json: the notes' text and the calendar's
events) instead of their texture, which is kept for the 2D pictures:
"note:monitor", "note:side" and "note:wall" are the three sticky notes,
and "calendar" is the wall calendar. Light intensities are in Qt Quick 3D's brightness units
(1 = its default).

Requires Pillow and numpy.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

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

    def add(self, shape, position, size, color="#808080", rotation=(0, 0, 0), texture=None,
            repeat=(1, 1), roughness=0.7, metalness=0.0, emissive=None, shadows=True, group=None,
            live=None):
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


def add_monitor(sc, mon, casing, casing_dark, sticky_notes=()):
    """The monitor, screen facing +Z. `sticky_notes` are up to two note
    textures: the first goes on the bezel above the top left corner of the
    screen, the second on the right side of the casing."""
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
    for i, tex in enumerate(sticky_notes):
        if i == 0:
            sc.plane((-mon.w / 2 + size / 2 + 1, sy + mon.h / 2 + top_border / 2, sz - 0.45), size, size,
                     rotation=(0, 0, 4), texture=tex, shadows=False, group="sticky-notes", live="note:monitor")
        else:
            sc.plane((mon.half_width + 0.05, sy - 4, sz - 5), 6, 6, rotation=(0, 90, -5), texture=tex,
                     shadows=False, group="sticky-notes", live="note:side")


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
    sc.plane((-14, 164, -89.3), 7, 7, rotation=(0, 0, -6), texture=t_n3, shadows=False, group="sticky-notes",
             live="note:wall")
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
    sc.plane((-91.8, 110, -40), 7, 7, rotation=(0, 90, 0), texture=t_green, shadows=False, group="sticky-notes",
             live="note:wall")

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
        "picture": picture(sc.name, mon, fill, any(o.get("group") == "sticky-notes" for o in sc.objects)),
        # Light cast by the screen, in the profile's text colour.
        "screenGlow": {"position": [0, mon.y, mon.z + 15], "intensity": 0.6, "range": 120},
        "lights": sc.lights,
        "objects": sc.objects,
    }


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(repo, "app", "qml", "office")
    os.makedirs(out, exist_ok=True)
    # The picture at the top of the live calendar, which the apps draw
    # under the month name.
    save(calendar_90s().crop((16, 16, 368, 200)), out, "calendar-picture.jpg")
    for room, builder, seed in (("80s", room_80s, 1984), ("90s", room_90s, 1995)):
        for mon in (STANDARD, WIDE):
            scene = builder(out, np.random.default_rng(seed), mon)
            name = "office-%s-%s.json" % (room, mon.name)
            with open(os.path.join(out, name), "w") as f:
                json.dump(scene, f, indent=1)
                f.write("\n")
            print("wrote %s: %d objects" % (name, len(scene["objects"])), file=sys.stderr)


if __name__ == "__main__":
    main()
