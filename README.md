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

## Production & Engineering Highlights

This project goes beyond a basic Docker deployment by implementing robust, real-world DevOps practices:

- **Zero-Downtime Deployments:** Features a custom CI/CD deployment script that scales containers, performs deterministic health checks on new replicas via `jq` & `docker compose ps`, and routes traffic dynamically via a custom NGINX DNS resolver—ensuring zero dropped requests during updates.
- **Advanced Security & fail2ban:** Secured at the host level with UFW (default deny). A custom `fail2ban` jail and filter parse Docker's JSON NGINX logs, automatically banning malicious IPs exhibiting repeated 4xx/5xx errors.
- **Cloudflare Edge Integration:** DNS is proxied via Cloudflare with "Full (strict)" SSL. NGINX is configured to trust Cloudflare's edge ranges and accurately extract the real client IP via the `CF-Connecting-IP` header for precise rate limiting and logging.
- **Host-Bound Monitoring:** Integrated Prometheus and Grafana for full observability. To maintain a zero-trust external footprint, these services do not expose ports to the public internet; they are bound exclusively to `127.0.0.1` and accessed via secure SSH tunnels.
- **Redis Rate-Limiting & Caching:** The FastAPI app utilizes a Redis-backed token bucket algorithm for IP-based rate limiting, protecting the Postgres database from volumetric abuse while providing read-through caching for high-traffic endpoints.
- **Automated Local Backups:** A robust cron-scheduled bash script executes `pg_dump` securely within the Docker network, compressing and rotating backups on the host filesystem with a 7-day retention policy.

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
   git clone https://github.com/<your-username>/FastAPI-Redis-Stack.git
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
