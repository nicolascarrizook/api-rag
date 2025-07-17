#!/bin/bash

# Test script para Telegram Bot de Nutrición
# Automatiza las pruebas del flujo completo

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
API_BASE="http://localhost:8000"
TEST_USER_ID=${TEST_USER_ID:-123456789}
TEST_CHAT_ID=${TEST_CHAT_ID:-$TEST_USER_ID}

# Check if services are running
check_services() {
    log "Verificando servicios..."
    
    # Check RAG API
    if ! curl -s "$API_BASE/health" > /dev/null; then
        error "RAG API no está corriendo en $API_BASE"
        exit 1
    fi
    
    log "✅ RAG API está funcionando"
}

# Test Telegram bot info
test_bot_info() {
    log "Probando información del bot..."
    
    response=$(curl -s "$API_BASE/telegram/info" 2>/dev/null)
    
    if echo "$response" | jq -e '.result.username' > /dev/null 2>&1; then
        username=$(echo "$response" | jq -r '.result.username')
        first_name=$(echo "$response" | jq -r '.result.first_name')
        log "✅ Bot conectado: @$username ($first_name)"
        return 0
    else
        warn "❌ No se pudo obtener información del bot"
        warn "Respuesta: $response"
        return 1
    fi
}

# Send test message to webhook
send_telegram_message() {
    local text="$1"
    local user_id="${2:-$TEST_USER_ID}"
    
    local payload='{
        "update_id": '$(date +%s)',
        "message": {
            "message_id": '$(date +%s)',
            "from": {
                "id": '$user_id',
                "is_bot": false,
                "first_name": "TestUser",
                "username": "testuser"
            },
            "chat": {
                "id": '$user_id',
                "type": "private",
                "first_name": "TestUser"
            },
            "date": '$(date +%s)',
            "text": "'"$text"'"
        }
    }'
    
    info "Enviando: '$text' (usuario: $user_id)"
    
    response=$(curl -s -X POST "$API_BASE/telegram/webhook" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    if echo "$response" | jq -e '.status' > /dev/null 2>&1; then
        status=$(echo "$response" | jq -r '.status')
        if [ "$status" = "ok" ]; then
            log "✅ Mensaje procesado correctamente"
            return 0
        else
            warn "❌ Error en procesamiento: $status"
            return 1
        fi
    else
        warn "❌ Respuesta inválida del webhook"
        warn "Respuesta: $response"
        return 1
    fi
}

# Test main menu
test_main_menu() {
    log "🔹 Probando menú principal..."
    send_telegram_message "/start"
    sleep 1
}

# Test new plan flow
test_new_plan_flow() {
    log "🔹 Probando flujo de plan nuevo..."
    
    # Start new plan
    send_telegram_message "🆕 Plan Nuevo"
    sleep 1
    
    # Provide name
    info "Enviando nombre..."
    send_telegram_message "Juan Pérez" "$TEST_USER_ID"
    sleep 1
    
    # Provide age
    info "Enviando edad..."
    send_telegram_message "30" "$TEST_USER_ID"
    sleep 1
    
    # Provide weight
    info "Enviando peso..."
    send_telegram_message "75.5" "$TEST_USER_ID"
    sleep 1
    
    # Provide height
    info "Enviando altura..."
    send_telegram_message "175" "$TEST_USER_ID"
    sleep 1
    
    # Select objective
    info "Enviando objetivo..."
    send_telegram_message "⬇️ Bajar 0.5kg/semana" "$TEST_USER_ID"
    sleep 1
    
    # Select activity level
    info "Enviando nivel de actividad..."
    send_telegram_message "🏃 Moderado" "$TEST_USER_ID"
    sleep 2
    
    log "✅ Flujo de plan nuevo completado"
}

# Test help command
test_help() {
    log "🔹 Probando comando de ayuda..."
    send_telegram_message "/help"
    sleep 1
}

# Test invalid input
test_invalid_input() {
    log "🔹 Probando entrada inválida..."
    send_telegram_message "texto random que no debería ser reconocido"
    sleep 1
}

# Test cancel command
test_cancel() {
    log "🔹 Probando comando cancelar..."
    send_telegram_message "cancelar"
    sleep 1
}

# Main test suite
run_test_suite() {
    log "🚀 Iniciando suite de pruebas para Telegram Bot"
    log "Usuario de prueba: $TEST_USER_ID"
    echo ""
    
    # Check prerequisites
    check_services
    
    # Test bot connection
    if ! test_bot_info; then
        warn "El bot no está configurado correctamente, pero continuando con tests de webhook..."
    fi
    
    echo ""
    log "📝 Ejecutando pruebas funcionales..."
    
    # Basic tests
    test_main_menu
    test_help
    test_invalid_input
    
    # Full flow test
    log "🔄 Probando flujo completo de plan nuevo..."
    test_new_plan_flow
    
    # Cleanup test
    test_cancel
    
    echo ""
    log "✅ Suite de pruebas completada"
    log "Revisá los logs del sistema para ver las respuestas del bot"
}

# Interactive mode
interactive_test() {
    log "🎮 Modo interactivo activado"
    log "Escribe mensajes para enviar al bot (escribe 'quit' para salir)"
    
    while true; do
        echo ""
        read -p "💬 Mensaje: " message
        
        if [ "$message" = "quit" ] || [ "$message" = "exit" ]; then
            log "👋 Saliendo del modo interactivo"
            break
        fi
        
        if [ -n "$message" ]; then
            send_telegram_message "$message"
        fi
    done
}

# Show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -i, --interactive    Modo interactivo para enviar mensajes"
    echo "  -s, --suite          Ejecutar suite completa de pruebas (default)"
    echo "  -m, --menu           Probar solo menú principal"
    echo "  -n, --new-plan       Probar solo flujo de plan nuevo"
    echo "  -b, --bot-info       Mostrar solo información del bot"
    echo "  -h, --help           Mostrar esta ayuda"
    echo ""
    echo "Variables de entorno:"
    echo "  TEST_USER_ID         ID de usuario para pruebas (default: 123456789)"
    echo ""
    echo "Ejemplos:"
    echo "  $0                   # Ejecutar suite completa"
    echo "  $0 -i                # Modo interactivo"
    echo "  $0 -m                # Solo menú principal"
    echo "  TEST_USER_ID=987654321 $0 -n  # Plan nuevo con usuario específico"
}

# Parse command line arguments
case "${1:-}" in
    -i|--interactive)
        check_services
        interactive_test
        ;;
    -s|--suite)
        run_test_suite
        ;;
    -m|--menu)
        check_services
        test_main_menu
        ;;
    -n|--new-plan)
        check_services
        test_new_plan_flow
        ;;
    -b|--bot-info)
        check_services
        test_bot_info
        ;;
    -h|--help)
        usage
        ;;
    "")
        run_test_suite
        ;;
    *)
        error "Opción desconocida: $1"
        usage
        exit 1
        ;;
esac