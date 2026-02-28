# PostgreSQL AI-Driven Appointment and Webhook Automation System

## Project Purpose
This repository provides a production-ready PostgreSQL architecture for AI-assisted appointment scheduling, lead scoring, and automated webhook dispatching. By relying on PostgreSQL as a centralized, event-driven engine, it handles customer relationship management (CRM) tasks like orchestrating events, tracking appointment statuses, and integrating directly with external AI agents and automation workflows.

## Repository Structure
The configuration is split into two SQL files. This separates the core relational logic from extension dependencies and background job scheduling, making it easier to deploy across different environments (like self-hosted or managed cloud).

- **`CLEAN_SCHEMA.sql`**: Contains the core database structures. This includes all table definitions, constraints, indexes, triggers, and PL/pgSQL functions. Sensitive webhook URLs are sanitized with placeholders (e.g., `YOUR_N8N_WEBHOOK_URL_HERE`).
- **`EXTENSIONS_&_CRONS.sql`**: Contains the setup commands for the required PostgreSQL extensions (`uuid-ossp`, `pgcrypto`, `vector`, `http`, `pg_cron`) and the `cron.schedule` blocks needed for time-based automations.

## Architecture Overview
The system relies entirely on PostgreSQL, using standard relational features, PL/pgSQL functions, and specialized extensions to communicate with external web services.

### High-Level Architecture Flow
The workflow operates on two primary execution models:

**Event-Driven Flow:**
1. An event occurs on a core table (e.g., `INSERT`, `UPDATE`, or `DELETE` on a lead or appointment).
2. A PostgreSQL trigger intercepts the event synchronously.
3. The trigger invokes a specific PL/pgSQL function.
4. The function builds a JSON payload and makes an outbound HTTP request (using `http_post`).
5. External platforms (like n8n or Meta Conversions API) receive the webhook and handle the rest of the business logic.

**Time-Driven Flow:**
1. Background workers scheduled via `pg_cron` routinely run specific PL/pgSQL queries.
2. These queries check records against time-based conditions (e.g., upcoming appointments that need reminders, or past appointments that need attendance follow-ups).
3. Qualifying records trigger outbound HTTP requests to the appropriate external services.

## System Requirements
The schema is designed for modern PostgreSQL environments (version 17+ recommended) and requires the following extensions at the cluster level:
- `uuid-ossp`: UUID generation.
- `pgcrypto`: Cryptographic hashing and validation.
- `vector`: Embeddings handling and similarity search.
- `http`: Outbound HTTP requests natively inside PostgreSQL.
- `pg_cron`: Task scheduling engine inside the database.

---

## Deployment Options

### Option A: Self-Hosted PostgreSQL (Ubuntu / Docker)
For self-hosted setups, you maintain full control over the database cluster. This makes it straightforward to install extensions that require elevated privileges and configure shared preload libraries.

#### Docker Deployment (Recommended)
The official `postgres:17` image doesn't bundle `pg_cron`, `pgvector`, or `pgsql-http` out of the box. You'll need to build a custom container to include them.

**1. Create a `Dockerfile`**
```dockerfile
FROM postgres:17

RUN apt-get update && \
    apt-get install -y \
    postgresql-17-cron \
    postgresql-17-pgvector \
    postgresql-17-http && \
    rm -rf /var/lib/apt/lists/*
```

**2. Configure `docker-compose.yml`**
Ensure `pg_cron` is loaded in `shared_preload_libraries` and pointed to the correct database:
```yaml
services:
  postgres:
    build: .
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secure_password
      POSTGRES_DB: automation_db
    ports:
      - "5432:5432"
    command: postgres -c shared_preload_libraries='pg_cron' -c cron.database_name='automation_db'
    volumes:
      - postgres_data:/var/lib/postgresql/data
      # Ensure extensions are processed before the core schema
      - ./EXTENSIONS_&_CRONS.sql:/docker-entrypoint-initdb.d/01_extensions.sql
      - ./CLEAN_SCHEMA.sql:/docker-entrypoint-initdb.d/02_schema.sql

volumes:
  postgres_data:
```

Start the stack by running:
```bash
docker compose up -d --build
```

#### Ubuntu Native Deployment
If deploying directly on a Linux host:

1. Install the required packages:
   ```bash
   sudo apt update
   sudo apt install postgresql-17 postgresql-contrib-17 postgresql-17-pgvector postgresql-17-cron postgresql-17-http
   ```
2. Update your `postgresql.conf` (usually located at `/etc/postgresql/17/main/postgresql.conf`) to include `pg_cron`:
   ```ini
   shared_preload_libraries = 'pg_cron'
   cron.database_name = 'automation_db'
   ```
3. Restart the PostgreSQL service:
   ```bash
   sudo systemctl restart postgresql
   ```
4. Load the files into the database:
   ```bash
   psql -U postgres -d automation_db -f "EXTENSIONS_&_CRONS.sql"
   psql -U postgres -d automation_db -f "CLEAN_SCHEMA.sql"
   ```

---

### Option B: Supabase Managed PostgreSQL
Supabase inherently supports most of these extensions, making managed deployments more straightforward.

#### Supabase Setup Steps
1. Go to your Supabase Project Dashboard -> **Database** -> **Extensions**.
2. Enable `pgvector` and `pg_cron`.
3. **Important Note on Webhooks:** While Supabase supports `pgsql-http`, they highly recommend using their asynchronous `pg_net` extension instead. If you want to use `pg_net` to avoid blocking database transactions, you'll need to update the `http_post` calls in `CLEAN_SCHEMA.sql` to use `net.http_post`.
4. Run the contents of `CLEAN_SCHEMA.sql` directly in the Supabase SQL Editor.
5. Run the cron jobs from `EXTENSIONS_&_CRONS.sql` in the Supabase SQL Editor. *Note: Ensure your user role has the required permissions to schedule background jobs.*

---

## Configuration and Secrets Management
For safety, the provided schema is sanitized. Before deploying to production, locate the following placeholders in the PL/pgSQL functions and replace them with your actual credentials:
- `YOUR_N8N_WEBHOOK_URL_HERE`
- `YOUR_META_WEBHOOK_URL_HERE`
- `YOUR_WEBHOOK_SECRET_HERE`
- `YOUR_INTERNAL_SERVICE_URL_HERE`

### Security Best Practices
- **Don't hardcode secrets in version control:** Never commit real webhook URLs or API keys to your repository.
- **Use PostgreSQL configuration variables:** Instead of hardcoding URLs into the SQL functions, it's safer to define custom configuration parameters (e.g., `ALTER SYSTEM SET custom.webhook_n8n = '...';`) and read them at runtime using `current_setting('custom.webhook_n8n')`.
- **Restrict execution privileges:** Ensure that only authorized roles have permission to execute the functions that dispatch webhooks.

## Known Limitations
When deploying this architecture—especially on managed database providers—keep the following constraints in mind:

- **Superuser Requirements:** Extensions like `pg_cron` and `pgsql-http` require superuser privileges to install and configure.
- **Managed Provider Restrictions:** Many fully-managed Postgres services lock down `shared_preload_libraries`, which means `pg_cron` might not be supported. Additionally, some providers block outbound network traffic by default, preventing `http_post` requests.
- **Synchronous HTTP Risks:** The `pgsql-http` extension is synchronous, meaning it holds the database transaction open until the external API responds. Network lag or slow responses from n8n / Meta can tie up database connections. For high-scale production systems, consider switching to an asynchronous model like `pg_net` or using an external message broker.
