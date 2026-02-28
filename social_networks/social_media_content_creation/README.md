# 🤖 Omnichannel Social Media AI Factory

An advanced n8n-based ecosystem for automated content generation and multichannel publishing. This pipeline leverages state-of-the-art AI models (Sora 2, Nano Banana, GPT-4o) to transform abstract marketing ideas into high-fidelity visual assets and tailored social media posts.

## 🚀 High-Level Architecture

The factory is organized into four core specialized modules:

1.  **AI Content Command Center (`AGENTE CONTENT MANAGER.json`)**
    *   **Role**: The primary AI orchestrator and conversational gateway.
    *   **Intelligence**: Handles complex, multi-turn interactions via Telegram to gather creative requirements.
    *   **Memory**: Maintains long-term project state, allowing users to iterate on generative tasks without losing context.
    *   **Output**: Generates high-precision JSON payloads that trigger specialized video, image, or publishing sub-workflows.

2.  **Kinetic AI Video Engine (`creador de VIDEOS redes sociales.json`)**
    *   **Model**: Sora 2 (via Kie AI API).
    *   **Capabilities**: Converts text descriptions or reference images into 10-25 second cinematic videos.
    *   **Logic**: Includes a dedicated prompt engineering layer that translates marketing goals into Sora-compatible visual descriptions and handles asynchronous job polling.

3.  **Generative AI Image Engine (`creador de IMAGENES redes sociales.json`)**
    *   **Model**: Nano Banana (via Kie AI API).
    *   **Capabilities**: High-fidelity image generation and editing (In-painting/Out-painting).
    *   **Logic**: Manages the lifecycle of image creation, from initial prompt to multi-cloud storage synchronization (Google Drive & Supabase).

4.  **Multichannel Social Media Publisher (`publicar en redes sociales v2.json`)**
    *   **Platforms**: Instagram (Feed, Reels, Carousel, Stories), Facebook, TikTok, LinkedIn, Twitter/X, Threads, and YouTube (Shorts, Community).
    *   **Intelligence**: Tailors high-conversion copy for each platform using GPT-4o-mini.
    *   **Delivery**: Handles complex binary uploads, container management (for Carousels), and rate-limited API calls with automated retry logic.

## 🛠️ Key Technologies

*   **Orchestration**: n8n (Advanced Agentic Workflows)
*   **AI Models**: Sora 2, Nano Banana, GPT-4o, OpenAI Whisper
*   **Infrastructure**: PostgreSQL (Supabase), Google Drive API, Telegram Bot API
*   **Social APIs**: Meta Graph API (IG/FB), X/Twitter API, LinkedIn API, TikTok API, YouTube Data API

## 🛡️ Security & Portability

*   **Credential Management**: All workflows are sanitized. Sensitive keys are replaced with `{{your_api_key}}` placeholders or environment variables.
*   **Modular Design**: Each workflow functions as a standalone microservice but is optimized for horizontal integration.
*   **Scalability**: Built to handle multi-file carousels and high-latency video rendering tasks through robust polling mechanisms.
