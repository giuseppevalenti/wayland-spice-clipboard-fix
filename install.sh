#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PKGS="wl-clipboard xclip spice-vdagent"

if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y $PKGS
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y $PKGS
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm $PKGS
elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y $PKGS
else
    echo "Unsupported package manager. Install manually: $PKGS" >&2
    exit 1
fi

sudo install -m 755 scripts/wayland-spice-clipboard /usr/local/bin/

mkdir -p ~/.config/systemd/user
install -m 644 systemd/wayland-spice-clipboard.service ~/.config/systemd/user/

sudo systemctl enable --now spice-vdagentd.service

systemctl --user daemon-reload
systemctl --user enable --now wayland-spice-clipboard.service

echo
echo "Installed. Status:"
systemctl --user --no-pager status wayland-spice-clipboard.service | head -5
