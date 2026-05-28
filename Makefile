.PHONY: up down build restart logs shell test lint status deploy deploy-frontend

REPO   := /opt/lluvia-premiumv1
STATIC := /app/lluvia-deploy/backend/static

# ── Production (run from /opt/lluvia-premiumv1) ───────────────────────────────

up:
	docker compose up -d

down:
	docker compose down

build:
	docker compose build --no-cache backend

restart: build
	docker compose up -d backend

logs:
	docker logs lluvia_backend -f --tail 100

logs-mongo:
	docker logs lluvia_mongo -f --tail 50

shell:
	docker exec -it lluvia_backend bash

# ── Frontend ──────────────────────────────────────────────────────────────────

build-frontend:
	@echo "Building frontend..."
	cd frontend && yarn build
	@echo "Syncing to nginx static..."
	rsync -a --delete frontend/build/ $(STATIC)/
	@echo "✓ Frontend deployed to $(STATIC)"

# ── Quality ───────────────────────────────────────────────────────────────────

lint:
	flake8 backend/ --max-line-length=120 \
		--exclude=backend/generated_apps,backend/uploads,backend/app_templates,backend/__pycache__ \
		--ignore=E501,W503,E203

test:
	REACT_APP_BACKEND_URL=http://localhost:8001 \
		python -m pytest backend/tests/ -v --timeout=30

# ── Status ────────────────────────────────────────────────────────────────────

status:
	@echo "=== Source ==="
	@git log --oneline -2
	@echo ""
	@echo "=== Containers ==="
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep lluvia || true
	@echo ""
	@echo "=== Backend health ==="
	@curl -s http://localhost:8001/api/ | python3 -c "import sys,json; d=json.load(sys.stdin); print(' status:', d.get('status'), '| version:', d.get('version'))"
	@echo ""
	@echo "=== LLM provider ==="
	@docker exec lluvia_backend python3 -c \
		"from llm_router import get_console_client; c,m=get_console_client(); print(' Model:', m)" 2>/dev/null || true
	@echo ""
	@echo "=== Tools ==="
	@docker exec lluvia_backend python3 -c \
		"import agents_catalog; ag=agents_catalog.get_agent('lluvia_studio'); print(' Tools:', len(ag.get('tools',[])))" 2>/dev/null || true

# ── Full production deploy ────────────────────────────────────────────────────
# Runs git pull + frontend build + docker rebuild + restart + health check

deploy:
	@bash scripts/deploy-production.sh

deploy-frontend:
	@bash scripts/deploy-production.sh --frontend

# ── Rollback ──────────────────────────────────────────────────────────────────
# Restores production to /opt/lluvia if something goes wrong

rollback:
	@echo "⚠ Rolling back to /opt/lluvia..."
	cd /opt/lluvia-premiumv1 && docker compose down
	cd /opt/lluvia && docker compose up -d
	@echo "✓ Rolled back to /opt/lluvia"
