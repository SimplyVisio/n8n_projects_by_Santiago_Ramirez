import hashlib
import json
import logging
import httpx
from sqlalchemy import select, update, insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from datetime import datetime
from app.db.models import Incident, IncidentStat, AgentReasoningLog
from app.db.session import AsyncSessionLocal
from app.services.redis_service import RedisService, redis_service
from app.core.config import settings

logger = logging.getLogger(__name__)

async def generate_fingerprint(stack_trace: str) -> str:
    """Generate SHA256 fingerprint from stack trace."""
    return hashlib.sha256(stack_trace.strip().encode()).hexdigest()

async def check_redis_memory(fingerprint: str, refresh: bool = True) -> str:
    """Retrieve cached context and refresh TTL (Sliding Window)."""
    context = await redis_service.get_memory(fingerprint)
    if context and refresh:
        # Sliding window: refresh TTL on every hit
        await redis_service.set_memory(fingerprint, context)
    return context if context else "null"

async def query_incident_stats_sql(fingerprint: str = None, error_message: str = None) -> str:
    """Query historical incident stats from Postgres."""
    async with AsyncSessionLocal() as db:
        query = select(IncidentStat)
        if fingerprint:
            query = query.where(IncidentStat.fingerprint == fingerprint)
        elif error_message:
            query = query.where(IncidentStat.summary.ilike(f"%{error_message}%"))
        
        query = query.limit(10)
        result = await db.execute(query)
        stats = result.scalars().all()
        
        if not stats:
            return "No historical data found."
        
        output = []
        for s in stats:
            output.append({
                "fingerprint": s.fingerprint,
                "occurrence_count": s.occurrence_count,
                "last_seen": s.last_seen.isoformat(),
                "summary": s.summary
            })
        return json.dumps(output)

async def cache_in_redis(fingerprint: str, context: str):
    """Cache context in Redis with configured TTL."""
    await redis_service.set_memory(fingerprint, context)
    return "Cached successfully."

async def store_incident_postgres(
    fingerprint: str,
    workflow_id: str,
    error_message: str,
    root_cause: str,
    suggested_fix: str,
    node_name: str = None,
    severity: str = "medium",
    priority: str = "medium",
    stack_trace: str = None
) -> str:
    """Store the finalized incident in Postgres with DB-level idempotency."""
    async with AsyncSessionLocal() as db:
        async with db.begin():
            stmt = pg_insert(Incident).values(
                fingerprint=fingerprint,
                workflow_id=workflow_id,
                error_message=error_message,
                root_cause=root_cause,
                suggested_fix=suggested_fix,
                node_name=node_name,
                severity=severity,
                priority=priority,
                stack_trace=stack_trace,
                status='resolved'
            ).on_conflict_do_nothing(
                # References the unique index: uniq_fingerprint_time_window
                # Postgres will use it automatically for conflict detection
                constraint='uniq_fingerprint_time_window'
            )
            try:
                await db.execute(stmt)
                return "Incident processed (stored or skipped by idempotency)"
            except Exception as e:
                logger.error(f"DB Error in store_incident: {e}")
                return f"Error: {str(e)}"

async def send_telegram_notification(
    workflow_id: str,
    severity: str,
    priority: str,
    root_cause: str,
    suggested_fix: str,
    occurrence_count: int,
    node_name: str = None,   # optional — LLM may omit it; defaults to 'N/A' in message
    source: str = "DB"
):
    """Send a production-grade Telegram notification."""
    message = (
        f"🚨 *DevOps Incident Alert*\n\n"
        f"📌 *Workflow:* {workflow_id}\n"
        f"🧩 *Node:* {node_name or 'N/A'}\n"
        f"🔥 *Severity:* {severity.upper()}\n"
        f"⚖️ *Priority:* {priority.upper()}\n\n"
        f"🔍 *Root Cause:* {root_cause}\n"
        f"💡 *Suggested Fix:* {suggested_fix}\n\n"
        f"📈 *Occurrences:* {occurrence_count}\n"
        f"ℹ️ *Source:* {source}\n"
    )
    
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": settings.TELEGRAM_CHAT_ID,
        "text": message,
        "parse_mode": "Markdown"
    }
    
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            return "Notification sent."
        except Exception as e:
            logger.error(f"Failed to send Telegram: {e}")
            return f"Error sending notification: {str(e)}"

async def update_incident_stats(fingerprint: str, summary: str):
    """Increment occurrence count safely with atomic UPSERT."""
    async with AsyncSessionLocal() as db:
        stmt = pg_insert(IncidentStat).values(
            fingerprint=fingerprint,
            occurrence_count=1,
            last_seen=datetime.utcnow(),
            summary=summary[:200]
        ).on_conflict_do_update(
            index_elements=['fingerprint'],
            set_={
                'occurrence_count': IncidentStat.occurrence_count + 1,
                'last_seen': datetime.utcnow()
            }
        )
        await db.execute(stmt)
        await db.commit()
    return "Stats updated."

async def finalize_incident_transactional(
    fingerprint: str,
    workflow_id: str,
    error_message: str,
    root_cause: str,
    suggested_fix: str,
    node_name: str = None,
    severity: str = "medium",
    priority: str = "medium",
    occurrence_count: int = 1
):
    """
    ATOMIC TRANSACTION: Store incident and Update stats in one go.
    Ensures data consistency across tables.
    """
    async with AsyncSessionLocal() as db:
        async with db.begin():
            try:
                # 1. Update stats
                stat_stmt = pg_insert(IncidentStat).values(
                    fingerprint=fingerprint,
                    occurrence_count=1,
                    last_seen=datetime.utcnow(),
                    summary=error_message[:200]
                ).on_conflict_do_update(
                    index_elements=['fingerprint'],
                    set_={
                        'occurrence_count': IncidentStat.occurrence_count + 1,
                        'last_seen': datetime.utcnow()
                    }
                )
                await db.execute(stat_stmt)

                # 2. Store incident (DB handles idempotency via unique index)
                inc_stmt = pg_insert(Incident).values(
                    fingerprint=fingerprint,
                    workflow_id=workflow_id,
                    error_message=error_message,
                    root_cause=root_cause,
                    suggested_fix=suggested_fix,
                    node_name=node_name,
                    severity=severity,
                    priority=priority,
                    status='resolved'
                ).on_conflict_do_nothing(
                    constraint='uniq_fingerprint_time_window'
                )
                await db.execute(inc_stmt)
                
                return "Incident finalized atomically in DB."
            except Exception as e:
                logger.error(f"Atomic transaction failed: {e}")
                raise
