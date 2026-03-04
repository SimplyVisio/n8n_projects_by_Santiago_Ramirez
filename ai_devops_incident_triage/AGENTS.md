Project Identity

This project implements a production-oriented Agentic AI DevOps Incident Intelligence System.

This is NOT a simple LLM wrapper.
This is NOT a chatbot.
This is NOT a synchronous inference API.

It is a structured, tool-driven, memory-aware, asynchronous AI system designed to process DevOps incidents intelligently.

The agent must behave like a reasoning system, not like a text generator.

Core Philosophy

The system follows these principles:

Agent-first architecture

Tool-based deterministic actions

Memory hierarchy (hot + cold)

Async processing separation

Resource-efficient reasoning

Minimal token waste

Production-grade modularity

Every design decision must support these principles.

System Architecture Overview

Components:

FastAPI (API layer)

Redis (queue + hot memory)

Worker process (agent execution)

PostgreSQL (cold memory)

Tool registry

Single reasoning agent (iterative loop)

n8n is only an orchestrator.
This system is the intelligence layer.

Agent Design Contract

The agent MUST:

Operate using iterative reasoning (Level 2)

Use OpenAI function-calling for tool invocation

Never hallucinate external actions

Only act through registered tools

Update memory after each reasoning step

Stop after max_iterations

Produce structured output

The agent MUST NOT:

Directly access database clients

Directly access Redis

Directly send HTTP requests

Execute business logic outside tools

Store full chain-of-thought logs

All external interactions happen via tools.

Iterative Reasoning Model

Each iteration must follow:

Analyze current state

Decide next tool

Call tool via function-calling

Receive structured result

Update working memory

Decide whether to continue

Max iterations configurable via environment variable.

The reasoning loop must be deterministic and controlled.

Memory Hierarchy Design
Redis (Hot Memory)

Purpose:

Store frequent fingerprints

Store short contextual summaries

Store cached DB query results

Track recent incident counts

Redis is for:

Fast lookup

Avoiding DB queries

Temporary context

TTL must be configurable.
Default: 7 days.

The agent must always check Redis before querying Postgres.

PostgreSQL (Cold Memory)

Purpose:

Long-term incident storage

Audit trail

Structured reasoning summaries

Historical stats

Rules:

No full-table scans

Use indexed columns only

Limit result sets

Only query necessary columns

Agent must use SQL generation tool.
Never raw queries in agent logic.

SQL Tool Design Rules

The SQL tool must:

Accept structured parameters

Validate allowed columns

Use parameterized queries

Use indexed columns:

fingerprint

workflow_id

created_at

error_message (indexed)

Always apply LIMIT

Never allow dynamic column injection

If query result is useful:
Cache it in Redis.

Tool System Architecture

Tools must be:

Pure

Deterministic

Typed

Side-effect controlled

Independently testable

Each tool must:

Define input schema

Define output schema

Raise structured errors

Log execution metadata

Tools are the only interface between the agent and the world.

Required Tool Categories

Identity tools

fingerprint generation

Memory tools

check redis

cache redis

Database tools

structured SQL query

incident storage

stats update

Notification tools

telegram alert

Finalization tools

structured incident decision

Async Architecture Rules

API layer must:

Validate input

Push to Redis queue

Return 202 immediately

Never call LLM

Worker must:

Consume queue

Execute agent

Handle retries

Log failures

LLM execution must never block API thread.

Structured Reasoning Logs

We do NOT store chain-of-thought.

We store:

iteration number

tool chosen

tool result summary

decision delta

final reasoning summary

Logs must be concise and structured.

Purpose:

Observability

Debugging

Audit

Recruiter credibility

Fingerprint Strategy

Fingerprint must:

Be deterministic

Use stack trace normalization

Use SHA256

Ignore timestamps

Ignore dynamic IDs

Goal:
Group semantically identical errors.

Similarity Without Embeddings (v1 Constraint)

Embeddings are disabled in v1.

Similarity must rely on:

fingerprint match

indexed error_message ILIKE search

structured pattern matching

SQL tool may perform limited ILIKE queries with LIMIT 10.

Caching Strategy

If:

Redis miss → SQL query → useful result

Then:

Cache result in Redis with TTL.

Cache must include:

count

last_seen

short context summary

source: "db"

Configuration Philosophy

All tunable parameters must be in .env:

Redis TTL

Max iterations

Model

Retry policy

No hardcoded values.

Error Handling Rules

System must handle:

Redis unavailable

DB unavailable

LLM timeout

Tool failure

Invalid input

Failures must:

Be logged

Not crash worker

Trigger safe fallback

Optionally notify Telegram

Observability Requirements

Log:

Request ID

Fingerprint

Iteration count

Tool usage

Cache hit/miss

Total processing time

Structured logging required.

Scalability Expectations

System must allow:

Multiple workers

Horizontal scaling

Redis cluster upgrade

Postgres scaling

Model change without refactor

Architecture must remain modular.

Code Quality Rules

Clear module boundaries

No circular imports

Dependency injection friendly

Pydantic models for schemas

Type hints everywhere

Async-safe patterns

What This Project Is Meant To Demonstrate

This project showcases:

Agentic architecture

Tool-driven reasoning

Memory layering

Async AI systems

Production-aware design

Token efficiency strategy

This is a systems engineering portfolio piece.

All implementation choices must reinforce that identity.

Future Roadmap (Not v1)

Embeddings-based similarity

SRE metrics engine

Severity auto-calibration

Incident clustering

Dashboard UI

Multi-agent planner layer

Do NOT implement these in v1.
Design for extensibility.

Final Directive to Any AI Generating Code

Do not simplify architecture.
Do not remove agent loop.
Do not collapse tools into agent logic.
Do not remove async queue.
Do not bypass Redis memory layer.
Do not convert into a simple chatbot.

This system must remain a structured, memory-aware, tool-driven agent.
