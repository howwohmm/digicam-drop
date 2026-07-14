# digicam-drop configuration — copy to config.sh (git-ignored) and edit.
# Everything has a sane default; an empty config.sh is fine too.

# Google Drive folder to mirror the library into, by folder ID (the part after
# /folders/ in its URL). Requires the Google Drive desktop app, signed in.
# Leave empty to upload into "My Drive/Digicam" (created if missing).
#DRIVE_FOLDER_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# What to do with the card after a successful import, so it can be pulled out
# without thinking:
#   eject    -> unmount it completely (default)
#   readonly -> keep it browsable in Finder but remount read-only: no pending
#               writes are possible, so yanking it can't corrupt anything
#   off      -> leave it mounted as-is (you eject manually)
#EJECT_AFTER_IMPORT=eject

# Also import each batch into the Photos app (with iCloud Photos on, this
# syncs to your iPhone with zero taps). 0 = off (default).
#IMPORT_TO_PHOTOS=0

# Ask before running any operations (same as passing -i/--ask). Terminal runs
# get a y/N prompt; card-insert (launchd) runs get a macOS dialog that
# auto-cancels after 2 minutes. Declining leaves the card untouched.
#ASK_BEFORE_IMPORT=0

# Cameras whose clock resets (dead/removed battery) stamp everything ~2012.
# Dates before BOGUS_YEAR_MIN are replaced with the import time — folder AND
# embedded metadata — so photos sort correctly. Set FIX_BOGUS_DATES=0 to keep
# whatever the camera wrote.
#FIX_BOGUS_DATES=1
#BOGUS_YEAR_MIN=2015
