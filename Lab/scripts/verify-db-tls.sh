#!/bin/sh
set -eu

RESULT="$(
  PGSSLMODE=verify-full \
  PGSSLROOTCERT=/etc/lab/pki/ca.crt \
  PGSSLCERT=/etc/lab/pki/db-client.crt \
  PGSSLKEY=/etc/lab/pki/db-client.key \
  psql -h 10.100.30.10 -U cde_user -d cde_db -At -v ON_ERROR_STOP=1 -c \
    "SELECT CASE WHEN ssl AND version = 'TLSv1.2' THEN 'PASS' ELSE 'FAIL' END FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
)"

[ "$RESULT" = 'PASS' ] || {
  echo "PostgreSQL TLS verification: FAIL ($RESULT)" >&2
  exit 1
}

echo 'PostgreSQL TLS verification: PASS'
