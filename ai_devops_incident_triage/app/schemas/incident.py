from pydantic import BaseModel, HttpUrl
from typing import Optional, Dict, Any

class IncidentPayload(BaseModel):
    workflow_id: str
    error_message: str
    stack_trace: Optional[str] = None
    node_name: Optional[str] = None
    severity: Optional[str] = "medium"
    execution_url: Optional[str] = None
    additional_metadata: Optional[Dict[str, Any]] = None
