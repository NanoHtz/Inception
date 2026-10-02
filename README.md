*This project has been created as part of the 42 curriculum by fgalvez-.*

# Inception

## Description

Inception builds a small web infrastructure from scratch using Docker and Docker
Compose, running inside a dedicated virtual machine. The result is a WordPress
site served over HTTPS, with every piece of the stack isolated in its own
container and every image built from a hand-written Dockerfile.

Three services make up the mandatory part. NGINX sits in front as the only way
in, listening on port 443 and terminating TLS. Behind it, WordPress runs on
PHP-FPM with no web server of its own. MariaDB stores everything and is only
reachable from inside the Docker network.

Five more services were added as the bonus part: Redis caches database queries
for WordPress, Adminer gives a web interface to the database, a small static
site is served by its own NGINX, an FTP server exposes the WordPress files, and
a backup service dumps the database on a schedule.

Everything is built on Debian 12, which is the penultimate stable release as
the subject requires. No ready-made images are pulled from Docker Hub beyond
the official Debian base.

## Instructions

You need a Linux virtual machine with Docker Engine, the Docker Compose plugin
(version 2, invoked as `docker compose` without a hyphen), `make`, and sudo
rights so the data directories can be created under your home.

Clone the repository, point the domain at your own machine, and build:

```bash
git clone <repository-url> inception
cd inception
echo "127.0.0.1 fgalvez-.42.fr" | sudo tee -a /etc/hosts
make
```

That single `make` generates the secret files if they are missing, creates the
directories the volumes need, builds the eight images and starts everything.
The first run takes a few minutes; on a slow network it can take considerably
longer, since roughly 250 MB of packages have to come down.

Then open `https://fgalvez-.42.fr`. The certificate is self-signed, so the
browser will complain the first time and you have to accept it.

The bonus services are not behind NGINX, since the subject allows extra ports
for them. Adminer listens on 8080, the static site on 8081, and the FTP server
on port 21 with a passive range from 30000 to 30009. Only the mandatory
infrastructure is restricted to port 443.

Besides `make`, the Makefile has `down` to stop and remove the containers,
`stop` and `start` to pause and resume without removing anything, `logs` to
follow everything at once, `ps` for the current state, `clean` to prune images
and build cache, and `re` for a full rebuild.

There is also `fclean`, which removes the volumes and wipes
`/home/fgalvez-/data`. That one destroys the database and the site content for
good, so it is only there to start over from nothing.

## Project description

### How Docker is used here

Each service gets its own Dockerfile and its own container. None of them is
kept alive by a trick: every entry point ends by handing the process over to
the real service running in the foreground, so the service itself becomes PID 1
and receives signals directly.

MariaDB initialises its data directory on the first run using
`mysqld --bootstrap`, which reads SQL from standard input, executes it and
exits without ever opening a port. Then the script execs `mysqld`. WordPress
waits for the database to actually answer before doing anything, installs
itself with WP-CLI, and execs `php-fpm8.2 -F`. NGINX generates its certificate
at build time and runs with `daemon off`. Redis runs with `daemonize no` and no
persistence at all. The backup container runs `cron -f`, which is a real daemon
in foreground mode rather than a loop. pure-ftpd uses virtual users, so no PAM
or system account is involved.

All the entry points are idempotent. They check whether the data is already
there and skip the setup if it is, which is what makes the whole stack survive
a reboot of the virtual machine.

### Layout

The Makefile sits at the root, next to the documentation and the `.gitignore`.
Credentials live in `secrets/`, which is excluded from version control.
Everything else is under `srcs/`: the `.env` file with the non-sensitive
configuration, the compose file, and a `requirements/` directory holding one
folder per service, each with its Dockerfile, its `.dockerignore`, its
configuration files and its entry point script. The bonus services follow the
same layout inside `requirements/bonus/`.

