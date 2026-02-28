# n8n-config

Production-style n8n infrastructure running in **Queue Mode** with PostgreSQL, Redis, Docker Compose, and a FastAPI microservice.

This folder contains the base infrastructure configuration for scalable workflow automation. Additional services (Chatwoot, LightRAG, etc.) will be added progressively, but this README documents the initial core setup.

---

# 🚀 Overview

This setup demonstrates:

* n8n running in **Queue Mode**
* PostgreSQL as the primary database
* Redis for job queue management (Bull)
* Dedicated n8n worker container
* Python FastAPI microservice for data processing
* Docker-based service isolation
* Environment-based configuration
* Resource limits per container

This architecture is designed to simulate a production-ready automation environment.

---

# 🏗 Architecture

```
                    ┌────────────────────┐
                    │   Reverse Proxy    │
                    │ (Optional Traefik) │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │        n8n         │
                    │   (Editor + API)   │
                    └─────────┬──────────┘
                              │ Queue
                    ┌─────────▼──────────┐
                    │      Redis         │
                    │   (Bull Engine)    │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │     n8n Worker     │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │     Python API     │
                    │     (FastAPI)      │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │    PostgreSQL DB   │
                    └────────────────────┘
```

---

# ⚙️ Services

## 1️⃣ PostgreSQL

* Persistent storage for n8n
* Tuned memory configuration
* Data volume mounted for durability

## 2️⃣ Redis

* Handles job queue management
* Configured with memory limits
* LRU eviction policy

## 3️⃣ n8n (Main Instance)

* Workflow editor
* Webhook receiver
* API interface
* Connected to PostgreSQL and Redis

## 4️⃣ n8n Worker

* Processes queued executions
* Scalable horizontally
* Runs independently from the editor

## 5️⃣ Python API (FastAPI)

* Internal microservice
* Performs statistical processing using:

  * NumPy
  * Pandas
* Receives requests from n8n HTTP node

---

# 🔁 Execution Mode

This deployment runs in:

```
EXECUTIONS_MODE=queue
```

Benefits:

* Background execution
* Horizontal scalability
* Fault isolation
* Improved performance under load

---

# 🔐 Environment Variables

Sensitive values are injected through `.env`.

Example (sanitized):

```
N8N_ENCRYPTION_KEY={{YOUR_ENCRYPTION_KEY}}
DB_POSTGRESDB_PASSWORD={{YOUR_POSTGRES_PASSWORD}}
PYTHON_API_KEY={{YOUR_PYTHON_KEY}}
WEBHOOK_URL={{YOUR_WEBHOOK_URL}}
```

No secrets are committed to version control.

---

# 🐳 Running the Stack

From the `n8n-config` directory:

```
docker compose up -d
```

Check logs:

```
docker compose logs -f
```

Stop services:

```
docker compose down
```

---

# 🧪 Example Use Case: Lead Scoring API

Workflow:

1. Webhook receives lead data
2. n8n sends data to Python API
3. FastAPI processes statistics (mean, std deviation)
4. Lead score and classification returned

Example response:

```
{
  "lead_score": 79,
  "classification": "Hot",
  "analytics": {
    "mean_input": 78.33,
    "std_dev_input": 13.12
  }
}
```

---

# 📈 Why This Matters

This setup demonstrates:

* Containerized microservices
* Queue-based background processing
* Service separation
* Environment-based configuration
* Production-style deployment patterns

---

# 🌐 VPS Production Deployment (Traefik + External Network)

In the VPS environment, this stack runs behind **Traefik** as a reverse proxy with automatic TLS certificates.

Key differences from local setup:

* Uses an **external Docker network** (`n8n_evoapi`)
* Services are attached to the shared network
* Traefik handles:

  * HTTPS termination
  * Automatic Let's Encrypt certificates
  * Domain-based routing
* n8n is exposed via labels instead of direct port binding

Example production characteristics:

* No direct `5678:5678` port exposure
* Access controlled via domain rules
* TLS enforced
* Security headers configured

This demonstrates:

* Reverse proxy configuration
* Multi-service Docker networking
* Domain-based routing
* TLS automation
* Production-style container orchestration

---

# 🛠 Future Additions

Planned integrations:

* Chatwoot
* LightRAG
* AI-based agents
* External CRM integrations
* Monitoring & observability

---

# 🧠 Production Notes

For real production environments:

* Use a reverse proxy (Traefik or Nginx)
* Enable HTTPS certificates
* Remove mounted source volumes
* Add health checks
* Implement backup strategies
* Use secrets manager instead of plain .env

---

# 📄 License

MIT

---

Built as part of an automation engineering portfolio project.

