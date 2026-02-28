--
-- PostgreSQL database dump
--

\restrict 0uKk0EfQjNaSqwCA3erfYrL3HehaAKRrojN5uofbmCVSIqMLByPFP6OknWTVSnb

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.8 (Ubuntu 17.8-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: actualizar_citas_pasadas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.actualizar_citas_pasadas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Si la fecha de la cita ya pasó y no está marcada como pasada
  IF NEW.fecha_cita_timezone_cliente < NOW() AND 
     (NEW.cita_pasada IS NULL OR NEW.cita_pasada != 'cita_pasada') THEN
    NEW.cita_pasada := 'cita_pasada';
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: actualizar_es_cliente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.actualizar_es_cliente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Verifica si el nuevo estado_lead es 'Venta cerrada'
  IF NEW.estado_lead = 'Venta cerrada' THEN
    NEW.es_cliente := TRUE;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION actualizar_es_cliente(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.actualizar_es_cliente() IS 'Actualiza automáticamente es_cliente a TRUE cuando estado_lead cambia a Venta cerrada';


--
-- Name: actualizar_fecha_conversion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.actualizar_fecha_conversion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Para INSERT: siempre establece fecha_conversion si estado_lead tiene valor
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado_lead IS NOT NULL THEN
      NEW.fecha_conversion = NOW();
    END IF;
  -- Para UPDATE: solo si el estado_lead cambió
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.estado_lead IS DISTINCT FROM OLD.estado_lead THEN
      NEW.fecha_conversion = NOW();
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: asignar_id_cita(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.asignar_id_cita() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Si el id viene vacío o null, le asignamos el siguiente número de la secuencia
  IF NEW.id IS NULL THEN
    NEW.id := nextval('citas_id_seq');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: buscar_leads(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.buscar_leads(termino text) RETURNS TABLE(id bigint, lead_id character varying, nombre character varying, email character varying, telefono character varying, empresa character varying, servicio character varying, fuente character varying, estado_lead character varying, score_lead integer, fecha_creado date)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    l.id,
    l.lead_id,
    l.nombre,
    l.email,
    l.telefono,
    l.empresa,
    l.servicio,
    l.fuente,
    l.estado_lead,
    l.score_lead,
    l.fecha_creado
  FROM leads_formularios_optimizada l
  WHERE 
    l.lead_id ILIKE '%' || termino || '%'
    OR l.nombre ILIKE '%' || termino || '%'
    OR l.nombre_normalizado ILIKE '%' || termino || '%'
    OR l.email ILIKE '%' || termino || '%'
    OR l.telefono ILIKE '%' || termino || '%'
    OR l.empresa ILIKE '%' || termino || '%'
    OR to_tsvector('spanish', 
         COALESCE(l.nombre, '') || ' ' || 
         COALESCE(l.email, '') || ' ' || 
         COALESCE(l.empresa, '')
       ) @@ plainto_tsquery('spanish', termino)
  ORDER BY l.created_at DESC
  LIMIT 100;
END;
$$;


--
-- Name: FUNCTION buscar_leads(termino text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.buscar_leads(termino text) IS 'Búsqueda de leads por múltiples criterios';


--
-- Name: buscar_tickets(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.buscar_tickets(termino_busqueda text) RETURNS TABLE(id bigint, ticket_numero character varying, asunto character varying, descripcion text, estado character varying, prioridad character varying, creado timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    st.id,
    st.ticket_numero,
    st.asunto,
    st.descripcion,
    st.estado,
    st.prioridad,
    st.creado
  FROM soporte_tecnico st
  WHERE 
    st.ticket_numero ILIKE '%' || termino_busqueda || '%'
    OR st.asunto ILIKE '%' || termino_busqueda || '%'
    OR st.descripcion ILIKE '%' || termino_busqueda || '%'
    OR st.nombre_cliente ILIKE '%' || termino_busqueda || '%'
    OR st.email ILIKE '%' || termino_busqueda || '%'
    OR termino_busqueda = ANY(st.tags)
  ORDER BY st.creado DESC
  LIMIT 50;
END;
$$;


--
-- Name: calcular_score_lead(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calcular_score_lead() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  nuevo_score INTEGER;
BEGIN
  -- Inicializar score base
  nuevo_score := 60;
  
  -- Sumar puntos según campos disponibles
  
  -- Email válido (+10 puntos)
  IF NEW.email IS NOT NULL AND NEW.email LIKE '%@%' THEN
    nuevo_score := nuevo_score + 10;
  END IF;
  
  -- Teléfono (+10 puntos)
  IF NEW.telefono IS NOT NULL AND NEW.telefono <> '' AND NEW.telefono <> 'null' THEN
    nuevo_score := nuevo_score + 10;
  END IF;
  
  -- Servicio (+5 puntos)
  IF NEW.servicio IS NOT NULL AND NEW.servicio <> '' AND NEW.servicio <> 'null' THEN
    nuevo_score := nuevo_score + 5;
  END IF;
  
  -- Empresa (+5 puntos)
  IF NEW.empresa IS NOT NULL AND NEW.empresa <> '' AND NEW.empresa <> 'null' THEN
    nuevo_score := nuevo_score + 5;
  END IF;
  
  -- Estado y País juntos (+3 puntos)
  IF NEW.estado IS NOT NULL AND NEW.estado <> '' AND NEW.estado <> 'null' 
     AND NEW.pais IS NOT NULL AND NEW.pais <> '' AND NEW.pais <> 'null' THEN
    nuevo_score := nuevo_score + 3;
  END IF;
  
  -- Código postal (+2 puntos)
  IF NEW.codigo_postal IS NOT NULL AND NEW.codigo_postal <> '' AND NEW.codigo_postal <> 'null' THEN
    nuevo_score := nuevo_score + 2;
  END IF;
  
  -- Asegurar que el score no exceda 100
  IF nuevo_score > 100 THEN
    nuevo_score := 100;
  END IF;
  
  -- Actualizar el campo score_lead en el registro
  NEW.score_lead := nuevo_score;
  
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION calcular_score_lead(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.calcular_score_lead() IS 'Calcula el score de calidad de un lead basado en la completitud de sus datos.
Score base: 60 puntos
- Email válido: +10
- Teléfono: +10
- Servicio: +5
- Empresa: +5
- Estado + País: +3
- Código postal: +2
Score máximo: 100 puntos';


--
-- Name: eliminar_duplicados_whatsapp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eliminar_duplicados_whatsapp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Eliminar registros duplicados más recientes con el mismo whatsapp
  DELETE FROM leads_formularios_optimizada
  WHERE whatsapp = NEW.whatsapp
    AND id != NEW.id
    AND created_at > NEW.created_at;
  
  -- Si el nuevo registro es más reciente que alguno existente, eliminar el nuevo
  IF EXISTS (
    SELECT 1 
    FROM leads_formularios_optimizada 
    WHERE whatsapp = NEW.whatsapp 
      AND id != NEW.id 
      AND created_at < NEW.created_at
  ) THEN
    DELETE FROM leads_formularios_optimizada WHERE id = NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: enviar_recordatorio_cita_n8n(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enviar_recordatorio_cita_n8n() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  cita_record RECORD;
  webhook_url TEXT := 'YOUR_N8N_WEBHOOK_URL_HERE';
  payload JSONB;
  response INT;
BEGIN
  -- Buscar citas que NO han enviado recordatorio y faltan entre 23-25 horas
  FOR cita_record IN
    SELECT 
      id,
      client_id,
      nombre,
      telefono,
      enlace_reunion,
      fecha_cita_timezone_cliente
    FROM citas
    WHERE recordatorio_enviado = FALSE
      AND fecha_cita_timezone_cliente BETWEEN 
        NOW() + INTERVAL '23 hours' AND 
        NOW() + INTERVAL '25 hours'
  LOOP
    -- Construir el payload JSON
    payload := jsonb_build_object(
      'id', cita_record.id,
      'client_id', cita_record.client_id,
      'nombre', cita_record.nombre,
      'telefono', cita_record.telefono,
      'enlace_reunion', cita_record.enlace_reunion,
      'fecha_cita_timezone_cliente', cita_record.fecha_cita_timezone_cliente
    );

    -- Enviar POST al webhook de n8n
    SELECT status INTO response
    FROM http((
      'POST',
      webhook_url,
      ARRAY[http_header('Content-Type', 'application/json')],
      'application/json',
      payload::TEXT
    )::http_request);

    -- Marcar como enviado
    UPDATE citas 
    SET recordatorio_enviado = TRUE 
    WHERE id = cita_record.id;

    RAISE NOTICE 'Recordatorio enviado para cita ID: %, Status: %', cita_record.id, response;
  END LOOP;
END;
$$;


--
-- Name: enviar_webhook_verificacion_asistencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enviar_webhook_verificacion_asistencia() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    cita_record RECORD;
    webhook_url TEXT := 'YOUR_N8N_WEBHOOK_URL_HERE';
    response TEXT;
    payload JSON;
BEGIN
    -- Buscar citas que cumplan las condiciones:
    -- 1. La fecha_cita + 30 minutos ya pasó
    -- 2. No se ha enviado el webhook aún
    -- 3. El estado es 'cita agendada' o 'cita reagendada'
    FOR cita_record IN
        SELECT 
            c.id,
            c.client_id,
            c.estado,
            c.nombre,
            c.fecha_cita,
            c.email,
            c.telefono,
            c.servicio,
            c.resumen,
            c.pais,
            c.empresa,
            c.enlace_reunion,
            c.duracion_minutos,
            c.asistencia,
            c.cita_pasada,
            c.fecha_cita_timezone_cliente,
            c.fecha_cita_timezone_legible,
            c.fecha_cita_legible
        FROM citas c
        LEFT JOIN citas_webhook_enviadas cwe ON c.id = cwe.cita_id
        WHERE 
            -- Verificar que han pasado 30 minutos desde la cita
            c.fecha_cita + INTERVAL '30 minutes' <= NOW()
            -- No se ha enviado el webhook
            AND cwe.id IS NULL
            -- FILTRO CRÍTICO: Solo citas agendadas o reagendadas
            AND (LOWER(c.estado) = 'cita agendada' OR LOWER(c.estado) = 'cita reagendada')
            -- Opcional: solo citas de los últimos 7 días para evitar enviar citas muy antiguas
            AND c.fecha_cita >= NOW() - INTERVAL '7 days'
    LOOP
        BEGIN
            -- Construir el payload JSON con todos los datos del cliente
            payload := json_build_object(
                'cita_id', cita_record.id,
                'client_id', cita_record.client_id,
                'estado', cita_record.estado,
                'nombre', cita_record.nombre,
                'fecha_cita', cita_record.fecha_cita,
                'email', cita_record.email,
                'telefono', cita_record.telefono,
                'servicio', cita_record.servicio,
                'resumen', cita_record.resumen,
                'pais', cita_record.pais,
                'empresa', cita_record.empresa,
                'enlace_reunion', cita_record.enlace_reunion,
                'duracion_minutos', cita_record.duracion_minutos,
                'asistencia', cita_record.asistencia,
                'cita_pasada', cita_record.cita_pasada,
                'fecha_cita_timezone_cliente', cita_record.fecha_cita_timezone_cliente,
                'fecha_cita_timezone_legible', cita_record.fecha_cita_timezone_legible,
                'fecha_cita_legible', cita_record.fecha_cita_legible,
                'enviado_en', NOW(),
                'minutos_despues_cita', EXTRACT(EPOCH FROM (NOW() - cita_record.fecha_cita)) / 60
            );

            -- Realizar la petición HTTP POST al webhook
            SELECT content INTO response
            FROM http((
                'POST',
                webhook_url,
                ARRAY[http_header('Content-Type', 'application/json')],
                'application/json',
                payload::text
            )::http_request);

            -- Registrar el envío exitoso
            INSERT INTO citas_webhook_enviadas (cita_id, respuesta_webhook, estado)
            VALUES (cita_record.id, response, 'enviado');

            -- Log para debugging (opcional)
            RAISE NOTICE 'Webhook enviado para cita ID: %, Estado: %, Response: %', 
                cita_record.id, cita_record.estado, response;

        EXCEPTION WHEN OTHERS THEN
            -- Registrar el error pero continuar con las demás citas
            INSERT INTO citas_webhook_enviadas (cita_id, respuesta_webhook, estado)
            VALUES (cita_record.id, SQLERRM, 'error');
            
            RAISE WARNING 'Error al enviar webhook para cita ID %: %', cita_record.id, SQLERRM;
        END;
    END LOOP;
END;
$$;


--
-- Name: estadisticas_leads(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.estadisticas_leads(fecha_inicio date DEFAULT (CURRENT_DATE - '30 days'::interval), fecha_fin date DEFAULT CURRENT_DATE) RETURNS TABLE(total_leads bigint, leads_nuevos bigint, leads_convertidos bigint, leads_descartados bigint, tasa_conversion numeric, score_promedio numeric, leads_con_telefono bigint, leads_con_email bigint, leads_enviados_meta bigint, leads_con_error bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::BIGINT as total_leads,
    COUNT(*) FILTER (WHERE estado_lead = 'Nuevo Lead')::BIGINT as leads_nuevos,
    COUNT(*) FILTER (WHERE fecha_conversion IS NOT NULL)::BIGINT as leads_convertidos,
    COUNT(*) FILTER (WHERE estado_lead = 'Descartado')::BIGINT as leads_descartados,
    ROUND(
      (COUNT(*) FILTER (WHERE fecha_conversion IS NOT NULL)::NUMERIC / 
       NULLIF(COUNT(*)::NUMERIC, 0)) * 100, 
      2
    ) as tasa_conversion,
    ROUND(AVG(score_lead), 2) as score_promedio,
    COUNT(*) FILTER (WHERE telefono IS NOT NULL)::BIGINT as leads_con_telefono,
    COUNT(*) FILTER (WHERE email IS NOT NULL)::BIGINT as leads_con_email,
    COUNT(*) FILTER (WHERE enviado_meta = true)::BIGINT as leads_enviados_meta,
    COUNT(*) FILTER (WHERE error_meta IS NOT NULL)::BIGINT as leads_con_error
  FROM leads_formularios_optimizada
  WHERE fecha_creado BETWEEN fecha_inicio AND fecha_fin;
END;
$$;


--
-- Name: FUNCTION estadisticas_leads(fecha_inicio date, fecha_fin date); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.estadisticas_leads(fecha_inicio date, fecha_fin date) IS 'Estadísticas generales de leads en un rango de fechas';


--
-- Name: fill_date_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fill_date_metadata() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.mes_creacion = EXTRACT(MONTH FROM NEW.fecha_creado);
    NEW.ano_creacion = EXTRACT(YEAR FROM NEW.fecha_creado);
    RETURN NEW;
END;
$$;


--
-- Name: generate_client_id_before_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_client_id_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_client_id TEXT;
    counter INT := 0;
    max_attempts INT := 10;
BEGIN
    -- Solo generar client_id si no viene ya asignado
    IF NEW.client_id IS NULL OR NEW.client_id = '' THEN
        LOOP
            -- Generar ID con timestamp + nanosegundos + random más grande
            new_client_id := FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000000)::TEXT || 
                             LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
            
            -- Verificar si ya existe
            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM leads_formularios_optimizada 
                WHERE client_id = new_client_id
            );
            
            counter := counter + 1;
            
            -- Prevenir loop infinito
            IF counter >= max_attempts THEN
                RAISE EXCEPTION 'No se pudo generar un client_id único después de % intentos', max_attempts;
            END IF;
        END LOOP;
        
        -- Asignar el client_id único
        NEW.client_id := new_client_id;
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: generate_unique_client_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_unique_client_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.client_id IS NULL THEN
        NEW.client_id := FLOOR(EXTRACT(EPOCH FROM NOW()) * 1000)::TEXT || 
                        LPAD(FLOOR(RANDOM() * 1000)::TEXT, 3, '0');
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: get_unsynced_leads(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_unsynced_leads(limit_count integer DEFAULT 100) RETURNS TABLE(id bigint, client_id character varying, nombre_completo character varying, correo_electronico character varying, telefono character varying, estado_lead character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    l.id,
    l.client_id,
    l.nombre_completo,
    l.correo_electronico,
    l.telefono,
    l.estado_lead,
    l.created_at
  FROM leads_formularios_optimizada l
  WHERE l.chatwoot_contact_id IS NULL
  ORDER BY l.created_at DESC
  LIMIT limit_count;
END;
$$;


--
-- Name: insertar_lead_desde_prospecto(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.insertar_lead_desde_prospecto() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO leads_formularios_optimizada (
    empresa,
    email,
    telefono,
    whatsapp,
    estado,
    pais,
    url_origen,
    nombre,
    fuente,
    estado_lead,
    fecha_creado_timestamp
  )
  VALUES (
    NEW.empresa_nombre,
    NEW.email_corporativo,

    -- telefono (solo telefono_empresa)
    CASE 
      WHEN NEW.telefono_empresa IS NOT NULL AND NEW.telefono_empresa <> '' THEN NEW.telefono_empresa
      ELSE NULL
    END,

    -- whatsapp (solo whatsapp_numero)
    CASE 
      WHEN NEW.whatsapp_numero IS NOT NULL AND NEW.whatsapp_numero <> '' THEN NEW.whatsapp_numero
      ELSE NULL
    END,

    NEW.ubicacion_estado,
    'México',
    NEW.sitio_web,
    NEW.contacto_decisor_nombre,
    NEW.fuente_datos,
    'Nuevo Lead',
    NEW.created_at
  );

  RETURN NEW;
END;
$$;


--
-- Name: levantar_penalizacion_asistencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.levantar_penalizacion_asistencia() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Si han pasado más de 1 mes desde la cita y asistencia está en 'false' (penalizado)
  -- entonces cambiar a 'true' para levantar la penalización
  IF NEW.fecha_cita_timezone_cliente + INTERVAL '1 month' < NOW() AND 
     NEW.asistencia = 'false' THEN
    NEW.asistencia := 'true';
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: levantar_penalizaciones_existentes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.levantar_penalizaciones_existentes() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  citas_actualizadas INTEGER;
BEGIN
  UPDATE citas
  SET asistencia = 'true'
  WHERE fecha_cita_timezone_cliente + INTERVAL '1 month' < NOW()
    AND asistencia = 'false';
    
  GET DIAGNOSTICS citas_actualizadas = ROW_COUNT;
  RAISE NOTICE 'Penalizaciones levantadas: %', citas_actualizadas;
END;
$$;


--
-- Name: log_sync_operation(character varying, character varying, character varying, character varying, bigint, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_sync_operation(p_source character varying, p_target character varying, p_operation character varying, p_table character varying, p_record_id bigint, p_payload jsonb) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_log_id BIGINT;
BEGIN
  INSERT INTO sync_log (source, target, operation, table_name, record_id, payload)
  VALUES (p_source, p_target, p_operation, p_table, p_record_id, p_payload)
  RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$;


--
-- Name: marcar_citas_pasadas_existentes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marcar_citas_pasadas_existentes() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE citas
  SET cita_pasada = 'cita_pasada'
  WHERE fecha_cita_timezone_cliente < NOW()
    AND (cita_pasada IS NULL OR cita_pasada != 'cita_pasada');
END;
$$;


--
-- Name: match_documents(public.vector, integer, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.match_documents(query_embedding public.vector, match_count integer DEFAULT NULL::integer, filter jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
    LANGUAGE plpgsql
    AS $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;


--
-- Name: normalizar_telefono(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalizar_telefono() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  phone TEXT;
BEGIN

  ------------------------------------------------------------------
  -- FUNCIÓN LOCAL PARA NORMALIZAR UN NÚMERO INDIVIDUAL
  ------------------------------------------------------------------
  -- Limpia, elimina el "1" fantasma y normaliza tal como tu JS
  ------------------------------------------------------------------
  -- Retorna NULL si el número no existe
  ------------------------------------------------------------------

  -- Normalización general
  phone := NULL;

  ------------------------------------------------------------------
  -- Normalizar whatsapp_numero
  ------------------------------------------------------------------
  IF NEW.whatsapp_numero IS NOT NULL AND NEW.whatsapp_numero != '' THEN
    
    -- Limpiar caracteres no válidos
    phone := regexp_replace(NEW.whatsapp_numero, '[^0-9+]', '', 'g');

    -- ========== PATRONES ESPECIALES ==========

    -- Caso: +521XXXXXXXXXX  (remover 1)
    IF phone ~ '^\+521[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 5);

    -- Caso: 521XXXXXXXXXX (sin +)
    ELSIF phone ~ '^521[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 4);

    -- Caso: +52XXXXXXXXXX (ya está correcto)
    ELSIF phone ~ '^\+52[0-9]{10}$' THEN
      phone := phone;

    -- Caso: 52XXXXXXXXXX (agregar +)
    ELSIF phone ~ '^52[0-9]{10}$' THEN
      phone := '+' || phone;

    -- Caso: 1XXXXXXXXXX (11 dígitos comenzando con 1)
    ELSIF phone ~ '^1[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 2);

    -- Caso: 10 dígitos → asumir número mexicano
    ELSIF phone ~ '^[0-9]{10}$' THEN
      phone := '+52' || phone;

    ELSE
      -- No coincide con ningún patrón
      RAISE WARNING 'WhatsApp inválido o no reconocible: %', phone;
    END IF;

    NEW.whatsapp_numero := phone;
  END IF;


  ------------------------------------------------------------------
  -- Normalizar telefono_empresa (igual que whatsapp_numero)
  ------------------------------------------------------------------
  IF NEW.telefono_empresa IS NOT NULL AND NEW.telefono_empresa != '' THEN
    
    phone := regexp_replace(NEW.telefono_empresa, '[^0-9+]', '', 'g');

    -- +521 → eliminar 1
    IF phone ~ '^\+521[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 5);

    -- 521 → eliminar 1
    ELSIF phone ~ '^521[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 4);

    -- +52 correcto
    ELSIF phone ~ '^\+52[0-9]{10}$' THEN
      phone := phone;

    -- 52XXXXXXXXXX
    ELSIF phone ~ '^52[0-9]{10}$' THEN
      phone := '+' || phone;

    -- 1XXXXXXXXXX
    ELSIF phone ~ '^1[0-9]{10}$' THEN
      phone := '+52' || substr(phone, 2);

    -- 10 dígitos → mexicano válido
    ELSIF phone ~ '^[0-9]{10}$' THEN
      phone := '+52' || phone;

    ELSE
      RAISE WARNING 'Teléfono empresa inválido o desconocido: %', phone;
    END IF;

    NEW.telefono_empresa := phone;
  END IF;


  RETURN NEW;
END;
$_$;


--
-- Name: notify_meta_capi(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_meta_capi() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  -- TU URL CONFIGURADA:
  webhook_url TEXT := 'YOUR_META_WEBHOOK_URL_HERE?secret=YOUR_WEBHOOK_SECRET_HERE';
  payload JSONB;
BEGIN
  -- CASO 1: INSERT (Siempre enviar nuevos leads)
  IF TG_OP = 'INSERT' THEN
    payload := jsonb_build_object(
      'type', TG_OP, 
      'table', TG_TABLE_NAME, 
      'record', row_to_json(NEW), 
      'old_record', NULL
    );
    
    -- CORRECCIÓN CRÍTICA: 'body' se pasa directamente como JSONB
    PERFORM net.http_post(
      url := webhook_url, 
      headers := '{"Content-Type": "application/json"}'::jsonb, 
      body := payload
    );
    
    RETURN NEW;
  END IF;

  -- CASO 2: UPDATE (Solo enviar si cambia el estado o la fecha)
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.estado_lead IS DISTINCT FROM NEW.estado_lead) OR 
       (OLD.fecha_conversion IS DISTINCT FROM NEW.fecha_conversion) THEN
       
      payload := jsonb_build_object(
        'type', TG_OP, 
        'table', TG_TABLE_NAME, 
        'record', row_to_json(NEW), 
        'old_record', row_to_json(OLD)
      );
      
      -- CORRECCIÓN CRÍTICA: 'body' se pasa directamente como JSONB
      PERFORM net.http_post(
        url := webhook_url, 
        headers := '{"Content-Type": "application/json"}'::jsonb, 
        body := payload
      );
    END IF;
    RETURN NEW;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: notify_n8n_lead(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_n8n_lead() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    webhook_url TEXT := 'YOUR_N8N_WEBHOOK_URL_HERE';
    lead_json JSONB;
BEGIN
    -- Solo procesar si la fuente contiene WordPress o Meta_ADS
    IF (NEW.fuente ILIKE '%WordPress%' OR NEW.fuente ILIKE '%Meta_ADS%') THEN
        
        -- Construir el JSON con los datos del lead
        lead_json := json_build_object(
            'nombre', NEW.nombre,
            'client_id', NEW.client_id,
            'email', NEW.email,
            'telefono', NEW.telefono,
            'servicio', NEW.servicio,
            'empresa', NEW.empresa,
            'estado_lead', NEW.estado_lead,
            'fuente', NEW.fuente,
            'pais', NEW.pais,
            'created_at', NEW.created_at
        );
        
        -- Enviar webhook a N8N usando pg_net
        PERFORM net.http_post(
            url := webhook_url,
            headers := '{"Content-Type": "application/json"}'::jsonb,
            body := lead_json
        );
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: notify_sync_service_http(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_sync_service_http() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  payload json;
  response json;
BEGIN
  -- Construir payload
  payload := json_build_object(
    'table', TG_TABLE_NAME,
    'type', TG_OP,
    'record', row_to_json(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
  );

  -- Enviar HTTP request al Sync Service
  -- Nota: Requiere extensión http o usar pg_net de Supabase
  SELECT content::json INTO response
  FROM http_post(
    'YOUR_INTERNAL_SERVICE_URL_HERE',
    payload::text,
    'application/json'
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error pero no fallar el trigger
    RAISE WARNING 'Error notifying sync service: %', SQLERRM;
    RETURN NEW;
END;
$$;


--
-- Name: notify_sync_service_pg(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_sync_service_pg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  payload text;
BEGIN
  payload := json_build_object(
    'table', TG_TABLE_NAME,
    'type', TG_OP,
    'id', NEW.id,
    'client_id', NEW.client_id
  )::text;

  PERFORM pg_notify('sync_channel', payload);
  
  RETURN NEW;
END;
$$;


--
-- Name: notify_vercel_webhook(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_vercel_webhook() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Para INSERT: siempre continuar
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  -- Para UPDATE: solo continuar si cambiaron estado_lead o fecha_conversion
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.estado_lead IS DISTINCT FROM NEW.estado_lead) OR 
       (OLD.fecha_conversion IS DISTINCT FROM NEW.fecha_conversion) THEN
      RETURN NEW;
    ELSE
      -- Si no cambiaron las columnas importantes, cancelar la notificación
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: obtener_estadisticas_citas(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.obtener_estadisticas_citas(fecha_inicio timestamp with time zone DEFAULT (now() - '30 days'::interval), fecha_fin timestamp with time zone DEFAULT now()) RETURNS TABLE(total_citas bigint, citas_completadas bigint, citas_canceladas bigint, citas_pendientes bigint, tasa_completado numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::BIGINT as total_citas,
    COUNT(*) FILTER (WHERE estado = 'completada')::BIGINT as citas_completadas,
    COUNT(*) FILTER (WHERE estado = 'cancelada')::BIGINT as citas_canceladas,
    COUNT(*) FILTER (WHERE estado = 'pendiente')::BIGINT as citas_pendientes,
    ROUND(
      (COUNT(*) FILTER (WHERE estado = 'completada')::NUMERIC / 
       NULLIF(COUNT(*)::NUMERIC, 0)) * 100, 
      2
    ) as tasa_completado
  FROM citas
  WHERE creado BETWEEN fecha_inicio AND fecha_fin;
END;
$$;


--
-- Name: obtener_estadisticas_soporte(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.obtener_estadisticas_soporte(fecha_inicio timestamp with time zone DEFAULT (now() - '30 days'::interval), fecha_fin timestamp with time zone DEFAULT now()) RETURNS TABLE(total_tickets bigint, tickets_abiertos bigint, tickets_resueltos bigint, tickets_cerrados bigint, tiempo_promedio_respuesta numeric, tiempo_promedio_resolucion numeric, satisfaccion_promedio numeric, tasa_resolucion numeric, tickets_escalados bigint, tickets_reabiertos bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::BIGINT as total_tickets,
    COUNT(*) FILTER (WHERE estado = 'abierto')::BIGINT as tickets_abiertos,
    COUNT(*) FILTER (WHERE estado = 'resuelto')::BIGINT as tickets_resueltos,
    COUNT(*) FILTER (WHERE estado = 'cerrado')::BIGINT as tickets_cerrados,
    ROUND(AVG(tiempo_respuesta_minutos), 2) as tiempo_promedio_respuesta,
    ROUND(AVG(tiempo_resolucion_minutos), 2) as tiempo_promedio_resolucion,
    ROUND(AVG(satisfaccion_cliente), 2) as satisfaccion_promedio,
    ROUND(
      (COUNT(*) FILTER (WHERE estado IN ('resuelto', 'cerrado'))::NUMERIC / 
       NULLIF(COUNT(*)::NUMERIC, 0)) * 100, 
      2
    ) as tasa_resolucion,
    COUNT(*) FILTER (WHERE escalado = true)::BIGINT as tickets_escalados,
    COUNT(*) FILTER (WHERE reabierto = true)::BIGINT as tickets_reabiertos
  FROM soporte_tecnico
  WHERE creado BETWEEN fecha_inicio AND fecha_fin;
END;
$$;


--
-- Name: registrar_cambio_estado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_cambio_estado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO citas_historial_estados (
      id,
      cita_id,
      estado_anterior,
      estado_nuevo,
      client_id,
      fecha_cambio
    )
    VALUES (
      (SELECT COALESCE(MAX(id), 0) + 1 FROM citas_historial_estados),
      NEW.id,
      OLD.estado,
      NEW.estado,
      NEW.client_id,
      NOW()
    );
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: registrar_cambio_estado_lead(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_cambio_estado_lead() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Solo registrar si el estado_lead cambió
  IF (OLD.estado_lead IS DISTINCT FROM NEW.estado_lead) THEN
    INSERT INTO historial_estado_leads (
      lead_id_original,
      lead_id,
      fb_click_id,
      nombre,
      email,
      telefono,
      servicio,
      fuente,
      empresa,
      estado,
      pais,
      codigo_postal,
      direccion_ip,
      identificador_externo,
      url_origen,
      user_agent,
      nombre_formulario,
      nombre_campana,
      nombre_conjunto_anuncios,
      nombre_anuncio,
      nombre_pagina,
      estado_lead_anterior,
      estado_lead_nuevo,
      fecha_creado,
      fecha_creado_timestamp,
      created_at,
      updated_at,
      fecha_conversion,
      enviado_meta,
      score_lead,
      mes_creacion,
      ano_creacion,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      fbclid,
      fuente_completa,
      campana_nombre,
      anuncio_nombre,
      error_meta,
      client_id,
      messenger,
      instagram,
      whatsapp,
      identificado,
      nombre_normalizado,
      es_cliente,
      messenger_normalizado,
      instagram_normalizado,
      fecha_cambio,
      usuario_cambio
    ) VALUES (
      OLD.id,
      OLD.lead_id,
      OLD.fb_click_id,
      OLD.nombre,
      OLD.email,
      OLD.telefono,
      OLD.servicio,
      OLD.fuente,
      OLD.empresa,
      OLD.estado,
      OLD.pais,
      OLD.codigo_postal,
      OLD.direccion_ip,
      OLD.identificador_externo,
      OLD.url_origen,
      OLD.user_agent,
      OLD.nombre_formulario,
      OLD.nombre_campana,
      OLD.nombre_conjunto_anuncios,
      OLD.nombre_anuncio,
      OLD.nombre_pagina,
      OLD.estado_lead,
      NEW.estado_lead,
      OLD.fecha_creado,
      OLD.fecha_creado_timestamp,
      OLD.created_at,
      OLD.updated_at,
      OLD.fecha_conversion,
      OLD.enviado_meta,
      OLD.score_lead,
      OLD.mes_creacion,
      OLD.ano_creacion,
      OLD.utm_source,
      OLD.utm_medium,
      OLD.utm_campaign,
      OLD.utm_content,
      OLD.utm_term,
      OLD.fbclid,
      OLD.fuente_completa,
      OLD.campana_nombre,
      OLD.anuncio_nombre,
      OLD.error_meta,
      OLD.client_id,
      OLD.messenger,
      OLD.instagram,
      OLD.whatsapp,
      OLD.identificado,
      OLD.nombre_normalizado,
      OLD.es_cliente,
      OLD.messenger_normalizado,
      OLD.instagram_normalizado,
      NOW(),
      current_user
    );
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: registrar_cambio_estado_soporte(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_cambio_estado_soporte() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO soporte_historial_estados (id, ticket_id, estado_anterior, estado_nuevo)
    VALUES (
      (SELECT COALESCE(MAX(id), 0) + 1 FROM soporte_historial_estados),
      NEW.id,
      OLD.estado,
      NEW.estado
    );
    
    IF NEW.estado = 'resuelto' AND OLD.estado != 'resuelto' THEN
      NEW.resuelto_en = NOW();
      NEW.tiempo_resolucion_minutos = EXTRACT(EPOCH FROM (NOW() - NEW.creado)) / 60;
    END IF;
    
    IF NEW.estado = 'abierto' AND OLD.estado IN ('resuelto', 'cerrado') THEN
      NEW.reabierto = true;
      NEW.numero_reaperturas = NEW.numero_reaperturas + 1;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: registrar_primera_respuesta(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_primera_respuesta() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE soporte_tecnico 
    SET primera_respuesta = NEW.creado,
        tiempo_respuesta_minutos = EXTRACT(EPOCH FROM (NEW.creado - soporte_tecnico.creado)) / 60
    WHERE id = NEW.ticket_id 
      AND primera_respuesta IS NULL
      AND NEW.tipo IN ('respuesta_cliente', 'comentario');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: reset_enviado_meta_on_estado_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_enviado_meta_on_estado_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Si el estado_lead cambió, resetear enviado_meta
    IF OLD.estado_lead IS DISTINCT FROM NEW.estado_lead THEN
        NEW.enviado_meta = FALSE;
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: update_actualizado_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_actualizado_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_client_id_after_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_client_id_after_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_client_id TEXT;
BEGIN
    new_client_id := FLOOR(EXTRACT(EPOCH FROM NOW()) * 1000)::TEXT || 
                     LPAD(FLOOR(RANDOM() * 1000)::TEXT, 3, '0');
    
    UPDATE leads_formularios_optimizada 
    SET client_id = new_client_id
    WHERE id = NEW.id;
    
    RETURN NEW;
END;
$$;


--
-- Name: update_soporte_actualizado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_soporte_actualizado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_ultima_actualizacion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_ultima_actualizacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.ultima_actualizacion = now();
  RETURN NEW;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: validar_fecha_cita(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_fecha_cita() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.fecha_cita < NOW() AND TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'La fecha de la cita no puede ser en el pasado';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: verificar_citas_para_webhook(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verificar_citas_para_webhook() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM enviar_webhook_verificacion_asistencia();
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: leads_formularios_optimizada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads_formularios_optimizada (
    id bigint NOT NULL,
    lead_id character varying(255),
    fb_click_id character varying(255),
    nombre character varying(255),
    email character varying(255),
    telefono character varying(50),
    servicio character varying(255),
    fuente character varying(100),
    empresa character varying(255),
    estado character varying(100),
    pais character varying(100),
    codigo_postal character varying(20),
    direccion_ip inet,
    identificador_externo character varying(255),
    url_origen text,
    user_agent text,
    nombre_formulario character varying(255),
    nombre_campana character varying(255),
    nombre_conjunto_anuncios character varying(255),
    nombre_anuncio character varying(255),
    nombre_pagina character varying(255),
    estado_lead character varying(100) DEFAULT 'Nuevo Lead'::character varying,
    fecha_creado date DEFAULT CURRENT_DATE NOT NULL,
    fecha_creado_timestamp timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    fecha_conversion timestamp with time zone,
    enviado_meta boolean DEFAULT false,
    score_lead integer DEFAULT 0,
    mes_creacion integer,
    ano_creacion integer,
    utm_source character varying(255),
    utm_medium character varying(255),
    utm_campaign character varying(255),
    utm_content character varying(255),
    utm_term character varying(255),
    fbclid character varying(500),
    fuente_completa character varying(255),
    campana_nombre character varying(255),
    anuncio_nombre character varying(255),
    error_meta text,
    client_id text,
    messenger text,
    instagram text,
    whatsapp text,
    identificado text,
    nombre_normalizado text,
    es_cliente text,
    messenger_normalizado text,
    instagram_normalizado text,
    fbp text,
    telegram text,
    conversationid text,
    accountid text,
    content_type text,
    private text,
    content_attributes text,
    contact_id text,
    sessionid text,
    agente text,
    message_type text,
    sender text,
    chatwoot_contact_id integer,
    telegram_normalizado text,
    source_id_web text,
    source_id_chatwoot text
);


--
-- Name: analisis_mensual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.analisis_mensual AS
 SELECT ano_creacion AS "año",
    mes_creacion AS mes,
    to_char((((((ano_creacion || '-'::text) || mes_creacion) || '-01'::text))::date)::timestamp with time zone, 'Month YYYY'::text) AS periodo,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS convertidos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'Nuevo Lead'::text)) AS nuevos,
    count(*) FILTER (WHERE (es_cliente = 'Si'::text)) AS clientes,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio
   FROM public.leads_formularios_optimizada
  WHERE ((ano_creacion IS NOT NULL) AND (mes_creacion IS NOT NULL))
  GROUP BY ano_creacion, mes_creacion
  ORDER BY ano_creacion DESC, mes_creacion DESC;


--
-- Name: analisis_social_media_tiktok; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analisis_social_media_tiktok (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text,
    description text
);


--
-- Name: analisis_social_media_tiktok_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.analisis_social_media_tiktok ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.analisis_social_media_tiktok_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chat_bot_creacion_contenido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_bot_creacion_contenido (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: conversaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversaciones (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    etiqueta text,
    fecha timestamp with time zone DEFAULT now(),
    clasificacion_cita text
);


--
-- Name: n8n_chat_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_id_seq OWNED BY public.conversaciones.id;


--
-- Name: chatbot_prospectos_b2b_WA; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."chatbot_prospectos_b2b_WA" (
    id integer DEFAULT nextval('public.n8n_chat_histories_id_seq'::regclass) NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    etiqueta text,
    fecha timestamp with time zone DEFAULT now(),
    clasificacion_cita text
);


--
-- Name: TABLE "chatbot_prospectos_b2b_WA"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public."chatbot_prospectos_b2b_WA" IS 'This is a duplicate of conversaciones';


--
-- Name: chatbot_prospectos_b2b_wa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chatbot_prospectos_b2b_wa (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: chatbot_prospectos_b2b_wa_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.chatbot_prospectos_b2b_wa_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: chatbot_prospectos_b2b_wa_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.chatbot_prospectos_b2b_wa_id_seq OWNED BY public.chatbot_prospectos_b2b_wa.id;


--
-- Name: citas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.citas (
    id bigint NOT NULL,
    client_id numeric NOT NULL,
    estado character varying(50) DEFAULT ''::character varying,
    nombre character varying(255) NOT NULL,
    fecha_cita timestamp with time zone NOT NULL,
    email character varying(255) NOT NULL,
    telefono character varying(50),
    servicio character varying(200) NOT NULL,
    resumen text,
    pais character varying(100),
    empresa character varying(255),
    enlace_reunion text,
    notas_internas text,
    duracion_minutos integer DEFAULT 60,
    recordatorio_enviado boolean DEFAULT false,
    cancelado_por character varying(100),
    motivo_cancelacion text,
    creado timestamp with time zone DEFAULT now(),
    actualizado timestamp with time zone DEFAULT now(),
    fecha_cita_timezone_cliente timestamp with time zone,
    asistencia text,
    cita_pasada text,
    fecha_cita_timezone_legible text,
    fecha_cita_legible text,
    google_event_id text
);


--
-- Name: TABLE citas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.citas IS 'Tabla principal para gestionar citas con clientes';


--
-- Name: COLUMN citas.notas_internas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.notas_internas IS 'Notas privadas no visibles para el cliente';


--
-- Name: COLUMN citas.duracion_minutos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.duracion_minutos IS 'Duración estimada de la cita en minutos';


--
-- Name: COLUMN citas.recordatorio_enviado; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.recordatorio_enviado IS 'Indica si se envió recordatorio al cliente';


--
-- Name: COLUMN citas.motivo_cancelacion; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.motivo_cancelacion IS 'Razón por la cual se canceló la cita';


--
-- Name: COLUMN citas.asistencia; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.asistencia IS 'asistencia de cliente a reunion';


--
-- Name: COLUMN citas.cita_pasada; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.citas.cita_pasada IS 'indica si la cita ya es del pasado';


--
-- Name: citas_historial_estados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.citas_historial_estados (
    id bigint NOT NULL,
    cita_id bigint,
    estado_anterior character varying(50),
    estado_nuevo character varying(50),
    cambiado_en timestamp with time zone DEFAULT now(),
    notas text,
    client_id text,
    fecha_cambio timestamp with time zone DEFAULT now()
);


--
-- Name: citas_hoy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.citas_hoy AS
 SELECT id,
    client_id,
    estado,
    nombre,
    fecha_cita,
    email,
    telefono,
    servicio,
    resumen,
    pais,
    empresa,
    enlace_reunion,
    notas_internas,
    duracion_minutos,
    recordatorio_enviado,
    cancelado_por,
    motivo_cancelacion,
    creado,
    actualizado
   FROM public.citas
  WHERE (date(fecha_cita) = CURRENT_DATE)
  ORDER BY fecha_cita;


--
-- Name: citas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.citas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: citas_proximas; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.citas_proximas AS
 SELECT id,
    client_id,
    estado,
    nombre,
    fecha_cita,
    email,
    telefono,
    servicio,
    resumen,
    pais,
    empresa,
    enlace_reunion,
    notas_internas,
    duracion_minutos,
    recordatorio_enviado,
    cancelado_por,
    motivo_cancelacion,
    creado,
    actualizado,
    (EXTRACT(epoch FROM (fecha_cita - now())) / (3600)::numeric) AS horas_hasta_cita
   FROM public.citas c
  WHERE ((fecha_cita > now()) AND ((estado)::text <> ALL ((ARRAY['cancelada'::character varying, 'completada'::character varying])::text[])))
  ORDER BY fecha_cita;


--
-- Name: citas_webhook_enviadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.citas_webhook_enviadas (
    id bigint NOT NULL,
    cita_id bigint NOT NULL,
    fecha_envio timestamp with time zone DEFAULT now() NOT NULL,
    respuesta_webhook text,
    estado character varying(50) DEFAULT 'enviado'::character varying
);


--
-- Name: citas_webhook_enviadas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.citas_webhook_enviadas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: citas_webhook_enviadas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.citas_webhook_enviadas_id_seq OWNED BY public.citas_webhook_enviadas.id;


--
-- Name: contador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contador (
    client_id numeric NOT NULL,
    intentos numeric NOT NULL
);


--
-- Name: conversion_por_fuente; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.conversion_por_fuente AS
 SELECT fuente,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS leads_convertidos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'Nuevo Lead'::text)) AS leads_nuevos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'En Seguimiento'::text)) AS leads_seguimiento,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio,
    avg((EXTRACT(epoch FROM (fecha_conversion - created_at)) / (86400)::numeric)) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS dias_promedio_conversion
   FROM public.leads_formularios_optimizada
  GROUP BY fuente
  ORDER BY (count(*)) DESC;


--
-- Name: VIEW conversion_por_fuente; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.conversion_por_fuente IS 'Análisis de rendimiento por fuente de tráfico';


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id bigint NOT NULL,
    content text,
    metadata jsonb,
    embedding public.vector(1536)
);


--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.documents_id_seq OWNED BY public.documents.id;


--
-- Name: eventos_enviados_meta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eventos_enviados_meta (
    event_id text,
    lead_id text,
    estado_lead text,
    fecha_conversion timestamp with time zone,
    event_name text,
    value bigint,
    sent_at timestamp with time zone,
    response text
);


--
-- Name: funnel_conversion; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.funnel_conversion AS
 SELECT estado_lead,
    count(*) AS cantidad,
    round((((count(*))::numeric / ( SELECT (count(*))::numeric AS count
           FROM public.leads_formularios_optimizada leads_formularios_optimizada_1)) * (100)::numeric), 2) AS porcentaje_total,
    avg(score_lead) AS score_promedio,
    avg((EXTRACT(epoch FROM (now() - created_at)) / (86400)::numeric)) AS dias_promedio_en_estado
   FROM public.leads_formularios_optimizada
  GROUP BY estado_lead
  ORDER BY (count(*)) DESC;


--
-- Name: generador_contenido_imagenes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generador_contenido_imagenes (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    prompt text,
    modelo text,
    output_format text DEFAULT 'png'::text,
    image_size text,
    url_1 text,
    url_2 text,
    url_3 text,
    url_4 text,
    url_5 text,
    identificador text
);


--
-- Name: generador_contenido_imagenes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.generador_contenido_imagenes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.generador_contenido_imagenes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: generador_de_contenido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generador_de_contenido (
    id bigint NOT NULL,
    identificador text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    objetivo text,
    url_1 text,
    url_2 text,
    url_3 text,
    url_4 text,
    url_5 text,
    modelo text,
    type text,
    servicio_video text,
    formato_de_imagen_video text,
    duracion_video text,
    descripcion_imagenes_video text,
    idioma text DEFAULT 'es-MX'::text,
    url_logo text
);


--
-- Name: generador_de_contenido_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.generador_de_contenido ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.generador_de_contenido_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: generation_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.generation_jobs (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    telegram_id bigint,
    kie_task_id text,
    status text DEFAULT 'pending'::text,
    model text,
    prompt text,
    result_url text,
    result_metadata jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: historial_estado_leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.historial_estado_leads (
    id bigint NOT NULL,
    lead_id_original bigint NOT NULL,
    lead_id character varying,
    fb_click_id character varying,
    nombre character varying,
    email character varying,
    telefono character varying,
    servicio character varying,
    fuente character varying,
    empresa character varying,
    estado character varying,
    pais character varying,
    codigo_postal character varying,
    direccion_ip inet,
    identificador_externo character varying,
    url_origen text,
    user_agent text,
    nombre_formulario character varying,
    nombre_campana character varying,
    nombre_conjunto_anuncios character varying,
    nombre_anuncio character varying,
    nombre_pagina character varying,
    estado_lead_anterior character varying,
    estado_lead_nuevo character varying,
    fecha_creado date,
    fecha_creado_timestamp timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    fecha_conversion timestamp with time zone,
    enviado_meta boolean,
    score_lead integer,
    mes_creacion integer,
    ano_creacion integer,
    utm_source character varying,
    utm_medium character varying,
    utm_campaign character varying,
    utm_content character varying,
    utm_term character varying,
    fbclid character varying,
    fuente_completa character varying,
    campana_nombre character varying,
    anuncio_nombre character varying,
    error_meta text,
    client_id text,
    messenger text,
    instagram text,
    whatsapp text,
    identificado text,
    nombre_normalizado text,
    es_cliente text,
    messenger_normalizado text,
    instagram_normalizado text,
    fecha_cambio timestamp with time zone DEFAULT now(),
    usuario_cambio text
);


--
-- Name: historial_estado_leads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.historial_estado_leads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: historial_estado_leads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.historial_estado_leads_id_seq OWNED BY public.historial_estado_leads.id;


--
-- Name: leads_alta_prioridad; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_alta_prioridad AS
 SELECT id,
    lead_id,
    client_id,
    nombre,
    email,
    telefono,
    empresa,
    servicio,
    fuente,
    estado_lead,
    score_lead,
    fecha_creado,
        CASE
            WHEN (score_lead >= 80) THEN 'MUY ALTA'::text
            WHEN (score_lead >= 60) THEN 'ALTA'::text
            WHEN (score_lead >= 40) THEN 'MEDIA'::text
            ELSE 'BAJA'::text
        END AS prioridad
   FROM public.leads_formularios_optimizada
  WHERE ((fecha_conversion IS NULL) AND ((estado_lead)::text <> ALL ((ARRAY['Convertido'::character varying, 'Descartado'::character varying, 'Cliente'::character varying])::text[])) AND (score_lead >= 40))
  ORDER BY score_lead DESC, created_at DESC;


--
-- Name: VIEW leads_alta_prioridad; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.leads_alta_prioridad IS 'Leads con score alto pendientes de conversión';


--
-- Name: leads_errores_meta; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_errores_meta AS
 SELECT id,
    lead_id,
    client_id,
    nombre,
    email,
    telefono,
    error_meta,
    enviado_meta,
    nombre_campana,
    nombre_formulario,
    created_at
   FROM public.leads_formularios_optimizada
  WHERE (error_meta IS NOT NULL)
  ORDER BY created_at DESC;


--
-- Name: leads_formularios_optimizada_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.leads_formularios_optimizada_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leads_formularios_optimizada_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.leads_formularios_optimizada_id_seq OWNED BY public.leads_formularios_optimizada.id;


--
-- Name: leads_nuevos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_nuevos AS
 SELECT id,
    lead_id,
    client_id,
    nombre,
    email,
    telefono,
    empresa,
    servicio,
    fuente,
    estado_lead,
    score_lead,
    fecha_creado,
    created_at,
    (EXTRACT(epoch FROM (now() - created_at)) / (3600)::numeric) AS horas_desde_creacion
   FROM public.leads_formularios_optimizada
  WHERE ((fecha_creado >= (CURRENT_DATE - '7 days'::interval)) AND ((estado_lead)::text = 'Nuevo Lead'::text))
  ORDER BY created_at DESC;


--
-- Name: VIEW leads_nuevos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.leads_nuevos IS 'Leads creados en los últimos 7 días sin convertir';


--
-- Name: leads_por_servicio; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_por_servicio AS
 SELECT servicio,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS convertidos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'Nuevo Lead'::text)) AS nuevos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'En Seguimiento'::text)) AS en_seguimiento,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio
   FROM public.leads_formularios_optimizada
  WHERE (servicio IS NOT NULL)
  GROUP BY servicio
  ORDER BY (count(*)) DESC;


--
-- Name: leads_por_ubicacion; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_por_ubicacion AS
 SELECT pais,
    estado,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS convertidos,
    count(*) FILTER (WHERE ((estado_lead)::text = 'Nuevo Lead'::text)) AS nuevos,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio
   FROM public.leads_formularios_optimizada
  WHERE (pais IS NOT NULL)
  GROUP BY pais, estado
  ORDER BY (count(*)) DESC;


--
-- Name: leads_redes_sociales; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_redes_sociales AS
 SELECT id,
    lead_id,
    client_id,
    nombre,
    email,
    telefono,
    messenger,
    messenger_normalizado,
    instagram,
    instagram_normalizado,
    whatsapp,
    fuente,
    estado_lead,
        CASE
            WHEN (messenger IS NOT NULL) THEN true
            ELSE false
        END AS tiene_messenger,
        CASE
            WHEN (instagram IS NOT NULL) THEN true
            ELSE false
        END AS tiene_instagram,
        CASE
            WHEN (whatsapp IS NOT NULL) THEN true
            ELSE false
        END AS tiene_whatsapp,
    fecha_creado
   FROM public.leads_formularios_optimizada
  WHERE ((messenger IS NOT NULL) OR (instagram IS NOT NULL) OR (whatsapp IS NOT NULL))
  ORDER BY created_at DESC;


--
-- Name: leads_sin_contactar; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.leads_sin_contactar AS
 SELECT id,
    lead_id,
    client_id,
    nombre,
    email,
    telefono,
    empresa,
    servicio,
    fuente,
    estado_lead,
    fecha_creado,
    EXTRACT(day FROM (now() - created_at)) AS dias_sin_contacto
   FROM public.leads_formularios_optimizada
  WHERE (((estado_lead)::text = ANY ((ARRAY['Nuevo Lead'::character varying, 'Sin Contactar'::character varying])::text[])) AND (fecha_conversion IS NULL))
  ORDER BY created_at;


--
-- Name: llamadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.llamadas (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resumen text NOT NULL,
    client_id text,
    telefono text,
    fecha_llamada timestamp with time zone,
    fecha_llamada_legible text
);


--
-- Name: TABLE llamadas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.llamadas IS 'memoria de llamadas retellai';


--
-- Name: llamadas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.llamadas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.llamadas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media_assets (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    telegram_id bigint,
    telegram_file_id text,
    storage_path text NOT NULL,
    public_url text NOT NULL,
    file_type text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: n8n_chat_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_chat_histories_id_seq1; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_id_seq1 OWNED BY public.chat_bot_creacion_contenido.id;


--
-- Name: n8n_chat_histories_id_seq2; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_id_seq2
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_id_seq2; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_id_seq2 OWNED BY public.n8n_chat_histories.id;


--
-- Name: prospectos_b2b; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prospectos_b2b (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    empresa_nombre text NOT NULL,
    industria text,
    ubicacion_ciudad text,
    ubicacion_estado text,
    tamano_empresa text,
    sitio_web text,
    email_corporativo text,
    telefono_empresa text,
    linkedin_url text,
    facebook_url text,
    instagram_url text,
    contacto_decisor_nombre text,
    contacto_decisor_cargo text,
    contacto_decisor_linkedin text,
    tecnologias_detectadas jsonb DEFAULT '{}'::jsonb,
    performance_score integer,
    seo_score integer,
    mobile_friendly boolean,
    tiene_chatbot boolean DEFAULT false,
    tiene_analytics boolean DEFAULT false,
    lead_score numeric(3,1),
    clasificacion text,
    oportunidades_detectadas text[],
    notas_personalizacion text,
    estado_contacto text DEFAULT 'no_contactado'::text,
    canal_contacto text,
    fecha_ultimo_contacto timestamp with time zone,
    fecha_proximo_followup timestamp with time zone,
    fuente_datos text,
    ultima_actualizacion timestamp with time zone DEFAULT now(),
    mensaje_personalizado text,
    mejoras_sugeridas text[],
    caso_exito_industria text,
    noticia_ia_url text,
    noticia_ia_titulo text,
    noticia_ia_resumen text,
    noticia_ia_fecha date,
    impacto_ia_negocio text,
    servicios_recomendados text[],
    email_status text DEFAULT 'unknown'::text,
    timezone text DEFAULT 'America/Mexico_City'::text,
    tech_stack text[],
    pain_point_hypothesis text,
    email_enviado boolean,
    whatsapp_enviado boolean,
    whatsapp_numero text,
    whatsapp_enviado_manualmente boolean,
    email_enviado_manualmente boolean,
    CONSTRAINT prospectos_b2b_canal_contacto_check CHECK ((canal_contacto = ANY (ARRAY['email'::text, 'linkedin'::text, 'llamada'::text, 'whatsapp'::text]))),
    CONSTRAINT prospectos_b2b_clasificacion_check CHECK ((clasificacion = ANY (ARRAY['HOT'::text, 'WARM'::text, 'COLD'::text, 'PENDIENTE'::text]))),
    CONSTRAINT prospectos_b2b_estado_contacto_check CHECK ((estado_contacto = ANY (ARRAY['no_contactado'::text, 'contactado'::text, 'interesado'::text, 'negociacion'::text, 'perdido'::text, 'cliente'::text]))),
    CONSTRAINT prospectos_b2b_lead_score_check CHECK (((lead_score >= (0)::numeric) AND (lead_score <= (10)::numeric))),
    CONSTRAINT prospectos_b2b_performance_score_check CHECK (((performance_score >= 0) AND (performance_score <= 100))),
    CONSTRAINT prospectos_b2b_seo_score_check CHECK (((seo_score >= 0) AND (seo_score <= 100))),
    CONSTRAINT prospectos_b2b_tamano_empresa_check CHECK ((tamano_empresa = ANY (ARRAY['micro'::text, 'pequeña'::text, 'mediana'::text, 'grande'::text])))
);


--
-- Name: TABLE prospectos_b2b; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prospectos_b2b IS 'Table for B2B prospects for your_brand automation';


--
-- Name: COLUMN prospectos_b2b.mensaje_personalizado; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.mensaje_personalizado IS 'Mensaje completo personalizado listo para email/llamada';


--
-- Name: COLUMN prospectos_b2b.mejoras_sugeridas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.mejoras_sugeridas IS 'Array de mejoras específicas detectadas';


--
-- Name: COLUMN prospectos_b2b.caso_exito_industria; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.caso_exito_industria IS 'Caso de éxito relevante de la industria';


--
-- Name: COLUMN prospectos_b2b.noticia_ia_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.noticia_ia_url IS 'URL de noticia actual sobre IA en su sector';


--
-- Name: COLUMN prospectos_b2b.noticia_ia_titulo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.noticia_ia_titulo IS 'Título de la noticia';


--
-- Name: COLUMN prospectos_b2b.noticia_ia_resumen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.noticia_ia_resumen IS 'Resumen ejecutivo de la noticia';


--
-- Name: COLUMN prospectos_b2b.noticia_ia_fecha; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.noticia_ia_fecha IS 'Fecha de publicación de la noticia';


--
-- Name: COLUMN prospectos_b2b.impacto_ia_negocio; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.impacto_ia_negocio IS 'Descripción del impacto de IA en su tipo de negocio';


--
-- Name: COLUMN prospectos_b2b.servicios_recomendados; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.servicios_recomendados IS 'Servicios your_brand recomendados';


--
-- Name: COLUMN prospectos_b2b.email_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.email_status IS 'Estado de verificación del email (valid, invalid, risky) para Instantly.ai';


--
-- Name: COLUMN prospectos_b2b.timezone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.timezone IS 'Zona horaria para agendar llamadas con Retell AI correctamente';


--
-- Name: COLUMN prospectos_b2b.tech_stack; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.tech_stack IS 'Tecnologías detectadas en su sitio web (ej: WordPress, Shopify) para personalizar el pitch';


--
-- Name: COLUMN prospectos_b2b.pain_point_hypothesis; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prospectos_b2b.pain_point_hypothesis IS 'Hipótesis específica del problema que enfrenta este prospecto en particular';


--
-- Name: publicaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publicaciones (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    url text,
    descripcion text,
    fecha_publicacion text,
    transcripcion text
);


--
-- Name: publicaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.publicaciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.publicaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publish_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publish_jobs (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    telegram_id bigint,
    platforms text[],
    status text DEFAULT 'pending'::text,
    content_data jsonb,
    logs jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: rendimiento_campanas_meta; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.rendimiento_campanas_meta AS
 SELECT nombre_campana,
    nombre_conjunto_anuncios,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS leads_convertidos,
    count(*) FILTER (WHERE (enviado_meta = true)) AS enviados_meta,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio,
    count(DISTINCT date(created_at)) AS dias_activos,
    (count(*) / NULLIF(count(DISTINCT date(created_at)), 0)) AS leads_por_dia
   FROM public.leads_formularios_optimizada
  WHERE (nombre_campana IS NOT NULL)
  GROUP BY nombre_campana, nombre_conjunto_anuncios
  ORDER BY (count(*)) DESC;


--
-- Name: VIEW rendimiento_campanas_meta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.rendimiento_campanas_meta IS 'Métricas de campañas de Meta Ads';


--
-- Name: rendimiento_utm; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.rendimiento_utm AS
 SELECT utm_source,
    utm_medium,
    utm_campaign,
    count(*) AS total_leads,
    count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)) AS convertidos,
    round((((count(*) FILTER (WHERE (fecha_conversion IS NOT NULL)))::numeric / NULLIF((count(*))::numeric, (0)::numeric)) * (100)::numeric), 2) AS tasa_conversion,
    avg(score_lead) AS score_promedio
   FROM public.leads_formularios_optimizada
  WHERE ((utm_source IS NOT NULL) OR (utm_campaign IS NOT NULL))
  GROUP BY utm_source, utm_medium, utm_campaign
  ORDER BY (count(*)) DESC;


--
-- Name: reportes_quejas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reportes_quejas (
    id bigint NOT NULL,
    client_id numeric NOT NULL,
    fecha timestamp with time zone DEFAULT now(),
    cliente_nombre character varying(255) NOT NULL,
    tipo_queja character varying(100),
    nivel_urgencia character varying(50),
    servicio_afectado character varying(200),
    detalles text,
    emocion_cliente character varying(100),
    escalacion_requerida boolean DEFAULT false,
    estado character varying(50) DEFAULT 'pendiente'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    formulario_enviado text,
    telefono text,
    empresa text
);


--
-- Name: reportes_quejas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reportes_quejas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reportes_quejas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: soporte_tecnico_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.soporte_tecnico_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: soporte_tecnico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.soporte_tecnico (
    id bigint NOT NULL,
    ticket_numero character varying(50) DEFAULT ('TICKET-'::text || lpad((nextval('public.soporte_tecnico_seq'::regclass))::text, 6, '0'::text)) NOT NULL,
    client_id numeric NOT NULL,
    estado character varying(50) DEFAULT 'abierto'::character varying,
    prioridad character varying(50) DEFAULT 'media'::character varying,
    nombre_cliente character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    telefono character varying(50),
    empresa character varying(255),
    categoria character varying(100) NOT NULL,
    tipo_problema character varying(100),
    asunto character varying(500) NOT NULL,
    descripcion text NOT NULL,
    solucion text,
    notas_internas text,
    asignado_a character varying(255),
    tiempo_respuesta_minutos integer,
    tiempo_resolucion_minutos integer,
    primera_respuesta timestamp with time zone,
    resuelto_en timestamp with time zone,
    satisfaccion_cliente integer,
    comentario_satisfaccion text,
    sistema_operativo character varying(100),
    navegador character varying(100),
    version_producto character varying(50),
    archivos_adjuntos jsonb DEFAULT '[]'::jsonb,
    tags character varying(50)[] DEFAULT ARRAY[]::character varying[],
    escalado boolean DEFAULT false,
    escalado_a character varying(255),
    reabierto boolean DEFAULT false,
    numero_reaperturas integer DEFAULT 0,
    creado timestamp with time zone DEFAULT now(),
    actualizado timestamp with time zone DEFAULT now(),
    CONSTRAINT soporte_tecnico_satisfaccion_cliente_check CHECK (((satisfaccion_cliente >= 1) AND (satisfaccion_cliente <= 5)))
);


--
-- Name: resumen_por_agente; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.resumen_por_agente AS
 SELECT asignado_a,
    count(*) FILTER (WHERE ((estado)::text = 'abierto'::text)) AS tickets_abiertos,
    count(*) FILTER (WHERE ((estado)::text = 'en_progreso'::text)) AS tickets_en_progreso,
    count(*) FILTER (WHERE (((estado)::text = 'resuelto'::text) AND (date(resuelto_en) = CURRENT_DATE))) AS resueltos_hoy,
    count(*) FILTER (WHERE (((estado)::text = 'resuelto'::text) AND (date(resuelto_en) >= (CURRENT_DATE - '7 days'::interval)))) AS resueltos_semana,
    avg(tiempo_resolucion_minutos) FILTER (WHERE ((estado)::text = 'resuelto'::text)) AS tiempo_promedio_resolucion,
    avg(satisfaccion_cliente) FILTER (WHERE (satisfaccion_cliente IS NOT NULL)) AS satisfaccion_promedio
   FROM public.soporte_tecnico
  WHERE (asignado_a IS NOT NULL)
  GROUP BY asignado_a
  ORDER BY (count(*) FILTER (WHERE ((estado)::text = 'abierto'::text))) DESC;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    telegram_id bigint NOT NULL,
    state jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_updated timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: soporte_comentarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.soporte_comentarios (
    id bigint NOT NULL,
    ticket_id bigint,
    autor character varying(255) NOT NULL,
    tipo character varying(50) DEFAULT 'comentario'::character varying,
    contenido text NOT NULL,
    es_publico boolean DEFAULT true,
    archivos_adjuntos jsonb DEFAULT '[]'::jsonb,
    creado timestamp with time zone DEFAULT now()
);


--
-- Name: soporte_historial_estados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.soporte_historial_estados (
    id bigint NOT NULL,
    ticket_id bigint,
    estado_anterior character varying(50),
    estado_nuevo character varying(50),
    cambiado_por character varying(255),
    cambiado_en timestamp with time zone DEFAULT now(),
    notas text
);


--
-- Name: soporte_tiempo_trabajado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.soporte_tiempo_trabajado (
    id bigint NOT NULL,
    ticket_id bigint,
    usuario character varying(255) NOT NULL,
    minutos_trabajados integer NOT NULL,
    descripcion_trabajo text,
    fecha_trabajo timestamp with time zone DEFAULT now()
);


--
-- Name: sync_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sync_log (
    id bigint NOT NULL,
    source character varying(50) NOT NULL,
    target character varying(50) NOT NULL,
    operation character varying(20) NOT NULL,
    table_name character varying(100),
    record_id bigint,
    status character varying(20) DEFAULT 'pending'::character varying,
    error_message text,
    payload jsonb,
    created_at timestamp with time zone DEFAULT now(),
    processed_at timestamp with time zone
);


--
-- Name: sync_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sync_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sync_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sync_log_id_seq OWNED BY public.sync_log.id;


--
-- Name: sync_status_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sync_status_summary AS
 SELECT count(*) FILTER (WHERE (chatwoot_contact_id IS NOT NULL)) AS synced_leads,
    count(*) FILTER (WHERE (chatwoot_contact_id IS NULL)) AS unsynced_leads,
    count(*) AS total_leads,
    round(((100.0 * (count(*) FILTER (WHERE (chatwoot_contact_id IS NOT NULL)))::numeric) / (NULLIF(count(*), 0))::numeric), 2) AS sync_percentage
   FROM public.leads_formularios_optimizada
  WHERE (created_at > (now() - '30 days'::interval));


--
-- Name: tickets_abiertos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tickets_abiertos AS
SELECT
    NULL::bigint AS id,
    NULL::character varying(50) AS ticket_numero,
    NULL::numeric AS client_id,
    NULL::character varying(50) AS estado,
    NULL::character varying(50) AS prioridad,
    NULL::character varying(255) AS nombre_cliente,
    NULL::character varying(255) AS email,
    NULL::character varying(50) AS telefono,
    NULL::character varying(255) AS empresa,
    NULL::character varying(100) AS categoria,
    NULL::character varying(100) AS tipo_problema,
    NULL::character varying(500) AS asunto,
    NULL::text AS descripcion,
    NULL::text AS solucion,
    NULL::text AS notas_internas,
    NULL::character varying(255) AS asignado_a,
    NULL::integer AS tiempo_respuesta_minutos,
    NULL::integer AS tiempo_resolucion_minutos,
    NULL::timestamp with time zone AS primera_respuesta,
    NULL::timestamp with time zone AS resuelto_en,
    NULL::integer AS satisfaccion_cliente,
    NULL::text AS comentario_satisfaccion,
    NULL::character varying(100) AS sistema_operativo,
    NULL::character varying(100) AS navegador,
    NULL::character varying(50) AS version_producto,
    NULL::jsonb AS archivos_adjuntos,
    NULL::character varying(50)[] AS tags,
    NULL::boolean AS escalado,
    NULL::character varying(255) AS escalado_a,
    NULL::boolean AS reabierto,
    NULL::integer AS numero_reaperturas,
    NULL::timestamp with time zone AS creado,
    NULL::timestamp with time zone AS actualizado,
    NULL::bigint AS total_comentarios,
    NULL::timestamp with time zone AS ultimo_comentario,
    NULL::bigint AS total_minutos_trabajados;


--
-- Name: tickets_sin_asignar; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tickets_sin_asignar AS
 SELECT id,
    ticket_numero,
    client_id,
    estado,
    prioridad,
    nombre_cliente,
    email,
    telefono,
    empresa,
    categoria,
    tipo_problema,
    asunto,
    descripcion,
    solucion,
    notas_internas,
    asignado_a,
    tiempo_respuesta_minutos,
    tiempo_resolucion_minutos,
    primera_respuesta,
    resuelto_en,
    satisfaccion_cliente,
    comentario_satisfaccion,
    sistema_operativo,
    navegador,
    version_producto,
    archivos_adjuntos,
    tags,
    escalado,
    escalado_a,
    reabierto,
    numero_reaperturas,
    creado,
    actualizado
   FROM public.soporte_tecnico
  WHERE (((asignado_a IS NULL) OR ((asignado_a)::text = ''::text)) AND ((estado)::text <> ALL ((ARRAY['cerrado'::character varying, 'resuelto'::character varying])::text[])))
  ORDER BY
        CASE prioridad
            WHEN 'critica'::text THEN 1
            WHEN 'alta'::text THEN 2
            WHEN 'media'::text THEN 3
            WHEN 'baja'::text THEN 4
            ELSE NULL::integer
        END, creado;


--
-- Name: tickets_sla; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tickets_sla AS
 SELECT id,
    ticket_numero,
    client_id,
    estado,
    prioridad,
    nombre_cliente,
    email,
    telefono,
    empresa,
    categoria,
    tipo_problema,
    asunto,
    descripcion,
    solucion,
    notas_internas,
    asignado_a,
    tiempo_respuesta_minutos,
    tiempo_resolucion_minutos,
    primera_respuesta,
    resuelto_en,
    satisfaccion_cliente,
    comentario_satisfaccion,
    sistema_operativo,
    navegador,
    version_producto,
    archivos_adjuntos,
    tags,
    escalado,
    escalado_a,
    reabierto,
    numero_reaperturas,
    creado,
    actualizado,
    (EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) AS horas_abierto,
        CASE
            WHEN (((prioridad)::text = 'critica'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (4)::numeric)) THEN 'SLA_VIOLADO'::text
            WHEN (((prioridad)::text = 'alta'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (24)::numeric)) THEN 'SLA_VIOLADO'::text
            WHEN (((prioridad)::text = 'media'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (72)::numeric)) THEN 'SLA_VIOLADO'::text
            WHEN (((prioridad)::text = 'critica'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (2)::numeric)) THEN 'PROXIMO_A_VENCER'::text
            WHEN (((prioridad)::text = 'alta'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (20)::numeric)) THEN 'PROXIMO_A_VENCER'::text
            WHEN (((prioridad)::text = 'media'::text) AND ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (60)::numeric)) THEN 'PROXIMO_A_VENCER'::text
            ELSE 'EN_TIEMPO'::text
        END AS estado_sla
   FROM public.soporte_tecnico st
  WHERE ((estado)::text <> ALL ((ARRAY['cerrado'::character varying, 'resuelto'::character varying])::text[]))
  ORDER BY
        CASE
            WHEN ((EXTRACT(epoch FROM (now() - creado)) / (3600)::numeric) > (
            CASE prioridad
                WHEN 'critica'::text THEN 4
                WHEN 'alta'::text THEN 24
                WHEN 'media'::text THEN 72
                ELSE 168
            END)::numeric) THEN 1
            ELSE 2
        END, creado;


--
-- Name: tickets_urgentes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tickets_urgentes AS
SELECT
    NULL::bigint AS id,
    NULL::character varying(50) AS ticket_numero,
    NULL::numeric AS client_id,
    NULL::character varying(50) AS estado,
    NULL::character varying(50) AS prioridad,
    NULL::character varying(255) AS nombre_cliente,
    NULL::character varying(255) AS email,
    NULL::character varying(50) AS telefono,
    NULL::character varying(255) AS empresa,
    NULL::character varying(100) AS categoria,
    NULL::character varying(100) AS tipo_problema,
    NULL::character varying(500) AS asunto,
    NULL::text AS descripcion,
    NULL::text AS solucion,
    NULL::text AS notas_internas,
    NULL::character varying(255) AS asignado_a,
    NULL::integer AS tiempo_respuesta_minutos,
    NULL::integer AS tiempo_resolucion_minutos,
    NULL::timestamp with time zone AS primera_respuesta,
    NULL::timestamp with time zone AS resuelto_en,
    NULL::integer AS satisfaccion_cliente,
    NULL::text AS comentario_satisfaccion,
    NULL::character varying(100) AS sistema_operativo,
    NULL::character varying(100) AS navegador,
    NULL::character varying(50) AS version_producto,
    NULL::jsonb AS archivos_adjuntos,
    NULL::character varying(50)[] AS tags,
    NULL::boolean AS escalado,
    NULL::character varying(255) AS escalado_a,
    NULL::boolean AS reabierto,
    NULL::integer AS numero_reaperturas,
    NULL::timestamp with time zone AS creado,
    NULL::timestamp with time zone AS actualizado,
    NULL::numeric AS horas_abierto,
    NULL::bigint AS total_comentarios;


--
-- Name: tokens_fbpage&ig; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."tokens_fbpage&ig" (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    token text,
    creado timestamp with time zone,
    vencimiento timestamp with time zone,
    canal text,
    page_id text,
    tipo_de_token text,
    identificador_de_app text
);


--
-- Name: tokens_fbpgae&ig_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."tokens_fbpage&ig" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."tokens_fbpgae&ig_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    telegram_id bigint NOT NULL,
    username text,
    first_name text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: videos_SORA_&_imagenes_nanobanana; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."videos_SORA_&_imagenes_nanobanana" (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type text,
    url text,
    descripcion_para_copy text,
    nombre text,
    id_publicacion text
);


--
-- Name: videos_SORA_2_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."videos_SORA_&_imagenes_nanobanana" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."videos_SORA_2_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vista_penalizaciones_activas; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vista_penalizaciones_activas AS
 SELECT id,
    client_id,
    estado,
    nombre,
    fecha_cita,
    email,
    telefono,
    servicio,
    resumen,
    pais,
    empresa,
    enlace_reunion,
    notas_internas,
    duracion_minutos,
    recordatorio_enviado,
    cancelado_por,
    motivo_cancelacion,
    creado,
    actualizado,
    fecha_cita_timezone_cliente,
    asistencia,
    cita_pasada,
    (fecha_cita_timezone_cliente + '1 mon'::interval) AS penalizacion_termina,
    EXTRACT(day FROM ((fecha_cita_timezone_cliente + '1 mon'::interval) - now())) AS dias_restantes
   FROM public.citas c
  WHERE ((asistencia = 'false'::text) AND ((fecha_cita_timezone_cliente + '1 mon'::interval) > now()))
  ORDER BY fecha_cita_timezone_cliente DESC;


--
-- Name: chat_bot_creacion_contenido id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_bot_creacion_contenido ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_id_seq1'::regclass);


--
-- Name: chatbot_prospectos_b2b_wa id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chatbot_prospectos_b2b_wa ALTER COLUMN id SET DEFAULT nextval('public.chatbot_prospectos_b2b_wa_id_seq'::regclass);


--
-- Name: citas_webhook_enviadas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_webhook_enviadas ALTER COLUMN id SET DEFAULT nextval('public.citas_webhook_enviadas_id_seq'::regclass);


--
-- Name: conversaciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversaciones ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents ALTER COLUMN id SET DEFAULT nextval('public.documents_id_seq'::regclass);


--
-- Name: historial_estado_leads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_estado_leads ALTER COLUMN id SET DEFAULT nextval('public.historial_estado_leads_id_seq'::regclass);


--
-- Name: leads_formularios_optimizada id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads_formularios_optimizada ALTER COLUMN id SET DEFAULT nextval('public.leads_formularios_optimizada_id_seq'::regclass);


--
-- Name: n8n_chat_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_id_seq2'::regclass);


--
-- Name: sync_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_log ALTER COLUMN id SET DEFAULT nextval('public.sync_log_id_seq'::regclass);


--
-- Name: analisis_social_media_tiktok analisis_social_media_tiktok_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analisis_social_media_tiktok
    ADD CONSTRAINT analisis_social_media_tiktok_pkey PRIMARY KEY (id);


--
-- Name: chatbot_prospectos_b2b_WA chatbot_prospectos_b2b_WA_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."chatbot_prospectos_b2b_WA"
    ADD CONSTRAINT "chatbot_prospectos_b2b_WA_pkey" PRIMARY KEY (id);


--
-- Name: chatbot_prospectos_b2b_wa chatbot_prospectos_b2b_wa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chatbot_prospectos_b2b_wa
    ADD CONSTRAINT chatbot_prospectos_b2b_wa_pkey PRIMARY KEY (id);


--
-- Name: citas_historial_estados citas_historial_estados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_historial_estados
    ADD CONSTRAINT citas_historial_estados_pkey PRIMARY KEY (id);


--
-- Name: citas citas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas
    ADD CONSTRAINT citas_pkey PRIMARY KEY (id);


--
-- Name: citas_webhook_enviadas citas_webhook_enviadas_cita_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_webhook_enviadas
    ADD CONSTRAINT citas_webhook_enviadas_cita_id_key UNIQUE (cita_id);


--
-- Name: citas_webhook_enviadas citas_webhook_enviadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_webhook_enviadas
    ADD CONSTRAINT citas_webhook_enviadas_pkey PRIMARY KEY (id);


--
-- Name: contador contador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contador
    ADD CONSTRAINT contador_pkey PRIMARY KEY (client_id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: generador_contenido_imagenes generador_contenido_imagenes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generador_contenido_imagenes
    ADD CONSTRAINT generador_contenido_imagenes_pkey PRIMARY KEY (id);


--
-- Name: generador_de_contenido generador_de_contenido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generador_de_contenido
    ADD CONSTRAINT generador_de_contenido_pkey PRIMARY KEY (id);


--
-- Name: generation_jobs generation_jobs_kie_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_jobs
    ADD CONSTRAINT generation_jobs_kie_task_id_key UNIQUE (kie_task_id);


--
-- Name: generation_jobs generation_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_jobs
    ADD CONSTRAINT generation_jobs_pkey PRIMARY KEY (id);


--
-- Name: historial_estado_leads historial_estado_leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_estado_leads
    ADD CONSTRAINT historial_estado_leads_pkey PRIMARY KEY (id);


--
-- Name: leads_formularios_optimizada leads_formularios_optimizada_client_Id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads_formularios_optimizada
    ADD CONSTRAINT "leads_formularios_optimizada_client_Id_key" UNIQUE (client_id);


--
-- Name: leads_formularios_optimizada leads_formularios_optimizada_lead_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads_formularios_optimizada
    ADD CONSTRAINT leads_formularios_optimizada_lead_id_key UNIQUE (lead_id);


--
-- Name: leads_formularios_optimizada leads_formularios_optimizada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads_formularios_optimizada
    ADD CONSTRAINT leads_formularios_optimizada_pkey PRIMARY KEY (id);


--
-- Name: llamadas llamadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.llamadas
    ADD CONSTRAINT llamadas_pkey PRIMARY KEY (id);


--
-- Name: media_assets media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_pkey PRIMARY KEY (id);


--
-- Name: conversaciones n8n_chat_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversaciones
    ADD CONSTRAINT n8n_chat_histories_pkey PRIMARY KEY (id);


--
-- Name: chat_bot_creacion_contenido n8n_chat_histories_pkey1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_bot_creacion_contenido
    ADD CONSTRAINT n8n_chat_histories_pkey1 PRIMARY KEY (id);


--
-- Name: n8n_chat_histories n8n_chat_histories_pkey2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories
    ADD CONSTRAINT n8n_chat_histories_pkey2 PRIMARY KEY (id);


--
-- Name: prospectos_b2b prospectos_b2b_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospectos_b2b
    ADD CONSTRAINT prospectos_b2b_pkey PRIMARY KEY (id);


--
-- Name: publicaciones publicaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publicaciones
    ADD CONSTRAINT publicaciones_pkey PRIMARY KEY (id);


--
-- Name: publish_jobs publish_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_jobs
    ADD CONSTRAINT publish_jobs_pkey PRIMARY KEY (id);


--
-- Name: reportes_quejas reportes_quejas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reportes_quejas
    ADD CONSTRAINT reportes_quejas_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (telegram_id);


--
-- Name: soporte_comentarios soporte_comentarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_comentarios
    ADD CONSTRAINT soporte_comentarios_pkey PRIMARY KEY (id);


--
-- Name: soporte_historial_estados soporte_historial_estados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_historial_estados
    ADD CONSTRAINT soporte_historial_estados_pkey PRIMARY KEY (id);


--
-- Name: soporte_tecnico soporte_tecnico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_tecnico
    ADD CONSTRAINT soporte_tecnico_pkey PRIMARY KEY (id);


--
-- Name: soporte_tecnico soporte_tecnico_ticket_numero_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_tecnico
    ADD CONSTRAINT soporte_tecnico_ticket_numero_key UNIQUE (ticket_numero);


--
-- Name: soporte_tiempo_trabajado soporte_tiempo_trabajado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_tiempo_trabajado
    ADD CONSTRAINT soporte_tiempo_trabajado_pkey PRIMARY KEY (id);


--
-- Name: sync_log sync_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_pkey PRIMARY KEY (id);


--
-- Name: tokens_fbpage&ig tokens_fbpgae&ig_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."tokens_fbpage&ig"
    ADD CONSTRAINT "tokens_fbpgae&ig_pkey" PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (telegram_id);


--
-- Name: videos_SORA_&_imagenes_nanobanana videos_SORA_2_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."videos_SORA_&_imagenes_nanobanana"
    ADD CONSTRAINT "videos_SORA_2_pkey" PRIMARY KEY (id);


--
-- Name: idx_citas_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_client_id ON public.citas USING btree (client_id);


--
-- Name: idx_citas_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_email ON public.citas USING btree (email);


--
-- Name: idx_citas_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_estado ON public.citas USING btree (estado);


--
-- Name: idx_citas_fecha_cita; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_fecha_cita ON public.citas USING btree (fecha_cita);


--
-- Name: idx_citas_fecha_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_fecha_estado ON public.citas USING btree (fecha_cita, estado);


--
-- Name: idx_citas_servicio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_citas_servicio ON public.citas USING btree (servicio);


--
-- Name: idx_clasificacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clasificacion ON public.prospectos_b2b USING btree (clasificacion);


--
-- Name: idx_email_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_email_unique ON public.prospectos_b2b USING btree (email_corporativo) WHERE (email_corporativo IS NOT NULL);


--
-- Name: idx_estado_contacto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_estado_contacto ON public.prospectos_b2b USING btree (estado_contacto);


--
-- Name: idx_eventos_event_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_eventos_event_name ON public.eventos_enviados_meta USING btree (event_name);


--
-- Name: idx_eventos_fecha_conversion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_eventos_fecha_conversion ON public.eventos_enviados_meta USING btree (fecha_conversion);


--
-- Name: idx_eventos_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_eventos_lead_id ON public.eventos_enviados_meta USING btree (lead_id);


--
-- Name: idx_fecha_followup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fecha_followup ON public.prospectos_b2b USING btree (fecha_proximo_followup) WHERE (fecha_proximo_followup IS NOT NULL);


--
-- Name: idx_historial_estado_nuevo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historial_estado_nuevo ON public.historial_estado_leads USING btree (estado_lead_nuevo);


--
-- Name: idx_historial_fecha_cambio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historial_fecha_cambio ON public.historial_estado_leads USING btree (fecha_cambio);


--
-- Name: idx_historial_lead_id_original; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historial_lead_id_original ON public.historial_estado_leads USING btree (lead_id_original);


--
-- Name: idx_industria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_industria ON public.prospectos_b2b USING btree (industria);


--
-- Name: idx_lead_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lead_score ON public.prospectos_b2b USING btree (lead_score DESC);


--
-- Name: idx_leads_busqueda_texto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_busqueda_texto ON public.leads_formularios_optimizada USING gin (to_tsvector('spanish'::regconfig, (((((((COALESCE(nombre, ''::character varying))::text || ' '::text) || (COALESCE(email, ''::character varying))::text) || ' '::text) || (COALESCE(empresa, ''::character varying))::text) || ' '::text) || (COALESCE(telefono, ''::character varying))::text)));


--
-- Name: idx_leads_campana_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_campana_nombre ON public.leads_formularios_optimizada USING btree (campana_nombre);


--
-- Name: idx_leads_chatwoot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_chatwoot_id ON public.leads_formularios_optimizada USING btree (chatwoot_contact_id);


--
-- Name: idx_leads_client_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_client_estado ON public.leads_formularios_optimizada USING btree (client_id, estado_lead);


--
-- Name: idx_leads_client_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_client_fecha ON public.leads_formularios_optimizada USING btree (client_id, fecha_creado DESC);


--
-- Name: idx_leads_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_client_id ON public.leads_formularios_optimizada USING btree (client_id);


--
-- Name: idx_leads_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_created_at ON public.leads_formularios_optimizada USING btree (created_at);


--
-- Name: idx_leads_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_email ON public.leads_formularios_optimizada USING btree (email);


--
-- Name: idx_leads_enviado_meta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_enviado_meta ON public.leads_formularios_optimizada USING btree (enviado_meta);


--
-- Name: idx_leads_es_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_es_cliente ON public.leads_formularios_optimizada USING btree (es_cliente) WHERE (es_cliente IS NOT NULL);


--
-- Name: idx_leads_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_estado ON public.leads_formularios_optimizada USING btree (estado);


--
-- Name: idx_leads_estado_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_estado_fecha ON public.leads_formularios_optimizada USING btree (estado_lead, fecha_creado DESC);


--
-- Name: idx_leads_estado_lead; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_estado_lead ON public.leads_formularios_optimizada USING btree (estado_lead);


--
-- Name: idx_leads_fb_click_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fb_click_id ON public.leads_formularios_optimizada USING btree (fb_click_id) WHERE (fb_click_id IS NOT NULL);


--
-- Name: idx_leads_fbclid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fbclid ON public.leads_formularios_optimizada USING btree (fbclid) WHERE (fbclid IS NOT NULL);


--
-- Name: idx_leads_fecha_conversion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fecha_conversion ON public.leads_formularios_optimizada USING btree (fecha_conversion) WHERE (fecha_conversion IS NOT NULL);


--
-- Name: idx_leads_fecha_creado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fecha_creado ON public.leads_formularios_optimizada USING btree (fecha_creado);


--
-- Name: idx_leads_fecha_creado_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fecha_creado_timestamp ON public.leads_formularios_optimizada USING btree (fecha_creado_timestamp);


--
-- Name: idx_leads_fuente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fuente ON public.leads_formularios_optimizada USING btree (fuente);


--
-- Name: idx_leads_fuente_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_fuente_fecha ON public.leads_formularios_optimizada USING btree (fuente, fecha_creado DESC);


--
-- Name: idx_leads_identificado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_identificado ON public.leads_formularios_optimizada USING btree (identificado) WHERE (identificado IS NOT NULL);


--
-- Name: idx_leads_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_leads_lead_id ON public.leads_formularios_optimizada USING btree (lead_id);


--
-- Name: idx_leads_mes_ano; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_mes_ano ON public.leads_formularios_optimizada USING btree (ano_creacion, mes_creacion);


--
-- Name: idx_leads_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_nombre ON public.leads_formularios_optimizada USING btree (nombre);


--
-- Name: idx_leads_nombre_campana; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_nombre_campana ON public.leads_formularios_optimizada USING btree (nombre_campana);


--
-- Name: idx_leads_nombre_formulario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_nombre_formulario ON public.leads_formularios_optimizada USING btree (nombre_formulario);


--
-- Name: idx_leads_nombre_normalizado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_nombre_normalizado ON public.leads_formularios_optimizada USING btree (nombre_normalizado);


--
-- Name: idx_leads_pais; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_pais ON public.leads_formularios_optimizada USING btree (pais);


--
-- Name: idx_leads_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_score ON public.leads_formularios_optimizada USING btree (score_lead DESC);


--
-- Name: idx_leads_servicio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_servicio ON public.leads_formularios_optimizada USING btree (servicio);


--
-- Name: idx_leads_servicio_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_servicio_estado ON public.leads_formularios_optimizada USING btree (servicio, estado_lead);


--
-- Name: idx_leads_telefono; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_telefono ON public.leads_formularios_optimizada USING btree (telefono);


--
-- Name: idx_leads_utm_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_utm_campaign ON public.leads_formularios_optimizada USING btree (utm_campaign);


--
-- Name: idx_leads_utm_medium; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_utm_medium ON public.leads_formularios_optimizada USING btree (utm_medium);


--
-- Name: idx_leads_utm_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_utm_source ON public.leads_formularios_optimizada USING btree (utm_source);


--
-- Name: idx_reportes_quejas_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_quejas_client_id ON public.reportes_quejas USING btree (client_id);


--
-- Name: idx_reportes_quejas_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_quejas_estado ON public.reportes_quejas USING btree (estado);


--
-- Name: idx_reportes_quejas_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_quejas_fecha ON public.reportes_quejas USING btree (fecha);


--
-- Name: idx_reportes_quejas_nivel_urgencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reportes_quejas_nivel_urgencia ON public.reportes_quejas USING btree (nivel_urgencia);


--
-- Name: idx_sitio_web_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_sitio_web_unique ON public.prospectos_b2b USING btree (sitio_web) WHERE (sitio_web IS NOT NULL);


--
-- Name: idx_soporte_asignado_a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_asignado_a ON public.soporte_tecnico USING btree (asignado_a);


--
-- Name: idx_soporte_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_categoria ON public.soporte_tecnico USING btree (categoria);


--
-- Name: idx_soporte_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_client_id ON public.soporte_tecnico USING btree (client_id);


--
-- Name: idx_soporte_creado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_creado ON public.soporte_tecnico USING btree (creado);


--
-- Name: idx_soporte_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_email ON public.soporte_tecnico USING btree (email);


--
-- Name: idx_soporte_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_estado ON public.soporte_tecnico USING btree (estado);


--
-- Name: idx_soporte_estado_prioridad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_estado_prioridad ON public.soporte_tecnico USING btree (estado, prioridad);


--
-- Name: idx_soporte_prioridad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_prioridad ON public.soporte_tecnico USING btree (prioridad);


--
-- Name: idx_soporte_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_tags ON public.soporte_tecnico USING gin (tags);


--
-- Name: idx_soporte_ticket_numero; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_soporte_ticket_numero ON public.soporte_tecnico USING btree (ticket_numero);


--
-- Name: idx_sync_log_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sync_log_record ON public.sync_log USING btree (table_name, record_id);


--
-- Name: idx_sync_log_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sync_log_status ON public.sync_log USING btree (status, created_at);


--
-- Name: idx_ubicacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ubicacion ON public.prospectos_b2b USING btree (ubicacion_ciudad, ubicacion_estado);


--
-- Name: tickets_abiertos _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.tickets_abiertos AS
 SELECT st.id,
    st.ticket_numero,
    st.client_id,
    st.estado,
    st.prioridad,
    st.nombre_cliente,
    st.email,
    st.telefono,
    st.empresa,
    st.categoria,
    st.tipo_problema,
    st.asunto,
    st.descripcion,
    st.solucion,
    st.notas_internas,
    st.asignado_a,
    st.tiempo_respuesta_minutos,
    st.tiempo_resolucion_minutos,
    st.primera_respuesta,
    st.resuelto_en,
    st.satisfaccion_cliente,
    st.comentario_satisfaccion,
    st.sistema_operativo,
    st.navegador,
    st.version_producto,
    st.archivos_adjuntos,
    st.tags,
    st.escalado,
    st.escalado_a,
    st.reabierto,
    st.numero_reaperturas,
    st.creado,
    st.actualizado,
    count(sc.id) AS total_comentarios,
    max(sc.creado) AS ultimo_comentario,
    COALESCE(sum(stt.minutos_trabajados), (0)::bigint) AS total_minutos_trabajados
   FROM ((public.soporte_tecnico st
     LEFT JOIN public.soporte_comentarios sc ON ((st.id = sc.ticket_id)))
     LEFT JOIN public.soporte_tiempo_trabajado stt ON ((st.id = stt.ticket_id)))
  WHERE ((st.estado)::text <> ALL ((ARRAY['cerrado'::character varying, 'resuelto'::character varying])::text[]))
  GROUP BY st.id
  ORDER BY
        CASE st.prioridad
            WHEN 'critica'::text THEN 1
            WHEN 'alta'::text THEN 2
            WHEN 'media'::text THEN 3
            WHEN 'baja'::text THEN 4
            ELSE NULL::integer
        END, st.creado;


--
-- Name: tickets_urgentes _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.tickets_urgentes AS
 SELECT st.id,
    st.ticket_numero,
    st.client_id,
    st.estado,
    st.prioridad,
    st.nombre_cliente,
    st.email,
    st.telefono,
    st.empresa,
    st.categoria,
    st.tipo_problema,
    st.asunto,
    st.descripcion,
    st.solucion,
    st.notas_internas,
    st.asignado_a,
    st.tiempo_respuesta_minutos,
    st.tiempo_resolucion_minutos,
    st.primera_respuesta,
    st.resuelto_en,
    st.satisfaccion_cliente,
    st.comentario_satisfaccion,
    st.sistema_operativo,
    st.navegador,
    st.version_producto,
    st.archivos_adjuntos,
    st.tags,
    st.escalado,
    st.escalado_a,
    st.reabierto,
    st.numero_reaperturas,
    st.creado,
    st.actualizado,
    (EXTRACT(epoch FROM (now() - st.creado)) / (3600)::numeric) AS horas_abierto,
    count(sc.id) AS total_comentarios
   FROM (public.soporte_tecnico st
     LEFT JOIN public.soporte_comentarios sc ON ((st.id = sc.ticket_id)))
  WHERE (((st.estado)::text <> ALL ((ARRAY['cerrado'::character varying, 'resuelto'::character varying])::text[])) AND ((st.prioridad)::text = ANY ((ARRAY['critica'::character varying, 'alta'::character varying])::text[])))
  GROUP BY st.id
  ORDER BY
        CASE st.prioridad
            WHEN 'critica'::text THEN 1
            WHEN 'alta'::text THEN 2
            ELSE NULL::integer
        END, st.creado;


--
-- Name: leads_formularios_optimizada notify_leads_changes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_leads_changes AFTER INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.notify_sync_service_pg();


--
-- Name: soporte_tecnico registrar_cambio_estado_soporte_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER registrar_cambio_estado_soporte_trigger BEFORE UPDATE ON public.soporte_tecnico FOR EACH ROW EXECUTE FUNCTION public.registrar_cambio_estado_soporte();


--
-- Name: citas registrar_cambio_estado_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER registrar_cambio_estado_trigger AFTER UPDATE ON public.citas FOR EACH ROW EXECUTE FUNCTION public.registrar_cambio_estado();


--
-- Name: soporte_comentarios registrar_primera_respuesta_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER registrar_primera_respuesta_trigger AFTER INSERT ON public.soporte_comentarios FOR EACH ROW EXECUTE FUNCTION public.registrar_primera_respuesta();


--
-- Name: leads_formularios_optimizada sync_leads_to_chatwoot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_leads_to_chatwoot AFTER INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.notify_sync_service_http();


--
-- Name: leads_formularios_optimizada trigger_actualizar_es_cliente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_actualizar_es_cliente BEFORE INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.actualizar_es_cliente();


--
-- Name: TRIGGER trigger_actualizar_es_cliente ON leads_formularios_optimizada; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_actualizar_es_cliente ON public.leads_formularios_optimizada IS 'Trigger que marca leads como clientes cuando se cierra una venta';


--
-- Name: leads_formularios_optimizada trigger_actualizar_fecha_conversion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_actualizar_fecha_conversion BEFORE INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.actualizar_fecha_conversion();


--
-- Name: citas trigger_asignar_id_cita; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_asignar_id_cita BEFORE INSERT ON public.citas FOR EACH ROW EXECUTE FUNCTION public.asignar_id_cita();


--
-- Name: leads_formularios_optimizada trigger_calcular_score_lead; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_calcular_score_lead BEFORE INSERT OR UPDATE OF email, telefono, servicio, empresa, pais, estado, codigo_postal ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.calcular_score_lead();


--
-- Name: TRIGGER trigger_calcular_score_lead ON leads_formularios_optimizada; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_calcular_score_lead ON public.leads_formularios_optimizada IS 'Trigger que recalcula automáticamente el score_lead cuando se insertan o actualizan 
los campos: email, telefono, servicio, empresa, pais, estado, codigo_postal';


--
-- Name: leads_formularios_optimizada trigger_eliminar_duplicados_whatsapp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_eliminar_duplicados_whatsapp AFTER INSERT ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.eliminar_duplicados_whatsapp();


--
-- Name: leads_formularios_optimizada trigger_generate_client_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_generate_client_id BEFORE INSERT ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.generate_client_id_before_insert();


--
-- Name: leads_formularios_optimizada trigger_historial_estado_lead; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_historial_estado_lead AFTER UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.registrar_cambio_estado_lead();


--
-- Name: prospectos_b2b trigger_insert_lead_from_prospecto; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_insert_lead_from_prospecto AFTER INSERT ON public.prospectos_b2b FOR EACH ROW EXECUTE FUNCTION public.insertar_lead_desde_prospecto();


--
-- Name: citas trigger_levantar_penalizacion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_levantar_penalizacion BEFORE INSERT OR UPDATE ON public.citas FOR EACH ROW EXECUTE FUNCTION public.levantar_penalizacion_asistencia();


--
-- Name: citas trigger_marcar_cita_pasada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_marcar_cita_pasada BEFORE INSERT OR UPDATE ON public.citas FOR EACH ROW EXECUTE FUNCTION public.actualizar_citas_pasadas();


--
-- Name: leads_formularios_optimizada trigger_meta_capi; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_meta_capi AFTER INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.notify_meta_capi();


--
-- Name: prospectos_b2b trigger_normalizar_telefono; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_normalizar_telefono BEFORE INSERT OR UPDATE OF whatsapp_numero, telefono_empresa ON public.prospectos_b2b FOR EACH ROW EXECUTE FUNCTION public.normalizar_telefono();


--
-- Name: leads_formularios_optimizada trigger_notify_n8n_lead; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_n8n_lead AFTER INSERT ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.notify_n8n_lead();


--
-- Name: leads_formularios_optimizada trigger_notify_vercel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_vercel AFTER INSERT OR UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.notify_vercel_webhook();


--
-- Name: leads_formularios_optimizada trigger_reset_enviado_meta; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_reset_enviado_meta BEFORE UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.reset_enviado_meta_on_estado_change();


--
-- Name: prospectos_b2b trigger_update_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_timestamp BEFORE UPDATE ON public.prospectos_b2b FOR EACH ROW EXECUTE FUNCTION public.update_ultima_actualizacion();


--
-- Name: citas update_citas_actualizado; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_citas_actualizado BEFORE UPDATE ON public.citas FOR EACH ROW EXECUTE FUNCTION public.update_actualizado_column();


--
-- Name: leads_formularios_optimizada update_leads_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_leads_updated_at BEFORE UPDATE ON public.leads_formularios_optimizada FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: reportes_quejas update_reportes_quejas_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_reportes_quejas_updated_at BEFORE UPDATE ON public.reportes_quejas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: soporte_tecnico update_soporte_actualizado_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_soporte_actualizado_trigger BEFORE UPDATE ON public.soporte_tecnico FOR EACH ROW EXECUTE FUNCTION public.update_soporte_actualizado();


--
-- Name: citas validar_fecha_cita_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validar_fecha_cita_trigger BEFORE INSERT ON public.citas FOR EACH ROW EXECUTE FUNCTION public.validar_fecha_cita();


--
-- Name: citas_historial_estados citas_historial_estados_cita_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_historial_estados
    ADD CONSTRAINT citas_historial_estados_cita_id_fkey FOREIGN KEY (cita_id) REFERENCES public.citas(id) ON DELETE CASCADE;


--
-- Name: citas_webhook_enviadas citas_webhook_enviadas_cita_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.citas_webhook_enviadas
    ADD CONSTRAINT citas_webhook_enviadas_cita_id_fkey FOREIGN KEY (cita_id) REFERENCES public.citas(id) ON DELETE CASCADE;


--
-- Name: generation_jobs generation_jobs_telegram_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.generation_jobs
    ADD CONSTRAINT generation_jobs_telegram_id_fkey FOREIGN KEY (telegram_id) REFERENCES public.users(telegram_id);


--
-- Name: media_assets media_assets_telegram_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_telegram_id_fkey FOREIGN KEY (telegram_id) REFERENCES public.users(telegram_id);


--
-- Name: publish_jobs publish_jobs_telegram_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_jobs
    ADD CONSTRAINT publish_jobs_telegram_id_fkey FOREIGN KEY (telegram_id) REFERENCES public.users(telegram_id);


--
-- Name: sessions sessions_telegram_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_telegram_id_fkey FOREIGN KEY (telegram_id) REFERENCES public.users(telegram_id) ON DELETE CASCADE;


--
-- Name: soporte_comentarios soporte_comentarios_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_comentarios
    ADD CONSTRAINT soporte_comentarios_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.soporte_tecnico(id) ON DELETE CASCADE;


--
-- Name: soporte_historial_estados soporte_historial_estados_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_historial_estados
    ADD CONSTRAINT soporte_historial_estados_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.soporte_tecnico(id) ON DELETE CASCADE;


--
-- Name: soporte_tiempo_trabajado soporte_tiempo_trabajado_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.soporte_tiempo_trabajado
    ADD CONSTRAINT soporte_tiempo_trabajado_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.soporte_tecnico(id) ON DELETE CASCADE;


--
-- Name: prospectos_b2b Allow full access to service_role; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow full access to service_role" ON public.prospectos_b2b USING ((auth.role() = 'service_role'::text));


--
-- Name: citas Usuarios autenticados pueden actualizar citas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden actualizar citas" ON public.citas FOR UPDATE TO authenticated USING (true);


--
-- Name: soporte_tecnico Usuarios autenticados pueden actualizar tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden actualizar tickets" ON public.soporte_tecnico FOR UPDATE TO authenticated USING (true);


--
-- Name: citas Usuarios autenticados pueden eliminar citas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden eliminar citas" ON public.citas FOR DELETE TO authenticated USING (true);


--
-- Name: soporte_tecnico Usuarios autenticados pueden eliminar tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden eliminar tickets" ON public.soporte_tecnico FOR DELETE TO authenticated USING (true);


--
-- Name: soporte_comentarios Usuarios autenticados pueden gestionar comentarios; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden gestionar comentarios" ON public.soporte_comentarios TO authenticated USING (true) WITH CHECK (true);


--
-- Name: soporte_tiempo_trabajado Usuarios autenticados pueden gestionar tiempo; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden gestionar tiempo" ON public.soporte_tiempo_trabajado TO authenticated USING (true) WITH CHECK (true);


--
-- Name: citas Usuarios autenticados pueden insertar citas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden insertar citas" ON public.citas FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: soporte_tecnico Usuarios autenticados pueden insertar tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden insertar tickets" ON public.soporte_tecnico FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: citas Usuarios autenticados pueden leer citas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden leer citas" ON public.citas FOR SELECT TO authenticated USING (true);


--
-- Name: citas_historial_estados Usuarios autenticados pueden leer historial; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden leer historial" ON public.citas_historial_estados FOR SELECT TO authenticated USING (true);


--
-- Name: soporte_historial_estados Usuarios autenticados pueden leer historial; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden leer historial" ON public.soporte_historial_estados FOR SELECT TO authenticated USING (true);


--
-- Name: soporte_tecnico Usuarios autenticados pueden leer tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados pueden leer tickets" ON public.soporte_tecnico FOR SELECT TO authenticated USING (true);


--
-- Name: reportes_quejas Usuarios pueden actualizar reportes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios pueden actualizar reportes" ON public.reportes_quejas FOR UPDATE TO authenticated USING (true);


--
-- Name: reportes_quejas Usuarios pueden insertar reportes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios pueden insertar reportes" ON public.reportes_quejas FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: reportes_quejas Usuarios pueden leer reportes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios pueden leer reportes" ON public.reportes_quejas FOR SELECT TO authenticated USING (true);


--
-- Name: analisis_social_media_tiktok; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.analisis_social_media_tiktok ENABLE ROW LEVEL SECURITY;

--
-- Name: citas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.citas ENABLE ROW LEVEL SECURITY;

--
-- Name: citas_historial_estados; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.citas_historial_estados ENABLE ROW LEVEL SECURITY;

--
-- Name: contador; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contador ENABLE ROW LEVEL SECURITY;

--
-- Name: generador_contenido_imagenes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.generador_contenido_imagenes ENABLE ROW LEVEL SECURITY;

--
-- Name: generador_de_contenido; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.generador_de_contenido ENABLE ROW LEVEL SECURITY;

--
-- Name: generation_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.generation_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: media_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: publish_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.publish_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: reportes_quejas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reportes_quejas ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: soporte_comentarios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.soporte_comentarios ENABLE ROW LEVEL SECURITY;

--
-- Name: soporte_historial_estados; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.soporte_historial_estados ENABLE ROW LEVEL SECURITY;

--
-- Name: soporte_tecnico; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.soporte_tecnico ENABLE ROW LEVEL SECURITY;

--
-- Name: soporte_tiempo_trabajado; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.soporte_tiempo_trabajado ENABLE ROW LEVEL SECURITY;

--
-- Name: tokens_fbpage&ig; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."tokens_fbpage&ig" ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: videos_SORA_&_imagenes_nanobanana; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."videos_SORA_&_imagenes_nanobanana" ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 0uKk0EfQjNaSqwCA3erfYrL3HehaAKRrojN5uofbmCVSIqMLByPFP6OknWTVSnb

