# M4b Touch Control Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the M4a touch-control spike with the real M4b touch layer: per-finger zone
ownership so a steering thumb and a button thumb can never steal each other's input, a floating
rate-control joystick that replaces relative-drag steering, a double-tap boost toggle that runs to
energy depletion, resized/repositioned FIRE/WEAPON/BOMB buttons that hide outside active flight,
and a fix for the web shell's portrait-rotate watcher.

**Architecture:** `scripts/touch_controls.gd` (a `CanvasLayer` living outside the 320×200
SubViewport, same pattern as `Overlays`) owns all touch input and translates it into the *same*
Input Map actions the keyboard already drives (`steer_left/right/up/down`, `boost`, `fire`), so
`player.gd`'s tuning is the single source of truth for both input methods. The one change to
`player.gd` is swapping its steering reads from boolean `is_action_pressed` to magnitude-aware
`get_action_strength`, which is a no-op for keyboard (a held key always reports strength 1.0) and
is what lets the floating stick report a *proportional* turn rate. `game.gd` gets a one-line
per-frame poll that keeps the touch layer's visibility and input-processing tied to
`state == State.PLAYING`, plus two new signal connections for the WEAPON/BOMB buttons. The web
shell's portrait watcher becomes a function that can be armed from two call sites instead of an
IIFE that only runs once at page load.

Everything here is gated behind the existing `_touch_mode` flag (itself gated behind the `?touch=1`
URL flag while M4 development continues) — the default desktop/mouse/keyboard build is untouched
byte-for-byte.

**Testing note — why this plan doesn't do strict per-step red/green:** this project has no unit
test framework; verification is a single ~770-line headless script,
`tests/smoke_test.gd`/`tests/smoke_test.tscn`, run via
`godot --headless --path void-runner-godot tests/smoke_test.tscn`, that boots the real game and
asserts against live state. Every prior feature in this codebase added its smoke-test coverage as
one consolidated section at the end of the session, not interleaved per micro-step, because the
script is one continuous procedural flow and mid-file insertions from multiple tasks would collide.
This plan follows that convention: Tasks 1-4 each end with a headless **compile-and-boot** check
(catches syntax/reference errors immediately, cheap), and Task 5 adds the full "M4b" assertion
section plus the project's complete gate (headless import, headless smoke test, screenshot probe,
web export). Task 5 is where the real red→green cycle happens, exactly as it has for every prior
feature logged in `../../../../CLAUDE.md` §6.

**Tech Stack:** Godot 4.7.stable, GDScript, GL Compatibility renderer, web export via
`build.sh`/`stamp_build.sh` (threads disabled).

