#!/usr/bin/env python3
"""Asset budgets and license bookkeeping (docs/ASSET_BUDGETS.md). Exits 1 on a breach.

    python3 tools/check_budgets.py                    # repo checks (+ dist/ if exported)
    python3 tools/check_budgets.py --web-log LOG      # also the title-up time from web_check.mjs

Checks:
  - the web .pck size (when dist/index.pck exists);
  - resources/baked/: total PNG bytes, each sheet's sides (the 2048 px WebGL2 floor), the
    RGBA8 texture memory they decode to, and that every sheet the manifest names exists;
  - assets/cc0/: every file has a LICENSES.md row, its sha256 matches the row, the row's
    license is CC0-1.0, and every manifest entry passes fetch_cc0's checks;
  - resources/sfx/: every crunched .wav is an AudioSys slot backed by a manifest entry;
  - with --web-log: title up within budget.
The stale-bake check (the manifest's source hash) needs Godot, so it lives in the smoke test.
"""
import hashlib
import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import fetch_cc0  # noqa: E402
import crunch_sfx  # noqa: E402

MB = 1024 * 1024
BUDGETS = {
    "pck_bytes": int(2.5 * MB),         # today 1.66 MB
    "baked_png_bytes": int(2.0 * MB),   # today 1.17 MB
    "sheet_side_px": 2048,              # SpriteForge.MAX_SHEET_PX
    "baked_rgba_bytes": 32 * MB,        # today ~11 MB decoded
    "title_up_ms": 6500,                # web_check on SwiftShader; today 5.2-5.8 s
}
BAKED = os.path.join(ROOT, "resources", "baked")
SFX_OUT = os.path.join(ROOT, "resources", "sfx")
CC0 = os.path.join(ROOT, "assets", "cc0")
LICENSES = os.path.join(ROOT, "assets", "LICENSES.md")
PCK = os.path.join(ROOT, "dist", "index.pck")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", head[16:24])


def license_rows(path=LICENSES):
    rows = {}
    if not os.path.exists(path):
        return rows
    for line in open(path):
        m = re.match(r"\|\s*`([^`]+)`\s*\|(.*)", line)
        if not m:
            continue
        cols = [c.strip() for c in m.group(2).split("|")]
        # | File | Kind | Source | URL | License | Fetched | sha256 |
        if len(cols) >= 6:
            rows[m.group(1)] = {"kind": cols[0], "source": cols[1], "url": cols[2],
                                "license": cols[3], "sha256": cols[5].strip("`")}
    return rows


def check(web_log=None):
    fails, notes = [], []

    if os.path.exists(PCK):
        size = os.path.getsize(PCK)
        notes.append("pck %.2f MB (budget %.1f)" % (size / MB, BUDGETS["pck_bytes"] / MB))
        if size > BUDGETS["pck_bytes"]:
            fails.append("dist/index.pck is %.2f MB, over %.1f MB" % (size / MB, BUDGETS["pck_bytes"] / MB))

    man_path = os.path.join(BAKED, "manifest.json")
    if not os.path.exists(man_path):
        fails.append("resources/baked/manifest.json is missing (run tools/bake_sprites.tscn)")
    else:
        man = json.load(open(man_path))
        png_total, rgba = 0, 0
        for sh in man.get("sheets", []):
            p = os.path.join(BAKED, sh["file"])
            if not os.path.exists(p):
                fails.append("baked sheet %s is in the manifest but missing" % sh["file"])
                continue
            w, h = png_size(p)
            png_total += os.path.getsize(p)
            rgba += w * h * 4
            if max(w, h) > BUDGETS["sheet_side_px"]:
                fails.append("%s is %dx%d, over %d px" % (sh["file"], w, h, BUDGETS["sheet_side_px"]))
            if w != sh["angles"] * sh["cell"] or h != len(sh["ids"]) * sh["anim"] * sh["cell"]:
                fails.append("%s is %dx%d, which doesn't match its manifest layout" % (sh["file"], w, h))
            if not os.path.exists(p + ".import") or 'importer="keep"' not in open(p + ".import").read():
                fails.append("%s needs an importer=\"keep\" .import (rebake)" % sh["file"])
        for f in os.listdir(BAKED):
            if f.endswith(".png") and f not in {s["file"] for s in man.get("sheets", [])}:
                fails.append("resources/baked/%s isn't in the manifest (stale; rebake)" % f)
        notes.append("baked PNG %.2f MB (budget %.1f), %.1f MB as RGBA8 (budget %d)" % (
            png_total / MB, BUDGETS["baked_png_bytes"] / MB, rgba / MB, BUDGETS["baked_rgba_bytes"] // MB))
        if png_total > BUDGETS["baked_png_bytes"]:
            fails.append("baked PNGs total %.2f MB, over %.1f MB" % (png_total / MB, BUDGETS["baked_png_bytes"] / MB))
        if rgba > BUDGETS["baked_rgba_bytes"]:
            fails.append("baked sheets decode to %.1f MB, over %d MB" % (rgba / MB, BUDGETS["baked_rgba_bytes"] // MB))

    rows = license_rows()
    for kind_dir in ("models", "sfx"):
        d = os.path.join(CC0, kind_dir)
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if f.startswith("."):
                continue
            rel = "cc0/%s/%s" % (kind_dir, f)
            row = rows.get(rel)
            if row is None:
                fails.append("assets/%s has no LICENSES.md row (fetch it with tools/fetch_cc0.py)" % rel)
                continue
            if row["license"] != fetch_cc0.LICENSE_OK:
                fails.append("assets/%s is licensed %r, not CC0-1.0" % (rel, row["license"]))
            if fetch_cc0.sha256_of(os.path.join(d, f)) != row["sha256"]:
                fails.append("assets/%s doesn't match its LICENSES sha256" % rel)
    for rel, row in rows.items():
        if not os.path.exists(os.path.join(ROOT, "assets", rel)):
            notes.append("LICENSES row %s has no file (not fetched here)" % rel)
    entries = fetch_cc0.load_manifest()
    for e in entries:
        try:
            fetch_cc0.check_entry(e)
        except fetch_cc0.Refused as err:
            fails.append("manifest: %s" % err)
    slots = {e.get("slot", e.get("name")) for e in entries if e.get("kind") == "sfx"}
    for f in sorted(os.listdir(SFX_OUT)) if os.path.isdir(SFX_OUT) else []:
        if not f.endswith(".wav"):
            continue
        slot = f[:-4]
        if slot not in crunch_sfx.SLOTS:
            fails.append("resources/sfx/%s isn't an AudioSys slot" % f)
        elif slot not in slots:
            fails.append("resources/sfx/%s has no CC0 manifest entry behind it" % f)
    notes.append("%d CC0 entries, %d LICENSES rows" % (len(entries), len(rows)))

    if web_log:
        m = re.search(r"title up (\d+) ms", open(web_log).read())
        if not m:
            fails.append("%s has no 'title up' line" % web_log)
        else:
            ms = int(m.group(1))
            notes.append("title up %d ms (budget %d)" % (ms, BUDGETS["title_up_ms"]))
            if ms > BUDGETS["title_up_ms"]:
                fails.append("title up %d ms, over %d ms" % (ms, BUDGETS["title_up_ms"]))
    return fails, notes


def main(argv):
    web_log = argv[argv.index("--web-log") + 1] if "--web-log" in argv else None
    fails, notes = check(web_log)
    for n in notes:
        print("  " + n)
    for f in fails:
        print("BUDGET FAIL: " + f)
    print("BUDGETS OK" if not fails else "BUDGETS FAILED (%d)" % len(fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
