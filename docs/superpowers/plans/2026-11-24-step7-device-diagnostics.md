# Step 7: Device Diagnostics and Device-Pass Checklist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the game a hidden diagnostics overlay, a WebGL "signal lost — tap to reload"
screen and a complete `vrReport()`, then write the checklist John runs on real devices.

**Architecture:** A new `DiagOverlay` CanvasLayer samples real-time frame stats plus the
game-view SubViewport's render info and the boot numbers `SpriteForge` already records, and
formats them with a pure static function the smoke test can call. It's off by default, never
saved, and toggled by Shift+F3, a 1 s long-press on the build stamp, or `?diag=1`. On web, the
game mirrors the same numbers into `window.vrBoot` so `vrReport()` carries them. The shell
listens for `webglcontextlost` and covers the canvas with a reload screen. The checkpoint
system (re-audit Step 4) already makes a reload resumable.

**Tech Stack:** Godot 4.7 GDScript, the custom web shell `web/vr_shell.html`, Playwright 1.63
(`tests/web_check.mjs`).

**Spec:** `docs/revamp/2026-10-11-v4-spec.md` §8 (the Step 7 brief), with
`docs/revamp/2026-09-28-m5-m9-reaudit.md` §4 Step 7 and the "Borrowed from the Step 7 device
pass" block in `docs/ios/TESTFLIGHT.md:82-95`.

## Already shipped (don't rebuild)

- Boot bake numbers: `game.gd:151-157` writes `vrBoot.bakeMs/bakeGpu/prebaked`.
- First-flight time: `game.gd:1138-1146` writes `vrBoot.firstFlightMs` (web only).
- `vrReport()` exists (`vr_shell.html:628-646`) and dumps `window.vrBoot`.
- Pause on focus loss (`game.gd:2330-2333`), checkpoint CONTINUE after a closed tab
  (`game_state.gd:431-595`).
- Lost: the M4a spike's FPS label (`touch_controls.gd:172-177, 551-560`) is **always on in
  touch mode**, so beta players see it. Task 2 removes it, and the overlay replaces it.

## Global Constraints

- Hard rules (`./CLAUDE.md`): never name the '95 game or its studio, MIT only, no GPL,
  child-friendly text, CC0-only third-party content.
- 320×200 viewport stretch `keep`, GL Compatibility, nearest filter, no AA. Web export
  `thread_support=false`.
- The overlay is **off by default, never persisted, and never shown in normal play.**
- Overlay text uses `PixelFont` at size 8 (inherited from the theme). No new fonts.
- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`. Run `--headless --import`
  after adding the `class_name` script.
- Smoke-test locals get a `dg_` prefix (Task 1/2) or `cl_` prefix (Task 3), because `_run()` is one function.
- Not in scope: a lower-resolution distant-sprite set. The checklist decides whether one is
  needed (re-audit Step 7: "only if needed").

## Review Focus

1. **Paused tree (pause menu, automap):** the overlay keeps updating. Set `process_mode = ALWAYS`; Task 1 test pauses the tree and samples.
2. **Hit-stop / GAME SPEED assist change `Engine.time_scale`:** fps must come from wall-clock time, not `delta`. Task 1 test feeds samples with `time_scale = 0.25` semantics through the pure stats function.
3. **Headless / no GPU:** adapter strings are empty and render info is 0. `lines()` must still return every row with `—` placeholders and never error. Task 1 test runs headless.
4. **A short tap on the build stamp must not toggle**, and a press that slides off before 1 s must not either. Task 2 tests both.
5. **Context lost while the loading overlay (`#vr-loading`, z-index 200/210) is up:** the lost screen must sit above it. Task 3 uses z-index 300, and the web check asserts it is the topmost element at the screen centre.

---

### Task 1: `DiagOverlay`, with frame stats and formatted lines

**Files:**
- Create: `scripts/diag_overlay.gd`
- Modify: `scripts/game.gd` (build it in `_ready` after `crt_layer`; `_report_first_flight` at `game.gd:1138` also records `DiagOverlay.first_flight_ms` on every platform)
- Test: `tests/smoke_test.gd` (new `DIAG` section after the `FEEL ok` print at line 3677)

