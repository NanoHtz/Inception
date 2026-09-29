# Developer documentation

This document describes how to set up, build and work on the project. For
day-to-day operation, see `USER_DOC.md`.

---

## 1. Setting up the environment from scratch

### Prerequisites

The project must run inside a Linux virtual machine. It was developed on Debian
12 (bookworm) under VirtualBox.

Required on the machine:

| Requirement | Why |
|---|---|
| Docker Engine | Builds and runs the containers |
| Docker Compose plugin (v2) | The project uses `docker compose`, not `docker-compose` |
| `make` | Not installed by default on a minimal Debian |
| `openssl` | Generates the secret files |
| `sudo` | Needed by `make fclean` to remove root-owned volume data |

Note that the `docker.io` package shipped by Debian provides Compose v1, invoked
with a hyphen. This project requires v2, which comes from Docker's own
repository:

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg make
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian bookworm stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
```

Log out and back in for the group change to apply. Verify:

```bash
docker compose version
```

Note that membership of the `docker` group is equivalent to root privileges, as
any member can mount the host filesystem inside a container. This is acceptable
on a disposable development VM.

### Host configuration

The domain must resolve to the loopback address:

```bash
echo "127.0.0.1 fgalvez-.42.fr" | sudo tee -a /etc/hosts
```

### Clone and run

```bash
git clone <repository-url> inception
cd inception
make
```

### Configuration files

**`srcs/.env`** holds non-sensitive configuration and is versioned:

| Variable | Purpose |
|---|---|
| `DOMAIN_NAME` | Site domain, used by NGINX and by WordPress |
| `MYSQL_DATABASE` | Database name |
| `MYSQL_USER` | Database user WordPress connects with |
| `WP_TITLE` | Site title |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL` | WordPress administrator |
| `WP_USER`, `WP_USER_EMAIL` | Second WordPress user |
| `FTP_USER` | FTP account name |
| `RETENTION_DAYS` | Days a database dump is kept before rotation |
| `DATA_PATH` | Host directory backing every volume |

The administrator username must not contain `admin` or `administrator` in any
form; this is a hard requirement of the subject.

**`secrets/`** holds the five passwords (MariaDB root, MariaDB application user,
WordPress administrator, WordPress author, FTP account) and is excluded from
version control. The files are generated automatically by `make` if they are
absent:

```bash
make secrets
```

Existing files are never overwritten. Template files with the `.example`
extension are versioned so that the expected structure is visible in a fresh
clone.

Note that `ftp_password.txt` is generated without `/`, `+` or `=`. pure-pw
receives the password through a pipe when the container first starts, and those
characters proved unreliable there.

---

## 2. Building and launching

### Makefile targets

| Target | Command it runs |
|---|---|
| `all` / `up` | Generates secrets, creates data directories, `docker compose up -d --build` |
| `secrets` | Creates any missing secret file |
| `setup` | Creates the host data directories |
| `build` | Builds the images without starting them |
| `down` | `docker compose down` |
| `stop` / `start` | Pauses and resumes the containers |
| `logs` | Follows all logs |
| `ps` | Container state |
| `clean` | `down` plus `docker system prune -af` |
| `fclean` | `clean` plus volume removal and deletion of host data |
| `re` | `fclean` then `all` |

### Why the Makefile passes `--env-file` explicitly

Where Compose looks for `.env` by default depends on the Compose version and on
how it is invoked. Passing the path explicitly removes that dependency, so the
Makefile behaves the same whatever the version and whatever directory it is
run from:

```makefile
COMPOSE = docker compose -f srcs/docker-compose.yml --env-file srcs/.env
```

If `.env` were not found, `${DATA_PATH}` would expand to an empty string and
the volumes would fail to mount.

### Why `setup` creates the directories

The volumes use `driver_opts` with `type: none`, which means Docker binds an
existing host directory rather than creating one. If the directory is missing,
the container fails to start. `setup` runs before every `up` for that reason.

