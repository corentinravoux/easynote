#!/usr/bin/env bash
# Install easynote for the current user.
#
#   scripts/install-linux.sh                         # from a local `flutter build linux --release`
#   scripts/install-linux.sh easynote-v1.0.0-linux-x64.tar.gz   # from a release download
#
# Safe to run again to update: the app directory is replaced, notes and
# settings (in ~/.local/share/io.easynote.app) are not touched.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/easynote/app"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
hicolor="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

src="${1:-$here/build/linux/x64/release/bundle}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -f "$src" ]]; then
  tar -xzf "$src" -C "$tmp"
  src="$tmp/bundle"
fi
if [[ ! -x "$src/easynote" ]]; then
  echo "No easynote bundle at $src. Build it with: flutter build linux --release" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")" "$apps"
rm -rf "$dest.new"
cp -a "$src" "$dest.new"
rm -rf "$dest"
mv "$dest.new" "$dest"

# Icons: the scalable SVG when the repository is at hand, and the bundled PNG
# (always present) at 512 px. The icon name matches the application id.
png="$dest/data/flutter_assets/assets/icon/easynote.png"
mkdir -p "$hicolor/512x512/apps"
cp "$png" "$hicolor/512x512/apps/io.easynote.app.png"
if [[ -f "$here/assets/icon/easynote.svg" ]]; then
  mkdir -p "$hicolor/scalable/apps"
  cp "$here/assets/icon/easynote.svg" "$hicolor/scalable/apps/io.easynote.app.svg"
fi
rm -f "$hicolor/512x512/apps/easynote.png" "$apps/easynote.desktop"  # older installs

# Named after the application id, which GNOME uses to match the window.
cat > "$apps/io.easynote.app.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=easynote
Comment=Notes synced to a GitHub repository
Exec=$dest/easynote
Icon=io.easynote.app
Terminal=false
Categories=Office;Utility;
StartupWMClass=io.easynote.app
DESKTOP

update-desktop-database "$apps" >/dev/null 2>&1 || true
gtk-update-icon-cache -q -t "$hicolor" >/dev/null 2>&1 || true
echo "Installed to $dest. Launch easynote from the applications menu."
