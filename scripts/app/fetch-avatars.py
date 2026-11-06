#!/usr/bin/env python3
"""docs/credits.json -> app/src/main/assets/{avatars/<login>.webp,contributors.json}
usage: fetch-avatars.py   (needs network and Pillow)"""
import io, json, os, urllib.request
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "docs", "credits.json")
OUT = os.path.join(ROOT, "app", "src", "main", "assets")
AV = os.path.join(OUT, "avatars")
SIZE = 96


def walk(o):
    if isinstance(o, dict):
        if o.get("github"):
            yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


os.makedirs(AV, exist_ok=True)
seen, rows = set(), []
for d in walk(json.load(open(SRC, encoding="utf-8"))):
    login = d["github"]
    if login.lower() in seen:
        continue
    seen.add(login.lower())
    ok = False
    try:
        req = urllib.request.Request(
            "https://github.com/%s.png?size=%d" % (login, SIZE * 2),
            headers={"User-Agent": "seiran-avatars"})
        img = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=20).read()))
        img = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        img.save(os.path.join(AV, login + ".webp"), "WEBP", quality=80)
        ok = True
    except Exception as e:
        print("SKIP %s: %s" % (login, e))
    rows.append({"login": login, "name": d.get("name", login), "avatar": ok})
json.dump(rows, open(os.path.join(OUT, "contributors.json"), "w", encoding="utf-8"), indent=1)
print("OK: %d logins, %d avatars" % (len(rows), sum(r["avatar"] for r in rows)))
