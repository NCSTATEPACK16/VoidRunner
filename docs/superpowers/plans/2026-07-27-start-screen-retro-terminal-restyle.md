# Start Screen Retro-Terminal Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the in-game start screen (`Overlays._build_start()`) with the
retro-terminal / BBS-shareware visual language from the `BeyondTheVoid` Figma
design and PDF, scoped to what fits the game's real 320×200 single-screen
constraint: a two-line hero, a bracket-boxed backstory panel, and a
terminal-prompt launch CTA — with no changes to the actual launch mechanic.

**Architecture:** All changes are additive/in-place edits to one file,
`void-runner-godot/scripts/overlays.gd`, plus one new capture step in the
existing rendered screenshot probe. One new widget helper (`_box`, a bordered
"bracket panel" with a `[ LABEL ]` header) is added alongside the existing
`_title`/`_line`/`_at`/`_button` helpers and reused by both the backstory
panel and the CTA. No new nodes, scenes, signals, or autoloads.

**Tech Stack:** Godot 4.7.stable, GDScript. Run via the `godot` shell alias
(`/Applications/Godot.app/Contents/MacOS/Godot`). All commands below assume
the working directory is `void-runner-godot/` (where `project.godot` lives).

## Global Constraints

- Design/render resolution for all overlays is fixed at **320×200**, single
  screen, no scrolling (`overlays.gd:3` comment; confirmed via Phase I4).
