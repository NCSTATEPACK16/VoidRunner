# Step 7 device pass (web)

The real-device check the re-audit (`docs/revamp/2026-09-28-m5-m9-reaudit.md` §4 Step 7) asks
for before Step 8 (landing page, `/play`, PWA). It covers the **web build** in each browser. The
native iOS app has its own list in `docs/ios/TESTFLIGHT.md` §5, which uses the same overlay.

## Before you start

- **Open the diagnostics overlay.** Any of these works:
  - Go to `https://beyondthevoidrunner.netlify.app/?diag=1`. It's the easiest way on a phone.
  - **Hold the build number** (bottom-left of the title screen or the pause menu) for one
    second.
  - Press **Shift+F3** on a keyboard.
- **Know the seven rows:**

  | Row | Meaning |
  |---|---|
  | `FPS · AVG · WORST` | Frames per second, average and worst frame time over the last second |
  | `DRAWS · OBJS` | Draw calls and objects in the game view this frame |
  | `BAKE · GPU · PRE` | Boot sprite-sheet time. `PRE Y` = loaded from the prebaked sheets (expected) |
  | `BOSS · OBJ` | The boss and objects sheets, filled in when a level first needs them |
  | `FLIGHT` | Seconds from page load to the first controllable frame |
  | renderer · driver | `gl_compatibility` and the WebGL/OpenGL version string |
  | `GPU` | The unmasked GPU name (Safari often just says "Apple GPU"; Chrome gives an ANGLE string) |

- **Get the full report from a desktop.** Open the browser console and run `vrReport()`. Paste
  the output under the device's table. It includes all of the above plus `contextLost`.
- **Reaching L8 and L9.** There's no level skip. Use **SECTOR** on the title if those sectors
  are unlocked on that device. If they aren't, measure the furthest sector you can reach and use
  the **L3 boss** for the boss rows. Write down which one you used.
- **Baselines** (SwiftShader software GL in headless Chromium, so a slow floor, not a target):
  - boot bake about 50–110 ms prebaked;
  - first flight about 20 s;
  - for desktop GL numbers, see `tests/perf_baseline.md`.

## Pass thresholds

| Measure | Pass |
|---|---|
| FPS in the L8 dense arena and at the L9 boss | Average ≥ 50 and WORST ≤ 50 ms for most of the fight. A single spike as the boss appears is fine |
| FLIGHT (first launch, cold cache) | ≤ 30 s on a phone, and ≤ 15 s on a desktop with a real GPU |
| BAKE | `PRE Y`, under 500 ms |
| Shimmer | See the method below |

**Shimmer method.** Fly into an arena, stop near one wall with the brake, and look at an enemy
or pickup across the room (60 m or more away) for 10 seconds without moving.
- **Pass:** the sprite stays recognisably the same shape.
- **Fail:** it visibly crawls or flickers between two looks as it turns or bobs.

## Per-device table

Copy this table once for each device: iPad (Safari), iPhone (Safari), a mid-range Android
(Chrome), desktop Chrome, desktop Firefox and desktop Safari. Put the device model and OS
version above it.

| # | Check | Expected | Result | Notes |
|---|---|---|---|---|
| 1 | Title-up time (tap the page to the title over the flythrough) | Loading rotates story lines, no frozen screen | | |
| 2 | FLIGHT row on the first launch | Under the threshold | | |
| 3 | BAKE row | `PRE Y`, under 500 ms | | |
| 4 | BOSS row at the first boss level | A number appears; no long freeze entering the boss room | | |
| 5 | FPS / WORST in the L8 dense arena | Pass threshold | | |
| 6 | FPS / WORST at the L9 boss (or the L3 boss) | Pass threshold | | |
| 7 | DRAWS / OBJS at the same two spots | Record them (no threshold yet) | | |
| 8 | Fog-distance shimmer | Pass (method above) | | |
| 9 | Touch on the PRESS START title (phones, tablets) | Tapping starts; the touch layout appears in flight | | |
| 10 | Audio starts after the first touch or key press | Music and SFX, no silent run | | |
| 11 | Switch tab or app mid-flight, then come back | The run is paused and waits for RESUME | | |
| 12 | Close the tab mid-sector after a cleared bulkhead, reopen | CONTINUE resumes at that bulkhead | | |
| 13 | Lost-context recovery (below) | SIGNAL LOST → tap → reload → CONTINUE works | | |
| 14 | SETUP: REDUCE FLASH and REDUCE ROLL on | Plasma white-out dimmed, warnings steady, banking damped | | |
| 15 | The overlay off again (long-press, Shift+F3) | It hides; nothing else changes | | |

**Lost-context recovery.**
- **Desktop Chrome:** in DevTools → Console, run
  `document.getElementById('canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext()`.
- **iPhone:** it happens on its own under memory pressure. If it does, note when.

## What a failure means

**These block Step 8:**
- FPS fails on any phone or tablet;
- row 12 (CONTINUE) or row 13 (lost-context recovery) fails;
- the game doesn't start on any listed browser.

**These only queue work:**
- **Shimmer fails:** queue a lower-resolution sprite set for distant enemies (re-audit Step 7).
- **BAKE over 500 ms or `PRE N`:** queue a bake-budget item. `PRE N` also means the prebaked
  sheets didn't load, which is a bug.
- **FLIGHT over the threshold:** queue a boot-time item for Step 8, which moves the game to
  `/play/` anyway.

## Report back

For each device: the table, the `vrReport()` paste (desktop only), and anything strange. Then
update the Step 7 row in the re-audit's progress table.
