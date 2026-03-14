#!/bin/bash
set -e

echo "🐙 La Pieuvre — VPS Setup"
echo "========================="
echo ""

# ─── 1. Create .env files from examples ─────────────
for dir in pieuvre-cockpit infra; do
  if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "Created $dir/.env from .env.example — EDIT IT with real values!"
  fi
done

# ─── 2. Install cockpit dependencies ────────────────
echo ""
echo "Installing cockpit API dependencies..."
cd pieuvre-cockpit/api && npm install && cd ../..

echo "Installing cockpit frontend dependencies..."
cd pieuvre-cockpit/front && npm install && cd ../..

echo "Installing docs dependencies (if any)..."
cd pieuvre-cockpit/docs && npm install 2>/dev/null; cd ../..

# ─── 3. Start infra containers ──────────────────────
echo ""
echo "Starting infrastructure containers..."
cd infra && docker compose up -d && cd ..

# ─── 4. Run cockpit DB migrations ───────────────────
echo ""
echo "Running cockpit database migrations..."
cd pieuvre-cockpit && node api/services/db.js 2>/dev/null; cd ..

# ─── 5. Setup pm2 ───────────────────────────────────
echo ""
echo "Setting up pm2 processes..."

# MCP servers
pm2 start pieuvre-cockpit/api/server.js --name cockpit --cwd pieuvre-cockpit 2>/dev/null || pm2 restart cockpit
pm2 start pieuvre-cockpit/docs/server.js --name docs --cwd pieuvre-cockpit/docs 2>/dev/null || pm2 restart docs

pm2 save

echo ""
echo "========================================="
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Edit pieuvre-cockpit/.env with your Atlassian/Bitbucket credentials"
echo "  2. Edit infra/.env with your database passwords"
echo "  3. Clone your project(s) into Projects/"
echo "  4. Start MCP servers (see CLAUDE.md for pm2 commands)"
echo "  5. Access cockpit at http://localhost:8888"
echo "  6. Access docs at http://localhost:7777"
echo "========================================="
