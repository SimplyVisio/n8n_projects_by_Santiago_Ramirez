"""
Prometheus Metrics Registry — Cardinality-Safe.

All label values are BOUNDED to fixed enumerations.
No dynamic or LLM-generated strings are ever used as label values.
This is critical: unbounded label cardinality will destroy Prometheus.

CARDINALITY CONTRACT:
  tool_name   → bounded by ALLOWED_TOOL_NAMES (8 values max)
  error_type  → bounded by ALLOWED_ERROR_TYPES (4 values max)
  status      → bounded by ALLOWED_STATUSES (5 values max)
  operation   → bounded by ALLOWED_DB_OPS / ALLOWED_REDIS_OPS (small sets)

If an unknown value arrives, it is normalized to "unknown" — never passed raw.
"""

from prometheus_client import Counter, Gauge, Histogram

# ── Namespace ──────────────────────────────────────────────────────────────────
NS = "incident_agent"
LATENCY_BUCKETS = (0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 20.0, 30.0)

# ── Cardinality-safe label allow-lists ────────────────────────────────────────
# These are the ONLY values that will ever appear in Prometheus label dimensions.
# Anything outside this set gets normalized to "unknown".

ALLOWED_TOOL_NAMES = frozenset({
    "generate_fingerprint",
    "check_redis_memory",
    "query_incident_stats_sql",
    "cache_in_redis",
    "store_incident_postgres",
    "send_telegram_notification",
    "update_incident_stats",
    "finalize_incident_transactional",
    "finalize_incident_decision",
    "unknown",            # catch-all for any future unregistered tool
})

ALLOWED_ERROR_TYPES = frozenset({
    "timeout",            # openai.APITimeoutError
    "api_error",          # openai.APIError
    "circuit_open",       # CircuitBreakerOpen
    "unknown",
})

ALLOWED_STATUSES = frozenset({
    "success",
    "error",
    "circuit_open",
    "max_iterations_reached",
    "incomplete",
    "unknown",
})

ALLOWED_DB_OPS = frozenset({
    "store_incident",
    "update_stats",
    "finalize_transactional",
    "unknown",
})

ALLOWED_REDIS_OPS = frozenset({
    "get",
    "set",
    "unknown",
})


def _safe(value: str, allowed: frozenset) -> str:
    """Normalize a label value against its allow-list. Never lets raw strings through."""
    return value if value in allowed else "unknown"


# ── API Layer ──────────────────────────────────────────────────────────────────
INCIDENTS_RECEIVED = Counter(
    f"{NS}_incidents_received_total",
    "Total incidents received from n8n"
)
INCIDENTS_ENQUEUED = Counter(
    f"{NS}_incidents_enqueued_total",
    "Total incidents successfully enqueued to Redis"
)
ENQUEUE_ERRORS = Counter(
    f"{NS}_enqueue_errors_total",
    "Total enqueue failures"
)

# ── Agent Reasoning ────────────────────────────────────────────────────────────
AGENT_ITERATIONS = Histogram(
    f"{NS}_agent_iterations_total",
    "Distribution of reasoning loop iteration count per execution",
    buckets=(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
)
AGENT_PROCESSING_SECONDS = Histogram(
    f"{NS}_agent_processing_seconds",
    "End-to-end agent processing duration in seconds",
    buckets=LATENCY_BUCKETS
)
AGENT_TOOL_CALLS = Counter(
    f"{NS}_agent_tool_calls_total",
    "Tool invocations by tool name (bounded label cardinality)",
    labelnames=["tool_name"]
)
AGENT_OUTCOMES = Counter(
    f"{NS}_agent_outcomes_total",
    "Agent final status distribution (bounded label set)",
    labelnames=["status"]
)

# ── OpenAI ─────────────────────────────────────────────────────────────────────
OPENAI_CALL_DURATION = Histogram(
    f"{NS}_openai_call_duration_seconds",
    "OpenAI API call latency per attempt",
    buckets=LATENCY_BUCKETS
)
OPENAI_ERRORS = Counter(
    f"{NS}_openai_errors_total",
    "OpenAI errors by fixed error_type label (bounded cardinality)",
    labelnames=["error_type"]
)
OPENAI_RETRIES = Counter(
    f"{NS}_openai_retries_total",
    "Number of exponential-backoff retry attempts triggered"
)

# ── Circuit Breaker ────────────────────────────────────────────────────────────
CIRCUIT_BREAKER_STATE = Gauge(
    f"{NS}_circuit_breaker_state",
    "Current state of the circuit breaker (0=CLOSED 1=HALF_OPEN 2=OPEN)",
    labelnames=["breaker_name"]
)

# ── Redis ──────────────────────────────────────────────────────────────────────
REDIS_CACHE_HITS = Counter(
    f"{NS}_redis_cache_hits_total",
    "Redis hot-memory fingerprint cache hits"
)
REDIS_CACHE_MISSES = Counter(
    f"{NS}_redis_cache_misses_total",
    "Redis hot-memory fingerprint cache misses"
)
REDIS_OPERATION_SECONDS = Histogram(
    f"{NS}_redis_operation_seconds",
    "Redis operation latency — label values: get|set",
    labelnames=["operation"],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.5)
)

# ── Database ───────────────────────────────────────────────────────────────────
DB_TRANSACTION_SECONDS = Histogram(
    f"{NS}_db_transaction_duration_seconds",
    "Postgres write transaction duration — label values: store_incident|update_stats|finalize_transactional",
    labelnames=["operation"],
    buckets=LATENCY_BUCKETS
)
DB_ERRORS = Counter(
    f"{NS}_db_errors_total",
    "Database errors by operation type (bounded label set)",
    labelnames=["operation"]
)


# ── Safe recording helpers ─────────────────────────────────────────────────────
def record_tool_call(tool_name: str) -> None:
    """Record a tool invocation — normalizes label against allow-list."""
    AGENT_TOOL_CALLS.labels(tool_name=_safe(tool_name, ALLOWED_TOOL_NAMES)).inc()


def record_agent_outcome(status: str) -> None:
    """Record agent final outcome — normalizes label against allow-list."""
    AGENT_OUTCOMES.labels(status=_safe(status, ALLOWED_STATUSES)).inc()


def record_openai_error(error_type: str) -> None:
    """Record OpenAI error — normalizes label against allow-list."""
    OPENAI_ERRORS.labels(error_type=_safe(error_type, ALLOWED_ERROR_TYPES)).inc()


def record_redis_op(operation: str, latency: float) -> None:
    """Record Redis latency — normalizes label against allow-list."""
    REDIS_OPERATION_SECONDS.labels(
        operation=_safe(operation, ALLOWED_REDIS_OPS)
    ).observe(latency)


def record_db_op(operation: str, latency: float) -> None:
    """Record DB transaction latency — normalizes label against allow-list."""
    DB_TRANSACTION_SECONDS.labels(
        operation=_safe(operation, ALLOWED_DB_OPS)
    ).observe(latency)


def record_db_error(operation: str) -> None:
    """Record DB error — normalizes label against allow-list."""
    DB_ERRORS.labels(operation=_safe(operation, ALLOWED_DB_OPS)).inc()
