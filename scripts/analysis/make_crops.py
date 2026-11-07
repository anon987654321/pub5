#!/usr/bin/env python3
"""Crops and sheet 5 for the screenshot review (pub5 layout). pyvips / libvips.

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


def cap(text, width, size=26):
    t = pyvips.Image.text(text, font=f"DejaVu Sans {size}", dpi=72,
                          width=width, align="low")
    return t


def labelled(img_ref, text, crop=None, scale=1.0):
    im = img_ref
    if crop:
        left, top, w, h = crop
        im = im.crop(left, top, w, h)
    if scale != 1.0:
        im = im.resize(scale)
    c = cap(text, im.width)
    return c.join(im, "vertical", expand=True, background=BG)


def row(tiles, bg=BG):
    h = max(t.height for t in tiles)
    tiles = [t.embed(0, 0, t.width, h, background=bg) for t in tiles]
    out = tiles[0]
    for t in tiles[1:]:
        out = out.join(t, "horizontal", expand=True, background=bg, shim=GAP)
    return out


def stack(rows, bg=BG):
    w = max(r.width for r in rows)
    rows = [r.embed(0, 0, w, r.height, background=bg) for r in rows]
    out = rows[0]
    for r in rows[1:]:
        out = out.join(r, "vertical", expand=True, background=bg, shim=GAP)
    return out


def save(image, name):
    image.jpegsave(os.path.join(OUT, name), Q=85)
    print(name, image.width, "x", image.height)


def shot(app, f):
    return os.path.join(SHOTS[app], f + ".png")

# ---- Sheet 5: remaining mrdamascy screens (2 rows x 5) ---------------
names = ["02-menu-en", "04-menu-after-add", "07-tracking", "08-loyalty-guest",
         "09-about", "10-login", "11-offline", "12-vipps-login-mock",
         "13-staff-board", "14-orders"]
t5 = [labelled(img(shot("mrdamascy", n)), n, scale=0.6) for n in names]
save(stack([row(t5[0:5]), row(t5[5:10])]), "s5-mrdamascy-rest.jpg")

# ---- Crop sheet 1 -----------------------------------------------------
parts = []
# nav strip: brgen desktop vs maps desktop vs radio desktop (AI badge)
for app, f, y in [("brgen", "brgen-desktop", 18),
                  ("brgen_maps", "maps-desktop", 18),
                  ("brgen_radio", "radio-desktop", 18)]:
    parts.append(labelled(
        img(shot(app, f)),
        f"{f}: nav strip y={y}", crop=(0, y, 900, 64)))
# maps-mobile header ("place" leak) and search row
mm = img(shot("brgen_maps", "maps-mobile"))
parts.append(labelled(mm, "maps-mobile: page top", crop=(0, 0, 390, 150)))
parts.append(labelled(mm, "maps-mobile: search row", crop=(0, 40, 390, 110)))
# amber-desktop: wordmark, Bymorgen tile, footer wordmark
ad = img(shot("amber", "amber-desktop"))
parts.append(labelled(ad, "amber-desktop: header wordmark", crop=(900, 0, 540, 130)))
parts.append(labelled(ad, "amber-desktop: Bymorgen tile", crop=(940, 1750, 500, 320)))
parts.append(labelled(ad, "amber-desktop: footer wordmark", crop=(950, 2820, 490, 190)))
# amber-mobile: nav + Bymorgen tile with label above
am = img(shot("amber", "amber-mobile"))
parts.append(labelled(am, "amber-mobile: nav row", crop=(0, 30, 390, 70)))
parts.append(labelled(am, "amber-mobile: Bymorgen tile", crop=(0, 1330, 390, 260)))
c1 = stack(parts)
save(c1, "c1-crops-a.jpg")

# ---- Crop sheet 2 -----------------------------------------------------
parts = []
# dating-desktop hero: eyebrow + Oppdag + pills
dd = img(shot("brgen_dating", "dating-desktop"))
parts.append(labelled(dd, "dating-desktop: hero + pills", crop=(560, 40, 700, 160)))
# tv-desktop: hero + chips + section head + card
tv = img(shot("brgen_radio", "tv-desktop"))
parts.append(labelled(tv, "tv-desktop: hero + chips", crop=(380, 40, 680, 220)))
parts.append(labelled(tv, "tv-desktop: card + caption", crop=(380, 260, 680, 330)))
# radio: desktop section head vs mobile section head
rd = img(shot("brgen_radio", "radio-desktop"))
parts.append(labelled(rd, "radio-desktop: Utvalg label + Bla knapp", crop=(380, 200, 680, 160)))
rm = img(shot("brgen_radio", "radio-mobile"))
parts.append(labelled(rm, "radio-mobile: Utvalg label", crop=(0, 220, 390, 130)))
# bsdports-mobile: top bar + mid-list controls
bm = img(shot("bsdports", "bsdports-mobile"))
parts.append(labelled(bm, "bsdports-mobile: top bar", crop=(0, 0, 390, 70)))
parts.append(labelled(bm, "bsdports-mobile: mid-list controls", crop=(0, 1750, 390, 220)))
# messenger-desktop heading box
md = img(shot("brgen_messenger", "messenger-desktop"))
parts.append(labelled(md, "messenger-desktop: Meldinger heading box", crop=(180, 60, 800, 160)))
c2 = stack(parts)
save(c2, "c2-crops-b.jpg")

# ---- Crop sheet 3 -----------------------------------------------------
parts = []
# mrdamascy 01: status line + hours line 1:1
menu = img(shot("mrdamascy", "01-menu"))
parts.append(labelled(menu, "01-menu: status line 1:1", crop=(0, 0, 500, 60)))
parts.append(labelled(menu, "01-menu: hours line 1:1", crop=(0, 250, 500, 90)))
# 03 item chips 1:1
sheet3 = img(shot("mrdamascy", "03-item-sheet"))
parts.append(labelled(sheet3, "03: ingredient chips 1:1", crop=(0, 470, 500, 260)))
# 05 cart copy 1:1
cart = img(shot("mrdamascy", "05-cart"))
parts.append(labelled(cart, "05-cart: empty copy 1:1", crop=(0, 90, 500, 200)))
# marketplace-desktop hero
mkd = img(shot("brgen_marketplace", "marketplace-desktop"))
parts.append(labelled(mkd, "marketplace-desktop: info strip + hero", crop=(620, 0, 820, 300), scale=0.9))
# brgen-desktop: composer + floating logg inn
bd = img(shot("brgen", "brgen-desktop"))
parts.append(labelled(bd, "brgen-desktop: composer + floating pill", crop=(780, 60, 660, 320)))
c3 = stack(parts)
save(c3, "c3-crops-c.jpg")

print("done")
