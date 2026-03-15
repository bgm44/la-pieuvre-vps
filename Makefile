# ============================================================
# 🐙 La Pieuvre — VPS Bootstrap Makefile
# One command to rule them all: make setup
# ============================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─── Paths ──────────────────────────────────────────────────
ROOT          := $(shell pwd)
COCKPIT_DIR   := $(ROOT)/pieuvre-cockpit
INFRA_DIR     := $(ROOT)/infra
SCRIPTS_DIR   := $(ROOT)/scripts
PROJECTS_DIR  := $(ROOT)/Projects
LOG           := $(ROOT)/.setup.log

# ─── Colors ─────────────────────────────────────────────────
C_RESET  := \033[0m
C_CYAN   := \033[36m
C_GREEN  := \033[32m
C_YELLOW := \033[33m
C_RED    := \033[31m

define log_step
	@printf "$(C_CYAN)[pieuvre]$(C_RESET) $(1)\n"
endef

define log_ok
	@printf "$(C_GREEN)[  ok  ]$(C_RESET) $(1)\n"
endef

define log_warn
	@printf "$(C_YELLOW)[ warn ]$(C_RESET) $(1)\n"
endef

define log_skip
	@printf "$(C_YELLOW)[ skip ]$(C_RESET) $(1) (already done)\n"
endef

# ============================================================
# MAIN TARGETS
# ============================================================

.PHONY: setup
## Full VPS setup — run this once on a fresh machine
setup: deps docker submodules infra cockpit-install cockpit-db cockpit-build pm2 tmux-session watchdog tailscale-check
	@echo ""
	@printf "$(C_GREEN)=========================================$(C_RESET)\n"
	@printf "$(C_GREEN) La Pieuvre is operational$(C_RESET)\n"
	@printf "$(C_GREEN)=========================================$(C_RESET)\n"
	@echo ""
	@echo "  Cockpit API   → http://localhost:8888"
	@echo "  Cockpit Front → http://localhost:3333"
	@echo "  Docs          → http://localhost:7777"
	@echo ""
	@echo "  tmux attach -t pieuvre   → join the session"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Edit pieuvre-cockpit/.env with Atlassian/Bitbucket credentials"
	@echo "  2. Edit infra/.env with database passwords"
	@echo "  3. Clone your project(s) into Projects/"
	@echo "  4. make mcp-install  (once MCP servers are configured)"
	@echo ""

.PHONY: start
## Start everything (infra + cockpit + tmux) — daily use
start: infra-up cockpit-start tmux-session
	$(call log_ok,La Pieuvre started)

.PHONY: stop
## Stop everything gracefully
stop: cockpit-stop infra-down tmux-kill
	$(call log_ok,La Pieuvre stopped)

.PHONY: restart
## Restart everything
restart: stop start

.PHONY: status
## Show status of all services
status:
	@echo ""
	@printf "$(C_CYAN)── Docker containers ──$(C_RESET)\n"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Docker not running"
	@echo ""
	@printf "$(C_CYAN)── pm2 processes ──$(C_RESET)\n"
	@pm2 list 2>/dev/null || echo "  pm2 not running"
	@echo ""
	@printf "$(C_CYAN)── tmux sessions ──$(C_RESET)\n"
	@tmux list-sessions 2>/dev/null || echo "  No tmux sessions"
	@echo ""
	@printf "$(C_CYAN)── Tailscale ──$(C_RESET)\n"
	@tailscale status 2>/dev/null || echo "  Tailscale not connected"
	@echo ""

# ============================================================
# SYSTEM DEPENDENCIES
# ============================================================

.PHONY: deps
## Install system packages (Docker, pm2, tmux, build tools)
deps: deps-system deps-node deps-pm2
	$(call log_ok,All dependencies installed)

.PHONY: deps-system
deps-system:
	$(call log_step,Installing system packages...)
	@if ! command -v git &>/dev/null || ! command -v curl &>/dev/null || ! command -v tmux &>/dev/null || ! command -v jq &>/dev/null; then \
		apt-get update -qq && \
		apt-get install -y -qq git curl wget tmux jq make build-essential ca-certificates gnupg lsb-release >> $(LOG) 2>&1; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) System packages installed\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) System packages (already installed)\n"; \
	fi

.PHONY: deps-node
deps-node:
	$(call log_step,Checking Node.js...)
	@if ! command -v node &>/dev/null; then \
		curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> $(LOG) 2>&1 && \
		apt-get install -y -qq nodejs >> $(LOG) 2>&1; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) Node.js $$(node --version) installed\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) Node.js ($$(node --version) already installed)\n"; \
	fi

.PHONY: deps-pm2
deps-pm2:
	$(call log_step,Checking pm2...)
	@if ! command -v pm2 &>/dev/null; then \
		npm install -g pm2 >> $(LOG) 2>&1; \
		pm2 startup systemd -u root --hp /root >> $(LOG) 2>&1 || true; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) pm2 installed\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) pm2 ($$(pm2 --version) already installed)\n"; \
	fi

