#!/usr/bin/env python3
"""PR D2: checks the Xcode project Godot's iOS export wrote, before anyone opens Xcode.

    python3 tests/ios_export_check.py build/ios [--team ID --bundle ID --version V --build N]

Each check is something App Store Connect or a tester would trip over later: an icon
with an alpha channel, the engine's stock launch screen, a portrait orientation, source
folders packed into the game data. Exits non-zero on the first run with any failure.
build_ios.sh runs it after every export, and CI runs it on the Linux export.
"""
import argparse
import plistlib
import re
import struct
import sys
from pathlib import Path

APP = "Voidline"
# The void colour (Palette.ramp(BLUE, 0)), as the storyboard writes it.
VOID_RGB = (3 / 255, 4 / 255, 26 / 255)
# Folders the export filters keep out of the game data.
# node_modules/ and web-out/ appear when CI has run the web check in the project folder.
SOURCE_DIRS = ("tests/", "tools/", "docs/", "assets/", "web/", "dist/", "node_modules/", "web-out/", "bin/")
ICON_SIZES = (40, 58, 60, 76, 80, 87, 114, 120, 128, 136, 152, 167, 180, 192, 1024)

failures = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        failures.append(what)


def png_header(path):
    """(width, height, colour type) from a PNG's IHDR. Colour types 4 and 6 carry alpha."""
    with open(path, "rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return (0, 0, -1)
    width, height, _depth, colour = struct.unpack(">IIBB", head[16:26])
    return (width, height, colour)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--team")
    ap.add_argument("--bundle")
    ap.add_argument("--version")
    ap.add_argument("--build")
    args = ap.parse_args()
    out = args.out

    pbx_path = out / f"{APP}.xcodeproj" / "project.pbxproj"
    plist_path = out / APP / f"{APP}-Info.plist"
    check(pbx_path.is_file(), "the Xcode project exists")
    check(plist_path.is_file(), "Info.plist exists")
    if failures:
        return 1
    pbx = pbx_path.read_text()
    with open(plist_path, "rb") as f:
        info = plistlib.load(f)

    print("Info.plist")
    landscape = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
    for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
        check(sorted(info.get(key, [])) == landscape, f"{key} is both landscapes only")
    check(info.get("ITSAppUsesNonExemptEncryption") is False,
          "declares no non-exempt encryption (no export-compliance question per upload)")
    check(info.get("UIRequiresFullScreen") is True, "full screen only (no iPad split view)")
    check(info.get("UIStatusBarHidden") is True, "status bar hidden")
    check(info.get("GCSupportsControllerUserInteraction") is True, "declares game controller support")
    profiles = [d.get("ProfileName") for d in info.get("GCSupportedGameControllers", [])]
    check(profiles == ["ExtendedGamepad"], "controller profile is ExtendedGamepad")
    check(info.get("LSApplicationCategoryType") == "public.app-category.action-games",
          "App Store category is action games")
    check(info.get("UILaunchStoryboardName") == "Launch Screen", "has a launch storyboard")

    print("Build settings")
    def setting(name):
        return set(re.findall(rf"\b{name} = \"?([^\";]*)\"?;", pbx))
    check(setting("TARGETED_DEVICE_FAMILY") == {"1,2"}, "targets iPhone and iPad")
    check(setting("IPHONEOS_DEPLOYMENT_TARGET") == {"14.0"}, "deployment target is iOS 14.0")
    team, bundle = setting("DEVELOPMENT_TEAM"), setting("PRODUCT_BUNDLE_IDENTIFIER")
    version, build = setting("MARKETING_VERSION"), setting("CURRENT_PROJECT_VERSION")
    check(len(team) == 1 and "" not in team, "a development team is set")
    check(len(version) == 1 and re.fullmatch(r"\d+(\.\d+){0,2}", next(iter(version), "")) is not None,
          "marketing version is up to three dotted numbers")
    check(len(build) == 1 and re.fullmatch(r"\d+(\.\d+){0,2}", next(iter(build), "")) is not None,
          "build number is numeric")
    for label, got, want in (("team", team, args.team), ("bundle id", bundle, args.bundle),
                             ("version", version, args.version), ("build", build, args.build)):
        if want is not None:
            check(got == {want}, f"{label} is {want}")
    if args.bundle is not None:
        check(not args.bundle.startswith("com.example."), "bundle id is not the placeholder")

    print("Icons")
    icons = out / APP / "Images.xcassets" / "AppIcon.appiconset"
    for size in ICON_SIZES:
        w, h, colour = png_header(icons / f"Icon-{size}.png") if (icons / f"Icon-{size}.png").is_file() else (0, 0, -1)
        check((w, h) == (size, size) and colour in (0, 2, 3), f"Icon-{size}.png is {size} px with no alpha channel")

    print("Launch screen")
    splash = out / APP / "Images.xcassets" / "SplashImage.imageset"
    check(png_header(splash / "splash@2x.png")[:2] == (256, 256), "launch mark @2x is ours (256 px)")
    check(png_header(splash / "splash@3x.png")[:2] == (384, 384), "launch mark @3x is ours (384 px)")
    board = (out / APP / "Launch Screen.storyboard").read_text()
    m = re.search(r'key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"', board)
    bg_ok = m is not None and all(abs(float(m.group(i + 1)) - VOID_RGB[i]) < 0.004 for i in range(3))
    check(bg_ok, "launch background is the void colour")
    check('contentMode="center"' in board, "launch mark is centred, not stretched")

    print("Privacy manifest")
    privacy_path = out / "PrivacyInfo.xcprivacy"
    check(privacy_path.is_file(), "PrivacyInfo.xcprivacy exists")
    if privacy_path.is_file():
        with open(privacy_path, "rb") as f:
            privacy = plistlib.load(f)
        check(privacy.get("NSPrivacyTracking") is False, "declares no tracking")
        check(not privacy.get("NSPrivacyCollectedDataTypes"), "declares no collected data")
        check(all(t.get("NSPrivacyAccessedAPITypeReasons") for t in privacy.get("NSPrivacyAccessedAPITypes", [])),
              "every required-reason API has a reason")

    print("Game data")
    pck_path = out / f"{APP}.pck"
    check(pck_path.is_file(), "the .pck exists")
    if pck_path.is_file():
        pck = pck_path.read_bytes()
        check(len(pck) < 16 * 1024 * 1024, f"the .pck is under 16 MB ({len(pck) / 1048576:.1f} MB)")
        for d in SOURCE_DIRS:
            check(f"res://{d}".encode() not in pck and f"\x00{d}".encode() not in pck,
                  f"no {d} files are packed")
        check(b"scripts/game.gd" in pck, "the game scripts are packed")
        check(b"resources/baked/manifest.json" in pck, "the prebaked sprite manifest is packed")

    print(f"iOS export check: {'FAILED, ' + str(len(failures)) + ' problem(s)' if failures else 'all good'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
