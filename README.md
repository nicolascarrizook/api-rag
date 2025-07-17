# Telegram Nutrition Bot 🥗

Automated nutrition consultation system for Telegram that generates personalized meal plans using AI and the "Tres Días y Carga | Dieta Inteligente® & Nutrición Evolutiva" methodology.

> **📱 Platform**: Now optimized for Telegram instead of WhatsApp for easier setup and no costs!

## 🚀 Features

- **Three Consultation Types**: New patient, control, and meal replacement
- **AI-Powered**: GPT-4 with RAG for contextual meal planning
- **Telegram Integration**: Native Telegram Bot API support (FREE!)
- **Comprehensive Database**: Patient tracking, conversation history, progress monitoring
- **Argentine Methodology**: Specialized nutrition approach with local terminology
- **Automated Workflows**: n8n-based message processing and response generation
- **Production Ready**: Docker deployment with SSL, monitoring, and backups

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Telegram      │    │     n8n      │    │   PostgreSQL    │
│   Bot API       │◄──►│   Workflows  │◄──►│   Database      │
└─────────────────┘    └──────┬───────┘    └─────────────────┘
                              │
                    ┌─────────▼─────────┐    ┌─────────────────┐
                    │   RAG System     │◄──►│     Redis       │
                    │  (FastAPI +      │    │     Cache       │
                    │   ChromaDB)      │    └─────────────────┘
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │   OpenAI GPT-4   │
                    │  Meal Planning   │
                    └───────────────────┘
```

## 📋 Prerequisites

- Ubuntu 24.04 LTS server (or any system with Docker)
- Docker and Docker Compose
- Domain name with DNS configured (optional for development)
- **Telegram Bot Token** (free from @BotFather)
- **OpenAI API key** (for meal plan generation)

## ⚡ Quick Start

### 1. Clone and Install

```bash
git clone <repository-url>
cd whatsapp-nutrition-bot
chmod +x scripts/install.sh
./scripts/install.sh
```

### 2. Configure Environment

```bash
cp .env.example .env
nano .env
```

Required variables:
```env
DOMAIN=your-domain.com
OPENAI_API_KEY=sk-your-openai-key
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_WEBHOOK_SECRET=your-webhook-secret-key
POSTGRES_PASSWORD=secure-password
REDIS_PASSWORD=secure-password
N8N_PASSWORD=secure-password
```

### 3. Start Services

```bash
make start
```

### 4. Setup SSL (Production)

```bash
make ssl-setup
```

### 5. Configure Telegram Webhook

Set your Telegram webhook URL:
```bash
make telegram-set-webhook DOMAIN=your-domain.com
```

Or use the direct API:
```
https://your-domain.com/api/rag/telegram/webhook
```

## 🛠️ Development

### Common Commands

```bash
# Start services
make start

# View logs
make logs

# Check health
make health

# Create backup
make backup

# Stop services
make stop

# Complete list
make help
```

### Project Structure

```
├── docker-compose.yml          # Main orchestration
├── .env                        # Environment variables
├── Makefile                    # Development commands
├── postgres/
│   └── init/01-init.sql       # Database schema
├── n8n/
│   └── workflows/             # WhatsApp workflows
├── rag-system/
│   ├── api/rag_api.py         # RAG FastAPI service
│   ├── scripts/rag_indexer.py # Knowledge indexer
│   └── data/                  # Nutrition knowledge base
├── nginx/
│   └── nginx.conf             # Reverse proxy config
└── scripts/
    ├── install.sh             # System installation
    ├── backup.sh              # Backup automation
    └── restore.sh             # Restore automation
```

## 🍽️ Nutrition Methodology

### Three Motors System

1. **Motor 1 (Nuevo)**: Complete new patient consultation
   - Collects: name, age, weight, height, activity level, objectives
   - Generates: Full 3-day meal plan with macros

2. **Motor 2 (Control)**: Follow-up consultation
   - Updates progress metrics
   - Adjusts existing plan based on results

3. **Motor 3 (Reemplazo)**: Meal replacement
   - Replaces specific meals (breakfast, lunch, snack, dinner)
   - Maintains overall nutritional balance

### Plan Format

```
PLAN ALIMENTARIO - MARÍA GARCÍA
Objetivo: -0.5kg por semana
=== DÍA 1, 2 y 3 ===

