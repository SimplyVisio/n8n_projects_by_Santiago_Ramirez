🚀 AI Lead Scoring Pipeline

n8n + FastAPI + pandas + numpy

📌 Overview

This project demonstrates a microservice-based lead scoring system using:

n8n as the orchestration layer

FastAPI as a backend processing engine

pandas for structured data handling

numpy for statistical calculations

Docker for containerized deployment

The goal of this project is to showcase how workflow automation can be combined with real backend data processing to build scalable and modular systems.

🏗 Architecture
Client → n8n (Webhook)
        ↓
Validation Layer
        ↓
Python FastAPI Microservice
        ↓
Statistical Processing (pandas + numpy)
        ↓
Formatted Response
⚙️ How It Works

A lead is submitted via webhook.

n8n validates required fields.

The workflow sends the data to a Python FastAPI microservice.

The microservice:

Converts input into a pandas DataFrame

Cleans missing values

Applies a weighted scoring model using numpy

Computes statistical metrics (mean & standard deviation)

The lead is classified as:

Hot

Warm

Cold

The response is returned to the client.

🧮 Example Input
{
  "name": "John Doe",
  "budget": 85,
  "company_size": 60,
  "engagement_level": 90
}
📊 Example Output
{
  "lead_score": 79,
  "classification": "Hot",
  "analytics": {
    "mean_input": 78.33,
    "std_dev_input": 13.12
  }
}
🧠 Why This Project Matters

This project demonstrates:

Separation of concerns (orchestration vs processing)

Microservice communication via HTTP

Statistical data processing with pandas & numpy

Docker-based deployment

Secure API key validation

Workflow-driven system design

It highlights the ability to combine automation tools with backend engineering practices.

🐳 Running the Project

Build the Python service:

docker compose build
docker compose up -d

Import the n8n workflow JSON.

Execute the webhook endpoint.

Send a test request using curl or Postman.

👨‍💻 Author

your_name Ramirez
Automation Engineer | Workflow Architect | Backend Enthusiast