**Spec:** the "Thumbs On Glass" artifact (M4 mobile control spec, 2026-08-22) and
`../../../../PLAN.md` Part Two §M4 (decisions D9-D11 locked). This plan implements **M4b only**
(build-order steps M4b-1 through M4b-4). M4c (home-screen install nudge / D11, D-pad alternative /
D9's opt-in, gyro fine-aim) is explicitly **out of scope** — a later plan.

## Global Constraints

- Godot version: 4.7.stable — do not use APIs newer than that.
- The touch layer is a `CanvasLayer` **outside** the 320×200 `SubViewport` (established pattern
  from `Overlays`) — but as a `CanvasLayer` in the root viewport it still inherits that viewport's
  `content_scale_mode = canvas_items`, so button/stick geometry is in **320×200 canvas units**
  (matching `hud.gd`/`overlays.gd`), NOT real screen pixels. **POST-REVIEW CORRECTION:** the plan
  as originally written got this wrong (assumed real screen pixels); see the Task 3 ruling for the
  corrected constants.
- Everything new is reached only through the existing `_touch_mode` flag in `game.gd` — the
  non-touch build must be byte-identical in behavior. Never remove or weaken that gate.
- D9 (locked): the floating joystick is the *only* touch steering method this plan builds. No D-pad
  alternative, no settings toggle — that's M4c-2, out of scope here.
- D10 (locked): boost on touch is a **left-zone double-tap that toggles the existing `boost` Input
  Map action on**, draining `GameState.energy` through the same path `player.gd` already uses for
  the desktop RMB hold. It is not a held button, and it does not auto-engage on straight runs.
- Web export must stay thread-free (`thread_support=false`) — no threading APIs anywhere in this
  change.
- No original '95-DOS-games assets or naming; this work doesn't touch assets, but any UI text added must
  stay in the existing terse all-caps HUD idiom (`FIRE`, `WEAPON`, `BOMB`), not full sentences.

---

## Task 1: Fix the web shell's portrait-rotate watcher

**Files:**
- Modify: `web/vr_shell.html:407-427` (the M4a touch-mode IIFE) and `web/vr_shell.html:445-456`
  (the capability card's "LET ME TRY ANYWAY" button handler)

**Interfaces:**
- Produces: `window.vrArmPortraitWatch()` — a global function, safe to call more than once
  (idempotent), that wires the portrait-rotate card to `resize`/`orientationchange` and runs an
  immediate check.

This file is plain HTML/JS and is **not** part of the jcodemunch code index for this repo (it has
no GDScript symbols) — read it directly with the `Read` tool rather than searching for symbols.

**The bug:** `window.vrTouchMode` starts `false` on every load except when the URL already has
`?touch=1`. The IIFE at line 409 checks `if (!window.vrTouchMode) { return; }` and exits before
ever attaching the resize/orientationchange listeners. Later, if a phone visitor clicks
**LET ME TRY ANYWAY** on the capability card (around line 447), that handler sets
`window.vrTouchMode = true` — but the IIFE that would have wired the watcher already ran and
returned minutes/seconds earlier. The rotate card can never appear for anyone who reaches touch
mode through that button, which today is the *only* way most phones reach it (`?touch=1` is a
manual URL flag for this development spike).

- [ ] **Step 1: Read the current file to get exact line numbers and confirm nothing else changed underneath this plan**

Read `web/vr_shell.html` around lines 395-460 (the block already quoted in this plan's research —
confirm it still matches before editing).

- [ ] **Step 2: Replace the IIFE with an idempotent, callable watcher**

Replace this block (currently lines 407-427):

```javascript
		// M4a: ?touch=1 opts a device into the touch build being measured. Until the
		// spike passes, the default phone experience is still the capability card.
		(function () {
			window.vrTouchMode = /[?&]touch=1\b/.test(window.location.search);
			if (!window.vrTouchMode) { return; }
			// landscape is not optional: portrait renders the cockpit unusably small
			var rot = document.getElementById('vr-rotate');
			function sync() {
				var portrait = window.innerHeight > window.innerWidth;
				if (rot) { rot.style.display = portrait ? 'flex' : 'none'; }
			}
			window.addEventListener('resize', sync);
			window.addEventListener('orientationchange', sync);
			sync();
			// best-effort lock; Safari refuses it outside fullscreen, hence the prompt
			try {
				if (screen.orientation && screen.orientation.lock) {
					screen.orientation.lock('landscape').catch(function () {});
				}
			} catch (e) { /* unsupported — the prompt covers it */ }
		}());
```

with:

```javascript
		// M4a: ?touch=1 opts a device into the touch build being measured. Until the
		// spike passes, the default phone experience is still the capability card.
		//
		// M4b fix: touch mode can also turn on LATER, when a phone visitor clicks LET ME
		// TRY ANYWAY on the capability card below. The watcher used to be a plain IIFE
		// that only wired itself up if vrTouchMode was already true at page load, so that
		// later path never armed the rotate card. It's now a named, idempotent function
		// callable from both places.
		window.vrTouchMode = /[?&]touch=1\b/.test(window.location.search);
		(function () {
			var armed = false;
			window.vrArmPortraitWatch = function () {
				if (armed) { return; }
				armed = true;
				// landscape is not optional: portrait renders the cockpit unusably small
				var rot = document.getElementById('vr-rotate');
				function sync() {
					var portrait = window.innerHeight > window.innerWidth;
					if (rot) { rot.style.display = portrait ? 'flex' : 'none'; }
				}
				window.addEventListener('resize', sync);
				window.addEventListener('orientationchange', sync);
				sync();
				// best-effort lock; Safari refuses it outside fullscreen, hence the prompt
				try {
					if (screen.orientation && screen.orientation.lock) {
						screen.orientation.lock('landscape').catch(function () {});
					}
				} catch (e) { /* unsupported — the prompt covers it */ }
			};
			if (window.vrTouchMode) { window.vrArmPortraitWatch(); }
		}());
```

- [ ] **Step 3: Arm the watcher from the capability card's button too**

Find the "LET ME TRY ANYWAY" click handler (currently around lines 445-456):

```javascript
			var btn = document.getElementById('vr-gate-anyway');
			if (btn) {
				btn.addEventListener('click', function () {
					gate.style.display = 'none';
					window.vrGated = false;
					// the card is shown because there are no controls, so anyone who
					// insists gets the touch build rather than an unplayable one
					window.vrTouchMode = true;
					if (load) { load.style.display = 'flex'; }
					if (window.vrStartEngine) { window.vrStartEngine(); }
				});
			}
```

Add one line so it re-checks orientation the moment touch mode turns on:

```javascript
			var btn = document.getElementById('vr-gate-anyway');
			if (btn) {
				btn.addEventListener('click', function () {
					gate.style.display = 'none';
					window.vrGated = false;
					// the card is shown because there are no controls, so anyone who
					// insists gets the touch build rather than an unplayable one
					window.vrTouchMode = true;
					if (window.vrArmPortraitWatch) { window.vrArmPortraitWatch(); }
					if (load) { load.style.display = 'flex'; }
					if (window.vrStartEngine) { window.vrStartEngine(); }
				});
			}
```

- [ ] **Step 4: Manually verify in a browser dev-tools device-emulation portrait phone view**

Open `web/vr_shell.html` is not directly openable (it's a Godot export template, not a standalone
page) — this step is folded into Task 5's web-export gate, where the exported `dist/index.html`
(built from this shell) is served locally and checked in a portrait-emulated phone viewport both
via `?touch=1` in the URL AND via clicking LET ME TRY ANYWAY on a spoofed-phone user agent. Do not
skip re-verifying this step at Task 5 — it's the only point in this plan where the fix is actually
exercised end-to-end.

- [ ] **Step 5: Commit**

```bash
git add web/vr_shell.html
git commit -m "fix(web): arm the portrait-rotate watcher from both touch-mode entry points"
```

---

## Task 2: Player steering reads magnitude, not just on/off

**Files:**
- Modify: `scripts/player.gd:126-141` (top of `update_flight`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `update_flight()`'s steering now scales by `Input.get_action_strength(...)` instead of
  gating on `Input.is_action_pressed(...)`. This is the seam Task 3's floating stick relies on —
  it will call `Input.action_press("steer_left", magnitude)` with `magnitude` in `(0.0, 1.0]`, and
  this task is what makes that magnitude actually change the turn rate instead of being treated as
  a plain boolean.

Godot's `Input.action_press(action, strength)` already supports a strength argument (default
`1.0`); `Input.is_action_pressed` only checks "is strength above the analog deadzone", discarding
the magnitude. Switching to `Input.get_action_strength` is the whole fix, and it doesn't change
keyboard behavior at all: a physically held key always reports strength `1.0`. The gamepad path a
few lines below already reads `Input.get_joy_axis` directly and bypasses the action system
entirely, so it's untouched.

- [ ] **Step 1: Read the current function to confirm line numbers**

Read `scripts/player.gd` lines 126-145.

- [ ] **Step 2: Replace the four boolean steering checks**

Replace:

```gdscript
	if Input.is_action_pressed("steer_left"):
		yaw += ts
		_turn_sm += ts * 0.6
	if Input.is_action_pressed("steer_right"):
		yaw -= ts
		_turn_sm -= ts * 0.6
	# M2.2: invert-Y applies to the pitch axis wholesale, keys as well as mouse
	var kb_inv := -1.0 if GameState.invert_y else 1.0
	if Input.is_action_pressed("steer_up"):
		pitch = clampf(pitch + ps * kb_inv, -PITCH_LIMIT, PITCH_LIMIT)
	if Input.is_action_pressed("steer_down"):
		pitch = clampf(pitch - ps * kb_inv, -PITCH_LIMIT, PITCH_LIMIT)
```

with:

```gdscript
	# M4b: strength, not a plain boolean — a held key always reports 1.0 so this is a
	# no-op for keyboard, but it's what lets a touch joystick report a proportional
	# turn rate through this exact same path instead of a separate tuning curve.
	var sl := Input.get_action_strength("steer_left")
	var sr := Input.get_action_strength("steer_right")
	if sl > 0.0:
		yaw += ts * sl
		_turn_sm += ts * 0.6 * sl
	if sr > 0.0:
		yaw -= ts * sr
		_turn_sm -= ts * 0.6 * sr
	# M2.2: invert-Y applies to the pitch axis wholesale, keys as well as mouse
	var kb_inv := -1.0 if GameState.invert_y else 1.0
	var su := Input.get_action_strength("steer_up")
	var sd := Input.get_action_strength("steer_down")
	if su > 0.0:
		pitch = clampf(pitch + ps * kb_inv * su, -PITCH_LIMIT, PITCH_LIMIT)
	if sd > 0.0:
		pitch = clampf(pitch - ps * kb_inv * sd, -PITCH_LIMIT, PITCH_LIMIT)
```

- [ ] **Step 3: Headless compile/boot check**

Run: `godot --headless --path void-runner-godot --import` then
`godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600`

Expected: no new `SCRIPT ERROR` lines versus the pre-change baseline (the smoke test doesn't yet
assert anything about strength — Task 5 adds that — this step is only confirming nothing broke).

- [ ] **Step 4: Commit**

```bash
git add scripts/player.gd
git commit -m "refactor(player): steering reads action strength for proportional touch input"
```

---

## Task 3: Touch layer rewrite — zone dispatch, floating stick, boost double-tap, buttons, lifecycle

**Files:**
- Modify: `scripts/touch_controls.gd` (full rewrite; the class stays a `CanvasLayer` named
  `TouchControls`)

**Interfaces:**
- Consumes: `Input.action_press(action: StringName, strength: float)` /
  `Input.action_release(action: StringName)` (Godot built-ins), `GameState.energy` (read, to
  auto-cancel boost on depletion). `player.apply_mouse_look` is **no longer called from here** —
  that was the old relative-drag path and this task replaces it.
- Produces: `enable(p: PlayerShip) -> void` (signature unchanged), `set_flight_active(flag: bool)
  -> void` (new — Task 4's game.gd wiring calls this every frame), `visible`/`active` (existing
  properties, now driven by `set_flight_active` instead of only `enable`), signals
  `fire_held(down: bool)` (unchanged, still connected in game.gd), `weapon_tapped` and
  `bomb_tapped` (new — Task 4 connects both to existing game.gd handlers).

This task covers everything the build-order table calls M4b-2 through M4b-4 (zone dispatch, the
floating stick, boost double-tap, the resized/repositioned buttons, idle fade, press states, and
the activate/deactivate lifecycle) as **one** diff against this one file rather than several,
because the pieces share state too tightly to review as independent slices — `_process`'s idle-fade
and press-state block reads the same touch indices the dispatch logic sets, `_release_all` has to
know about boost and the stick together or it leaks stuck input, and `_set_boost` recolors a stick
visual that the dispatch code owns. Splitting them into separate commits would just be arbitrary
cut points in one function graph. The self-review in Step 3 below is where each piece gets checked
against the spec individually, before the single commit.

**The zone model:** every touch carries a Godot-assigned `index` for its whole press-drag-release
lifecycle. A touch that lands inside a button rect (right side) is owned by that button until it
lifts. A touch that lands anywhere else in the **left 45%** of the screen becomes the one and only
steering touch until it lifts. A touch that lands outside both (right side, not on a button) is
ignored — this is a deliberate behavior change from the M4a spike, where "anywhere else" on the
whole screen could steer; the spec's whole point is that finger ownership by zone/button is what
lets both thumbs work independently without stealing input from each other.

- [ ] **Step 1: Read the current file in full**

Read `scripts/touch_controls.gd` (125 lines) — confirm it still matches the version this plan was
written against (class doc-comment, `TOUCH_MIN`/`DRAG_GAIN` constants, `_ready`/`_build`/`enable`/
`_in_fire`/`_input`/`_process`).

- [ ] **Step 2: Rewrite the file**

Replace the entire contents of `scripts/touch_controls.gd` with:

```gdscript
extends CanvasLayer
## M4b touch layer: replaces the M4a relative-drag spike with per-finger zone
## ownership and a floating rate-control joystick.
##
## Every touch is owned by exactly one of: a button (FIRE/WEAPON/BOMB, right side)
## or the steering stick (anywhere in the left 45%). No touch can affect both, which
## is what makes "steer while firing" actually work on two thumbs — the M4a spike
## let the whole non-button screen steer, so a thumb reaching for FIRE could yank
## the ship mid-corner.
##
## Lives OUTSIDE the 320x200 SubViewport (like Overlays), but as a CanvasLayer in
## the root viewport it still inherits that viewport's content_scale_mode=canvas_items
## — so button/stick geometry below is sized in 320x200 canvas units, matching
## hud.gd/overlays.gd, NOT real screen pixels (a POST-REVIEW correction; the first
## draft of this file wrongly assumed screen pixels, inherited from the M4a spike's
## own mistaken doc-comment).
class_name TouchControls

signal fire_held(down: bool)
signal weapon_tapped
signal bomb_tapped

## D9: the touch steering stick — radius and dead zone, in 320x200 canvas units.
## POST-REVIEW CORRECTION (Task 3 ruling, 2026-08-22): this CanvasLayer sits in the
## root viewport, which uses content_scale_mode=canvas_items — so get_visible_rect()
## and all Control position/size values here are 320x200 canvas units, identical
## headless and rendered, NOT real screen pixels. Every constant below was
## recomputed for that space (see the ruling in this plan's Task 3 section).
## TOUCH_MIN (Apple/Google's 44-64pt minimum touch target) does not translate into
## this coordinate space at all and was dead code besides — removed.
const STICK_RADIUS := 40.0
const STICK_DEAD_ZONE := 3.0
## Fraction of screen width, from the left edge, that can start a steering touch.
const LEFT_ZONE_FRAC := 0.45
## D10: double-tap window/radius to toggle boost, in seconds / canvas units.
const BOOST_TAP_WINDOW := 0.3
const BOOST_TAP_DIST := 15.0
## Button sizes (diameter, canvas units) per the "Thumbs On Glass" spec, rescaled
## into the 320x200 canvas_items space.
const FIRE_SIZE := 32.0
const SIDE_SIZE := 22.0
## Idle fade: how long with no touch before the layer dims, and to what alpha.
const IDLE_FADE_AFTER := 2.5
const IDLE_ALPHA := 0.35

var player: PlayerShip
var active := false

var _steer_touch := -1        # finger index currently steering, -1 = none
var _fire_touch := -1
var _weapon_touch := -1
var _bomb_touch := -1

var _stick_center := Vector2.ZERO
var _boost_active := false
var _last_tap_time := -999.0
var _last_tap_pos := Vector2.ZERO
var _idle_t := 0.0

var _fps_label: Label
var _fps_accum := 0.0
var _fps_frames := 0
var _worst_frame := 0.0

var _root: Control
var _fire_btn: Panel
var _weapon_btn: Panel
var _bomb_btn: Panel
var _stick_ring: Panel
var _stick_knob: Panel


func _ready() -> void:
	layer = 12   # above the HUD, below the overlays (10) is wrong — overlays must win
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	visible = false
	set_process(false)
	set_process_input(false)


func _build() -> void:
	_fire_btn = _make_button(FIRE_SIZE, Vector2(40.0, 28.0), "FIRE",
		Color(1.0, 0.45, 0.2, 0.14), Color(1.0, 0.61, 0.25, 0.7))
	_bomb_btn = _make_button(SIDE_SIZE, Vector2(76.0, 28.0), "BOMB",
		Color(0.55, 0.2, 0.85, 0.14), Color(0.7, 0.4, 1.0, 0.7))
	_weapon_btn = _make_button(SIDE_SIZE, Vector2(62.0, 60.0), "WPN",
		Color(0.2, 0.55, 0.85, 0.14), Color(0.4, 0.75, 1.0, 0.7))
	# floating stick visuals — hidden until a steering touch begins
	_stick_ring = Panel.new()
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(0, 0, 0, 0)
	ring_sb.border_color = Color(1.0, 0.61, 0.25, 0.55)
	ring_sb.set_border_width_all(2)
	ring_sb.set_corner_radius_all(int(STICK_RADIUS))
	_stick_ring.add_theme_stylebox_override("panel", ring_sb)
	_stick_ring.size = Vector2(STICK_RADIUS, STICK_RADIUS) * 2.0
	_stick_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_ring.visible = false
	_root.add_child(_stick_ring)
	_stick_knob = Panel.new()
	var knob_sb := StyleBoxFlat.new()
	knob_sb.bg_color = Color(1.0, 0.75, 0.45, 0.55)
	knob_sb.set_corner_radius_all(int(STICK_KNOB_SIZE * 0.5))
	_stick_knob.add_theme_stylebox_override("panel", knob_sb)
	_stick_knob.size = Vector2(STICK_KNOB_SIZE, STICK_KNOB_SIZE)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.visible = false
	_root.add_child(_stick_knob)
	# framerate readout — the M4a spike's whole purpose, kept for the M4d Android check
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 12)
	_fps_label.add_theme_font_size_override("font_size", 7)
	_fps_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_root.add_child(_fps_label)


## One button, bottom-right-anchored, offset (right, up) canvas units from that
## corner. Used for FIRE/WEAPON/BOMB so the three share one code path.
func _make_button(size: float, offset_from_br: Vector2, text: String,
		fill: Color, border: Color) -> Panel:
	var btn := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size))
	btn.add_theme_stylebox_override("panel", sb)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.size = Vector2(size, size)
	btn.position = Vector2(-offset_from_br.x - size * 0.5, -offset_from_br.y - size * 0.5)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(btn)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 6 if size < FIRE_SIZE else 8)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8))
	# Full-rect + centered alignment, not a hand-tuned position offset: the old
	# `-text.length() * 4.5` heuristic was already an approximation and broke
	# outright at the corrected (smaller) button scale. This is correct for any
	# text/font/button size without ever needing to be re-tuned again.
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(l)
	return btn


func enable(p: PlayerShip) -> void:
	player = p
	set_flight_active(true)


## M4b: called every frame from game.gd with (state == State.PLAYING). Replaces the
## M4a behavior where enable() turned the layer on once and nothing ever turned it
## back off — which is why the fire pad used to paint over the game-over screen and
## every menu.
func set_flight_active(flag: bool) -> void:
	if flag == active:
		return
	active = flag
	visible = flag
	set_process(flag)
	set_process_input(flag)
	if not flag:
		_release_all()


## Releases every action/touch this layer might be holding down. Needed because
## set_process_input(false) means a touch's eventual "up" event is never delivered
## here — without this, pausing mid-turn or mid-boost would leave that input stuck
## pressed for the rest of the run.
func _release_all() -> void:
	if _fire_touch >= 0:
		_fire_touch = -1
		fire_held.emit(false)
	_weapon_touch = -1
	_bomb_touch = -1
	_steer_touch = -1
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	Input.action_release("steer_up")
	Input.action_release("steer_down")
	if _boost_active:
		_set_boost(false)
	_stick_ring.visible = false
	_stick_knob.visible = false


func _set_boost(on: bool) -> void:
	_boost_active = on
	if on:
		Input.action_press("boost")
	else:
		Input.action_release("boost")
	var ring_sb := _stick_ring.get_theme_stylebox("panel") as StyleBoxFlat
	ring_sb.border_color = Color(0.4, 1.0, 0.6, 0.8) if on else Color(1.0, 0.61, 0.25, 0.55)


func _in_rect(btn: Panel, pos: Vector2) -> bool:
	return btn.get_global_rect().has_point(pos)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _steer_touch:
			_update_stick(d.position)


func _on_touch(t: InputEventScreenTouch) -> void:
	_idle_t = 0.0
	if t.pressed:
		if _in_rect(_fire_btn, t.position) and _fire_touch < 0:
			_fire_touch = t.index
			fire_held.emit(true)
		elif _in_rect(_bomb_btn, t.position) and _bomb_touch < 0:
			_bomb_touch = t.index
			bomb_tapped.emit()
		elif _in_rect(_weapon_btn, t.position) and _weapon_touch < 0:
			_weapon_touch = t.index
			weapon_tapped.emit()
		elif t.position.x < get_viewport().get_visible_rect().size.x * LEFT_ZONE_FRAC \
				and _steer_touch < 0:
			_steer_touch = t.index
			_start_stick(t.position)
			_check_boost_tap(t.position)
	else:
		if t.index == _fire_touch:
			_fire_touch = -1
			fire_held.emit(false)
		if t.index == _weapon_touch:
			_weapon_touch = -1
		if t.index == _bomb_touch:
			_bomb_touch = -1
		if t.index == _steer_touch:
			_steer_touch = -1
			_end_stick()


func _check_boost_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time < BOOST_TAP_WINDOW and pos.distance_to(_last_tap_pos) < BOOST_TAP_DIST:
		_set_boost(not _boost_active)
		_last_tap_time = -999.0   # consume — a third rapid tap starts a fresh window
	else:
		_last_tap_time = now
		_last_tap_pos = pos


func _start_stick(pos: Vector2) -> void:
	_stick_center = pos
	_stick_ring.position = pos - _stick_ring.size * 0.5
	_stick_knob.position = pos - _stick_knob.size * 0.5
	_stick_ring.visible = true
	_stick_knob.visible = true


func _update_stick(pos: Vector2) -> void:
	var raw := pos - _stick_center
	var clamped := raw.limit_length(STICK_RADIUS)
	_stick_knob.position = _stick_center + clamped - _stick_knob.size * 0.5
	var dist := clamped.length()
	var mag := 0.0
	if dist > STICK_DEAD_ZONE:
		mag = (dist - STICK_DEAD_ZONE) / (STICK_RADIUS - STICK_DEAD_ZONE)
	var dir := clamped / dist if dist > 0.001 else Vector2.ZERO
	var out := dir * mag   # each component in [-1, 1]; magnitude feeds player.gd's strength read
	if out.x > 0.0:
		Input.action_press("steer_right", out.x)
		Input.action_release("steer_left")
	elif out.x < 0.0:
		Input.action_press("steer_left", -out.x)
		Input.action_release("steer_right")
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
	if out.y < 0.0:
		Input.action_press("steer_up", -out.y)
		Input.action_release("steer_down")
	elif out.y > 0.0:
		Input.action_press("steer_down", out.y)
		Input.action_release("steer_up")
	else:
		Input.action_release("steer_up")
		Input.action_release("steer_down")


func _end_stick() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	Input.action_release("steer_up")
	Input.action_release("steer_down")
	_stick_ring.visible = false
	_stick_knob.visible = false


func _process(delta: float) -> void:
	# boost runs by itself once toggled on — D10 — so it must be checked here even
	# with no finger on the steer zone at all
	if _boost_active and GameState.energy <= 0.0:
		_set_boost(false)
	# idle fade: the layer recedes when nothing has been touched for a couple of
	# seconds, without ever fully hiding — hiding would mean hunting for it again
	_idle_t += delta
	var target_alpha := IDLE_ALPHA if _idle_t > IDLE_FADE_AFTER else 1.0
	_root.modulate.a = move_toward(_root.modulate.a, target_alpha, delta * 2.0)
	# press-state feedback: a held button reads brighter
	_fire_btn.modulate = Color(1.3, 1.3, 1.3) if _fire_touch >= 0 else Color.WHITE
	_bomb_btn.modulate = Color(1.3, 1.3, 1.3) if _bomb_touch >= 0 else Color.WHITE
	_weapon_btn.modulate = Color(1.3, 1.3, 1.3) if _weapon_touch >= 0 else Color.WHITE
	# framerate readout
	_fps_accum += delta
	_fps_frames += 1
	_worst_frame = maxf(_worst_frame, delta)
	if _fps_accum >= 0.5:
		var fps := _fps_frames / _fps_accum
		_fps_label.text = "%d FPS  ·  worst %d ms" % [roundi(fps), roundi(_worst_frame * 1000.0)]
		_fps_label.add_theme_color_override("font_color",
			Color(0.4, 1.0, 0.6) if fps >= 50.0 else Color(1.0, 0.5, 0.3))
		_fps_accum = 0.0
		_fps_frames = 0
		_worst_frame = 0.0
```

- [ ] **Step 3: Self-review the whole rewrite against the spec before committing**

Check the file just written against the spec (`PLAN.md` §M4 / "Thumbs On Glass"), piece by piece:
- `_set_boost` toggles the `boost` action and recolors the stick ring — confirm the ring color
  actually changes visibly (border alpha 0.8 vs 0.55, hue amber→green) rather than a change too
  subtle to read on a phone in daylight.
- `_check_boost_tap` only fires for touches that already passed the left-zone gate in `_on_touch`
  (it's called from inside that branch) — confirm a double-tap on a BUTTON does not also trigger
  boost. (It can't: `_check_boost_tap` is only reachable from the final `elif` branch, which is
  mutually exclusive with the button branches above it.)
- `FIRE_SIZE = 32.0`, `SIDE_SIZE = 22.0`, and the offsets in `_build()` — `(40, 28)` for FIRE,
  `(76, 28)` for BOMB, `(62, 60)` for WEAPON — in the 320x200 canvas: FIRE centers at (280,172) r16,
  bounds x[264,296] y[156,188]; BOMB centers at (244,172) r11, bounds x[233,255] y[161,183]; WEAPON
  centers at (258,140) r11, bounds x[247,269] y[129,151]. Pairwise center-distance clears
  sum-of-radii for all three pairs (FIRE-BOMB 36 vs 27, FIRE-WPN ≈38.8 vs 27, BOMB-WPN ≈34.9 vs 22)
  — no overlap — and all three left edges (264/233/247) clear the `LEFT_ZONE_FRAC` boundary at
  x=144 by 120/89/103 units, so no button can be mistaken for a steering touch. Confirm this
  arithmetic against Task 5's screenshot probe, which renders at the same 320x200 canvas scale.
- `_release_all` covers every piece of state this file can set: fire/weapon/bomb/steer touch
  indices, all four steer actions, boost, and both stick visuals. If a later change adds new held
  state to this file, it must be added here too — leave that as a comment on the review if anything
  is missing today, don't silently patch around it.
- The zone check order in `_on_touch` tests FIRE, then BOMB, then WEAPON, then the left-zone/steer
  branch, each gated on that slot being free (`_fire_touch < 0`, etc.) — confirm a second touch
  landing on an already-owned button is simply dropped (falls through every branch) rather than
  stealing it, and that a button touch can never also satisfy the left-zone branch (the buttons all
  sit in the right-side region past `LEFT_ZONE_FRAC`).

Fix anything this turns up directly in the file before Step 4 — there's no separate commit for it,
this is part of the same diff.

- [ ] **Step 4: Headless compile/boot check**

Run: `godot --headless --path void-runner-godot --check-only --script scripts/touch_controls.gd`
(expect no output / exit 0 — the project's own convention is that this command
false-positives on autoload class names, which `TouchControls` is not, so a clean pass here means
something), then the full boot:
`godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600`

Expected: no new `SCRIPT ERROR`. The smoke test doesn't yet touch-simulate anything (Task 5 adds
that) — this step only confirms the rewrite doesn't break the existing flight-through-level
assertions that already exist in the script (they exercise `player.update_flight` continuously,
which now goes through Task 2's strength-based reads).

- [ ] **Step 5: Commit**

```bash
git add scripts/touch_controls.gd
git commit -m "feat(touch): zone dispatch, floating stick, boost double-tap, resized buttons"
```

---

## Task 4: Wire the new touch layer into game.gd

**Files:**
- Modify: `scripts/game.gd:863` (top of `_process`) and `scripts/game.gd:133-141` (the `_touch_mode`
  setup block)

**Interfaces:**
- Consumes: `TouchControls.set_flight_active(flag: bool)`, `TouchControls.weapon_tapped`,
  `TouchControls.bomb_tapped` (all from Task 3).
- Produces: nothing new for later tasks — this is the last wiring point.

**No dynamic test covers this task's diff.** `_touch_mode` is set from a real web
`JavaScriptBridge.eval` call gated on `OS.has_feature("web")` — headless test runs have neither, so
`game.touch_ui` is always null and the `if _touch_mode:` signal-connection block never executes in
any test in this repo, before or after this task. That's a pre-existing constraint of this
codebase, not something to work around here. The per-frame visibility line (Step 2) sits outside
that gate and *is* exercised every frame by the existing smoke test — but only through the
`touch_ui != null` branch always being false, so it never actually calls `set_flight_active`. Given
that, this task's correctness rests on **careful reading, not a passing test**: the task reviewer
must confirm by inspection that (a) the visibility line in Step 2 is placed before the
`state != State.PLAYING` early return, not after, and reads exactly
`touch_ui.set_flight_active(state == State.PLAYING)`, and (b) the two signal connections in Step 3
call the exact existing handlers `_select_weapon((GameState.weapon_index + 1) % weapons.size())` and
`_fire_plasma_bomb` with no typos, matching the identical expression `_unhandled_input` already uses
for the keyboard/gamepad path. Say so explicitly when dispatching this task's review.

- [ ] **Step 1: Read the current file at both spots to confirm line numbers**

Read `scripts/game.gd` lines 125-145 and lines 860-870.

- [ ] **Step 2: Add the per-frame active/visible poll**

In `_process`, replace:

```gdscript
func _process(delta: float) -> void:
	world.animate(delta)
	if state == State.BRIEFING:
```

with:

```gdscript
func _process(delta: float) -> void:
	world.animate(delta)
	# M4b: touch_ui's own active/visible state used to be set once by enable() and
	# never revisited, so it kept drawing (and accepting input) over the pause menu,
	# game-over screen, and every other non-flight state. This line is the fix — it
	# has to run before the State.PLAYING early-return below, not after.
	if touch_ui != null:
		touch_ui.set_flight_active(state == State.PLAYING)
	if state == State.BRIEFING:
```

- [ ] **Step 3: Connect the new WEAPON/BOMB signals where FIRE is already connected**

Replace:

```gdscript
	if _touch_mode:
		touch_ui = TouchControls.new()
		add_child(touch_ui)
		touch_ui.fire_held.connect(func(down: bool) -> void:
			if down:
				Input.action_press("fire")
			else:
				Input.action_release("fire"))
```

with:

```gdscript
	if _touch_mode:
		touch_ui = TouchControls.new()
		add_child(touch_ui)
		touch_ui.fire_held.connect(func(down: bool) -> void:
			if down:
				Input.action_press("fire")
			else:
				Input.action_release("fire"))
		# M4b: WEAPON/BOMB are one-shot taps, not holds, so they call the same
		# handlers _unhandled_input already uses for the keyboard/gamepad bindings
		# (weapon_cycle / plasma_bomb) rather than simulating an action event.
		touch_ui.weapon_tapped.connect(func() -> void:
			_select_weapon((GameState.weapon_index + 1) % weapons.size()))
		touch_ui.bomb_tapped.connect(_fire_plasma_bomb)
```

(Confirm the exact surrounding indentation/braces against the file read in Step 1 before applying —
GDScript is indentation-sensitive and this block sits inside an existing `if OS.has_feature("web"):`
/ `if _touch_mode:` nest.)

- [ ] **Step 4: Headless compile/boot check**

Run: `godot --headless --path void-runner-godot --import` then
`godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600`

Expected: no new `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/game.gd
git commit -m "feat(game): drive touch layer visibility from flight state, wire WEAPON/BOMB taps"
```

---

## Task 5: Smoke-test coverage and the full ship gate

**Files:**
- Modify: `tests/smoke_test.gd` (new "M4b" section, inserted immediately before the existing
  `print("SMOKE TEST COMPLETE")` line and after the `print("M3 ok — ...")` line — read the file's
  tail first to get the exact surrounding text, since line numbers will have shifted from the
  research in this plan's header after Tasks 1-4 land)

**Interfaces:**
- Consumes: everything from Tasks 2-4 — `Input.get_action_strength`, `TouchControls` (all its new
  methods/signals), `game.touch_ui`.
- Produces: nothing further — this is the plan's final task.

This is where the real test-then-implement cycle for this plan happens, per the note in this
plan's header: the assertions below reference methods that already exist after Task 3, so
"write it, watch it fail" here specifically means *intentionally breaking one assertion first* to
prove the harness is actually checking something (Step 2) before trusting the green run in Step 4.

- [ ] **Step 1: Read the tail of `tests/smoke_test.gd`**

Read the last ~90 lines of `tests/smoke_test.gd` to find the exact current text of the `"M3 ok"`
print line and the `"SMOKE TEST COMPLETE"` print line (this plan's research captured them as of
2026-08-22; confirm nothing else has landed on this file since).

- [ ] **Step 2: Insert the M4b section, then deliberately break one line to prove the harness works**

Insert this block between the `"M3 ok"` print and the `"SMOKE TEST COMPLETE"` print:

```gdscript
	# --- M4b: touch layer — zone dispatch, floating stick, boost double-tap ---
	var touch := TouchControls.new()
	add_child(touch)
	touch.enable(game.player)
	await get_tree().process_frame
	# activation lifecycle: enable() turns it on; set_flight_active(false) must
	# release every held action so a pause mid-input can't leave something stuck
	assert(touch.active)
	assert(touch.visible)
	var vp_w: float = get_viewport().get_visible_rect().size.x
	# a touch in the left zone becomes the steer touch and spawns the stick
	var left_pos := Vector2(vp_w * 0.2, 100.0)
	var t_down := InputEventScreenTouch.new()
	t_down.index = 0
	t_down.position = left_pos
	t_down.pressed = true
	touch._input(t_down)
	assert(touch._steer_touch == 0)
	# a second finger landing on FIRE must NOT steal the steering finger's ownership
	var fire_pos: Vector2 = touch._fire_btn.get_global_rect().get_center()
	var f_down := InputEventScreenTouch.new()
	f_down.index = 1
	f_down.position = fire_pos
	f_down.pressed = true
	touch._input(f_down)
	assert(touch._fire_touch == 1)
	assert(touch._steer_touch == 0)   # unchanged — zone ownership held
	# dragging the steering finger right produces a proportional steer_right strength,
	# and leaves steer_left at zero rather than merely "pressed"
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = left_pos + Vector2(TouchControls.STICK_RADIUS, 0.0)   # full deflection
	touch._input(drag)
	assert(is_equal_approx(Input.get_action_strength("steer_right"), 1.0))
	assert(Input.get_action_strength("steer_left") == 0.0)
	# Task 2 integration: a raw action strength is only half the feature — prove
	# player.gd actually consumes it and turns. steer_right decreases yaw (see
	# player.gd's update_flight), so one physics step at full deflection must move
	# yaw down, not just leave the action flagged.
	var yaw_before: float = game.player.yaw
	game.player.update_flight(0.05)
	assert(game.player.yaw < yaw_before)
	# lifting the fire finger releases only fire, not steering
	var f_up := InputEventScreenTouch.new()
	f_up.index = 1
	f_up.position = fire_pos
	f_up.pressed = false
	touch._input(f_up)
	assert(touch._fire_touch == -1)
	assert(touch._steer_touch == 0)
	# lifting the steering finger releases the steer actions
	var t_up := InputEventScreenTouch.new()
	t_up.index = 0
	t_up.position = left_pos
	t_up.pressed = false
	touch._input(t_up)
	assert(touch._steer_touch == -1)
	assert(Input.get_action_strength("steer_right") == 0.0)
	# D10: a double-tap in the left zone toggles boost on, and it runs to depletion
	# on its own rather than needing the finger held
	var tap_pos := Vector2(vp_w * 0.15, 120.0)
	var tap_a := InputEventScreenTouch.new()
	tap_a.index = 2
	tap_a.position = tap_pos
	tap_a.pressed = true
	touch._input(tap_a)
	var tap_a_up := InputEventScreenTouch.new()
	tap_a_up.index = 2
	tap_a_up.position = tap_pos
	tap_a_up.pressed = false
	touch._input(tap_a_up)
	var tap_b := InputEventScreenTouch.new()
	tap_b.index = 3
	tap_b.position = tap_pos + Vector2(5.0, 5.0)   # well inside BOOST_TAP_DIST
	tap_b.pressed = true
	touch._input(tap_b)   # second tap of the pair — toggles boost on
	assert(touch._boost_active)
	assert(Input.is_action_pressed("boost"))
	GameState.energy = 0.0
	touch._process(0.016)
	assert(not touch._boost_active)          # depletion auto-cancels it
	assert(not Input.is_action_pressed("boost"))
	# set_flight_active(false) must leave nothing pressed — the whole point of M4b-1's
	# "never disabled" fix
	Input.action_press("steer_left", 1.0)
	touch._steer_touch = 5
	touch.set_flight_active(false)
	assert(not touch.visible)
	assert(Input.get_action_strength("steer_left") == 0.0)
	assert(touch._steer_touch == -1)
	touch.queue_free()
	Input.action_release("steer_right")   # belt-and-suspenders: don't leak into later sections
	Input.action_release("steer_left")
	print("M4b ok — zone ownership holds under a second finger, stick strength is proportional, "
		+ "boost double-tap toggles and self-depletes, deactivation releases everything")
```

Now temporarily change the `is_equal_approx(Input.get_action_strength("steer_right"), 1.0)`
assertion's expected value to `0.5` and run the test (Step 3) to confirm it actually fails, proving
this isn't a vacuously-true assertion — then change it back to `1.0` before Step 4.

- [ ] **Step 3: Run with the deliberately-wrong value and confirm failure**

Run: `godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600`

Expected: `Assertion failed` pointing at the `steer_right` strength line, script exits non-zero.
This proves the harness is exercising real behavior, not a tautology.

- [ ] **Step 4: Revert the deliberate break, run again, expect green**

Run: `godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600`

Expected: `M4b ok — ...` printed, `SMOKE TEST COMPLETE` printed, exit 0, zero `SCRIPT ERROR` lines
anywhere in the log.

- [ ] **Step 5: Full project gate, matching every prior session's ship checklist**

Run in order:
1. `godot --headless --path void-runner-godot --import` — expect clean, no errors.
2. `godot --headless --path void-runner-godot tests/smoke_test.tscn --quit-after 600` — expect the
   green run from Step 4 again (confirms nothing Step 5's later commands touch broke it).
3. `godot --headless --path void-runner-godot tests/screenshot_probe.tscn --quit-after 600` —
   capture frames; eyeball the corridor/arena frames for the new FIRE/WEAPON/BOMB button layout and
   the stick ring (it will be hidden/idle in a static screenshot since nothing is touching it, so
   confirm only that the buttons render at their new size/position without overlapping and that
   nothing else regressed).
4. Web export: run the project's normal local export step (same command prior sessions used —
   check `build.sh`/`stamp_build.sh` for the exact invocation) to `dist/`, then serve `dist/`
   locally (e.g. `python3 -m http.server 8765` from `dist/`) and open
   `http://localhost:8765/?touch=1` in a real mobile browser or a portrait-emulated desktop
   browser dev-tools viewport. Confirm: the rotate card now appears in portrait and disappears in
   landscape (Task 1's fix); FIRE/BOMB/WPN are visibly smaller and in the new position; dragging in
   the left 45% shows the floating stick appear at the touch point; double-tapping there toggles a
   visible ring-color change; touching FIRE while dragging the stick does not interrupt steering.
5. Confirm `git log --oneline` shows all 5-6 commits from this plan's tasks in order, working tree
   clean.

- [ ] **Step 6: Update the project's own tracking docs**

This project logs every session in `../../../../CLAUDE.md` §6 and keeps a rolling status line in
`../../../../PLAN.md` (the table row that currently reads "S3 = M4a spike DONE ... Next: S4 = M4b
..."). Append a dated `CLAUDE.md` §6 entry summarizing what shipped (mirror the style of the most
recent entries already there — commit hashes, gate results, what's next), and update that `PLAN.md`
status line to point at M4c as the next step. Do not invent new structure for these docs — match
the existing format exactly.

- [ ] **Step 7: Final commit for the test coverage (docs commit can ride along or be separate, match whichever the user prefers when this task executes)**

```bash
git add tests/smoke_test.gd
git commit -m "test: M4b zone-dispatch, floating stick, and boost double-tap coverage"
```
