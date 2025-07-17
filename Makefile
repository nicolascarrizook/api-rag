.PHONY: help install start stop restart logs backup restore clean status health

# Default target
help: ## Show this help message
	@echo "WhatsApp Nutrition Bot - Available Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment Commands:"
	@echo "  make install     - Complete system installation"
	@echo "  make build       - Build Docker images"
	@echo "  make start       - Start all services"
	@echo "  make stop        - Stop all services"
	@echo "  make restart     - Restart all services"
	@echo ""
	@echo "Monitoring Commands:"
	@echo "  make logs        - View real-time logs"
	@echo "  make status      - Check service status"
	@echo "  make health      - Run health checks"
	@echo ""
	@echo "Data Commands:"
	@echo "  make backup      - Create full backup"
	@echo "  make restore     - Restore from backup"
	@echo "  make clean       - Clean containers and volumes"
	@echo "  make index-rag   - Reindex nutrition knowledge base"

install: ## Run complete system installation
	@echo "Starting complete system installation..."
	chmod +x scripts/install.sh
	./scripts/install.sh

build: ## Build Docker images
	@echo "Building Docker images..."
	docker compose build --parallel

start: ## Start all services
	@echo "Starting Telegram Nutrition Bot services..."
	docker compose up -d
	@echo "Services started! Waiting for initialization..."
	@sleep 10
	@make status

stop: ## Stop all services
	@echo "Stopping all services..."
	docker compose down

restart: ## Restart all services
	@echo "Restarting all services..."
	docker compose restart
	@sleep 5
	@make status

logs: ## View real-time logs from all services
	@echo "Showing real-time logs (Ctrl+C to exit)..."
	docker compose logs -f

logs-service: ## View logs for specific service (usage: make logs-service SERVICE=postgres)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make logs-service SERVICE=<service_name>"; \
		echo "Available services: postgres, redis, n8n, rag_api, nginx"; \
	else \
		docker compose logs -f $(SERVICE); \
	fi

status: ## Check status of all services
	@echo "=== Docker Compose Services ==="
	@docker compose ps
	@echo ""
	@echo "=== Container Health ==="
	@docker ps --filter "name=nutrition_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

health: ## Run comprehensive health checks
	@echo "Running health checks..."
	@echo ""
	@echo "1. Checking Docker Compose services..."
	@docker compose ps
	@echo ""
	@echo "2. Checking PostgreSQL connection..."
	@docker exec nutrition_postgres pg_isready -U nutrition_admin || echo "PostgreSQL: FAILED"
	@echo ""
	@echo "3. Checking Redis connection..."
	@docker exec nutrition_redis redis-cli ping || echo "Redis: FAILED"
	@echo ""
	@echo "4. Checking n8n health..."
	@curl -s http://localhost:5678/healthz > /dev/null && echo "n8n: OK" || echo "n8n: FAILED"
	@echo ""
	@echo "5. Checking RAG API health..."
	@curl -s http://localhost:8000/health > /dev/null && echo "RAG API: OK" || echo "RAG API: FAILED"
	@echo ""
	@echo "6. Checking Nginx..."
	@curl -s http://localhost/health > /dev/null && echo "Nginx: OK" || echo "Nginx: FAILED"

backup: ## Create full system backup
	@echo "Creating system backup..."
	chmod +x scripts/backup.sh
	./scripts/backup.sh

