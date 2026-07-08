#!/bin/bash
# Installs ram-sentinel.sh as a systemd --user service, so it survives
# logout/reboot and auto-restarts on failure, instead of relying on
# `nohup ... &` (which dies with the parent shell/session).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$BIN_DIR" "$UNIT_DIR"
cp "$SCRIPT_DIR/ram-sentinel.sh" "$BIN_DIR/ram-sentinel.sh"
chmod +x "$BIN_DIR/ram-sentinel.sh"
cp "$SCRIPT_DIR/systemd/ram-sentinel.service" "$UNIT_DIR/ram-sentinel.service"

systemctl --user daemon-reload
systemctl --user enable --now ram-sentinel.service

echo "Installed and started. Useful commands:"
echo "  systemctl --user status ram-sentinel"
echo "  journalctl --user -u ram-sentinel -f"
echo "  systemctl --user stop ram-sentinel"
echo ""
echo "Edit $UNIT_DIR/ram-sentinel.service to change flags (threshold, interval, -n for headless),"
echo "then: systemctl --user daemon-reload && systemctl --user restart ram-sentinel"