# ============================================================
# DOCKER
# ============================================================

.PHONY: docker
## Install Docker Engine if not present
docker:
	$(call log_step,Checking Docker...)
	@if ! command -v docker &>/dev/null; then \
		curl -fsSL https://get.docker.com | sh >> $(LOG) 2>&1; \
		systemctl enable docker >> $(LOG) 2>&1; \
		systemctl start docker >> $(LOG) 2>&1; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) Docker installed\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) Docker ($$(docker --version) already installed)\n"; \
	fi

# ============================================================
# GIT SUBMODULES
# ============================================================

.PHONY: submodules
## Initialize and pull git submodules (pieuvre-cockpit)
submodules:
	$(call log_step,Initializing git submodules...)
	@if [ ! -f "$(COCKPIT_DIR)/package.json" ] && [ ! -f "$(COCKPIT_DIR)/api/server.js" ]; then \
		ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null; \
		git submodule update --init --recursive; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) Submodules initialized\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) Submodules (already cloned)\n"; \
	fi

# ============================================================
# INFRASTRUCTURE (Docker containers)
# ============================================================

.PHONY: infra
## Start infra containers and wait for readiness
infra: infra-up infra-wait
	$(call log_ok,Infrastructure ready)

.PHONY: infra-up
infra-up:
	$(call log_step,Starting infrastructure containers...)
	@cd $(INFRA_DIR) && docker compose up -d

.PHONY: infra-down
infra-down:
	$(call log_step,Stopping infrastructure containers...)
	@cd $(INFRA_DIR) && docker compose down

.PHONY: infra-wait
infra-wait:
	$(call log_step,Waiting for PostgreSQL...)
	@for i in $$(seq 1 30); do \
		docker exec pieuvre-postgres pg_isready -U pieuvre > /dev/null 2>&1 && break; \
		sleep 1; \
	done
	@docker exec pieuvre-postgres pg_isready -U pieuvre > /dev/null 2>&1 && \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) PostgreSQL ready\n" || \
		printf "$(C_RED)[ FAIL ]$(C_RESET) PostgreSQL not ready after 30s\n"

.PHONY: infra-logs
## Tail infra container logs
infra-logs:
	@cd $(INFRA_DIR) && docker compose logs -f

# ============================================================
# COCKPIT
# ============================================================

.PHONY: cockpit-install
## Install cockpit dependencies (api + front + docs)
cockpit-install: cockpit-env
	$(call log_step,Installing cockpit API dependencies...)
	@cd $(COCKPIT_DIR)/api && npm install >> $(LOG) 2>&1
	$(call log_step,Installing cockpit frontend dependencies...)
	@cd $(COCKPIT_DIR)/front && npm install >> $(LOG) 2>&1
	@if [ -f "$(COCKPIT_DIR)/docs/package.json" ]; then \
		printf "$(C_CYAN)[pieuvre]$(C_RESET) Installing docs dependencies...\n"; \
		cd $(COCKPIT_DIR)/docs && npm install >> $(LOG) 2>&1; \
	fi
	$(call log_ok,Cockpit dependencies installed)

.PHONY: cockpit-env
cockpit-env:
	@if [ -f "$(COCKPIT_DIR)/.env.example" ] && [ ! -f "$(COCKPIT_DIR)/.env" ]; then \
		cp $(COCKPIT_DIR)/.env.example $(COCKPIT_DIR)/.env; \
		printf "$(C_YELLOW)[ warn ]$(C_RESET) Created cockpit .env from .env.example — edit it with real values\n"; \
	fi
	@if [ -f "$(INFRA_DIR)/.env.example" ] && [ ! -f "$(INFRA_DIR)/.env" ]; then \
		cp $(INFRA_DIR)/.env.example $(INFRA_DIR)/.env; \
		printf "$(C_YELLOW)[ warn ]$(C_RESET) Created infra .env from .env.example — edit it with real values\n"; \
	fi

.PHONY: cockpit-db
## Run cockpit database migrations
cockpit-db:
	$(call log_step,Running cockpit database migrations...)
	@cd $(COCKPIT_DIR) && node api/services/db.js 2>/dev/null || true
	$(call log_ok,Database migrations done)

.PHONY: cockpit-build
## Build the Next.js frontend
cockpit-build:
	$(call log_step,Building cockpit frontend...)
	@cd $(COCKPIT_DIR)/front && npm run build >> $(LOG) 2>&1
	$(call log_ok,Frontend built)

