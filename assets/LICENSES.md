# Third-party content (CC0 only)

Hard rule 1 (`CLAUDE.md`) allows exactly two kinds of third-party file:

- **CC0 3D models**, used only as sprite sources. They're turntable-baked into atlases by
  `tools/bake_sprites.tscn`, and the models themselves never ship.
- **CC0 sound effects**, crunched by `tools/crunch_sfx.py` into `resources/sfx/`.

Every such file is pinned in `assets/cc0/manifest.json` and fetched with
`python3 tools/fetch_cc0.py fetch <name>`. The tool checks the sha256 pin, refuses anything that
isn't `CC0-1.0`, and writes the row below. Rules:

- Never add a file by hand.
- No CC-BY, CC-BY-SA, GPL or AI-generated content.
- No file name or URL that names the '95 game, its studio or its publisher.

`tools/check_budgets.py` fails CI if a file in `assets/cc0/` has no row here, or if its sha256
no longer matches.

CC0 needs no attribution. The source of each file is credited here anyway.

| File | Kind | Source | URL | License | Fetched | sha256 |
|---|---|---|---|---|---|---|
