FROM debian:bookworm

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nginx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY conf/static.conf /etc/nginx/conf.d/default.conf
COPY site/ /var/www/static/

RUN rm -f /etc/nginx/sites-enabled/default && \
    chown -R www-data:www-data /var/www/static

EXPOSE 8081

ENTRYPOINT ["nginx", "-g", "daemon off;"]
