# 🎯 Customer Excellence & Lead Intelligence Suite

A comprehensive framework for automating the entire lifecycle of a customer—from anonymous lead capture to loyal customer support. This suite leverages AI-driven orchestration to ensure zero-latency responses across all major social and messaging channels.

## 🚀 Core Functional Domains

The system is organized into specialized modules that handle specific stages of the customer journey:

### 1. 🤖 [AI Lead Scoring Pipeline](./AI_lead_scoring_pipeline)
Intelligent qualification engine that analyzes incoming leads from web forms and meta ads to prioritize high-value prospects.

### 2. 🛡️ [B2B Lead Scraping](./B2B_lead_scraping)
Automated tools for prospecting and data enrichment for cold outreach and sales development.

### 3. 📊 [Chatwoot Dashboards](./chatwoot_dashboards)
Custom interactive extensions for the Chatwoot CRM that enable agents and customers to book, reschedule, or cancel appointments directly within the conversation window.

### 📥 [Inbox: Lead to Customer](./inbox_lead_to_customer)
Multichannel inbox management pipeline that synchronizes WhatsApp, Instagram, and Messenger into a unified data stream with long-term memory.

## 🔗 Integrated Automation Architecture

1.  **Ingestion:** Webhooks capture signals from Meta Ads, Webforms, and Voice calls.
2.  **Intelligence:** GPT-4o models perform real-time intent analysis and data extraction.
3.  **Action:** The system automatically schedules meetings, updates CRM records, and notifies the team via Telegram.
4.  **Retention:** Continuous synchronization with Supabase ensure a 360° view of every customer interaction.

## 🛠️ Global Prerequisites

To deploy this suite, the following credentials should be configured in your n8n environment:

- **Messaging:** WhatsApp Business API, Meta Access Token, Telegram Bot Token.
- **CRM & Helpdesk:** Chatwoot API Token.
- **Data Persistence:** Supabase URL & Service Role Key, Postgres Credentials.
- **Productivity:** Google Calendar OAuth.

---
*Elevating customer engagement through agentic automation.*
