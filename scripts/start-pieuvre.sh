#!/bin/bash
# ============================================================
# La Pieuvre — Script de démarrage complet
# Lance toute l'infra + session tmux + Remote Control
# Usage : ./start-pieuvre.sh
# ============================================================

set -e
LOG="/home/ubuntu/scripts/start-pieuvre.log"
HISTORY="/home/ubuntu/command_history.txt"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }
hist() { echo "[$(ts)] $*" >> "$HISTORY"; }

log "🐙 Démarrage de La Pieuvre..."

# 1. Infra Docker
log "→ Lancement infra (PG + Mongo + PgAdmin + Mongo Express + Dozzle)..."
hist "docker compose up -d (start-pieuvre.sh)"
cd /home/ubuntu/infra && docker compose up -d
log "→ Infra lancée."

# 2. Attendre PostgreSQL
log "→ Attente PostgreSQL ready..."
until docker exec pieuvre-postgres pg_isready -U pieuvre > /dev/null 2>&1; do
  sleep 1
done
log "→ PostgreSQL prêt."

# 3. Session tmux pieuvre
log "→ Création session tmux 'pieuvre'..."
hist "tmux new-session -d -s pieuvre (start-pieuvre.sh)"
tmux kill-session -t pieuvre 2>/dev/null || true
tmux new-session -d -s pieuvre -n claude
tmux new-window -t pieuvre -n shell
tmux new-window -t pieuvre -n logs
tmux send-keys -t pieuvre:logs 'cd /home/ubuntu/infra && docker compose logs -f' Enter
tmux select-window -t pieuvre:claude
log "→ Session tmux prête (3 fenêtres : claude / shell / logs)."

# 4. Tailscale (si installé)
if command -v tailscale &> /dev/null; then
  tailscale status > /dev/null 2>&1 && log "→ Tailscale: déjà connecté ($(tailscale ip -4))" || log "→ Tailscale: non connecté, lance 'tailscale up' manuellement."
else
  log "→ Tailscale non installé (Phase 4)."
fi

log "🐙 La Pieuvre est opérationnelle !"
log "   tmux attach -t pieuvre   → pour rejoindre la session"
log "   Dozzle   → http://IP:9999"
log "   PgAdmin  → http://IP:5050  (dev@pieuvre.dev / PieuvreAdmin2024!)"
log "   Mongo    → http://IP:8081"

# VPN Touriz — route spécifique pour le serveur OVH (DB migration)
if ip link show tun0 > /dev/null 2>&1; then
  ip route add 54.37.150.133 via 192.168.255.41 dev tun0 2>/dev/null || true
  DOCKER_NET=$(docker network inspect touriz_default --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
  [ -n "$DOCKER_NET" ] && iptables -t nat -A POSTROUTING -s $DOCKER_NET -o tun0 -j MASQUERADE 2>/dev/null || true
fi
