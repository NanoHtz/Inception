#!/bin/bash
set -eo pipefail

DB_PASS=$(cat /run/secrets/db_password)
STAMP=$(date +%Y%m%d-%H%M%S)
TARGET="/backups/${MYSQL_DATABASE}-${STAMP}.sql.gz"

echo "[backup] $(date '+%F %T') Iniciando copia de ${MYSQL_DATABASE}"

mariadb-dump -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${DB_PASS}" \
    --single-transaction \
    --databases "${MYSQL_DATABASE}" | gzip > "${TARGET}"

if [ ! -s "${TARGET}" ] || [ "$(stat -c%s "${TARGET}")" -lt 1000 ]; then
    echo "[backup] ERROR: la copia está vacía o es sospechosamente pequeña"
    rm -f "${TARGET}"
    exit 1
fi
echo "[backup] Copia creada: ${TARGET} ($(du -h "${TARGET}" | cut -f1))"

DELETED=$(find /backups -name "*.sql.gz" -mtime +"${RETENTION_DAYS}" -print -delete | wc -l)
if [ "${DELETED}" -gt 0 ]; then
    echo "[backup] Eliminadas ${DELETED} copias con más de ${RETENTION_DAYS} días"
fi
