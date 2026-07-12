#!/bin/bash
# digicam-drop installer — sets up dependencies and the launchd agent.
# Usage: ./install.sh          install / update
#        ./install.sh --uninstall

set -eu

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.digicam-drop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled ($PLIST removed). Your library is untouched."
  exit 0
fi

# dependencies
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required (https://brew.sh) — install it first." >&2
  exit 1
fi
for pkg in ffmpeg exiftool; do
  if [[ ! -x /opt/homebrew/bin/$pkg && ! -x /usr/local/bin/$pkg ]]; then
    echo "Installing $pkg…"
    brew install "$pkg"
  fi
done

chmod +x "$BASE/digicam-import.sh"
[[ -f "$BASE/config.sh" ]] || cp "$BASE/config.example.sh" "$BASE/config.sh"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$BASE/digicam-import.sh</string>
    </array>
    <key>StartOnMount</key>
    <true/>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/digicam-import.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/digicam-import.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"

echo "Installed. Insert a camera card and watch it go."
echo "Config: $BASE/config.sh   Log: ~/Library/Logs/digicam-import.log"
