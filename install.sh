#!/usr/bin/env bash
# What: Cross-distro, no-sudo installer and uninstaller for the bb Linux ARM64 AppImage.
# Why: Provides a zero-clone `curl | bash` install that integrates bb with the desktop launcher
#      and keeps the AppImage at a fixed user-writable path so Electron's built-in auto-updater works.
# Design notes:
#   - Verifies SHA-512 against latest-linux-arm64.yml from the rolling desktop-latest GitHub Release.
#   - Extracts bundled .desktop and hicolor icons via `--appimage-extract` (works even without FUSE mounted).
#   - Rewrites Exec= to pass `--ozone-platform-hint=auto` for native Wayland + X11 fallback and points to
#     the versionless path ~/.local/share/bb/bb.AppImage so in-place self-updates never break the shortcut.
# Gotchas:
#   - Running an AppImage requires FUSE (fuse3 / libfuse2) on the host; installer warns if missing.
#   - Only supports Linux aarch64/arm64; x86_64 users should use upstream get-bb/bb releases directly.

set -euo pipefail

REPO="${BB_ARM64_REPO:-mturilin/bb-arm64}"
RELEASE_BASE="https://github.com/${REPO}/releases/download/desktop-latest"
FEED_URL="${RELEASE_BASE}/latest-linux-arm64.yml"

APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bb"
APPIMAGE="${APP_DIR}/bb.AppImage"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="${APPS_DIR}/bb.desktop"
ICON_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

refresh_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d "$ICON_ROOT" ]]; then
    gtk-update-icon-cache -f "$ICON_ROOT" >/dev/null 2>&1 || true
  fi
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  fi
}

uninstall_bb() {
  echo "Uninstalling bb ARM64 AppImage..."
  rm -f "$APPIMAGE" "$DESKTOP_FILE"
  rmdir "$APP_DIR" 2>/dev/null || true
  find "$ICON_ROOT" -type f -name 'bb.png' -delete 2>/dev/null || true
  refresh_caches
  echo "Done. User data in ~/.bb and ~/.config/bb was left intact."
  exit 0
}

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "uninstall" ]]; then
  uninstall_bb
fi

arch="$(uname -m)"
if [[ "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
  echo "Error: this installer is for Linux ARM64 (aarch64), detected '${arch}'." >&2
  echo "For x86_64 Linux, use upstream releases: https://github.com/get-bb/bb/releases/tag/desktop-latest" >&2
  exit 1
fi

for cmd in curl openssl base64; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '${cmd}' is not installed." >&2
    exit 1
  fi
done

exec_unsafe='["`$\\|&]'
if [[ "$APPIMAGE" =~ $exec_unsafe ]]; then
  echo "Error: install path contains characters unsafe for a .desktop Exec line: $APPIMAGE" >&2
  exit 1
fi

work="$(mktemp -d)"
mkdir -p "$APP_DIR"
download="${APP_DIR}/.bb.AppImage.download"
trap 'rm -rf "$work" "$download"' EXIT

echo "Fetching latest release metadata from ${REPO}..."
curl -fsSL --retry 3 "$FEED_URL" -o "$work/feed.yml"

version="$(sed -n 's/^version: *//p' "$work/feed.yml" | head -n 1 | tr -d "\"'\r")"
file="$(sed -n 's/^path: *//p' "$work/feed.yml" | head -n 1 | tr -d "\"'\r")"
sha512="$(sed -n 's/^sha512: *//p' "$work/feed.yml" | head -n 1 | tr -d "\"'\r")"

if [[ -z "$version" || -z "$sha512" || ! "$file" =~ ^bb-[A-Za-z0-9._-]+\.AppImage$ ]]; then
  echo "Error: release feed at ${FEED_URL} did not match expected format." >&2
  exit 1
fi

echo "Downloading bb ${version} (${file})..."
curl -fL --retry 3 --progress-bar "${RELEASE_BASE}/${file}" -o "$download"

actual_sha512="$(openssl dgst -sha512 -binary "$download" | base64 -w0)"
if [[ "$actual_sha512" != "$sha512" ]]; then
  echo "Error: SHA-512 checksum mismatch for ${file}." >&2
  exit 1
fi
chmod 755 "$download"

echo "Extracting desktop entry and icons..."
(
  cd "$work"
  "$download" --appimage-extract '*.desktop' >/dev/null 2>&1 || true
  "$download" --appimage-extract 'usr/share/icons/hicolor/*/apps/*.png' >/dev/null 2>&1 || true
  "$download" --appimage-extract 'bb.png' >/dev/null 2>&1 || true
)

installed_icon=false
rm -f "${ICON_ROOT}/1024x1024/apps/bb.png"
shopt -s nullglob
for icon in "$work"/squashfs-root/usr/share/icons/hicolor/*/apps/*.png; do
  rel="${icon#"$work/squashfs-root/usr/share/icons/hicolor/"}"
  size="${rel%%/*}"
  # hicolor's index.theme tops out at 512x512; 1024x1024 is ignored by KDE/KRunner.
  [[ "$size" == "1024x1024" ]] && size="512x512"
  install -Dm644 "$icon" "${ICON_ROOT}/${size}/apps/bb.png"
  installed_icon=true
done
if [[ "$installed_icon" == "false" && -f "$work/squashfs-root/bb.png" ]]; then
  install -Dm644 "$work/squashfs-root/bb.png" "${ICON_ROOT}/512x512/apps/bb.png"
fi

mkdir -p "$APPS_DIR"
exec_path="${APPIMAGE//%/%%}"
extracted_desktop=("$work"/squashfs-root/*.desktop)
if (( ${#extracted_desktop[@]} > 0 )); then
  sed \
    -e "s|^Exec=.*|Exec=\"${exec_path}\" --ozone-platform-hint=auto %U\nTryExec=${APPIMAGE}|" \
    -e "s|^Icon=.*|Icon=bb|" \
    -e '/^X-AppImage-Version=/d' \
    "${extracted_desktop[0]}" > "$work/bb.desktop"
  if ! grep -q '^StartupWMClass=' "$work/bb.desktop"; then
    printf 'StartupWMClass=bb\n' >> "$work/bb.desktop"
  fi
  install -Dm644 "$work/bb.desktop" "$DESKTOP_FILE"
else
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=bb
Comment=Agentic IDE that builds itself
Exec="${exec_path}" --ozone-platform-hint=auto %U
TryExec=${APPIMAGE}
Icon=bb
Terminal=false
Categories=Development;IDE;
StartupWMClass=bb
StartupNotify=true
EOF
fi

mv -f "$download" "$APPIMAGE"
refresh_caches

echo ""
echo "Installed bb ${version} to ${APPIMAGE}"
echo "Desktop launcher: ${DESKTOP_FILE}"
echo "Future updates will happen automatically inside bb."

if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
  echo ""
  echo "Note: FUSE (fusermount3/fusermount) was not detected. AppImages need FUSE to run"
  echo "(e.g. 'sudo pacman -S fuse3' on Arch or 'sudo apt install libfuse2' on Ubuntu/Debian)."
fi
