#!/bin/bash

# Script de deploy para la Mini API RAG
# Automatiza el deployment en un servidor Ubuntu

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO: $1${NC}"
}

# Configuration
API_DIR="/opt/nutrition-rag-api"
API_USER="rag-api"
PYTHON_VERSION="3.11"

# Parse command line arguments
OPENAI_API_KEY=""
SERVER_IP=""
FORCE_REINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --openai-key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --openai-key YOUR_KEY --server-ip YOUR_IP [--force]"
            echo ""
            echo "Options:"
            echo "  --openai-key    OpenAI API key"
            echo "  --server-ip     Server IP address"
            echo "  --force         Force reinstall even if already exists"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$OPENAI_API_KEY" ]]; then
    error "OpenAI API key is required. Use --openai-key"
    exit 1
fi

if [[ -z "$SERVER_IP" ]]; then
    error "Server IP is required. Use --server-ip"
    exit 1
fi

log "Starting deployment of Nutrition RAG API"
log "Target directory: $API_DIR"
log "Server IP: $SERVER_IP"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# Check if already installed
if [[ -d "$API_DIR" && "$FORCE_REINSTALL" != true ]]; then
    warn "API already installed at $API_DIR"
    read -p "Continue with reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
fi

# Update system
log "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
log "Installing required packages..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    supervisor \
    nginx \
    ufw \
    git \
    htop \
    curl \
    wget \
    unzip

# Create API user
if ! id "$API_USER" &>/dev/null; then
    log "Creating API user: $API_USER"
    useradd --system --shell /bin/bash --home /home/$API_USER --create-home $API_USER
else
    info "User $API_USER already exists"
fi

# Create API directory
log "Setting up API directory..."
mkdir -p $API_DIR
chown $API_USER:$API_USER $API_DIR

