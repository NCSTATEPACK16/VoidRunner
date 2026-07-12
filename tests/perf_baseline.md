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