### Useful Compose commands

```bash
docker compose -f srcs/docker-compose.yml --env-file srcs/.env config
docker compose -f srcs/docker-compose.yml --env-file srcs/.env build nginx
docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d wordpress
docker compose -f srcs/docker-compose.yml --env-file srcs/.env restart nginx
```

`config` is particularly useful: it prints the fully resolved file with all
variables expanded, which is the quickest way to confirm that `.env` is being
read.

---

## 3. Managing containers and volumes

### Inspection

```bash
docker ps                      # running containers
docker ps -a                   # including stopped ones
docker images                  # built images
docker network ls              # networks
docker volume ls               # volumes
docker stats                   # live resource usage
```

### Entering a container

```bash
docker exec -it mariadb bash
docker exec -it wordpress bash
docker exec -it nginx bash
docker exec -it redis bash
docker exec -it backup bash
docker exec -it ftp bash
```

Note that `adminer` and `static` ship without a shell's usual tooling; use
`docker logs` for them instead.

### Checking PID 1

```bash
docker exec wordpress ps aux
```

The service itself must appear with PID 1. If a shell holds PID 1 instead, the
entry point is using the shell form and signals will not reach the service.

### Database access

```bash
docker exec -it mariadb mysql -u root -p"$(cat secrets/db_root_password.txt)"
```

Or as the application user:

```bash
docker exec -it mariadb mysql -u "$(grep MYSQL_USER srcs/.env | cut -d= -f2)" \
  -p"$(cat secrets/db_password.txt)" wordpress
```

### WP-CLI

WP-CLI is installed inside the WordPress container:

```bash
docker exec wordpress wp core version --allow-root --path=/var/www/html
docker exec wordpress wp user list --allow-root --path=/var/www/html
docker exec wordpress wp plugin list --allow-root --path=/var/www/html
```

### Volume inspection

```bash
docker volume inspect inception_mariadb_data
```

The `Options.device` field shows the host path backing the volume.

### Network inspection

```bash
docker network inspect inception_inception
```

Shows which containers are attached and their addresses on the bridge.

---

## 4. Where the data lives and how it persists

### Layout

| Volume | Mount point in container | Host directory |
|---|---|---|
| `mariadb_data` | `/var/lib/mysql` | `/home/fgalvez-/data/mariadb` |
| `wordpress_data` | `/var/www/html` | `/home/fgalvez-/data/wordpress` |
| `backup_data` | `/backups` | `/home/fgalvez-/data/backup` |

`wordpress_data` is mounted by **three** containers: by `wordpress`, which runs
the PHP code; by `nginx`, which needs to read the static assets and serve them
directly without involving PHP; and by `ftp`, which exposes those same files for
upload and download.

Redis deliberately has no volume. A cache must not survive a restart: the
authoritative data lives in MariaDB, and Redis simply refills itself. The static
site has no volume either, since its content is baked into the image at build
time and never changes at runtime.

### How persistence works

Both entry points are idempotent and detect existing data:

- `mariadb` checks whether `/var/lib/mysql/${MYSQL_DATABASE}` exists. If it does,
  initialisation is skipped.
- `wordpress` checks whether `/var/www/html/wp-config.php` exists. If it does,
  installation is skipped.

This is what allows the containers to be destroyed and recreated freely. It can
be verified directly:

```bash
make down && make
docker logs mariadb | head -3
```

The log should report that the database already exists.

### Backing up

Since both volumes are backed by ordinary host directories, a backup is a plain
copy:

```bash
sudo tar czf backup-$(date +%F).tar.gz -C /home/fgalvez- data
```

For a consistent database dump, prefer:

```bash
docker exec mariadb mysqldump -u root -p"$(cat secrets/db_root_password.txt)" \
  wordpress > wordpress-backup.sql
```

### What `fclean` destroys

