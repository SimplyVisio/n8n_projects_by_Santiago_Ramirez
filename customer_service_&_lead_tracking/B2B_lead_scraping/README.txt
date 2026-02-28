🚀 B2B Automated Sales & Outreach Pipeline

n8n + AI + Evolution API + Google Calendar + Postgres

📌 Overview

This project is a high-performance B2B sales automation engine. It handles everything from initial cold outreach to conversational qualification and final appointment scheduling. By integrating behavioral rules with advanced AI, the system maintains a human-like presence while operating at a scale impossible for manual sales teams.

The pipeline is split into Outbound (Cold Outreach) and Inbound (Lead Response) phases, synchronized via a centralized PostgreSQL database.

🏗 Architecture

1. Lead Acquisition (Documentation Note)
   - New leads are populated into the 'prospectos_b2b' table in PostgreSQL.
   - For high-volume lead extraction, this system can be integrated with Model Context Protocol (MCP) tools like Playwright or the Antigravity tool to scrape B2B data (LinkedIn, Google Maps, Industry Directories) and save it directly to the database.

2. Outbound Phase (CRON)
   - Automator: Monitors the database for uncontacted leads.
   - Validation: Respects business hours (Mon-Fri) and adds randomized delays to prevent spam detection.
   - Delivery: Dispatches personalized first-touch messages via Evolution API (WhatsApp).

3. Filtering & Routing Phase
   - Buffer: Redis ensures that multi-message inquiries from prospects are processed as a single context.
   - Classification: An AI agent filters out OOO (Out of Office) replies and social fillers, focusing only on real commercial interest.

4. Conversational Intelligence (Main Agent)
   - Context: Injects lead-specific data (company, industry, pain points) and past history.
   - Tools: Directly manages a Google Calendar to find slots and book meetings without human intervention.
   - Memory: Chat history is persisted in Postgres for consistency.

⚙️ Core Components

1. AGENTE DE VENTAS B2B WA: The primary AI gateway for all inbound WhatsApp leads.
2. responder prospecto WA b2b: Specialized response gateway for leads coming from cold outreach.
3. agendamiento y ventas B2B COLD: The central "Brain" that manages calendar logic and booking.
4. agendamiento y ventas para prospectos_b2b: Segment-specific variant of the scheduling engine.
5. enviar cold WA: The outbound engine that dispatches automated, human-like cold messages.
6. GUARDAR MEMORIA AGENTE HUMANO: Synchronization tool that keeps AI memory updated with human agent interactions.
7. BOT_ON_OFF_PROSPECTOS_WA: Control utility to enable/disable AI automation for specific sessions or global states.

🗄️ Database Infrastructure (PostgreSQL)

- prospectos_b2b: Master table for LinkedIn/Maps scraped data.
- conversaciones: Unified chat history for cross-session context.
- citas: Real-time appointment tracking and synchronization.

🧠 Strategy & Benefits

- Hybrid Execution: Hardcoded constraints (business hours, spam protection) mixed with LLM flexibility.
- Proactive Engagement: Doesn't just wait for leads—it goes and gets them.
- Data Enrichment: Uses specialized SQL queries to retrieve lead profile data before every AI response.
- Automated Scheduling: Eliminates the "back and forth" of booking calls.

👨‍💻 Author

your_name Ramirez
Automation Engineer | Workflow Architect | Backend Enthusiast
