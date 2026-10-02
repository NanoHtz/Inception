# Developer documentation

How to set the project up, build it and work on it. For day-to-day operation
see `USER_DOC.md`.

## Setting up from scratch

The project has to run inside a Linux virtual machine. It was developed on
Debian 12 under VirtualBox, with no desktop environment installed: only the SSH
server and the standard system utilities.

You need Docker Engine and the Compose plugin, `make`, `openssl`, and sudo
rights. `make` in particular is not there by default on a minimal Debian, which
is easy to forget.

One thing worth getting right from the start: the Debian package `docker.io`
ships Compose version 1, the Python one invoked with a hyphen. This project
needs version 2, which comes from Docker's own repository:

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

Log out and back in for the group change to take effect, then check with
`docker compose version`. If it answers, you have v2.

Worth knowing: being in the `docker` group is effectively root, since any member
can mount the host filesystem inside a container. On a disposable development VM
that is an acceptable trade.

The domain also needs to resolve locally:

```bash
echo "127.0.0.1 fgalvez-.42.fr" | sudo tee -a /etc/hosts
```

After that it is just clone and build.

## Configuration

`srcs/.env` holds everything that is not sensitive and is versioned:
`DOMAIN_NAME`, the database name and user, the WordPress title and the two
account names with their emails, the FTP user, how many days backups are kept,
and `DATA_PATH`, the host directory all three volumes are backed by.

The administrator username must not contain `admin` or `administrator` in any
form. That is a hard requirement of the subject, not a style preference.

`secrets/` holds the five passwords and is excluded from version control. They
are generated automatically by `make` if they are absent, or on demand with
`make secrets`. Existing files are never overwritten. The `.example` templates
are versioned so the expected structure is visible in a fresh clone.

The FTP password is generated without `/`, `+` or `=`. pure-pw receives it
through a pipe when the container first starts, and those characters turned out
to be unreliable there.

## Building and running

The Makefile targets are straightforward. `all` and `up` do the same thing:
generate secrets, create the data directories, build and start. `build` builds
without starting. `down`, `stop`, `start`, `logs` and `ps` do what they say.
`clean` takes everything down and prunes images and build cache. `fclean` goes
further and removes the volumes and the host data. `re` is `fclean` then `all`.

Two details in there are not obvious.

The Makefile passes `--env-file srcs/.env` explicitly. Where Compose looks for
`.env` by default depends on the version and on how it was invoked, and being
explicit removes that dependency entirely. If the file is not found,
`${DATA_PATH}` expands to an empty string and the volumes fail to mount, which
is a confusing way to discover the problem.

And `setup` runs before every `up` because the volumes use `driver_opts` with
`type: none`. That means Docker binds a directory that must already exist rather
than creating one, so a missing directory stops the container from starting.

For working directly with Compose rather than through the Makefile, the useful
one is:

```bash
docker compose -f srcs/docker-compose.yml --env-file srcs/.env config
```

It prints the fully resolved file with every variable expanded, which is the
fastest way to confirm `.env` is being read and that the YAML is valid.

## Poking at the running stack

The usual inspection commands all work: `docker ps`, `docker images`,
`docker network ls`, `docker volume ls`, `docker stats`.

To get inside a container, `docker exec -it <name> bash`. That works for
mariadb, wordpress, nginx, redis, backup and ftp. The adminer and static
containers are deliberately minimal and do not have much tooling, so
`docker logs` is the way with those.

To check that the right process is PID 1:

```bash
docker exec wordpress ps aux
```

The service itself must be PID 1. If a shell holds it instead, the entry point
is using the shell form and signals will never reach the service.

For the database:

```bash
docker exec -it mariadb mysql -u root -p"$(cat secrets/db_root_password.txt)"
```

WP-CLI is installed inside the WordPress container, so things like
`docker exec wordpress wp user list --allow-root --path=/var/www/html` work.

`docker volume inspect inception_mariadb_data` shows the host path backing the
volume in its `Options.device` field, and `docker network inspect
inception_inception` shows which containers are attached and at which addresses.

## Where the data lives

