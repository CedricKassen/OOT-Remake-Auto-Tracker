#!/bin/bash
# Packs a Flutter Linux bundle into a single-file AppImage.
#
#   tools/appimage/make.sh <bundle folder> <executable name> <display name> <output.AppImage>
#
# Needs appimagetool on the PATH or as $APPIMAGETOOL (the release workflow
# downloads it). The bundle folder is copied, not changed.
set -euo pipefail

bundle="$1" exe="$2" name="$3" output="$4"
here="$(cd "$(dirname "$0")" && pwd)"
tool="${APPIMAGETOOL:-appimagetool}"

appdir="$(mktemp -d)/AppDir"
mkdir -p "$appdir"
cp -a "$bundle/." "$appdir/"
[ -x "$appdir/$exe" ] || { echo "No executable $exe in $bundle" >&2; exit 66; }

cp "$here/icon.png" "$appdir/$exe.png"
cat > "$appdir/$exe.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Exec=$exe
Icon=$exe
Categories=Game;Utility;
Terminal=false
DESKTOP

# What the AppImage runs: the app from wherever the image is mounted.
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/@EXE@" "$@"
APPRUN
sed -i "s/@EXE@/$exe/" "$appdir/AppRun"
chmod +x "$appdir/AppRun"

# --appimage-extract-and-run: build machines usually have no FUSE.
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$output"
chmod +x "$output"
echo "Wrote $output"
