from contextlib import asynccontextmanager
import logging
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from redis.exceptions import RedisError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from .config import get_settings
from .database import init_db
from .redis_client import redis_client
from .routers.tasks import router as tasks_router

settings = get_settings()

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    logger.info(
        "Task Management API starting up - (log_level=%s, rate_limit=%d req/min)",
        settings.LOG_LEVEL.upper(),
        settings.RATE_LIMIT_PER_MINUTE,
    )
    yield
    logger.info("Task Management API shutting down")


app = FastAPI(title="Task Management API", lifespan=lifespan)
app.include_router(tasks_router)


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    if request.url.path == "/health":
        return await call_next(request)

    client_ip = request.headers.get("x-forwarded-for")
    if client_ip:
        client_ip = client_ip.split(",")[0].strip()
    else:
        client_host = request.client.host if request.client else "unknown"
        client_ip = client_host

    window = int(time.time() // 60)
    key = f"rate_limit:{client_ip}:{window}"

    try:
        pipeline = redis_client.pipeline()
        pipeline.incr(key)
        pipeline.expire(key, 60)
        count, _ = pipeline.execute()
    except RedisError as exc:
        logger.exception("Rate limiter unavailable")
        return JSONResponse(
            status_code=503,
            content={"detail": "Rate limiting unavailable"},
        )

    if count > settings.RATE_LIMIT_PER_MINUTE:
        logger.warning(
            "Rate limit exceeded for %s (%d/%d req/min)",
            client_ip,
            count,
            settings.RATE_LIMIT_PER_MINUTE,
        )
        return JSONResponse(
            status_code=429,
            content={"detail": "Rate limit exceeded"},
        )

    return await call_next(request)


@app.get("/health")
def health_check():
    db_status = "ok"
    redis_status = "ok"
    details = {}

    try:
        from .database import SessionLocal

        with SessionLocal() as db:
            db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.exception("Database health check failed")
        db_status = "error"
        details["db"] = "unavailable"

    try:
        redis_client.ping()
    except RedisError as exc:
        logger.exception("Redis health check failed")
        redis_status = "error"
        details["redis"] = "unavailable"

    if details:
        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "db": db_status,
                "redis": redis_status,
                "detail": "Health check failed",
            },
        )

    return {"status": "ok", "db": "ok", "redis": "ok"}
