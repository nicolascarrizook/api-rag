#!/usr/bin/env python3
"""
Bot de Nutrición Telegram - Versión Simple
Conecta con n8n para procesamiento de IA y genera planes nutricionales
"""

import os
import json
import logging
import asyncio
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

import requests
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    ContextTypes,
    filters
)
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Configuration
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL")
SESSION_TIMEOUT_MINUTES = int(os.getenv("SESSION_TIMEOUT_MINUTES", "30"))
DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"

# In-memory session storage (para producción usar Redis)
user_sessions: Dict[int, Dict[str, Any]] = {}

# Session management
def get_user_session(user_id: int) -> Dict[str, Any]:
    """Get or create user session"""
    if user_id not in user_sessions:
        user_sessions[user_id] = {
            "step": "start",
            "data": {},
            "created_at": datetime.now(),
            "last_activity": datetime.now()
        }
    
    # Update last activity
    user_sessions[user_id]["last_activity"] = datetime.now()
    return user_sessions[user_id]

def clear_user_session(user_id: int):
    """Clear user session"""
    if user_id in user_sessions:
        del user_sessions[user_id]

def is_session_expired(session: Dict[str, Any]) -> bool:
    """Check if session is expired"""
    timeout = timedelta(minutes=SESSION_TIMEOUT_MINUTES)
    return datetime.now() - session["last_activity"] > timeout

