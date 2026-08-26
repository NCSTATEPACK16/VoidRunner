# M4c + M4d: Mobile Play Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish mobile touch play — a D-pad steering alternative to the default floating stick (D9), an opt-in gyro fine-aim layer, an end-of-session home-screen install nudge (D11), and routing that boots real phones straight into the touch build instead of gating them behind a manual "try anyway" click. Close out M11 items still blocking a public post that this phase owns.

**Architecture:** Everything here extends two files that already carry the whole touch system — `scripts/touch_controls.gd` (the `CanvasLayer` input surface) and `scripts/game_state.gd` (persisted settings) — plus the settings UI in `scripts/overlays.gd` and the web boot sequence in `web/vr_shell.html`. No new nodes or autoloads. The D-pad and gyro paths both terminate in the exact same `Input.action_press(action, strength)` / `Input.action_release(action)` calls the floating stick already uses, so `player.gd` needs zero changes — it already reads `steer_left/right/up/down` via `Input.get_action_strength()` (see `player.gd:135-152`), which is what let M4b's floating stick "just work" against existing gameplay code.

**Tech Stack:** GDScript (Godot 4.7), Godot's `Input` singleton action system, `JavaScriptBridge` for the two web-only pieces (gyro permission prompt, install prompt), plain JS additions to `web/vr_shell.html`.

**Spec:** `../../../../PLAN.md` (the parent `RadixRemix/PLAN.md`), Part Two §M4 — specifically the M4c/M4d bullets and the D9/D11 decision rows in the table above them. This plan is the bite-sized breakdown of that spec; read both.

## Global Constraints

- Hard rule (repo `CLAUDE.md`): everything shipped is code-generated in this repo — no imported assets. Nothing in this plan adds art assets; it's all `Panel`/`StyleBoxFlat`/`Label` UI built the same way `touch_controls.gd` already builds its buttons.
- Never name the specific commercial '95 DOS game this project draws on, in code, comments, or docs — genre-generic phrasing only (already enforced project-wide as of `d2ecffb`).
- Rendering profile must not change: 320×200 viewport, GL Compatibility, nearest filtering. `TouchControls` already lives outside the SubViewport in canvas-item units (see its own class doc comment) — new UI must follow that same pattern, not screen pixels. M4b shipped with this exact bug (screen-px literals in a canvas-unit space) and fixed it in `aa51ccc`/`9eb84e9` — do not reintroduce it. Every new geometry constant in this plan is already expressed in canvas units.
- Threads stay off (`thread_support=false` in the Web export preset) — nothing here touches that.
- Every settings addition must go through `GameState`'s existing load/save/apply triangle (`load_settings()`, `_save_settings()`, `apply_settings()` in `scripts/game_state.gd:344-383`) — a setting that isn't wired into all three silently resets on reload.
- Gate discipline before any task is "done": headless `godot --headless --import`, then headless `tests/smoke_test.tscn` with zero `SCRIPT ERROR` lines, then a rendered pass of `tests/screenshot_probe.tscn` eyeballed for the new UI, then a clean `Web` export (`godot --headless --export-release "Web" dist/index.html`, checked for unsubstituted `$GODOT_` placeholders). This project does not use a unit-test framework — `tests/smoke_test.gd` is a single scripted headless run with `assert()` calls; follow that idiom, don't introduce a new one.
- Commit per task. Update `PLAN.md`'s M4 ledger row and `CLAUDE.md` §6 at the end of the session, per this project's own established convention (every prior session in the log does this).

---

## Task 1: D-pad steering setting (persisted, off by default)

**Files:**
- Modify: `scripts/game_state.gd:315-383` (settings block)
- Modify: `scripts/overlays.gd:349-373` (`_build_settings`)
- Test: `tests/smoke_test.gd` (extend the existing M1/M2 settings section)

**Interfaces:**
- Produces: `GameState.touch_dpad_enabled: bool` (default `false`), persisted under `settings.cfg` key `"dpad"`. Read by Task 2.

- [ ] **Step 1: Add the field and wire it into the load/save/apply triangle**

In `scripts/game_state.gd`, add next to the other M1/M2 comfort settings (after `var view_fov := 78.0`):

```gdscript
## M4c: swaps the floating steering stick for a fixed D-pad. Off by default —
## the stick is what a first-time touch player meets (D9); this is the opt-in alt.
var touch_dpad_enabled := false
```