**Interfaces:**
- Produces:
  - `class_name DiagOverlay extends CanvasLayer`, with `layer = 101` (above the CRT pass at 100, so it stays readable).
  - `static var first_flight_ms := 0`. `Time.get_ticks_msec()` at the first controllable frame. `_report_first_flight` sets it before its web-only early return.
  - `var view: SubViewport`, set by `game.gd` to `game.view`.
  - `func set_shown(on: bool) -> void` and `func toggle() -> void`. `visible` mirrors the state. While hidden, `_process` does nothing.
  - `static func frame_stats(samples_usec: PackedInt64Array) -> Dictionary`. `samples_usec` holds frame end times in microseconds covering the last ~1 s. It returns `{fps: float, avg_ms: float, worst_ms: float}`, which are all 0.0 for fewer than 2 samples.
  - `func snapshot() -> Dictionary` returns these keys: `fps, avg_ms, worst_ms, draw_calls, objects, bake_ms, bake_gpu, prebaked, boss_bake_ms, objects_bake_ms, first_flight_ms, renderer, adapter, vendor, api`.
  - `static func lines(s: Dictionary) -> PackedStringArray`. A missing or empty value prints `—`.

- [ ] **Step 1: Write the failing test** (in `smoke_test.gd`, new DIAG section)

