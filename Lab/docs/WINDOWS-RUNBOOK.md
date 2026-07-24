# Windows Docker Desktop Runbook

## Supported setup

- Windows 10/11
- Docker Desktop with WSL 2 backend
- Linux containers
- Docker Compose v2

Do not switch Docker Desktop to Windows containers. The lab uses Linux
`iptables`, WireGuard, Nginx, Vault, PostgreSQL, and `/dev/net/tun`.

## Start from Command Prompt

```cmd
cd /d D:\path\to\PCI-Segmentation-Lab
lab.cmd up
```

The first run downloads base images and may take several minutes. The generated
`.env` and `secrets` stay on the local workstation and are excluded from the
release archive.

## Normal operations

```cmd
lab.cmd status
lab.cmd verify
lab.cmd logs
lab.cmd down
```

Start the optional topology markers only when needed:

```cmd
lab.cmd topology
```

## Configuration-only check

```cmd
lab.cmd config
```

This checks Compose syntax and interpolation without starting containers.

## Common failures

### Docker Desktop is not running

Start Docker Desktop and wait until the engine reports ready, then rerun:

```cmd
lab.cmd up
```

### `/dev/net/tun` is unavailable

Confirm Docker Desktop uses the WSL 2 backend and Linux containers. Restart
Docker Desktop after changing the backend.

### Port 8443 is already in use

Edit `.env` and change:

```text
DEMO_UI_PORT=9443
```

Then open `https://localhost:9443`.

### A service is unhealthy

```cmd
docker compose ps
docker compose logs --tail=200 SERVICE_NAME
```

Correct the reported service; do not disable its health check or firewall rule
to force startup.

### Certificates no longer match

This replaces the local lab PKI and requires the containers to be stopped:

```cmd
lab.cmd regenerate-secrets --yes
lab.cmd up
```

### Clean rebuild

This deletes PostgreSQL, Vault, log, and anti-malware volumes:

```cmd
lab.cmd reset --yes
lab.cmd up
```

Do not use `reset --yes` if the local lab data must be preserved.

## Windows file handling

Keep shell scripts and Linux configuration files with LF line endings. The
included `.gitattributes` enforces this when Git is used. Run the project from a
local NTFS path shared with Docker Desktop; avoid cloud-synchronized folders
during live demonstrations.