In `load_settings()`, add alongside the other `cfg.get_value` reads:

```gdscript
		touch_dpad_enabled = cfg.get_value("settings", "dpad", touch_dpad_enabled)
```

In `_save_settings()`, add alongside the other `cfg.set_value` calls:

```gdscript
	cfg.set_value("settings", "dpad", touch_dpad_enabled)
```

`apply_settings()` needs no change — `touch_dpad_enabled` is read live by `TouchControls` each time it rebuilds its steering zone (Task 2), the same way `GameState.gamepad_enabled` is read live by `player.gd`'s `update_flight()` rather than pushed through a signal.

- [ ] **Step 2: Add the settings-panel toggle**

`_build_settings()`'s toggle grid (`scripts/overlays.gd:349-373`) has 4 left-column rows filled (y=92/110/128/146) and only 3 of 4 right-column rows filled (y=92/110/128 — y=146 is free). Add:

```gdscript
	_toggle_row(p, Vector2(166, 146), "TOUCH D-PAD", "dpad", func() -> void:
		GameState.touch_dpad_enabled = not GameState.touch_dpad_enabled)
```

`_toggle_row`'s `key` parameter must match the `settings.cfg` key from Step 1 exactly — it's used both as the `_settings_labels` dictionary key and (via `_refresh_settings()`) to find the ON/OFF button to relabel. `_refresh_settings()` (`overlays.gd:408-418`) iterates `_settings_labels` generically, so no separate change is needed there — but read that function before this step to confirm it doesn't special-case the toggle keys list (it shouldn't; the other three M1/M2 toggles were added the same way with no changes there).

- [ ] **Step 3: Extend the smoke test**

In `tests/smoke_test.gd`'s existing settings round-trip section (search for the `for k in ["volume", "sens", "fov", ...]` loop, ~line 642), add `"dpad"` to that key list so the generic round-trip assertion covers it for free. Then add one targeted assertion near the other M1/M2-specific checks:

```gdscript
	assert(GameState.touch_dpad_enabled == false)   # default off, per D9
	game.overlays._adjust_setting("dpad", 1)   # wait — see note below
```

Note: `_adjust_setting` is for the stepper rows (VOLUME/SENS/FOV); toggles are flipped via the `Callable` passed to `_toggle_row`, not `_adjust_setting`. Call the toggle directly instead:

```gdscript
	assert(GameState.touch_dpad_enabled == false)
	GameState.touch_dpad_enabled = not GameState.touch_dpad_enabled
	assert(GameState.touch_dpad_enabled == true)
	GameState.save_settings if GameState.has_method("save_settings") else GameState._save_settings()
```

Actually, prefer exercising the real UI path used everywhere else in this file rather than flipping the field directly — find how the existing `"dither"`/`"gamepad"` toggles are tested in this file (grep the smoke test for `_settings_labels` or the toggle button lookup pattern already used for GAMEPAD) and copy that exact pattern for `"dpad"` so the test proves the button, not just the field.

- [ ] **Step 4: Run the gate**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
```

Expected: `SMOKE TEST COMPLETE`, zero `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/game_state.gd scripts/overlays.gd tests/smoke_test.gd
git commit -m "feat(settings): add TOUCH D-PAD toggle (M4c, off by default per D9)"
```

---

## Task 2: D-pad steering UI in TouchControls

**Files:**
- Modify: `scripts/touch_controls.gd`
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `GameState.touch_dpad_enabled: bool` (Task 1).
- Produces: no new public API — the D-pad drives the same `steer_left/right/up/down` actions the floating stick already drives, so nothing downstream needs to know which mode is active.

- [ ] **Step 1: Add D-pad geometry constants**

Next to the existing stick constants (`touch_controls.gd:21-31`), add:

```gdscript
## M4c: fixed D-pad alternative to the floating stick (opt-in, D9). Same left-zone
## footprint as the stick, laid out as a 4-arrow cross anchored bottom-left so it
## doesn't collide with the boost double-tap area (which uses BOOST_TAP_DIST from
## the touch's *start* position, not a fixed zone, so any D-pad placement is safe).
const DPAD_BTN_SIZE := 22.0
const DPAD_GAP := 3.0
const DPAD_ANCHOR := Vector2(58.0, 50.0)   # (right, up) offset from bottom-left corner
```

- [ ] **Step 2: Build the D-pad panel (hidden by default, shown when the setting is on)**

Add a new builder, called from `_build()`:

```gdscript
var _dpad_root: Control
var _dpad_up: Panel
var _dpad_down: Panel
var _dpad_left: Panel
var _dpad_right: Panel
var _dpad_pressed := {"up": false, "down": false, "left": false, "right": false}


