# Start screen retro-terminal restyle — design

## Context

John shared a Figma file (`BeyondTheVoid`, node `1:2579`) and a matching PDF
(`BeyondTheVoid.pdf`) mocking up a "shareware BBS boot screen" marketing page
for VOID RUNNER: a scrolling 1440×3278 web layout with a hero, backstory
panel, feature cards, testimonials, pricing tiers, and a `C:BEYOND_VOID>
RUN.EXE` terminal-prompt CTA.

The ask: bring that retro-terminal visual language into the actual game,
with the click-to-launch CTA wired to really start the game — not build a
separate marketing site.

## Decision: no separate landing page, no Figma round-trip

The in-game start screen (`Overlays._build_start()` in
`void-runner-godot/scripts/overlays.gd`) already renders at the real
constraint: a single **320×200** canvas, built entirely in GDScript
(`_title`/`_line`/`_button`/`_panel` helpers draw everything — no imported
UI graphics, no scrolling). The Figma page is a tall multi-section desktop
site; nothing from it ports 1:1. Figma's design-to-code pipeline also only
emits React/Tailwind, which has no path into a Godot project.

So this is a **restyle of `_build_start`**, using the Figma screenshot/PDF
purely as a visual/copy reference (palette, `[ LABEL.SYS ]` bracket-box
chrome, terminal voice), scoped to what fits a single 320×200 screen:
**hero + backstory + terminal-prompt CTA**. Testimonials, pricing, media
sensors, and config diagnostics are marketing-only content with no in-game
equivalent and are dropped.

The launch mechanic needs no new wiring: the existing `> START` button
already calls `AudioSys.unlock()` and emits `launch_requested`, which
`game.gd` uses to boot the level. The CTA is a re-skin of that button, not
new logic.

## Design

### 1. New helper: bracket-box panel

Add `_box(p: Control, rect: Rect2, color: Color, label: String) -> Panel`
to `overlays.gd`, alongside the existing `_title`/`_line`/`_at`/`_button`
widget helpers. Draws a thin colored border (`StyleBoxFlat` with
`border_width_*` set, `bg_color` transparent, on a `Panel`) and a
`[ LABEL ]` header `Label` positioned in the box's top-left corner, in the
given color. This is the one new visual primitive; everything else below
reuses existing helpers.

### 2. Hero rework

In `_build_start`, replace the single-line title with two stacked lines:
`"BEYOND THE"` / `"VOID RUNNER"` (was one line, `"VOID RUNNER"`), using
`_title` at the existing size/`TITLE_COL`. Add a tagline line below it,
`"RUN. SURVIVE. ESCAPE THE VOID."`, then keep the existing
`"9-LEVEL CAMPAIGN · SECTOR RUN"` and high-score lines unchanged beneath
that. Vertical positions shift down slightly to make room; exact `y`
offsets are an implementation detail for the plan/execution step, not
fixed here.

### 3. Backstory panel

Replace the four flat flavor lines (`"Your fighter runs the labyrinth..."`
etc.) with one `_box` titled `[ SYSTEM_BACKSTORY.DAT ]` (green border,
`TITLE_COL`), containing:
- One line of in-fiction backstory, reusing existing lore copy rather than
  new invented text: `Lore._STORIES[0]` — *"The Rift tore open at 0400.
  Starlight's outer ring went dark in minutes. You are the last Void
  Runner on the board."* (wrapped/trimmed to fit the box width at font
  size 8; `Lore.story()` is `static` and already used elsewhere as the
  reference way to pull sector copy, so call it the same way here rather
  than reaching into the private constant directly).
- A second short line: `"TERMINAL STATUS: CRITICAL"` in `KEY_COL` (amber),
  echoing the Figma design's status chip.

### 4. Terminal-prompt CTA

Restyle the existing `> START` button in place: same position, same
`on_press` callback (`AudioSys.unlock()` + `launch_requested.emit()`), but
wrapped in a `_box` (green border) and relabeled `"C:VOID_RUNNER>
RUN.EXE"`. No behavior change — this is the button skin only.

### 5. Unchanged

- Sector `< >` selector and its label: unchanged, unmoved except for the
  vertical shift from the hero rework.
- `CONTROLS` / `SETTINGS` / `GAUNTLET` buttons: same signals/behavior,
  recolored to reflect the green/orange/cyan role-coding from the Figma
  palette (was uniformly `TEXT_COL`/`KEY_COL`).
- Every other overlay (`help`, `briefing`, `pause`, `game_over`,
  `level_clear`, `victory`, `settings`, `bay`) is untouched.

### Out of scope

Top BIOS chrome bar (`VOID_BIOS v4.01 ...`), media-sensor screenshot
cards, BBS testimonials, pricing tiers, and the config.sys diagnostics
block — all pure marketing content from the Figma page with no in-game
equivalent, confirmed out of scope with John during brainstorming.

## Testing

Godot has no automated UI-pixel test in this project; verification is the
existing pattern used throughout this codebase's session log: headless
`--import` clean, `game.tscn` boots headless with zero errors, then a
manual/visual check (screenshot probe or a served web export) of the start
screen specifically. No new automated test is proposed — this is a visual
restyle of an existing, already-tested interaction path (`launch_requested`
→ `game.gd`), not new game logic.
