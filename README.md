# digicam-drop

Insert your digicam's SD card. Everything else is automatic.

Pure bash + launchd, macOS. Works with any camera that writes `DCIM/`.

On insert:

- Imports **new files only** (manifest + byte-level dedupe — never a duplicate)
- Organises into `~/Pictures/Digicam/YYYY/YYYY-MM-DD/` (EXIF dates)
- Transcodes videos to iPhone-ready H.264 `.mp4` — iOS Photos rejects the
  MJPEG/MPEG-4 that old digicams record. Near-lossless, ~6x smaller, capture
  date + camera model embedded in the file
- Opens an AirDrop batch folder with just the new files (hardlinks, zero extra disk)
  → ⌘A → AirDrop → straight into your iPhone photo gallery, videos included
- Mirrors the library to a Google Drive folder (desktop app, add-only, optional)
- Ejects the card when done — pull it out without thinking

## Install

```bash
git clone https://github.com/howwohmm/digicam-drop && cd digicam-drop
./install.sh
```

Pulls `ffmpeg` + `exiftool` via Homebrew, sets up the launchd agent. Done.

## Config (`config.sh`, git-ignored)

```bash
DRIVE_FOLDER_ID=""        # Drive folder ID from its URL; empty = My Drive/Digicam
EJECT_AFTER_IMPORT=eject  # eject | readonly (browsable, write-locked) | off
IMPORT_TO_PHOTOS=0        # 1 = also import into Photos.app (iCloud sync)
ASK_BEFORE_IMPORT=0       # 1 = confirm first (terminal y/N, or a dialog on
                          # card insert; auto-cancels after 2 min). One-off:
                          # ./digicam-import.sh --ask
```

## Ops

- Log: `~/Library/Logs/digicam-import.log`
- Manual import: `./digicam-import.sh /path/to/folder`
- Re-import all: empty `~/Pictures/Digicam/.imported-manifest`
- Uninstall: `./install.sh --uninstall`

Set your camera's clock — files sort by embedded date.

## Backstory

Bought a vintage Sony DSC-W620. AirDropped videos landed in Files instead of
Photos (iOS rejects old codecs), the desktop dump hit 2 GB, duplicates
everywhere, and I never eject before pulling. Fixed each problem once, wired
it all to card insert.

Multiple cameras / an office card that should ask before importing? →
[media-io-ops-ic](https://github.com/howwohmm/media-io-ops-ic)

— [Ohm](https://github.com/howwohmm) · MIT