.PHONY: cockpit-start
## Start cockpit via pm2
cockpit-start:
	$(call log_step,Starting cockpit via pm2...)
	@pm2 start $(COCKPIT_DIR)/api/server.js --name cockpit --cwd $(COCKPIT_DIR) 2>/dev/null || pm2 restart cockpit
	@if [ -f "$(COCKPIT_DIR)/docs/server.js" ]; then \
		pm2 start $(COCKPIT_DIR)/docs/server.js --name docs --cwd $(COCKPIT_DIR)/docs 2>/dev/null || pm2 restart docs; \
	fi
	@pm2 save >> $(LOG) 2>&1
	$(call log_ok,Cockpit started)

.PHONY: cockpit-stop
## Stop cockpit pm2 processes
cockpit-stop:
	$(call log_step,Stopping cockpit...)
	@pm2 stop cockpit 2>/dev/null || true
	@pm2 stop docs 2>/dev/null || true

.PHONY: cockpit-restart
## Restart cockpit
cockpit-restart:
	@pm2 restart cockpit
	@pm2 restart docs 2>/dev/null || true
	$(call log_ok,Cockpit restarted)

.PHONY: cockpit-logs
## Tail cockpit logs
cockpit-logs:
	@pm2 logs cockpit --lines 50

# ============================================================
# PM2 SETUP
# ============================================================

.PHONY: pm2
## Register all pm2 processes and save
pm2: cockpit-start
	@pm2 save >> $(LOG) 2>&1
	$(call log_ok,pm2 processes saved)

# ============================================================
# MCP SERVERS
# ============================================================

.PHONY: mcp-install
## Install and start all MCP servers (Jira, Bitbucket, Postgres, Filesystem)
mcp-install: mcp-jira mcp-bitbucket mcp-postgres mcp-filesystem
	@pm2 save >> $(LOG) 2>&1
	$(call log_ok,All MCP servers installed and running)

.PHONY: mcp-jira
mcp-jira:
	$(call log_step,Starting MCP Jira server (port 3001)...)
	@pm2 start npx --name mcp-jira -- -y supergateway --stdio "npx -y @anthropic/mcp-jira" --port 3001 2>/dev/null || pm2 restart mcp-jira

.PHONY: mcp-bitbucket
mcp-bitbucket:
	$(call log_step,Starting MCP Bitbucket server (port 3002)...)
	@pm2 start npx --name mcp-bitbucket -- -y supergateway --stdio "npx -y @anthropic/mcp-bitbucket" --port 3002 2>/dev/null || pm2 restart mcp-bitbucket

.PHONY: mcp-postgres
mcp-postgres:
	$(call log_step,Starting MCP PostgreSQL server (port 3003)...)
	@pm2 start npx --name mcp-postgres -- -y supergateway --stdio "npx -y @anthropic/mcp-postgres postgresql://localhost:5432/touriz" --port 3003 2>/dev/null || pm2 restart mcp-postgres

.PHONY: mcp-filesystem
mcp-filesystem:
	$(call log_step,Starting MCP Filesystem server (port 3004)...)
	@pm2 start npx --name mcp-filesystem -- -y supergateway --stdio "npx -y @anthropic/mcp-filesystem /root" --port 3004 2>/dev/null || pm2 restart mcp-filesystem

.PHONY: mcp-restart
## Restart all MCP servers
mcp-restart:
	@pm2 restart mcp-jira mcp-bitbucket mcp-postgres mcp-filesystem 2>/dev/null || true
	$(call log_ok,MCP servers restarted)

.PHONY: mcp-logs
## Tail MCP server logs
mcp-logs:
	@pm2 logs --lines 30

# ============================================================
# TMUX
# ============================================================

.PHONY: tmux-session
## Create the pieuvre tmux session (claude / shell / logs windows)
tmux-session:
	$(call log_step,Setting up tmux session...)
	@if ! tmux has-session -t pieuvre 2>/dev/null; then \
		tmux new-session -d -s pieuvre -n claude; \
		tmux new-window -t pieuvre -n shell; \
		tmux new-window -t pieuvre -n logs; \
		tmux send-keys -t pieuvre:logs "cd $(INFRA_DIR) && docker compose logs -f" Enter; \
		tmux select-window -t pieuvre:claude; \
		$(call log_ok,tmux session 'pieuvre' created (claude / shell / logs)); \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) tmux session 'pieuvre' already exists\n"; \
	fi

.PHONY: tmux-kill
tmux-kill:
	@tmux kill-session -t pieuvre 2>/dev/null || true

# ============================================================
# WATCHDOG (cron)
# ============================================================

.PHONY: watchdog
## Install the watchdog cron job (runs every 5 minutes)
watchdog:
	$(call log_step,Setting up watchdog cron...)
	@chmod +x $(SCRIPTS_DIR)/pieuvre-watchdog.sh
	@chmod +x $(SCRIPTS_DIR)/start-pieuvre.sh
	@(crontab -l 2>/dev/null | grep -v pieuvre-watchdog; echo "*/5 * * * * $(SCRIPTS_DIR)/pieuvre-watchdog.sh") | crontab -
	$(call log_ok,Watchdog cron installed (every 5 min))