The database sits in `/home/fgalvez-/data/mariadb`, mounted at
`/var/lib/mysql`. The site files sit in `/home/fgalvez-/data/wordpress`, mounted
at `/var/www/html`. The backups go to `/home/fgalvez-/data/backup`, mounted at
`/backups`.

The WordPress volume is mounted by three containers, not one: by `wordpress`
which runs the PHP, by `nginx` which reads the static assets and serves them
without involving PHP at all, and by `ftp` which exposes the same files for
upload and download.

Redis has no volume on purpose. A cache must not survive a restart; the real
data is in MariaDB and Redis refills itself. The static site has none either,
since its content is baked into the image at build time and never changes at
runtime.

Persistence works because the entry points are idempotent. MariaDB checks
whether its database directory exists, WordPress checks for `wp-config.php`,
and both skip initialisation if the data is already there. You can watch it
happen:

```bash
make down && make
docker logs mariadb | head -3
```

The log should report that the database already exists rather than
initialising it again.

For a backup, the volumes are ordinary host directories, so a copy is enough:

```bash
sudo tar czf backup-$(date +%F).tar.gz -C /home/fgalvez- data
```

Though for a consistent database snapshot, `mysqldump` through the backup
container is better.

Finally, `make fclean` empties `/home/fgalvez-/data` and removes the volumes.
There is no undo.

## Changing something

Every service lives under `srcs/requirements/<service>/` with the same layout:
the `Dockerfile`, a `.dockerignore` controlling what enters the build context,
a `conf/` directory for configuration files copied into the image, and a
`tools/` directory for the entry point script where one exists. Bonus services
sit under `requirements/bonus/`.

PHP-FPM settings, including its port and the process manager, are in
`wordpress/conf/www.conf`. Where NGINX forwards PHP requests is the
`fastcgi_pass` line in `nginx/conf/nginx.conf`, and the TLS protocol versions
are a few lines above it. Database tuning and the bind address are in
`mariadb/conf/50-server.cnf`. Published ports are in the compose file, and
names and identifiers in `srcs/.env`.

For the bonus services: the cache size and eviction policy are in
`bonus/redis/conf/redis.conf`, the static site's content in
`bonus/static/site/` and its port in `bonus/static/conf/static.conf`, the
backup schedule in `bonus/backup/conf/backup.cron` with retention controlled by
`RETENTION_DAYS` in `.env`, and the FTP passive port range in both the entry
point and the compose file.

Configuration files are copied into the image with `COPY`, so changing one
means rebuilding: `make down && make`. Changes limited to `.env` or to the
compose file only need the containers recreated, since nothing is rebuilt.

As a worked example, moving PHP-FPM from port 9000 to something else means
changing `listen` in `www.conf`, updating `EXPOSE` in the Dockerfile to match
for consistency, and changing `fastcgi_pass` in the NGINX config to the same
port. Both sides have to agree or NGINX returns a 502, which is itself a useful
thing to know.

## Things that went wrong, and why

`missing separator` from make means spaces where a tab belongs. Recipe lines
need real tabs.

A container that exits immediately has usually daemonised instead of staying in
the foreground. Each service has its own flag for that.

Database authentication failing with what looks like the right password is
almost always the trailing newline. Files generated with `openssl` end with one,
so always read them with `$(cat file)`, which strips it. Passing the file
contents around any other way appends `\n` to the password.

A 502 from NGINX means PHP-FPM is unreachable: either the container is down or
the port in `fastcgi_pass` does not match the one in `www.conf`.

A build that hangs during `apt-get install` is waiting on an interactive prompt.
`DEBIAN_FRONTEND=noninteractive` on the install command prevents that.

pure-ftpd exiting with `421 Unable to switch capabilities` means the container
lacks the capabilities it needs to drop its own privileges. The service declares
`DAC_READ_SEARCH`, `SYS_NICE` and `AUDIT_WRITE` for exactly that reason. If FTP
connects but transfers hang instead, the passive port range is not published or
does not match what `pure-ftpd -p` was given.

A backup file of only a few bytes means the dump failed and gzip happily
compressed nothing. The script exits with an error when the output is under a
kilobyte, precisely so a silent failure cannot pass for a valid backup.

And if Redis reports an invalid drop-in, regenerate it with
`docker exec wordpress wp redis enable --allow-root --path=/var/www/html`.
