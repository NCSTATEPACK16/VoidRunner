# Perf baseline log (V2.1 perf pass)

Probe: `tests/perf_probe.tscn`. Headless = CPU/script cost only (dummy
rasterizer — blind to upload/draw/compile stalls). Rendered = real window,
wall-clock frame deltas, spike threshold 40 ms. All runs `VR_PERF_RAIL=1`.

Commands:

```
VR_PERF_RAIL=1 VR_PERF_LEVEL=7    Godot [--headless] --path . tests/perf_probe.tscn   # L8, 210 rings
VR_PERF_RAIL=1 VR_PERF_LEVEL=8    ...                                                 # L9 boss
VR_PERF_RAIL=1 VR_PERF_GAUNTLET=1 ...                                                 # endless
(rendered adds VR_PERF_RENDERED=1 and drops --headless)
```

## Baseline — 2026-07-12, SHA 76b20ff (branch v2.1-perf-sprites), M-series Mac, Godot 4.7

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 6.7 ms | 0 >8 ms | completed ring 203/210 |
| L9 | headless | 1.5 ms | 0 >8 ms | boss killed, level complete |
| Gauntlet | headless | 4.8 ms | 0 >8 ms | streamed to ring 370 |
| L8 | rendered | 210.6 ms | 2 >40 ms | spikes at t=51.0 s (210.6) and t=234.8 s (91.2); `built=` UNCHANGED on both |
| L9 | rendered | 214.2 ms | 2 >40 ms | t=24.3 s (41.2), t=52.0 s (214.2); `built=` unchanged |
| Gauntlet | rendered | 51.2 ms | 1 >40 ms | t=9.5 s (51.2); `built=` unchanged |

Rendered histograms are bimodal (4–6 ms / 10–12 ms — display pacing on this
Mac); full outputs in the session scratchpad (`probe_*_{headless,rendered}.txt`).

## After Step 1 (briefing prebuild, 9e018da)

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 2.5 ms | 0 >8 ms | was 6.7 ms — mid-flight builds gone |
| L8 | rendered | 213.8 ms | 3 >40 ms | **`built=209->209` the whole flight — zero mid-flight builds, gate met.** Spikes uncorrelated with game state; the ~t=51 s big one has now fired at t≈51 s in three separate runs (machine-periodic event, not game work) |

## After Step 2 (gauntlet throttle)

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| Gauntlet | headless ×2 | 51.0 / 49.4 ms | 6 / 6 >8 ms | spike rings DIFFER entirely between runs (58/173/314 vs 79/228/343), `built=` constant on every spike ⇒ OS preemption noise (Spotlight was indexing ~1 k new reference PNGs), not game cost. One-chunk-per-frame cap + drained queues verified by smoke asserts |

**Interpretation.** On desktop GL, no spike coincides with a chunk build
(`built=` never changes on a spike frame); the 40–215 ms one-offs are the same
non-repeating environment-noise class documented 2026-07-05 (desktop has a warm
shader cache and cheap buffer uploads). The mid-flight chunk builds that this
pass removes hurt on **single-threaded WebGL**, which this desktop probe cannot
emulate. Therefore the Step 1/2 gates are:

1. **Architectural (deterministic):** after Step 1, `world._built_up_to` must
   never change while PLAYING a finite level — asserted in the smoke test.
2. **Statistical:** spike counts / histograms here must not regress.
3. **Felt:** John's in-browser test on the web export (the binding platform).

## After Step 4 (HUD dirty-cache draw calls + shared enemy-shot cache)

The cockpit was re-emitting the full canopy + console every frame. Now the
static frame (struts, plates, wells) draws once at boot on its own layer, and
each dynamic layer redraws only when its inputs change — threat lamp/blink,
plasma pips, boss HP bar on the canopy; weapon slots, MISL ammo, EVD lamp, TIME
clock, kills on the console. `shot_manager` fills one `eshot_cache`
(`PackedVector3Array`) + a `threat_near` bool inside its existing enemy-shot
loop (which already touches every shot); the HUD threat lamp and the radar both
read those, replacing the fresh `Array[Vector3]` that `enemy_shot_positions()`
allocated on every radar `_draw`. That method is removed.

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 2.7 ms | 0 >8 ms | completed ring 203/210 — CPU band unchanged vs Step 1 (2.5 ms) |

Headless can't see the win (it measures `game._process` only; HUD `_draw` and
the per-frame canvas draw-call count live on the render thread). Regression bar
met (sim cost flat, no new script errors); a red-green smoke run confirmed the
removed method: reverting the radar to `enemy_shot_positions()` throws
`Nonexistent function … in base 'ShotManager'` at `radar_display.gd:60` every
frame, and the cache fix clears it. The **felt** gate stays John's in-browser
test — fewer canvas draw calls per frame is a single-threaded-WebGL win, the
same class as the Step 1/2 chunk-build removals.

## 3.0 "Technicolor Void" re-baseline (2026-09-28)

Re-run on `main` after PR #6 merged (sector shader, SpriteForge sprites,
STINGER/SPINNER/MINE, time-sliced music). Godot 4.7-stable headless on a
shared 4-vCPU cloud container, so treat ±1–2 ms as noise. Rendered runs weren't
repeated this pass. The rendered and web checks in
`docs/revamp/2026-09-27-v3-technicolor-revamp.md` §5 still stand.

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 3.5 ms | 0 >8 ms | boot+instantiate 453 ms, briefing 33 ms |
| L9 boss | headless | 3.6 ms | 0 >8 ms | ring 52/58, reaches victory state |
| Gauntlet | headless | 3.8–5.8 ms in 7 of 8 runs | 1 >8 ms in 1 run | one run had a single 8–10 ms step; 7 reruns stayed under 6 ms |

That's within 1 ms of the phase-7 numbers (3.0 / 1.7 / 3.1 ms) on L8 and
the gauntlet. The L9 boss is ~2 ms higher, but still far under the 8 ms spike
bar. Watch the single gauntlet outlier in the in-browser test: if the gauntlet
stutters on iPad, start here.
