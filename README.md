**A themed resting timer for Final Fantasy XI on Ashita v4.**

Sit down with `/heal` and a small window shows how long until your next recovery tick, what your HP and MP will be after it, and how many ticks you need to be full. Stand up and it goes away. It knows the real tick timing, re-syncs itself to the actual HP/MP gains, and reads your gear, food, Clear Mind and Signet bonuses so the numbers match what you get.

## Install

1. Click **Code > Download ZIP** on this page (or grab the latest release).
2. Unzip it. Put it in your addons folder, so you have `/addons/zztick/zztick.lua`.
3. In game: `/addon load zztick`
4. To load it every time, add `/addon load zztick` to `/scripts/default.txt`.
5. Type `/zztick test` to show a preview while standing, drag it where you want it, then `/zztick lock`.
6. `/zztick config` opens the settings.

---

## Features

| | |
| --- | --- |
| **Next tick countdown** | One decimal, plus a progress bar |
| **HP / MP after the tick** | `812 -> 834 (+22)`, capped at your max |
| **Time to full** | Ticks left and seconds until HP and MP are full |
| **Accurate model** | Retail or LandSandBoat (private server) formulas, re-synced to every real tick |
| **Bonuses read for you** | Gear "HP/MP recovered while healing", food, Signet/Sanction/Sigil, Clear Mind I-VI |
| **Level Sync aware** | Uses your synced level and shows a "Synced Lv NN" badge |
| **Themes** | Frames, HP/MP mini bars and icons, bundled fonts |
| **Effects** | Moving shine, leading-edge spark, tick glint, number roll-up, border comet when full |
| **Full-heal chime** | Optional sound when you're fully rested, with volume and your own `.wav` files |
| **Compact mode** | One-line window that fits its row |
| **Safe settings** | Saved per character; hand edits are checked and fixed on load |

---

## Themes

<img width="1280" height="452" alt="themes" src="https://github.com/user-attachments/assets/98e90167-8322-44f8-a118-43084783d91d" />

Vana'diel Gold (default), Crystal Blue, Midnight, Ember Forge, Windurst Verdant, Bastok Steam, Jeuno Twilight, Abyssea and Classic. Classic uses the colors you pick in the Style tab; the others have their own palettes.

---

## Config Tabs

`/zztick config` opens the settings window. This section mirrors the menu. The **Show preview window (test mode)** checkbox at the top shows the window with sample numbers so you can see changes while standing.

### General
- **Window:** lock position, title bar, compact mode, scale, background opacity, bar height, line padding, width (compact mode always fits its one row; your width comes back when it's off), exact X/Y.
- **Lines:** countdown, progress bar, HP, MP, gain amounts, tick number, ticks/time to full, food and its bonus, Level Sync badge, and a "last observed gain" diagnostic line.

### Style
- Theme and corner rounding.
- HP/MP mini bars and HP/MP icons.
- **Font:** body, title and number fonts, size, bold, outline and outline color.
- **Colors (Classic theme):** text, timer, HP, MP, bar and bar background.

### Effects
- Effects level and strength, animations on/off, fade time.
- **Bar:** moving shine (and how often), leading-edge spark (size and strength), charge-up in the last 3 seconds.
- **On every tick:** glint, heart/droplet pop, numbers roll up, border comet.
- **Resting and full:** breathing moon and floating z, fully-rested line, glint and stars, and what happens when HP or MP reaches full (border, sparkle, both or off).
- **Preview:** replay a tick or the full effect without resting.

### Sound
- Chime when fully healed, and when (both full, either, HP only, MP only).
- Sound picker, volume 0-200%, Test chime, Rescan `sounds/`.
- Also chime when you sit down already full.

### Recovery
- **Bonuses:** extra HP/MP per tick for things the scan can't see, read gear bonuses on/off, count the food bonus.
- **Rules:** Signet/Sigil (Auto, Always, Never), server rules (Retail or LandSandBoat), BLU Clear Mind tier 0-6.

---

## Commands

Everything is also in `/zztick config`.

| Command | What it does |
| --- | --- |
| `/zztick` | Help |
| `/zztick config` | Open/close the settings window (everything below is also there) |
| `/zztick lock` / `unlock` | Lock or unlock the window position |
| `/zztick test` | Toggle a preview window with sample numbers (for positioning) |
| `/zztick test sync` | Preview with the "Synced Lv 30" badge |
| `/zztick sync on` / `off` | Show the "Synced Lv NN" badge under Level Sync / Level Restriction (default on) |
| `/zztick compact` | Toggle one-line compact mode |
| `/zztick theme <name>` | `Vana'diel Gold` (default), `Crystal Blue`, `Midnight`, `Ember Forge`, `Windurst Verdant`, `Bastok Steam`, `Jeuno Twilight`, `Abyssea`, `Classic` (short names like `gold`, `ember`, `windurst`, `bastok`, `jeuno`, `abyssea` work) |
| `/zztick chime on` / `off` / `test` | Soft chime when fully healed, once per rest (on by default). `test` always plays and prints diagnostics |
| `/zztick chime volume <0-200>` | Chime volume in percent (100 = the file as it is) |
| `/zztick info` | Print what the model is using: jobs, real vs effective (synced) levels and their source, Clear Mind tier, gear bonuses, tick 1 values |
| `/zztick reset` | Reset settings to defaults |

---

## Credits

- **Fonts** (SIL Open Font License 1.1, licenses in `fonts/licenses/`): Barlow Semi Condensed by Jeremy Tribby, Cinzel by Natanael Gama, JetBrains Mono by JetBrains, Inter by Rasmus Andersson.
- **Sounds:** `chime_soft.wav` and `chime_bell.wav` were made for Zztick and are CC0.
- Formulas and data from BG-Wiki, Gamer Escape, the LandSandBoat server and Windower resources (links in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md#sources)).
- Built on [Ashita v4](https://github.com/AshitaXI/Ashita-v4beta).

## License

Copyright (c) 2026 Banedon. Zztick is released under the [GNU General Public License v3](LICENSE).
