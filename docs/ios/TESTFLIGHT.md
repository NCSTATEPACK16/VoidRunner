# TestFlight checklist (iOS + SN30 Pro)

PR D's gate. The build is specified in `docs/ios/2026-11-15-testflight-build-spec.md`. Run it on the MacBook Neo with an iPhone, an iPad and the 8BitDo SN30 Pro. Tick
each box, and note anything that fails along with the device and iOS version.

## 1. One-time setup on the Neo
- [ ] Install Xcode (a current release that supports the devices' iOS version) and its command
      line tools. Open it once to accept the license.
- [ ] Install Godot 4.7 stable (the same version `build.sh` pins) and its export templates:
      Editor → Manage Export Templates → Download. The iOS template is `ios.zip`.
- [ ] Have an Apple Developer account, and know your **Team ID** (developer.apple.com →
      Membership).

## 2. Your signing details
- [ ] Copy `docs/ios/ios.local.env.example` to `ios.local.env` in the repo root and fill in
      `VR_IOS_TEAM_ID` and `VR_IOS_BUNDLE_ID` (your reverse-DNS id, e.g.
      `com.yourname.voidline`). The file is gitignored, so neither id reaches the repo.
- [ ] In App Store Connect, register that bundle id and create the app record (once).
      Internal testers need nothing more. For external testers, fill in the fields drafted
      in `docs/ios/BETA_REVIEW.md` and submit the first build for Beta App Review.

The version is `application/short_version` in `export_presets.cfg` (`0.4.0`). The build number
is the git commit count, so every new commit uploads cleanly. To upload the same commit twice,
set `VR_IOS_BUILD` to a higher number.

## 3. Build and upload
- [ ] Export and check the Xcode project:

  ```sh
  ./build_ios.sh
  ```

  It stamps the build id, paints the icons and the launch mark, exports to `build/ios/`, and
  runs `tests/ios_export_check.py`. Every line should say `ok`.
- [ ] Open `build/ios/Voidline.xcodeproj`. Under Signing & Capabilities, check that your team
      is picked and automatic signing is on.
- [ ] Run it on a cabled device first (Product → Run).
- [ ] Upload. Either Product → Archive → Distribute App → TestFlight in Xcode, or:

  ```sh
  ./build_ios.sh upload
  ```

  **VERIFY:** `archive` and `upload` have never run on a Mac. If `xcodebuild` complains, use
  the Xcode route and note the error.
- [ ] **VERIFY** the launch screen: our mark on dark blue, no engine logo, then the title.
- [ ] **VERIFY** the home-screen icon is sharp pixel art, in light and dark mode.

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

**Borrowed from the Step 7 device pass** (method and pass thresholds:
`docs/device-pass/2026-11-24-step7-device-pass.md`; read the numbers off the diagnostics
overlay, opened by holding the build number for one second, since the app has no `vrReport()`)
- [ ] Title-up and first-flight times; the sprite bake time (compare with
      `tests/perf_baseline.md`).
- [ ] fps in the L8 dense arena and the L9 boss.
- [ ] Fog-distance shimmer on distant sprites.
- [ ] Audio starts after the first touch or press. Backgrounding the app pauses the run.
- [ ] The ring/silent switch mutes the game.
- [ ] **VERIFY** SETUP → SOUND → SILENT SWITCH MUTES: turn it OFF, close and reopen the app,
      and the game plays with the switch on silent. Turn it back ON, relaunch, and it is
      muted again.
- [ ] On a 120 Hz device the game feels the same speed as on a 60 Hz one.
- [ ] Checkpoint CONTINUE works after force-quitting the app.

## 6. Report back
Note the device, iOS version, the Godot and Xcode versions, and every unticked box.
