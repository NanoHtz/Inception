FROM debian:bookworm

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        mariadb-client \
        cron \
        gzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY tools/backup.sh /usr/local/bin/backup.sh
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY conf/backup.cron /etc/cron.d/backup

RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh && \
    chmod 0644 /etc/cron.d/backup && \
    mkdir -p /backups

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
