from app.agent.tools import (
    generate_fingerprint,
    check_redis_memory,
    query_incident_stats_sql,
    cache_in_redis,
    store_incident_postgres,
    send_telegram_notification,
    update_incident_stats,
    finalize_incident_transactional,
)

TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "generate_fingerprint",
            "description": "Generate a unique SHA256 hash from a stack trace or error message.",
            "parameters": {
                "type": "object",
                "properties": {
                    "stack_trace": {"type": "string", "description": "The raw stack trace or error message content."}
                },
                "required": ["stack_trace"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "check_redis_memory",
            "description": "Check if this incident fingerprint already exists in hot memory (Redis).",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string", "description": "The unique SHA256 incident fingerprint."}
                },
                "required": ["fingerprint"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "query_incident_stats_sql",
            "description": "Query cold storage (Postgres) for historical incident data by fingerprint or error message.",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string", "description": "Search by SHA256 fingerprint."},
                    "error_message": {"type": "string", "description": "Fuzzy search by error message summary."}
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "cache_in_redis",
            "description": "Cache incident analysis in hot memory (Redis).",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string", "description": "The unique SHA256 incident fingerprint."},
                    "context": {"type": "string", "description": "Structured analysis context to store."}
                },
                "required": ["fingerprint", "context"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "store_incident_postgres",
            "description": "Persistently store the final structured incident record in Postgres cold storage.",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string"},
                    "workflow_id": {"type": "string"},
                    "error_message": {"type": "string"},
                    "root_cause": {"type": "string"},
                    "suggested_fix": {"type": "string"},
                    "node_name": {"type": "string"},
                    "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
                    "priority": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
                    "stack_trace": {"type": "string"}
                },
                "required": ["fingerprint", "workflow_id", "error_message", "root_cause", "suggested_fix"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "send_telegram_notification",
            "description": "Send a structural alert message to the DevOps team via Telegram.",
            "parameters": {
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "string"},
                    "node_name": {"type": "string"},
                    "severity": {"type": "string"},
                    "priority": {"type": "string"},
                    "root_cause": {"type": "string"},
                    "suggested_fix": {"type": "string"},
                    "occurrence_count": {"type": "integer"},
                    "source": {"type": "string", "description": "Memory source: 'Redis' or 'Postgres'."}
                },
                "required": [
                    "workflow_id",
                    "node_name",
                    "severity",
                    "priority",
                    "root_cause",
                    "suggested_fix",
                    "occurrence_count"
                ]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "update_incident_stats",
            "description": "Increment incident occurrence count in Postgres.",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string"},
                    "summary": {"type": "string"}
                },
                "required": ["fingerprint", "summary"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "finalize_incident_transactional",
            "description": "Store the incident and update statistics in a single atomic database transaction.",
            "parameters": {
                "type": "object",
                "properties": {
                    "fingerprint": {"type": "string"},
                    "workflow_id": {"type": "string"},
                    "error_message": {"type": "string"},
                    "root_cause": {"type": "string"},
                    "suggested_fix": {"type": "string"},
                    "node_name": {"type": "string"},
                    "severity": {"type": "string"},
                    "priority": {"type": "string"}
                },
                "required": ["fingerprint", "workflow_id", "error_message", "root_cause", "suggested_fix"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "finalize_incident_decision",
            "description": "Mark the investigation as finished and return the final analysis.",
            "parameters": {
                "type": "object",
                "properties": {
                    "decision": {
                        "type": "object",
                        "properties": {
                            "incident_id": {"type": "string"},
                            "fingerprint": {"type": "string"},
                            "status": {"type": "string"},
                            "priority": {"type": "string"},
                            "summary": {"type": "string"}
                        }
                    }
                },
                "required": ["decision"]
            }
        }
    }
]

# Map names to actual callables
TOOL_MAPPING = {
    "generate_fingerprint": generate_fingerprint,
    "check_redis_memory": check_redis_memory,
    "query_incident_stats_sql": query_incident_stats_sql,
    "cache_in_redis": cache_in_redis,
    "store_incident_postgres": store_incident_postgres,
    "send_telegram_notification": send_telegram_notification,
    "update_incident_stats": update_incident_stats,
    "finalize_incident_transactional": finalize_incident_transactional
}
