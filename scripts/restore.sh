#!/bin/bash

# WhatsApp Nutrition Bot - Restore Script
# Restores system from backup

set -e

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

# Usage information
usage() {
    echo "Usage: $0 <backup_file.tar.gz> [options]"
    echo ""
    echo "Options:"
    echo "  --force       Skip confirmation prompts"
    echo "  --db-only     Restore only database"
    echo "  --no-db       Skip database restore"
    echo "  --help        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 nutrition_bot_backup_20240716_143000.tar.gz"
    echo "  $0 backup.tar.gz --db-only"
    echo "  $0 backup.tar.gz --force"
}

# Parse command line arguments
BACKUP_FILE=""
FORCE=false
DB_ONLY=false
NO_DB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --no-db)
            NO_DB=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option $1"
            ;;
        *)
            if [ -z "$BACKUP_FILE" ]; then
                BACKUP_FILE="$1"
            else
                error "Multiple backup files specified"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$BACKUP_FILE" ]; then
    error "Backup file not specified"
fi

if [ "$DB_ONLY" = true ] && [ "$NO_DB" = true ]; then
    error "Cannot specify both --db-only and --no-db"
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    # Try to find it in backups directory
    BACKUP_DIR="/home/$USER/whatsapp-nutrition-bot/backups"
    if [ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
        BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    else
        error "Backup file not found: $BACKUP_FILE"
    fi
fi

log "Using backup file: $BACKUP_FILE"

# Check if running from correct directory
if [ ! -f "docker-compose.yml" ]; then
    error "Please run this script from the WhatsApp Nutrition Bot directory"
fi

# Confirmation prompt
if [ "$FORCE" = false ]; then
    echo ""
    warn "This will restore the system from backup and may overwrite existing data!"
    echo "Backup file: $BACKUP_FILE"
    echo "Current directory: $(pwd)"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
fi

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log "Extracting backup to temporary directory..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Find the backup directory
BACKUP_DIR_NAME=$(ls "$TEMP_DIR" | head -n1)
EXTRACT_DIR="$TEMP_DIR/$BACKUP_DIR_NAME"

if [ ! -d "$EXTRACT_DIR" ]; then
    error "Invalid backup file structure"
fi

log "Backup extracted to: $EXTRACT_DIR"

# Display backup information
if [ -f "$EXTRACT_DIR/backup_info.txt" ]; then
    echo ""
    echo "=== Backup Information ==="
    head -20 "$EXTRACT_DIR/backup_info.txt"
    echo "=========================="
    echo ""
fi

# Function to stop services
stop_services() {
    log "Stopping services..."
    docker-compose down || true
    sleep 5
}

# Function to start services
start_services() {
    log "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for services to start..."
    sleep 30
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        log "Services started successfully"
    else
        error "Some services failed to start"
    fi
}

# Function to restore PostgreSQL
restore_postgres() {
    if [ "$NO_DB" = true ]; then
        log "Skipping database restore (--no-db specified)"
        return
    fi
    
    log "Restoring PostgreSQL database..."
    
    # Check if backup files exist
    if [ ! -f "$EXTRACT_DIR/postgres_backup.dump" ] && [ ! -f "$EXTRACT_DIR/postgres_backup.sql" ]; then
        warn "No PostgreSQL backup found, skipping database restore"
        return
    fi
    
    # Make sure PostgreSQL is running
    log "Ensuring PostgreSQL is running..."
    docker-compose up -d postgres
    sleep 10
    
    # Wait for PostgreSQL to be ready
    for i in {1..30}; do
        if docker exec nutrition_postgres pg_isready -U nutrition_admin; then
            break
        fi
        if [ $i -eq 30 ]; then
            error "PostgreSQL not ready after 30 attempts"
        fi
        log "Waiting for PostgreSQL to be ready... ($i/30)"
        sleep 2
    done
    
    # Get database credentials
    source .env 2>/dev/null || true
    
    # Drop and recreate database
    log "Recreating database..."
    docker exec nutrition_postgres psql -U ${POSTGRES_USER:-nutrition_admin} -c "DROP DATABASE IF EXISTS ${POSTGRES_DB:-nutrition_bot};"
    docker exec nutrition_postgres psql -U ${POSTGRES_USER:-nutrition_admin} -c "CREATE DATABASE ${POSTGRES_DB:-nutrition_bot};"
    
    # Restore from custom format if available
    if [ -f "$EXTRACT_DIR/postgres_backup.dump" ]; then
        log "Restoring from custom format backup..."
        docker cp "$EXTRACT_DIR/postgres_backup.dump" nutrition_postgres:/tmp/
        docker exec nutrition_postgres pg_restore \
            -U ${POSTGRES_USER:-nutrition_admin} \
            -d ${POSTGRES_DB:-nutrition_bot} \
            --clean \
            --if-exists \
            --verbose \
            /tmp/postgres_backup.dump
    elif [ -f "$EXTRACT_DIR/postgres_backup.sql" ]; then
        log "Restoring from SQL backup..."
        docker cp "$EXTRACT_DIR/postgres_backup.sql" nutrition_postgres:/tmp/
        docker exec nutrition_postgres psql \
            -U ${POSTGRES_USER:-nutrition_admin} \
            -d ${POSTGRES_DB:-nutrition_bot} \
            -f /tmp/postgres_backup.sql
    fi
    
    log "PostgreSQL restore completed"
}

# Function to restore Redis
restore_redis() {
    if [ "$DB_ONLY" = true ]; then
        return
    fi
    
    log "Restoring Redis data..."
    
    if [ ! -f "$EXTRACT_DIR/redis_dump.rdb" ]; then
        warn "No Redis backup found, skipping Redis restore"
        return
    fi
    
    # Stop Redis container
    docker-compose stop redis
    
    # Replace Redis data
    docker cp "$EXTRACT_DIR/redis_dump.rdb" nutrition_redis:/data/dump.rdb
    
    # Start Redis
    docker-compose start redis
    
    log "Redis restore completed"
}

# Function to restore n8n data
restore_n8n() {
    if [ "$DB_ONLY" = true ]; then
        return
    fi
    
    log "Restoring n8n data..."
    
    # Stop n8n
    docker-compose stop n8n
    
    # Restore n8n data
    if [ -d "$EXTRACT_DIR/n8n_data" ]; then
        rm -rf n8n/data/*
        cp -r "$EXTRACT_DIR/n8n_data"/* n8n/data/
        log "n8n data restored"
    fi
    
    # Restore workflows
    if [ -d "$EXTRACT_DIR/n8n_workflows" ]; then
        rm -rf n8n/workflows/*
        cp -r "$EXTRACT_DIR/n8n_workflows"/* n8n/workflows/
        log "n8n workflows restored"
    fi
    
    # Fix permissions
    sudo chown -R 1000:1000 n8n/data/
    
    # Start n8n
    docker-compose start n8n
    
    log "n8n restore completed"
}

# Function to restore RAG system
restore_rag() {
    if [ "$DB_ONLY" = true ]; then
        return
    fi
    
    log "Restoring RAG system data..."
    
    # Restore knowledge base
    if [ -d "$EXTRACT_DIR/rag_data" ]; then
        rm -rf rag-system/data/*
        cp -r "$EXTRACT_DIR/rag_data"/* rag-system/data/
        log "RAG knowledge base restored"
    fi
    
    # Restore embeddings
    if [ -d "$EXTRACT_DIR/rag_embeddings" ]; then
        rm -rf rag-system/embeddings/*
        cp -r "$EXTRACT_DIR/rag_embeddings"/* rag-system/embeddings/
        log "RAG embeddings restored"
    fi
    
    log "RAG system restore completed"
}

# Function to restore configuration
restore_config() {
    if [ "$DB_ONLY" = true ]; then
        return
    fi
    
    log "Restoring configuration files..."
    
    # Backup current configs
    BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
    
    if [ -f ".env" ]; then
        cp .env ".env.backup_$BACKUP_SUFFIX"
    fi
    
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml "docker-compose.yml.backup_$BACKUP_SUFFIX"
    fi
    
    # Restore configs
    config_files=(".env" "docker-compose.yml" "nginx.conf")
    
    for file in "${config_files[@]}"; do
        if [ -f "$EXTRACT_DIR/$file" ]; then
            cp "$EXTRACT_DIR/$file" ./
            log "Restored: $file"
        fi
    done
    
    # Restore SSL certificates
    if [ -d "$EXTRACT_DIR/ssl_certs" ]; then
        rm -rf nginx/ssl/*
        cp -r "$EXTRACT_DIR/ssl_certs"/* nginx/ssl/
        chmod 600 nginx/ssl/*.pem
        log "SSL certificates restored"
    fi
    
    log "Configuration restore completed"
}

# Function to verify restore
verify_restore() {
    log "Verifying restore..."
    
    # Check if services are running
    if ! docker-compose ps | grep -q "Up"; then
        error "Services are not running after restore"
    fi
    
    # Check database connectivity
    if [ "$NO_DB" = false ]; then
        if ! docker exec nutrition_postgres pg_isready -U nutrition_admin; then
            error "PostgreSQL is not responding after restore"
        fi
        
        # Check if tables exist
        TABLE_COUNT=$(docker exec nutrition_postgres psql -U nutrition_admin -d nutrition_bot -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
        if [ "$TABLE_COUNT" -lt 5 ]; then
            warn "Database may not have been restored correctly (found $TABLE_COUNT tables)"
        else
            log "Database verification passed ($TABLE_COUNT tables found)"
        fi
    fi
    
    # Check RAG system
    if [ "$DB_ONLY" = false ]; then
        if [ -d "rag-system/data" ] && [ "$(ls -A rag-system/data)" ]; then
            log "RAG data verification passed"
        else
            warn "RAG data directory appears empty"
        fi
    fi
    
    log "Restore verification completed"
}

# Main restore function
main() {
    local start_time=$(date +%s)
    
    log "Starting restore from: $BACKUP_FILE"
    
    # Stop services
    stop_services
    
    # Perform restore based on options
    if [ "$DB_ONLY" = true ]; then
        log "Performing database-only restore..."
        start_services
        restore_postgres
    else
        log "Performing full system restore..."
        restore_config
        restore_rag
        restore_n8n
        restore_redis
        start_services
        restore_postgres
    fi
    
    # Wait for services to stabilize
    sleep 10
    
    # Verify restore
    verify_restore
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Restore completed successfully in ${duration} seconds"
    
    # Show service status
    echo ""
    log "Service status after restore:"
    docker-compose ps
    
    echo ""
    log "Restore summary:"
    echo "  Backup file: $BACKUP_FILE"
    echo "  Duration: ${duration} seconds"
    echo "  Options: $([ "$DB_ONLY" = true ] && echo "database-only" || echo "full restore")"
    
    if [ "$DB_ONLY" = false ]; then
        echo ""
        warn "Remember to:"
        warn "1. Verify all services are working correctly"
        warn "2. Test WhatsApp webhook connectivity"
        warn "3. Check n8n workflows are imported"
        warn "4. Verify RAG system is responding"
    fi
}

# Error handling
trap 'error "Restore failed at line $LINENO"' ERR

# Execute main function
main "$@"