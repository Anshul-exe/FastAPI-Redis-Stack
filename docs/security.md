# Security Considerations

## Implemented Security Measures
- **Non-root Container Execution**: The FastAPI `app` Dockerfile creates an `appuser` and drops root privileges before executing the application.
- **Internal Docker Network**: `postgres`, `redis`, and `app` containers do not publish ports to the host machine. They are completely inaccessible from the public internet and communicate exclusively over the isolated `backend_net` bridge network.
- **UFW Firewall**: The VPS firewall is configured to implicitly deny all incoming traffic, explicitly allowing only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS).
- **Security Headers**: NGINX enforces HSTS, prevents clickjacking (`X-Frame-Options`), stops MIME sniffing (`X-Content-Type-Options`), and applies a basic Content Security Policy.
- **Rate Limiting**: The FastAPI middleware enforces a configurable request limit per IP address, backed by Redis, to mitigate brute force attempts and volumetric abuse.
- **Secret Management**: No secrets (database passwords, API keys) are committed to the Git repository. `.gitignore` explicitly ignores `.env` files. In production, secrets are provisioned via GitHub Actions securely.

## Known Limitations and Accepted Risks
- **Single Point of Failure (SPOF)**: The architecture relies on a single VPS node. A hardware failure at the hosting provider will result in downtime. This is an accepted risk for a $0 budget architecture.
- **No Web Application Firewall (WAF)**: NGINX provides basic security headers but does not inspect traffic payloads for SQL injection, XSS, or other Layer 7 attacks like a dedicated WAF (e.g., AWS WAF, Cloudflare WAF) would.
- **Self-Managed Certificates**: Relying on Certbot and Let's Encrypt requires the VPS to manage its own certificate lifecycle, unlike managed load balancers (e.g., AWS ALB) which abstract this completely.
- **No Database Encryption at Rest**: Unless the underlying VPS block storage is encrypted by the provider, Postgres data is not encrypted at rest.

## SSH Hardening Recommendations (Manual Steps)
To further secure the VPS, the operator should manually harden the SSH daemon (`/etc/ssh/sshd_config`):
1. **Disable Password Authentication**: Ensure `PasswordAuthentication no` is set so only SSH keys can be used.
2. **Disable Root Login**: Ensure `PermitRootLogin no` is set.
3. **Change Default Port**: Move SSH off port 22 to reduce log spam from automated scanners. (Remember to update UFW rules if you do this).
4. Restart SSH daemon: `sudo systemctl restart ssh`.

## What is NOT Implemented and Why
- **HashiCorp Vault / External Secret Stores**: Too complex and resource-intensive for a single-node setup. Environment variables via `.env` are standard and adequate for this scale.
- **mTLS (Mutual TLS) between microservices**: Since all containers run on a single host inside an isolated Docker bridge network, internal traffic does not traverse a physical network. The overhead of managing mTLS (e.g., via Istio or Linkerd) is unnecessary.
- **Kubernetes / Swarm**: Out of scope for a single-service $0 budget architecture. Docker Compose provides all necessary orchestration.
