# Agentic AI DevOps Incident Intelligence System

An production-grade, asynchronous, agentic AI system for triaging DevOps incidents received from n8n.

---

## 🚀 Project Overview

The system is designed to act as an intelligent agent rather than a simple microservice. When a raw JSON error event is received from an orchestration platform like n8n, the system processes it asynchronously, leveraging a single-agent system with:

- **Iterative Tool-Based Reasoning**: The agent dynamically selects tools for data retrieval and analysis.
- **Hierarchical Memory**: Uses Redis for fast "Hot" memory (cached fingerprints) and PostgreSQL (Supabase) for durable "Cold" memory.
- **Asynchronous Processing**: Immediate `202 Accepted` response, offloading heavy agentic reasoning to a Redis-backed queue.

---

## 🏗 Why Agentic Architecture?

Traditional error handlers use rigid IF/ELSE logic. An **Agentic AI** approach allows:
- **Flexibility**: The agent can choose to investigate historical data only if the fingerprint is new.
- **Iterative refinement**: The model can perform multiple "Chain of Thought" steps to reach a decision.
- **Tool-based extension**: Easily add new diagnostic tools (e.g., query logs, check cloud status) without changing core logic.

---

## 🔥 Data Flow Diagram

```ascii
[n8n / Raw Error] ---POST /incident---> [FastAPI Layer] ---[202 Accepted]
                                            |
                                      (Enqueue Job)
                                            |
[Redis Hot Memory] <---[TTL Lookup]------- [RQ Worker] <---[Agent Core Loop]
                                            |                    ^
                                      (Tool Execution)           | (Reasoning Iterations)
                                            |                    v
[Postgres Cold Storage] <---[SQL Tool]----- [Agent Action] -----[LLM Decision]
                                            |
                                     (Final Decision)
                                            |
[Telegram Alert] <--------------------------+
```

---

## 🛠 Setup & Installation

Detailed steps are provided in `installation_steps.txt`.

### Prerequisites
1.  **OpenAI API Key** (GPT-4o recommended).
2.  **Redis** (Local or Cloud).
3.  **Supabase** (PostgreSQL instance).
4.  **Telegram Bot Token & Chat ID**.

---

## ⚡ Redis Hot Memory vs Postgres Cold Memory
- **Redis (Hot)**: Stores Shaw-256 fingerprints of errors seen in the last 7 days. If a repeat error occurs, the agent retrieves the previous analysis from Redis in milliseconds.
- **Postgres (Cold)**: Durable storage for every incident, occurrence statistics, and detailed agent reasoning steps for auditing.

---

## 🔗 n8n Integration
Configure an HTTP Request node in n8n:
- **Method**: POST
- **URL**: `http://<your-api-url>:8000/incident`
- **Body Content**: Raw JSON error object from your workflow.

---

## 📜 Example `CURL` Request

```bash
curl -X POST "http://localhost:8000/incident" \
     -H "Content-Type: application/json" \
     -d '{
           "workflow_id": "prod_checkout_gateway",
           "node_name": "Stripe Node",
           "error_message": "Invalid API Key provided",
           "stack_trace": "Error: Unauthorized at ...",
           "severity": "high"
         }'
```

---

## 🔮 Future Improvements
- **Metrics v2**: Integration with Prometheus/Grafana to track successful triage rates.
- **Embeddings v3**: Implement RAG for better semantic search of similar historical incidents.

---

## ⚖️ License
MIT License recommendation.
Designed by Antigravity (Google DeepMind).
