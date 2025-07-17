-- Nutrition Bot Database Schema
-- Created for WhatsApp Business nutrition consultation bot

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabla de pacientes/usuarios
CREATE TABLE IF NOT EXISTS patients (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100),
    age INTEGER CHECK (age >= 15 AND age <= 80),
    gender CHAR(1) CHECK (gender IN ('M', 'F')),
    height INTEGER CHECK (height >= 140 AND height <= 210),
    weight DECIMAL(5,2) CHECK (weight >= 40 AND weight <= 150),
    activity_level VARCHAR(20) CHECK (activity_level IN ('sedentario', 'ligero', 'moderado', 'intenso', 'atleta')),
    medical_conditions TEXT,
    allergies TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de conversaciones
CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
    session_id VARCHAR(100) NOT NULL,
    message_id VARCHAR(100),
    message_type VARCHAR(20) CHECK (message_type IN ('text', 'image', 'document')),
    message_text TEXT,
    response_text TEXT,
    motor_type INTEGER CHECK (motor_type IN (1, 2, 3)),
    conversation_state JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de planes alimentarios generados
CREATE TABLE IF NOT EXISTS meal_plans (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
    plan_type VARCHAR(20) CHECK (plan_type IN ('nuevo', 'control', 'reemplazo')),
    objective VARCHAR(50) CHECK (objective IN ('-1kg', '-0.5kg', 'mantener', '+0.5kg', '+1kg')),
    daily_calories INTEGER,
    daily_protein DECIMAL(5,2),
    daily_carbs DECIMAL(5,2),
    daily_fats DECIMAL(5,2),
    plan_content JSONB NOT NULL,
    rag_context JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    active BOOLEAN DEFAULT TRUE
);

