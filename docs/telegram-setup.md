# 🚀 Guía Completa de Setup - Telegram Bot de Nutrición

## 📱 Paso 1: Crear Bot en Telegram

### 1.1 Contactar @BotFather
1. Abre Telegram en tu teléfono o computadora
2. Busca y contacta a **@BotFather**
3. Envía el comando `/start`

### 1.2 Crear Nuevo Bot
1. Envía `/newbot` a BotFather
2. Elige un **nombre** para tu bot (ej: "Bot Nutrición Pro")
3. Elige un **username** que termine en "bot" (ej: "nutricion_pro_bot")
4. **¡GUARDA el token!** Se ve así: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

### 1.3 Configurar Bot (Opcional)
```
/setdescription - Bot de nutrición con IA para planes alimentarios personalizados
/setabouttext - Genera planes nutricionales con el método "Tres Días y Carga"
/setuserpic - Sube una imagen para tu bot
```

## 🔧 Paso 2: Configurar Variables de Entorno

### 2.1 Obtener Token
El token que te dio BotFather va en:
```env
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
```

### 2.2 Generar Webhook Secret
```bash
# Genera un secret aleatorio seguro
openssl rand -hex 32
```

Ponelo en:
```env
TELEGRAM_WEBHOOK_SECRET=tu_secret_generado_aqui
```

### 2.3 Archivo .env Completo
```env
# Domain Configuration
DOMAIN=tu-dominio.com

# Telegram Bot API
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_WEBHOOK_SECRET=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6

# OpenAI Configuration
OPENAI_API_KEY=sk-tu-api-key-de-openai

# Database passwords (cambialos!)
POSTGRES_PASSWORD=TuPasswordSeguro123!
REDIS_PASSWORD=OtroPasswordSeguro456!
N8N_PASSWORD=PasswordN8N789!
```

## 🚀 Paso 3: Levantar el Sistema

### 3.1 Iniciar Servicios
```bash
# En el directorio del proyecto
make start

# Verificar que todo esté funcionando
make health
```

### 3.2 Verificar Bot
```bash
# Ver información del bot
make telegram-info

# Debería mostrar algo así:
{
  "ok": true,
  "result": {
    "id": 123456789,
    "is_bot": true,
    "first_name": "Bot Nutrición Pro",
    "username": "nutricion_pro_bot"
  }
}
```

## 🌐 Paso 4: Configurar Webhook

### 4.1 Desarrollo Local (con ngrok)
```bash
# Instalar ngrok
npm install -g ngrok

# Exponer puerto 8000 (RAG API)
ngrok http 8000

# Usar la URL que te da ngrok
make telegram-set-webhook DOMAIN=abc123.ngrok.io
```

### 4.2 Producción (con dominio real)
```bash
# Configurar SSL primero
make ssl-setup

# Luego configurar webhook
make telegram-set-webhook DOMAIN=tu-dominio.com
```

### 4.3 Verificar Webhook
```bash
# Verificar que el webhook esté configurado
curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo"
```

## 🧪 Paso 5: Probar el Bot

### 5.1 Pruebas Automáticas
```bash
# Suite completa de pruebas
./scripts/test-telegram.sh

# Pruebas específicas
./scripts/test-telegram.sh -m  # Solo menú
./scripts/test-telegram.sh -n  # Solo plan nuevo
./scripts/test-telegram.sh -i  # Modo interactivo
```

### 5.2 Prueba Manual
1. Busca tu bot en Telegram: `@tu_bot_username`
2. Envía `/start`
3. Deberías ver el menú principal con botones
4. Prueba crear un "🆕 Plan Nuevo"

## 🔍 Paso 6: Debugging

### 6.1 Logs del Sistema
```bash
# Ver todos los logs
make logs

# Ver solo logs del RAG API
make logs-service SERVICE=rag_api

# Ver logs en tiempo real
docker logs -f nutrition_rag
```

