#!/usr/bin/env python3
"""Fetch the pinned CC0 sources listed in assets/cc0/manifest.json.

Hard rule 1 (CLAUDE.md): third-party content is allowed only as CC0, only as 3D models
used as sprite sources or as sound effects, and every file is logged in
assets/LICENSES.md. This tool is the only way such a file enters the repo:

    python3 tools/fetch_cc0.py fetch <name>    # one manifest entry
    python3 tools/fetch_cc0.py fetch --all
    python3 tools/fetch_cc0.py place <name> <local file>   # a hand-downloaded file
    python3 tools/fetch_cc0.py list
    python3 tools/fetch_cc0.py --self-test

A manifest entry is
    {"name": "drone_hull", "kind": "model" | "sfx", "url": "https://...",
     "file": "drone_hull.glb", "license": "CC0-1.0", "source": "Kenney",
     "sha256": "<64 hex>"}

Some hosts only serve people in a browser (Drive folders, sites that turn away scripts).
Those entries carry "manual": true, with the pack page as "url" (the page that states
CC0) and "from" naming the file inside the pack. `place` checks a hand-downloaded file
against the same pin and rules, and `fetch --all` skips manual entries.

It refuses an entry that isn't exactly CC0-1.0, a download whose sha256 doesn't match
its pin, and any name, file or URL containing a blocked word (hard rule 2). The blocked
words are stored as sha256 digests so this file never spells them out. Standard
library only, so it runs on the Neo and in CI without installs.
"""
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CC0_DIR = os.path.join(ROOT, "assets", "cc0")
MANIFEST = os.path.join(CC0_DIR, "manifest.json")
LICENSES = os.path.join(ROOT, "assets", "LICENSES.md")
KIND_DIRS = {"model": "models", "sfx": "sfx"}
LICENSE_OK = "CC0-1.0"
KIND_EXT = {"model": (".glb", ".gltf"), "sfx": (".wav", ".ogg", ".mp3", ".flac")}

# sha256 of lowercase words that must never appear in a committed name or URL (the
# '95 game and its studio and publisher). Compared against every token of the text
# and every pair of neighbouring tokens run together.
BLOCKED = {
    "da7f85eaf3d0452479031da124d28778aaf15cc756a6c909d7dc708fade343f0",
    "28a899f3d49fcc26d8509418e990d20833a29f3cbe763553e2c8c599f2da3b54",
    "64a5c32ff2f645e579822a9fac34ad39464fa85cc9382149beaa43046bc5d073",
    "d9107399381c58d33d5d6d4446fe9ff3386f1797f2d9420efb16a54a8bad1b28",
}

TABLE_HEAD = ("| File | Kind | Source | URL | License | Fetched | sha256 |\n"
              "|---|---|---|---|---|---|---|\n")


class Refused(Exception):
    pass


def _digest(word):
    return hashlib.sha256(word.encode()).hexdigest()


def blocked(text):
    tokens = [t for t in re.split(r"[^a-z0-9]+", text.lower()) if t]
    words = set(tokens)
    words.update(a + b for a, b in zip(tokens, tokens[1:]))
    joined = "".join(tokens)
    for w in words:
        if _digest(w) in BLOCKED:
            return True
    # run-together names ("SomeStudioSounds") are caught by every substring of 4-14 chars
    for n in range(4, 15):
        for i in range(0, max(0, len(joined) - n + 1)):
            if _digest(joined[i:i + n]) in BLOCKED:
                return True
    return False


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest(path=MANIFEST):
    with open(path) as f:
        data = json.load(f)
    return data.get("files", [])


def check_entry(e):
    for key in ("name", "kind", "url", "file", "license", "source", "sha256"):
        if not e.get(key):
            raise Refused("%s: missing %r" % (e.get("name", "?"), key))
    if e["license"] != LICENSE_OK:
        raise Refused("%s: license %r is not %s" % (e["name"], e["license"], LICENSE_OK))
    if e["kind"] not in KIND_DIRS:
        raise Refused("%s: kind %r is not one of %s" % (e["name"], e["kind"], sorted(KIND_DIRS)))
    if not e["file"].lower().endswith(KIND_EXT[e["kind"]]):
        raise Refused("%s: %s files must end in %s" % (e["name"], e["kind"], KIND_EXT[e["kind"]]))
    if os.path.basename(e["file"]) != e["file"]:
        raise Refused("%s: file must be a bare name" % e["name"])
    if not re.fullmatch(r"[0-9a-f]{64}", e["sha256"]):
        raise Refused("%s: sha256 pin must be 64 lowercase hex" % e["name"])
    for field in ("name", "file", "url", "source"):
        if blocked(e[field]):
            raise Refused("%s: %s contains a blocked word (hard rule 2)" % (e["name"], field))


def fetch(e, cc0_dir=CC0_DIR, licenses=LICENSES):
    check_entry(e)
    dest_dir = os.path.join(cc0_dir, KIND_DIRS[e["kind"]])
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, e["file"])
    fd, tmp = tempfile.mkstemp(dir=dest_dir, suffix=".part")
    os.close(fd)
    try:
        with urllib.request.urlopen(e["url"], timeout=60) as r, open(tmp, "wb") as out:
            shutil.copyfileobj(r, out)
        got = sha256_of(tmp)
        if got != e["sha256"]:
            raise Refused("%s: sha256 %s does not match the pin %s" % (e["name"], got, e["sha256"]))
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    log_license(e, licenses)
    return dest


