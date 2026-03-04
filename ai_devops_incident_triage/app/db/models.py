"""
SQLAlchemy ORM Models — Reconciled with database_schema.sql v3.0

IMPORTANT: DateTime columns use timezone=True to match TIMESTAMPTZ in Postgres.
Without this, SQLAlchemy stores naive UTC datetimes that break on timezone-aware comparisons.

Tables:
  incidents             — Raw events + AI analysis results
  incident_stats        — Aggregated occurrence counts per fingerprint
  agent_reasoning_logs  — Per-iteration reasoning trace for debugging
"""

from sqlalchemy import (
    Column, String, Text, Integer, Index,
    CHAR, func
)
from sqlalchemy import DateTime as SaDateTime
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
import uuid

from app.db.base import Base


def _utcnow():
    """Return a timezone-aware UTC datetime (avoids deprecation warning)."""
    return datetime.now(timezone.utc)


# =============================================================================
# Table: incidents
# =============================================================================
class Incident(Base):
    __tablename__ = "incidents"
    __table_args__ = (
        # Mirror of the DB-level unique index for idempotency.
        # SQLAlchemy doesn't express function-based indexes natively here;
        # the real constraint lives in database_schema.sql as:
        #   CREATE UNIQUE INDEX uniq_fingerprint_time_window
        #   ON incidents (fingerprint, date_trunc('minute', created_at));
        # This comment documents the constraint so maintainers know it exists.
        {"comment": "DB-level idempotency via uniq_fingerprint_time_window index"},
    )

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    fingerprint   = Column(CHAR(64),       nullable=False, index=True)
    workflow_id   = Column(String(255),    nullable=False, index=True)
    node_name     = Column(String(255))
    severity      = Column(String(50))
    priority      = Column(String(50))
    error_message = Column(Text,           nullable=False)
    stack_trace   = Column(Text)
    root_cause    = Column(Text)
    suggested_fix = Column(Text)
    status        = Column(String(50),     nullable=False, default='unresolved')
    created_at    = Column(SaDateTime(timezone=True), nullable=False, default=_utcnow, index=True)
    updated_at    = Column(SaDateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow)


# =============================================================================
# Table: incident_stats
# =============================================================================
class IncidentStat(Base):
    __tablename__ = "incident_stats"

    fingerprint      = Column(CHAR(64),                  primary_key=True)
    occurrence_count = Column(Integer,                   nullable=False, default=1)
    first_seen       = Column(SaDateTime(timezone=True), nullable=False, default=_utcnow)
    last_seen        = Column(SaDateTime(timezone=True), nullable=False, default=_utcnow, index=True)
    summary          = Column(Text)


# =============================================================================
# Table: agent_reasoning_logs
# =============================================================================
class AgentReasoningLog(Base):
    __tablename__ = "agent_reasoning_logs"

    id               = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    incident_id      = Column(
        UUID(as_uuid=True),
        # ForeignKey as string to avoid circular import risk
        nullable=True,   # nullable: log can exist before incident is committed
    )
    iteration_number = Column(Integer,                   nullable=False)
    thought          = Column(Text,                      nullable=False)
    tool_name        = Column(String(255))
    tool_input       = Column(JSONB)   # JSONB enables @>, ?, and GIN indexing
    tool_output      = Column(JSONB)
    created_at       = Column(SaDateTime(timezone=True), nullable=False, default=_utcnow)
