#!/bin/bash
set -e

printenv | grep -E "^(MYSQL_|RETENTION_)" > /etc/environment

touch /var/log/cron.log

echo "[entrypoint] Esperando a MariaDB..."
ATTEMPTS=0
until mariadb-admin ping -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"$(cat /run/secrets/db_password)" --silent 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "${ATTEMPTS}" -ge 30 ]; then
        echo "[entrypoint] ERROR: MariaDB no responde"
        exit 1
    fi
    sleep 2
done

echo "[entrypoint] Copia inicial"
/usr/local/bin/backup.sh

echo "[entrypoint] Iniciando cron"
exec cron -f
