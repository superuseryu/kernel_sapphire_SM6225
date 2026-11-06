#!/usr/bin/env python3
"""docs/credits.md <-> docs/credits.json

usage: credits.py import   read credits.md, write credits.json
       credits.py render   read credits.json, write credits.md
       credits.py check    render in memory, compare with credits.md (rc 1 on diff)
"""
import json, os, re, sys
from urllib.parse import urlparse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MD = os.path.join(ROOT, "docs", "credits.md")
JS = os.path.join(ROOT, "docs", "credits.json")
DASH = "\u2014"
ENTRY = re.compile(r"^- \*\*\[(.+?)\]\((.+?)\)\*\* " + DASH + r" (.*)$")
MAINT = re.compile(r"^\*\*(.+?)\*\* " + DASH + r" (.*)$")
TG = re.compile(r"^- Telegram: \[(.+?)\]\((.+?)\)$")


def github_login(url):
    u = urlparse(url)
    if u.netloc.lower() != "github.com":
        return None
    parts = [p for p in u.path.split("/") if p]
    return parts[0] if parts else None


def entry(m):
    return {"name": m.group(1), "url": m.group(2), "description": m.group(3),
            "github": github_login(m.group(2))}


def parse(text):
    sect, data = None, {"maintainer": {}, "credits": [], "inspiration": {"intro": "", "entries": []}}
    for ln in text.split("\n"):
        if ln.startswith("## "):
            sect = ln[3:]
            continue
        if sect == "Maintainer":
            m = MAINT.match(ln)
            if m:
                data["maintainer"].update(name=m.group(1), description=m.group(2),
                                          github=m.group(1))
            t = TG.match(ln)
            if t:
                data["maintainer"].update(telegram_text=t.group(1), telegram_url=t.group(2))
        elif sect == "Thanks & Credits":
            m = ENTRY.match(ln)
            if m:
                data["credits"].append(entry(m))
        elif sect == "Inspiration":
            m = ENTRY.match(ln)
            if m:
                data["inspiration"]["entries"].append(entry(m))
            elif ln and not ln.startswith(("---", "*Missing")):
                data["inspiration"]["intro"] = ln
    return data


def line(e):
    return "- **[%s](%s)** %s %s" % (e["name"], e["url"], DASH, e["description"])


def render(d):
    m = d["maintainer"]
    out = ["# Credits", "", "---", "", "## Maintainer", "",
           "**%s** %s %s" % (m["name"], DASH, m["description"]), "",
           "- Telegram: [%s](%s)" % (m["telegram_text"], m["telegram_url"]), "",
           "---", "", "## Thanks & Credits", ""]
    out += [line(e) for e in d["credits"]]
    out += ["", "---", "", "## Inspiration", "", d["inspiration"]["intro"], ""]
    out += [line(e) for e in d["inspiration"]["entries"]]
    out += ["", "---", "",
            "*Missing credit? \u2192 [%s](%s)*" % (m["telegram_text"], m["telegram_url"])]
    return "\n".join(out) + "\n"


def rd(p):
    with open(p, encoding="utf-8", newline="") as f:
        return f.read()


def wr(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "import":
        wr(JS, json.dumps(parse(rd(MD)), indent=2, ensure_ascii=False) + "\n")
        print("[OK] wrote docs/credits.json")
    elif cmd == "render":
        wr(MD, render(json.loads(rd(JS))))
        print("[OK] wrote docs/credits.md")
    elif cmd == "check":
        if render(json.loads(rd(JS))) == rd(MD):
            print("[OK] credits.md matches credits.json")
        else:
            print("[FAIL] credits.md differs from credits.json")
            sys.exit(1)
    else:
        sys.exit(__doc__)


main()
