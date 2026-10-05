#!/bin/bash
set -e

DB_PASS=$(cat /run/secrets/db_password)
WP_ADMIN_PASS=$(cat /run/secrets/wp_admin_password)
WP_USER_PASS=$(cat /run/secrets/wp_user_password)

echo "[entrypoint] Esperando a que MariaDB acepte conexiones..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until mariadb-admin ping -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${DB_PASS}" --silent 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
        echo "[entrypoint] ERROR: MariaDB no responde tras ${MAX_ATTEMPTS} intentos"
        exit 1
    fi
    sleep 2
done
echo "[entrypoint] MariaDB disponible"

if [ ! -f /var/www/html/wp-config.php ]; then
    echo "[entrypoint] Primera ejecución: instalando WordPress"

    wp core download --allow-root --path=/var/www/html

    wp config create --allow-root --path=/var/www/html \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost="${MYSQL_HOST}"

    wp core install --allow-root --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    wp user create --allow-root --path=/var/www/html \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASS}"
    wp config set WP_REDIS_HOST "redis" --allow-root --path=/var/www/html
    wp config set WP_REDIS_PORT 6379 --raw --allow-root --path=/var/www/html
    wp config set WP_CACHE true --raw --allow-root --path=/var/www/html

    wp plugin install redis-cache --activate --allow-root --path=/var/www/html
    wp redis enable --allow-root --path=/var/www/html
    chown -R www-data:www-data /var/www/html
    echo "[entrypoint] WordPress instalado correctamente"
else
    echo "[entrypoint] WordPress ya instalado, se omite la instalación"
fi

exec php-fpm8.2 -F
