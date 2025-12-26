#!/usr/bin/env bash
set -euo pipefail

HELP_CRACK_URL="https://wpa-sec.stanev.org/hc/help_crack.py"
HELP_CRACK_PATH="/opt/help_crack/help_crack.py"

mkdir -p /opt/help_crack
curl -fsSL "${HELP_CRACK_URL}" -o "${HELP_CRACK_PATH}"

exec python3 "${HELP_CRACK_PATH}" "$@"
