import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    # API Settings
    PROJECT_NAME: str = "Agentic AI DevOps Incident Intelligence System"
    API_VERSION: str = "1.0.0"
    
    # OpenAI Settings
    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o"
    OPENAI_TIMEOUT: float = 20.0  # Reduced to 20s for better worker responsiveness
    OPENAI_MAX_RETRIES: int = 2
    
    # Database Settings (Supabase)
    SUPABASE_DB_URL: str
    SUPABASE_DB_USER: str
    SUPABASE_DB_PASSWORD: str
    
    # Redis Settings
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_TTL_SECONDS: int = 604800          # Sliding window reset per hit (default 7 days)
    REDIS_MAX_LIFETIME_SECONDS: int = 2592000  # Absolute eviction cap (default 30 days; 0 = disabled)
    
    # Agent Settings
    AGENT_MAX_ITERATIONS: int = 8
    IDEMPOTENCY_WINDOW_SECONDS: int = 300  # 5 minutes
    
    # Telegram Settings
    TELEGRAM_BOT_TOKEN: str
    TELEGRAM_CHAT_ID: str

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

settings = Settings()
