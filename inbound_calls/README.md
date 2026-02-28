# 📞 AI-Powered Inbound Voice Engine

A sophisticated voice-to-action pipeline that automates inbound call handling using state-of-the-art Voice AI (Retell AI). This system eliminates wait times, captures 100% of lead data, and performs real-time CRM updates during conversation.

## 🚀 System Architecture

The inbound engine consists of two tightly coupled specialized workflows:

1.  **Inbound Call Data Router (`enviar_data.json`)**
    *   **Role**: The central nervous system for voice data.
    *   **Logic**: Orchestrates the initial handshake and final data persistence of the call lifecycle.
    *   **Context Optimization**: Before the AI agent speaks, this workflow retrieves the full customer profile (history, previous summaries, current status) from the database to inject "personality" and continuity into the conversation via dynamic variables.
    *   **Visibility**: Generates real-time notifications to internal teams via Telegram with comprehensive call summaries and lead scoring updates.

2.  **Retell AI Voice Capabilities Toolset (`herramientas_agenteRetellAI.json`)**
    *   **Role**: The execution arm of the AI voice agent.
    *   **Real-Time Interactions**: Exposes a suite of secure webhooks that allow the voice bot to "act" while listening:
        *   **Calendar Tool**: Queries Google Calendar for real-time availability and instantly books or cancels appointments based on the user's intent.
        *   **WhatsApp Bridge**: Triggers automated support escalations or meeting details via WhatsApp templates during or immediately after the call.
        *   **Memory Sync**: Updates the agent's long-term memory in the database to ensure the next call starts exactly where this one ended.

## 🛠️ Technology Stack

*   **Voice Core**: Retell AI (LLM-driven Voice Agents)
*   **Infrastructure**: n8n (Agentic Workflows), Postgres (Data Persistence)
*   **Communication**: WhatsApp Business API, Telegram Bot API
*   **Scheduling**: Google Calendar API
*   **Intelligence**: GPT-4o-mini (Transcript analysis & Intent classification)

## 💎 Key Business Value

*   **Zero Latency Response**: 24/7 immediate call answering without human dispatchers.
*   **Deep CRM Integration**: Bi-directional data sync ensures voice agents are always aware of the lead's position in the sales funnel.
*   **Self-Correction**: Timezone-aware scheduling logic prevents booking errors across different countries (Mexico, Colombia, Argentina, Spain, etc.).
*   **Automated Escalation**: Intelligent routing of complex queries to human support via instant messaging.

---
*Note: This module has been sanitized for portfolio demonstration. All sensitive API keys and internal identifiers have been replaced with placeholders.*
