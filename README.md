*This project has been created as part of the 42 curriculum by fgalvez-.*

# Inception

## Description

Inception is a system administration project that builds a small web
infrastructure from scratch using Docker and Docker Compose, running inside a
dedicated virtual machine.

The stack serves a WordPress website over HTTPS. It is composed of three
services, each isolated in its own container, each built from a hand-written
Dockerfile based on Debian 12 (bookworm):

| Service | Role |
|---|---|
| `nginx` | Reverse proxy and TLS termination. The only entry point, on port 443. |
| `wordpress` | WordPress with PHP-FPM. No web server inside. |
| `mariadb` | Database server. No web server inside. |

The containers communicate over a user-defined Docker bridge network. Two named
volumes provide persistence for the database and for the website files, both
backed by `/home/fgalvez-/data` on the host. All credentials are handled through
Docker secrets and are never committed to this repository.

No pre-built images are pulled from Docker Hub other than the official Debian
base image, as required by the subject.

## Instructions

### Prerequisites

- A Linux virtual machine (this project was developed on Debian 12)
- Docker Engine and the Docker Compose plugin (v2)
- `make`
- `sudo` privileges, needed to write to `/home/fgalvez-/data`

### Setup

```bash
git clone <repository-url> inception
cd inception
```

Add the domain to your hosts file:

```bash
echo "127.0.0.1 fgalvez-.42.fr" | sudo tee -a /etc/hosts
```

### Build and run

```bash
make
```

This single command generates the secret files if they are missing, creates the
data directories on the host, builds the three images and starts the stack.

Then open `https://fgalvez-.42.fr` in a browser. The TLS certificate is
self-signed, so the browser will display a warning that must be accepted.

### Available targets

| Target | Effect |
|---|---|
| `make` | Build the images and start the stack |
| `make down` | Stop and remove the containers and the network |
| `make stop` / `make start` | Pause and resume without removing anything |
| `make logs` | Follow the logs of every service |
| `make ps` | Show the state of the containers |
| `make clean` | Stop everything and prune images and build cache |
| `make fclean` | `clean` plus removal of the volumes and the data on the host |
| `make re` | Full rebuild from scratch |

Note that `make fclean` deletes the database and the website content
permanently.

## Project description

### Use of Docker

Each service runs in a dedicated container built from its own Dockerfile. None
of the containers is kept alive artificially: every entry point ends by handing
over the process to the real service in the foreground, so that the service
itself is PID 1 and receives signals directly.

- MariaDB initialises its data directory on first run using `mysqld --bootstrap`,
  then execs `mysqld`.
- WordPress waits for the database to accept connections, installs WordPress with
  WP-CLI on first run, then execs `php-fpm8.2 -F`.
- NGINX generates a self-signed certificate at build time and runs with
  `daemon off;`.

Both application entry points are idempotent: they detect an already-initialised
volume and skip the setup, which is what makes the stack survive a reboot.

### Sources included in the project

```
Makefile                 Single entry point for the whole stack
secrets/                 Credentials, generated locally, never committed
srcs/.env                Non-sensitive configuration
srcs/docker-compose.yml  Infrastructure definition
srcs/requirements/       One directory per service, each with its Dockerfile,
                         its configuration files and its entry point script
```

### Main design choices

**Debian rather than Alpine.** Both are allowed by the subject. Debian was chosen
for predictability: it uses glibc rather than musl, its PHP and MariaDB packages
follow the canonical layout found in most documentation, and the debugging
surface is smaller. The trade-off is image size, which is not a criterion here.

**Bookworm rather than Trixie.** The subject requires the penultimate stable
release. Debian 13 is current, so Debian 12 is used. Beyond the rule, the older
release has years of production use and documented behaviour behind it.

**Explicit image tags.** Every image is tagged `<service>:inception` rather than
left to default to `latest`, which the subject forbids and which would also make
builds non-reproducible.

**Waiting for the database in the entry point rather than relying on
`depends_on`.** `depends_on` only orders container startup; it does not wait for
the service inside to become ready. The WordPress entry point polls the database
with a bounded retry loop and fails after a fixed number of attempts.

### Virtual Machines vs Docker

A virtual machine virtualises hardware. A hypervisor emulates a complete machine
and boots a full operating system with its own kernel inside it. That is why
installing one takes minutes and consumes gigabytes.

A container virtualises nothing. Its processes run directly on the host kernel.
What is isolated is their *view* of the system, through kernel namespaces (pid,
net, mnt, uts, ipc, user) and cgroups for resource limits. That is why a
container starts in milliseconds and weighs megabytes.

