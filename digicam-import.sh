#!/bin/bash
# digicam-drop — insert a camera SD card, everything else is automatic.
#
# Policy: ONE copy per media, highest quality, metadata embedded in the file.
#   - Photos: original JPEGs, untouched (EXIF already embedded).
#   - Videos: single H.264/AAC .mp4 (near-lossless CRF 16) — old digicams
#     record MJPEG/MPEG-4 that iOS Photos rejects; capture date + camera
#     make/model are embedded from the .THM sidecar, which is then not needed.
#   - Library: ~/Pictures/Digicam/YYYY/YYYY-MM-DD/
#   - Afterwards the card is ejected (or remounted read-only) so it can be
#     pulled out without thinking.
#
# Usage:
#   digicam-import.sh            # scan /Volumes for a card with DCIM/
#   digicam-import.sh /path/dir  # import a folder (card roots with DCIM/ scan
#                                # only DCIM/MP_ROOT/PRIVATE; dot-dirs skipped)

set -u

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$BASE/config.sh" ]] && source "$BASE/config.sh"

LIB="${DIGICAM_LIB:-$HOME/Pictures/Digicam}"
BATCHES="$LIB/AirDrop Batches"
MANIFEST="$LIB/.imported-manifest"
LOG="$HOME/Library/Logs/digicam-import.log"
LOCK="/tmp/digicam-import.lock"

# Set to 1 (here or in config.sh) to ALSO auto-import each batch into the
# Photos app (with iCloud Photos on, that syncs to the iPhone with zero taps).
IMPORT_TO_PHOTOS="${IMPORT_TO_PHOTOS:-0}"

# Google Drive upload: the whole library is mirrored (new files only, never
# deletes) into a Drive folder via the Google Drive desktop app's synced
# filesystem. Resolution order: DIGICAM_DRIVE_DIR override -> folder matching
# DRIVE_FOLDER_ID from config.sh (DriveFS stores the ID in an xattr) ->
# cached last-known path -> My Drive/Digicam.
DRIVE_FOLDER_ID="${DRIVE_FOLDER_ID:-}"
DRIVE_DIR="${DIGICAM_DRIVE_DIR:-}"
if [[ -z "$DRIVE_DIR" && -n "$DRIVE_FOLDER_ID" ]]; then
  for gd in "$HOME/Library/CloudStorage/"GoogleDrive-*/*; do
    [[ -d "$gd" ]] || continue
    while IFS= read -r -d '' d; do
      id=$(/usr/bin/xattr -p 'com.google.drivefs.item-id#S' "$d" 2>/dev/null)
      if [[ "$id" == *"$DRIVE_FOLDER_ID"* ]]; then DRIVE_DIR="$d"; break 2; fi
    done < <(find "$gd" -maxdepth 3 -type d -print0 2>/dev/null)
  done
fi
# Cache the ID-resolved folder: DriveFS xattr reads can transiently fail
# (observed 2026-07-12), which would otherwise silently divert the sync into
# the My Drive/Digicam fallback and build a duplicate library there.
DRIVE_DIR_CACHE="$HOME/Library/Caches/digicam-drop.drive-dir"
if [[ -n "$DRIVE_DIR" && -z "${DIGICAM_DRIVE_DIR:-}" ]]; then
  printf '%s\n' "$DRIVE_DIR" > "$DRIVE_DIR_CACHE" 2>/dev/null
elif [[ -z "$DRIVE_DIR" && -s "$DRIVE_DIR_CACHE" ]]; then
  cached=$(<"$DRIVE_DIR_CACHE")
  [[ -d "$cached" ]] && DRIVE_DIR="$cached"
fi
if [[ -z "$DRIVE_DIR" ]]; then
  for gd in "$HOME/Library/CloudStorage/"GoogleDrive-*/"My Drive"; do
    [[ -d "$gd" ]] && DRIVE_DIR="$gd/Digicam" && break
  done
fi

# launchd runs with a bare PATH, so locate Homebrew tools explicitly
# (Apple Silicon and Intel prefixes).
find_tool() {
  local t
  for t in "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
    [[ -x "$t" ]] && { echo "$t"; return; }
  done
  command -v "$1" 2>/dev/null
}
FFMPEG="$(find_tool ffmpeg)"
FFPROBE="$(find_tool ffprobe)"
EXIFTOOL="$(find_tool exiftool)"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

notify() {
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1
}

