# Changelog

*[中文说明 →](CHANGELOG.zh.md)*

Newest first. Everything before `v1.0.0` was released as a pre-release;
`v1.0.0` was the first official release.

## Versioning conventions

**The version number is agreed before every push.**

- Pre-1.0 we used `0.x.y`; from the first official release, `1.x.y`:
  - **New feature / large change** → bump the minor version (`1.0.3` → `1.1.0`)
  - **Bug fix / small change** → bump the patch version (`1.0.3` → `1.0.4`)
  - **Docs or comments only** → no tag
- Every tag gets a GitHub Release
- **The repository holds source only** — executables go on Release assets, never in git
- **Tags are immutable.** Never move one; cut a new number instead
- **Commit messages state facts only** — what changed. No "root cause / measured /
  gotcha / this used to be wrong" narrative; commit history is public

---

## v1.0.3 — 2026-10-07

### Fixed

- **The "heavy gravity" event made the craft completely uncontrollable — it fell in a
  straight line.** Lift while climbing is `cruise_speed × lift_gain` (660 × 5.2 = 3432);
  gravity is `1800 × multiplier`. At the old 2.3× that came to 4140 — larger than the
  lift, so holding the climb key still lost altitude. Now 1.65 (net +462: you can pull
  up, but it feels heavy). `main.gd` also got a hard `MAX_GRAVITY_SCALE = 1.7` cap

### Added

- **English README** (`README.md`), with a language switcher on both versions
- The acceptance suite now **checks the gravity budget** across every
  world × gravity-event combination, reading the real values from `player.tscn`
  and the script constants rather than hard-coding them

### Changed

- The promo line on the title screen is now `Also try Bililearn-AI`

### Release

- Re-exported Windows (x86_64) and macOS (universal) builds

---

## v1.0.2 — 2026-10-07

### Changed

- **Solo controls changed to `W` to climb and `E` to dash**, matching player 1 in co-op.
  `SPACE` is no longer used (player 2 still uses `↑` / `ENTER`)
- On-screen control hints and the README updated to match
- The promo line on the title screen moved slightly up and to the left

### Docs

- Obstacles are now consistently called "pillars" throughout the README and changelog

### Release

- Re-exported Windows (x86_64) and macOS (universal) builds

---

## v1.0.1 — 2026-10-07

### Changed

- **Splash background** became a shower of falling coins (46 of them, varying speed and
  size, looping endlessly)
- The promo line on the title screen is **rotated 30° counter-clockwise**, with its
  position and width adjusted to clear the control hint below it

### Release

- Re-exported Windows (x86_64) and macOS (universal) builds

---

## v1.0.0 — 2026-10-07

The first official release.

### Release

- **Windows (x86_64)** and **macOS (universal binary, Intel + Apple Silicon)** builds
  attached to the Release as zip files
- The repository still holds source only; no executables are committed to git

### Added

- Splash animation, split-screen co-op, revive countdown, skins panel, bilingual
  English/Chinese UI, gamepad support, window and fullscreen settings

---

## v0.11.0 — 2026-10-06

### Added

- A promo line at the lower right of the title screen, centred near the "RD" of "BIRD",
  in yellow pixel type, cycling a scale pulse around its own centre

### Changed

- **Splash animation**: duration cut from 6.25 s to 1.88 s
- **Splash background** changed to a blue sky with clouds, plus two animated layers:
  clouds drifting left with seamless wrap, and coins rising and spinning

---

## v0.10.0 — 2026-10-06

### Added

- **Splash animation**: the seven letters of "YYCHRER" in handwritten pixel type floating
  in one at a time, each with its own tilt and vertical offset, 0.55 s apart. Skippable
- **Revive countdown** in the top right of the co-op HUD, shown only while someone is down

### Changed

- Co-op **revive now inherits the horizontal speed** from the moment of going down

---

## v0.9.1 — 2026-10-06

### Fixed

- **Coins spawning inside pillars.** `obstacle.position.x` is the pillar's **left edge**
  (both the sprite and the collision box are `centered = false` and laid out to the right
  over 384 px), but the coin corridor was computed as `± HALF_PILLAR(192)` — treating it
  as the centre, which short-changed the left boundary by 192 px. The corridor is now
  computed from the left and right edges
- Coins from the "coin burst" power-up now pass through `push_out_of_pillars()`, iterated
  until stable (pushing out of one pillar can land you inside another)

---

## v0.9.0 — 2026-10-06

### Added

- **Bilingual English/Chinese UI**: every label is baked into a texture, so the generator
  emits two sets — `art/ui/en/` and `art/ui/zh/` — with identical filenames. Switching
  language at runtime needs no lookup table; the filename is the key. English by default
- **Gamepad support** for every gameplay action, plus menu navigation
  (d-pad / left stick, `A` to confirm, `B` to back)
- **Settings panel**: language / window mode / resolution
- **Window and fullscreen settings**: opens at 1280×720 by default, `F11` to toggle,
  choice persisted

### Fixed

- Event banner text not following the language switch

---

## Earlier milestones (untagged)

### 2026-10-06 — AI copilot and split screen

- **AI copilot mode**: a bot flies player 2 with three difficulty levels
  (Rookie / Regular / Ace). The bot doesn't fake `InputEvent`s — it writes
  `player.virtual_up` and so shares the human player's physics path. "Misses" are
  implemented as *freezing* (holding the previous input) rather than random button
  mashing, which reads more like a human reacting late
- **Split screen** when the two players drift more than one screen apart
- **Per-world BGM**: six chiptunes cross-faded over 1.4 s on world switch
- **Revive view**: the split turns off while someone is down, handing the view to the
  surviving player
- Collecting a coin shaves 0.5 s off *that player's* dash cooldown

### 2026-10-06 — Co-op polish

- P1 / P2 / AI badges above each craft; skins editable separately per player
- Crash sound; a distinct looping engine sound per aircraft
- Co-op keys split: P1 `W` + `E`, P2 `↑` + `ENTER`
- Camera smoothing reworked; the two craft start one body-length apart

### 2026-10-05 — Major expansion

- **Two-player co-op**: a downed player can be revived if their partner survives 5 s
- **Random event system** (7 events): portal (a 20-second coin realm), coin rain,
  moon gravity, heavy gravity, free dash, meteor shower, double coins
- **Skins**: six aircraft × six pilots
- **Six biomes**: clear skies / outer space / jungle / dream world / upside down /
  coin realm
- **Power-ups** (magnet / shield / coin burst) and a **combo multiplier**
- Four new Python generators: `gen_worlds.py`, `gen_events.py`, `gen_skins.py`,
  `gen_powerups.py`

### 2026-10-05 — First playable build

- 8-bit pixel-art reaction runner: hold to climb, with lift proportional to speed
- **Invincible dash**: 3 seconds of invulnerability, fully gilded, straight through pillars
- Title screen: 25 unpowered rigid-body birds fall from the sky onto a vertically
  oscillating ground
- Infinite ground, world-space parallax, camera with hard horizontal follow and a
  vertical dead zone
- Audio architecture: BGM across scenes plus a sound-effect pool
- **All art, music and sound effects are procedurally generated** by the Python scripts
  in `tools/` — no third-party assets
