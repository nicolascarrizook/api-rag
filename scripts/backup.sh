#!/bin/bash

# WhatsApp Nutrition Bot - Backup Script
# Creates full system backup including database, configurations, and data

set -e

# Configuration
BACKUP_DIR="/home/$USER/whatsapp-nutrition-bot/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="nutrition_bot_backup_${DATE}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Check if running from correct directory
if [ ! -f "docker-compose.yml" ]; then
    error "Please run this script from the WhatsApp Nutrition Bot directory"
fi

# Create backup directory
mkdir -p ${BACKUP_DIR}/${BACKUP_NAME}

log "Starting backup: ${BACKUP_NAME}"

# Function to check if container is running
is_container_running() {
    docker ps --filter "name=$1" --filter "status=running" | grep -q "$1"
}

# Function to backup PostgreSQL
backup_postgres() {
    log "Backing up PostgreSQL database..."
    
    if is_container_running "nutrition_postgres"; then
        # Get database credentials from environment
        source .env 2>/dev/null || true
        
        # Create database backup
        docker exec nutrition_postgres pg_dump \
            -U ${POSTGRES_USER:-nutrition_admin} \
            -d ${POSTGRES_DB:-nutrition_bot} \
            --clean \
            --if-exists \
            --format=custom \
            --verbose \
            > ${BACKUP_DIR}/${BACKUP_NAME}/postgres_backup.dump
        
        if [ $? -eq 0 ]; then
            # Also create a plain SQL backup for easier recovery
            docker exec nutrition_postgres pg_dump \
                -U ${POSTGRES_USER:-nutrition_admin} \
                -d ${POSTGRES_DB:-nutrition_bot} \
                --clean \
                --if-exists \
                > ${BACKUP_DIR}/${BACKUP_NAME}/postgres_backup.sql
            
            log "PostgreSQL backup completed"
            
            # Get database size
            DB_SIZE=$(docker exec nutrition_postgres psql -U ${POSTGRES_USER:-nutrition_admin} -d ${POSTGRES_DB:-nutrition_bot} -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-nutrition_bot}'));")
            echo "Database size: ${DB_SIZE}" > ${BACKUP_DIR}/${BACKUP_NAME}/database_info.txt
        else
            error "PostgreSQL backup failed"
        fi
    else
        warn "PostgreSQL container not running, skipping database backup"
    fi
}

# Function to backup Redis data
backup_redis() {
    log "Backing up Redis data..."
    
    if is_container_running "nutrition_redis"; then
        # Create Redis backup
        docker exec nutrition_redis redis-cli BGSAVE
        sleep 5  # Wait for background save to complete
        
        # Copy the RDB file
        docker cp nutrition_redis:/data/dump.rdb ${BACKUP_DIR}/${BACKUP_NAME}/redis_dump.rdb
        
        if [ $? -eq 0 ]; then
            log "Redis backup completed"
        else
            warn "Redis backup failed"
        fi
    else
        warn "Redis container not running, skipping Redis backup"
    fi
}

# Function to backup n8n data
backup_n8n() {
    log "Backing up n8n workflows and data..."
    
    if [ -d "n8n/data" ]; then
        cp -r n8n/data ${BACKUP_DIR}/${BACKUP_NAME}/n8n_data
        log "n8n data backup completed"
    else
        warn "n8n data directory not found"
    fi
    
    # Backup n8n workflows separately
    if [ -d "n8n/workflows" ]; then
        cp -r n8n/workflows ${BACKUP_DIR}/${BACKUP_NAME}/n8n_workflows
        log "n8n workflows backup completed"
    fi
}

# Function to backup RAG system
backup_rag() {
    log "Backing up RAG system data..."
    
    # Backup knowledge base
    if [ -d "rag-system/data" ]; then
        cp -r rag-system/data ${BACKUP_DIR}/${BACKUP_NAME}/rag_data
        log "RAG knowledge base backup completed"
    else
        warn "RAG data directory not found"
    fi
    
    # Backup embeddings
    if [ -d "rag-system/embeddings" ]; then
        cp -r rag-system/embeddings ${BACKUP_DIR}/${BACKUP_NAME}/rag_embeddings
        log "RAG embeddings backup completed"
    else
        warn "RAG embeddings directory not found"
    fi
}

# Function to backup configuration files
backup_config() {
    log "Backing up configuration files..."
    
    # Core configuration files
    files=(".env" "docker-compose.yml" "nginx/nginx.conf")
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" ${BACKUP_DIR}/${BACKUP_NAME}/
        else
            warn "Configuration file not found: $file"
        fi
    done
    
    # Backup SSL certificates if they exist
    if [ -d "nginx/ssl" ]; then
        cp -r nginx/ssl ${BACKUP_DIR}/${BACKUP_NAME}/ssl_certs
        log "SSL certificates backed up"
    fi
    
    log "Configuration backup completed"
}

