# FastAPI Task Management API

A production-grade, RESTful web service for managing tasks, built to demonstrate a complete DevOps lifecycle. This project takes a baseline FastAPI application and wraps it in a fully orchestrated, observable, and secure production environment using Docker, NGINX, PostgreSQL, and Redis.

## Tech Stack

| Component                 | Technology              |
| ------------------------- | ----------------------- |
| **Application Framework** | FastAPI (Python 3.12)   |
| **Database**              | PostgreSQL 16           |
| **Cache & Rate Limiting** | Redis 7                 |
| **Web Server / Proxy**    | NGINX                   |
| **Containerization**      | Docker & Docker Compose |
| **CI/CD**                 | GitHub Actions          |

## Documentation Quick Links

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment.md)
- [CI/CD Pipeline](docs/cicd.md)
- [Backup Strategy](docs/backups.md)
- [Security Operations](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Day-to-Day Operations](docs/operations.md)

## API Endpoints

The API is served at the root domain (`/`).

| Method   | Endpoint           | Description                                                      |
| -------- | ------------------ | ---------------------------------------------------------------- |
| `GET`    | `/health`          | Static health check endpoint (validates DB & Redis connections). |
| `POST`   | `/tasks`           | Create a new task.                                               |
| `GET`    | `/tasks`           | List all tasks (cached in Redis).                                |
| `GET`    | `/tasks/{task_id}` | Retrieve a specific task by ID.                                  |
| `PUT`    | `/tasks/{task_id}` | Update a specific task by ID.                                    |
| `DELETE` | `/tasks/{task_id}` | Delete a specific task by ID.                                    |

## Local Development Setup

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Anshul-exe/FastAPI-Redis-Stack.git
   cd FastAPI-Redis-Stack
   ```

2. **Configure environment variables:**

   ```bash
   cp .env.example .env
   # Open .env and fill in the POSTGRES_USER, POSTGRES_PASSWORD, and POSTGRES_DB values.
   ```

3. **Start the local development stack:**
   ```bash
   docker compose up --build
   ```
   The API will be available at `http://localhost:8000`, and interactive Swagger documentation will be at `http://localhost:8000/docs`.

## Production Deployment

This stack is designed to be deployed to a single Linux VPS (Ubuntu 24.04 recommended).

Please see the [Deployment Guide](docs/deployment.md) for a complete, step-by-step walkthrough of provisioning a server, bootstrapping SSL certificates, and starting the production `docker-compose.prod.yml` stack.

## License

MIT
