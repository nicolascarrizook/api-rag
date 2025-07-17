# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Telegram Nutrition Bot is a complete automated nutrition consultation system that generates personalized meal plans using the "Tres Días y Carga | Dieta Inteligente® & Nutrición Evolutiva" methodology. The system integrates Telegram Bot API, n8n workflow automation, RAG (Retrieval-Augmented Generation) with OpenAI, and PostgreSQL database.

**🔄 Migration from WhatsApp to Telegram**: This project was migrated from WhatsApp Business API to Telegram for easier setup, no costs, and faster development iteration.

## Architecture

### Core Components
- **n8n**: Workflow automation and WhatsApp integration
- **PostgreSQL**: Patient data, conversations, and meal plans storage
- **Redis**: Session management and caching
- **RAG System**: FastAPI service with ChromaDB for nutrition knowledge retrieval
- **Nginx**: Reverse proxy with SSL termination
- **Docker Compose**: Container orchestration

### Key Technologies
- Python FastAPI (RAG API)
- OpenAI GPT-4 (meal plan generation)
- ChromaDB (embeddings storage)
- **Telegram Bot API** (free messaging platform)
- n8n workflow automation
- PostgreSQL with JSONB
- Redis for caching
- Nginx with SSL

## Common Development Commands

### Essential Commands
```bash
# Start all services
make start

# View logs
make logs

# Check service status
make status

# Run health checks
make health

# Create backup
make backup

# Stop services
make stop
```

### Database Operations
```bash
# Database shell
make shell-postgres

# Backup database only
make db-backup

# Restore database
make db-restore BACKUP=filename.sql
```

### RAG System
```bash
# Reindex nutrition knowledge
make index-rag

# Access RAG container
make shell-rag

# Test RAG API
curl http://localhost:8000/health
```

## Project Structure

```
/
├── docker-compose.yml          # Main orchestration
├── .env                        # Environment variables
├── Makefile                    # Common commands
├── postgres/
│   ├── data/                   # Database data (mounted)
│   └── init/01-init.sql       # Database schema
├── n8n/
│   ├── data/                   # n8n data (mounted)
│   └── workflows/             # Workflow definitions
├── rag-system/
│   ├── api/rag_api.py         # FastAPI RAG service
│   ├── scripts/rag_indexer.py # Knowledge indexer
│   ├── data/                  # Nutrition knowledge base
│   │   ├── recetas/           # Recipe collections
│   │   ├── ingredientes/      # Ingredient data
│   │   └── planes-ejemplo/    # Example meal plans
│   └── embeddings/            # ChromaDB storage
├── nginx/
│   ├── nginx.conf             # Reverse proxy config
│   └── ssl/                   # SSL certificates
└── scripts/
    ├── install.sh             # System installation
    ├── backup.sh              # Backup automation
    └── restore.sh             # Restore automation
```

## Environment Configuration

Key environment variables in `.env`:
- `OPENAI_API_KEY`: OpenAI API key for GPT-4
- `TELEGRAM_BOT_TOKEN`: Telegram bot token from @BotFather
- `TELEGRAM_WEBHOOK_SECRET`: Webhook security secret
- `POSTGRES_PASSWORD`: Database password
- `REDIS_PASSWORD`: Redis password
- `DOMAIN`: Your domain name for SSL

### Telegram Setup
1. Contact @BotFather on Telegram
2. Create new bot with `/newbot`
3. Get bot token (format: `123456:ABC-DEF...`)
4. Set webhook URL to: `https://domain.com/api/rag/telegram/webhook`

## Business Logic

### Three Consultation Engines
1. **Motor 1 (Nuevo)**: New patient consultation - collects full data and generates initial meal plan
2. **Motor 2 (Control)**: Follow-up consultation - adjusts existing plan based on progress
3. **Motor 3 (Reemplazo)**: Meal replacement - substitutes specific meals in existing plan