### 6.2 Pruebas de Conectividad
```bash
# Probar RAG API
curl http://localhost:8000/health

# Probar info del bot
curl http://localhost:8000/telegram/info

# Enviar mensaje de prueba
make test-telegram USER_ID=TU_USER_ID TEXT="hola"
```

### 6.3 Problemas Comunes

#### Bot no responde
```bash
# 1. Verificar que el bot esté corriendo
make telegram-info

# 2. Verificar webhook
curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo"

# 3. Ver logs de errores
make logs-service SERVICE=rag_api | grep ERROR
```

#### Webhook no funciona
```bash
# 1. Verificar que el dominio sea accesible
curl https://tu-dominio.com/api/rag/telegram/webhook

# 2. Reconfigurar webhook
make telegram-set-webhook DOMAIN=tu-dominio.com

# 3. Verificar SSL
curl -I https://tu-dominio.com
```

#### Base de datos no conecta
```bash
# 1. Verificar PostgreSQL
make shell-postgres

# 2. Ver logs de la DB
make logs-service SERVICE=postgres

# 3. Verificar variables de entorno
docker exec nutrition_rag env | grep POSTGRES
```

## 📊 Paso 7: Monitoreo

### 7.1 Health Checks
```bash
# Verificación completa del sistema
make health

# Salida esperada:
# PostgreSQL: OK
# Redis: OK
# n8n: OK
# RAG API: OK
# Nginx: OK
```

### 7.2 Métricas del Bot
```bash
# Estadísticas de la base de conocimientos
curl http://localhost:8000/stats

# Información del bot
curl http://localhost:8000/telegram/info
```

### 7.3 Backups
```bash
# Crear backup completo
make backup

# Verificar backups
ls -la backups/
```

## 🎯 Uso del Bot

### Comandos Disponibles
- `/start` - Mostrar menú principal
- `/help` - Mostrar ayuda
- `🆕 Plan Nuevo` - Crear plan alimentario
- `📊 Control` - Control de progreso (próximamente)
- `🔄 Reemplazo` - Reemplazar comida (próximamente)
- `cancelar` - Cancelar operación actual

### Flujo de Plan Nuevo
1. Usuario: "🆕 Plan Nuevo"
2. Bot: Pide nombre
3. Usuario: "Juan Pérez"
4. Bot: Pide edad (15-80 años)
5. Usuario: "30"
6. Bot: Pide peso (40-150 kg)
7. Usuario: "75.5"
8. Bot: Pide altura (140-210 cm)
9. Usuario: "175"
10. Bot: Muestra opciones de objetivo
11. Usuario: Selecciona objetivo
12. Bot: Muestra opciones de actividad
13. Usuario: Selecciona actividad
14. Bot: Genera y envía plan personalizado

## 🔒 Seguridad

### Variables Sensibles
- ❌ **NUNCA** compartas tu `TELEGRAM_BOT_TOKEN`
- ❌ **NUNCA** subas las claves a repositorios públicos
- ✅ Usa `TELEGRAM_WEBHOOK_SECRET` para verificar requests
- ✅ Cambia las contraseñas por defecto

### Configuración Segura
```env
# Genera passwords seguros
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
N8N_PASSWORD=$(openssl rand -base64 32)
TELEGRAM_WEBHOOK_SECRET=$(openssl rand -hex 32)
```

## 📈 Siguientes Pasos

1. **Completar Motors 2 y 3**: Control y Reemplazo
2. **Agregar más recetas**: Expandir base de conocimientos
3. **Mejorar UI**: Usar teclados inline de Telegram
4. **Analytics**: Agregar métricas de uso
5. **Multiidioma**: Soporte para otros países
6. **Integración con balanza**: Para datos automáticos

## ❓ Soporte

Si tenés problemas:
1. Revisá los logs: `make logs`
2. Ejecutá las pruebas: `./scripts/test-telegram.sh`
3. Verificá la configuración: `make health`
4. Consultá la documentación completa en README.md

¡Tu bot de nutrición ya está listo para usar! 🥗🤖