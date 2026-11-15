# VOID RUNNER TestFlight build spec (PR D2)

_Status: implemented 2026-11-15, except the items under "Needs the Mac and a device". Follows
PR D (`docs/revamp/2026-11-07-v2-mobile-roadmap.md`), whose code merged in PR #22._

## 1. Goal

One command on the MacBook Neo turns a clean checkout into a build in TestFlight, and the
build is one Apple will accept on the first upload. PR D made the game run on iOS (export
preset, touch, pad hot-plug, pad-true labels). This spec covers the packaging around it:
icon, launch screen, version numbers, signing details, privacy declarations, and a check that
runs before Xcode is ever opened.

Out of scope: gameplay changes, App Store (public) release, Android.

## 2. What the trial export showed

A headless export of the PR D preset on Linux (Godot 4.7, placeholder Team ID) writes a valid
Xcode project. Reading that project turned up four problems. All four are fixed here.

| Finding | Why it matters | Fix |
|---|---|---|
| The 1024 px App Store icon was the 180 px icon scaled up with a smoothing filter, and it had an alpha channel | App Store Connect rejects an icon with alpha; the blur breaks the pixel-art look | `IconGen.store_icon()` paints 1024 px (32 × 32 art at ×32) as RGB; the preset scales the other sizes down from it with nearest sampling |
| The launch screen was the engine's stock logo on grey, and the same logo showed again as the boot splash | First thing a tester sees; not ours | `IconGen.launch_image()` paints our mark on the void colour; the boot splash image is off and its background is the void colour |
| Version and build number were empty, so Xcode got `1.0.0` for both | TestFlight refuses a build number it has seen before | Preset carries `0.4.0`; `build_ios.sh` sets the build number to the git commit count |
| Team ID and bundle id had to be typed into a committed file | They would leak into a public repo, or be forgotten | `build_ios.sh` reads them from a gitignored `ios.local.env` and patches the preset only for the length of the export |

Already right in the generated project, now pinned by the check (§5): landscape-only on both
device families, full screen (no iPad split view), hidden status bar, the "no non-exempt
encryption" flag (so no export-compliance question on each upload), a privacy manifest with
reasons for the file-timestamp, boot-time and disk-space APIs, and source folders kept out of
the `.pck` (1.6 MB).

## 3. Decisions

1. **Godot exports the Xcode project; Xcode signs.** `export_project_only=true` stays. Automatic
   signing, so no provisioning profiles to manage by hand.
2. **Secrets never enter the repo.** `ios.local.env` holds `VR_IOS_TEAM_ID` and
   `VR_IOS_BUNDLE_ID`. The committed preset keeps an empty Team ID and
   `com.example.voidrunner`, and the check fails a real build that still has the placeholder.
3. **Version scheme.** Marketing version `0.4.0` for the v4 content, changed by hand in the
   preset (or `VR_IOS_VERSION`). Build number = `git rev-list --count HEAD`, so it rises with
   every commit and needs no bookkeeping. Override with `VR_IOS_BUILD` to re-upload the same
   commit.
4. **All icon and launch art is painted by code** (hard rule 1), by the same
   `tools/make_icons.tscn` step as the web icons, into gitignored `build/icons/`.
5. **Info.plist additions:** game-controller support (`GCSupportsControllerUserInteraction`,
   profile `ExtendedGamepad`) and the action-games category.
6. **Privacy.** The native build collects nothing: `Feedback.count()` is a no-op off the web,
   so the privacy manifest declares no tracking and no collected data. The App Store Connect
   privacy answer is "Data Not Collected". The feedback form opens in Safari and only when the
   player asks for it.
7. **Engine defaults kept:** home indicator hidden, edge-gesture guard on, screen kept awake,
   up to 120 Hz, audio session `Ambient` (the ring/silent switch mutes the game, as players
   expect from a game).
8. **Minimum iOS 14.0, iPhone and iPad, arm64.** Unchanged from PR D.

## 4. The build

```sh
cp docs/ios/ios.local.env.example ios.local.env   # once; then fill in the two ids
./build_ios.sh            # Xcode project in build/ios/, checked
./build_ios.sh archive    # + xcodebuild archive
./build_ios.sh upload     # + upload to TestFlight
```

Steps inside `build_ios.sh`: stamp the build id → import → paint icons → patch the preset
(restored on exit, whatever happens) → export → `tests/ios_export_check.py` → optionally
`xcodebuild archive` and `xcodebuild -exportArchive` with an upload destination. Upload uses the
account Xcode is signed in to, or an App Store Connect API key (`VR_ASC_KEY_PATH`,
`VR_ASC_KEY_ID`, `VR_ASC_ISSUER_ID`).

On Linux the script stops after the check, since archiving needs Xcode. CI runs it that way
with placeholder ids.

## 5. The check (`tests/ios_export_check.py`)

Reads `build/ios/` and fails on any of: a portrait orientation; a missing encryption flag,
controller declaration or category; a device family other than iPhone + iPad; an unset team;
a non-numeric version or build; the placeholder bundle id; any icon of the wrong size or with
an alpha channel; a launch screen that isn't our mark on the void colour; a privacy manifest
that declares tracking or collected data, or is missing a reason; a `.pck` over 16 MB or one
that contains `tests/`, `tools/`, `docs/`, `assets/`, `web/` or `dist/`; a `.pck` without the
game scripts or the prebaked sprite manifest.

The smoke test covers the art itself: 1024 px, RGB, no alpha, palette colours only; launch
marks 256 and 384 px.

## 6. Needs the Mac and a device

Nothing below can be run in a Linux container. Each is a line in `docs/ios/TESTFLIGHT.md`.

- **`archive` and `upload` are untested.** The `xcodebuild` calls are written from Apple's
  documented flags and have never run. Expect to adjust them on the first try; the Xcode
  Organizer route in the checklist is the fallback.
- **App Store Connect record.** Register the bundle id and create the app once (name, primary
  language, SKU). Internal testers (your own team) need no beta review. External testers need
  a privacy policy URL and a first beta review.
- **The launch screen and icon on a real home screen**, light and dark.
- **Audio session.** If testers find the silent switch muting the game surprising, change
  `audio/general/ios/session_category` in `project.godot` to Playback.
- **120 Hz.** ProMotion devices run the game at up to 120 fps. If the perf numbers or battery
  say otherwise, set `display/window/ios/allow_high_refresh_rate=false`.
- **Everything in the PR D device pass:** rendering parity, safe areas, the SN30 Pro.

## 7. Open questions for the user

1. The bundle id and app name on the App Store Connect record ("VOID RUNNER" may be taken as a
   store name; the name under the icon is separate and stays).
2. Internal testers only, or external too? External adds the privacy policy URL and a review.
3. If this ever ships in the Kids category, the feedback link needs a parental gate, or to be
   left out of the native build.

## 8. Gates

- `./build_ios.sh` passes on Linux (CI) and on the Neo.
- Smoke test, `node tests/web_check.mjs`, `python3 tools/check_budgets.py` stay green (the boot
  splash change touches the web export too).
- A build reaches TestFlight and passes `docs/ios/TESTFLIGHT.md` on an iPhone and an iPad.
