from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", env_file=None)

    DATABASE_URL: str = Field(min_length=1)
    REDIS_URL: str = Field(min_length=1)
    RATE_LIMIT_PER_MINUTE: int = Field(default=100, ge=1)
    LOG_LEVEL: str = Field(default="INFO")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