That structure is not decoration. Because `build.context` points at each
service's own folder, only that folder is sent to the Docker daemon when
building. If the context were the repository root, every build would ship the
whole project, `secrets/` included.

### Choices worth explaining

**Debian rather than Alpine.** Both are allowed. Debian uses glibc instead of
musl, its PHP and MariaDB packages follow the layout almost every piece of
documentation assumes, and there is simply less to debug. The trade-off is
size, since the Alpine base is around 5 MB against Debian's 75, but size is not
what this project is graded on.

**Bookworm rather than Trixie.** The subject asks for the penultimate stable
release, and Debian 13 is current. Worth noting that even a fixed tag is not
immutable: halfway through the project the digest behind `debian:bookworm`
changed because Debian published a security update. For strict reproducibility
the digest itself would have to be pinned.

**Explicit image tags.** Every image is tagged `<service>:inception` rather
than defaulting to `latest`, which the subject forbids and which would make
builds non-reproducible anyway.

**Waiting for the database in the entry point.** `depends_on` only orders
container startup. Compose expands it to `condition: service_started`, which
says nothing about whether the service inside is ready to answer. Both WordPress
and the backup container poll MariaDB with a bounded retry loop instead.

**pure-ftpd rather than vsftpd.** vsftpd leans heavily on privilege-separation
machinery that collides with what Docker already applies, and it fails with
errors that tell you nothing useful. pure-ftpd works once three capabilities are
granted: `DAC_READ_SEARCH`, `SYS_NICE` and `AUDIT_WRITE`. That is the minimal
set it needs to drop its own privileges, and granting exactly those instead of
`privileged: true` leaves the rest of the container isolation untouched.

**Backups as the free-choice service.** A volume keeps data safe when a
container is destroyed. It does nothing against an accidental deletion, a
corruption or plain human error. Those are different problems, and running
`make fclean` a few times during development makes the difference very
concrete. The backup service dumps the database with `mariadb-dump`, compresses
it and rotates old copies. The script uses `set -o pipefail` and checks the
resulting file size, because `set -e` alone misses a failure in the middle of a
pipeline, and a backup that fails quietly is worse than no backup at all.

### Virtual machines and containers

A virtual machine virtualises hardware. A hypervisor emulates a whole machine
and boots a complete operating system inside it, kernel included. That is why
installing one takes minutes and why it weighs gigabytes.

A container virtualises nothing. Its processes run straight on the host kernel.
What gets isolated is their view of the system, through namespaces for what a
process can see (its own process table, its own network interfaces, its own
filesystem) and cgroups for what it can consume. That is why a container starts
in milliseconds and weighs megabytes.

Neither is better in the abstract. Containers win on packaging, density and
startup time. Virtual machines win when you need strong isolation between
parties that do not trust each other, or a different kernel entirely. This
project uses both at once: containers inside a virtual machine.

### Secrets and environment variables

Environment variables leak in several directions. They show up in
`docker inspect`, they end up in an image layer if they came from an `ENV`
instruction, any process in the container can read them from `/proc`, and every
child process inherits them.

Docker secrets are files mounted read-only under `/run/secrets/`, and only
inside the containers that explicitly ask for them. None of the above applies.

One thing worth being precise about: with plain Compose, as opposed to Swarm, a
file-based secret is literally the host file mounted read-only. It is not
encrypted and it does not live in memory. Protecting the host file is therefore
part of the design, which is why everything in `secrets/` is `chmod 600` and
kept out of git.

The split in this project follows the nature of the data. Names and identifiers
go in `.env` as environment variables; passwords are secrets.

### Docker networks and the host network

A user-defined bridge network gives the containers their own network stack and
an internal DNS server, so one container reaches another by service name
without knowing any address. This is what replaced the old `links:` mechanism,
which wrote static entries into each container's `/etc/hosts`, coupled services
together and went stale as soon as an address changed.

