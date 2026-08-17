#!/usr/bin/env bash
# ============================================================
# NFC-Kasse -- Backend Starter (Linux / macOS)
# Reads settings from config.env next to this file.
# Run this in a terminal before starting the app.
#
# Prerequisites (one-time setup):
#   pip install -r backend/requirements.txt
# ============================================================

set -e
cd "$(dirname "$0")"

echo ""
echo " ================================================"
echo "  NFC-Kasse Backend"
echo " ================================================"
echo ""

# ---- Load config.env ----------------------------------------
if [ ! -f "config.env" ]; then
    echo " [ERROR] config.env not found next to this script."
    echo " Copy config.env and edit it, then run again."
    exit 1
fi

# Export every KEY=VALUE line; skip comments (#) and blank lines.
set -a
# shellcheck disable=SC1091
source config.env
set +a

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

if [ -z "${SECRET_KEY:-}" ]; then
    echo " [ERROR] SECRET_KEY is not set in config.env."
    exit 1
fi

# ---- Database -----------------------------------------------
cd backend
if [ ! -f "kasse.db" ]; then
    echo " [SETUP] kasse.db not found -- creating database ..."
    python3 init_db.py
    echo ""
    echo " [SETUP] Done. Default login: admin / admin"
    echo " [SETUP] Change the password immediately after first login!"
    echo ""
else
    echo " [OK] kasse.db found."
fi
cd ..

# ---- Network info -------------------------------------------
echo ""
# ip route get picks the source IP for the default route — reliable even with many interfaces.
LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
if [ -z "$LAN_IP" ]; then
    # Fallback: first non-loopback IPv4 address
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

if [ -n "$LAN_IP" ]; then
    echo " Backend URL: http://${LAN_IP}:${PORT}"
else
    echo " Backend URL: [could not detect IP -- check 'ip addr' manually]"
fi
echo " Local URL:   http://localhost:${PORT}"
echo " API Docs:    http://localhost:${PORT}/docs"
echo ""
echo " Press Ctrl+C to stop the server."
echo " ================================================"
echo ""

# ---- Start server -------------------------------------------
cd backend
export SECRET_KEY
python3 -m uvicorn main:app --host "$HOST" --port "$PORT" --reload
