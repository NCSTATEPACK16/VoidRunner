# Asset budgets

`tools/check_budgets.py` enforces these limits, and CI (`.github/workflows/ci.yml`) runs it on
every pull request. The numbers are kept in the script's `BUDGETS` table; change them there and
here together, in a PR that says why.

| Budget | Limit | Today (PR E, 2026-11-09) | Why |
|---|---|---|---|
| Web `.pck` | 2.5 MB | 1.59 MB | The engine is ~10 MB gzipped. The pack shouldn't become the long pole on a phone connection. |
| Prebaked sprite PNGs, total | 2.0 MB | 1.14 MB (4 sheets) | Most of the pack. PR F's higher angle and frame counts spend from here first. |
| Sheet side | 2048 px | 1920 px (enemies) | The texture size every WebGL2 device must support (`SpriteForge.MAX_SHEET_PX`). |
| Baked sheets decoded (RGBA8) | 32 MB | 10.9 MB | Texture memory on the oldest iPad we target. |
| Web title up (SwiftShader, `web_check.mjs`) | 6.5 s | 5.2 s | Boot time; real GPUs are faster. Compare on one machine, never across machines. |

Bookkeeping, also checked:
- Every file in `assets/cc0/` has a `LICENSES.md` row, its sha256 matches, and its license is
  `CC0-1.0`.
- Every manifest entry passes `fetch_cc0.py`'s checks: CC0 only, the right kind of file, and no
  blocked names.
- Every `resources/sfx/*.wav` is an AudioSys slot, with a manifest entry behind it.
- Every baked sheet exists, matches its manifest layout and has an `importer="keep"` import.
  No PNG in `resources/baked/` is missing from the manifest.

The smoke test does the stale-bake check. The manifest's source hash has to match
`SpriteForge.source_hash()`, and that hash needs Godot to compute. After changing a sprite model,
`studio.gdshader`, `TextureGen` or the class table, rebake:

```sh
xvfb-run -a godot --rendering-driver opengl3 tools/bake_sprites.tscn
```

On the Neo, run `godot tools/bake_sprites.tscn` (windowed). Commit `resources/baked/` with the
change.
