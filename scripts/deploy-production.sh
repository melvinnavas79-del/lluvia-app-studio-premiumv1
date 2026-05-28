#!/usr/bin/env bash
# ============================================================================
# Lluvia App Studio — Production Deploy Script
# Source: /opt/lluvia-premiumv1 (premium repo)
#
# Usage:
#   ./scripts/deploy-production.sh              Full deploy (pull + build + up)
#   ./scripts/deploy-production.sh --no-pull    Skip git pull (local changes)
#   ./scripts/deploy-production.sh --frontend   Frontend only (no Docker rebuild)
#   BRANCH=develop ./scripts/deploy-production.sh  Deploy develop branch
# ============================================================================
set -euo pipefail

REPO_DIR="/opt/lluvia-premiumv1"
NGINX_STATIC="/app/lluvia-deploy/backend/static"
LOG_FILE="/var/log/lluvia_deploy.log"
BRANCH="${BRANCH:-main}"
NO_PULL="${1:-}"
FRONTEND_ONLY="${1:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=== Deploy started (branch: $BRANCH) ==="
cd "$REPO_DIR"

# ── Step 1: Git pull ──────────────────────────────────────────────────────────
if [[ "$NO_PULL" != "--no-pull" ]]; then
  log "Pulling $BRANCH from origin..."
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
  log "✓ Git pull OK — $(git log --oneline -1)"
fi

# ── Step 2: Build frontend ────────────────────────────────────────────────────
log "Building frontend..."
cd "$REPO_DIR/frontend"
if [[ ! -d "node_modules" ]]; then
  log "  Installing frontend dependencies..."
  yarn install --frozen-lockfile --silent
fi
yarn build 2>&1 | tail -5
log "✓ Frontend built → $REPO_DIR/frontend/build"

# ── Step 3: Sync static files to nginx ───────────────────────────────────────
log "Syncing static files to nginx..."
mkdir -p "$NGINX_STATIC"
rsync -a --delete "$REPO_DIR/frontend/build/" "$NGINX_STATIC/"
log "✓ Static files synced to $NGINX_STATIC"

# ── Step 4: Rebuild Docker backend ───────────────────────────────────────────
if [[ "$FRONTEND_ONLY" != "--frontend" ]]; then
  log "Rebuilding backend Docker image..."
  cd "$REPO_DIR"
  docker compose build --no-cache backend 2>&1 | tail -5
  log "✓ Docker image built"

  log "Restarting containers..."
  docker compose up -d
  sleep 12
fi

# ── Step 5: Health check ──────────────────────────────────────────────────────
log "Running health check..."
STATUS=$(curl -sf http://localhost:8001/api/ | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unreachable")
if [[ "$STATUS" == "running" ]]; then
  log "✓ Backend healthy: $STATUS"
else
  log "✗ Backend health check FAILED: $STATUS"
  log "  Check logs: docker logs lluvia_backend --tail 50"
  exit 1
fi

log "=== Deploy complete ==="
log "  Source: $REPO_DIR (branch: $BRANCH)"
log "  Nginx static: $NGINX_STATIC"
log "  Backend: http://localhost:8001/api/"