# Function to backup logs
backup_logs() {
    log "Backing up recent logs..."
    
    # Create logs backup directory
    mkdir -p ${BACKUP_DIR}/${BACKUP_NAME}/logs
    
    # Backup application logs (last 7 days)
    if [ -d "logs" ]; then
        find logs -name "*.log" -mtime -7 -exec cp {} ${BACKUP_DIR}/${BACKUP_NAME}/logs/ \;
    fi
    
    # Backup Docker container logs
    containers=("nutrition_postgres" "nutrition_redis" "nutrition_n8n" "nutrition_rag" "nutrition_nginx")
    
    for container in "${containers[@]}"; do
        if is_container_running "$container"; then
            docker logs --since=7d "$container" > ${BACKUP_DIR}/${BACKUP_NAME}/logs/${container}.log 2>&1 || true
        fi
    done
    
    log "Logs backup completed"
}

# Function to create backup metadata
create_metadata() {
    log "Creating backup metadata..."
    
    cat > ${BACKUP_DIR}/${BACKUP_NAME}/backup_info.txt << EOF
Backup Information
==================
Backup Name: ${BACKUP_NAME}
Created: $(date)
Host: $(hostname)
User: $(whoami)
System: $(uname -a)

Docker Images:
$(docker images --filter "reference=*nutrition*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}")

Running Containers:
$(docker ps --filter "name=nutrition_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

Disk Usage:
$(df -h /)

Memory Usage:
$(free -h)

Backup Contents:
$(find ${BACKUP_DIR}/${BACKUP_NAME} -type f | sort)

Backup Sizes:
$(du -sh ${BACKUP_DIR}/${BACKUP_NAME}/* 2>/dev/null | sort -hr)
EOF

    log "Backup metadata created"
}

# Function to compress backup
compress_backup() {
    log "Compressing backup..."
    
    cd ${BACKUP_DIR}
    tar -czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}
    
    if [ $? -eq 0 ]; then
        rm -rf ${BACKUP_NAME}
        BACKUP_SIZE=$(du -h ${BACKUP_NAME}.tar.gz | cut -f1)
        log "Backup compressed successfully: ${BACKUP_SIZE}"
    else
        error "Backup compression failed"
    fi
}

# Function to clean old backups
cleanup_old_backups() {
    log "Cleaning up old backups (keeping last ${RETENTION_DAYS} days)..."
    
    find ${BACKUP_DIR} -name "nutrition_bot_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete
    
    # Count remaining backups
    BACKUP_COUNT=$(find ${BACKUP_DIR} -name "nutrition_bot_backup_*.tar.gz" | wc -l)
    log "Cleanup completed. ${BACKUP_COUNT} backups retained"
}

# Function to upload to cloud storage (optional)
upload_backup() {
    if [ -n "${S3_BUCKET}" ] && command -v aws &> /dev/null; then
        log "Uploading backup to S3..."
        
        aws s3 cp ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz s3://${S3_BUCKET}/backups/
        
        if [ $? -eq 0 ]; then
            log "Backup uploaded to S3 successfully"
        else
            warn "S3 upload failed"
        fi
    fi
    
    # Add support for other cloud providers here
    # (Google Cloud, Azure, etc.)
}

# Function to send notification
send_notification() {
    local status=$1
    local message=$2
    
    # Email notification (if configured)
    if [ -n "${BACKUP_EMAIL}" ] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "Nutrition Bot Backup: $status" "${BACKUP_EMAIL}"
    fi
    
    # Webhook notification (if configured)
    if [ -n "${BACKUP_WEBHOOK_URL}" ]; then
        curl -X POST "${BACKUP_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"status\":\"$status\",\"message\":\"$message\",\"timestamp\":\"$(date)\"}" \
            &> /dev/null || true
    fi
}

# Main backup execution
main() {
    local start_time=$(date +%s)
    
    # Create backup directory
    mkdir -p ${BACKUP_DIR}
    
    # Execute backup steps
    backup_postgres
    backup_redis
    backup_n8n
    backup_rag
    backup_config
    backup_logs
    create_metadata
    compress_backup
    cleanup_old_backups
    upload_backup
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local success_message="Backup completed successfully in ${duration} seconds
Backup file: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz
Backup size: $(du -h ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz | cut -f1)"
    
    log "$success_message"
    send_notification "SUCCESS" "$success_message"
}

# Error handling
trap 'error "Backup failed at line $LINENO"' ERR

# Execute main function
main "$@"