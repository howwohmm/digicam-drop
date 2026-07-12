# digicam-drop

**Insert your digicam's SD card. Everything else is automatic.**

A single-script macOS pipeline for vintage digicams (anything that writes a
`DCIM/` folder). On card insert it:

1. **Imports only what's new** — a manifest remembers every file ever imported
   (byte-level duplicate detection), so you never get doubles.
2. **Organises by capture date** — `~/Pictures/Digicam/YYYY/YYYY-MM-DD/`,
   dates read from EXIF.
3. **Makes videos iPhone-ready** — old digicams record Motion-JPEG or MPEG-4
   AVIs that iOS Photos rejects (AirDrop dumps them into Files 😤). Each video
   becomes a single near-lossless H.264/AAC `.mp4` at a fraction of the size,
   capture date and camera model embedded in the file itself.
4. **Opens an AirDrop batch** — a Finder folder with *just this import*:
   ⌘A → Share → AirDrop → everything (videos included!) lands in your iPhone
   photo gallery. Batches are hardlinks — zero extra disk.
5. **Mirrors to Google Drive** — optional add-only sync via the Google Drive
   desktop app. No OAuth, no API keys, no drama.
6. **Ejects the card by itself** — "safe to pull it out ✅" notification when
   done. Or set `readonly` mode: the card stays browsable but write-locked, so
   yanking it can't corrupt anything.

## Install

```bash
git clone https://github.com/howwohmm/digicam-drop && cd digicam-drop
./install.sh
```

Pulls `ffmpeg` + `exiftool` via Homebrew and sets up a `launchd` agent that
fires on card insert. That's it.

## Configuration (`config.sh`, git-ignored)

```bash
DRIVE_FOLDER_ID=""            # Drive folder ID from its URL; empty = My Drive/Digicam
EJECT_AFTER_IMPORT=eject      # eject | readonly (browsable but yank-safe) | off
IMPORT_TO_PHOTOS=0            # 1 = also import into Photos.app (iCloud sync!)
```

## Ops

- Log: `~/Library/Logs/digicam-import.log`
- Import any folder manually: `./digicam-import.sh /path/to/folder`
- Re-import everything: empty `~/Pictures/Digicam/.imported-manifest`
- Uninstall: `./install.sh --uninstall` (your library stays)

## Gotchas

- Set your camera's clock! Files sort by their embedded date.
- AirDrop batches are hardlinks: deleting a batch folder doesn't delete the
  library copy (and vice versa).

## How I got here

I picked up a vintage Sony DSC-W620 and hit every wall in order: AirDropped
videos landing in Files instead of Photos (old digicams record codecs iOS
refuses), a 2 GB unorganised dump on my desktop, re-imports full of duplicates,
and a lifelong habit of yanking cards without ejecting. This script is those
problems solved one at a time and wired to fire the moment the card mounts.

Need per-card profiles (personal cam auto-imports, office cam asks first)?
That grew into a bigger tool: [media-io-ops-ic](https://github.com/howwohmm/media-io-ops-ic).

— built by [Ohm](https://github.com/howwohmm) · MIT license