restore: ## Restore from backup (usage: make restore BACKUP=filename.tar.gz)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore BACKUP=filename.tar.gz"; \
		echo "Available backups:"; \
		ls -la backups/*.tar.gz 2>/dev/null || echo "No backups found"; \
	else \
		chmod +x scripts/restore.sh; \
		./scripts/restore.sh $(BACKUP); \
	fi

clean: ## Clean containers, volumes, and images
	@echo "Stopping services..."
	docker-compose down
	@echo "Removing containers and volumes..."
	docker-compose down -v --remove-orphans
	@echo "Cleaning up Docker system..."
	docker system prune -f
	@echo "Clean completed!"

clean-data: ## Clean only data volumes (DANGEROUS!)
	@echo "WARNING: This will delete all data!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		docker-compose down -v; \
		sudo rm -rf postgres/data/* redis/data/* n8n/data/*; \
		echo "Data cleaned!"; \
	else \
		echo "Operation cancelled"; \
	fi

index-rag: ## Reindex RAG knowledge base
	@echo "Reindexing nutrition knowledge base..."
	@if docker ps --filter "name=nutrition_rag" --filter "status=running" | grep -q nutrition_rag; then \
		docker exec nutrition_rag python /app/scripts/rag_indexer.py; \
		echo "RAG indexing completed!"; \
	else \
		echo "RAG service not running. Starting services first..."; \
		make start; \
		sleep 30; \
		docker exec nutrition_rag python /app/scripts/rag_indexer.py; \
	fi

dev-setup: ## Setup development environment
	@echo "Setting up development environment..."
	@if [ ! -f .env ]; then \
		echo "Creating .env file from template..."; \
		cp .env.example .env 2>/dev/null || echo "Please create .env file manually"; \
	fi
	@echo "Installing development dependencies..."
	pip3 install --user docker-compose httpie jq
	@echo "Development setup completed!"

test-webhook: ## Test WhatsApp webhook (usage: make test-webhook PHONE=5491234567890)
	@if [ -z "$(PHONE)" ]; then \
		echo "Usage: make test-webhook PHONE=5491234567890"; \
	else \
		echo "Testing webhook with phone: $(PHONE)"; \
		curl -X POST http://localhost/webhook/whatsapp-webhook \
		  -H "Content-Type: application/json" \
		  -d '{"entry":[{"changes":[{"value":{"messages":[{"from":"$(PHONE)","text":{"body":"test"},"id":"test123"}]}}]}]}'; \
	fi

test-telegram: ## Test Telegram webhook (usage: make test-telegram USER_ID=123456789)
	@if [ -z "$(USER_ID)" ]; then \
		echo "Usage: make test-telegram USER_ID=123456789 [TEXT='hola']"; \
		echo "Example: make test-telegram USER_ID=123456789 TEXT='nuevo plan'"; \
	else \
		TEXT=$${TEXT:-"hola"}; \
		echo "Testing Telegram webhook with user: $(USER_ID), text: $$TEXT"; \
		curl -X POST http://localhost:8000/telegram/webhook \
		  -H "Content-Type: application/json" \
		  -d '{"update_id":1,"message":{"message_id":1,"from":{"id":$(USER_ID),"is_bot":false,"first_name":"Test","username":"testuser"},"chat":{"id":$(USER_ID),"type":"private","first_name":"Test"},"date":'$$(date +%s)',"text":"'$$TEXT'"}}'; \
	fi

test-telegram-menu: ## Test Telegram main menu
	@echo "Testing Telegram main menu..."
	@make test-telegram USER_ID=123456789 TEXT="/start"

test-telegram-nuevo: ## Test Telegram new plan flow
	@echo "Testing Telegram new plan flow..."
	@make test-telegram USER_ID=123456789 TEXT="🆕 Plan Nuevo"

telegram-info: ## Get Telegram bot information
	@echo "Getting Telegram bot info..."
	@curl -s http://localhost:8000/telegram/info | jq .

telegram-set-webhook: ## Set Telegram webhook (usage: make telegram-set-webhook DOMAIN=yourdomain.com)
	@if [ -z "$(DOMAIN)" ]; then \
		echo "Usage: make telegram-set-webhook DOMAIN=yourdomain.com"; \
	else \
		echo "Setting Telegram webhook to: https://$(DOMAIN)/api/rag/telegram/webhook"; \
		curl -X POST "http://localhost:8000/telegram/set-webhook?webhook_url=https://$(DOMAIN)/api/rag/telegram/webhook"; \
	fi

monitor: ## Run system monitoring
	@echo "Running system monitoring..."
	chmod +x scripts/monitor.sh
	./scripts/monitor.sh

ssl-setup: ## Setup SSL certificates with Let's Encrypt
	@echo "Setting up SSL certificates..."
	@read -p "Enter your domain name: " domain; \
	sudo certbot --nginx -d $$domain; \
	echo "SSL setup completed for $$domain"

update: ## Update system and Docker images
	@echo "Updating system..."
	sudo apt update && sudo apt upgrade -y
	@echo "Updating Docker images..."
	docker-compose pull
	@echo "Rebuilding services..."
	docker-compose up -d --build
	@echo "Update completed!"

db-backup: ## Backup only database
	@echo "Creating database backup..."
	@if docker ps --filter "name=nutrition_postgres" --filter "status=running" | grep -q nutrition_postgres; then \
		mkdir -p backups; \
		docker exec nutrition_postgres pg_dump -U nutrition_admin nutrition_bot > backups/db_backup_$(shell date +%Y%m%d_%H%M%S).sql; \
		echo "Database backup completed!"; \
	else \
		echo "PostgreSQL container not running"; \
	fi

db-restore: ## Restore database (usage: make db-restore BACKUP=db_backup_file.sql)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make db-restore BACKUP=db_backup_file.sql"; \
		echo "Available database backups:"; \
		ls -la backups/db_backup_*.sql 2>/dev/null || echo "No database backups found"; \
	else \
		echo "Restoring database from $(BACKUP)..."; \
		docker exec -i nutrition_postgres psql -U nutrition_admin -d nutrition_bot < $(BACKUP); \
		echo "Database restore completed!"; \
	fi

shell-postgres: ## Open PostgreSQL shell
	@docker exec -it nutrition_postgres psql -U nutrition_admin -d nutrition_bot

shell-redis: ## Open Redis shell
	@docker exec -it nutrition_redis redis-cli

shell-rag: ## Open RAG container shell
	@docker exec -it nutrition_rag /bin/bash

logs-tail: ## Tail specific service logs (usage: make logs-tail SERVICE=postgres LINES=100)
	@LINES=$${LINES:-50}; \
	SERVICE=$${SERVICE:-all}; \
	if [ "$$SERVICE" = "all" ]; then \
		docker-compose logs --tail=$$LINES; \
	else \
		docker-compose logs --tail=$$LINES $$SERVICE; \
	fi

config-check: ## Check configuration files
	@echo "Checking configuration files..."
	@echo "1. Docker Compose file..."
	@docker-compose config --quiet && echo "✓ docker-compose.yml is valid" || echo "✗ docker-compose.yml has errors"
	@echo "2. Environment file..."
	@if [ -f .env ]; then echo "✓ .env file exists"; else echo "✗ .env file missing"; fi
	@echo "3. Nginx configuration..."
	@docker run --rm -v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro nginx nginx -t && echo "✓ nginx.conf is valid" || echo "✗ nginx.conf has errors"
	@echo "4. RAG data..."
	@if [ -d rag-system/data ] && [ "$$(ls -A rag-system/data)" ]; then echo "✓ RAG data exists"; else echo "✗ RAG data missing"; fi

# Development helpers
dev-logs: ## Show development logs with colors
	@docker-compose logs --tail=100 -f | grep -E "(ERROR|WARN|INFO|DEBUG)" --color=always

dev-reset: ## Reset development environment
	@echo "Resetting development environment..."
	make stop
	make clean-data
	make start
	sleep 30
	make index-rag
	@echo "Development environment reset completed!"

# Production helpers
prod-deploy: ## Deploy to production
	@echo "Deploying to production..."
	@git pull origin main
	@docker-compose pull
	@docker-compose up -d --build
	@sleep 30
	@make health
	@echo "Production deployment completed!"

prod-backup: ## Create production backup with upload
	@echo "Creating production backup..."
	@./scripts/backup.sh
	@echo "Production backup completed!"