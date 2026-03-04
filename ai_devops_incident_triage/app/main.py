import time
import logging

import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from app.core.config import settings
from app.core.queue import push_incident_to_queue
from app.core.metrics import (
    INCIDENTS_RECEIVED,
    INCIDENTS_ENQUEUED,
    ENQUEUE_ERRORS,
)
from app.db.session import engine
from app.schemas.incident import IncidentPayload

import sqlalchemy

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
)
logger = logging.getLogger(__name__)

# ------------------------------------------------------------------ #
app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.API_VERSION,
    description=(
        "Async Agentic AI DevOps Incident Intelligence System. "
        "Powered by OpenAI function-calling, Redis-backed circuit breaker, "
        "and PostgreSQL cold storage."
    )
)

_UPTIME_START = time.time()


# ------------------------------------------------------------------ #
#   Observability                                                      #
# ------------------------------------------------------------------ #

@app.get("/health", tags=["Observability"], summary="Liveness probe")
async def health():
    """Always 200 if the process is alive."""
    return {"status": "healthy", "service": settings.PROJECT_NAME}


@app.get("/ready", tags=["Observability"], summary="Readiness probe")
async def ready():
    """
    503 if Redis or Postgres are unreachable.
    Used by Kubernetes/Docker healthchecks before sending traffic.
    """
    errors: dict = {}

    try:
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        await r.ping()
        await r.aclose()
    except Exception as e:
        errors["redis"] = str(e)

    try:
        async with engine.connect() as conn:
            await conn.execute(sqlalchemy.text("SELECT 1"))
    except Exception as e:
        errors["postgres"] = str(e)

    if errors:
        return JSONResponse(
            status_code=503,
            content={"status": "unavailable", "errors": errors}
        )
    return {"status": "ready", "dependencies": {"redis": "ok", "postgres": "ok"}}


@app.get(
    "/metrics",
    tags=["Observability"],
    summary="Prometheus-compatible metrics scrape endpoint"
)
async def prometheus_metrics():
    """
    Returns metrics in Prometheus text exposition format.
    Point your Prometheus scraper here:
      - job: incident_agent
        static_configs:
          - targets: ['api:8000']
    """
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


# ------------------------------------------------------------------ #
#   Incident ingestion                                                 #
# ------------------------------------------------------------------ #

@app.post(
    "/incident",
    status_code=202,
    tags=["Incidents"],
    summary="Receive a validated incident from n8n"
)
async def report_incident(request: Request, payload: IncidentPayload):
    """
    Validates the incoming incident payload and enqueues it for async AI triage.
    Returns 202 immediately — the agent reasoning happens in the background.
    """
    request_id = hex(id(request))
    logger.info(
        f"[API] Incident received | req={request_id} | "
        f"workflow={payload.workflow_id} | node={payload.node_name} | "
        f"severity={payload.severity}"
    )
    INCIDENTS_RECEIVED.inc()

    try:
        job_id = push_incident_to_queue(payload.model_dump())
        INCIDENTS_ENQUEUED.inc()
        logger.info(f"[API] Enqueued | req={request_id} | job={job_id}")
        return {
            "status": "accepted",
            "message": "Incident validated and enqueued for AI triage.",
            "job_id": job_id,
            "request_id": request_id
        }
    except Exception as e:
        ENQUEUE_ERRORS.inc()
        logger.exception(f"[API] Enqueue failed | req={request_id} | error={e}")
        raise HTTPException(status_code=500, detail=f"Failed to enqueue incident: {str(e)}")


# ------------------------------------------------------------------ #
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