With `network_mode: host` there is no separate stack at all. The container uses
the host's. Port collisions become possible, nothing is isolated, and every
port any container opens is open on the host. For this project that would break
the central requirement outright, since MariaDB would be listening on the
machine's own 3306 and NGINX would no longer be the only way in.

Only NGINX publishes a port in the mandatory part. MariaDB and PHP-FPM are
reachable from inside the network and nowhere else.

### Volumes and bind mounts

A bind mount maps an arbitrary host path into a container. It is written inline
in the service, Docker does not manage it, and it never shows up in
`docker volume ls`. A named volume is a proper Docker object with a lifecycle
of its own, declared separately and referenced by name.

The subject asks for named volumes and at the same time requires the data to
sit under `/home/fgalvez-/data`. Both hold at once through `driver_opts`:

```yaml
mariadb_data:
  driver: local
  driver_opts:
    type: none
    o: bind
    device: /home/fgalvez-/data/mariadb
```

The volume is still a named volume that Docker creates, registers and manages;
`driver_opts` only tells the local driver where to put the bytes. What the
subject rules out is the short inline syntax that bypasses Docker's volume
management entirely, and the difference is easy to check: run `docker volume ls`
and `docker volume inspect`. A real bind mount would not appear in the first and
would error on the second.

One practical consequence of `type: none` is that Docker will not create the
host directory for you. If it is missing the container fails to start, which is
why the Makefile creates all three before bringing anything up.

## Resources

### Documentation

- Docker documentation — https://docs.docker.com/
- Dockerfile reference and best practices — https://docs.docker.com/build/building/best-practices/
- Compose file reference — https://docs.docker.com/reference/compose-file/
- Secrets in Compose — https://docs.docker.com/compose/how-tos/use-secrets/
- MariaDB knowledge base — https://mariadb.com/kb/en/
- PHP-FPM configuration — https://www.php.net/manual/en/install.fpm.configuration.php
- NGINX documentation — https://nginx.org/en/docs/
- WP-CLI handbook — https://make.wordpress.org/cli/handbook/
- pure-ftpd documentation — https://www.pureftpd.org/project/pure-ftpd/doc/
- Redis configuration — https://redis.io/docs/latest/operate/oss_and_stack/management/config/
- Debian packages — https://packages.debian.org/bookworm/

### Reference material

- `man 7 namespaces` and `man 7 cgroups` for the kernel mechanisms behind
  containers
- `man 7 capabilities`, which came in useful when pure-ftpd refused to start
- Mozilla SSL Configuration Generator — https://ssl-config.mozilla.org/

### Use of AI

<Throughout the development of this project, I used artificial intelligence as a support tool for learning and research, rather than as a substitute for my own work. Its main role was to help me understand the subject more thoroughly and to make better-informed decisions at each stage.

First, I used AI to look up concepts I was not familiar with. Whenever I came across a term, method or idea that I did not fully understand, I asked for a clear explanation and, when necessary, for examples that made it easier to grasp. This allowed me to build a solid foundation before moving forward, instead of working with ideas I only partially understood.

Second, AI was useful for investigating the different options available to me. When I had to choose between several possible approaches, I used it to get an overview of the alternatives, along with their advantages and disadvantages. This gave me a broader perspective than I would have had on my own and helped me compare possibilities I might not have considered otherwise. The final decisions, however, were always mine, based on what best suited the goals of the project.

Finally, I used AI to explore certain elements of the project in greater depth. Once I had a general understanding of a topic, I asked more specific follow-up questions to examine the details, clarify doubts and understand how different parts were connected. This was especially helpful for the more complex aspects, where a superficial explanation was not enough.

Overall, AI worked as a starting point for research and as a way of speeding up my learning. I contrasted the information it gave me with other sources and with my own judgement, since I am aware that these tools can make mistakes. Using it in this way allowed me to save time on the initial search for information and dedicate more effort to analysing, deciding and developing the project itself.
