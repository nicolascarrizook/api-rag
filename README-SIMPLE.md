# 🤖 Bot de Nutrición Telegram - Versión Simple con RAG

Sistema optimizado que conecta Telegram → n8n (Hostinger) → API RAG → OpenAI para generar planes nutricionales personalizados con tu propia base de conocimientos.

## 🏗️ Arquitectura Simplificada

```
📱 Telegram Bot (Python)
    ↕️ webhook
🔄 n8n (tu Hostinger) 
    ↕️ HTTP request
🧠 Mini API RAG (servidor económico)
    ↕️ embeddings
🤖 OpenAI GPT-4
```

## 🎯 Ventajas de esta Solución

- ✅ **Aprovecha tu n8n existente** en Hostinger
- ✅ **Tus documentos Word** procesados automáticamente
- ✅ **RAG preciso** con tu metodología "Tres Días y Carga" 
- ✅ **Costo bajo** (~$5/mes adicional para servidor RAG)
- ✅ **Setup simple** - 3 componentes independientes
- ✅ **Escalable** - fácil agregar más documentos

## 📋 Componentes

### 1. 🧠 Mini API RAG 
- Procesa tus archivos Word con metodología nutricional
- Búsqueda vectorial con ChromaDB
- Endpoints REST para n8n
- Deploy en DigitalOcean/Linode ($5/mes)

### 2. 📱 Bot Telegram
- Maneja conversación con usuarios
- Recolecta datos del paciente (nombre, edad, peso, etc.)
- Envía datos estructurados a n8n
- Desplegable en cualquier servidor o local

### 3. 🔄 Workflow n8n
- Recibe datos del bot via webhook
- Consulta API RAG para contexto
- Genera plan con OpenAI + tu metodología
- Envía respuesta al usuario via Telegram

## 🚀 Setup Paso a Paso

### Paso 1: Configurar Mini API RAG

#### 1.1 Crear servidor económico
```bash
# En DigitalOcean, Linode, etc. (Ubuntu 22.04)
# Droplet básico: $5/mes

# Conectar via SSH
ssh root@tu-servidor-ip
```

#### 1.2 Instalar dependencias
```bash
# Actualizar sistema
apt update && apt upgrade -y

# Instalar Python y pip
apt install python3 python3-pip python3-venv -y

# Instalar supervisor para mantener API corriendo
apt install supervisor -y
```

#### 1.3 Deploy la API RAG
```bash
# Clonar proyecto
git clone <tu-repo-url>
cd bot/simple-rag-api

# Crear entorno virtual
python3 -m venv venv
source venv/bin/activate

# Instalar dependencias
pip install -r requirements.txt

# Configurar variables de entorno
cp .env.example .env
nano .env
```

Editar `.env`:
```env
OPENAI_API_KEY=sk-tu-api-key-de-openai
API_HOST=0.0.0.0
API_PORT=8001
CHROMA_PERSIST_DIRECTORY=./chroma_db
```

#### 1.4 Configurar supervisor para auto-start
```bash
# Crear config de supervisor
cat > /etc/supervisor/conf.d/rag-api.conf << EOF
[program:rag-api]
command=/root/bot/simple-rag-api/venv/bin/python rag_api.py
directory=/root/bot/simple-rag-api
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/rag-api.err.log
stdout_logfile=/var/log/rag-api.out.log
EOF

# Recargar supervisor
supervisorctl reread
supervisorctl update
supervisorctl start rag-api

# Verificar que está corriendo
supervisorctl status rag-api
```

#### 1.5 Verificar API
```bash
# Test básico
curl http://localhost:8001/health

# Debería responder:
# {"status":"healthy","chromadb":"connected","openai":"connected"}
```

### Paso 2: Subir tus Documentos Word

#### 2.1 Preparar documentos
- Recopilá todos tus archivos Word con:
  - Metodología "Tres Días y Carga"
  - Tablas nutricionales
  - Recetas argentinas
  - Restricciones alimentarias
  - Equivalencias de alimentos

#### 2.2 Procesar documentos automáticamente
```bash
# En tu computadora local
cd bot/document-processor

# Instalar dependencias
pip install -r requirements.txt

# Procesar todos los documentos en un directorio
python process_documents.py /ruta/a/tus/documentos/word --api-url http://tu-servidor-ip:8001

# Verificar que se subieron
curl http://tu-servidor-ip:8001/documents
```

### Paso 3: Configurar Bot Telegram

#### 3.1 Crear bot en Telegram
1. Contactar @BotFather en Telegram
2. Enviar `/newbot`
3. Elegir nombre: "Bot Nutrición Pro"
4. Elegir username: "tu_nutrition_bot"
5. **Guardar el token**: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

#### 3.2 Configurar bot
```bash
# En tu servidor o computadora local
cd bot/telegram-bot

# Instalar dependencias
pip install -r requirements.txt

# Configurar variables
cp .env.example .env
nano .env
```

Editar `.env`:
```env
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
N8N_WEBHOOK_URL=https://tu-n8n-hostinger.com/webhook/telegram-nutrition
```