```gdscript
var dg_st := DiagOverlay.frame_stats(PackedInt64Array([0, 16000, 32000, 82000]))
assert(is_equal_approx(dg_st.worst_ms, 50.0))
assert(is_equal_approx(dg_st.avg_ms, 82.0 / 3.0))
assert(is_equal_approx(dg_st.fps, 3.0 / 0.082))
assert(DiagOverlay.frame_stats(PackedInt64Array([5])).fps == 0.0)
var dg_lines := DiagOverlay.lines({})   # headless/empty: every row, placeholders, no error
assert(dg_lines.size() == 6 and "—" in dg_lines[0])
var dg := game.diag as DiagOverlay
assert(dg != null and not dg.visible)   # off by default
dg.set_shown(true)
game.get_tree().paused = true
for dg_i in 3: await game.get_tree().process_frame
var dg_snap := dg.snapshot()
assert(dg_snap.has("draw_calls") and dg_snap.has("renderer") and dg_snap.bake_ms == SpriteForge.bake_ms)
game.get_tree().paused = false
dg.set_shown(false)
print("DIAG ok — frame stats, placeholder lines, snapshot while paused, off by default")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn 2>&1 | grep -E 'SCRIPT ERROR|DIAG ok' | head`
Expected: a SCRIPT ERROR naming `DiagOverlay` (the identifier isn't declared yet).

- [ ] **Step 3: Implement `scripts/diag_overlay.gd`, then build it in `game._ready` (`game.diag`)**

Six rows, fixed order:
1. `FPS <fps>  AVG <avg>ms  WORST <worst>ms`
2. `DRAWS <n>  OBJS <n>`, the game view only
3. `BAKE <ms>ms GPU <Y/N> PRE <Y/N>`
4. `BOSS <ms>ms  OBJ <ms>ms`
5. `FLIGHT <s.s>s`, from `first_flight_ms`
6. `<renderer> · <adapter>`, cut to 38 chars

Use:
- frame times: `Time.get_ticks_usec()`, with a rolling buffer pruned to the last 1 000 000 µs;
- draw calls: `RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)`, and `..._OBJECTS_IN_FRAME` for objects;
- renderer strings: `OS.get_current_rendering_method()`, `RenderingServer.get_video_adapter_name()`, `get_video_adapter_vendor()` and `get_video_adapter_api_version()`.

Draw the rows as one `Label` on a translucent black `ColorRect` at the top-left, in green `Palette.ramp`-safe colours (the overlay sits after the palette pass, so any colour is fine). Refresh the text 4× a second. Set `process_mode = PROCESS_MODE_ALWAYS`.

- [ ] **Step 4: Import, then run the smoke test**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import && /Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn 2>&1 | grep -cE 'SCRIPT ERROR'; … | grep -E 'DIAG ok|SMOKE TEST COMPLETE'`
Expected: `0`, then both lines.

- [ ] **Step 5: Commit**: `feat(diag): hidden diagnostics overlay with frame, draw and boot stats (Step 7)`

---

### Task 2: Toggles (Shift+F3, build-stamp long-press, `?diag=1`), and the spike FPS label goes

**Files:**
- Modify: `scripts/game.gd:2208` (`_unhandled_input`: the Shift+F3 check comes first, before `feedback`)
- Modify: `scripts/overlays.gd:788, 964` (both build-stamp labels), plus a new `signal diag_toggle_requested`
- Modify: `scripts/touch_controls.gd`: delete `_fps_label`, `_fps_accum`, `_fps_frames` and `_worst_frame`, the label build (`:172-177`) and the readout block (`:551-560`)
- Modify: `web/vr_shell.html`: parse `?diag=1` into `window.vrDiagOn = true` next to the `?touch=1` parse (`:445`). `game._ready` reads it through `JavaScriptBridge.eval("window.vrDiagOn === true", true)` and calls `diag.set_shown(true)`.
- Test: `tests/smoke_test.gd` (DIAG section), `tests/screenshot_probe.gd` (new `shot_diag.png` over the L1 corridor)

**Interfaces:**
- Consumes: `DiagOverlay.toggle()` and `game.diag` from Task 1.
- Produces:
  - `Overlays.diag_toggle_requested`, emitted once per long-press, connected in `game._ready` to `diag.toggle`;
  - `func _make_stamp(p: Control, pos: Vector2) -> Label` in `overlays.gd`. It replaces both `_text(… BuildInfo.label() …)` calls and sets `mouse_filter = MOUSE_FILTER_STOP`. Its `gui_input` starts a 1.0 s timer on press and cancels it on release or exit, so it fires at 1.0 s while still held.
  - `const STAMP_HOLD := 1.0`.

- [ ] **Step 1: Write the failing tests** (the DIAG section continues)

```gdscript
var dg_key := InputEventKey.new()
dg_key.keycode = KEY_F3; dg_key.shift_pressed = true; dg_key.pressed = true
game._unhandled_input(dg_key)
assert(dg.visible)
game._unhandled_input(dg_key)
assert(not dg.visible)
var dg_plain := dg_key.duplicate(); dg_plain.shift_pressed = false
game._unhandled_input(dg_plain)
assert(not dg.visible)   # plain F3 does nothing
var dg_stamp: Label = game.overlays._stamp_labels[0]
var dg_down := InputEventMouseButton.new(); dg_down.button_index = MOUSE_BUTTON_LEFT; dg_down.pressed = true
var dg_up := dg_down.duplicate(); dg_up.pressed = false
dg_stamp.gui_input.emit(dg_down); await game.get_tree().create_timer(0.3).timeout
dg_stamp.gui_input.emit(dg_up); await game.get_tree().create_timer(1.0).timeout
assert(not dg.visible)   # a short tap never toggles
dg_stamp.gui_input.emit(dg_down); await game.get_tree().create_timer(0.4).timeout
dg_stamp.mouse_exited.emit(); await game.get_tree().create_timer(1.0).timeout
assert(not dg.visible)   # sliding off cancels
dg_stamp.gui_input.emit(dg_down); await game.get_tree().create_timer(1.15).timeout
assert(dg.visible)       # a held press toggles at 1 s, before release
dg_stamp.gui_input.emit(dg_up); dg.set_shown(false)
var dg_tc := TouchControls.new()   # game.touch_ui is null headless, so probe a fresh one
assert(not "_fps_label" in dg_tc)   # the always-on spike readout is gone
dg_tc.free()
print("DIAG toggles ok — Shift+F3, stamp long-press (tap/slide-off ignored), spike label removed")
```

(Godot emulates mouse from touch, so `gui_input` mouse events cover a finger too. Keep `_stamp_labels: Array[Label]` in `overlays.gd` for the test.)

- [ ] **Step 2: Run it to verify it fails**: the same smoke command. Expected: an assert or SCRIPT ERROR at the first `dg.visible`.

- [ ] **Step 3: Implement the three toggles and delete the spike label** as listed under Files. Shift+F3 marks the input handled (`get_viewport().set_input_as_handled()`).

- [ ] **Step 4: Add `shot_diag.png` to `tests/screenshot_probe.gd`.** After `shot_corridor.png`, call `game.diag.set_shown(true)`, wait 30 frames, then `_capture_root("shot_diag.png", dir)` and hide it again. Also add the shot to the header list.

- [ ] **Step 5: Verify**
  - Run the smoke test: expect 0 `SCRIPT ERROR`, `DIAG toggles ok`, `SMOKE TEST COMPLETE`.
  - Run `/Applications/Godot.app/Contents/MacOS/Godot --path . tests/screenshot_probe.tscn` (windowed). Expect `SCREENSHOT PROBE COMPLETE`.
  - Eyeball `shot_diag.png`: six legible rows, nothing clipped, the HUD still readable beside it.
  - Eyeball `shot_touch.png`: no FPS text any more.

- [ ] **Step 6: Commit**: `feat(diag): Shift+F3, build-stamp long-press and ?diag=1 toggles; drop the always-on touch FPS label`

---

### Task 3: `vrReport()` carries everything, and the lost-context reload screen

**Files:**
- Modify: `scripts/game.gd`. Add `func _publish_diag() -> void`, web only, called from `_process` every 2.0 s of real time. It writes `window.vrBoot.diag = <JSON of diag.snapshot()>` through `JavaScriptBridge.eval`. The overlay doesn't need to be visible: `snapshot()` keeps the frame buffer filled whenever this needs it, because `DiagOverlay._process` samples whenever `visible or OS.has_feature("web")`.
- Modify: `web/vr_shell.html`:
  - Add `#vr-lost`: a full-screen div, `z-index: 300`, hidden by default. It uses the DOS-window look of `#vr-loading` (reuse its CSS variables), with the text `SIGNAL LOST` / `The display took a break. Tap to reload — your last checkpoint is waiting.`
  - On `canvas` `webglcontextlost`: call `e.preventDefault()`, increment `window.vrBoot.contextLost`, then show `#vr-lost`. Its `click` and `touchend` handlers call `location.reload()`.
  - `vrReport()` adds `diag: window.vrBoot.diag` (already inside `boot`, so nothing more is needed) and `contextLost`.
- Modify: `tests/web_check.mjs`. After the `5_flight` shot:
  1. Stop counting errors (`const lostAt = errors.length`, and only `errors.slice(0, lostAt)` decides the exit).
  2. Assert `window.vrBoot.diag.fps > 0` and `typeof window.vrBoot.diag.renderer === 'string'`.
  3. Lose the context with `document.getElementById('canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext()`.
  4. Wait 500 ms. Assert `document.elementFromPoint(480,300).closest('#vr-lost')` is not null, then take shot `6_lost`.
  5. Print `diag ok` and `lost screen ok`, and exit 1 if either assert fails.

**Interfaces:**
- Consumes: `DiagOverlay.snapshot()` (Task 1).
- Produces: `window.vrBoot.diag` (the snapshot's keys) and `window.vrBoot.contextLost: number`.

- [ ] **Step 1: Write the failing web-check asserts** (listed above) **and a smoke assert.** `game._diag_json()`, the pure helper `_publish_diag` uses, returns a string that `JSON.parse_string` turns into a Dictionary holding `fps` and `renderer`.
- [ ] **Step 2: Export and run, verifying failure**: `./build.sh`-equivalent local export (`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Web dist/index.html` after `./stamp_build.sh`), then `node tests/web_check.mjs web-out dist`. Expected: FAIL on `diag` or `lost screen`.
- [ ] **Step 3: Implement** `_diag_json`, `_publish_diag`, `#vr-lost` and the listener.
- [ ] **Step 4: Verify**
  - The smoke test is green.
  - After a fresh export, `node tests/web_check.mjs web-out dist` prints `diag ok`, `lost screen ok` and `no script, shader or page errors`, then exits 0.
  - Eyeball `web-out/6_lost.png`.
  - `grep -c '\$GODOT_' dist/index.html` prints 0.
- [ ] **Step 5: Commit**: `feat(web): vrReport carries live diagnostics; tap-to-reload screen on WebGL context loss`

---

### Task 4: The device-pass checklist, and the full gate

**Files:**
- Create: `docs/device-pass/2026-11-24-step7-device-pass.md`
- Modify: `docs/ios/TESTFLIGHT.md:82`. Point the borrowed block at the new doc for the method (the native app has no `vrReport`, but it does have the overlay).
- Modify: `docs/revamp/2026-09-28-m5-m9-reaudit.md`. In the progress table, Step 7 becomes "Tooling done (PR #N); device pass pending John".

**What the checklist contains** (one table per device, each row with *Expected / Result / Notes* columns):
- **Devices:** iPad (Safari), iPhone (Safari), a mid-range Android (Chrome), desktop Chrome, Firefox and Safari. iOS native goes through `TESTFLIGHT.md`.
- **Setup:** open `https://beyondthevoidrunner.netlify.app/?diag=1`, or long-press the build stamp. On a desktop, paste the `vrReport()` output into the results at the end.
- **Rows:**
  - Title-up time.
  - FLIGHT time.
  - BAKE (expect `PRE Y`; compare with `tests/perf_baseline.md`).
  - BOSS bake at the first boss level.
  - FPS and WORST in the L8 dense arena and the L9 boss (pass: avg ≥ 50, worst ≤ 50 ms).
  - DRAWS and OBJS in the same two spots.
  - Fog-distance shimmer on distant sprites (method: hover at a far arena wall and watch a sprite 60+ u away for 10 s; *pass* if no sprite flickers between two looks frame-to-frame. *Fail* means queue the lower-res distant set).
  - Touch on PRESS START.
  - Audio starts on the first touch or press.
  - Pause on tab or app switch.
  - Checkpoint CONTINUE after closing the tab mid-sector.
  - Lost-context recovery (desktop Chrome: DevTools console `document.getElementById('canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext()` → SIGNAL LOST → tap → reload → CONTINUE).
  - Reduce Flash/Roll toggles still apply.
- **Decision rules** at the end:
  - Which failures block Step 8: FPS, the lost-context recovery and CONTINUE.
  - Which only queue work: shimmer leads to the distant-sprite set, and a slow bake leads to a bake-budget item.

- [ ] **Step 1: Write the checklist doc and the two doc edits.**
- [ ] **Step 2: Run the full gate on the branch tip**
  - Import, then the smoke test: 0 `SCRIPT ERROR`, `SMOKE TEST COMPLETE`.
  - Screenshot probe: PNGs eyeballed.
  - Warmup, forge and perf probes (`tests/warmup_probe.tscn`, `tests/forge_probe.tscn`, `tests/perf_probe.tscn`): no new step over 8 ms (the overlay is hidden by default, so expect no change).
  - Fresh Web export, then `python3 tools/check_budgets.py`.
  - `node tests/web_check.mjs web-out dist`.
  - `./build_ios.sh`.
  - No sprite, `studio.gdshader`, `TextureGen` or class-table changes, so no rebake.
- [ ] **Step 3: Commit**: `docs: Step 7 device-pass checklist`
- [ ] **Step 4: Session log**
  - Append an entry to `../CLAUDE.md` §6.
  - Update `./CLAUDE.md` "Current work": Step 7 tooling is in, the device pass is John's, and Step 8 follows.
  - Commit only when John asks.