func _build_dpad() -> void:
	_dpad_root = Control.new()
	_dpad_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dpad_root.position = Vector2(DPAD_ANCHOR.x - DPAD_BTN_SIZE * 1.5, -DPAD_ANCHOR.y - DPAD_BTN_SIZE * 1.5)
	_dpad_root.size = Vector2(DPAD_BTN_SIZE * 3.0, DPAD_BTN_SIZE * 3.0)
	_dpad_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dpad_root.visible = false
	_root.add_child(_dpad_root)
	var mid := DPAD_BTN_SIZE
	_dpad_up = _dpad_cell(Vector2(mid, 0.0))
	_dpad_down = _dpad_cell(Vector2(mid, mid * 2.0))
	_dpad_left = _dpad_cell(Vector2(0.0, mid))
	_dpad_right = _dpad_cell(Vector2(mid * 2.0, mid))


func _dpad_cell(pos: Vector2) -> Panel:
	var btn := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.61, 0.25, 0.16)
	sb.border_color = Color(1.0, 0.61, 0.25, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("panel", sb)
	btn.position = pos
	btn.size = Vector2(DPAD_BTN_SIZE, DPAD_BTN_SIZE)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dpad_root.add_child(btn)
	return btn
```

Call `_build_dpad()` at the end of `_build()` (`touch_controls.gd:85-118`).

- [ ] **Step 3: Route steering input through the D-pad when the setting is on**

Replace the steering branch in `_on_touch()` (the `elif t.position.x < ... LEFT_ZONE_FRAC ... and _steer_touch < 0:` branch, `touch_controls.gd:225-228`) so it dispatches on the setting:

```gdscript
		elif t.position.x < get_viewport().get_visible_rect().size.x * LEFT_ZONE_FRAC \
				and _steer_touch < 0:
			_steer_touch = t.index
			if GameState.touch_dpad_enabled:
				_dpad_root.visible = true
				_update_dpad(t.position)
			else:
				_start_stick(t.position)
				_check_boost_tap(t.position)
```

And in `_input()`'s drag branch (`touch_controls.gd:203-211`):

```gdscript
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _steer_touch:
			if GameState.touch_dpad_enabled:
				_update_dpad(d.position)
			else:
				_update_stick(d.position)
```

And the release path in `_on_touch()` (the `if t.index == _steer_touch:` branch):

```gdscript
		if t.index == _steer_touch:
			_steer_touch = -1
			if GameState.touch_dpad_enabled:
				_end_dpad()
			else:
				_end_stick()
```

- [ ] **Step 4: Implement `_update_dpad` / `_end_dpad`**

A D-pad is discrete (on/off per direction), not proportional like the stick — mirror `_dpad_root`'s local rect to decide which cell(s) a finger is over, at most one horizontal + one vertical direction active at once (so a diagonal drag can hold e.g. up+left together, matching how a real D-pad works):

```gdscript
func _update_dpad(pos: Vector2) -> void:
	var local := pos - _dpad_root.global_position
	var want := {"up": false, "down": false, "left": false, "right": false}
	if _dpad_up.get_rect().has_point(local): want.up = true
	if _dpad_down.get_rect().has_point(local): want.down = true
	if _dpad_left.get_rect().has_point(local): want.left = true
	if _dpad_right.get_rect().has_point(local): want.right = true
	for dir in want:
		if want[dir] and not _dpad_pressed[dir]:
			Input.action_press("steer_%s" % dir, 1.0)
		elif not want[dir] and _dpad_pressed[dir]:
			Input.action_release("steer_%s" % dir)
	_dpad_pressed = want
	_dpad_up.modulate = Color(1.4, 1.4, 1.4) if want.up else Color.WHITE
	_dpad_down.modulate = Color(1.4, 1.4, 1.4) if want.down else Color.WHITE
	_dpad_left.modulate = Color(1.4, 1.4, 1.4) if want.left else Color.WHITE
	_dpad_right.modulate = Color(1.4, 1.4, 1.4) if want.right else Color.WHITE


func _end_dpad() -> void:
	for dir in _dpad_pressed:
		if _dpad_pressed[dir]:
			Input.action_release("steer_%s" % dir)
	_dpad_pressed = {"up": false, "down": false, "left": false, "right": false}
	_dpad_root.visible = false
```

`"steer_%s" % dir` resolves to exactly `steer_up`/`steer_down`/`steer_left`/`steer_right` — the same four actions `input_setup.gd` registers and `player.gd:135-152` reads via `Input.get_action_strength()`. A D-pad press always reports strength 1.0 (full-rate turn), matching a real gamepad D-pad's binary nature — no proportional curve to tune.

- [ ] **Step 5: Wire `_release_all()` and idle-fade to the D-pad path too**

`_release_all()` (`touch_controls.gd:177-186`) currently calls `_end_stick()` unconditionally. Change to:

```gdscript
	if _steer_touch >= 0:
		_steer_touch = -1
	if GameState.touch_dpad_enabled:
		_end_dpad()
	else:
		_end_stick()
```

In `_process()`'s idle-fade block, the stick ring's visibility line (`_stick_ring.visible = _steer_touch >= 0 or _boost_active`) should stay stick-only; add the equivalent for the D-pad so it also hides when idle and isn't left painted over the game-over screen:

```gdscript
	if not GameState.touch_dpad_enabled:
		_stick_ring.visible = _steer_touch >= 0 or _boost_active
```

(the D-pad's own visibility is already handled by `_update_dpad`/`_end_dpad` directly, so no per-frame line is needed for it — just make sure the stick-ring line doesn't fight it when D-pad mode is active, since both panels exist simultaneously in the tree and only one is meant to be visible at a time.)

- [ ] **Step 6: Extend the smoke test**

Add a D-pad section modeled on the existing M4b zone-dispatch test (search `tests/smoke_test.gd` for how it currently drives a synthetic `InputEventScreenTouch`/`InputEventScreenDrag` into `TouchControls` for the floating-stick test — copy that harness). New assertions:

```gdscript
	# M4c: D-pad mode drives the same steer_* actions at full strength
	GameState.touch_dpad_enabled = true
	# ... synthesize a touch press inside the D-pad's "up" cell using the same
	# harness pattern the stick test above uses (an InputEventScreenTouch at the
	# _dpad_up global rect center, index 0) ...
	assert(is_equal_approx(Input.get_action_strength("steer_up"), 1.0))
	# ... synthesize the release ...
	assert(is_equal_approx(Input.get_action_strength("steer_up"), 0.0))
	GameState.touch_dpad_enabled = false
```

- [ ] **Step 7: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn   # eyeball the new shot for D-pad geometry
godot --headless --export-release "Web" dist/index.html
git add scripts/touch_controls.gd tests/smoke_test.gd
git commit -m "feat(touch): D-pad steering alternative (M4c, D9's opt-in path)"
```

---

## Task 3: Gyro fine-aim (opt-in, additive nudge)

**Files:**
- Modify: `scripts/game_state.gd` (new setting)
- Modify: `scripts/overlays.gd` (`_build_settings` — see note on grid space below)
- Modify: `scripts/player.gd:112-119` (`apply_mouse_look`) or `update_flight` (`player.gd:126-220`)
- Modify: `web/vr_shell.html` (iOS permission gesture bridge)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces: `GameState.gyro_aim_enabled: bool` (default `false`), persisted under key `"gyro"`.
- Consumes (web only): `Input.get_gyroscope() -> Vector3` (Godot's built-in, populated from the browser's `DeviceOrientationEvent` on platforms that grant permission).

- [ ] **Step 1: Settings field + persistence**

Same pattern as Task 1 Step 1, in `scripts/game_state.gd`:

```gdscript
## M4c: small additive fine-aim nudge from device tilt, on top of stick/D-pad
## steering. Opt-in — iOS requires an explicit permission gesture (Step 4 below)
## and a constant background nudge is disorienting for anyone who doesn't want it.
var gyro_aim_enabled := false
```

Add to `load_settings()`: `gyro_aim_enabled = cfg.get_value("settings", "gyro", gyro_aim_enabled)`
Add to `_save_settings()`: `cfg.set_value("settings", "gyro", gyro_aim_enabled)`

- [ ] **Step 2: Settings-panel toggle — grid is full, so this one needs a row, not a slot**

`_build_settings()`'s 2×4 toggle grid (`overlays.gd:349-373`) is now full after Task 1 (D-PAD took the last open slot at y=146 right column). Rather than shrinking existing rows, drop the row spacing from 18 to 15 canvas units for the right column only and add a 4th right-column row at y=143, or — simpler and lower-risk — make GYRO AIM a `_setting_row` (stepper: OFF/ON, reusing `_setting_row`'s existing 3-value cycle machinery) placed as a 4th line under the three existing stepper rows, pushing the `COMFORT & DISPLAY` box down by one row (currently `Rect2(8, 88, 304, 78)` starting at y=88; move to y=100 and add the new stepper row at y=82). Re-flow all y-offsets below it (`_toggle_row` calls, the `< BACK` button) by the same +12 delta. Read `_build_settings()` in full again before this step and pick whichever reflow is cleanest in the actual current geometry rather than assuming the deltas above are exact — the point is: 320×200 has no free real estate, so adding a 9th control means shifting something, not just appending.

