FROM debian:bookworm

ARG DOMAIN_NAME=fgalvez-.42.fr

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nginx \
        openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=42/OU=42/CN=${DOMAIN_NAME}"

COPY conf/nginx.conf /etc/nginx/conf.d/default.conf

RUN rm -f /etc/nginx/sites-enabled/default

EXPOSE 443

ENTRYPOINT ["nginx", "-g", "daemon off;"]