### Data Flow
1. Telegram message → RAG API webhook
2. Bot processes message and manages conversation state
3. Routes to appropriate motor based on intent
4. RAG system provides nutrition context
5. OpenAI generates personalized meal plan
6. Response sent via Telegram
7. Conversation stored in PostgreSQL

## Database Schema

### Key Tables
- `patients`: Basic patient information
- `conversations`: Message history with context
- `meal_plans`: Generated plans with macros
- `patient_metrics`: Progress tracking
- `ingredients`: Nutritional database

### Important Constraints
- Ages: 15-80 years
- Weight: 40-150 kg
- Height: 140-210 cm
- Objectives: -1kg, -0.5kg, mantener, +0.5kg, +1kg per week

## Nutrition Methodology Rules

### Format Requirements
- All weights in raw grams (except free vegetables)
- Type C vegetables (potato, sweet potato, corn) always in grams
- Argentine Spanish terminology mandatory
- Three identical days format
- Balanced macronutrients across main meals

### Sample Format
```
PLAN ALIMENTARIO - [NAME]
Objetivo: [objective]
=== DÍA 1, 2 y 3 ===
DESAYUNO (08:00 hs)
• Alimento 1: XXg
• Alimento 2: XXg
Preparación: [description]
Macros diarios: P: XXg | C: XXg | G: XXg
Calorías: XXXX kcal
```

## Development Workflow

### Adding New Recipes
1. Add content to `rag-system/data/recetas/[meal-type].txt`
2. Run `make index-rag` to update embeddings
3. Test with RAG API endpoints

### Modifying Workflows
1. Edit n8n workflows through web interface (https://domain/)
2. Export workflow JSON to `n8n/workflows/`
3. Commit changes to version control

### Database Changes
1. Modify `postgres/init/01-init.sql`
2. Test with clean environment: `make clean-data && make start`
3. Update any affected application code

## Monitoring and Maintenance

### Regular Tasks
- Daily backups via `make backup`
- Monitor logs with `make logs`
- Check health with `make health`
- Update system with `make update`

### Troubleshooting
- Check service status: `make status`
- View specific logs: `make logs-service SERVICE=postgres`
- Database shell: `make shell-postgres`
- RAG container access: `make shell-rag`

### Common Issues
- n8n not starting: Check PostgreSQL connection
- RAG API errors: Verify OpenAI API key and knowledge base
- WhatsApp webhook fails: Check domain SSL and webhook URL
- Database connection issues: Verify credentials in .env

## Security Considerations

### SSL/HTTPS
- All endpoints use HTTPS in production
- Certificates in `nginx/ssl/`
- Auto-renewal with certbot

### Secrets Management
- All sensitive data in `.env`
- Never commit real credentials
- Rotate tokens regularly

### Access Control
- n8n admin interface password protected
- WhatsApp webhook token verification
- Database user with limited privileges

## Deployment

### Initial Setup
1. Run `./scripts/install.sh` on Ubuntu 24.04
2. Configure `.env` with production values
3. Set up SSL certificates
4. Configure WhatsApp Business webhook
5. Import n8n workflows
6. Index RAG knowledge base

### Production Updates
```bash
git pull origin main
make prod-deploy
make health
```

## Testing

### Telegram Testing
```bash
# Test complete flow
./scripts/test-telegram.sh

# Test specific functions
make test-telegram USER_ID=123456789 TEXT="🆕 Plan Nuevo"
make test-telegram-menu
make test-telegram-nuevo

# Interactive testing
./scripts/test-telegram.sh -i

# Bot information
make telegram-info
```

### Manual Testing
- Telegram integration: `make test-telegram USER_ID=123456789`
- RAG API: `curl http://localhost:8000/health` 
- Database: `make shell-postgres`
- Telegram webhook: `curl http://localhost:8000/telegram/webhook`

### Health Checks
- All services: `make health`
- Individual components via Docker health checks
- Automated monitoring script in `scripts/monitor.sh`
- Telegram bot status: `curl http://localhost:8000/telegram/info`