- No original Radix assets, names, or copy — "VOID RUNNER" only, never
  "Radix," in any in-game text (project non-negotiable #3).
- The launch mechanic is not new logic: reuse the existing
  `AudioSys.unlock()` + `launch_requested.emit()` pair exactly as
  `_build_start`'s current `> START` button already calls them
  (`overlays.gd:207-209`). The CTA task only changes the button's label and
  visual chrome, never its `on_press` callable.
- Backstory copy must reuse `Lore.story(0)` for the in-fiction line rather
  than inventing new lore (per `lore.gd`'s stated contract: it is the single
  source of narrative text so campaign copy reads as one voice).
- No automated pixel/UI test framework exists in this project. The
  acceptance bar, matching every prior session in this codebase's history,
  is: headless `--import` clean, headless script check clean, the existing
  `tests/smoke_test.tscn` unaffected (this is a UI-only change; it touches
  no gameplay/flight/enemy/scoring code the smoke test exercises), and a
  rendered visual check via `tests/screenshot_probe.tscn`.

---

### Task 1: Add the bracket-box helper and supporting constant/param

**Files:**
- Modify: `void-runner-godot/scripts/overlays.gd:16-18` (add a constant)
- Modify: `void-runner-godot/scripts/overlays.gd:482-491` (`_title`, add optional param)
- Modify: `void-runner-godot/scripts/overlays.gd:521-529` (`_button`, add optional param)
- Modify: `void-runner-godot/scripts/overlays.gd` widget-helpers section (add new `_box` function after `_button`)

**Interfaces:**
- Produces: `_box(p: Control, rect: Rect2, color: Color, label: String) -> Panel`
  — draws a 1px bordered, transparent-fill box at `rect` (design-px
  coordinates, same space as `_line`/`_at`/`_button` calls on the same
  panel), with a `[ LABEL ]` header `Label` in `color` sitting just above
  the box's top-left corner. Later tasks call this for the backstory panel
  and the terminal-prompt CTA.
- Produces: `_title(p, text, font_size, color, y: float = 28) -> Label` —
  same as before but the vertical position is now an optional 5th
  parameter (default 28, matching every existing call site so none of them
  need to change).
- Produces: `_button(p, pos, text, on_press, color: Color = TITLE_COL) -> Button`
  — same as before but font color is now an optional 5th parameter
  (default `TITLE_COL`, matching every existing call site).
- Produces: `ORANGE_COL := Color("ff9c40")` constant, alongside the existing
  `TITLE_COL`/`TEXT_COL`/`KEY_COL`.
- Consumes: nothing new — only `Control`, `Panel`, `StyleBoxFlat`, `Label`,
  `Color`, `Rect2`, all core Godot types already used elsewhere in this file.

- [ ] **Step 1: Add the `ORANGE_COL` constant**

  In `overlays.gd`, right after the existing color constants:

  ```gdscript
  const TITLE_COL := Color("62ffd0")
  const TEXT_COL := Color("8fb8cc")
  const KEY_COL := Color("ffd34d")
  const ORANGE_COL := Color("ff9c40")
  ```

- [ ] **Step 2: Give `_title` an optional `y` parameter**

  Change:

  ```gdscript
  func _title(p: Control, text: String, font_size: int, color: Color) -> Label:
  	var l := Label.new()
  	l.text = text
  	l.position = Vector2(0, 28)
  ```

  to:

  ```gdscript
  func _title(p: Control, text: String, font_size: int, color: Color, y: float = 28) -> Label:
  	var l := Label.new()
  	l.text = text
  	l.position = Vector2(0, y)
  ```

  (Rest of the function body is unchanged.)

- [ ] **Step 3: Give `_button` an optional `color` parameter**

  Change:

  ```gdscript
  func _button(p: Control, pos: Vector2, text: String, on_press: Callable) -> Button:
  	var b := Button.new()
  	b.text = text
  	b.position = pos
  	b.add_theme_font_size_override("font_size", 8)
  	b.add_theme_color_override("font_color", TITLE_COL)
  	b.pressed.connect(on_press)
  	p.add_child(b)
  	return b
  ```

  to:

  ```gdscript
  func _button(p: Control, pos: Vector2, text: String, on_press: Callable, color: Color = TITLE_COL) -> Button:
  	var b := Button.new()
  	b.text = text
  	b.position = pos
  	b.add_theme_font_size_override("font_size", 8)
  	b.add_theme_color_override("font_color", color)
  	b.pressed.connect(on_press)
  	p.add_child(b)
  	return b
  ```

- [ ] **Step 4: Add the `_box` helper**

  Add this new function directly after `_button` (still in the
  `# ---------- widget helpers ----------` section):

  ```gdscript
  func _box(p: Control, rect: Rect2, color: Color, label: String) -> Panel:
  	var b := Panel.new()
  	b.position = rect.position
  	b.size = rect.size
  	var sb := StyleBoxFlat.new()
  	sb.bg_color = Color(0, 0, 0, 0)
  	sb.border_color = color
  	sb.set_border_width_all(1)
  	b.add_theme_stylebox_override("panel", sb)
  	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
  	p.add_child(b)
  	if label != "":
  		var l := Label.new()
  		l.text = "[ %s ]" % label
  		l.position = Vector2(rect.position.x + 4, rect.position.y - 9)
  		l.add_theme_font_size_override("font_size", 7)
  		l.add_theme_color_override("font_color", color)
  		p.add_child(l)
  	return b
  ```

  (`mouse_filter = MOUSE_FILTER_IGNORE` matters: the box sits visually
  behind/around real buttons in later tasks, and must not intercept their
  clicks.)

- [ ] **Step 5: Headless script check**

  Run: `godot --headless --check-only --script scripts/overlays.gd`
  Expected: no `SCRIPT ERROR` output (the `GameState`/`AudioSys` autoload
  "class not found" lines are a known false-positive for this check —
  ignore those specifically, per this project's established pattern; fail
  on anything else).

- [ ] **Step 6: Headless import + boot check**

  Run: `godot --headless --import`
  Then: `godot --headless tests/smoke_test.tscn`
  Expected: import completes with no errors; smoke test prints
  `SMOKE TEST COMPLETE` (or the project's existing completion marker) with
  no `SCRIPT ERROR` lines — this task changed no gameplay code, so the
  smoke test's behavior must be byte-identical to before this task.

- [ ] **Step 7: Commit**

  ```bash
  git add scripts/overlays.gd
  git commit -m "Add bracket-box widget helper for start-screen restyle

  New _box() helper (bordered panel + [ LABEL ] header) plus optional
  y param on _title and color param on _button, all backward-compatible
  with every existing call site. No behavior change yet."
  ```

---

### Task 2: Hero rework — two-line title + tagline

**Files:**
- Modify: `void-runner-godot/scripts/overlays.gd:207-208` (inside `_build_start`)

**Interfaces:**
- Consumes: `_title(p, text, font_size, color, y)` and `_line(p, y, text, font_size, color)`
  from Task 1/existing code.
- Produces: nothing new — this task only changes what `_build_start` draws
  in its first few lines. Task 3 continues immediately after this task's
  last line.

- [ ] **Step 1: Replace the single-line title and first info line**

  In `_build_start`, change:

  ```gdscript
  	var p := _panel("start")
  	_title(p, "VOID RUNNER", 24, TITLE_COL)
  	_line(p, 58, "9-LEVEL CAMPAIGN · SECTOR RUN", 8, Color("5fb6d8"))
  	_high_label = _line(p, 70, "", 8, KEY_COL)
  ```

  to:

  ```gdscript
  	var p := _panel("start")
  	_title(p, "BEYOND THE", 10, TITLE_COL, 6)
  	_title(p, "VOID RUNNER", 18, TITLE_COL, 18)
  	_line(p, 38, "RUN. SURVIVE. ESCAPE THE VOID.", 7, Color("5fb6d8"))
  	_line(p, 47, "9-LEVEL CAMPAIGN · SECTOR RUN", 7, Color("5fb6d8"))
  	_high_label = _line(p, 56, "", 7, KEY_COL)
  ```

  Leave every line after this (the four flavor lines, sector buttons, etc.)
  in place for now — Task 3 replaces the flavor lines next.

- [ ] **Step 2: Headless script check**

  Run: `godot --headless --check-only --script scripts/overlays.gd`
  Expected: no `SCRIPT ERROR` output (autoload false-positives excepted, as
  in Task 1).

- [ ] **Step 3: Headless boot check**

  Run: `godot --headless tests/smoke_test.tscn`
  Expected: same completion marker as Task 1's Step 6, no `SCRIPT ERROR`.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/overlays.gd
  git commit -m "Restyle start screen hero: two-line title + tagline

  BEYOND THE / VOID RUNNER stacked title plus a tagline, echoing the
  BeyondTheVoid Figma hero, compressed to fit the 320x200 start screen."
  ```

---

### Task 3: Backstory bracket-box panel

**Files:**
- Modify: `void-runner-godot/scripts/overlays.gd` inside `_build_start`
  (the four flavor lines that currently follow the block Task 2 changed:
  originally at `overlays.gd:210-213`, now shifted down two lines by
  Task 2's edit)

**Interfaces:**
- Consumes: `_box(p, rect, color, label)` from Task 1; `Lore.story(level_index: int) -> String`
  (`lore.gd:95`, already used the same way in `set_briefing`,
  `overlays.gd:118-119`); `_line(p, y, text, font_size, color)` (existing).
- Produces: nothing new — continues directly into Task 4, which picks up
  right after this panel's last line.

- [ ] **Step 1: Replace the four flavor lines with the backstory box**

  Find (now at approximately `overlays.gd:212-215`, immediately after
  Task 2's `_high_label` line):

  ```gdscript
  	_line(p, 82, "Your fighter runs the labyrinth at constant burn.", 8, TEXT_COL)
  	_line(p, 92, "Clear tunnels, survive arenas, watch the radar.", 8, TEXT_COL)
  	_line(p, 102, "Cannons build HEAT — redline locks them 3 s.", 8, TEXT_COL)
  	_line(p, 112, "Wall hits drain shields. At zero: hull breach.", 8, TEXT_COL)
  ```

  Replace with:

  ```gdscript
  	_box(p, Rect2(8, 64, 304, 58), TITLE_COL, "SYSTEM_BACKSTORY.DAT")
  	_line(p, 68, "TRANSMISSION LOG — SECTOR ALPHA", 7, KEY_COL)
  	var _story_l := _line(p, 78, Lore.story(0), 7, TEXT_COL)
  	_story_l.position.x = 30
  	_story_l.size = Vector2(260, 24) * 2   # _line labels are 2x-size, 0.5-scale
  	_story_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  	var _flavor_l := _line(p, 98,
  		"You are the last Void Runner on the board — fly the tunnels, or the dark wins.",
  		7, TEXT_COL)
  	_flavor_l.position.x = 30
  	_flavor_l.size = Vector2(260, 24) * 2
  	_flavor_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  	_line(p, 116, "TERMINAL STATUS: CRITICAL", 7, KEY_COL)
  ```

  This mirrors the exact autowrap pattern `_build_briefing` already uses
  for its `Story`/`Body` labels (`overlays.gd:250-251`, `263-266`) — same
  260-design-px band width, same `AUTOWRAP_WORD_SMART` mode.

- [ ] **Step 2: Headless script check**

  Run: `godot --headless --check-only --script scripts/overlays.gd`
  Expected: no `SCRIPT ERROR` output (autoload false-positives excepted).

- [ ] **Step 3: Headless boot check**

  Run: `godot --headless tests/smoke_test.tscn`
  Expected: same completion marker, no `SCRIPT ERROR`.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/overlays.gd
  git commit -m "Add backstory bracket-box panel to start screen

  Replaces the four flat flavor lines with a bordered
  [ SYSTEM_BACKSTORY.DAT ] panel: a transmission-log subheading, the
  Lore.story(0) line, one added connective sentence, and a status chip
  — echoing the Figma page's boot-screen framing without contradicting
  the game's real Rift/Starlight/Hive story."
  ```

---

### Task 4: Terminal-prompt CTA + bottom row reflow/recolor

**Files:**
- Modify: `void-runner-godot/scripts/overlays.gd` inside `_build_start`
  (the sector-selector and button rows that follow Task 3's panel)

**Interfaces:**
- Consumes: `_box(p, rect, color, label)`, `_button(p, pos, text, on_press, color)`
  (both from Task 1); `AudioSys.unlock()` and `launch_requested`/
  `gauntlet_requested` signals (existing, unchanged).
- Produces: nothing new — this is the last edit inside `_build_start`.

- [ ] **Step 1: Reflow the sector row and restyle the bottom buttons**

  Find the remainder of `_build_start` (the sector selector through the
  four bottom buttons):

  ```gdscript
  	_button(p, Vector2(84, 126), "<", func() -> void: _adjust_sector(-1))
  	_sector_label = _line(p, 132, "", 8, KEY_COL)
  	_button(p, Vector2(216, 126), ">", func() -> void: _adjust_sector(1))
  	_button(p, Vector2(88, 152), "> START", func() -> void:
  		AudioSys.unlock()
  		launch_requested.emit())
  	_button(p, Vector2(168, 152), "? CONTROLS", func() -> void: show_only("help"))
  	_button(p, Vector2(70, 174), "* SETTINGS", func() -> void:
  		_settings_return = "start"
  		show_only("settings"))
  	# K5: endless survival mode — the button doubles as the audio-unlock gesture
  	_button(p, Vector2(170, 174), "% GAUNTLET", func() -> void:
  		AudioSys.unlock()
  		gauntlet_requested.emit())
  ```

  Replace with:

  ```gdscript
  	_button(p, Vector2(84, 126), "<", func() -> void: _adjust_sector(-1))
  	_sector_label = _line(p, 132, "", 8, KEY_COL)
  	_button(p, Vector2(216, 126), ">", func() -> void: _adjust_sector(1))
  	_box(p, Rect2(30, 148, 260, 18), TITLE_COL, "TERMINAL_PROMPT.EXE")
  	_button(p, Vector2(38, 150), "C:VOID_RUNNER> RUN.EXE", func() -> void:
  		AudioSys.unlock()
  		launch_requested.emit())
  	_button(p, Vector2(16, 176), "? CONTROLS", func() -> void: show_only("help"),
  		Color("55ffee"))
  	_button(p, Vector2(120, 176), "* SETTINGS", func() -> void:
  		_settings_return = "start"
  		show_only("settings"), ORANGE_COL)
  	# K5: endless survival mode — the button doubles as the audio-unlock gesture
  	_button(p, Vector2(224, 176), "% GAUNTLET", func() -> void:
  		AudioSys.unlock()
  		gauntlet_requested.emit())
  ```

  Notes:
  - The `> START` button's `on_press` body is untouched (still
    `AudioSys.unlock()` + `launch_requested.emit()`) — only its label,
    position, and surrounding box changed.
  - `GAUNTLET` keeps the default `TITLE_COL` (green) — no explicit color
    argument needed, matching the Figma palette's green/orange/cyan
    role-coding (green = primary/freeware-equivalent action, here the
    default gauntlet button; orange = secondary; cyan = tertiary/info,
    here CONTROLS).

- [ ] **Step 2: Headless script check**

  Run: `godot --headless --check-only --script scripts/overlays.gd`
  Expected: no `SCRIPT ERROR` output (autoload false-positives excepted).

- [ ] **Step 3: Headless boot check**

  Run: `godot --headless tests/smoke_test.tscn`
  Expected: same completion marker, no `SCRIPT ERROR`. This step also
  confirms `launch_requested` still fires correctly, since the smoke test
  drives the briefing→launch flow that depends on it.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/overlays.gd
  git commit -m "Restyle start-screen CTA as terminal prompt, recolor bottom row

  > START becomes a boxed C:VOID_RUNNER> RUN.EXE prompt (same on_press
  callback, no logic change). CONTROLS/SETTINGS/GAUNTLET recolored to
  the Figma page's cyan/orange/green role-coding and reflowed onto one
  row to make room for the CTA's own row above it."
  ```

---

### Task 5: Add a start-screen capture to the rendered screenshot probe

**Files:**
- Modify: `void-runner-godot/tests/screenshot_probe.gd:51-111` (`_run`)

**Interfaces:**
- Consumes: `_capture_root(file_name: String, dir: String) -> void`
  (`screenshot_probe.gd:33`, already used for the briefing capture since
  overlays render outside the 320×200 game `SubViewport`); `game.overlays`
  (existing `Overlays` instance on the `game` scene root).
- Produces: `shot_start.png` in the probe's output directory, alongside
  the existing `shot_briefing.png`/`shot_corridor.png`/etc.

- [ ] **Step 1: Capture the start screen before the briefing capture**

  In `_run`, find:

  ```gdscript
  	var game: Node3D = load("res://scenes/game.tscn").instantiate()
  	add_child(game)
  	await get_tree().process_frame
  	await get_tree().process_frame
  	GameState.unlocked_level = 0
  	game.overlays._sector = 0
  	GameState.level_index = 0
  	GameState.score = 0
  	game._show_briefing()
  ```

  Change to:

  ```gdscript
  	var game: Node3D = load("res://scenes/game.tscn").instantiate()
  	add_child(game)
  	await get_tree().process_frame
  	await get_tree().process_frame
  	GameState.unlocked_level = 0
  	game.overlays._sector = 0
  	GameState.level_index = 0
  	GameState.score = 0
  	game.overlays.show_only("start")
  	await _capture_root("shot_start.png", dir)
  	game._show_briefing()
  ```

- [ ] **Step 2: Headless script check**

  Run: `godot --headless --check-only --script tests/screenshot_probe.gd`
  Expected: no `SCRIPT ERROR` output.

- [ ] **Step 3: Run the rendered probe and inspect the new capture**

  Run: `godot tests/screenshot_probe.tscn`
  (Not `--headless` — this probe needs the real rasterizer, per its own
  header comment.)
  Expected: console prints `[shot] .../shot_start.png` among the other
  `[shot]` lines, ending with `SCREENSHOT PROBE COMPLETE`, and the process
  exits on its own (`get_tree().quit()` at the end of `_run`).

  Then open `shot_start.png` (in `user://shots`, or wherever `$VR_SHOT_DIR`
  points if set) and visually confirm, against the layout from Tasks 2–4:
  - The two-line title, tagline, and campaign/high-score lines don't
    overlap each other or run off either edge of the 320×200 frame.
  - The `[ SYSTEM_BACKSTORY.DAT ]` box's header, its four text lines
    (including the two potentially-autowrapped lines), and its border all
    stay inside the box and don't collide with the sector `< >` row above
    the `TERMINAL_PROMPT.EXE` box below.
  - The `C:VOID_RUNNER> RUN.EXE` box and button don't collide with the
    sector row above or the CONTROLS/SETTINGS/GAUNTLET row below.
  - All three bottom buttons (CONTROLS cyan, SETTINGS orange, GAUNTLET
    green) render fully on-screen with visible gaps between them.

  **If anything overlaps or clips:** go back to the relevant step in
  Task 2, 3, or 4 and adjust the affected element's `y` (or the box
  `Rect2`) by 4–8px, re-run this step, and re-inspect. Do not proceed to
  Step 4 until `shot_start.png` shows no overlapping or clipped elements.

