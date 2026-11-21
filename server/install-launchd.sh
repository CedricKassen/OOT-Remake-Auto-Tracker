#!/bin/sh
# Starts ootd at login and keeps it running (macOS).
#   ./install-launchd.sh            install and start
#   ./install-launchd.sh uninstall  stop and remove
set -e
LABEL=dev.oottracker.ootd
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HERE="$(cd "$(dirname "$0")" && pwd)"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "$1" = uninstall ]; then
  rm -f "$PLIST"
  echo "Removed $LABEL"
  exit 0
fi
[ -x "$HERE/ootd" ] || (cd "$HERE" && dart compile exe bin/ootd.dart -o ootd)
# In a release bundle the data folder sits next to this script, in the
# repository one level up.
DATA="$HERE/data"
[ -d "$DATA" ] || DATA="$HERE/../data"
mkdir -p "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$HERE/ootd</string>
    <string>--data-dir</string><string>$DATA</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/ootd.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/ootd.log</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "ootd now starts at login. Log: ~/Library/Logs/ootd.log"
