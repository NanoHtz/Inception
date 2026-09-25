#!/bin/bash
set -e

mkdir -p /etc/pure-ftpd/conf
mkdir -p /var/www/html

if [ ! -f /etc/pure-ftpd/pureftpd.passwd ]; then
    PASS=$(cat /run/secrets/ftp_password)
    printf '%s\n%s\n' "${PASS}" "${PASS}" > /tmp/pw
    echo "[entrypoint] Creando usuario virtual ${FTP_USER}"
    pure-pw useradd "${FTP_USER}" \
        -u www-data -g www-data \
        -d /var/www/html \
        -f /etc/pure-ftpd/pureftpd.passwd \
        -m < /tmp/pw
    rm -f /tmp/pw
    echo "[entrypoint] Usuario virtual creado"
else
    echo "[entrypoint] Usuario virtual ya existente"
fi

echo "[entrypoint] Iniciando pure-ftpd"
exec pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -A \
    -p 30000:30009 \
    -P 127.0.0.1