- [ ] **Step 4: Headless boot check**

  Run: `godot --headless tests/smoke_test.tscn`
  Expected: same completion marker as every prior task, no `SCRIPT ERROR`
  — confirms the probe change didn't disturb the headless test path.

- [ ] **Step 5: Commit**

  ```bash
  git add tests/screenshot_probe.gd
  git commit -m "Add start-screen capture to the rendered screenshot probe

  shot_start.png lets the retro-terminal restyle be visually verified
  the same way corridor/arena/boss/briefing already are."
  ```

---

### Task 6: Final full verification pass

**Files:** none (verification only)

**Interfaces:** none — this task re-runs everything from Tasks 1–5 together
as a final gate, matching this project's established pre-ship checklist
(headless import → headless smoke → rendered probe → web export).

- [ ] **Step 1: Full headless import + smoke test**

  ```bash
  godot --headless --import
  godot --headless tests/smoke_test.tscn
  ```

  Expected: clean import, smoke test completion marker, no `SCRIPT ERROR`
  anywhere in the output.

- [ ] **Step 2: Rendered screenshot probe, one more time**

  ```bash
  godot tests/screenshot_probe.tscn
  ```

  Expected: `SCREENSHOT PROBE COMPLETE`, and `shot_start.png` still clean
  per Task 5 Step 3's checklist (re-confirm — this run also exercises the
  full briefing/corridor/arena/boss path, so it doubles as a regression
  check that nothing outside the start screen moved).

- [ ] **Step 3: Local web export smoke check (optional but recommended)**

  If you want to see it in a browser before considering this done, export
  and serve exactly as prior sessions in this project's history did:

  ```bash
  godot --headless --export-release "Web" dist/index.html
  cd dist && python3 -m http.server 8765
  ```

  Then open `http://localhost:8765` and click through to the start screen
  to confirm it matches the reviewed `shot_start.png`.

- [ ] **Step 4: Update the project session log**

  Append a dated entry to `/Users/johnbradner/Documents/ClaudeWork/RadixRemix/CLAUDE.md`
  §6 (Session log) summarizing: the Figma/PDF source, the restyle scope
  decision (hero + backstory + terminal-prompt CTA only), and verification
  results — following the exact style of the existing entries in that
  section.

- [ ] **Step 5: Final commit**

  ```bash
  git add /Users/johnbradner/Documents/ClaudeWork/RadixRemix/CLAUDE.md
  git commit -m "Log start-screen retro-terminal restyle session"
  ```
