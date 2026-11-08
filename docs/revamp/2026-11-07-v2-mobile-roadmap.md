# VOID RUNNER roadmap: iOS + controller build, v2 asset pipeline, hangar upgrades

_Status: approved 2026-11-07. Picks up after v4 PR C. Hard rule 1 stays as written until PR E lands._

## Progress (2026-11-08)

| Track | Status |
|---|---|
| Track 0: v4 PR B, PR C | Done (PRs #20, #21); the bake cache was skipped (PR E replaces it) |
| PR D: iOS + controller | Code in PR #22; waiting on the TestFlight pass (`docs/ios/TESTFLIGHT.md`) |
| PR E, PR F, PR G | Not started |

How PR D's code landed, and where it differs from the plan below:
- **Touch on native** turns on for `OS.has_feature("mobile")` only, not for every touchscreen,
  so a touchscreen laptop keeps the desktop controls. The touch layer is inset by the safe area
  through `TouchControls.safe_insets`, which allows for the letterbox (stretch aspect `keep`):
  on an iPhone in landscape the side notch falls inside the bars, so only the home indicator
  moves the controls.
- **The iOS export** needs ETC2/ASTC texture import (now on in `project.godot`) and a Team ID.
  The preset exports an Xcode project (`export_project_only`); a trial headless export on Linux
  with a placeholder Team ID wrote it.
- **The pad bindings** now match any device (`-1`), not just device 0, so a re-paired pad that
  gets a new id still works. With two pads connected, losing one hands control to the other
  instead of pausing.
- **B / dodge on resume:** `ui_cancel` never resumes play (it acts only on the title's card
  row), so the B press can't dodge on the resume frame. Fire held through LAUNCH or RESUME is
  swallowed until it's released.

## Context

The user shared a cross-game `ASSET_PIPELINE.md` (written for GolfCartSimulator and the other games) and asked what VoidRunner can use from it. They also want the game sharpened for web and for iPhone/iPad with a controller; their test pad is an 8BitDo SN30 Pro in an Xcode/TestFlight build.

As written, most of the doc conflicts with hard rule 1 ("no imported assets, ever"). The user has now agreed to relax that rule for v2, keeping the mid-90s DOS sprite-shooter look. The MacBook Neo stays the only machine; the Windows PC is used only if something truly needs it.

Decisions locked in the grill session:

1. **Native Godot iOS export** (not a WKWebView wrapper).
2. **New asset rule:** code-generated content, plus *build-time bakes* by scripts in this repo, plus *CC0 third-party content*. No CC-BY-SA, no GPL, no AI-generated content.
3. **CC0 scope:** 3D models used only as **sprite sources** (turntable-baked by SpriteForge) and **sound effects**. Wall textures stay code-painted (`TextureGen`).
4. **Fidelity:** keep the 320×200 viewport, palette LUT, nearest filtering and GL Compatibility. Quality comes from richer art inside that frame.
5. **Upgrades:** a hangar shop between levels. This **extends the existing Upgrade Bay**: salvage, MK weapon marks and ship ranks are already in `game_state.gd:27-46` and `overlays.gd:945-1039`.
6. **Controller on iOS:** auto-enables when a pad connects, prompts use labels that match the pad (Nintendo layout for 8BitDo), and a disconnect pauses the game.
7. **Order:** finish v4 PR B and PR C as specced → PR D (iOS + controller) → v2 tracks (PR E pipeline, PR F content, PR G upgrades).

Hard rule 2 still applies: nothing committed names the '95 game or its studio. That includes CC0 file names and metadata. Each PR below ends at an approval gate.

---

## Track 0: finish v4 (no changes to the existing spec)

- PR B (v4d) and PR C (beta polish) per `docs/revamp/2026-10-11-v4-spec.md` §6–§7.
- Do PR C's "bake cache across visits" item only if PR E is delayed. PR E's prebaked atlases make it unnecessary.
- **Gate:** smoke test, probes and `node tests/web_check.mjs` are green; the user playtests.

## PR D: native iOS export + SN30 Pro controller

**Export setup**
- Add an `iOS` preset to `export_presets.cfg`. Set landscape (sensor) orientation in `project.godot`. Keep the renderer `gl_compatibility`.
- Replace `export_filter="all_resources"` with exclusions for `assets/`, `tools/`, `tests/` and `docs/`, so source files never ship.

**Touch on native**
- `game.gd:206` turns touch mode on only from `window.vrTouchMode` (web). Add a native fallback: `OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()`.
- Place the touch layer inside `DisplayServer.get_display_safe_area()` (`touch_controls.gd:15-49` uses 320×200 canvas coordinates; map the safe rect into them).

**Pad hot-plug (new `scripts/pad_watch.gd`, an autoload or owned by `game.gd`)**
- Connect `Input.joy_connection_changed`.
  - **On connect:** set `GameState.pad_device`. On mobile builds, call `InputSetup.set_gamepad(true)` (web and desktop keep K6's opt-in default). Hide `TouchControls`.
  - **On disconnect during PLAYING:** call `_auto_pause()` (already exists, `game.gd:2160`) and show the touch layer again.
- `player.gd:191-192`: read `GameState.pad_device` instead of device `0`.

**Button labels (new `scripts/pad_glyphs.gd`)**
- `PadGlyphs.label(JoyButton)` returns positional names. The layout comes from `Input.get_joy_name(pad_device)`: names containing 8BitDo, Nintendo or Pro Controller get the Nintendo layout (bottom=B, right=A, left=Y, top=X); everything else gets the Xbox layout.
- Use it in `tip_text()` (`game.gd:1176-1188`) and the controls help line (`overlays.gd:154`), instead of the hard-coded "A OR RT" / "X OR B" strings.

**Input edge cases**
- A is both `ui_accept` and `fire`. Swallow `fire` until it's released after the state changes into PLAYING, so LAUNCH doesn't fire a shot.
- B is both `dodge_right` and `ui_cancel`. Fine in menus, because the weapon and dodge checks are gated on PLAYING (`game.gd:2068`). Verify that dodge doesn't trigger on the frame play resumes.

**Docs and tests**
- New `docs/ios/TESTFLIGHT.md`, a checklist for the Neo:
  - Godot 4.7 export templates and Xcode version;
  - signing / bundle id (user supplies);
  - **VERIFY** the SN30 Pro firmware and its iOS pairing mode;
  - **VERIFY** the palette LUT and sector shader render the same on the A18 GPU;
  - device pass items borrowed from Step 7.
- Smoke-test additions: the PadGlyphs mapping for both name families; `pad_watch` connect/disconnect handlers, called directly (auto-enable, pause, touch hidden and shown again).

**Gate:** the TestFlight build runs on the user's iPhone/iPad with the SN30 Pro (menus, flight, pause on disconnect, correct labels), and the web gate is still green.

## PR E: v2 asset pipeline (new rule, tooling, prebaked atlases)

**Rule change**
- Rewrite CLAUDE.md hard rule 1, and the README to match:
  > Shipped content is generated by code in this repo, baked at build time by scripts in this repo, or CC0 third-party 3D models (as sprite sources only) and sound effects, each logged in `assets/LICENSES.md`. No CC-BY-SA, no GPL, no AI-generated content.

**Layout**
- `assets/cc0/models/*.glb`, `assets/cc0/sfx/*` (source files, excluded from export).
- `assets/LICENSES.md` records source, URL, license, date and sha256 for each file.
- Use Git LFS only if the sources pass ~50 MB.

**`tools/fetch_cc0.py`**
- Reproducible downloads by name, with pinned sha256.
- Sources: Quaternius, Kenney, Poly Haven models; Kenney and other CC0 SFX.
- Refuses anything not CC0.

**Model sources in SpriteForge**
- `SpriteModels.build(id, frame)` (`sprite_models.gd:27`) may instance a GLB scene, kitbashed with the existing `taper/fin/pod/pair` parts kit.
- Override every surface with `studio.gdshader` (`m()`/`painted()`, `sprite_models.gd:62,262`) so code-built and CC0 models share one lighting model and palette.

**Build-time bake (`tools/bake_sprites.tscn`)**
- Run windowed on the Neo; headless can't render, see `sprite_forge.gd:336`.
- Reuses `SpriteForge._build_sheet`/`_slice` and writes `resources/baked/<class>.png` plus `manifest.json` (bake version, cell sizes, angles, frames).
- Fidelity becomes tunable per class:
  - `ANGLES` 8→16 and `ANIM` 2→4 for enemies;
  - enemy cells 64→96 px only if the budget allows;
  - `MAX_SHEET_PX` 2048 kept.
- At runtime, `SpriteForge.sprite_set()` (`:158`) loads the baked atlas when the manifest version matches. Otherwise it falls back to the current boot bake. That keeps fresh clones and the headless tests working, and it cuts boot time on web.

**SFX**
- `tools/crunch_sfx.py` (ffmpeg via Homebrew on the Neo) converts CC0 clips to mono, 22.05 kHz, 8-bit-style, for the DOS feel.
- `AudioSys` plays them next to the procedural `MusicGen` stems. The procedural SFX stay as fallbacks.

**Budgets and CI**
- `docs/ASSET_BUDGETS.md` sets limits for `.pck` size, total baked PNG size, per-sheet px, boot time and texture memory.
- `tools/check_budgets.py` fails on a breach, and also when any file in `assets/` is missing its LICENSES row.
- `.github/workflows/ci.yml` (new; Netlify is the only build today) runs `godot --headless --import`, the smoke test, `check_budgets.py`, and the export plus `web_check.mjs`.

**Gate:** CI green; boot-bake and first-flight numbers in `tests/perf_baseline.md` are equal to today or better; the user approves.

## PR F: refined content pilot

- Rebuild 2 enemies (drone + hulk) and 1 boss with CC0 kitbash plus parts kit, at the higher angle and frame counts.
- Make A/B comparisons through the existing gallery and screenshot probes, at 320×200 after the palette pass.
- Swap in 3–5 CC0 SFX (explosion, pickup, hit).
- **Gate:** the user picks which look wins before the rest of the 16 enemy types and 6 bosses move over.

## PR G: hangar upgrades (extends the Upgrade Bay)

- Open the Bay from the post-level tally (after PR B's tally rework) as well as from the briefing (`overlays.gd:662`).
- Add ship ranks for **engines** (`BASE_SPEED`/`BOOST_SPEED`, `player.gd:11-18`) and **thrusters** (`DODGE_CD`/`DODGE_COST`, `player.gd:33-37`). Use the same pattern as `ship_ranks` / `SHIP_COST` / `BAY_SHIP`, read through accessors like `hull_mult` (`game_state.gd:246-267`).
- Possibly add a MK IV row to the `MARK_*` tables (`game_state.gd:33-38`).
- Add a hangar ship preview: the player ship as a SpriteModels model, turntable-baked with its installed parts showing.
- Bump the version for `records.cfg` and the checkpoint, with migration defaults for the new ranks.
- Gamepad-navigable Bay: it uses the same `_focus` mechanism (`overlays.gd:60,163`).
- **Gate:** balance pass; the user playtests the economy on web and TestFlight.

---

## Not adopted from ASSET_PIPELINE.md

- Blender authoring: Godot imports GLB natively, so the Neo never needs Blender for this game.
- PBR, HDRI, KTX2, gltf-transform, LODs: no benefit at 320×200 with a 256-colour palette.
- The Windows PC offload: unless a bake ever runs longer than ~5 minutes.

## Verification (every PR)

- `godot --headless --import` (needed for new `class_name` scripts).
- Smoke test: `timeout 1500 godot --headless --path . tests/smoke_test.tscn`. It must print `SMOKE TEST COMPLETE` with 0 `SCRIPT ERROR`.
- Probes: warmup, campaign, `fx_parity` (must print `FX PARITY OK`), forge (bake times), and perf with `VR_PERF_RAIL=1 VR_PERF_LEVEL=7` (worst step under 8 ms).
- Web gate: `./build.sh` then `node tests/web_check.mjs <out> dist`.
- PR D only: a real-device TestFlight pass with the SN30 Pro, per `docs/ios/TESTFLIGHT.md`.
- PR E onward: `tools/check_budgets.py` in CI.
