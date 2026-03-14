# 🐙 La Pieuvre — Guide de Setup Complet

> **Objectif** : Transformer un VPS Hostinger KVM 8 en station de développement pilotable à distance depuis un téléphone, grâce à Claude Code Remote Control.

---

## RÈGLE ABSOLUE — Historique des commandes

> **Claude Code DOIT écrire dans `/root/command_history.txt` CHAQUE commande qu'il exécute**, sans exception.
> Format : `[DATE HEURE] COMMANDE`
> Objectif : en cas de réinstallation, rejouer tout le setup depuis ce fichier suffit.
> Ce fichier est la mémoire d'or du VPS.

---

## Sommaire

1. [Architecture globale](#1-architecture-globale)
2. [Prérequis](#2-prérequis)
3. [Phase 1 — Setup système du VPS](#3-phase-1--setup-système-du-vps)
4. [Phase 2 — Docker & Infra partagée](#4-phase-2--docker--infra-partagée)
5. [Phase 3 — Claude Code & Remote Control](#5-phase-3--claude-code--remote-control)
6. [Phase 4 — Tailscale (réseau privé)](#6-phase-4--tailscale-réseau-privé)
7. [Phase 5 — Intégrations MCP](#7-phase-5--intégrations-mcp)
8. [Phase 6 — Structure des projets](#8-phase-6--structure-des-projets)
9. [Phase 7 — Monitoring & Logs (Dozzle + Monolog)](#9-phase-7--monitoring--logs-dozzle--monolog)
10. [Phase 8 — Debug API (curl comme Postman)](#10-phase-8--debug-api-curl-comme-postman)
11. [Phase 9 — Watchdog & Résilience](#11-phase-9--watchdog--résilience)
12. [Phase 10 — CLAUDE.md du projet](#12-phase-10--claudemd-du-projet)
13. [Workflows quotidiens](#13-workflows-quotidiens)
14. [Maintenance & Troubleshooting](#14-maintenance--troubleshooting)
15. [Checklist de validation](#15-checklist-de-validation)

---

## 1. Architecture globale

```
┌─────────────────────────────────────────────────────────────────┐
│                    VPS Hostinger KVM 8                           │
│                 Debian 12 · 8 vCPU · 32 Go RAM · 400 Go NVMe   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    INFRA PARTAGÉE                         │   │
│  │   PostgreSQL 16 (1 instance, N bases)                     │   │
│  │   MongoDB 7 (1 instance, N bases)                         │   │
│  │   Réseau Docker : pieuvre-net                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐     │
│  │ Agence Projet 1│  │ Agence Projet 2│  │ Client Fullstack│    │
│  │ Symfony API    │  │ Symfony API    │  │ Nuxt + Symfony  │    │
│  │ :8001          │  │ :8002          │  │ :3000 + :8000   │    │
│  └────────────────┘  └────────────────┘  └────────────────┘     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │   Claude Code + Remote Control (dans tmux)                │   │
│  │   MCP Servers : JIRA · Bitbucket · Filesystem             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │  Tailscale   │  │   Dozzle     │ ◄── Logs temps réel :9999  │
│  └──────────────┘  └──────────────┘                             │
│  │  Tailscale   │ ◄──── Réseau privé ────► 📱 Téléphone        │
│  └──────────────┘                          💻 Laptop (backup)   │
└─────────────────────────────────────────────────────────────────┘

Pilotage :
  📱 App Claude (iOS/Android) → claude.ai/code → Remote Control Session
  📱 Safari/Chrome (téléphone) → http://100.x.x.x:3000 (front Nuxt via Tailscale)
  💻 Laptop → SSH + tmux attach (dernier recours)
```

---

## 2. Prérequis

### Comptes nécessaires

| Service | Usage | Coût |
|---------|-------|------|
| Hostinger KVM 8 | VPS principal | 21,99 €/mois (promo) |
| Anthropic Max | Claude Code + Remote Control | ~100 $/mois |
| Tailscale | Réseau privé VPS ↔ téléphone | Gratuit (perso) |
| Atlassian (JIRA) | Tickets client | Existant |
| Bitbucket | Repos Git | Existant |

### Sur ton téléphone

- App Claude (iOS ou Android) — dernière version
- App Tailscale
- Un navigateur (Safari / Chrome)

### Sur ton laptop (backup)

- Client SSH
- Tailscale
- Un navigateur

---

## 3. Phase 1 — Setup système du VPS

### 3.1 Première connexion

```bash
# Connexion initiale (depuis ton laptop)
ssh root@IP_DU_VPS

# Mise à jour système
apt update && apt upgrade -y

# Packages essentiels
apt install -y \
  curl wget git tmux htop unzip jq \
  build-essential python3 python3-pip \
  ca-certificates gnupg lsb-release \
  fail2ban ufw
```

### 3.2 Créer un utilisateur dédié

```bash
# Ne jamais travailler en root
adduser dev
usermod -aG sudo dev

# Copier la clé SSH
mkdir -p /home/dev/.ssh
cp ~/.ssh/authorized_keys /home/dev/.ssh/
chown -R dev:dev /home/dev/.ssh
chmod 700 /home/dev/.ssh
chmod 600 /home/dev/.ssh/authorized_keys

# Désactiver le login root SSH (optionnel mais recommandé)
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd
```

### 3.3 Firewall de base

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw enable
```

> **Note** : On n'ouvre PAS de ports publics pour les services de dev. Tout passera par Tailscale.

### 3.4 Installer Node.js 22+

```bash
# En tant que user dev
su - dev

# Via nvm (recommandé pour Claude Code)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 22
nvm alias default 22
node -v  # Doit afficher v22.x.x
```

### 3.5 Installer Docker

```bash
# En tant que root ou avec sudo
curl -fsSL https://get.docker.com | sh
usermod -aG docker dev

# Docker Compose est inclus dans Docker moderne
docker compose version  # Vérification
```

### 3.6 Configurer tmux

```bash
# En tant que dev
cat > ~/.tmux.conf << 'EOF'
# Garder un historique long
set -g history-limit 50000

# Permettre le scroll avec la souris (utile en SSH depuis laptop)
set -g mouse on

# Commencer la numérotation à 1
set -g base-index 1

# Reconnexion automatique
set -g remain-on-exit on

# Status bar informative
set -g status-right '#[fg=green]#H #[fg=white]%H:%M'
set -g status-interval 30

# Garder les variables d'environnement
set -g update-environment "SSH_AUTH_SOCK SSH_CONNECTION"
EOF
```

---

## 4. Phase 2 — Docker & Infra partagée

### 4.1 Arborescence

```bash
mkdir -p ~/infra
mkdir -p ~/agence/projet-1
mkdir -p ~/agence/projet-2
mkdir -p ~/touriz
mkdir -p ~/scripts
```

### 4.2 Docker Compose — Infra partagée

```bash
cat > ~/infra/docker-compose.yml << 'EOF'
services:
  postgres:
    image: postgres:16
    container_name: pieuvre-postgres
    restart: unless-stopped
    ports:
      - "0.0.0.0:5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init-databases.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      POSTGRES_USER: pieuvre
      POSTGRES_PASSWORD: ${PG_PASSWORD:-changeme_en_prod}
    networks:
      - pieuvre-net
    shm_size: '256mb'
    # Tuning pour 32 Go RAM (environ 8 Go alloués à PG max)
    command: >
      postgres
        -c shared_buffers=2GB
        -c effective_cache_size=6GB
        -c work_mem=64MB
        -c maintenance_work_mem=512MB
        -c max_connections=200

  mongo:
    image: mongo:7
    container_name: pieuvre-mongo
    restart: unless-stopped
    ports:
      - "0.0.0.0:27017:27017"
    volumes:
      - mongo_data:/data/db
    environment:
      MONGO_INITDB_ROOT_USERNAME: pieuvre
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD:-changeme_en_prod}
    networks:
      - pieuvre-net

  # Interface web pour PostgreSQL (accessible via Tailscale)
  pgadmin:
    image: dpage/pgadmin4
    container_name: pieuvre-pgadmin
    restart: unless-stopped
    ports:
      - "0.0.0.0:5050:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: dev@pieuvre.local
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD:-admin}
    networks:
      - pieuvre-net

  # Interface web pour MongoDB (accessible via Tailscale)
  mongo-express:
    image: mongo-express
    container_name: pieuvre-mongo-express
    restart: unless-stopped
    ports:
      - "0.0.0.0:8081:8081"
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: pieuvre
      ME_CONFIG_MONGODB_ADMINPASSWORD: ${MONGO_PASSWORD:-changeme_en_prod}
      ME_CONFIG_MONGODB_URL: mongodb://pieuvre:${MONGO_PASSWORD:-changeme_en_prod}@mongo:27017/
    depends_on:
      - mongo
    networks:
      - pieuvre-net

  # Monitoring des logs de TOUS les containers en temps réel
  dozzle:
    image: amir20/dozzle:latest
    container_name: pieuvre-dozzle
    restart: unless-stopped
    ports:
      - "0.0.0.0:9999:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      DOZZLE_LEVEL: info
      DOZZLE_ENABLE_ACTIONS: "true"

networks:
  pieuvre-net:
    name: pieuvre-net
    driver: bridge

volumes:
  pg_data:
  mongo_data:
EOF
```

### 4.3 Script d'init des bases PostgreSQL

```bash
cat > ~/infra/init-databases.sql << 'EOF'
-- Bases pour l'agence web
CREATE DATABASE agence_projet1;
CREATE DATABASE agence_projet2;

-- Base pour le projet Touriz
CREATE DATABASE touriz;

-- Créer un user par projet (optionnel mais recommandé)
CREATE USER agence WITH PASSWORD 'agence_password';
CREATE USER client WITH PASSWORD 'client_password';

GRANT ALL PRIVILEGES ON DATABASE agence_projet1 TO agence;
GRANT ALL PRIVILEGES ON DATABASE agence_projet2 TO agence;
GRANT ALL PRIVILEGES ON DATABASE touriz TO client;
EOF
```

### 4.4 Fichier d'environnement

```bash
cat > ~/infra/.env << 'EOF'
PG_PASSWORD=ton_vrai_mdp_pg
MONGO_PASSWORD=ton_vrai_mdp_mongo
PGADMIN_PASSWORD=ton_vrai_mdp_pgadmin
EOF

chmod 600 ~/infra/.env
```

### 4.5 Lancer l'infra

```bash
cd ~/infra
docker compose up -d

# Vérifier que tout tourne
docker compose ps
docker exec pieuvre-postgres psql -U pieuvre -l  # Lister les bases
```

---

## 5. Phase 3 — Claude Code & Remote Control

### 5.1 Installer Claude Code

```bash
# En tant que dev
npm install -g @anthropic-ai/claude-code
```

### 5.2 Authentification (nécessite ton laptop la première fois)

L'authentification OAuth nécessite un navigateur. Depuis le VPS headless, utiliser le port forwarding SSH :

```bash
# Sur ton LAPTOP (pas le VPS)
ssh -L 8080:localhost:8080 dev@IP_DU_VPS

# Puis sur le VPS (dans la session SSH)
claude /login
# Claude va afficher une URL localhost:8080/...
# Ouvre cette URL dans le navigateur de ton laptop
# Connecte-toi avec ton compte Anthropic Max
```

### 5.3 Lancer Remote Control dans tmux

```bash
# Sur le VPS
tmux new-session -d -s pieuvre

# Fenêtre 0 : Claude Code Remote Control
tmux send-keys -t pieuvre:0 'cd ~/touriz && claude remote-control' Enter

# Fenêtre 1 : Shell libre pour commandes manuelles
tmux new-window -t pieuvre
tmux send-keys -t pieuvre:1 'cd ~' Enter

# Fenêtre 2 : Logs Docker
tmux new-window -t pieuvre
tmux send-keys -t pieuvre:2 'cd ~/infra && docker compose logs -f' Enter
```

### 5.4 Vérifier depuis le téléphone

1. Ouvre l'app Claude sur ton téléphone
2. Va dans l'onglet **Code**
3. Tu devrais voir **"Remote Control Session (nom-du-vps)"**
4. Tape un message test : "Liste les fichiers dans le répertoire home"

---

## 6. Phase 4 — Tailscale (réseau privé)

### 6.1 Installer sur le VPS

```bash
# En tant que root
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Afficher l'IP Tailscale du VPS
tailscale ip -4
# Exemple : 100.64.0.1
```

### 6.2 Installer sur ton téléphone

1. Télécharge Tailscale sur l'App Store / Play Store
2. Connecte-toi avec le même compte
3. Ton téléphone obtient une IP 100.x.x.x

### 6.3 Installer sur ton laptop (backup)

```bash
# Ubuntu
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

### 6.4 Tester l'accès

Depuis ton téléphone, ouvre un navigateur :

| URL | Service |
|-----|---------|
| `http://100.x.x.x:3000` | Front Nuxt (Touriz) |
| `http://100.x.x.x:8000` | API Symfony (Touriz) |
| `http://100.x.x.x:8001` | API Symfony (agence projet 1) |
| `http://100.x.x.x:8002` | API Symfony (agence projet 2) |
| `http://100.x.x.x:5050` | PgAdmin |
| `http://100.x.x.x:8081` | Mongo Express |
| `http://100.x.x.x:9999` | **Dozzle** (logs temps réel de tous les containers) |

> **Remplace `100.x.x.x` par l'IP Tailscale de ton VPS.**

---

## 7. Phase 5 — Intégrations MCP

Les MCP Servers permettent à Claude Code d'interagir directement avec tes outils.

### 7.1 Config Claude Code (settings)

Crée ou édite le fichier de config MCP de Claude Code :

```bash
mkdir -p ~/.claude

cat > ~/.claude/settings.json << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(docker *)",
      "Bash(git *)",
      "Bash(cd *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(grep *)",
      "Bash(find *)",
      "Bash(npm *)",
      "Bash(composer *)",
      "Bash(php *)",
      "Bash(psql *)",
      "Bash(mongosh *)",
      "Bash(curl *)",
      "Bash(tmux *)"
    ]
  },
  "mcpServers": {
    "jira": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-jira"],
      "env": {
        "JIRA_URL": "https://ton-instance.atlassian.net",
        "JIRA_EMAIL": "ton-email@example.com",
        "JIRA_API_TOKEN": "ton-token-jira"
      }
    },
    "bitbucket": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-bitbucket"],
      "env": {
        "BITBUCKET_WORKSPACE": "ton-workspace",
        "BITBUCKET_USERNAME": "ton-username",
        "BITBUCKET_APP_PASSWORD": "ton-app-password"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/dev"]
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://pieuvre:ton_mdp@localhost:5432/touriz"
      }
    }
  }
}
SETTINGS
```

> **⚠️ Important** : les noms de packages MCP ci-dessus sont indicatifs. Vérifie les packages MCP officiels disponibles au moment de l'install sur [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) et sur le marketplace Anthropic.

### 7.2 Obtenir les tokens

**JIRA :**
1. Va sur https://id.atlassian.com/manage-profile/security/api-tokens
2. Crée un token API

**Bitbucket :**
1. Va sur https://bitbucket.org/account/settings/app-passwords/
2. Crée un App Password avec les permissions : Repositories (read/write), Pull Requests (read/write)

---

## 8. Phase 6 — Structure des projets

### 8.1 Exemple docker-compose — Projet agence (API Symfony)

```yaml
# ~/agence/projet-1/docker-compose.yml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: agence-projet1-api
    restart: unless-stopped
    ports:
      - "0.0.0.0:8001:80"
    volumes:
      - .:/var/www/html
    environment:
      DATABASE_URL: postgresql://agence:agence_password@pieuvre-postgres:5432/agence_projet1
      APP_ENV: dev
    networks:
      - pieuvre-net
    depends_on: []  # PG est dans l'infra séparée

networks:
  pieuvre-net:
    external: true
```

### 8.2 Exemple docker-compose — Client fullstack (Nuxt + Symfony)

```yaml
# ~/touriz/docker-compose.yml
services:
  front:
    build:
      context: ./front
      dockerfile: Dockerfile
    container_name: client-front
    restart: unless-stopped
    ports:
      - "0.0.0.0:3000:3000"
    volumes:
      - ./front:/app
      - /app/node_modules
    environment:
      NUXT_PUBLIC_API_URL: http://localhost:8000
    networks:
      - pieuvre-net
    command: npm run dev

  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: client-api
    restart: unless-stopped
    ports:
      - "0.0.0.0:8000:80"
    volumes:
      - ./api:/var/www/html
    environment:
      DATABASE_URL: postgresql://client:client_password@pieuvre-postgres:5432/touriz
      MONGODB_URL: mongodb://pieuvre:${MONGO_PASSWORD}@pieuvre-mongo:27017/touriz
      APP_ENV: dev
    networks:
      - pieuvre-net

networks:
  pieuvre-net:
    external: true
```

### 8.3 Cloner les repos

```bash
# Agence
cd ~/agence
git clone git@bitbucket.org:workspace/projet-1.git
git clone git@bitbucket.org:workspace/projet-2.git

# Client fullstack
cd ~/touriz
git clone git@bitbucket.org:workspace/client-app.git .
```

> Pense à configurer ta clé SSH sur le VPS pour Bitbucket : `ssh-keygen -t ed25519` puis ajouter la clé publique dans Bitbucket.

---

## 9. Phase 7 — Monitoring & Logs (Dozzle + Monolog)

### 9.1 Dozzle — Interface logs temps réel

Dozzle est déjà inclus dans le `docker-compose.yml` de l'infra partagée (Phase 2). Il monte le socket Docker en lecture seule et affiche les logs de **tous** les containers en temps réel dans une interface web.

**Accès depuis le téléphone :** `http://100.x.x.x:9999` (via Tailscale)

**Ce que tu peux faire depuis ton téléphone :**
- Voir les logs de tous les containers simultanément ou filtrer par container
- Rechercher une erreur par mot-clé (ex: "500", "SQLSTATE", "TypeError")
- Voir les logs en temps réel avec auto-scroll
- Filtrer par niveau (error, warning, info)
- Télécharger les logs d'un container

### 9.2 Configurer Monolog (Symfony) pour des logs structurés

Pour que les logs Symfony soient lisibles dans Dozzle et exploitables par Claude Code, configure Monolog pour écrire en JSON sur `stderr` :

```yaml
# config/packages/monolog.yaml (dans chaque projet Symfony)
monolog:
  handlers:
    # Logs structurés JSON vers stderr → remontent dans Docker logs → Dozzle
    docker:
      type: stream
      path: "php://stderr"
      level: debug
      formatter: monolog.formatter.json
      channels: ["!event"]

    # Fichier de log classique pour debug approfondi par Claude Code
    main:
      type: rotating_file
      path: '%kernel.logs_dir%/%kernel.environment%.log'
      level: debug
      max_files: 7

    # Log dédié aux erreurs critiques
    critical:
      type: rotating_file
      path: '%kernel.logs_dir%/critical.log'
      level: critical
      max_files: 30
```

Avec cette config, chaque erreur Symfony apparaît :
1. **Dans Dozzle** (via stderr → docker logs) — pour ton monitoring visuel depuis le téléphone
2. **Dans un fichier** — pour que Claude Code puisse analyser en profondeur avec `cat`, `grep`, `tail`

### 9.3 Workflow monitoring depuis le téléphone

**Scénario : tu reçois un bug report d'un client**

```
📱 Ouvre Safari → http://100.x.x.x:9999 (Dozzle)
   → Filtre sur le container "client-api"
   → Recherche "500" ou le endpoint concerné
   → Tu repères l'erreur : "SQLSTATE[23503] violates foreign key constraint"

📱 Ouvre l'app Claude → Remote Control Session
   Toi : "Il y a une erreur foreign key sur le endpoint POST /api/orders,
          regarde les logs dans var/log/dev.log et corrige"
   Claude : [lit les logs, identifie le problème, corrige le code, lance les tests]
```

### 9.4 Commandes logs utiles (à demander à Claude Code)

| Ce que tu dis | Ce que Claude fait |
|---|---|
| "Montre-moi les dernières erreurs du back client" | `docker logs client-api --since 1h 2>&1 \| grep -i error` |
| "Il y a eu quoi comme 500 aujourd'hui sur agence projet 1 ?" | `docker logs agence-projet1-api --since 24h 2>&1 \| grep "500"` |
| "Analyse le dernier crash Symfony" | `tail -100 ~/touriz/api/var/log/dev.log` puis diagnostic |
| "Y a-t-il des slow queries PostgreSQL ?" | `docker logs pieuvre-postgres 2>&1 \| grep "duration"` |

---

## 10. Phase 8 — Debug API (curl comme Postman)

### 10.1 Pourquoi curl > Postman dans ce setup

Avec la Pieuvre, tu n'as plus besoin de Postman. Claude Code + curl est **strictement supérieur** :
- Tu décris ta requête en langage naturel, Claude génère le curl
- Claude analyse la réponse (JSON, headers, status code) et t'explique
- Si c'est une erreur, Claude lit directement les logs + le code source pour diagnostiquer
- Il peut enchaîner : requête → diagnostic → fix → re-test, en une seule conversation
- Pas besoin de gérer des collections, des environnements, des variables

### 10.2 Script helper pour les requêtes API

```bash
cat > ~/scripts/api-test.sh << 'APITEST'
#!/bin/bash
# Helper pour tester les API avec output formaté
# Usage : api-test.sh METHOD URL [DATA]
# Exemples :
#   api-test.sh GET http://localhost:8000/api/users
#   api-test.sh POST http://localhost:8000/api/users '{"name":"John"}'
#   api-test.sh PUT http://localhost:8000/api/users/1 '{"name":"Jane"}'

METHOD=${1:-GET}
URL=$2
DATA=$3
TOKEN=${API_TOKEN:-""}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 $METHOD $URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CURL_OPTS=(
  -s -w '\n\n━━━ Response Info ━━━\nHTTP Status: %{http_code}\nTime Total: %{time_total}s\nSize: %{size_download} bytes\n'
  -X "$METHOD"
  -H "Content-Type: application/json"
  -H "Accept: application/json"
)

# Ajouter le token JWT si présent
if [ -n "$TOKEN" ]; then
  CURL_OPTS+=(-H "Authorization: Bearer $TOKEN")
fi

# Ajouter le body si présent
if [ -n "$DATA" ]; then
  CURL_OPTS+=(-d "$DATA")
fi

# Exécuter et formater le JSON
curl "${CURL_OPTS[@]}" "$URL" | jq '.' 2>/dev/null || curl "${CURL_OPTS[@]}" "$URL"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
APITEST

chmod +x ~/scripts/api-test.sh
```

### 10.3 Script d'authentification JWT

```bash
cat > ~/scripts/api-login.sh << 'APILOGIN'
#!/bin/bash
# Récupère un token JWT et le stocke pour les requêtes suivantes
# Usage : source api-login.sh http://localhost:8000 email password

BASE_URL=${1:-http://localhost:8000}
EMAIL=${2:-admin@example.com}
PASSWORD=${3:-password}

RESPONSE=$(curl -s -X POST "$BASE_URL/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

export API_TOKEN=$(echo $RESPONSE | jq -r '.token // .access_token // .jwt // empty')

if [ -n "$API_TOKEN" ]; then
  echo "✅ Authentifié. Token stocké dans \$API_TOKEN"
  echo "   Utilise : api-test.sh GET $BASE_URL/api/endpoint"
else
  echo "❌ Échec d'authentification"
  echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
fi
APILOGIN

chmod +x ~/scripts/api-login.sh
```

### 10.4 Workflows debug API depuis le téléphone

**Scénario simple : tester un endpoint**

```
Toi : "Fais un GET sur /api/users du projet client et montre-moi la réponse"
Claude : ~/scripts/api-test.sh GET http://localhost:8000/api/users
       → affiche le JSON formaté + status 200 + temps de réponse
```

**Scénario auth : tester un endpoint protégé**

```
Toi : "Connecte-toi à l'API client avec admin@test.com / password123
       puis fais un POST /api/orders avec { "product_id": 5, "quantity": 2 }"
Claude :
  1. source ~/scripts/api-login.sh http://localhost:8000 admin@test.com password123
     → ✅ Token récupéré
  2. ~/scripts/api-test.sh POST http://localhost:8000/api/orders '{"product_id":5,"quantity":2}'
     → 422 Unprocessable Entity : "product_id 5 not found"
  3. Claude lit le code du controller, vérifie la base
     → "Le produit 5 n'existe pas en BDD. Tu veux que je crée une fixture ?"
```

**Scénario debug complet : boucle erreur → diagnostic → fix**

```
Toi : "L'endpoint PATCH /api/orders/42 renvoie une 500, debug ça"
Claude :
  1. Reproduit → curl PATCH → confirme la 500
  2. Lit les logs → "Typed property Order::$status must not be accessed before initialization"
  3. Lit le code → identifie le nullable manquant
  4. Fixe → relance le curl → 200 OK
  5. Lance les tests → tout passe
  6. "C'est corrigé. Tu veux que je commit et push ?"
```

### 10.5 Ajouter au CLAUDE.md de chaque projet

Ajoute cette section dans les fichiers CLAUDE.md pour que Claude Code connaisse les outils :

```markdown
## Debug API
- Script de test : `~/scripts/api-test.sh METHOD URL [BODY]`
- Login JWT : `source ~/scripts/api-login.sh BASE_URL EMAIL PASSWORD`
- Le token est stocké dans $API_TOKEN et utilisé automatiquement
- Toujours utiliser jq pour formater les réponses JSON
- En cas d'erreur 4xx/5xx : lire les logs Docker + var/log/dev.log avant de diagnostiquer
```

---

## 11. Phase 9 — Watchdog & Résilience

### 11.1 Script watchdog

```bash
cat > ~/scripts/pieuvre-watchdog.sh << 'WATCHDOG'
#!/bin/bash
# Vérifie que l'infra Docker et Claude Code tournent

LOG="/home/dev/scripts/watchdog.log"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Vérifier l'infra PostgreSQL
if ! docker ps | grep -q pieuvre-postgres; then
  echo "$(timestamp) [WARN] PostgreSQL down, relancement..." >> $LOG
  cd /home/dev/infra && docker compose up -d postgres
fi

# Vérifier MongoDB
if ! docker ps | grep -q pieuvre-mongo; then
  echo "$(timestamp) [WARN] MongoDB down, relancement..." >> $LOG
  cd /home/dev/infra && docker compose up -d mongo
fi

# Vérifier que la session tmux pieuvre existe
if ! tmux has-session -t pieuvre 2>/dev/null; then
  echo "$(timestamp) [WARN] Session tmux pieuvre absente, recréation..." >> $LOG
  tmux new-session -d -s pieuvre
  tmux send-keys -t pieuvre:0 'cd /home/dev && claude remote-control' Enter
fi

# Vérifier Tailscale
if ! tailscale status > /dev/null 2>&1; then
  echo "$(timestamp) [WARN] Tailscale down, reconnexion..." >> $LOG
  sudo tailscale up
fi
WATCHDOG

chmod +x ~/scripts/pieuvre-watchdog.sh
```

### 11.2 Cron job

```bash
# Exécuter le watchdog toutes les 5 minutes
crontab -e

# Ajouter :
*/5 * * * * /home/dev/scripts/pieuvre-watchdog.sh
```

### 11.3 Script de démarrage complet

```bash
cat > ~/scripts/start-pieuvre.sh << 'START'
#!/bin/bash
# Lance toute la Pieuvre au boot ou après reboot

echo "🐙 Démarrage de La Pieuvre..."

# 1. Infra partagée
echo "  → Lancement infra (PG + Mongo)..."
cd /home/dev/infra && docker compose up -d

# 2. Attendre que PG soit prêt
echo "  → Attente PostgreSQL..."
until docker exec pieuvre-postgres pg_isready -U pieuvre > /dev/null 2>&1; do
  sleep 1
done
echo "  → PostgreSQL prêt."

# 3. Session tmux
echo "  → Création session tmux..."
tmux kill-session -t pieuvre 2>/dev/null
tmux new-session -d -s pieuvre -n claude
tmux send-keys -t pieuvre:claude 'cd /home/dev && claude remote-control' Enter

tmux new-window -t pieuvre -n shell
tmux new-window -t pieuvre -n logs
tmux send-keys -t pieuvre:logs 'docker logs -f pieuvre-postgres' Enter

# 4. Tailscale (normalement déjà up via systemd)
tailscale status > /dev/null 2>&1 || sudo tailscale up

echo "🐙 La Pieuvre est opérationnelle !"
echo "  IP Tailscale : $(tailscale ip -4)"
echo "  Remote Control : ouvre l'app Claude → Code"
START

chmod +x ~/scripts/start-pieuvre.sh
```

### 11.4 Lancement au boot (systemd)

```bash
sudo cat > /etc/systemd/system/pieuvre.service << 'SERVICE'
[Unit]
Description=La Pieuvre - Dev Environment
After=docker.service tailscaled.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=dev
ExecStart=/home/dev/scripts/start-pieuvre.sh

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable pieuvre.service
```

---

## 12. Phase 10 — CLAUDE.md du projet

Chaque projet doit avoir un fichier `CLAUDE.md` à sa racine. C'est le cerveau contextuel de Claude Code pour ce projet.

### 12.1 Exemple pour Touriz

```markdown
# CLAUDE.md — Client Fullstack

## Architecture
- **Front** : Nuxt 3 (Vue 3 + TypeScript) dans `/front`
- **Back** : Symfony 6.4 (PHP 8.3) dans `/api`
- **BDD** : PostgreSQL 16 (base: touriz) + MongoDB 7
- **Infra** : Docker, réseau partagé `pieuvre-net`

## Commandes utiles
- `docker compose up -d` : lance front + back
- `docker compose down` : stoppe le projet
- `docker exec -it client-api php bin/console` : console Symfony
- `docker exec -it client-front npx nuxi` : CLI Nuxt

## Convention Git
- Branches : `feature/JIRA-XXXX-description-courte`
- Commits : `feat(scope): description` (conventional commits)
- PR : toujours vers `develop`, jamais vers `main`
- Toujours lancer les tests avant de push

## Tests
- Back : `docker exec client-api php bin/phpunit`
- Front : `docker exec client-front npm run test`

## Structure API (Symfony)
- Endpoints dans `src/Controller/Api/`
- Entités dans `src/Entity/`
- Migrations : `php bin/console doctrine:migrations:migrate`
- Fixtures : `php bin/console doctrine:fixtures:load`

## Structure Front (Nuxt)
- Pages dans `pages/`
- Composants dans `components/`
- Composables dans `composables/`
- Store Pinia dans `stores/`

## Règles de code
- PHP : PSR-12, strict types
- TypeScript : strict mode, pas de `any`
- Toujours typer les retours de fonctions
- Pas de logique métier dans les controllers (utiliser des services)
```

### 12.2 Exemple pour un projet agence

```markdown
# CLAUDE.md — Agence Projet 1

## Architecture
- **API** : Symfony 6.4 (PHP 8.3)
- **BDD** : PostgreSQL 16 (base: agence_projet1)
- **Port** : 8001

## Commandes
- `docker compose up -d`
- `docker exec -it agence-projet1-api php bin/phpunit`
- `docker exec -it agence-projet1-api php bin/console`

## Convention Git
- Branches : `feature/JIRA-XXXX`
- Commits : conventional commits
- PR vers `develop`

## Points d'attention
- L'API utilise API Platform
- Auth par JWT (lexik/jwt-authentication-bundle)
- Toujours vérifier les voters pour les permissions
```

---

## 13. Workflows quotidiens

### 13.1 Workflow type depuis le téléphone

```
📱 Matin — Ouvrir l'app Claude → Code → Remote Control Session

Toi : "Quels sont mes tickets JIRA en cours ?"
Claude : [lit via MCP JIRA] "Tu as 3 tickets : JIRA-101, JIRA-102, JIRA-103..."

Toi : "Commence JIRA-101. Crée la branche, lis le ticket, et implémente."
Claude : [crée branche, code, lance les tests]

Toi : [ouvre Safari → http://100.x.x.x:3000 pour voir le front]
Toi : "Le header n'est pas aligné, fixe le padding-top"
Claude : [corrige, hot-reload]

Toi : "C'est bon. Ouvre une PR vers develop."
Claude : [commit, push, crée la PR sur Bitbucket]

Toi : "Maintenant switch sur le projet agence-1, ticket JIRA-201."
Claude : [change de répertoire, lance le docker-compose, travaille]
```

### 13.2 Commandes rapides utiles

| Commande (à dire à Claude) | Ce que ça fait |
|---|---|
| "Status de tous les containers" | `docker ps` |
| "Logs du back client" | `docker logs -f client-api` |
| "Lance les tests agence projet 1" | `docker exec agence-projet1-api php bin/phpunit` |
| "Pull et rebase develop" | `git pull --rebase origin develop` |
| "Montre-moi les migrations en attente" | `php bin/console doctrine:migrations:status` |
| "Dump la base touriz" | `pg_dump -U pieuvre touriz > backup.sql` |
| "Quelle RAM est utilisée ?" | `free -h && docker stats --no-stream` |

### 13.3 Quand prendre le laptop

- Debug visuel complexe nécessitant les DevTools Chrome
- Revue de code longue avec diff complexe
- Visioconférence + partage d'écran avec un client
- Si Claude Code est down ou si tu as atteint la limite de messages

---

## 14. Maintenance & Troubleshooting

### 14.1 Backups

```bash
# Script de backup quotidien des bases
cat > ~/scripts/backup-databases.sh << 'BACKUP'
#!/bin/bash
BACKUP_DIR="/home/dev/backups/$(date +%Y-%m-%d)"
mkdir -p $BACKUP_DIR

# PostgreSQL — toutes les bases
docker exec pieuvre-postgres pg_dumpall -U pieuvre > "$BACKUP_DIR/pg_all.sql"

# MongoDB
docker exec pieuvre-mongo mongodump \
  -u pieuvre -p $MONGO_PASSWORD \
  --authenticationDatabase admin \
  --out /tmp/mongodump
docker cp pieuvre-mongo:/tmp/mongodump "$BACKUP_DIR/mongo/"

# Garder 30 jours de backups
find /home/dev/backups -maxdepth 1 -mtime +30 -type d -exec rm -rf {} +

echo "Backup terminé : $BACKUP_DIR"
BACKUP

chmod +x ~/scripts/backup-databases.sh

# Cron : backup tous les jours à 3h du matin
# 0 3 * * * /home/dev/scripts/backup-databases.sh
```

### 14.2 Problèmes fréquents

**La session Remote Control se déconnecte :**
```bash
# Se reconnecter en SSH depuis le laptop
ssh dev@IP_DU_VPS
tmux attach -t pieuvre
# Relancer Remote Control dans la fenêtre claude
claude remote-control
```

**Un container OOM killed :**
```bash
# Vérifier les limites
docker stats --no-stream
# Relancer
docker compose -f ~/touriz/docker-compose.yml restart
```

**Espace disque plein :**
```bash
# Nettoyer Docker
docker system prune -a --volumes
# Vérifier
df -h
```

**Claude Code ne retrouve pas le contexte du projet :**
```bash
# S'assurer que le CLAUDE.md existe et que Claude est dans le bon dossier
# Depuis Remote Control :
# "cd ~/touriz et lis le CLAUDE.md"
```

### 14.3 Monitoring rapide

```bash
# Alias à ajouter dans ~/.bashrc
alias pieuvre-status='echo "=== Docker ===" && docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" && echo "\n=== RAM ===" && free -h && echo "\n=== Disk ===" && df -h / && echo "\n=== Tailscale ===" && tailscale status'
```

---

## 15. Checklist de validation

Avant de considérer la Pieuvre opérationnelle, valider chaque point :

### Infra
- [ ] VPS Hostinger KVM 8 provisionné et accessible en SSH
- [ ] User `dev` créé, root SSH désactivé
- [ ] Docker installé et fonctionnel
- [ ] Node.js 22+ installé (via nvm)
- [ ] tmux configuré

### Docker & BDD
- [ ] `docker compose up -d` dans `~/infra` → PG + Mongo up
- [ ] Bases créées (agence_projet1, agence_projet2, touriz)
- [ ] PgAdmin accessible via Tailscale
- [ ] Réseau `pieuvre-net` créé et fonctionnel

### Claude Code
- [ ] Claude Code installé (`claude --version`)
- [ ] Authentification réussie (`claude /login`)
- [ ] Remote Control fonctionnel (`claude remote-control`)
- [ ] Session visible dans l'app Claude sur téléphone
- [ ] Peut exécuter des commandes sur le VPS depuis le téléphone

### Tailscale
- [ ] Installé sur VPS, téléphone et laptop
- [ ] Les 3 devices se voient (`tailscale status`)
- [ ] Accès aux ports Docker depuis le téléphone (tester :5050 pour PgAdmin)

### Projets
- [ ] Repos clonés dans les bons dossiers
- [ ] `docker compose up -d` fonctionne pour chaque projet
- [ ] Les projets se connectent à l'infra partagée (PG/Mongo)
- [ ] Front Nuxt accessible depuis le téléphone via Tailscale
- [ ] CLAUDE.md présent à la racine de chaque projet

### MCP
- [ ] MCP JIRA configuré et fonctionnel (tester : "liste mes tickets")
- [ ] MCP Bitbucket configuré (tester : "liste les PR ouvertes")
- [ ] Permissions Claude Code configurées pour les commandes courantes

### Monitoring & Logs
- [ ] Dozzle accessible via Tailscale (`http://100.x.x.x:9999`)
- [ ] Logs de tous les containers visibles dans Dozzle
- [ ] Monolog configuré en JSON/stderr sur chaque projet Symfony
- [ ] Recherche par mot-clé fonctionnelle dans Dozzle (tester : chercher "error")

### Debug API
- [ ] `jq` installé sur le VPS (`apt install jq`)
- [ ] Script `~/scripts/api-test.sh` fonctionnel (tester un GET)
- [ ] Script `~/scripts/api-login.sh` fonctionnel (tester un login JWT)
- [ ] Claude Code peut exécuter les scripts et analyser les réponses

### Résilience
- [ ] Watchdog en cron toutes les 5 minutes
- [ ] Service systemd `pieuvre.service` activé
- [ ] Script de backup en cron quotidien
- [ ] Test de reboot : `sudo reboot` → vérifier que tout remonte

---

> **🐙 La Pieuvre est prête.** Tu peux désormais piloter ton dev depuis ton téléphone, ta terrasse, un café, ou n'importe où. Le laptop ne sert plus que de filet de sécurité.