#### 3.3 Ejecutar bot
```bash
# Modo desarrollo
python nutrition_bot.py

# Modo producción (con supervisor)
# Similar al setup de la API RAG
```

### Paso 4: Configurar n8n en Hostinger

#### 4.1 Importar workflow
1. Ir a tu n8n en Hostinger
2. Crear nuevo workflow
3. Importar el archivo `n8n-workflow/telegram-nutrition-workflow.json`

#### 4.2 Configurar credenciales

**Telegram Bot:**
- Nombre: "Telegram Bot Credentials"
- Access Token: `tu-token-de-bot`

**OpenAI API:**
- Nombre: "OpenAI API Credentials" 
- API Key: `sk-tu-api-key`

**PostgreSQL (opcional):**
- Para logging de interacciones

#### 4.3 Configurar URLs
En el nodo "Search RAG Knowledge":
- URL: `http://tu-servidor-ip:8001/search`

#### 4.4 Activar workflow
1. Guardar workflow
2. Activar el webhook
3. Copiar URL del webhook: `https://tu-n8n-hostinger.com/webhook/telegram-nutrition`

### Paso 5: Conectar Todo

#### 5.1 Actualizar bot con URL de n8n
```bash
# Editar .env del bot
N8N_WEBHOOK_URL=https://tu-n8n-hostinger.com/webhook/telegram-nutrition
```

#### 5.2 Test completo
```bash
# Reiniciar bot
python nutrition_bot.py

# En Telegram:
# 1. Buscar tu bot: @tu_nutrition_bot
# 2. Enviar /start
# 3. Seguir flujo completo de "Plan Nuevo"
```

## 🧪 Testing

### Test API RAG
```bash
# Test health
curl http://tu-servidor-ip:8001/health

# Test search
curl "http://tu-servidor-ip:8001/search?q=plan+nutricional+bajar+peso&max_results=3"

# List documents
curl http://tu-servidor-ip:8001/documents
```

### Test Bot
```bash
# Ejecutar tests básicos
cd bot/telegram-bot
python test_bot.py  # (crear script simple de test)
```

### Test n8n
1. Usar el webhook URL directamente con Postman/curl
2. Verificar logs en n8n
3. Verificar respuesta en Telegram

## 📊 Monitoreo

### Logs API RAG
```bash
# Ver logs en tiempo real
tail -f /var/log/rag-api.out.log

# Ver errores
tail -f /var/log/rag-api.err.log

# Status del servicio
supervisorctl status rag-api
```

### Logs Bot Telegram
```bash
# Si usas supervisor para el bot también
supervisorctl status telegram-bot
tail -f /var/log/telegram-bot.out.log
```

### Logs n8n
- Ver directamente en la interfaz de n8n
- Revisar ejecuciones del workflow

## 💰 Costos Estimados

- **Mini API RAG**: $5/mes (DigitalOcean Droplet básico)
- **OpenAI API**: ~$10-30/mes (según uso)
- **n8n Hostinger**: Ya lo tenés
- **Telegram Bot**: Gratis
- **Total**: ~$15-35/mes

## 🔧 Mantenimiento

### Agregar nuevos documentos
```bash
# Simplemente procesar documentos nuevos
python process_documents.py /ruta/nuevos/docs --api-url http://tu-servidor-ip:8001
```

### Actualizar metodología
1. Editar prompts en el workflow de n8n
2. Reindexar documentos si es necesario

### Backup
```bash
# Backup base de conocimientos
tar -czf backup-rag-$(date +%Y%m%d).tar.gz /root/bot/simple-rag-api/chroma_db/

# Restaurar
tar -xzf backup-rag-YYYYMMDD.tar.gz -C /
```

## 🆘 Troubleshooting

### API RAG no responde
```bash
# Verificar servicio
supervisorctl status rag-api

# Reiniciar
supervisorctl restart rag-api

# Ver logs
tail -f /var/log/rag-api.err.log
```

### Bot no conecta con n8n
1. Verificar URL del webhook en `.env`
2. Verificar que el workflow esté activado
3. Revisar logs de n8n

### n8n no encuentra contexto
1. Verificar que la API RAG esté corriendo
2. Verificar URL en el nodo "Search RAG Knowledge"
3. Test directo: `curl "http://tu-servidor-ip:8001/search?q=test"`

### OpenAI API errors
1. Verificar API key en n8n
2. Verificar límites de rate
3. Verificar créditos disponibles

## 📈 Próximos Pasos

1. **Completar Motors 2 y 3**: Control y Reemplazo
2. **Agregar más recetas**: Expandir base de conocimientos  
3. **Mejorar UI**: Usar inline keyboards
4. **Analytics**: Métricas de uso en n8n
5. **Multiusuario**: Sesiones persistentes con Redis

## 🎯 Conclusión

Esta arquitectura te da:
- ✅ **Lo mejor de ambos mundos**: n8n + RAG personalizado
- ✅ **Aprovecha tu infraestructura** existente
- ✅ **Metodología específica** con tus documentos
- ✅ **Escalabilidad** y mantenimiento simple
- ✅ **Costo controlado** y predecible

¡Tu bot de nutrición con IA está listo para funcionar! 🥗🤖