-- Tabla de métricas y seguimiento
CREATE TABLE IF NOT EXISTS patient_metrics (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
    weight DECIMAL(5,2),
    body_fat_percentage DECIMAL(4,2),
    muscle_mass DECIMAL(5,2),
    notes TEXT,
    photo_url VARCHAR(500),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla para tracking de comidas específicas
CREATE TABLE IF NOT EXISTS meal_replacements (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
    original_meal_plan_id INTEGER REFERENCES meal_plans(id),
    meal_type VARCHAR(20) CHECK (meal_type IN ('desayuno', 'almuerzo', 'merienda', 'cena')),
    original_meal JSONB,
    replacement_meal JSONB,
    reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de ingredientes y valores nutricionales
CREATE TABLE IF NOT EXISTS ingredients (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) CHECK (category IN ('proteina', 'carbohidrato', 'grasa', 'verdura', 'fruta', 'lacteo')),
    protein_per_100g DECIMAL(5,2),
    carbs_per_100g DECIMAL(5,2),
    fat_per_100g DECIMAL(5,2),
    calories_per_100g INTEGER,
    fiber_per_100g DECIMAL(4,2),
    is_raw_weight BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de sesiones de chat
CREATE TABLE IF NOT EXISTS chat_sessions (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL,
    session_data JSONB,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de logs del sistema
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(10) CHECK (level IN ('DEBUG', 'INFO', 'WARN', 'ERROR')),
    component VARCHAR(50),
    message TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para optimización
CREATE INDEX IF NOT EXISTS idx_conversations_patient_id ON conversations(patient_id);
CREATE INDEX IF NOT EXISTS idx_conversations_session_id ON conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_meal_plans_patient_id ON meal_plans(patient_id);
CREATE INDEX IF NOT EXISTS idx_meal_plans_active ON meal_plans(active) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_patient_metrics_patient_id ON patient_metrics(patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_metrics_recorded_at ON patient_metrics(recorded_at);
CREATE INDEX IF NOT EXISTS idx_meal_replacements_patient_id ON meal_replacements(patient_id);
CREATE INDEX IF NOT EXISTS idx_ingredients_category ON ingredients(category);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_phone ON chat_sessions(phone_number);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_expires ON chat_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_system_logs_level ON system_logs(level);
CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON system_logs(created_at);

-- Función para actualizar timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger para actualizar updated_at automáticamente
CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Función para limpiar sesiones expiradas
CREATE OR REPLACE FUNCTION clean_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM chat_sessions WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Insertar ingredientes básicos
INSERT INTO ingredients (name, category, protein_per_100g, carbs_per_100g, fat_per_100g, calories_per_100g, fiber_per_100g) VALUES
-- Proteínas
('Pechuga de pollo', 'proteina', 23.0, 0.0, 2.0, 165, 0.0),
('Bife de lomo', 'proteina', 26.0, 0.0, 15.0, 250, 0.0),
('Huevos', 'proteina', 13.0, 1.0, 11.0, 155, 0.0),
('Merluza', 'proteina', 18.0, 0.0, 1.0, 82, 0.0),
('Atún en agua', 'proteina', 25.0, 0.0, 1.0, 116, 0.0),

-- Carbohidratos
('Avena', 'carbohidrato', 13.0, 66.0, 6.0, 389, 10.0),
('Arroz integral', 'carbohidrato', 7.0, 77.0, 3.0, 370, 4.0),
('Papa', 'carbohidrato', 2.0, 20.0, 0.0, 87, 2.0),
('Batata', 'carbohidrato', 2.0, 27.0, 0.0, 112, 4.0),
('Pan integral', 'carbohidrato', 8.0, 48.0, 4.0, 265, 7.0),

-- Grasas saludables
('Palta', 'grasa', 2.0, 9.0, 15.0, 160, 7.0),
('Almendras', 'grasa', 21.0, 22.0, 49.0, 579, 12.0),
('Aceite de oliva', 'grasa', 0.0, 0.0, 100.0, 884, 0.0),
('Nueces', 'grasa', 15.0, 14.0, 65.0, 654, 7.0),

-- Verduras
('Brócoli', 'verdura', 3.0, 7.0, 0.0, 34, 3.0),
('Espinaca', 'verdura', 2.9, 3.6, 0.4, 23, 2.2),
('Tomate', 'verdura', 0.9, 3.9, 0.2, 18, 1.2),
('Lechuga', 'verdura', 1.4, 2.9, 0.1, 15, 1.3),
('Zanahoria', 'verdura', 0.9, 9.6, 0.2, 41, 2.8),

-- Lácteos
('Yogur griego descremado', 'lacteo', 10.0, 4.0, 0.0, 59, 0.0),
('Queso cottage', 'lacteo', 11.0, 3.4, 4.3, 98, 0.0),
('Leche descremada', 'lacteo', 3.4, 5.0, 0.1, 34, 0.0)

ON CONFLICT (name) DO NOTHING;

-- Vista para planes activos con información del paciente
CREATE OR REPLACE VIEW active_meal_plans AS
SELECT 
    mp.id,
    mp.patient_id,
    p.name as patient_name,
    p.phone_number,
    mp.plan_type,
    mp.objective,
    mp.daily_calories,
    mp.daily_protein,
    mp.daily_carbs,
    mp.daily_fats,
    mp.plan_content,
    mp.created_at
FROM meal_plans mp
JOIN patients p ON mp.patient_id = p.id
WHERE mp.active = TRUE;

-- Comentarios en tablas principales
COMMENT ON TABLE patients IS 'Información básica de pacientes registrados en el bot';
COMMENT ON TABLE conversations IS 'Historial de conversaciones con contexto de estado';
COMMENT ON TABLE meal_plans IS 'Planes alimentarios generados por los 3 motores';
COMMENT ON TABLE patient_metrics IS 'Seguimiento de progreso y métricas corporales';
COMMENT ON TABLE meal_replacements IS 'Historial de reemplazos de comidas específicas';
COMMENT ON TABLE ingredients IS 'Base de datos nutricional de ingredientes';

-- Insertar usuario admin por defecto
INSERT INTO system_logs (level, component, message, metadata) VALUES
('INFO', 'database', 'Schema initialized successfully', '{"version": "1.0", "tables_created": 8}');

COMMIT;