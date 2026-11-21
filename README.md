# bb-arm64

Automated Linux **ARM64 (`aarch64`)** AppImage builds of [get-bb/bb](https://github.com/get-bb/bb) with working **in-app auto-updates**.

Upstream `get-bb/bb` currently publishes Linux AppImages for `x86_64` only. This repository checks upstream every 6 hours, builds the native ARM64 AppImage on `ubuntu-22.04-arm` (glibc 2.35 baseline for cross-distro compatibility), and publishes it to GitHub Releases so `bb`'s built-in updater can replace itself in place.

## Install (any Linux ARM64 distro, no sudo)

```bash
curl -fsSL https://raw.githubusercontent.com/mturilin/bb-arm64/main/install.sh | bash
```

What this installs:
- `~/.local/share/bb/bb.AppImage` (user-writable fixed path so in-app auto-updates work)
- `~/.local/share/applications/bb.desktop` (configured with `--ozone-platform-hint=auto` for Wayland/X11)
- `~/.local/share/icons/hicolor/*/apps/bb.png`

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/mturilin/bb-arm64/main/install.sh | bash -s -- --uninstall
```

*(User data in `~/.bb` and `~/.config/bb` is preserved.)*

## How auto-updates work

1. `.github/workflows/build-arm64.yml` checks `get-bb/bb` every 6 hours for new `desktop-v*` releases.
2. When a new version appears, it builds the ARM64 AppImage with the update feed URL pointed to `https://github.com/mturilin/bb-arm64/releases/download/desktop-latest/`.
3. Inside `bb`, the built-in Electron auto-updater fetches `latest-linux-arm64.yml` and updates `~/.local/share/bb/bb.AppImage` automatically.