- [ ] **Step 3: iOS permission bridge in `vr_shell.html`**

iOS Safari requires `DeviceOrientationEvent.requestPermission()` to be called from inside a user-gesture handler (a raw page-load listener is silently ignored). Add near the existing web-only bridges (same file that already has `vrShowLoading`/`vrReport`/`vrDiag`):

```javascript
window.vrRequestGyro = function () {
	if (typeof DeviceOrientationEvent !== 'undefined'
			&& typeof DeviceOrientationEvent.requestPermission === 'function') {
		DeviceOrientationEvent.requestPermission().catch(function () {});
	}
	// Android and desktop browsers need no permission call — Godot's own
	// DeviceOrientationEvent listener (registered internally by the engine on
	// web export) picks up the events once any listener has been attached,
	// which the iOS branch above satisfies as a side effect of the request.
};
```

- [ ] **Step 4: Call the permission bridge from the settings toggle**

In `overlays.gd`'s new gyro row callback (Step 2), call the bridge before flipping the field, gated to web:

```gdscript
	# ... inside the row's toggle Callable, before `GameState.gyro_aim_enabled = ...`:
	if not GameState.gyro_aim_enabled and OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.vrRequestGyro) window.vrRequestGyro();")
```

Only fire the request when turning the setting ON (the guard above checks the *pre-flip* value), so it fires exactly once per session as a direct result of the tap that enabled it — the actual required user gesture.

