#!/usr/bin/env python3
"""Crunch CC0 sound effects into the game's DOS-era format.

    python3 tools/crunch_sfx.py <name> [<name> ...]   # assets/cc0/sfx/<file> -> resources/sfx/<name>.wav
    python3 tools/crunch_sfx.py --all
    python3 tools/crunch_sfx.py --self-test

Each source in assets/cc0/sfx/ (fetched by tools/fetch_cc0.py, so it has a LICENSES
row) becomes resources/sfx/<name>.wav: mono, 22.05 kHz, 8-bit unsigned PCM, leading
and trailing silence trimmed, peak-normalised to -1 dBFS. AudioSys plays a file there
in place of the procedural sound of the same name (see AUDIO_NAMES in
scripts/audio_sys.gd); the procedural sounds stay as the fallback.

The output name is the AudioSys slot, given in the manifest entry's "slot" field, or
the entry name. Needs ffmpeg (Homebrew on the Neo; preinstalled on Linux CI images).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets", "cc0", "sfx")
OUT_DIR = os.path.join(ROOT, "resources", "sfx")
MANIFEST = os.path.join(ROOT, "assets", "cc0", "manifest.json")
LICENSES = os.path.join(ROOT, "assets", "LICENSES.md")
RATE = 22050
# the AudioSys slots a crunched file may replace (keep in step with audio_sys.gd)
SLOTS = {"boom_small", "boom_big", "hit", "select", "overheat", "portal", "clank", "dodge",
         "boost", "bomb", "gib_tick", "powerup", "warn", "tick", "stamp", "blip", "confirm"}

FILTER = ("silenceremove=start_periods=1:start_threshold=-50dB:"
          "stop_periods=-1:stop_threshold=-50dB:stop_duration=0.05,"
          "loudnorm=I=-14:TP=-1:LRA=11,alimiter=limit=0.89")


class Refused(Exception):
    pass


def ffmpeg():
    exe = shutil.which("ffmpeg")
    if not exe:
        raise Refused("ffmpeg not found (brew install ffmpeg)")
    return exe


def crunch(src, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    cmd = [ffmpeg(), "-v", "error", "-y", "-i", src, "-af", FILTER,
           "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_u8", dest]
    subprocess.run(cmd, check=True)
    return describe(dest)


def describe(path):
    with wave.open(path) as w:
        return {"channels": w.getnchannels(), "rate": w.getframerate(),
                "bits": w.getsampwidth() * 8, "seconds": w.getnframes() / float(w.getframerate())}


def licensed(file_name, licenses=LICENSES):
    text = open(licenses).read() if os.path.exists(licenses) else ""
    return ("`cc0/sfx/%s`" % file_name) in text


def entries():
    with open(MANIFEST) as f:
        return [e for e in json.load(f).get("files", []) if e.get("kind") == "sfx"]


def run(names):
    todo = entries()
    if names != ["--all"]:
        todo = [e for e in todo if e.get("name") in names]
    if not todo:
        print("nothing to crunch")
        return 0
    for e in todo:
        slot = e.get("slot", e["name"])
        if slot not in SLOTS:
            raise Refused("%s: slot %r is not an AudioSys sound (%s)" % (e["name"], slot, sorted(SLOTS)))
        if not licensed(e["file"]):
            raise Refused("%s: no LICENSES row; fetch it with tools/fetch_cc0.py" % e["name"])
        dest = os.path.join(OUT_DIR, slot + ".wav")
        info = crunch(os.path.join(SRC_DIR, e["file"]), dest)
        print("crunched %s -> %s (%.2f s)" % (e["file"], os.path.relpath(dest, ROOT), info["seconds"]))
    return 0


def self_test():
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "tone.wav")
        # a 0.5 s stereo 44.1 kHz 16-bit tone with silence either side
        subprocess.run([ffmpeg(), "-v", "error", "-f", "lavfi", "-i",
                        "aevalsrc=if(between(t\\,0.3\\,0.8)\\,0.2*sin(2*PI*440*t)\\,0):s=44100:d=1.1",
                        "-ac", "2", "-c:a", "pcm_s16le", src], check=True)
        dest = os.path.join(td, "out", "hit.wav")
        info = crunch(src, dest)
        assert info["channels"] == 1 and info["rate"] == RATE and info["bits"] == 8, info
        assert 0.4 < info["seconds"] < 0.75, info   # the silence either side is trimmed
        lic = os.path.join(td, "LICENSES.md")
        with open(lic, "w") as f:
            f.write("| `cc0/sfx/tone.wav` | sfx | test | file:// | CC0-1.0 | today | `x` |\n")
        assert licensed("tone.wav", lic) and not licensed("other.wav", lic)
    print("crunch_sfx self-test OK")


def main(argv):
    try:
        if argv[:1] == ["--self-test"]:
            self_test()
            return 0
        if not argv:
            print(__doc__)
            return 2
        return run(argv)
    except Refused as err:
        print("REFUSED", err)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