| | Virtual machine | Container |
|---|---|---|
| Virtualises | Hardware | Nothing; isolates processes |
| Kernel | Its own | Shared with the host |
| Startup | Minutes | Milliseconds |
| Size | Gigabytes | Megabytes |
| Isolation | Strong (hardware boundary) | Weaker (kernel boundary) |
| Different OS | Possible | Not possible |

Neither is strictly better. Containers win on packaging, density and startup
time. Virtual machines win when strong isolation between untrusted tenants is
required, or when a different kernel is needed. This project combines both:
containers running inside a virtual machine.

### Secrets vs Environment Variables

Environment variables are convenient but leak. They are visible through
`docker inspect`, they appear in `docker history` when they come from an `ENV`
instruction, they can be read from `/proc/<pid>/environ` by any process in the
container, and they are inherited by every child process.

Docker secrets are mounted as files under `/run/secrets/` on a tmpfs, so they
never touch the container's disk, never appear in an image layer, and are only
visible to the containers that explicitly declare them.

This project splits values by nature rather than by convenience: names and
identifiers live in `.env` as environment variables, while every password is a
secret. This can be verified directly:

```bash
docker exec mariadb ls -la /run/secrets/
docker inspect mariadb | grep -A5 '"Env"'
```

### Docker Network vs Host Network

A user-defined bridge network gives the containers their own network stack and
an internal DNS server, so a container can reach another by its service name
without knowing any IP address. This replaces the deprecated `links:` mechanism.

With `network_mode: host`, containers share the host network stack. There is no
isolation, port collisions become possible, and every port opened by any
container is exposed on the host. That would directly break the requirement that
NGINX be the only entry point, since MariaDB would be listening on the host's
port 3306.

Only NGINX publishes a port (443). MariaDB and PHP-FPM are reachable only from
within the network.

### Docker Volumes vs Bind Mounts

A bind mount maps an arbitrary host path into a container. It is declared inline
in the service, Docker does not manage it, and it does not appear in
`docker volume ls`.

A named volume is a first-class Docker object with its own lifecycle, declared in
the `volumes` section and referenced by name.

The subject requires named volumes while also requiring the data to live under
`/home/fgalvez-/data`. Both are satisfied with `driver_opts`:

```yaml
mariadb_data:
  driver: local
  driver_opts:
    type: none
    o: bind
    device: /home/fgalvez-/data/mariadb
```

The volume remains a Docker-managed named volume, inspectable with
`docker volume inspect`; `driver_opts` only tells the driver where to place the
bytes. What the subject forbids is the inline short syntax that bypasses Docker's
volume management entirely.

## Resources

### Documentation

- Docker documentation — https://docs.docker.com/
- Dockerfile reference and best practices — https://docs.docker.com/build/building/best-practices/
- Docker Compose file reference — https://docs.docker.com/reference/compose-file/
- Docker secrets in Compose — https://docs.docker.com/compose/how-tos/use-secrets/
- MariaDB knowledge base — https://mariadb.com/kb/en/
- PHP-FPM configuration — https://www.php.net/manual/en/install.fpm.configuration.php
- NGINX documentation — https://nginx.org/en/docs/
- WP-CLI handbook — https://make.wordpress.org/cli/handbook/
- Debian packages — https://packages.debian.org/bookworm/

### Articles and references

- Linux namespaces — `man 7 namespaces`
- Control groups — `man 7 cgroups`
- Why PID 1 matters in containers — https://docs.docker.com/reference/dockerfile/#entrypoint
- Mozilla SSL Configuration Generator — https://ssl-config.mozilla.org/

### Use of AI

An AI assistant (Claude) was used throughout this project, mainly as a tutor
rather than as a code generator. Specifically:

- **Explaining concepts** before implementing them: kernel namespaces and cgroups,
  the difference between the exec and shell forms of `ENTRYPOINT`, why PID 1
  behaves differently with signals, how FastCGI separates NGINX from PHP-FPM, and
  why `driver_opts` satisfies the named-volume requirement.
- **Drafting configuration files** (`docker-compose.yml`, the three Dockerfiles,
  the entry point scripts, `nginx.conf`, `www.conf`, `50-server.cnf`), which were
  then reviewed line by line and adjusted.
- **Reviewing command output**: build logs, container logs and verification
  commands were analysed together to confirm that each requirement was met.
- **Writing this documentation**, based on the decisions actually taken during
  the project.

Areas where the assistant was deliberately not relied upon: the choice of which
requirements to prioritise, the verification that each output matched the
subject, and the final understanding of every file, all of which remain the
author's responsibility. Every generated snippet was executed, inspected and
explained before being kept.
