#!/usr/bin/env python3
"""
Telegram Webhook Handler for Nutrition Bot
Procesa mensajes de Telegram y genera respuestas nutricionales
"""

import os
import json
import logging
import hashlib
import hmac
from typing import List, Dict, Optional, Any
from datetime import datetime

import redis
from fastapi import FastAPI, HTTPException, Request, Depends
from pydantic import BaseModel, Field
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Pydantic models para Telegram
class TelegramUser(BaseModel):
    id: int
    is_bot: bool
    first_name: str
    last_name: Optional[str] = None
    username: Optional[str] = None

class TelegramChat(BaseModel):
    id: int
    type: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    username: Optional[str] = None

class TelegramMessage(BaseModel):
    message_id: int
    from_: TelegramUser = Field(alias="from")
    chat: TelegramChat
    date: int
    text: Optional[str] = None

class TelegramUpdate(BaseModel):
    update_id: int
    message: Optional[TelegramMessage] = None

class NutritionSession(BaseModel):
    user_id: int
    chat_id: int
    motor_type: Optional[int] = None
    step: str = "initial"
    patient_data: Dict = {}
    created_at: str = Field(default_factory=lambda: datetime.now().isoformat())

class TelegramBot:
    def __init__(self, token: str, redis_client: redis.Redis):
        self.token = token
        self.redis_client = redis_client
        self.api_url = f"https://api.telegram.org/bot{token}"
        
    def verify_webhook_signature(self, body: str, signature: str) -> bool:
        """Verifica la firma del webhook de Telegram"""
        try:
            secret_key = os.getenv("TELEGRAM_WEBHOOK_SECRET", "").encode()
            expected_signature = hmac.new(
                secret_key,
                body.encode(),
                hashlib.sha256
            ).hexdigest()
            return hmac.compare_digest(signature, expected_signature)
        except Exception as e:
            logger.error(f"Error verifying webhook signature: {e}")
            return False
    
    def send_message(self, chat_id: int, text: str, reply_markup: Optional[Dict] = None) -> Dict:
        """Envía mensaje de texto a Telegram"""
        url = f"{self.api_url}/sendMessage"
        
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "Markdown"
        }
        
        if reply_markup:
            payload["reply_markup"] = json.dumps(reply_markup)
        
        try:
            response = requests.post(url, json=payload)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Error sending message: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to send message: {str(e)}")
    
    def send_keyboard(self, chat_id: int, text: str, keyboard: List[List[str]]) -> Dict:
        """Envía mensaje con teclado personalizado"""
        reply_markup = {
            "keyboard": [[{"text": button} for button in row] for row in keyboard],
            "resize_keyboard": True,
            "one_time_keyboard": True
        }
        
        return self.send_message(chat_id, text, reply_markup)
    
    def get_session(self, user_id: int) -> Optional[NutritionSession]:
        """Obtiene la sesión actual del usuario"""
        try:
            session_data = self.redis_client.get(f"telegram_session:{user_id}")
            if session_data:
                data = json.loads(session_data)
                return NutritionSession(**data)
            return None
        except Exception as e:
            logger.error(f"Error getting session: {e}")
            return None
    
    def save_session(self, session: NutritionSession, ttl: int = 1800) -> None:
        """Guarda la sesión del usuario"""
        try:
            session_key = f"telegram_session:{session.user_id}"
            session_data = session.dict()
            self.redis_client.setex(session_key, ttl, json.dumps(session_data))
        except Exception as e:
            logger.error(f"Error saving session: {e}")
    
    def clear_session(self, user_id: int) -> None:
        """Limpia la sesión del usuario"""
        try:
            self.redis_client.delete(f"telegram_session:{user_id}")
        except Exception as e:
            logger.error(f"Error clearing session: {e}")
    
    def detect_intent(self, text: str) -> str:
        """Detecta la intención del usuario"""
        text_lower = text.lower().strip()
        
        # Comandos específicos
        if text_lower in ["/start", "inicio", "empezar"]:
            return "start"
        elif text_lower in ["nuevo", "plan nuevo", "nuevo plan", "crear plan"]:
            return "nuevo_plan"
        elif text_lower in ["control", "seguimiento", "control peso"]:
            return "control"
        elif text_lower in ["reemplazo", "cambiar comida", "reemplazar"]:
            return "reemplazo"
        elif text_lower in ["/help", "ayuda", "help"]:
            return "help"
        elif text_lower in ["cancelar", "salir", "terminar"]:
            return "cancel"
        else:
            return "continue_flow"
    
    def show_main_menu(self, chat_id: int) -> Dict:
        """Muestra el menú principal"""
        text = """🥗 *Bot de Nutrición - Dieta Inteligente®*

¡Hola! Soy tu asistente nutricional especializado en el método *"Tres Días y Carga"*.

¿Qué querés hacer hoy?"""
        
        keyboard = [
            ["🆕 Plan Nuevo", "📊 Control"],
            ["🔄 Reemplazo", "❓ Ayuda"]
        ]
        
        return self.send_keyboard(chat_id, text, keyboard)
    
    def process_motor_1_nuevo(self, session: NutritionSession, message: TelegramMessage) -> Dict:
        """Procesa Motor 1 - Paciente Nuevo"""
        step = session.step
        text = message.text.strip() if message.text else ""
        
        if step == "collect_name":
            if len(text) < 2:
                return self.send_message(
                    message.chat.id,
                    "Por favor, ingresá un nombre válido (mínimo 2 caracteres):"
                )
            
            session.patient_data["name"] = text
            session.step = "collect_age"
            self.save_session(session)
            
            return self.send_message(
                message.chat.id,
                f"Perfecto *{text}*! 👋\n\nAhora necesito tu *edad* (entre 15 y 80 años):"
            )
        
        elif step == "collect_age":
            try:
                age = int(text)
                if not (15 <= age <= 80):
                    return self.send_message(
                        message.chat.id,
                        "❌ La edad debe estar entre 15 y 80 años.\n\nIngresá tu edad:"
                    )
                
                session.patient_data["age"] = age
                session.step = "collect_weight"
                self.save_session(session)
                
                return self.send_message(
                    message.chat.id,
                    "Excelente! 👍\n\nAhora necesito tu *peso actual* (en kg, entre 40 y 150):"
                )
            except ValueError:
                return self.send_message(
                    message.chat.id,
                    "❌ Por favor ingresá solo números.\n\nTu edad:"
                )
        
        elif step == "collect_weight":
            try:
                weight = float(text)
                if not (40 <= weight <= 150):
                    return self.send_message(
                        message.chat.id,
                        "❌ El peso debe estar entre 40 y 150 kg.\n\nIngresá tu peso:"
                    )
                
                session.patient_data["weight"] = weight
                session.step = "collect_height"
                self.save_session(session)
                
                return self.send_message(
                    message.chat.id,
                    "Perfecto! 📏\n\nAhora tu *altura* (en cm, entre 140 y 210):"
                )
            except ValueError:
                return self.send_message(
                    message.chat.id,
                    "❌ Por favor ingresá solo números (ej: 70.5).\n\nTu peso en kg:"
                )
        
        elif step == "collect_height":
            try:
                height = int(text)
                if not (140 <= height <= 210):
                    return self.send_message(
                        message.chat.id,
                        "❌ La altura debe estar entre 140 y 210 cm.\n\nIngresá tu altura:"
                    )
                
                session.patient_data["height"] = height
                session.step = "collect_objective"
                self.save_session(session)
                
                keyboard = [
                    ["⬇️ Bajar 1kg/semana", "⬇️ Bajar 0.5kg/semana"],
                    ["🎯 Mantener peso"],
                    ["⬆️ Subir 0.5kg/semana", "⬆️ Subir 1kg/semana"]
                ]
                
                return self.send_keyboard(
                    message.chat.id,
                    "Genial! 🎯\n\n¿Cuál es tu *objetivo*?",
                    keyboard
                )
            except ValueError:
                return self.send_message(
                    message.chat.id,
                    "❌ Por favor ingresá solo números.\n\nTu altura en cm:"
                )
        
        elif step == "collect_objective":
            objective_map = {
                "⬇️ Bajar 1kg/semana": "-1kg",
                "⬇️ Bajar 0.5kg/semana": "-0.5kg",
                "🎯 Mantener peso": "mantener",
                "⬆️ Subir 0.5kg/semana": "+0.5kg",
                "⬆️ Subir 1kg/semana": "+1kg"
            }
            
            if text not in objective_map:
                keyboard = [
                    ["⬇️ Bajar 1kg/semana", "⬇️ Bajar 0.5kg/semana"],
                    ["🎯 Mantener peso"],
                    ["⬆️ Subir 0.5kg/semana", "⬆️ Subir 1kg/semana"]
                ]
                return self.send_keyboard(
                    message.chat.id,
                    "❌ Por favor seleccioná una opción del menú:",
                    keyboard
                )
            
            session.patient_data["objective"] = objective_map[text]
            session.step = "collect_activity"
            self.save_session(session)
            
            keyboard = [
                ["🛋️ Sedentario", "🚶 Ligero"],
                ["🏃 Moderado", "💪 Intenso"],
                ["🏆 Atleta"]
            ]
            
            return self.send_keyboard(
                message.chat.id,
                "Excelente! 💪\n\n¿Cuál es tu *nivel de actividad física*?",
                keyboard
            )
        
        elif step == "collect_activity":
            activity_map = {
                "🛋️ Sedentario": "sedentario",
                "🚶 Ligero": "ligero",
                "🏃 Moderado": "moderado",
                "💪 Intenso": "intenso",
                "🏆 Atleta": "atleta"
            }
            
            if text not in activity_map:
                keyboard = [
                    ["🛋️ Sedentario", "🚶 Ligero"],
                    ["🏃 Moderado", "💪 Intenso"],
                    ["🏆 Atleta"]
                ]
                return self.send_keyboard(
                    message.chat.id,
                    "❌ Por favor seleccioná una opción del menú:",
                    keyboard
                )
            
            session.patient_data["activity_level"] = activity_map[text]
            session.step = "generate_plan"
            self.save_session(session)
            
            # Mostrar resumen y generar plan
            name = session.patient_data["name"]
            age = session.patient_data["age"]
            weight = session.patient_data["weight"]
            height = session.patient_data["height"]
            objective = session.patient_data["objective"]
            activity = activity_map[text]
            
            summary = f"""✅ *Datos Confirmados:*

👤 *Nombre:* {name}
🎂 *Edad:* {age} años
⚖️ *Peso:* {weight} kg
📏 *Altura:* {height} cm
🎯 *Objetivo:* {objective} por semana
💪 *Actividad:* {activity}

🔄 *Generando tu plan personalizado...*

⏳ Esto puede tomar unos segundos..."""
            
            # Enviar resumen
            self.send_message(message.chat.id, summary)
            
            # Aquí se llamaría a la función de generación de plan
            # Por ahora retornamos un placeholder
            return self.generate_nutrition_plan(session, message.chat.id)
        
        return self.send_message(message.chat.id, "❌ Error en el flujo. Iniciemos de nuevo.")
    
    def generate_nutrition_plan(self, session: NutritionSession, chat_id: int) -> Dict:
        """Genera el plan nutricional usando OpenAI + RAG"""
        try:
            # Aquí iría la llamada a la API RAG y OpenAI
            # Por ahora, enviamos un plan de ejemplo
            
            name = session.patient_data["name"]
            objective = session.patient_data["objective"]
            
            plan_text = f"""🥗 *PLAN ALIMENTARIO - {name.upper()}*
*Objetivo:* {objective} por semana

*=== DÍA 1, 2 y 3 ===*

🌅 *DESAYUNO (08:00 hs)*
• Yogur griego descremado: 200g
• Avena tradicional: 40g
• Banana: 100g
• Almendras: 15g

*Preparación:* Cocinar la avena con agua hasta que esté cremosa. Mezclar con yogur, agregar banana en rodajas y almendras picadas.

🍽️ *ALMUERZO (13:00 hs)*
• Pechuga de pollo: 150g
• Batata: 120g
• Brócoli: 150g
• Aceite de oliva: 10g

*Preparación:* Cocinar la pechuga a la plancha. Hornear la batata. Hervir el brócoli al dente. Rociar con aceite.

☕ *MERIENDA (16:30 hs)*
• Manzana: 120g
• Almendras: 15g

🌙 *CENA (20:00 hs)*
• Merluza: 140g
• Ensalada mixta: 200g
• Aceite de oliva: 8g

*Preparación:* Merluza al horno con limón. Ensalada fresca aliñada.

📊 *Macros diarios:* P: 125g | C: 140g | G: 58g
🔥 *Calorías:* 1480 kcal

💧 *Hidratación:* Mínimo 2.5L de agua por día

✅ *Tu plan está listo!* 
*Recordá seguirlo por 3 días consecutivos.*

¿Necesitás algo más? Enviá 'menú' para volver al inicio."""
            
            # Limpiar sesión después de generar el plan
            self.clear_session(session.user_id)
            
            return self.send_message(chat_id, plan_text)
            
        except Exception as e:
            logger.error(f"Error generating nutrition plan: {e}")
            return self.send_message(
                chat_id,
                "❌ Error generando el plan. Por favor intentá de nuevo más tarde.\n\nEnviá 'menú' para volver al inicio."
            )
    
    def process_update(self, update: TelegramUpdate) -> Optional[Dict]:
        """Procesa una actualización de Telegram"""
        if not update.message or not update.message.text:
            return None
        
        message = update.message
        user_id = message.from_.id
        chat_id = message.chat.id
        text = message.text.strip()
        
        logger.info(f"Processing message from user {user_id}: {text}")
        
        # Detectar intención
        intent = self.detect_intent(text)
        
        # Manejar comandos globales
        if intent == "start":
            self.clear_session(user_id)
            return self.show_main_menu(chat_id)
        
        elif intent == "help":
            help_text = """❓ *Ayuda - Bot de Nutrición*

🆕 *Plan Nuevo:* Crea tu primer plan alimentario personalizado

📊 *Control:* Seguimiento y ajustes de tu plan existente

🔄 *Reemplazo:* Cambia una comida específica de tu plan

*Comandos útiles:*
• Escribí 'menú' para volver al inicio
• Escribí 'cancelar' para terminar proceso actual
• Escribí 'ayuda' para ver esta información

*Método: "Tres Días y Carga | Dieta Inteligente®"*"""
            
            return self.send_message(chat_id, help_text)
        
        elif intent == "cancel":
            self.clear_session(user_id)
            return self.send_message(
                chat_id,
                "✅ Proceso cancelado.\n\nEnviá 'menú' para empezar de nuevo."
            )
        
        # Obtener sesión actual
        session = self.get_session(user_id)
        
        # Si no hay sesión activa, manejar nuevos comandos
        if not session:
            if intent == "nuevo_plan" or text == "🆕 Plan Nuevo":
                session = NutritionSession(
                    user_id=user_id,
                    chat_id=chat_id,
                    motor_type=1,
                    step="collect_name"
                )
                self.save_session(session)
                
                return self.send_message(
                    chat_id,
                    "🆕 *Creando tu Plan Nutricional*\n\nVamos a generar tu plan personalizado paso a paso.\n\n¿Cuál es tu *nombre*?"
                )
            
            elif intent == "control" or text == "📊 Control":
                return self.send_message(
                    chat_id,
                    "📊 *Control de Plan*\n\n⚠️ Función en desarrollo.\n\nPor ahora podés crear un 'Plan Nuevo'."
                )
            
            elif intent == "reemplazo" or text == "🔄 Reemplazo":
                return self.send_message(
                    chat_id,
                    "🔄 *Reemplazo de Comida*\n\n⚠️ Función en desarrollo.\n\nPor ahora podés crear un 'Plan Nuevo'."
                )
            
            else:
                return self.show_main_menu(chat_id)
        
        # Procesar según el motor activo
        if session.motor_type == 1:
            return self.process_motor_1_nuevo(session, message)
        
        # Fallback
        return self.show_main_menu(chat_id)