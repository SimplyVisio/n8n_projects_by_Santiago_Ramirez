🚀 Social Media Community Manager Agent (Facebook & Instagram)

n8n + AI + Meta Graph API

📌 Overview

This project provides an automated community management solution for Facebook and Instagram. It monitors brand accounts for new comments, classifies user intent (Sales vs. Engagement vs. Spam), and executes appropriate responses in near real-time.

The system combines rule-based logic for speed and AI-based processing for human-like conversation, ensuring that every lead is captured and every social interaction is acknowledged.

🏗 Architecture

CRON (Every 10 mins) → Meta Graph API (Fetch Activity)
        ↓
Filtration Layer (Check Timestamp & Ownership)
        ↓
Hybrid Classification Layer (JS Rules + AI Intent Detection)
        ↓
AI Intelligence Layer (GPT-4o mini + Vector Knowledge Base)
        ↓
Action Execution Layer (Private DM + Public Reply)

⚙️ How It Works

1. Monitoring: The workflow polls the Facebook/Instagram Graph API every 10 minutes for activity on the last 10 posts.
2. Filtering: It ignores the brand's own comments and those older than the polling interval.
3. Classification:
   - Sales Intent: Triggers a private DM invitation and a public comment reply.
   - Engagement: Triggers a warm AI-generated public reply to increase reach.
   - Spam: Filters out repetitive, empty, or low-value content.
4. AI Personalization: Uses GPT-4o mini and a specialized knowledge base to answer technical questions and maintain brand voice.
5. Formatting: Appends a professional social media footer with contact information and links.

🧮 Intent Classification Examples

Commercial Interest: "What is the price of the chatbot?" or "I'm interested."
Action: [Private DM sent] + [Public Reply: "Check your DMs!"]

Social Interaction: "Amazing content, keep it up!"
Action: [Public Reply: "Thank you! We're glad you find it useful. 🚀"]

🧠 Why This Project Matters

This project demonstrates:
- Multichannel Automation: Simultaneous handling of Facebook and Instagram.
- Real-world API Integration: Managing Meta Graph API complexity and rate limits.
- Cost-Effective AI: Using GPT-4o mini for high-quality, low-cost conversational agents.
- Lead Conversion: Proactively moving public comments into private sales channels.
- Brand Consistency: Unified voice and contact information across all social touchpoints.

🐳 Setup (Technical Note)

- Meta Developer App: Required with pages_manage_metadata, instagram_manage_comments, and instagram_manage_messages permissions.
- API Key Management: Uses secure n8n credential management for long-lived Page Access Tokens.
- Vector Store Integration: Connects to a dedicated Knowledge Base for accurate service information.

👨‍💻 Author

your_name Ramirez
Automation Engineer | Workflow Architect | Backend Enthusiast
