FROM debian:bookworm

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        redis-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf

RUN chown -R redis:redis /etc/redis

EXPOSE 6379

ENTRYPOINT ["redis-server", "/etc/redis/redis.conf"]