# Copy API files (assuming they're in the current directory)
log "Copying API files..."
if [[ -f "simple-rag-api/rag_api.py" ]]; then
    cp -r simple-rag-api/* $API_DIR/
else
    # Download from repository if files not present
    warn "API files not found locally. Please ensure simple-rag-api/ directory exists"
    exit 1
fi

# Set ownership
chown -R $API_USER:$API_USER $API_DIR

# Create virtual environment
log "Creating Python virtual environment..."
sudo -u $API_USER python3 -m venv $API_DIR/venv

# Install Python dependencies
log "Installing Python dependencies..."
sudo -u $API_USER $API_DIR/venv/bin/pip install --upgrade pip
sudo -u $API_USER $API_DIR/venv/bin/pip install -r $API_DIR/requirements.txt

# Create environment file
log "Creating environment configuration..."
cat > $API_DIR/.env << EOF
# OpenAI Configuration
OPENAI_API_KEY=$OPENAI_API_KEY

# API Configuration
API_HOST=0.0.0.0
API_PORT=8001
API_RELOAD=false

# ChromaDB Configuration
CHROMA_PERSIST_DIRECTORY=$API_DIR/chroma_db
COLLECTION_NAME=nutrition_knowledge

# Document Processing
CHUNK_SIZE=500
CHUNK_OVERLAP=50
MAX_SEARCH_RESULTS=5
EOF

chown $API_USER:$API_USER $API_DIR/.env
chmod 600 $API_DIR/.env

# Create data directories
log "Creating data directories..."
mkdir -p $API_DIR/chroma_db $API_DIR/uploads $API_DIR/logs
chown -R $API_USER:$API_USER $API_DIR/chroma_db $API_DIR/uploads $API_DIR/logs

# Create supervisor configuration
log "Configuring supervisor..."
cat > /etc/supervisor/conf.d/nutrition-rag-api.conf << EOF
[program:nutrition-rag-api]
command=$API_DIR/venv/bin/python rag_api.py
directory=$API_DIR
user=$API_USER
autostart=true
autorestart=true
stderr_logfile=$API_DIR/logs/api.err.log
stdout_logfile=$API_DIR/logs/api.out.log
environment=PATH="$API_DIR/venv/bin"
EOF

# Create nginx configuration
log "Configuring nginx..."
cat > /etc/nginx/sites-available/nutrition-rag-api << EOF
server {
    listen 80;
    server_name $SERVER_IP;

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Authorization, Content-Type";
        
        # Handle preflight OPTIONS requests
        if (\$request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
    }
}
EOF

# Enable nginx site
ln -sf /etc/nginx/sites-available/nutrition-rag-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t

# Configure firewall
log "Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80
ufw allow 443
ufw allow 8001

# Restart services
log "Starting services..."
supervisorctl reread
supervisorctl update
supervisorctl start nutrition-rag-api
systemctl restart nginx

# Wait for API to start
log "Waiting for API to start..."
sleep 10

# Test API
log "Testing API health..."
if curl -f http://localhost:8001/health > /dev/null 2>&1; then
    log "✅ API is healthy and responding"
else
    error "❌ API health check failed"
    warn "Check logs: tail -f $API_DIR/logs/api.err.log"
fi

# Create management scripts
log "Creating management scripts..."

# Create start script
cat > /usr/local/bin/rag-start << 'EOF'
#!/bin/bash
supervisorctl start nutrition-rag-api
echo "RAG API started"
EOF

# Create stop script
cat > /usr/local/bin/rag-stop << 'EOF'
#!/bin/bash
supervisorctl stop nutrition-rag-api
echo "RAG API stopped"
EOF

# Create restart script
cat > /usr/local/bin/rag-restart << 'EOF'
#!/bin/bash
supervisorctl restart nutrition-rag-api
echo "RAG API restarted"
EOF

# Create status script
cat > /usr/local/bin/rag-status << 'EOF'
#!/bin/bash
echo "=== Supervisor Status ==="
supervisorctl status nutrition-rag-api
echo ""
echo "=== API Health ==="
curl -s http://localhost:8001/health | python3 -m json.tool || echo "API not responding"
echo ""
echo "=== Nginx Status ==="
systemctl status nginx --no-pager -l
EOF

# Create logs script
cat > /usr/local/bin/rag-logs << 'EOF'
#!/bin/bash
tail -f /opt/nutrition-rag-api/logs/api.out.log
EOF

# Make scripts executable
chmod +x /usr/local/bin/rag-{start,stop,restart,status,logs}

# Create update script
cat > /usr/local/bin/rag-update << EOF
#!/bin/bash
cd $API_DIR
sudo -u $API_USER git pull
sudo -u $API_USER $API_DIR/venv/bin/pip install -r requirements.txt
supervisorctl restart nutrition-rag-api
echo "RAG API updated and restarted"
EOF

chmod +x /usr/local/bin/rag-update

# Final status check
log "Final status check..."
sleep 5

API_STATUS=$(curl -s http://localhost:8001/health | python3 -c "import sys, json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "error")

if [[ "$API_STATUS" == "healthy" ]]; then
    log "🎉 Deployment completed successfully!"
    echo ""
    info "API URL: http://$SERVER_IP"
    info "Health check: http://$SERVER_IP/health"
    info "Docs: http://$SERVER_IP/docs"
    echo ""
    info "Management commands:"
    info "  rag-start     - Start the API"
    info "  rag-stop      - Stop the API"  
    info "  rag-restart   - Restart the API"
    info "  rag-status    - Check status"
    info "  rag-logs      - View logs"
    info "  rag-update    - Update from git"
    echo ""
    info "Next steps:"
    info "1. Upload your Word documents using the document processor"
    info "2. Configure your n8n workflow with this API URL"
    info "3. Test the complete flow"
    echo ""
    warn "Remember to:"
    warn "- Keep your OpenAI API key secure"
    warn "- Regular backups of $API_DIR/chroma_db/"
    warn "- Monitor logs in $API_DIR/logs/"
else
    error "❌ Deployment failed - API is not healthy"
    error "Check logs: tail -f $API_DIR/logs/api.err.log"
    exit 1
fi