#!/usr/bin/env bash
# Deploys scripts/touchpad-inertia.py (tracked in this repo) to
# /usr/local/bin/, where touchpad-inertia.service actually runs it, then
# restarts the service. Run this after editing the script here.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/touchpad-inertia.py"
DEST="/usr/local/bin/touchpad-inertia.py"

sudo cp "$SRC" "$DEST"
sudo systemctl restart touchpad-inertia.service
sudo systemctl status touchpad-inertia.service --no-pager -l