# What to do with the card once the import is done: eject (default),
# readonly (keep it browsable but yank-safe), or off.
EJECT_AFTER_IMPORT="${EJECT_AFTER_IMPORT:-eject}"

safe_release() {  # make the card yank-safe per EJECT_AFTER_IMPORT
  local vol="$1" dev
  [[ "$vol" == /Volumes/* && -d "$vol" ]] || return 0
  case "$EJECT_AFTER_IMPORT" in
    0|off) return 0 ;;
    readonly|ro)
      # Remount read-only: card stays browsable in Finder, but with no pending
      # writes possible, pulling it out can no longer corrupt anything.
      if mount | grep -F " on $vol " | grep -q 'read-only'; then return 0; fi
      dev=$(/usr/sbin/diskutil info -plist "$vol" 2>/dev/null \
              | /usr/bin/plutil -extract DeviceNode raw - 2>/dev/null)
      [[ -n "$dev" ]] || return 0
      if /usr/sbin/diskutil unmount "$vol" >/dev/null 2>&1 \
         && /usr/sbin/diskutil mount readOnly "$dev" >/dev/null 2>&1; then
        log "remounted $vol read-only — browsable, safe to pull anytime"
        notify "Digicam Drop" "Card is now read-only — browse freely, pull it out anytime ✅"
      else
        /usr/sbin/diskutil mount "$dev" >/dev/null 2>&1  # restore access on failure
        log "read-only remount FAILED for $vol — eject manually before pulling"
        notify "Digicam Drop" "Import done, but couldn't protect the card — eject manually."
      fi ;;
    *)  # eject
      if /usr/sbin/diskutil eject "$vol" >/dev/null 2>&1 \
         || { sleep 3; /usr/sbin/diskutil eject "$vol" >/dev/null 2>&1; }; then
        log "ejected $vol — safe to pull the card"
        notify "Digicam Drop" "Card ejected — safe to pull it out ✅"
      else
        log "eject FAILED for $vol (still in use?) — eject manually before pulling"
        notify "Digicam Drop" "Import done, but eject failed — eject the card manually."
      fi ;;
  esac
}

# ---- find the source ---------------------------------------------------------
src="${1:-}"
scan_dirs=()
if [[ -n "$src" ]]; then
  [[ -d "$src" ]] || { echo "no such directory: $src" >&2; exit 1; }
  if [[ -d "$src/DCIM" ]]; then
    # card/volume root: scan only the camera dirs, exactly like the no-arg path
    # (never .Trashes, MISC, etc.)
    for d in DCIM MP_ROOT PRIVATE; do [[ -d "$src/$d" ]] && scan_dirs+=("$src/$d"); done
  else
    scan_dirs=("$src")
  fi
else
  sleep 2  # let the volume finish mounting
  for v in /Volumes/*; do
    [[ "$v" == "/Volumes/Macintosh HD" ]] && continue
    if [[ -d "$v/DCIM" ]]; then
      src="$v"
      for d in DCIM MP_ROOT PRIVATE; do [[ -d "$v/$d" ]] && scan_dirs+=("$v/$d"); done
      break
    fi
  done
fi
[[ ${#scan_dirs[@]} -eq 0 ]] && exit 0

# ---- single-instance lock ----------------------------------------------------
if ! mkdir "$LOCK" 2>/dev/null; then
  log "another import is running, skipping ($src)"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

mkdir -p "$LIB" "$BATCHES"
touch "$MANIFEST"
log "=== source detected: $src"

# ---- helpers -----------------------------------------------------------------
photo_day() {  # capture date of an image -> YYYY-MM-DD (falls back to file mtime)
  local d=""
  if [[ -x "$EXIFTOOL" ]]; then
    d=$("$EXIFTOOL" -s3 -d '%Y-%m-%d' -DateTimeOriginal -CreateDate "$1" 2>/dev/null | head -1)
  fi
  [[ -z "$d" ]] && d=$(date -r "$(stat -f %m "$1")" '+%Y-%m-%d')
  echo "$d"
}

thm_for() {  # sidecar thumbnail holding EXIF for a Sony video, if any
  local base="${1%.*}"
  for c in "$base.THM" "$base.thm"; do
    [[ -f "$c" ]] && { echo "$c"; return; }
  done
  echo ""
}

video_epoch() {  # capture time of a video -> unix epoch
  local f="$1" thm="$2" dt="" e=""
  if [[ -n "$thm" && -x "$EXIFTOOL" ]]; then
    dt=$("$EXIFTOOL" -s3 -DateTimeOriginal "$thm" 2>/dev/null)
    [[ -n "$dt" ]] && e=$(date -j -f '%Y:%m:%d %H:%M:%S' "$dt" +%s 2>/dev/null)
  fi
  if [[ -z "$e" ]]; then
    dt=$("$FFPROBE" -v error -show_entries format_tags=creation_time -of csv=p=0 "$f" 2>/dev/null | cut -c1-19)
    [[ -n "$dt" ]] && e=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$dt" +%s 2>/dev/null)
  fi
  [[ -z "$e" ]] && e=$(stat -f %m "$f")
  echo "$e"
}

sync_to_drive() {  # mirror the library into Google Drive (adds only, never deletes)
  [[ "${DIGICAM_DRIVE:-1}" == "0" ]] && { log "Drive sync skipped (DIGICAM_DRIVE=0)"; return; }
  [[ -n "$DRIVE_DIR" && -d "$(dirname "$DRIVE_DIR")" ]] || { log "Drive sync skipped (Google Drive not signed in)"; return; }
  mkdir -p "$DRIVE_DIR"
  local n
  n=$(rsync -rt --ignore-existing --exclude 'AirDrop Batches' --exclude '.*' \
        --out-format '%n' "$LIB/" "$DRIVE_DIR/" 2>>"$LOG" | grep -cv '/$')
  log "Drive sync: $n new file(s) queued for upload to $DRIVE_DIR"
}

unique_dest() {  # avoid overwriting a different file with the same name
  local srcf="$1" dest="$2" base ext n=1
  [[ ! -e "$dest" ]] && { echo "$dest"; return; }
  if cmp -s "$srcf" "$dest" 2>/dev/null; then echo "$dest"; return; fi
  base="${dest%.*}"; ext="${dest##*.}"
  while [[ -e "${base}_$n.$ext" ]]; do n=$((n+1)); done
  echo "${base}_$n.$ext"
}

# ---- import ------------------------------------------------------------------
photos=0 videos=0 skipped=0 failed=0
batch_files=()

while IFS= read -r -d '' f; do
  name=$(basename "$f")
  key="$name|$(stat -f '%z|%m' "$f")"
  if grep -qxF "$key" "$MANIFEST"; then
    skipped=$((skipped+1)); continue
  fi

  ext_lc=$(echo "${name##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext_lc" in
    jpg|jpeg|png|heic)
      day=$(photo_day "$f")
      fixdate=""
      if [[ "${FIX_BOGUS_DATES:-1}" == "1" && "${day%%-*}" -lt "${BOGUS_YEAR_MIN:-2015}" ]]; then
        # camera clock was reset (dead/removed battery) — use the import time
        fixdate=$(date '+%Y:%m:%d %H:%M:%S')
        day=$(date '+%Y-%m-%d')
      fi
      destdir="$LIB/${day%%-*}/$day"
      mkdir -p "$destdir"
      dest=$(unique_dest "$f" "$destdir/$name")
      if [[ -e "$dest" ]] && cmp -s "$f" "$dest"; then
        # identical content already in the library (e.g. re-copied with a new
        # timestamp) — record it and keep it out of the "new files" batch
        echo "$key" >> "$MANIFEST"; skipped=$((skipped+1)); continue
      fi
      cp -p "$f" "$dest" || { log "FAILED copy $f"; failed=$((failed+1)); continue; }
      if [[ -n "$fixdate" && -x "$EXIFTOOL" ]]; then
        "$EXIFTOOL" -q -overwrite_original "-AllDates=$fixdate" "$dest" 2>>"$LOG"
        log "fixed bogus camera date on $name -> $fixdate"
      fi
      batch_files+=("$dest")
      photos=$((photos+1))
      ;;
    mp4|avi|mpg|mov|mts|m2ts)
      thm=$(thm_for "$f")
      epoch=$(video_epoch "$f" "$thm")
      vfix=0
      if [[ "${FIX_BOGUS_DATES:-1}" == "1" && "$(date -r "$epoch" '+%Y')" -lt "${BOGUS_YEAR_MIN:-2015}" ]]; then
        epoch=$(date +%s); vfix=1  # camera clock was reset — use the import time
      fi
      day=$(date -r "$epoch" '+%Y-%m-%d')
      destdir="$LIB/${day%%-*}/$day"
      mkdir -p "$destdir"
      codec=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)
      if [[ "$codec" == "h264" || "$codec" == "hevc" ]] && [[ "$ext_lc" == "mp4" || "$ext_lc" == "mov" ]]; then
        dest=$(unique_dest "$f" "$destdir/$name")
        if [[ -e "$dest" ]] && cmp -s "$f" "$dest"; then
          echo "$key" >> "$MANIFEST"; skipped=$((skipped+1)); continue
        fi
        cp -p "$f" "$dest" || { log "FAILED copy $f"; failed=$((failed+1)); continue; }
      else
        dest="$destdir/${name%.*}.mp4"
        if [[ -e "$dest" ]]; then
          # same-name mp4 already there: same duration -> already imported;
          # different duration -> genuinely different clip, keep both
          d1=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
          d2=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$dest" 2>/dev/null)
          if [[ -n "$d1" && -n "$d2" ]] && awk -v a="$d1" -v b="$d2" 'BEGIN{exit (a-b<0.6 && b-a<0.6)?0:1}'; then
            echo "$key" >> "$MANIFEST"; skipped=$((skipped+1)); continue
          fi
          n=1; while [[ -e "$destdir/${name%.*}_$n.mp4" ]]; do n=$((n+1)); done
          dest="$destdir/${name%.*}_$n.mp4"
        fi
        ct=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ')
        if ! "$FFMPEG" -nostdin -hide_banner -loglevel error -y -i "$f" \
            -map_metadata 0 -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
            -c:a aac -b:a 192k -movflags +faststart \
            -metadata creation_time="$ct" "$dest"; then
          log "FAILED transcode $f — skipping (original left in place)"
          rm -f "$dest"
          failed=$((failed+1))
          continue
        fi
        # embed camera make/model (+ original date unless it was bogus) from the sidecar
        if [[ -n "$thm" && -x "$EXIFTOOL" ]]; then
          if [[ "$vfix" == "1" ]]; then
            "$EXIFTOOL" -q -overwrite_original -P -TagsFromFile "$thm" \
              -Make -Model "$dest" 2>>"$LOG"
          else
            "$EXIFTOOL" -q -overwrite_original -P -TagsFromFile "$thm" \
              -Make -Model -DateTimeOriginal "$dest" 2>>"$LOG"
          fi
        fi
        touch -t "$(date -r "$epoch" '+%Y%m%d%H%M.%S')" "$dest"
        log "transcoded $name ($codec -> h264, $(du -h "$dest" | cut -f1) from $(du -h "$f" | cut -f1))"
      fi
      batch_files+=("$dest")
      videos=$((videos+1))
      ;;
    *) continue ;;  # .THM sidecars et al: metadata harvested above, not imported
  esac

  echo "$key" >> "$MANIFEST"
done < <(find "${scan_dirs[@]}" -name '.*' -prune -o -type f -print0 2>/dev/null)

# ---- build the AirDrop batch ---------------------------------------------------
if [[ ${#batch_files[@]} -eq 0 ]]; then
  log "nothing new (skipped $skipped already-imported, $failed failed)"
  notify "Digicam Drop" "Checked $src — no new photos or videos."
  sync_to_drive
  safe_release "$src"
  exit 0
fi

batchdir="$BATCHES/$(date '+%Y-%m-%d %H.%M')"
mkdir -p "$batchdir"
for f in "${batch_files[@]}"; do
  ln "$f" "$batchdir/$(basename "$f")" 2>/dev/null || cp -p "$f" "$batchdir/"
done

log "imported $photos photos, $videos videos (skipped $skipped, failed $failed) -> $batchdir"

if [[ "$IMPORT_TO_PHOTOS" == "1" ]]; then
  /usr/bin/osascript <<OSA >> "$LOG" 2>&1
set fileList to {}
tell application "Finder" to set batchItems to files of (POSIX file "$batchdir" as alias)
repeat with i in batchItems
  set end of fileList to (i as alias)
end repeat
tell application "Photos" to import fileList skip check duplicates yes
OSA
  log "sent batch to Photos.app"
fi

sync_to_drive

notify "Digicam Drop" "Imported $photos photos, $videos videos. Batch folder is open — ⌘A, then Share → AirDrop."
open "$batchdir"
safe_release "$src"
