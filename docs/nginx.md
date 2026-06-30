# NGINX Reverse Proxy

## Purpose
In this architecture, NGINX serves as the public-facing gateway for the FastAPI application. Its primary responsibilities are:
- **TLS Termination**: Decrypting HTTPS traffic and managing SSL certificates.
- **Reverse Proxying**: Forwarding requests to the internal FastAPI application.
- **Security**: Enforcing strict HTTP security headers and hiding backend implementation details.

## Config File Locations
- **`docker/nginx/nginx.conf`**: The main NGINX configuration defining worker processes, connections, and core HTTP settings.
- **`docker/nginx/default.conf`**: The server block configuration defining virtual hosts, SSL paths, routing rules, and security headers.

## HTTP → HTTPS Redirect
NGINX is configured to listen on port 80 (HTTP) globally. Its only function on port 80 is to respond to ACME challenge requests from Certbot (`/.well-known/acme-challenge/`) and to issue a `301 Moved Permanently` redirect to the `https://` equivalent for all other traffic. This ensures no unencrypted traffic reaches the application.

## SSL Termination
NGINX handles the decryption of all inbound HTTPS traffic using Let's Encrypt certificates. It then communicates with the FastAPI container over plain HTTP on the internal Docker network. This offloads cryptographic overhead from the Python application and centralizes certificate management.

## Security Headers
The following headers are injected by NGINX into every response:
- **`Strict-Transport-Security (HSTS)`**: Forces browsers to only connect via HTTPS for the specified duration (1 year), preventing protocol downgrade attacks.
- **`X-Content-Type-Options: nosniff`**: Prevents MIME-type sniffing, ensuring the browser respects the declared content type.
- **`X-Frame-Options: DENY`**: Prevents the site from being embedded in iframes, protecting against clickjacking.
- **`X-XSS-Protection: 1; mode=block`**: Enables legacy cross-site scripting filters in older browsers.
- **`Content-Security-Policy (CSP)`**: Restricts where resources can be loaded from. Configured as `default-src 'self'` to prevent unauthorized external scripts or assets.

## Reloading Configuration Without Downtime
If you make changes to the NGINX configuration files and deploy them to the VPS, you can reload the configuration without restarting the container and dropping active connections:
```bash
docker compose -f compose/docker-compose.prod.yml exec nginx nginx -s reload
```

## Certbot Auto-Renewal
The `certbot` container in the production compose file runs an infinite shell loop:
```bash
while :; do certbot renew --webroot ...; sleep 12h & wait $!; done
```
It wakes up every 12 hours and checks if the certificate is within 30 days of expiration. If it is, it places a challenge file in the shared `/var/www/certbot` volume. NGINX serves this file to Let's Encrypt to validate domain control, and Certbot seamlessly replaces the certificates in the shared `/etc/letsencrypt` volume.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| **502 Bad Gateway** | The `app` container is down, restarting, or inaccessible. | Run `docker compose ps` to check `app` status. Check `docker compose logs app`. |
| **Cert Not Found (NGINX Crash)** | NGINX requires SSL certs to start the 443 block. If certs are missing, it fails. | Follow the initial SSL bootstrap steps in `deployment.md` (start HTTP-only, run certbot, restart NGINX). |
| **Redirect Loop (ERR_TOO_MANY_REDIRECTS)** | NGINX is redirecting HTTP to HTTPS, but the proxy target (app) is redirecting back, or Cloudflare/CDN SSL settings are incorrect (e.g., set to "Flexible"). | Ensure CDN SSL is set to "Full (Strict)". Verify NGINX `X-Forwarded-Proto` headers are correctly passing the scheme to FastAPI. |
