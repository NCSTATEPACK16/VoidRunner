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
| `cc0/models/pod_drone.glb` | model | Quaternius, Ultimate Space Kit (Spaceship, poly.pizza/m/u105mYHLHU) | https://static.poly.pizza/0843ab59-1800-4d96-9cc7-b4d6afbecf21.glb | CC0-1.0 | 2026-11-24 | `47527b47de38ee531f4fe86baa950867984dfbac4c44c73e8c10e456bf561a4f` |
| `cc0/models/heavy_mech.glb` | model | Quaternius, Ultimate Space Kit (Mech, poly.pizza/m/o3Ps8z8ByP) | https://static.poly.pizza/a242e73b-6a40-4bd9-bfa9-ed1d8e49ea21.glb | CC0-1.0 | 2026-11-24 | `d61427def92c18148eaa9cebbc0dbd26b8e55ea5d048293840165077180bd181` |
| `cc0/models/sentinel_mech.glb` | model | Quaternius, Ultimate Space Kit (Mech, poly.pizza/m/D5wW2jDO42) | https://static.poly.pizza/750173d2-53aa-4318-95dc-5f8e6d2dcad2.glb | CC0-1.0 | 2026-11-24 | `0ec238495ae7da168d66f74441b98b71525d4a80536eeaf3aed701c7efee17d8` |
| `cc0/sfx/sfx_boom.ogg` | sfx | rubberduck, 50 CC0 Sci-Fi SFX (OpenGameArt) — `retro_explosion.ogg` from the archive pinned at sha256 `7824c08e54b5b68d6c70ced9d8fe9e47f86ce19c1d8d47d093e1dc1b579f78ec` | https://opengameart.org/sites/default/files/sci-fi-sfx.zip | CC0-1.0 | 2026-11-24 | `2217da9c65702fb71b96113ed0c658ad388c32534c9756f403012f79126fa9c4` |
| `cc0/sfx/sfx_missile.ogg` | sfx | rubberduck, 50 CC0 Sci-Fi SFX (OpenGameArt) — `rocket_01.ogg` from the archive pinned at sha256 `7824c08e54b5b68d6c70ced9d8fe9e47f86ce19c1d8d47d093e1dc1b579f78ec` | https://opengameart.org/sites/default/files/sci-fi-sfx.zip | CC0-1.0 | 2026-11-24 | `9b1935d00fdbb7b1797b1d10347d26830d5707fef705c84d9cf919628e06f5a9` |
| `cc0/sfx/sfx_powerup.mp3` | sfx | Kenney, 63 Digital sound effects (OpenGameArt) — `powerUp2.mp3` from the archive pinned at sha256 `022f0f4b73da55989567fe2b373c8af89d74f5d015257e293cab497ca606d063` | https://opengameart.org/sites/default/files/Digital_SFX_Set.zip | CC0-1.0 | 2026-11-24 | `4339702d87d07acef9b10cd515cdea1d4321ff985225228c5ee80adccfa0628d` |
| `cc0/sfx/sfx_hit.mp3` | sfx | Kenney, 63 Digital sound effects (OpenGameArt) — `lowDown.mp3` from the archive pinned at sha256 `022f0f4b73da55989567fe2b373c8af89d74f5d015257e293cab497ca606d063` | https://opengameart.org/sites/default/files/Digital_SFX_Set.zip | CC0-1.0 | 2026-11-24 | `7cb72968216a27079304ecc78d1993ddee2dc88fd6a0bba3c76617745889f233` |
| `cc0/sfx/sfx_enemy_hit.mp3` | sfx | Kenney, 63 Digital sound effects (OpenGameArt) — `pepSound1.mp3` from the archive pinned at sha256 `022f0f4b73da55989567fe2b373c8af89d74f5d015257e293cab497ca606d063` | https://opengameart.org/sites/default/files/Digital_SFX_Set.zip | CC0-1.0 | 2026-11-24 | `01b82ccc249f6659669448e95f2c895bebf33df04ef0ecf5bc1052284257ba85` |
