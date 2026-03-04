import logging
from app.agent.reasoning_loop import ReasoningLoop
from typing import Dict, Any

logger = logging.getLogger(__name__)

class AgentCore:
    def __init__(self, incident_data: Dict[str, Any]):
        self.incident_data = incident_data
        self.reasoning_loop = ReasoningLoop(incident_data)
    
    async def analyze(self):
        """Entry point for incident analysis."""
        logger.info("Initializing Agent Analysis.")
        decision = await self.reasoning_loop.execute()
        return decision