# Utility functions
async def send_to_n8n(user_id: int, message_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Send data to n8n webhook"""
    try:
        payload = {
            "user_id": user_id,
            "timestamp": datetime.now().isoformat(),
            **message_data
        }
        
        if DEBUG_MODE:
            logger.info(f"Sending to n8n: {json.dumps(payload, indent=2)}")
        
        response = requests.post(
            N8N_WEBHOOK_URL,
            json=payload,
            timeout=30,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            result = response.json()
            if DEBUG_MODE:
                logger.info(f"n8n response: {json.dumps(result, indent=2)}")
            return result
        else:
            logger.error(f"n8n error: {response.status_code} - {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Error sending to n8n: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return None

# Keyboard layouts
def get_main_menu_keyboard():
    """Get main menu keyboard"""
    keyboard = [
        [KeyboardButton("🆕 Plan Nuevo")],
        [KeyboardButton("📊 Control"), KeyboardButton("🔄 Reemplazo")],
        [KeyboardButton("❓ Ayuda"), KeyboardButton("📋 Mi Información")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

def get_objetivo_keyboard():
    """Get objetivo selection keyboard"""
    keyboard = [
        [KeyboardButton("⬇️ Bajar 0.5kg/semana")],
        [KeyboardButton("⬇️ Bajar 1kg/semana")],
        [KeyboardButton("➡️ Mantener peso")],
        [KeyboardButton("⬆️ Subir peso")],
        [KeyboardButton("🏋️ Ganar masa muscular")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

def get_actividad_keyboard():
    """Get activity level keyboard"""
    keyboard = [
        [KeyboardButton("😴 Sedentario")],
        [KeyboardButton("🚶 Ligero")],
        [KeyboardButton("🏃 Moderado")],
        [KeyboardButton("💪 Intenso")],
        [KeyboardButton("🏋️ Muy Intenso")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

def get_cancel_keyboard():
    """Get cancel keyboard"""
    keyboard = [
        [KeyboardButton("❌ Cancelar")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

# Command handlers
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    user_id = update.effective_user.id
    user_name = update.effective_user.first_name or "Usuario"
    
    clear_user_session(user_id)
    
    welcome_message = f"""¡Hola {user_name}! 👋

Soy tu **Bot de Nutrición** especializado en la metodología **"Tres Días y Carga"**.

🥗 **¿Qué puedo hacer por vos?**
• Crear planes alimentarios personalizados
• Hacer seguimiento de tu progreso  
• Sugerir reemplazos de comidas
• Responder consultas nutricionales

**Seleccioná una opción del menú:**"""

    await update.message.reply_text(
        welcome_message,
        reply_markup=get_main_menu_keyboard()
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """🤖 **Comandos disponibles:**

/start - Mostrar menú principal
/help - Mostrar esta ayuda
/cancel - Cancelar operación actual

📋 **Flujo para Plan Nuevo:**
1. Seleccioná "🆕 Plan Nuevo"
2. Ingresá tu información personal
3. Elegí tu objetivo y nivel de actividad
4. Recibí tu plan personalizado

⚡ **Tips:**
• Usá "❌ Cancelar" para volver al menú
• Tus datos se guardan de forma segura
• Los planes siguen metodología argentina

¿Necesitás ayuda específica? Escribime y te ayudo! 💪"""

    await update.message.reply_text(help_text)

async def cancel_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /cancel command"""
    user_id = update.effective_user.id
    clear_user_session(user_id)
    
    await update.message.reply_text(
        "❌ Operación cancelada.\n\nVolviendo al menú principal:",
        reply_markup=get_main_menu_keyboard()
    )

# Message handlers
async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle all text messages"""
    user_id = update.effective_user.id
    text = update.message.text.strip()
    session = get_user_session(user_id)
    
    # Check session expiration
    if is_session_expired(session):
        clear_user_session(user_id)
        await update.message.reply_text(
            "⏰ Tu sesión expiró. Comenzando de nuevo...",
            reply_markup=get_main_menu_keyboard()
        )
        return
    
    # Handle cancel
    if text == "❌ Cancelar":
        await cancel_command(update, context)
        return
    
    # Handle main menu options
    if session["step"] == "start":
        await handle_main_menu(update, context, text)
    elif session["step"].startswith("nuevo_"):
        await handle_nuevo_plan(update, context, text)
    else:
        await handle_other_options(update, context, text)

async def handle_main_menu(update: Update, context: ContextTypes.DEFAULT_TYPE, text: str):
    """Handle main menu selection"""
    user_id = update.effective_user.id
    session = get_user_session(user_id)
    
    if text == "🆕 Plan Nuevo":
        session["step"] = "nuevo_collect_name"
        session["data"] = {"tipo": "nuevo"}
        
        await update.message.reply_text(
            "🆕 **Crear Plan Nuevo**\n\n"
            "Vamos a crear tu plan alimentario personalizado.\n\n"
            "👤 **Paso 1/6:** ¿Cuál es tu nombre completo?",
            reply_markup=get_cancel_keyboard()
        )
    
    elif text == "📊 Control":
        await update.message.reply_text(
            "📊 **Control de Progreso**\n\n"
            "Esta función estará disponible próximamente.\n"
            "Te permitirá hacer seguimiento de tu evolución.",
            reply_markup=get_main_menu_keyboard()
        )
    
    elif text == "🔄 Reemplazo":
        await update.message.reply_text(
            "🔄 **Reemplazo de Comida**\n\n"
            "Esta función estará disponible próximamente.\n"
            "Te permitirá cambiar comidas específicas manteniendo el balance nutricional.",
            reply_markup=get_main_menu_keyboard()
        )
    
    elif text == "❓ Ayuda":
        await help_command(update, context)
    
    elif text == "📋 Mi Información":
        if session["data"]:
            info = session["data"]
            info_text = "📋 **Tu información actual:**\n\n"
            for key, value in info.items():
                if key != "tipo":
                    info_text += f"• {key.replace('_', ' ').title()}: {value}\n"
        else:
            info_text = "📋 **Mi Información**\n\nAún no tenés información guardada.\nCreá un plan nuevo para empezar."
        
        await update.message.reply_text(info_text, reply_markup=get_main_menu_keyboard())
    
    else:
        await update.message.reply_text(
            "❓ No entendí esa opción.\n\nPor favor, seleccioná una opción del menú:",
            reply_markup=get_main_menu_keyboard()
        )

async def handle_nuevo_plan(update: Update, context: ContextTypes.DEFAULT_TYPE, text: str):
    """Handle new plan creation flow"""
    user_id = update.effective_user.id
    session = get_user_session(user_id)
    step = session["step"]
    
    if step == "nuevo_collect_name":
        # Validate name
        if len(text) < 2 or len(text) > 50:
            await update.message.reply_text(
                "❌ Por favor, ingresá un nombre válido (2-50 caracteres):"
            )
            return
        
        session["data"]["nombre"] = text
        session["step"] = "nuevo_collect_age"
        
        await update.message.reply_text(
            f"✅ Perfecto, {text}!\n\n"
            "🎂 **Paso 2/6:** ¿Cuál es tu edad? (15-80 años)"
        )
    
    elif step == "nuevo_collect_age":
        # Validate age
        try:
            age = int(text)
            if age < 15 or age > 80:
                raise ValueError("Age out of range")
        except ValueError:
            await update.message.reply_text(
                "❌ Por favor, ingresá una edad válida entre 15 y 80 años:"
            )
            return
        
        session["data"]["edad"] = age
        session["step"] = "nuevo_collect_weight"
        
        await update.message.reply_text(
            "✅ Perfecto!\n\n"
            "⚖️ **Paso 3/6:** ¿Cuál es tu peso actual en kg?\n"
            "(Ejemplo: 75.5)"
        )
    
    elif step == "nuevo_collect_weight":
        # Validate weight
        try:
            weight = float(text.replace(",", "."))
            if weight < 40 or weight > 150:
                raise ValueError("Weight out of range")
        except ValueError:
            await update.message.reply_text(
                "❌ Por favor, ingresá un peso válido entre 40 y 150 kg:"
            )
            return
        
        session["data"]["peso"] = weight
        session["step"] = "nuevo_collect_height"
        
        await update.message.reply_text(
            "✅ Perfecto!\n\n"
            "📏 **Paso 4/6:** ¿Cuál es tu altura en cm?\n"
            "(Ejemplo: 175)"
        )
    
    elif step == "nuevo_collect_height":
        # Validate height
        try:
            height = int(text)
            if height < 140 or height > 210:
                raise ValueError("Height out of range")
        except ValueError:
            await update.message.reply_text(
                "❌ Por favor, ingresá una altura válida entre 140 y 210 cm:"
            )
            return
        
        session["data"]["altura"] = height
        session["step"] = "nuevo_collect_objetivo"
        
        await update.message.reply_text(
            "✅ Perfecto!\n\n"
            "🎯 **Paso 5/6:** ¿Cuál es tu objetivo?\n"
            "Seleccioná una opción:",
            reply_markup=get_objetivo_keyboard()
        )
    
    elif step == "nuevo_collect_objetivo":
        # Validate objetivo
        objetivos_validos = [
            "⬇️ Bajar 0.5kg/semana",
            "⬇️ Bajar 1kg/semana", 
            "➡️ Mantener peso",
            "⬆️ Subir peso",
            "🏋️ Ganar masa muscular"
        ]
        
        if text not in objetivos_validos:
            await update.message.reply_text(
                "❌ Por favor, seleccioná una opción del menú:",
                reply_markup=get_objetivo_keyboard()
            )
            return
        
        session["data"]["objetivo"] = text
        session["step"] = "nuevo_collect_actividad"
        
        await update.message.reply_text(
            "✅ Perfecto!\n\n"
            "🏃 **Paso 6/6:** ¿Cuál es tu nivel de actividad física?\n"
            "Seleccioná una opción:",
            reply_markup=get_actividad_keyboard()
        )
    
    elif step == "nuevo_collect_actividad":
        # Validate actividad
        actividades_validas = [
            "😴 Sedentario",
            "🚶 Ligero",
            "🏃 Moderado", 
            "💪 Intenso",
            "🏋️ Muy Intenso"
        ]
        
        if text not in actividades_validas:
            await update.message.reply_text(
                "❌ Por favor, seleccioná una opción del menú:",
                reply_markup=get_actividad_keyboard()
            )
            return
        
        session["data"]["actividad"] = text
        session["step"] = "nuevo_processing"
        
        # Show processing message
        await update.message.reply_text(
            "✅ ¡Información completa!\n\n"
            "🤖 Generando tu plan alimentario personalizado...\n"
            "⏳ Esto puede tomar unos segundos.",
            reply_markup=ReplyKeyboardRemove()
        )
        
        # Send to n8n for processing
        await process_nuevo_plan(update, context)

async def process_nuevo_plan(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Process new plan with n8n"""
    user_id = update.effective_user.id
    session = get_user_session(user_id)
    
    try:
        # Send data to n8n
        response = await send_to_n8n(user_id, {
            "action": "generate_plan",
            "type": "nuevo",
            "patient_data": session["data"]
        })
        
        if response and response.get("success"):
            # Success response from n8n
            plan = response.get("plan", "Plan generado exitosamente")
            
            await update.message.reply_text(
                f"🎉 **¡Tu plan está listo!**\n\n{plan}",
                reply_markup=get_main_menu_keyboard()
            )
            
            # Reset session but keep data
            session["step"] = "start"
            
        else:
            # Error response
            error_msg = response.get("error", "Error desconocido") if response else "Sin respuesta del servidor"
            
            await update.message.reply_text(
                f"❌ **Error generando el plan:**\n\n{error_msg}\n\n"
                "Por favor, intentá nuevamente o contactá al soporte.",
                reply_markup=get_main_menu_keyboard()
            )
            
            # Reset session
            clear_user_session(user_id)
            
    except Exception as e:
        logger.error(f"Error processing plan: {e}")
        
        await update.message.reply_text(
            "❌ **Error técnico**\n\n"
            "Hubo un problema procesando tu solicitud.\n"
            "Por favor, intentá nuevamente en unos minutos.",
            reply_markup=get_main_menu_keyboard()
        )
        
        # Reset session
        clear_user_session(user_id)

async def handle_other_options(update: Update, context: ContextTypes.DEFAULT_TYPE, text: str):
    """Handle other message types"""
    await update.message.reply_text(
        "❓ No entendí ese mensaje.\n\n"
        "Por favor, usá las opciones del menú o escribí /help para obtener ayuda:",
        reply_markup=get_main_menu_keyboard()
    )

# Error handler
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Exception while handling an update: {context.error}")
    
    if isinstance(update, Update) and update.effective_message:
        await update.effective_message.reply_text(
            "❌ **Error técnico**\n\n"
            "Ocurrió un error inesperado.\n"
            "Por favor, intentá nuevamente o escribí /start para comenzar de nuevo."
        )

# Main function
def main():
    """Start the bot"""
    if not TELEGRAM_BOT_TOKEN:
        logger.error("TELEGRAM_BOT_TOKEN not found in environment variables")
        return
    
    if not N8N_WEBHOOK_URL:
        logger.error("N8N_WEBHOOK_URL not found in environment variables")
        return
    
    # Create application
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("cancel", cancel_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Add error handler
    application.add_error_handler(error_handler)
    
    # Start bot
    logger.info("Starting Telegram Nutrition Bot...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()