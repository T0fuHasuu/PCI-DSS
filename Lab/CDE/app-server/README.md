# 1. Project Structure

```text
hello-fastapi/
├── app/
│   └── main.py
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── .dockerignore
```

---

# 2. Create the FastAPI App

## `app/main.py`

```python
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
async def home():
    return """
    <html>
        <head>
            <title>Hello</title>
            <style>
                body {
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    font-family: Arial;
                    background-color: #111;
                    color: white;
                }
            </style>
        </head>
        <body>
            <h1>Hello World</h1>
        </body>
    </html>
    """
```

---

# 3. Python Dependencies

## `requirements.txt`

```txt
fastapi
uvicorn[standard]
```

---

# 4. Hardened Dockerfile

## `Dockerfile`

```dockerfile
# Use lightweight official Python image
FROM python:3.12-alpine

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Prevent Python cache files
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Copy dependency file first
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app ./app

# Change ownership
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose internal port
EXPOSE 9090

# Run FastAPI securely
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9090"]
```

---

# 5. Docker Ignore

## `.dockerignore`

```text
__pycache__
*.pyc
*.pyo
*.pyd
.env
.git
```

---

# 6. Docker Compose (Recommended)

## `docker-compose.yml`

```yaml
services:
  hello-fastapi:
    build: .
    container_name: hello-fastapi

    ports:
      - "9090:9090"

    restart: unless-stopped

    security_opt:
      - no-new-privileges:true

    cap_drop:
      - ALL

    read_only: true

    tmpfs:
      - /tmp

    mem_limit: 256m
    cpus: 0.50
```

---

# 7. Build and Deploy

Go inside the project folder:

```bash
cd hello-fastapi
```

Build:

```bash
docker compose build
```

Run:

```bash
docker compose up -d
```

Open browser:

```text
http://localhost:9090
```

---

# 8. When You Change Code

If you modify Python code:

```bash
docker compose up -d --build
```

This:

* rebuilds image
* recreates container
* applies changes

---

# 9. View Logs

```bash
docker compose logs -f
```

---

# 10. Stop Container

```bash
docker compose down
```

---

# 11. Basic Docker Hardening Explained

## Run as Non-Root

```dockerfile
USER appuser
```

Prevents attacker from getting root access inside container.

---

## Remove Linux Capabilities

```yaml
cap_drop:
  - ALL
```

Removes dangerous kernel privileges.

---

## Prevent Privilege Escalation

```yaml
security_opt:
  - no-new-privileges:true
```

Blocks processes from gaining more permissions.

---

## Read-Only Filesystem

```yaml
read_only: true
```

Attacker cannot modify files easily.

---

## Temporary Writable Space

```yaml
tmpfs:
  - /tmp
```

Allows temporary runtime files only in memory.

---

## Resource Limits

```yaml
mem_limit: 256m
cpus: 0.50
```

Prevents abuse or DoS consuming all host resources.

---

# 12. Extra Hardening Later (Advanced)

Later you can add:

* Reverse proxy:

  * Nginx
  * Traefik

* HTTPS/TLS

* Docker network segmentation

* Vulnerability scanning:

  * Trivy

* Image signing

* Read-only root filesystem

* Distroless containers

* AppArmor / SELinux

* Secrets management

---

# 13. Simple Mental Model

```text
FastAPI App
    ↓
Docker Image
    ↓
Docker Container
    ↓
Port 9090 exposed
    ↓
Browser accesses app
```

---

# 14. Important Security Note

Docker containers are NOT virtual machines.

If container escapes happen:

* weak kernel
* dangerous mounts
* privileged containers
* root user

the host can still be compromised.

Never run:

```bash
--privileged
```

unless absolutely required.
