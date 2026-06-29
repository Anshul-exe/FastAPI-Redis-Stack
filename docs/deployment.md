# Deployment Guide

This document provides a complete walkthrough for provisioning a fresh VPS and deploying the Task Management API for the first time.

## Prerequisites

- **Compute**: A fresh VPS (e.g., AWS EC2 t2.micro) running **Ubuntu 24.04**.
- **Networking**: Security group / firewall configured to allow inbound traffic on ports `22` (SSH), `80` (HTTP), and `443` (HTTPS).
- **Access**: An SSH key pair to connect to the server.
- **DNS**: An `A` record pointing `api.example.com` to the public IP address of your server.

---

## Step 1: Run the VPS Setup Script

SSH into the VPS as a user with `sudo` privileges (typically `ubuntu` on EC2) and run the setup script. This script handles system updates, installs Docker and UFW, sets firewall rules, creates backup directories, and clones the repository.

```bash
sudo curl -sO https://raw.githubusercontent.com/<your-username>/FastAPI-Redis-Stack/main/scripts/setup-vps.sh
sudo bash setup-vps.sh
```

**Required action:** Log out of the VPS completely and log back in to ensure the `ubuntu` user inherits the newly applied `docker` group permissions.

---

## Step 2: Configure Environment Variables

Navigate to the newly cloned repository and set up the environment variables file:

```bash
cd /opt/taskapi
cp .env.example .env
nano .env
```

Fill in the real values for your production environment (e.g., strong, secure passwords for `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`).

---

## Step 3: Initial SSL Certificate Issuance

Certbot uses an HTTP-01 challenge to prove domain ownership. For this to work, the Certbot container places a challenge file in the webroot, and NGINX serves it over HTTP. 

**Bootstrap Order:** NGINX must be running and listening on HTTP (port 80) *first*. Because our main NGINX config expects SSL certificates to already exist for the HTTPS block, NGINX will crash if you attempt to start the full stack immediately.
To bootstrap:
1. Temporarily start NGINX with a config that only listens on port 80 (or comment out the port 443 block in `docker/nginx/default.conf`).
2. Run NGINX.
3. Once NGINX is serving HTTP, run the initial Certbot command to generate the certs in the named Docker volumes:

```bash
docker run --rm -v certbot_certs:/etc/letsencrypt -v certbot_webroot:/var/www/certbot certbot/certbot certonly --webroot -w /var/www/certbot -d api.example.com --email <your-email@example.com> --agree-tos --no-eff-email
```

4. Stop NGINX and restore the full configuration containing the HTTPS block.

---

## Step 4: Start the Full Stack

With the certificates successfully generated and stored in the `certbot_certs` volume, you can start the full production stack:

```bash
docker compose -f compose/docker-compose.prod.yml up -d
```

---

## Step 5: Verify Services

Check that all containers started successfully and are running healthily:

```bash
docker compose -f compose/docker-compose.prod.yml ps
```

All services (`app`, `postgres`, `redis`, `nginx`, and `certbot`) should show a state of `Up` (and `healthy` for the ones with configured health checks).

---

## Step 6: Set Up Backup Cron

To prevent data loss, ensure that the Postgres database is backed up regularly. Reference [Backups Documentation](backups.md) to set up the automated backup cron job. 

To configure it quickly, edit the crontab:
```bash
sudo crontab -e
```
Add the following line to back up daily at 2:00 AM UTC:
```cron
0 2 * * * cd /opt/taskapi && set -a && . .env && set +a && bash scripts/backup.sh >> /var/log/taskapi-backup.log 2>&1
```

---

## Step 7: Set GitHub Secrets for CI/CD

To enable automated deployments on code pushes, navigate to your GitHub repository's Action Secrets and add the required variables. Reference [CI/CD Documentation](cicd.md) for full details.

You will need to set:
- `VPS_HOST`
- `VPS_USER`
- `VPS_SSH_KEY`

---

## Step 8: Zero-Downtime Deployments

To ensure continuous availability, the project includes a zero-downtime deployment script (`scripts/deploy-zero-downtime.sh`).
This script works by:
1. Scaling the `app` service to 2 replicas (leaving the old container running).
2. Polling `docker compose ps --format json` to ensure the new container is healthy before proceeding.
3. Terminating the exact `OLD_CONTAINER_ID` once the new one is verified.
4. If health checks fail (timeout), stopping the new unhealthy container and rolling back cleanly without touching the old container.

**NGINX DNS Resolver Quirk:**
Docker's embedded DNS usually resolves an upstream hostname (`app`) once at container startup. To route traffic dynamically without restarting NGINX during the scale up/down, NGINX is configured to force re-resolution:
```nginx
resolver 127.0.0.11 valid=10s;
set $upstream app;
proxy_pass http://$upstream:8000;
```
This ensures NGINX re-checks the internal DNS IP for `app` periodically instead of caching a stale container IP.

---

## Troubleshooting

### Cert Not Found on Startup
**Symptom:** NGINX container exits with a "cannot load certificate" error when running `docker compose up -d`.
**Fix:** The SSL certificate was not successfully issued. Follow the bootstrap order in Step 3 to start NGINX in HTTP-only mode first, request the certificate using the `docker run` command, and then restore the full configuration.

### Port Already in Use
**Symptom:** Docker fails to bind to port 80 or 443.
**Fix:** Another service (like Apache) might be running on the VPS natively. Stop and disable it: `sudo systemctl stop apache2 && sudo systemctl disable apache2`.

### Database Not Ready
**Symptom:** The `app` container restarts repeatedly, complaining about database connection failures.
**Fix:** The `postgres` container might take extra time to initialize on the very first run. The health check should handle this gracefully, but if the app container fails its retry limit, simply wait 30 seconds and run `docker compose -f compose/docker-compose.prod.yml up -d` again.

### Permission Denied on Docker
**Symptom:** Running `docker` or `docker compose` results in a permission denied error.
**Fix:** Your user session hasn't updated its groups. Ensure you completely log out of your SSH session and log back in (as stated in Step 1) so your user inherits the `docker` group.
