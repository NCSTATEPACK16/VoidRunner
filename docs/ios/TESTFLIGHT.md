# TestFlight checklist (iOS + SN30 Pro)

PR D's gate. Run it on the MacBook Neo with an iPhone, an iPad and the 8BitDo SN30 Pro. Tick
each box, and note anything that fails along with the device and iOS version.

## 1. One-time setup on the Neo
- [ ] Install Xcode (a current release that supports the devices' iOS version) and its command
      line tools. Open it once to accept the license.
- [ ] Install Godot 4.7 stable (the same version `build.sh` pins) and its export templates:
      Editor → Manage Export Templates → Download. The iOS template is `ios.zip`.
- [ ] Have an Apple Developer account, and know your **Team ID** (developer.apple.com →
      Membership).

## 2. Fill in the iOS preset
In `export_presets.cfg` (or Project → Export → iOS):
- [ ] `application/app_store_team_id`: your Team ID. The export refuses to run without it.
- [ ] `application/bundle_identifier`: your reverse-DNS id, replacing `com.example.voidrunner`.
- [ ] `application/short_version` / `application/version`: e.g. `0.4` / `1`. Bump `version`
      for every TestFlight upload.
- [ ] Leave `application/export_project_only=true`: Godot writes an Xcode project into
      `build/ios/`, and Xcode does the signing and the upload.

Don't commit your Team ID or bundle id unless you want them in the public repo.

## 3. Build and upload
- [ ] Run the export from the repo root:

  ```sh
  godot --headless --export-release "iOS" build/ios/VoidRunner.ipa
  ```

  You can also export from the editor. `build/` is gitignored, and `tools/make_icons.tscn`
  must have run once so the app icon exists (`./build.sh` does both on Linux).
- [ ] Open `build/ios/VoidRunner.xcodeproj`. Under Signing & Capabilities, pick your team and
      enable automatic signing.
- [ ] Run it on a cabled device first (Product → Run), then use Product → Archive →
      Distribute App → TestFlight.

## 4. Controller pairing
- [ ] **VERIFY** the SN30 Pro firmware is current (8BitDo's updater, on the Neo).
- [ ] **VERIFY** the iOS pairing mode. iOS sees the pad only in the mode 8BitDo documents for
      Apple devices (on recent firmware, START + A, or X, held at power-on; check 8BitDo's
      manual for your firmware). The pad should show up under Settings → Bluetooth as a game
      controller.

## 5. Device pass (each of iPhone and iPad)
**Rendering**
- [ ] **VERIFY** the palette LUT and sector shader look the same on the A-series GPU as on the
      web build: the same colours, the dither pattern, no banding or black walls.
- [ ] The view is landscape and turns over between the two landscapes. The 320×200 frame is
      letterboxed with sharp (nearest) pixels.

**Touch, with no pad paired**
- [ ] Touch controls show in flight. FIRE, BOMB, WPN and the II pause tab all sit clear of the
      notch / Dynamic Island and the home indicator, in both landscapes.
- [ ] TAP TO START, the menus, the tally and the episode cards all work by touch.

**Pad**
- [ ] Pair the pad with the game running: the touch layer hides at the next flight frame, and
      the pad flies the ship with no trip to SETUP (it turns on by itself on iOS).
- [ ] The flight tips and the manual's PAD line name the buttons as printed on the SN30 Pro:
      **B or ZR** to fire, **R or ZL** to boost, **Y or A** to roll.
- [ ] Menus: the D-pad or stick moves the blinking `>`, and the bottom face button presses.
- [ ] Pressing LAUNCH or RESUME with the bottom face button doesn't fire a shot. Fire starts on
      the next press.
- [ ] Rolling with the right face button doesn't trigger on the frame play resumes.
- [ ] START pauses; SELECT (−) opens the automap.
- [ ] Switch the pad off mid-flight: the game pauses, and the touch controls come back after
      RESUME.
- [ ] Switch it back on: it reconnects, and the touch layer hides again.

**Borrowed from the Step 7 device pass**
- [ ] Title-up and first-flight times; the sprite bake time (compare with
      `tests/perf_baseline.md`).
- [ ] fps in the L8 dense arena and the L9 boss.
- [ ] Fog-distance shimmer on distant sprites.
- [ ] Audio starts after the first touch or press. Backgrounding the app pauses the run.
- [ ] Checkpoint CONTINUE works after force-quitting the app.

## 6. Report back
Note the device, iOS version, the Godot and Xcode versions, and every unticked box. PR E (the
v2 asset pipeline) starts once this pass is green.
