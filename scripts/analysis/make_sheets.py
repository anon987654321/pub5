#!/usr/bin/env python3
"""Contact-sheet builder for the Rails screenshot review (pub5 layout).

Carried from pub4's scripts/analysis and adapted to pub5: the brgen
engines now live under rails/brgen/engines/. Uses pyvips (libvips) to
honour the repository's libvips / ruby-vips image stack. Sheets go to
/tmp/render/sheets/ for review.

Usage: python3 make_sheets.py
"""
import os
import pyvips

ROOT = os.environ.get("REVIEW_ROOT", os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.environ.get("REVIEW_OUT", "/tmp/render/sheets")
os.makedirs(OUT, exist_ok=True)

GAP = 14
BG = 235

# app name -> screenshot directory in pub5
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


def load(path):
    return pyvips.Image.new_from_file(os.path.join(ROOT, path), access="sequential")


def labelled_tile(path, width):
    """Thumbnail to width; prepend a small caption strip when text works."""
    src = load(path)
    img = src.resize(width / src.width)
    name = path.split("/")[-1].replace(".png", "").replace(".jpg", "")
    try:
        text = pyvips.Image.text(
            name, font="DejaVu Sans 20", dpi=72,
            width=img.width, align="centre",
        )
        text = text.embed(-1, -3, img.width, text.height + 4, background=BG)
        sheet = text.join(img, "vertical", expand=True, background=BG)
    except Exception:
        sheet = img
    return sheet


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


def save(img, name):
    img.jpegsave(os.path.join(OUT, name), Q=82)
    print(name, img.width, "x", img.height)


def shot(app, f):
    return os.path.join(SHOTS[app], f + ".png")

# ---- Sheet 1: desktop A (3 x 2) --------------------------------------
apps1 = [("brgen", "brgen-desktop"), ("brgen_maps", "maps-desktop"),
         ("brgen_marketplace", "marketplace-desktop"),
         ("brgen_messenger", "messenger-desktop"),
         ("brgen_radio", "radio-desktop"), ("bsdports", "bsdports-desktop")]
t1 = [labelled_tile(shot(app, f), 730) for app, f in apps1]
save(stack([row(t1[0:3]), row(t1[3:6])]), "s1-desktop-a.jpg")

# ---- Sheet 2: desktop B (3 x 1) --------------------------------------
apps2 = [("brgen_radio", "tv-desktop"), ("brgen_dating", "dating-desktop"),
         ("amber", "amber-desktop")]
t2 = [labelled_tile(shot(app, f), 730) for app, f in apps2]
save(row(t2), "s2-desktop-b.jpg")

# ---- Sheet 3: mobile A, one row of 6 full pages ----------------------
apps3 = [("brgen_messenger", "messenger-mobile"),
         ("bsdports", "bsdports-mobile"),
         ("brgen_radio", "radio-mobile"),
         ("brgen_radio", "tv-mobile"),
         ("brgen_dating", "dating-mobile"),
         ("amber", "amber-mobile")]
t3 = [labelled_tile(shot(app, f), 300) for app, f in apps3]
save(row(t3), "s3-mobile-a.jpg")

# ---- Sheet 4: mobile B + mrdamascy key frames ------------------------
t4 = [labelled_tile(shot("brgen", "brgen-mobile"), 300),
      labelled_tile(shot("brgen_maps", "maps-mobile"), 300),
      labelled_tile(shot("brgen_marketplace", "marketplace-mobile"), 300),
      labelled_tile(shot("mrdamascy", "01-menu"), 300),
      labelled_tile(shot("mrdamascy", "03-item-sheet"), 300),
      labelled_tile(shot("mrdamascy", "05-cart"), 300),
      labelled_tile(shot("mrdamascy", "06-checkout"), 300)]
save(row(t4), "s4-mobile-b-mrdamascy.jpg")

print("done")
