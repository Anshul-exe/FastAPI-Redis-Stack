# Troubleshooting Guide

| Symptom | Likely Cause | Fix |
|---|---|---|
| **App container won't start (CrashLoopBackOff)** | Syntax error in Python code, missing dependency, or invalid `.env` configuration. | Run `docker compose -f compose/docker-compose.prod.yml logs app` to view the Python traceback. |
| **502 Bad Gateway from NGINX** | NGINX cannot reach the FastAPI container. The app is down, restarting, or frozen. | Check app container status with `docker compose ps`. Restart the app: `docker compose restart app`. Check app logs for deadlocks. |
| **NGINX container fails to start (cert errors)** | NGINX configuration references SSL certificates that do not exist yet on a fresh provision. | Refer to `docs/deployment.md` Step 3 (Bootstrap Order) to run certbot first via HTTP. |
| **Database connection failed / SQLAlchemyError** | Postgres container is down, or `DATABASE_URL` in `.env` is incorrect or missing. | Check postgres logs: `docker compose logs postgres`. Verify `.env` credentials exactly match the connection string. |
| **Redis connection failed / Rate Limiter offline** | Redis container is down or unreachable. | Check redis status: `docker compose logs redis`. The app should gracefully bypass or fail-open/closed based on logic, but caching will fail. |
| **Rate limiter blocking all requests (429)** | `RATE_LIMIT_PER_MINUTE` is set too low, or NGINX is not forwarding the client IP correctly (causing all traffic to be rate-limited as a single IP). | Check `X-Forwarded-For` proxy settings in NGINX. Check `RATE_LIMIT_PER_MINUTE` in `.env`. |
| **Backup script fails (`pg_dump failed`)** | Incorrect credentials in `.env`, or the Postgres container is not running under the expected name. | Run `. .env` and echo the variables to verify. Check `docker ps` to ensure the postgres container is running. |
| **CI/CD deploy job fails via SSH** | Invalid GitHub Secrets (`VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`), or SSH port blocked. | Verify the private key in `VPS_SSH_KEY` is correct. Verify the public key is in `/home/ubuntu/.ssh/authorized_keys` on the VPS. |
