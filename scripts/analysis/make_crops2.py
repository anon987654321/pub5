#!/usr/bin/env python3
"""Corrected crops (round 2) for the screenshot review (pub5 layout). pyvips / libvips.

Carried from pub4's scripts/analysis; the brgen engines now live under
rails/brgen/engines/ and the roots are environment-overridable.
"""
import os
import pyvips

ROOT = os.environ.get("REVIEW_ROOT", os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.environ.get("REVIEW_OUT", "/tmp/render/sheets")
GAP = 14
BG = 235

SHOTS = {
    "brgen": "rails/brgen/screenshots",
    "amber": "rails/amber/screenshots",
    "bsdports": "rails/bsdports/screenshots",
    "mrdamascy": "rails/mrdamascy/screenshots",
    "brgen_dating": "rails/brgen/engines/dating/screenshots",
    "brgen_maps": "rails/brgen/engines/maps/screenshots",
    "brgen_marketplace": "rails/brgen/engines/marketplace/screenshots",
    "brgen_messenger": "rails/brgen/engines/messenger/screenshots",
    "brgen_radio": "rails/brgen/engines/radio/screenshots",
}


def img(path):
    return pyvips.Image.new_from_file(os.path.join(ROOT, path), access="random")


def labelled(ref, text, crop=None, scale=1.0):
    im = ref
    if crop:
        left, top, w, h = crop
        im = im.crop(left, top, w, h)
    if scale != 1.0:
        im = im.resize(scale)
    t = pyvips.Image.text(text, font="DejaVu Sans 22", dpi=72,
                          width=im.width, align="low")
    return t.join(im, "vertical", expand=True, background=BG)


def stack(rows):
    w = max(r.width for r in rows)
    rows = [r.embed(0, 0, w, r.height, background=BG) for r in rows]
    out = rows[0]
    for r in rows[1:]:
        out = out.join(r, "vertical", expand=True, background=BG, shim=GAP)
    return out


def save(image, name):
    image.jpegsave(os.path.join(OUT, name), Q=85)
    print(name, image.width, "x", image.height)


def shot(app, f):
    return os.path.join(SHOTS[app], f + ".png")


ad = img(shot("amber", "amber-desktop"))
am = img(shot("amber", "amber-mobile"))
dd = img(shot("brgen_dating", "dating-desktop"))
tv = img(shot("brgen_radio", "tv-desktop"))
rd = img(shot("brgen_radio", "radio-desktop"))
rm = img(shot("brgen_radio", "radio-mobile"))
bm = img(shot("bsdports", "bsdports-mobile"))
mk = img(shot("brgen_marketplace", "marketplace-desktop"))
md = img(shot("brgen_maps", "maps-desktop"))

parts = [
    labelled(ad, "amber-desktop: wordmark + nav", crop=(380, 30, 720, 180)),
    labelled(ad, "amber-desktop: Bymorgen tile", crop=(430, 1520, 580, 360)),
    labelled(ad, "amber-desktop: footer wordmark", crop=(420, 2830, 580, 160)),
    labelled(am, "amber-mobile: tile", crop=(0, 580, 390, 320)),
    labelled(dd, "dating-desktop: pills", crop=(560, 110, 760, 200)),
    labelled(tv, "tv-desktop: chips + section", crop=(300, 200, 900, 420), scale=0.85),
    labelled(rd, "radio-desktop: Utvalgt spor + knapp", crop=(380, 380, 700, 200)),
    labelled(rm, "radio-mobile: spor label", crop=(0, 340, 390, 180)),
    labelled(bm, "bsdports-mobile: import row", crop=(0, 1350, 390, 180)),
    labelled(mk, "marketplace-desktop: hero price", crop=(60, 400, 620, 220)),
    labelled(md, "maps-desktop: nav bleed 1:1", crop=(0, 0, 720, 120)),
]
v12 = img(shot("mrdamascy", "12-vipps-login-mock"))
parts.append(labelled(v12, "mrdamascy 12: buttons", crop=(0, 380, 500, 220)))
v13 = img(shot("mrdamascy", "13-staff-board"))
parts.append(labelled(v13, "mrdamascy 13: status rows", crop=(0, 100, 500, 220)))
v07 = img(shot("mrdamascy", "07-tracking"))
parts.append(labelled(v07, "mrdamascy 07: tail lines", crop=(0, 300, 500, 260)))
v08 = img(shot("mrdamascy", "08-loyalty-guest"))
parts.append(labelled(v08, "mrdamascy 08: stempler line", crop=(0, 50, 500, 140)))

save(stack(parts), "c4-crops-d.jpg")
print("done")
