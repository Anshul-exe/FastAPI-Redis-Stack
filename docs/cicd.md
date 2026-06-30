# CI/CD Pipeline

## Purpose

Documents the GitHub Actions pipeline that builds the application Docker image, publishes it to the GitHub Container Registry (GHCR), and deploys it to the production VPS on every push to `main`.

## Prerequisites

- Repository hosted on GitHub
- A running VPS with Docker, Docker Compose, and the repo cloned to `/opt/taskapi`
- GitHub Secrets configured (see Section 2)
- GHCR package visibility set to **Public** (see Section 5), or VPS configured to authenticate to GHCR (see alternative in Section 5)

---

## 1. Pipeline Overview

```
Push to main
     │
     ▼
┌─────────────────────────────────┐
│  Job 1: build-and-push          │
│                                 │
│  1. Checkout code               │
│  2. Log in to GHCR              │
│  3. Build Docker image          │
│     (context: repo root,        │
│      file: docker/app/          │
│             Dockerfile)         │
│  4. Push two tags:              │
│     • :latest                   │
│     • :<git-sha>                │
└────────────┬────────────────────┘
             │ on success
             ▼
┌─────────────────────────────────┐
│  Job 2: deploy                  │
│                                 │
│  SSH into VPS, then:            │
│  1. git pull origin main        │
│  2. docker compose pull         │
│  3. docker compose up -d        │
│     --remove-orphans            │
│  4. docker compose ps           │
└─────────────────────────────────┘
```

**Workflow file:** [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)

**Key design choices:**

| Choice | Rationale |
|--------|-----------|
| Two separate jobs | The VPS is only touched after the image is confirmed built and pushed. A failed build never triggers a deploy. |
| SHA tag alongside `:latest` | Enables precise rollback to any past commit without guessing (see Section 4). |
| `docker/build-push-action` with `cache-from/cache-to: type=gha` | GitHub Actions layer cache dramatically reduces build time for unchanged layers. |
| `set -euo pipefail` in SSH script | Any failed command on the VPS aborts the deploy immediately; partial deploys are never silently swallowed. |

---

## 2. Required GitHub Secrets

Navigate to: **GitHub → Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret name | What it is | How to obtain |
|-------------|-----------|--------------|
| `VPS_HOST` | Public IP address or hostname of the VPS | Copy from your VPS provider dashboard (e.g. `203.0.113.42` or `vps.example.com`) |
| `VPS_USER` | Linux username used to SSH into the VPS | The non-root deploy user you created (e.g. `deploy` or `ubuntu`) |
| `VPS_SSH_KEY` | **Private** SSH key whose public half is in `~/.ssh/authorized_keys` on the VPS | See below |

### Generating an SSH key pair for CI (if you don't have one)

Run this on your **local machine** (not the VPS):

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions_deploy -N ""
```

Copy the **public** key to the VPS:

```bash
ssh-copy-id -i ~/.ssh/github_actions_deploy.pub VPS_USER@VPS_HOST
```

Add the **private** key as the `VPS_SSH_KEY` secret:

```bash
cat ~/.ssh/github_actions_deploy
# Copy the entire output (including -----BEGIN ... and -----END ... lines)
# Paste it as the value of the VPS_SSH_KEY secret in GitHub
```

> [!CAUTION]
> Never commit the private key to the repository. It belongs only in GitHub Secrets and in `~/.ssh/` on your local machine.

---

## 3. Triggering a Deployment

A deployment starts automatically on every push to the `main` branch:

```bash
git add .
git commit -m "feat: your change description"
git push origin main
```

**To trigger without a code change** (e.g. to force a redeploy):

```bash
git commit --allow-empty -m "chore: trigger redeploy"
git push origin main
```

You can also re-run the most recent workflow run manually via:  
**GitHub → Actions → `Build, Push, and Deploy` → (select latest run) → Re-run all jobs**

---

## 4. Rolling Back a Deployment

### Option A — Re-run a previous workflow run (recommended for most cases)

1. Go to **GitHub → Actions → `Build, Push, and Deploy`**
2. Find the last known-good run in the list
3. Click into it → **Re-run all jobs**

This re-executes the exact same build and deploy steps that produced the last good image.

### Option B — Manually pin a specific SHA image on the VPS

Each successful build pushes a SHA-tagged image:
`ghcr.io/<owner>/taskapi:<git-sha>`

To roll back to a specific commit on the VPS:

```bash
ssh VPS_USER@VPS_HOST

