#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

printf '%-28s %-18s %-8s\n' 'DOCKER NETWORK' 'SUBNET' 'INTERNAL'
for net in store_net dmz_net app_net kms_net db_net ui_net security_tools_net; do
  docker network inspect "pci-segmentation-core_${net}" \
    --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Internal}}' \
  | awk '{printf "%-28s %-18s %-8s\n", $1, $2, $3}'
done

printf '\n%-14s %-60s\n' 'CONTAINER' 'NETWORK=IP'
for c in log-server antimalware pos peri-fw dmz int-fw app kms db demo-api demo-ui; do
  docker inspect -f '{{.Name}} {{range $name,$net := .NetworkSettings.Networks}}{{printf "%s=%s " $name $net.IPAddress}}{{end}}' "$c" \
  | sed 's#^/##' \
  | awk '{$1=sprintf("%-14s",$1); print}'
done
