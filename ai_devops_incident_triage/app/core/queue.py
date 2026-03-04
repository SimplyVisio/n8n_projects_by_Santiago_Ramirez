import logging
from redis import Redis
from rq import Queue
from app.core.config import settings

logger = logging.getLogger(__name__)

# Synchronous connection for RQ pushing
redis_conn = Redis.from_url(settings.REDIS_URL or 'redis://localhost:6379/0')
incident_queue = Queue('incident_triage', connection=redis_conn)

def push_incident_to_queue(incident_data: dict):
    """Push raw incident data from FastAPI to Redis queue."""
    logger.info("Enqueuing incident task.")
    # Use string-based enqueuing to avoid importing the heavy worker/agent logic in the API process.
    task = incident_queue.enqueue("app.worker.analyze_incident_task", incident_data)
    return task.id
