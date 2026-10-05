FROM debian:bookworm

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        php8.2-cli \
        php8.2-mysql \
        php8.2-mbstring \
        curl \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/adminer && \
    curl -L -o /var/www/adminer/index.php \
        https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php && \
    chown -R www-data:www-data /var/www/adminer

WORKDIR /var/www/adminer

EXPOSE 8080

ENTRYPOINT ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