`make fclean` removes the volumes and empties `/home/fgalvez-/data`. Both the
database and the site content are lost. There is no undo.

---

## 5. Modifying a service

The three services follow the same layout under `srcs/requirements/<service>/`:

| Path | Contents |
|---|---|
| `Dockerfile` | Image definition |
| `.dockerignore` | Files excluded from the build context |
| `conf/` | Configuration files copied into the image |
| `tools/` | Entry point script, where applicable |

### Where to change what

| Change | File |
|---|---|
| PHP-FPM port or process manager settings | `wordpress/conf/www.conf` |
| Where NGINX forwards PHP requests | `nginx/conf/nginx.conf` (`fastcgi_pass`) |
| Published port | `srcs/docker-compose.yml` (`ports`) |
| TLS protocol versions | `nginx/conf/nginx.conf` (`ssl_protocols`) |
| Database bind address or tuning | `mariadb/conf/50-server.cnf` |
| Database or user names | `srcs/.env` |
| Cache size or eviction policy | `bonus/redis/conf/redis.conf` |
| Static site content | `bonus/static/site/` |
| Static site port | `bonus/static/conf/static.conf` and the compose file |
| Backup schedule | `bonus/backup/conf/backup.cron` |
| Backup retention | `RETENTION_DAYS` in `srcs/.env` |
| FTP passive port range | `bonus/ftp/tools/entrypoint.sh` and the compose file |

### Applying a change

Configuration files are baked into the images with `COPY`, so editing one
requires a rebuild:

```bash
make down
make
```

A change limited to `.env` or to the compose file only needs a restart, since
nothing is rebuilt.

### Worked example: changing the PHP-FPM port

1. In `wordpress/conf/www.conf`, change `listen = 0.0.0.0:9000` to the new port.
2. In `wordpress/Dockerfile`, update `EXPOSE` to match (documentation only, but
   keep it consistent).
3. In `nginx/conf/nginx.conf`, change `fastcgi_pass wordpress:9000;` to the same
   port.
4. Rebuild with `make down && make`.
5. Verify with `curl -kI https://fgalvez-.42.fr`, which should still return 200.

Both sides must be changed together; the two files must agree or NGINX will
return a 502.

---

## 6. Troubleshooting

**`missing separator` from make.** Recipe lines require a tab character, not
spaces.

**`${DATA_PATH}` not expanded.** Compose is not finding `.env`. Run through the
Makefile, or pass `--env-file srcs/.env` explicitly.

**Container exits immediately.** Read `docker logs <name>`. The usual causes are
a service that daemonised instead of staying in the foreground, or a missing
directory.

**Database authentication fails with a correct-looking password.** Secret files
generated with `openssl` end with a newline. Always read them with `$(cat file)`,
which strips trailing newlines; passing the file content directly appends `\n` to
the password.

**NGINX returns 502.** PHP-FPM is unreachable. Check that the WordPress container
is running and that the port in `fastcgi_pass` matches the one in `www.conf`.

**Build hangs during `apt-get install`.** A package is waiting on an interactive
prompt. Ensure `DEBIAN_FRONTEND=noninteractive` is set on the install command.

**pure-ftpd exits with `421 Unable to switch capabilities`.** The container is
missing the capabilities pure-ftpd needs to drop its own privileges. The service
declares `cap_add: [DAC_READ_SEARCH, SYS_NICE, AUDIT_WRITE]` for that reason.

**FTP connects but data transfers hang.** The passive port range must be
published in the compose file and match the range passed to `pure-ftpd -p`.

**The backup file is suspiciously small.** The dump failed. The script exits
with an error when the output is under 1 kB, precisely so that a silent failure
does not pass for a valid backup. Check that the database user in `srcs/.env`
can reach `mariadb`.

**Redis reports `Drop-in: Invalid`.** The `object-cache.php` drop-in is missing
or outdated. Regenerate it with
`docker exec wordpress wp redis enable --allow-root --path=/var/www/html`.