def place(e, src, cc0_dir=CC0_DIR, licenses=LICENSES):
    """Copy a hand-downloaded file into place after the same checks fetch() makes."""
    check_entry(e)
    got = sha256_of(src)
    if got != e["sha256"]:
        raise Refused("%s: sha256 %s does not match the pin %s" % (e["name"], got, e["sha256"]))
    dest_dir = os.path.join(cc0_dir, KIND_DIRS[e["kind"]])
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, e["file"])
    shutil.copyfile(src, dest)
    log_license(e, licenses)
    return dest


def log_license(e, licenses=LICENSES):
    rel = "cc0/%s/%s" % (KIND_DIRS[e["kind"]], e["file"])
    row = "| `%s` | %s | %s | %s | %s | %s | `%s` |\n" % (
        rel, e["kind"], e["source"], e["url"], e["license"],
        datetime.date.today().isoformat(), e["sha256"])
    text = open(licenses).read() if os.path.exists(licenses) else ""
    if TABLE_HEAD not in text:
        text = text.rstrip("\n") + ("\n\n" if text else "") + TABLE_HEAD
    lines = [l for l in text.splitlines(True) if not l.startswith("| `%s` |" % rel)]
    text = "".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    with open(licenses, "w") as f:
        f.write(text + row)


def self_test():
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "beep.wav")
        with open(src, "wb") as f:
            f.write(b"RIFF\x24\x00\x00\x00WAVEfmt test payload")
        pin = sha256_of(src)
        good = {"name": "beep", "kind": "sfx", "url": "file://" + src, "file": "beep.wav",
                "license": "CC0-1.0", "source": "self-test", "sha256": pin}
        cc0 = os.path.join(td, "cc0")
        lic = os.path.join(td, "LICENSES.md")
        with open(lic, "w") as f:
            f.write("# Third-party content\n")
        dest = fetch(good, cc0, lic)
        assert os.path.exists(dest) and sha256_of(dest) == pin
        assert "`cc0/sfx/beep.wav`" in open(lic).read()
        fetch(good, cc0, lic)   # a refetch replaces its row, never duplicates it
        assert open(lic).read().count("`cc0/sfx/beep.wav`") == 1

        def refused(**over):
            e = dict(good, **over)
            try:
                fetch(e, cc0, lic)
            except Refused:
                return True
            return False

        assert refused(sha256="0" * 64), "a bad pin must be refused"
        assert refused(license="CC-BY-4.0"), "non-CC0 must be refused"
        assert refused(license="CC-BY-SA-4.0"), "CC-BY-SA must be refused"
        assert refused(file="beep.glb"), "an sfx must be an audio file"
        assert refused(file="../beep.wav"), "paths must be bare names"
        # the blocked words, built from parts so they never sit in this file whole
        word = "".join(["ra", "dix"])
        assert refused(name=word + "_beep"), "a blocked name must be refused"
        assert refused(url="file://" + td + "/" + word.upper() + "Sounds/beep.wav")
        assert not blocked("drone_hull_kenney") and not blocked("void_runner_sfx")
        assert not os.path.exists(os.path.join(cc0, "sfx", "beep.glb"))
        # a hand-downloaded file goes through the same pin
        man = dict(good, name="beep2", file="beep2.wav", manual=True, url="https://example.org/pack")
        assert os.path.exists(place(man, src, cc0, lic))
        try:
            place(dict(man, sha256="1" * 64), src, cc0, lic)
            assert False, "place must check the pin"
        except Refused:
            pass
    print("fetch_cc0 self-test OK")


def main(argv):
    if argv[:1] == ["--self-test"]:
        self_test()
        return 0
    if argv[:1] == ["place"] and len(argv) == 3:
        e = next((x for x in load_manifest() if x.get("name") == argv[1]), None)
        if e is None:
            print("no manifest entry named %r" % argv[1])
            return 1
        try:
            print("placed", os.path.relpath(place(e, argv[2]), ROOT))
        except Refused as err:
            print("REFUSED", err)
            return 1
        return 0
    if not argv or argv[0] not in ("fetch", "list"):
        print(__doc__)
        return 2
    entries = load_manifest()
    if argv[0] == "list":
        for e in entries:
            print("%-20s %-6s %s" % (e.get("name"), e.get("kind"), e.get("url")))
        return 0
    want = entries if argv[1:] == ["--all"] else [e for e in entries if e.get("name") in argv[1:]]
    if not want:
        print("nothing to fetch (manifest has %d entries)" % len(entries))
        return 1 if argv[1:] and argv[1:] != ["--all"] else 0
    for e in want:
        if e.get("manual"):
            print("manual   %s: download it from %s, then `place %s <file>`" % (e["name"], e["url"], e["name"]))
            continue
        try:
            print("fetched", os.path.relpath(fetch(e), ROOT))
        except Refused as err:
            print("REFUSED", err)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
