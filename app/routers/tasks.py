import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Response, status
from redis.exceptions import RedisError
from sqlalchemy.orm import Session

from ..crud import create_task, delete_task, get_task, list_tasks, update_task
from ..database import get_db
from ..redis_client import redis_client
from ..schemas import TaskCreate, TaskRead, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])
TASKS_CACHE_KEY = "tasks:list"
TASKS_CACHE_TTL_SECONDS = 30
logger = logging.getLogger(__name__)


def _invalidate_tasks_cache() -> None:
    try:
        redis_client.delete(TASKS_CACHE_KEY)
    except RedisError:
        logger.exception("Failed to invalidate tasks cache")


def _serialize_tasks(tasks: list[TaskRead]) -> str:
    return json.dumps([task.model_dump(mode="json") for task in tasks])


@router.post("", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task_endpoint(task_in: TaskCreate, db: Session = Depends(get_db)) -> TaskRead:
    task = create_task(db, task_in)
    _invalidate_tasks_cache()
    return TaskRead.model_validate(task)


@router.get("", response_model=list[TaskRead])
def list_tasks_endpoint(db: Session = Depends(get_db)) -> list[TaskRead]:
    try:
        cached_tasks = redis_client.get(TASKS_CACHE_KEY)
    except RedisError:
        logger.exception("Failed to read tasks cache")
        cached_tasks = None

    if cached_tasks:
        return [TaskRead.model_validate(item) for item in json.loads(cached_tasks)]

    tasks = list_tasks(db)
    task_schemas = [TaskRead.model_validate(task) for task in tasks]
    try:
        redis_client.setex(
            TASKS_CACHE_KEY,
            TASKS_CACHE_TTL_SECONDS,
            _serialize_tasks(task_schemas),
        )
    except RedisError:
        logger.exception("Failed to write tasks cache")
    return task_schemas


@router.get("/{task_id}", response_model=TaskRead)
def get_task_endpoint(task_id: int, db: Session = Depends(get_db)) -> TaskRead:
    task = get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return TaskRead.model_validate(task)


@router.put("/{task_id}", response_model=TaskRead)
def update_task_endpoint(
    task_id: int,
    task_in: TaskUpdate,
    db: Session = Depends(get_db),
) -> TaskRead:
    task = get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    updated_task = update_task(db, task, task_in)
    _invalidate_tasks_cache()
    return TaskRead.model_validate(updated_task)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task_endpoint(task_id: int, db: Session = Depends(get_db)) -> Response:
    task = get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    delete_task(db, task)
    _invalidate_tasks_cache()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
