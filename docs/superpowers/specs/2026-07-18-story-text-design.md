# Story Text + Briefing Layout Fix — Design

**Date:** 2026-07-18 · **Branch:** `v2.2-fun-pass` (extends the un-merged V2.2 Fun Pass; John
playtests everything together) · **Approved by:** John (chat, 2026-07-18)

## Problem

1. **Bug:** the briefing screen's `Objective` label was built as one line at y=60 with `Body`
   fixed at y=76. V2.2 grew the objective to 2–3 lines (SECONDARY: fuel cells; OPTIONAL: supply
   caches on spur levels), so objective text now overlaps the body paragraph (John's screenshot).
2. **Feature:** the load waits (web boot + entering a sector, where WebGL shader compilation
   blocks under the loading overlay) show only a spinner. John wants compelling sci-fi story text
   there — something to read while it loads — plus a story presence on the briefing itself.

## Decisions (made with John)

- Story lives in **both** places: rotating short "transmission" lines on the web loading overlay,
  and a story paragraph per level on the briefing screen.
- Tone: **pulpy 90s action** — terse mission-log style, matching the DOS aesthetic.
  Child-friendly, fully original (constraint §4: never "Radix", no original assets/text).
- Content architecture: **Approach 1 — a dedicated lore module** (`scripts/lore.gd`), not
  LevelDef .tres fields (avoids multiline prose in 9 .tres files) and not shell-hardcoded JS
  (level-agnostic, desktop gets nothing).

## Story arc (canon for all copy)

The Rift tears open near **Starlight Station**; a machine swarm — **the Hive** — pours through.
You are the last **VOID RUNNER** pilot. Sectors 1–2: outer tunnels fall, fight to the first
signature. 3/6/9 are signature-class guardians (existing boss names stay authoritative).
Sectors 4–5: deeper into occupied territory. 7–8: the cold approach to the Rift mouth.
Sector 9: shut the Rift. Gauntlet: an endless training/echo run, framed as "the Void remembers."

## Components

### 1. `scripts/lore.gd` (new, static data + accessors)

- `story(level_index: int) -> String` — 2–3 sentence briefing paragraph per campaign level;
  a gauntlet variant; safe fallback ("" never crashes) for out-of-range.
- `load_lines(level_index: int) -> PackedStringArray` — 3–4 short overlay transmission lines
  per level (≤ ~48 chars each; they render in the HTML shell at small size).
- `boot_lines() -> PackedStringArray` — generic cold-open lines for the initial page load.

### 2. Briefing layout fix + story paragraph (`scripts/overlays.gd`)

`_build_briefing` re-lays the panel (320×200 design space; `_line` labels are 2×-size,
0.5-scale — keep that idiom):

- Title (unchanged, top).
- **Story** label (new): y≈44, dim color (existing TEXT_COL dimmed or the Record blue
  `5fb6d8`), autowrap, centered, box ending above the objective.
- **Objective** label: becomes a proper multi-line label (autowrap or explicit newlines kept),
  positioned y≈96 with room for 3 lines.
- **Body** (`level.briefing`, the tactical one-liner): y≈132, box ends above the buttons (y=164).
- Worst case verified: 3 objective lines + 2 body lines + 3 story lines on a spur level fit
  with no overlap.
- `set_briefing` sets `Story.text = Lore.story(GameState.level_index)` (gauntlet variant when
  `GameState.gauntlet_mode`).

### 3. Loading-overlay transmissions (web shell + bridge)

- `web/vr_shell.html`: the loading overlay gains a fixed-height text region below the spinner.
  `vrShowLoading(linesJson)` (argument optional — no-arg keeps current behavior) builds one
  absolutely-stacked `<div>` per line and starts a **pure-CSS keyframe crossfade** cycle
  (~3.5 s per line, opacity-only, infinite loop). CSS animations are compositor-driven, so the
  rotation keeps moving even while the main thread is blocked in synchronous shader compiles —
  that is the entire point. No JS timers.
- `game.gd` (wiring-only, per V2.2 rules): the two existing `vrShowLoading` call sites pass
  `JSON.stringify`-style joined lines — boot → `Lore.boot_lines()`, sector load →
  `Lore.load_lines(level_index)`. Gated behind the existing `OS.has_feature("web")` guard;
  desktop/headless/tests byte-identical.

## Error handling

- Lore accessors return safe fallbacks for any index. Convention: **gauntlet = index -1**
  (callers pass -1 when `GameState.gauntlet_mode`); any other out-of-range index falls back to
  the level-1 entry rather than "".
- Shell: malformed/absent lines argument → overlay shows spinner only (current behavior).
- `$GODOT_*` placeholders in the shell must remain intact (existing export check).

## Testing

- Smoke additions: `Lore.story(i)` non-empty + `Lore.load_lines(i).size() >= 3` for all 9 levels;
  briefing overlap assert — after `set_briefing` on a spur level (max objective lines),
  `story.position.y + story.size.y * story.scale.y <= objective.position.y` and likewise
  objective→body, body bottom ≤ button y.
- Export gate: Web export exit 0, `grep -c '\$GODOT_' dist/index.html` = 0, overlay text region
  present in `dist/index.html`.
- Visual/feel: John's playtest (briefing readability, overlay rotation during a real web load).

## Out of scope

Typewriter effects, per-boss cutscenes, localization, desktop loading screens (desktop loads are
near-instant), story in the level-clear tally.
