#!/bin/bash
# ============================================================
# La Pieuvre — Watchdog
# Vérifie que l'infra tourne, relance si nécessaire
# Exécuté toutes les 5 minutes via cron
# ============================================================

LOG="/home/ubuntu/scripts/watchdog.log"
HISTORY="/home/ubuntu/command_history.txt"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# PostgreSQL
if ! docker ps --format '{{.Names}}' | grep -q pieuvre-postgres; then
  echo "[$(ts)] [WARN] PostgreSQL down — relancement..." >> "$LOG"
  echo "[$(ts)] docker compose up -d postgres (watchdog)" >> "$HISTORY"
  cd /home/ubuntu/infra && docker compose up -d postgres
fi

# MongoDB
if ! docker ps --format '{{.Names}}' | grep -q pieuvre-mongo; then
  echo "[$(ts)] [WARN] MongoDB down — relancement..." >> "$LOG"
  echo "[$(ts)] docker compose up -d mongo (watchdog)" >> "$HISTORY"
  cd /home/ubuntu/infra && docker compose up -d mongo
fi

# Dozzle
if ! docker ps --format '{{.Names}}' | grep -q pieuvre-dozzle; then
  echo "[$(ts)] [WARN] Dozzle down — relancement..." >> "$LOG"
  echo "[$(ts)] docker compose up -d dozzle (watchdog)" >> "$HISTORY"
  cd /home/ubuntu/infra && docker compose up -d dozzle
fi

# Session tmux pieuvre
if ! tmux has-session -t pieuvre 2>/dev/null; then
  echo "[$(ts)] [WARN] Session tmux 'pieuvre' absente — recréation..." >> "$LOG"
  echo "[$(ts)] tmux new-session -d -s pieuvre (watchdog)" >> "$HISTORY"
  tmux new-session -d -s pieuvre -n claude
  tmux new-window -t pieuvre -n shell
  tmux new-window -t pieuvre -n logs
  tmux send-keys -t pieuvre:logs 'cd /home/ubuntu/infra && docker compose logs -f' Enter
fi

# Tailscale
if command -v tailscale &> /dev/null; then
  if ! tailscale status > /dev/null 2>&1; then
    echo "[$(ts)] [WARN] Tailscale down — reconnexion..." >> "$LOG"
    echo "[$(ts)] tailscale up (watchdog)" >> "$HISTORY"
    tailscale up
  fi
fi