- [ ] **Step 5: Apply the tilt as an additive nudge in `player.gd`**

Add constants next to the other steering constants (`player.gd:19-22`):

```gdscript
const GYRO_YAW_SENS := 0.6     # rad/s of device tilt -> yaw rad/s
const GYRO_PITCH_SENS := 0.6
const GYRO_MAX_NUDGE := 0.35   # rad/s cap, so gyro can only ever be a fine-aim
                                # layer on top of stick/D-pad, never the whole turn
```

In `update_flight()`, after the existing keyboard/touch steering block and before the gamepad block (so it composes additively with whichever discrete input is active), add:

```gdscript
	# --- M4c: gyro fine-aim, additive on top of stick/D-pad/keyboard ---
	if GameState.gyro_aim_enabled:
		var gyro := Input.get_gyroscope()
		var gyaw := clampf(-gyro.y * GYRO_YAW_SENS, -GYRO_MAX_NUDGE, GYRO_MAX_NUDGE)
		var gpitch := clampf(gyro.x * GYRO_PITCH_SENS * kb_inv, -GYRO_MAX_NUDGE, GYRO_MAX_NUDGE)
		yaw += gyaw * delta
		pitch = clampf(pitch + gpitch * delta, -PITCH_LIMIT, PITCH_LIMIT)
```

Note `kb_inv` is already computed earlier in this same function for the invert-Y setting — reuse it rather than recomputing, so gyro respects the same invert preference as every other pitch input. `Input.get_gyroscope()` returns `Vector3(0,0,0)` on any platform/device that hasn't granted permission or doesn't have a sensor, so this is inert everywhere the feature isn't actually available — no platform branch needed in GDScript itself.

- [ ] **Step 6: Extend the smoke test**

