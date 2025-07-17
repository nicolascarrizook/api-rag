#!/bin/bash
set -e

# WhatsApp Nutrition Bot Installation Script
# For Ubuntu 24.04 LTS

echo "=== WhatsApp Nutrition Bot Installation ==="
echo "Starting installation on Ubuntu 24.04 LTS..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root for security reasons"
fi

# Check Ubuntu version
if ! grep -q "Ubuntu 24.04" /etc/os-release; then
    warn "This script is designed for Ubuntu 24.04 LTS. Proceeding anyway..."
fi

log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

log "Installing system dependencies..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    docker.io \
    docker-compose \
    python3-pip \
    nginx \
    certbot \
    python3-certbot-nginx \
    ufw \
    fail2ban \
    git \
    htop \
    ncdu \
    unzip \
    wget \
    jq \
    rsync

log "Configuring Docker..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

log "Configuring firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable

log "Setting up fail2ban..."
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Configure fail2ban for SSH
cat > /tmp/fail2ban-ssh.conf << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

sudo mv /tmp/fail2ban-ssh.conf /etc/fail2ban/jail.d/sshd.conf
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

log "Creating application directory structure..."
APP_DIR="/home/$USER/whatsapp-nutrition-bot"
if [ -d "$APP_DIR" ]; then
    warn "Application directory already exists. Backing up..."
    sudo mv "$APP_DIR" "${APP_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
fi

mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Create directory structure matching our project
mkdir -p {n8n/{data,workflows},postgres/{data,init},redis/data,rag-system/{embeddings,data/{recetas,ingredientes,planes-ejemplo},scripts,api},whatsapp/{config,logs},nginx/{ssl,conf.d},scripts,logs,backups}

log "Setting up SSL certificates..."
read -p "Enter your domain name (e.g., yourdomain.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    error "Domain name is required"
fi

# Update environment file with domain
if [ -f ".env" ]; then
    sed -i "s/tu-dominio.com/$DOMAIN_NAME/g" .env
    sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN_NAME/" .env
fi

# Create SSL directory and generate self-signed certificates for development
log "Creating SSL certificates..."
sudo mkdir -p nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/key.pem \
    -out nginx/ssl/cert.pem \
    -subj "/C=AR/ST=Buenos Aires/L=Buenos Aires/O=Nutrition Bot/CN=$DOMAIN_NAME" 2>/dev/null

# Set proper permissions
sudo chown -R $USER:$USER "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod 600 nginx/ssl/*.pem

log "Installing Python dependencies for RAG system..."
pip3 install --user virtualenv

log "Creating backup directories..."
mkdir -p backups/{database,files,logs}