.PHONY: watchdog-remove
## Remove the watchdog cron job
watchdog-remove:
	@crontab -l 2>/dev/null | grep -v pieuvre-watchdog | crontab -
	$(call log_ok,Watchdog cron removed)

# ============================================================
# TAILSCALE
# ============================================================

.PHONY: tailscale-install
## Install Tailscale for private networking
tailscale-install:
	$(call log_step,Installing Tailscale...)
	@if ! command -v tailscale &>/dev/null; then \
		curl -fsSL https://tailscale.com/install.sh | sh >> $(LOG) 2>&1; \
		printf "$(C_GREEN)[  ok  ]$(C_RESET) Tailscale installed — run 'tailscale up' to authenticate\n"; \
	else \
		printf "$(C_YELLOW)[ skip ]$(C_RESET) Tailscale already installed\n"; \
	fi

.PHONY: tailscale-check
tailscale-check:
	@if command -v tailscale &>/dev/null; then \
		tailscale status > /dev/null 2>&1 && \
			printf "$(C_GREEN)[  ok  ]$(C_RESET) Tailscale connected ($$(tailscale ip -4))\n" || \
			printf "$(C_YELLOW)[ warn ]$(C_RESET) Tailscale installed but not connected — run 'tailscale up'\n"; \
	else \
		printf "$(C_YELLOW)[ warn ]$(C_RESET) Tailscale not installed — run 'make tailscale-install'\n"; \
	fi

# ============================================================
# PROJECTS
# ============================================================

.PHONY: projects-dir
## Ensure Projects directory exists with .gitkeep
projects-dir:
	@mkdir -p $(PROJECTS_DIR)
	@touch $(PROJECTS_DIR)/.gitkeep

# ============================================================
# CLEANUP & MAINTENANCE
# ============================================================

.PHONY: clean
## Remove build artifacts and caches (keeps data)
clean:
	$(call log_step,Cleaning build artifacts...)
	@rm -rf $(COCKPIT_DIR)/front/.next
	@rm -f $(LOG)
	$(call log_ok,Cleaned)

.PHONY: nuke
## Full reset: stop everything, remove containers/volumes, clean all
nuke:
	$(call log_warn,This will destroy all containers and volumes!)
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) stop
	@cd $(INFRA_DIR) && docker compose down -v
	@pm2 delete all 2>/dev/null || true
	@rm -rf $(COCKPIT_DIR)/front/.next $(COCKPIT_DIR)/front/node_modules $(COCKPIT_DIR)/api/node_modules
	@rm -f $(LOG)
	$(call log_ok,Everything nuked)

# ============================================================
# HELP
# ============================================================

.PHONY: help
## Show this help
help:
	@echo ""
	@printf "$(C_CYAN)La Pieuvre — VPS Control System$(C_RESET)\n"
	@echo ""
	@printf "$(C_GREEN)Main commands:$(C_RESET)\n"
	@echo "  make setup          Full initial setup (run once on fresh VPS)"
	@echo "  make start          Start everything (daily use)"
	@echo "  make stop           Stop everything"
	@echo "  make restart        Restart everything"
	@echo "  make status         Show status of all services"
	@echo ""
	@printf "$(C_GREEN)Infrastructure:$(C_RESET)\n"
	@echo "  make infra          Start infra containers + wait for readiness"
	@echo "  make infra-down     Stop infra containers"
	@echo "  make infra-logs     Tail infra logs"
	@echo ""
	@printf "$(C_GREEN)Cockpit:$(C_RESET)\n"
	@echo "  make cockpit-install   Install all cockpit dependencies"
	@echo "  make cockpit-build     Build the Next.js frontend"
	@echo "  make cockpit-start     Start cockpit via pm2"
	@echo "  make cockpit-stop      Stop cockpit"
	@echo "  make cockpit-restart   Restart cockpit"
	@echo "  make cockpit-logs      Tail cockpit logs"
	@echo "  make cockpit-db        Run database migrations"
	@echo ""
	@printf "$(C_GREEN)MCP Servers:$(C_RESET)\n"
	@echo "  make mcp-install    Install and start all MCP servers"
	@echo "  make mcp-restart    Restart all MCP servers"
	@echo "  make mcp-logs       Tail MCP logs"
	@echo ""
	@printf "$(C_GREEN)Other:$(C_RESET)\n"
	@echo "  make deps           Install system dependencies"
	@echo "  make docker         Install Docker"
	@echo "  make tailscale-install  Install Tailscale"
	@echo "  make watchdog       Install watchdog cron"
	@echo "  make clean          Remove build artifacts"
	@echo "  make nuke           Full reset (destructive!)"
	@echo ""
