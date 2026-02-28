-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS http;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- CRON JOBS
SELECT cron.schedule(
  'actualizar-citas-pasadas',
  '0 * * * *',
  $$
  UPDATE citas
  SET cita_pasada = 'cita_pasada'
  WHERE fecha_cita_timezone_cliente < NOW()
    AND (cita_pasada IS NULL OR cita_pasada != 'cita_pasada');
  $$
);

SELECT cron.schedule(
  'recordatorio-citas-24h',
  '0 * * * *',
  $$SELECT enviar_recordatorio_cita_n8n()$$
);

SELECT cron.schedule(
  'verificacion-asistencia-citas',
  '*/5 * * * *',
  $$SELECT verificar_citas_para_webhook()$$
);