log "Setting up log rotation..."
cat > /tmp/nutrition-bot-logrotate << 'EOF'
/home/*/whatsapp-nutrition-bot/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 ubuntu ubuntu
    postrotate
        docker restart nutrition_nginx > /dev/null 2>&1 || true
    endscript
}
EOF

sudo mv /tmp/nutrition-bot-logrotate /etc/logrotate.d/nutrition-bot

log "Setting up monitoring..."
# Create monitoring script
cat > scripts/monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for Nutrition Bot

CONTAINERS=("nutrition_postgres" "nutrition_redis" "nutrition_n8n" "nutrition_rag" "nutrition_nginx")
ALERT_EMAIL=${ALERT_EMAIL:-"admin@localhost"}

check_container() {
    local container=$1
    if ! docker ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
        echo "ALERT: Container $container is not running"
        # Send alert (implement email/webhook notification as needed)
        return 1
    fi
    return 0
}

check_disk_space() {
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $usage -gt 80 ]; then
        echo "ALERT: Disk usage is at ${usage}%"
        return 1
    fi
    return 0
}

check_memory() {
    local mem_usage=$(free | awk 'NR==2{printf "%.2f", $3*100/$2 }')
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        echo "ALERT: Memory usage is at ${mem_usage}%"
        return 1
    fi
    return 0
}

# Main monitoring logic
echo "Checking system health at $(date)"

all_ok=true

for container in "${CONTAINERS[@]}"; do
    if ! check_container "$container"; then
        all_ok=false
    fi
done

if ! check_disk_space; then
    all_ok=false
fi

if ! check_memory; then
    all_ok=false
fi

if $all_ok; then
    echo "All systems operational"
else
    echo "Some issues detected"
    exit 1
fi
EOF

chmod +x scripts/monitor.sh

# Add monitoring to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * $APP_DIR/scripts/monitor.sh >> $APP_DIR/logs/monitor.log 2>&1") | crontab -

log "Creating system service for auto-start..."
cat > /tmp/nutrition-bot.service << EOF
[Unit]
Description=WhatsApp Nutrition Bot
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/nutrition-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nutrition-bot.service

log "Setting up automatic backups..."
cat > scripts/backup.sh << 'EOF'
#!/bin/bash

# Backup script for Nutrition Bot
BACKUP_DIR="/home/$USER/whatsapp-nutrition-bot/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="nutrition_bot_backup_${DATE}"

# Create backup directory
mkdir -p ${BACKUP_DIR}/${BACKUP_NAME}

echo "Starting backup at $(date)"

# Backup PostgreSQL
if docker ps --filter "name=nutrition_postgres" --filter "status=running" | grep -q "nutrition_postgres"; then
    echo "Backing up PostgreSQL..."
    docker exec nutrition_postgres pg_dump -U nutrition_admin nutrition_bot > ${BACKUP_DIR}/${BACKUP_NAME}/postgres_backup.sql
    if [ $? -eq 0 ]; then
        echo "PostgreSQL backup completed"
    else
        echo "PostgreSQL backup failed"
        exit 1
    fi
else
    echo "PostgreSQL container not running, skipping database backup"
fi

# Backup n8n workflows
echo "Backing up n8n data..."
if [ -d "n8n/data" ]; then
    cp -r n8n/data ${BACKUP_DIR}/${BACKUP_NAME}/n8n_data
    echo "n8n backup completed"
fi

# Backup RAG data
echo "Backing up RAG system data..."
if [ -d "rag-system/data" ]; then
    cp -r rag-system/data ${BACKUP_DIR}/${BACKUP_NAME}/rag_data
fi

if [ -d "rag-system/embeddings" ]; then
    cp -r rag-system/embeddings ${BACKUP_DIR}/${BACKUP_NAME}/rag_embeddings
fi

# Backup configuration files
echo "Backing up configuration..."
cp .env ${BACKUP_DIR}/${BACKUP_NAME}/ 2>/dev/null || true
cp docker-compose.yml ${BACKUP_DIR}/${BACKUP_NAME}/ 2>/dev/null || true

# Compress backup
echo "Compressing backup..."
cd ${BACKUP_DIR}
tar -czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}
rm -rf ${BACKUP_NAME}

# Clean old backups (keep last 7 days)
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: ${BACKUP_NAME}.tar.gz"
echo "Backup size: $(du -h ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz | cut -f1)"
EOF

chmod +x scripts/backup.sh

# Add daily backup to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * $APP_DIR/scripts/backup.sh >> $APP_DIR/logs/backup.log 2>&1") | crontab -

log "Setting up environment variables..."
if [ ! -f ".env" ]; then
    warn ".env file not found. You'll need to create it manually."
    cat > .env << 'EOF'
# Copy from .env.example and configure your values
DOMAIN=your-domain.com
POSTGRES_PASSWORD=change-this-password
REDIS_PASSWORD=change-this-password
N8N_PASSWORD=change-this-password
OPENAI_API_KEY=your-openai-key
WHATSAPP_ACCESS_TOKEN=your-whatsapp-token
WHATSAPP_PHONE_NUMBER_ID=your-phone-id
WHATSAPP_VERIFY_TOKEN=your-verify-token
EOF
fi

log "Creating useful aliases..."
cat >> ~/.bashrc << 'EOF'

# Nutrition Bot aliases
alias nb-start='cd ~/whatsapp-nutrition-bot && docker-compose up -d'
alias nb-stop='cd ~/whatsapp-nutrition-bot && docker-compose down'
alias nb-restart='cd ~/whatsapp-nutrition-bot && docker-compose restart'
alias nb-logs='cd ~/whatsapp-nutrition-bot && docker-compose logs -f'
alias nb-status='cd ~/whatsapp-nutrition-bot && docker-compose ps'
alias nb-backup='cd ~/whatsapp-nutrition-bot && ./scripts/backup.sh'
alias nb-monitor='cd ~/whatsapp-nutrition-bot && ./scripts/monitor.sh'
EOF

log "Installation completed successfully!"
echo ""
echo "Next steps:"
echo "1. Configure your .env file with proper values"
echo "2. Add nutrition knowledge data to rag-system/data/"
echo "3. Run: make install (to build and start services)"
echo "4. Configure WhatsApp Business API webhooks"
echo "5. Access n8n at: https://$DOMAIN_NAME"
echo ""
echo "Useful commands:"
echo "  nb-start    - Start all services"
echo "  nb-stop     - Stop all services"
echo "  nb-logs     - View logs"
echo "  nb-status   - Check service status"
echo "  nb-backup   - Create backup"
echo ""
warn "Remember to:"
warn "1. Update all passwords in .env file"
warn "2. Configure proper SSL certificates for production"
warn "3. Set up proper DNS for your domain"
warn "4. Configure email alerts for monitoring"
echo ""
log "Reboot recommended to apply all changes. Run: sudo reboot"