# Dashboard evidence-route repair

## Confirmed root cause

The dashboard workflow successfully completed payment health and transaction creation. It then requested:

`GET /transaction/<tx_id>/evidence`

The DMZ returned `404` with `upstream=-`, proving Nginx rejected the request before it reached the internal firewall or application. The existing DMZ rules allowed `/transaction/<id>` but omitted `/transaction/<id>/evidence`.

## Apply

Extract over `D:\Workspaces\Sandbox\V6`, then run:

```bat
cd /d D:\Workspaces\Sandbox\V6
scripts\repair-dashboard-evidence-route.cmd
```

The script rebuilds only POS-agent, recreates DMZ and POS-agent, validates Nginx, and requires a completed end-to-end dashboard transaction before reporting success.


docker compose exec -T log-server sh -lc "tail -f /var/log/remote/perimeter-firewall.log /var/log/remote/internal-firewall.log /var/log/remote/cde-transactions.log"