DESAYUNO (08:00 hs)
• Yogur griego descremado: 200g
• Avena tradicional: 40g
• Banana: 100g
• Almendras: 15g
Preparación: Cocinar la avena con agua...

ALMUERZO (13:00 hs)
• Pechuga de pollo: 150g
• Batata: 120g
• Brócoli: 150g
• Aceite de oliva: 10g
Preparación: Cocinar la pechuga a la plancha...

[Merienda y Cena...]

Macros diarios: P: 125g | C: 140g | G: 58g
Calorías: 1480 kcal
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `DOMAIN` | Your domain name | Yes |
| `OPENAI_API_KEY` | OpenAI API key | Yes |
| `WHATSAPP_ACCESS_TOKEN` | WhatsApp Business token | Yes |
| `WHATSAPP_PHONE_NUMBER_ID` | WhatsApp phone number ID | Yes |
| `POSTGRES_PASSWORD` | Database password | Yes |
| `REDIS_PASSWORD` | Redis password | Yes |
| `N8N_PASSWORD` | n8n admin password | Yes |

### WhatsApp Setup

1. Create WhatsApp Business app
2. Get access token and phone number ID
3. Configure webhook URL: `https://your-domain.com/webhook/whatsapp-webhook`
4. Set verify token in environment variables

### n8n Workflows

Access n8n interface at `https://your-domain.com` and import workflows from `n8n/workflows/`.

## 📊 Monitoring

### Health Checks

```bash
# Check all services
make health

# View service status
make status

# Monitor logs
make logs

# Run system monitoring
make monitor
```

### Backup and Restore

```bash
# Create full backup
make backup

# Restore from backup
make restore BACKUP=filename.tar.gz

# Database only backup
make db-backup
```

## 🚀 Deployment

### Production Deployment

1. **Server Setup**
   ```bash
   ./scripts/install.sh
   ```

2. **Configure Environment**
   ```bash
   nano .env
   # Set production values
   ```

3. **SSL Certificates**
   ```bash
   make ssl-setup
   ```

4. **Start Services**
   ```bash
   make start
   ```

5. **Verify Health**
   ```bash
   make health
   ```

### Updates

```bash
make update
# or
make prod-deploy
```

## 🔍 Troubleshooting

### Common Issues

1. **n8n not starting**
   - Check PostgreSQL connection
   - Verify database credentials in `.env`

2. **RAG API errors**
   - Verify OpenAI API key
   - Check knowledge base indexing: `make index-rag`

3. **WhatsApp webhook fails**
   - Verify SSL certificate
   - Check webhook URL configuration
   - Verify WhatsApp tokens

4. **Database connection issues**
   - Check PostgreSQL container: `docker ps`
   - Verify credentials in `.env`
   - Check logs: `make logs-service SERVICE=postgres`

### Debugging Commands

```bash
# Container shells
make shell-postgres  # PostgreSQL shell
make shell-redis     # Redis shell
make shell-rag       # RAG container shell

# Specific service logs
make logs-service SERVICE=postgres
make logs-service SERVICE=n8n
make logs-service SERVICE=rag_api

# Configuration check
make config-check
```

## 📚 API Reference

### RAG API Endpoints

- `GET /health` - Health check
- `POST /search` - Search nutrition knowledge
- `POST /context` - Generate contextual information
- `GET /stats` - Knowledge base statistics
- `POST /reindex` - Reindex knowledge base

### Database Schema

Key tables:
- `patients` - Patient information
- `conversations` - Message history
- `meal_plans` - Generated plans
- `patient_metrics` - Progress tracking
- `ingredients` - Nutritional database

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Update documentation
5. Submit pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Check the troubleshooting section
- Review logs with `make logs`
- Open an issue in the repository

## 🔐 Security

- All passwords in `.env` file
- HTTPS enforced in production
- Regular security updates recommended
- Webhook token verification enabled
- Database access restricted

---

**Made with ❤️ for nutrition professionals**