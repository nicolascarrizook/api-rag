# 🚀 Setup Rápido - Bot de Nutrición

## Para el servidor (Ubuntu):

```bash
# 1. Conectar al servidor
ssh root@165.227.206.121

# 2. Clonar repositorio
git clone https://github.com/TU_USUARIO/bot.git
cd bot

# 3. Deploy automático (reemplazar con tu OpenAI key)
chmod +x deployment/deploy-rag-api.sh
./deployment/deploy-rag-api.sh --openai-key sk-TU_OPENAI_KEY --server-ip 165.227.206.121
```

## Para tu Mac:

```bash
# 1. Procesar documentos Word
cd document-processor
pip install -r requirements.txt
python process_documents.py /ruta/a/tus/documentos --api-url http://165.227.206.121:8001

# 2. Configurar bot Telegram
cd telegram-bot
cp .env.example .env
# Editar .env con token y webhook URL
python nutrition_bot.py
```

## URLs importantes:
- API RAG: http://165.227.206.121:8001
- Health check: http://165.227.206.121:8001/health
- Docs: http://165.227.206.121:8001/docs