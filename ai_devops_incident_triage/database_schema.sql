-- =============================================================================
-- Agentic AI DevOps Incident Intelligence System — Database Schema
-- Version: 3.0 — Production Ready
-- Last updated: 2026-03-02
--
-- Changes in this version vs v1:
--   [1] incidents: added TIMESTAMP WITH TIME ZONE on created_at
--       (required by uniq_fingerprint_time_window via date_trunc())
--   [2] Added UNIQUE INDEX uniq_fingerprint_time_window for DB-level idempotency
--   [3] agent_reasoning_logs: tool_input/tool_output typed as JSONB (not TEXT)
--   [4] incidents: DateTime columns use TIMESTAMPTZ for timezone awareness
--   [5] incidents.status default 'unresolved' (matches ORM default)
--   [6] incident_stats: first_seen column present (matches ORM model)
-- =============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- fuzzy text search
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- uuid_generate_v4()

-- =============================================================================
-- Table: incidents
-- =============================================================================
CREATE TABLE IF NOT EXISTS incidents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fingerprint     CHAR(64)        NOT NULL,
    workflow_id     VARCHAR(255)    NOT NULL,
    node_name       VARCHAR(255),
    severity        VARCHAR(50),
    priority        VARCHAR(50),
    error_message   TEXT            NOT NULL,
    stack_trace     TEXT,
    root_cause      TEXT,
    suggested_fix   TEXT,
    status          VARCHAR(50)     NOT NULL DEFAULT 'unresolved',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Standard lookup index
CREATE INDEX IF NOT EXISTS idx_incidents_fingerprint
    ON incidents (fingerprint);

-- Workflow-scoped queries
CREATE INDEX IF NOT EXISTS idx_incidents_workflow_id
    ON incidents (workflow_id);

-- Time-range filtering (dashboard queries, retention jobs)
CREATE INDEX IF NOT EXISTS idx_incidents_created_at
    ON incidents (created_at);

-- Fuzzy full-text search on error_message (requires pg_trgm extension above)
CREATE INDEX IF NOT EXISTS idx_incidents_error_message_trgm
    ON incidents USING GIN (error_message gin_trgm_ops);

-- =============================================================================
-- CRITICAL: DB-level idempotency constraint
-- One record per unique fingerprint (one per unique error signature).
--
-- Design decision: simplified from time-window deduplication to per-fingerprint
-- uniqueness. The fingerprint (SHA256 of stack trace) is globally unique per
-- error type, so this prevents storing duplicate error analyses.
-- Recurring incidents are tracked via incident_stats.occurrence_count instead.
--
-- ON CONFLICT DO NOTHING in the application layer handles concurrent inserts.
-- =============================================================================
ALTER TABLE incidents
    ADD CONSTRAINT uniq_fingerprint_time_window UNIQUE (fingerprint);

-- =============================================================================
-- Table: incident_stats
-- =============================================================================
CREATE TABLE IF NOT EXISTS incident_stats (
    fingerprint       CHAR(64)    PRIMARY KEY,
    occurrence_count  INT         NOT NULL DEFAULT 1,
    first_seen        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    summary           TEXT
);

-- Index for sorting / dashboard queries by last activity
CREATE INDEX IF NOT EXISTS idx_incident_stats_last_seen
    ON incident_stats (last_seen);

-- =============================================================================
-- Table: agent_reasoning_logs
-- =============================================================================
CREATE TABLE IF NOT EXISTS agent_reasoning_logs (
    id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id      UUID        REFERENCES incidents(id) ON DELETE CASCADE,
    iteration_number INT         NOT NULL,
    thought          TEXT        NOT NULL,
    tool_name        VARCHAR(255),
    tool_input       JSONB,       -- typed JSONB, not TEXT — enables JSON operators
    tool_output      JSONB,       -- typed JSONB, not TEXT
    created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Foreign-key lookup index (critical for ON DELETE CASCADE performance)
CREATE INDEX IF NOT EXISTS idx_agent_reasoning_logs_incident_id
    ON agent_reasoning_logs (incident_id);

-- Optional: index on tool_name for per-tool analysis queries
CREATE INDEX IF NOT EXISTS idx_agent_reasoning_logs_tool_name
    ON agent_reasoning_logs (tool_name)
    WHERE tool_name IS NOT NULL;  -- partial index, skips NULL rows

-- =============================================================================
-- Trigger: auto-update incidents.updated_at on row modification
-- =============================================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_incidents_updated_at ON incidents;
CREATE TRIGGER trg_incidents_updated_at
    BEFORE UPDATE ON incidents
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