Headless has no real gyroscope, so the assertion is necessarily about the setting round-trip and the dead-when-off/present-when-on code path, not actual tilt response (parked, like M4a's Android check, to a real-device pass):

```gdscript
	assert(GameState.gyro_aim_enabled == false)   # default off
	# round-trip through settings.cfg — add "gyro" to the existing generic key loop
```

- [ ] **Step 7: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless --export-release "Web" dist/index.html
grep -c 'vrRequestGyro' dist/index.html   # confirm the bridge survived the export, non-zero
git add scripts/game_state.gd scripts/overlays.gd scripts/player.gd web/vr_shell.html tests/smoke_test.gd
git commit -m "feat(touch): opt-in gyro fine-aim nudge (M4c)"
```

**Manual verification note (cannot be automated):** actual gyro behavior needs a real iOS and Android device — flag this explicitly in the session's CLAUDE.md log as untested-on-hardware, same as M4b's touch feel.

---

## Task 4: End-of-session install nudge (D11)

**Files:**
- Modify: `web/vr_shell.html` (capture + expose the `beforeinstallprompt` event)
- Modify: `scripts/overlays.gd` (`_build_game_over`, `_build_victory`, `_build_start`)
- Test: `tests/smoke_test.gd`, `tests/screenshot_probe.gd`

**Interfaces:**
- Produces (web JS): `window.vrCanInstall(): bool`, `window.vrPromptInstall(): void`.
- Produces (GDScript): a reusable `_install_button(p: Control, pos: Vector2) -> void` helper in `overlays.gd`, following the exact same pattern as the existing `_feedback_button()` helper (`overlays.gd:629-632`) — one button, built the same way everywhere it appears.

- [ ] **Step 1: Capture the install prompt event in `vr_shell.html`**

`beforeinstallprompt` fires once, early, and only if the browser considers the page installable (HTTPS, a valid manifest, etc.) — it must be captured immediately at script load and stashed, not requested on demand. Add near the top-level state (alongside `window.vrTouchMode`):

```javascript
window.vrInstallEvent = null;
window.addEventListener('beforeinstallprompt', function (e) {
	e.preventDefault();
	window.vrInstallEvent = e;
});
window.vrCanInstall = function () {
	return window.vrInstallEvent !== null;
};
window.vrPromptInstall = function () {
	if (!window.vrInstallEvent) { return; }
	window.vrInstallEvent.prompt();
	window.vrInstallEvent = null;   // a captured prompt can only be shown once
};
```

Note for the doc: iOS Safari does not fire `beforeinstallprompt` at all (Apple has no equivalent API) — `vrCanInstall()` correctly returns `false` there, so the in-game button simply won't render, which is the right behavior rather than showing a button that does nothing. A future session could add iOS-specific "tap Share → Add to Home Screen" instructional copy if this matters enough to John; out of scope here.

- [ ] **Step 2: Add the reusable install-button helper**

In `overlays.gd`, mirroring `_feedback_button()`:

```gdscript
## D11: one install-nudge button, built the same way everywhere it appears.
## Only renders where the browser actually offered an install prompt (see
## web/vr_shell.html's vrCanInstall) — never shown on desktop or iOS Safari.
func _install_button(p: Control, pos: Vector2) -> void:
	if not OS.has_feature("web"):
		return
	if not JavaScriptBridge.eval("window.vrCanInstall ? window.vrCanInstall() : false"):
		return
	_button(p, pos, "INSTALL APP", func() -> void:
		JavaScriptBridge.eval("if (window.vrPromptInstall) window.vrPromptInstall();"))
```

- [ ] **Step 3: Place it on game-over, victory, and the start screen — never as a gate**

Per D11 ("ask only at the end... stays available as a quiet option from the start screen"), call `_install_button()` from `_build_game_over()` (`overlays.gd:305-313`) and `_build_victory()` (`overlays.gd:332-341`) at an unused position in each panel's existing layout, and from `_build_start()` (`overlays.gd:198-232`) as a small, low-emphasis line (not competing with the terminal-prompt CTA button from the retro-terminal restyle) — read all three builder functions first to find a coordinate that doesn't collide with existing buttons/text before placing it; this project's own history (`2026-07-27` session) shows exactly this kind of collision is easy to introduce and easy to catch late, so verify by screenshot, not by arithmetic alone.

- [ ] **Step 4: Extend the smoke test and screenshot probe**

Smoke: `_install_button` must not throw when `JavaScriptBridge` is unavailable (desktop/headless) — the `OS.has_feature("web")` guard makes this a no-op there, so simply calling `_build_game_over()`/`_build_victory()`/`_build_start()` headless (which the smoke test already does as part of booting the game) is the test; add an explicit comment noting this rather than a new assertion, since there's nothing to assert against on a platform where the feature is correctly absent.

Screenshot probe: add captures of the game-over and victory panels if they aren't already captured (`tests/screenshot_probe.gd` — check its existing capture list first), and eyeball that INSTALL APP does not render in the headless/rendered-desktop screenshot (correct — desktop is not `OS.has_feature("web")`) and that its layout slot doesn't collide with existing text in a mocked "as if web" render if the probe supports that; if it doesn't, note in the commit message that this button's actual on-screen appearance is unverified until a real web+mobile pass (M4d below covers the routing half of that pass; the button's visual fit is a fast manual check once dist/ is served locally with a fake `vrCanInstall` returning true).

- [ ] **Step 5: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
godot --headless --export-release "Web" dist/index.html
git add web/vr_shell.html scripts/overlays.gd tests/smoke_test.gd tests/screenshot_probe.gd
git commit -m "feat(web): end-of-session install nudge, D11"
```

---

## Task 5: M4d routing — phones boot straight into touch, no gate click

**Files:**
- Modify: `web/vr_shell.html` (the phone-heuristic IIFE, `web/vr_shell.html:439-` per the current gate block)

**Interfaces:** none (JS-only, no GDScript surface).

- [ ] **Step 1: Read the current gate block in full before touching it**

`web/vr_shell.html`'s phone-heuristic IIFE (starts at the `// M1.1: phone detection` comment, roughly line 439) currently: detects touch+coarse+shortEdge<600, and if matched and `window.vrTouchMode` isn't already true, shows the capability card (`window.vrGated = true`) and requires the user to click `#vr-gate-anyway` before booting. This was the correct default while the touch build was unproven (M1's kill criterion #3: "mobile visitors get a broken canvas with no explanation"). M4b has since shipped a real, playable touch build — so the default should flip: a matched device should boot directly into touch play, with the capability card demoted to a true fallback rather than the default phone experience.

- [ ] **Step 2: Flip the default — auto-arm touch mode instead of gating**

Change the IIFE so a matched device sets `window.vrTouchMode = true` and calls `window.vrArmPortraitWatch()` directly, the same two calls the "LET ME TRY ANYWAY" button currently performs, and skips setting `window.vrGated`:

```javascript
(function () {
	var coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
	var touch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
	var shortEdge = Math.min(window.screen.width, window.screen.height);
	if (window.vrTouchMode) { return; }   // already armed via ?touch=1 or an earlier call
	if (!(touch && coarse && shortEdge < 600)) { return; }
	// M4d: the touch build is proven (M4b) — phones boot straight in, no click gate.
	window.vrTouchMode = true;
	window.vrArmPortraitWatch();
}());
```

- [ ] **Step 3: Keep the capability card wired, but only as a manual escape hatch**

Do not delete the `#vr-gate` markup, `#vr-gate-anyway` button, or `window.vrGated` machinery — they're still the right fallback for a device the heuristic gets wrong in the other direction (a touch-capable device that the game genuinely can't run well, e.g. no WebGL2). Repoint them: instead of auto-showing on every phone-heuristic match, the card becomes reachable only from a small persistent "problems? tap here" affordance (or is simply left dormant — since nothing currently calls `gate.style.display = 'flex'` except the block just replaced in Step 2, and the WebGL2-missing case is already separately handled by the existing `STALLED AFTER 20s` diagnostic path). **Open call for John:** whether the card needs a manual entry point at all now that phones auto-boot, or whether it should be deleted entirely once M4d's device pass confirms the touch build holds up broadly. Default for this task: leave the markup and the `vrGated` reads elsewhere in the boot sequence (`if (!window.vrGated) { window.vrStartEngine(); }`) untouched — since nothing sets `vrGated` true anymore after this change, `vrStartEngine()` always fires, which is exactly the new intended behavior; the dead code is cheap insurance for a fast revert if John wants the gate back after the device pass.

- [ ] **Step 4: Gate + commit**

This is JS-only inside a file jCodemunch doesn't index and the headless smoke test doesn't execute (it never runs a browser) — the correctness check here is a real browser. Local verification:

```bash
godot --headless --import
godot --headless --export-release "Web" dist/index.html
python3 -m http.server 8765 --directory dist &
```

Then, in a real browser's mobile device emulation (Chrome DevTools device toolbar, an iPhone/Android profile) or — better, since emulation doesn't always match `matchMedia('(pointer: coarse)')` faithfully — an actual phone on the same LAN (`http://<mac-ip>:8765`), confirm: the game boots directly into touch mode with no capability card, the on-screen FPS/worst-frame readout (`touch_controls.gd`'s `_fps_label`) appears, and steering/fire/boost all work per M4b's existing feel.

```bash
git add web/vr_shell.html
git commit -m "feat(web): route phone-heuristic devices straight into touch play (M4d)"
```

---

## Task 6: M4d's mid-range Android check + full gate (manual, closes M11 items)

This task has no code — it is the actual device pass M4a's iPhone measurement explicitly could not stand in for, and it's what M4d's plan-doc gate requires before this phase is "done."

- [ ] **Step 1:** John runs the served `dist/` build (from Task 5) on a real mid-range Android phone (not flagship — the whole point is a device below the iPhone 15 Pro Max's ceiling) in a real mobile browser (Chrome for Android is the priority; Samsung Internet if easy). Record the on-screen FPS/worst-frame readout from a full sector-1 run.
- [ ] **Step 2:** Same device, confirm the D-pad toggle (Task 2), gyro toggle + iOS-equivalent Android permission flow (Task 3 — Android typically needs no explicit prompt, verify), and install nudge (Task 4) all work as designed.
- [ ] **Step 3:** iPhone (reuse M4a's device if available) — repeat the D-pad/gyro/install checks there too, and specifically the iOS gyro permission gesture from Task 3 Step 3/4, which is iOS-only behavior nothing else in this plan can verify.
- [ ] **Step 4:** Record results in `CLAUDE.md` §6 (this project's established log) and update `PLAN.md`'s M4 ledger row: mark M4c/M4d done or partial, with the actual numbers, mirroring exactly how M4a's "60 FPS, worst 17ms, verdict PROCEED" was logged.

**Gate for M4c+M4d as a whole:** a full sector-1 run completes on both a physical iPhone and a physical mid-range Android, in landscape, without a framerate stall; D-pad, gyro, and install nudge all behave as designed on both; the phone auto-boot from Task 5 is confirmed in a real mobile browser (not just emulation). This is `PLAN.md`'s existing M4 gate — Task 6 is what actually clears it, since M4b never got this far.

---

## Self-Review

**Spec coverage:** M4c bullet 1 (simplified touch verb set) — not a separate task above; re-read `PLAN.md`'s M4c line after Tasks 1-4 ship and confirm the existing four-verb set (steer/fire/boost/weapon-swap/bomb) still reads as "simplified" once D-pad + gyro are added as opt-in extras, not new always-on verbs — they're settings-gated specifically so the default verb set doesn't grow. M4c bullet 2 (D-pad) → Task 2. M4c bullet 3 (gyro) → Task 3. M4d bullet 1 (routing) → Task 5. M4d bullet 2 (mid-range Android check) → Task 6. M4d bullet 3 (install nudge, D11) → Task 4. All covered.

**Placeholder scan:** Task 5 Step 3 carries one explicit open product call (keep vs. delete the dormant gate card) with a committed default and a stated rationale — this is a real decision left to John per this project's own pattern (see D9-D11's own history), not a vague TODO; the code path it describes is fully specified either way. No other placeholders found.

**Type consistency:** `touch_dpad_enabled`/`gyro_aim_enabled` are used identically (bool, same settings.cfg key naming style as `reduce_roll`/`invert_y`) everywhere they appear across Tasks 1-3. `_install_button`/`_feedback_button` follow the same `(p: Control, pos: Vector2) -> void` shape. `steer_%s % dir` in Task 2 Step 4 resolves to the exact four action names `input_setup.gd` registers — verified against that file's source, not assumed.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m4c-m4d-mobile-finish.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in one session using executing-plans, batch execution with checkpoints.

Tasks 1-5 are code; Task 6 is real-device verification and must be run by John regardless of which execution mode is chosen for 1-5.
