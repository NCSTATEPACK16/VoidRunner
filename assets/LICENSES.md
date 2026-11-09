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
| `cc0/models/quaternius_striker.gltf` | model | Quaternius (Ultimate Spaceships) | https://quaternius.com/packs/ultimatespaceships.html | CC0-1.0 | 2026-11-09 | `2f6c4b1d16f11d5ce02833c5841ff17e19700418c83e52501ed29e3c2bc79359` |
| `cc0/models/quaternius_mech_leela.gltf` | model | Quaternius (Animated Mech Pack, Flat Colors) | https://quaternius.com/packs/animatedmech.html | CC0-1.0 | 2026-11-09 | `98e08e4fa3e5fcfec4b639a4922e78fa25c46d985993419955f9a13b725ae652` |
| `cc0/sfx/kenney_explosion_crunch_000.ogg` | sfx | Kenney (Sci-fi Sounds) | https://kenney.nl/assets/sci-fi-sounds | CC0-1.0 | 2026-11-09 | `4b597d658d0ae101f0a030fbeea5fc3a4292ab85f017470a8254a8e7959cbd69` |
| `cc0/sfx/kenney_low_frequency_explosion_000.ogg` | sfx | Kenney (Sci-fi Sounds) | https://kenney.nl/assets/sci-fi-sounds | CC0-1.0 | 2026-11-09 | `3cb48d86dab63140cfb9aaeea4d4a6846abaca5831d157d8adbec0490da26343` |
| `cc0/sfx/kenney_impact_metal_light_000.ogg` | sfx | Kenney (Impact Sounds) | https://kenney.nl/assets/impact-sounds | CC0-1.0 | 2026-11-09 | `33b5e6e37c6e9d54e07bf5a89b12c76e879f40c1ea83cdd82714df1d6f9fec6d` |
| `cc0/sfx/kenney_impact_metal_heavy_000.ogg` | sfx | Kenney (Impact Sounds) | https://kenney.nl/assets/impact-sounds | CC0-1.0 | 2026-11-09 | `e07045693e4a2b3d165c424e3dab4c781d9ff8880a386880ac89a51315d7f831` |
| `cc0/sfx/kenney_confirmation_001.ogg` | sfx | Kenney (Interface Sounds) | https://kenney.nl/assets/interface-sounds | CC0-1.0 | 2026-11-09 | `063564703b6094d70718a3e787a55cc9141611e4ecd6b6637f8828f79b4a8c3a` |
| `cc0/models/quaternius_executioner.gltf` | model | Quaternius (Ultimate Spaceships) | https://quaternius.com/packs/ultimatespaceships.html | CC0-1.0 | 2026-11-09 | `95dd08b854b0588480e91515949c5fd3e329ec856882e2b58b71e4cdc41348f9` |
