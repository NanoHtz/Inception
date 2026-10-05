FROM debian:bookworm

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        pure-ftpd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 21 30000-30009

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