cd /opt/taskapi

# Identify the SHA of the last known-good commit
git log --oneline -10

# Edit the app service image in the prod compose file to pin the SHA tag
# (or pass it inline via DOCKER_IMAGE env var if your compose file supports it)

# Pull the specific image
docker pull ghcr.io/<owner>/taskapi:<good-sha>

# Retag it as :latest so compose picks it up
docker tag ghcr.io/<owner>/taskapi:<good-sha> ghcr.io/<owner>/taskapi:latest

# Restart the app service
docker compose -f compose/docker-compose.prod.yml up -d app
```

> [!NOTE]
> This is a manual operation. The next push to `main` will overwrite `:latest` again. If you need to hold a rollback, revert the bad commit in Git first, then push the revert to `main` to let the pipeline deploy cleanly.

---

## 5. GHCR Image Visibility

The VPS needs to pull the image from GHCR. There are two options:

### Option A — Make the package public (simplest, recommended for open-source projects)

1. Go to **GitHub → Your profile → Packages → taskapi**
2. Click **Package settings**
3. Under **Danger Zone**, change visibility to **Public**

The VPS can then pull without any authentication:

```bash
docker pull ghcr.io/<owner>/taskapi:latest
```

### Option B — Keep the package private and authenticate the VPS

On the VPS, create a GitHub **Personal Access Token (classic)** with `read:packages` scope, then log Docker in:

```bash
echo "<YOUR_PAT>" | docker login ghcr.io -u <github-username> --password-stdin
```

> [!TIP]
> Store the PAT in a file (e.g. `/root/.ghcr_token`) with `chmod 600`, and reference it from a cron job or deploy script to re-authenticate if the token changes.

---

## 6. Monitoring a Deployment

### Via GitHub Actions UI

1. Go to **GitHub → Actions → `Build, Push, and Deploy`**
2. Click the in-progress or completed run
3. Expand **Job 1 (Build & Push)** and **Job 2 (Deploy)** to see step-by-step logs
4. The final step of Job 2 (`docker compose ps`) prints the live container state on the VPS — confirm all services show `running`

### Via the VPS directly

```bash
ssh VPS_USER@VPS_HOST

# Check container states
docker compose -f /opt/taskapi/compose/docker-compose.prod.yml ps

# Tail the app logs for errors after deploy
docker compose -f /opt/taskapi/compose/docker-compose.prod.yml logs --tail=50 --follow app

# Hit the health endpoint
curl -f https://stack.anshulfml.me/health
```

---

## 7. Troubleshooting

| Symptom | Likely cause | Resolution |
|---------|-------------|------------|
| Job 1 fails at "Log in to GHCR" | `GITHUB_TOKEN` lacks package write permissions | Ensure `permissions: packages: write` is set in the workflow job (already configured) |
| Job 1 fails at "Build and push" | Dockerfile syntax error or failing build step | Check the build log; fix the Dockerfile and push again |
| Job 2 fails at "Deploy via SSH" | Wrong secret value, VPS unreachable, or SSH key not in `authorized_keys` | Verify `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` secrets; test SSH manually from your machine |
| Job 2 succeeds but app is down | Deploy succeeded but app container crashed on startup | SSH to VPS; run `docker compose logs app` to see startup errors |
| `docker compose pull` fails on VPS | GHCR image is private and VPS is not authenticated | Set package to public (Section 5 Option A) or log Docker in to GHCR on the VPS (Option B) |
| Pipeline never triggers | Push was not to `main` branch | Confirm your branch name; the trigger is `branches: [main]` exactly |
