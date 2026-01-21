# 🤖 n8n Automation Portfolio

**Santiago Emiliano Ramírez Vázquez**  
*Automation & AI Specialist*

---

## 👋 Overview

This repository contains a curated portfolio of **production-ready n8n workflows** designed and implemented by Santiago Emiliano Ramírez Vázquez, focused on:

- 🧠 **AI agents**
- 📡 **Omnichannel automation**
- 💼 **Sales, marketing, and customer support workflows**
- 📱 **WhatsApp, voice agents, and social media automation**
- 🗄️ **Centralized data, memory, and orchestration using n8n**

Each project is composed of **multiple modular workflows** (JSON files) that work together as a complete automation system.

---

## 🏗️ Architecture Philosophy

All workflows follow these principles:

✅ **Modular design** (each JSON has a single responsibility)  
✅ **Centralized data & memory**  
✅ **Event-driven orchestration**  
✅ **Scalable and extensible**  
✅ **Multi-agent architecture** (AI agents with specialized roles)

---

## 📂 Projects & Files Description

### 🟢 1. Cold B2B Sales & WhatsApp Automation

**Purpose:** End-to-end cold B2B prospecting, lead qualification, and automated appointment scheduling using WhatsApp.

#### Files

| File | Description |
|------|-------------|
| `AGENTE DE VENTAS B2B WA (1).json` | **Main AI Sales Agent workflow**<br/>• Handles conversations with B2B prospects via WhatsApp<br/>• Personalizes responses using enriched company data<br/>• Moves prospects through sales funnel stages (Lead → Contacted → Meeting Booked) |
| `enviar cold WA (13).json` | **Cold outreach dispatcher**<br/>• Sends outbound WhatsApp messages<br/>• Controls rate limits and delivery logic<br/>• Prevents duplicate outreach |
| `agendamiento y ventas B2B COLD (4).json` | **Sales + scheduling orchestration**<br/>• Manages meeting booking<br/>• Integrates calendar logic<br/>• Normalizes timezones based on prospect location |

---

### 🟣 2. Voice AI Agent – Retell AI (Inbound Calls)

**Purpose:** Provide real-time AI assistance during inbound voice calls with live access to customer data and scheduling tools.

#### Files

| File | Description |
|------|-------------|
| `inbound_calls_retellAI_agent(EN).json` | **Inbound voice agent logic**<br/>• Triggered when a call is received<br/>• Provides contextual customer information<br/>• Guides the voice AI conversation dynamically |
| `herramientas_agenteRetellAI (40).json` | **Tooling layer for the voice agent**<br/>• Google Calendar tools (schedule, cancel, reschedule)<br/>• Data lookup and validation<br/>• Exposed as callable tools for the voice agent |
| `enviar_data (22).json` | **Data sharing utility** *(Shared with other projects)*<br/>• Passes structured customer and call data<br/>• Ensures consistency across voice and chat channels |

---

### 🔵 3. AI Content Creation for Social Media

**Purpose:** Automated creation and publishing of AI-generated images and videos for social media platforms.

#### Files

| File | Description |
|------|-------------|
| `AGENTE CONTENT MANAGER (2).json` | **Central content orchestration agent**<br/>• Decides content type (image or video)<br/>• Assigns tasks to specialized creation workflows<br/>• Maintains content metadata and state |
| `creador de IMAGENES redes sociales (8).json` | **Image generation workflow**<br/>• Generates AI images based on business goals<br/>• Stores assets and metadata<br/>• Prepares content for publishing |
| `creador de VIDEOS redes sociales (15).json` | **Video generation workflow**<br/>• Creates AI-generated videos (e.g. SORA-style workflows)<br/>• Generates prompts, scenes, and scripts<br/>• Stores output references |
| `publicar en redes sociales (23).json` | **Publishing automation**<br/>• Publishes content to social platforms<br/>• Generates captions and copy automatically<br/>• Supports scheduled or immediate posting |

---

### 🟠 4. Customer Support & Complaint Resolution (Omnichannel)

**Purpose:** Automated customer support system with AI agents, complaint handling, and escalation to humans.

#### Files

| File | Description |
|------|-------------|
| `soporte_cliente (7).json` | **Customer support agent**<br/>• Handles FAQs and common questions<br/>• Uses centralized customer memory<br/>• Responds consistently across channels |
| `queja_cliente (23).json` | **Complaint resolution workflow**<br/>• Collects structured complaint data<br/>• Integrates with WhatsApp Meta FLOWS<br/>• Routes issues to resolution agents or humans |

---

### 📄 Supporting Files

| File | Description |
|------|-------------|
| `portfolio2.pdf` | Generated PDF portfolio showcasing selected workflows<br/>Used for interviews and client presentations |

---

## 🧩 How These Workflows Interact

```mermaid
graph TD
    A[Customer Contact] --> B{Channel}
    B -->|WhatsApp| C[Sales Agent]
    B -->|Voice Call| D[Voice AI Agent]
    B -->|Support Request| E[Support Agent]
    
    C --> F[Centralized Memory]
    D --> F
    E --> F
    
    F --> G[Orchestration Layer]
    G --> H[Content Manager]
    G --> I[Scheduling System]
    G --> J[CRM Integration]
```

**Key interactions:**

- Multiple workflows communicate via **webhooks** and **shared data utilities**
- Customer identity is **unified across channels**
- AI agents specialize by role:
  - 💼 Sales
  - 🆘 Support
  - 📢 Complaints
  - 🎨 Content creation
  - 🎙️ Voice interaction
- **n8n acts as the central orchestration layer**

---

## 🚀 How to Use

1. **Import** desired `.json` workflows into n8n
2. **Configure credentials** (WhatsApp API, OpenAI, Supabase, etc.)
3. **Activate workflows** in the recommended order:
   - Data utilities
   - Core agents
   - Channel-specific triggers

---

## 👤 Author

**Santiago Emiliano Ramírez Vázquez**  
Automation & AI Specialist  
📍 Mexico (GMT-6)

🔗 [GitHub](https://github.com/SimplyVisio)  
💼 [LinkedIn](https://www.linkedin.com/in/santiago-emiliano-ramírez-vázquez-583957397)  
🌐 [Website](https://www.socialmask.com.mx)

---

## 🎯 Next Improvements

- [ ] Architecture diagrams per project
- [ ] Environment variables documentation
- [ ] Setup scripts per workflow group
- [ ] Video demos of workflows in action
- [ ] Performance metrics and benchmarks

---

## 📝 License

This portfolio is for demonstration purposes. Individual workflows may require specific credentials and API keys.

---

<div align="center">

**⭐ If you find this portfolio useful, please consider giving it a star!**

*Built with ❤️ using n8n*

</div>
