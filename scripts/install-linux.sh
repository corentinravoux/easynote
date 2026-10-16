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
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"

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

mkdir -p "$(dirname "$dest")" "$apps" "$icons"
rm -rf "$dest.new"
cp -a "$src" "$dest.new"
rm -rf "$dest"
mv "$dest.new" "$dest"

icon_src="$here/assets/icon/easynote.png"
[[ -f "$icon_src" ]] || icon_src="$dest/data/flutter_assets/assets/icon/easynote.png"
cp "$icon_src" "$icons/easynote.png"

cat > "$apps/easynote.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=easynote
Comment=Notes synced to a GitHub repository
Exec=$dest/easynote
Icon=easynote
Terminal=false
Categories=Office;Utility;
StartupWMClass=io.easynote.app
DESKTOP

update-desktop-database "$apps" >/dev/null 2>&1 || true
gtk-update-icon-cache -q "$(dirname "$(dirname "$icons")")" >/dev/null 2>&1 || true
echo "Installed to $dest. Launch easynote from the applications menu."
