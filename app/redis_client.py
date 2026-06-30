from redis import Redis

from .config import get_settings

settings = get_settings()

redis_client = Redis.from_url(settings.REDIS_URL, decode_responses=True)
