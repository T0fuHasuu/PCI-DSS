@echo off
setlocal
pushd "%~dp0.."

echo Removing all containers, networks, and persistent lab data...
docker compose down --remove-orphans --volumes
for %%C in (pos peri-fw dmz int-fw app kms db log-server) do docker rm -f %%C 2>nul
for %%N in (store_net dmz_net app_net kms_net db_net) do docker network rm pci-segmentation-core_%%N 2>nul

popd
echo Lab state removed. Run scripts\fresh-start.cmd to rebuild it.
