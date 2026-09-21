# User documentation

This document is written for an end user or an administrator who wants to run
and operate the stack, not to modify it. For development details, see
`DEV_DOC.md`.

---

## 1. What this stack provides

Running this project starts a complete WordPress website served over HTTPS. It
is made of three services, each in its own container:

| Container | What it does | Reachable from |
|---|---|---|
| `nginx` | Serves the site over HTTPS, terminates TLS, forwards PHP requests | The host, on port 443 |
| `wordpress` | Runs the WordPress code through PHP-FPM | Internal network only |
| `mariadb` | Stores all site content, users and settings | Internal network only |

Only NGINX is exposed. The database and the PHP interpreter cannot be reached
from outside the Docker network, which limits the attack surface to a single
entry point.

Two named volumes keep the data safe across restarts:

| Volume | Contains | Stored on the host at |
|---|---|---|
| `mariadb_data` | The WordPress database | `/home/fgalvez-/data/mariadb` |
| `wordpress_data` | Site files, themes, plugins, uploads | `/home/fgalvez-/data/wordpress` |

---

## 2. Starting and stopping

All commands are run from the root of the repository.

### Start

```bash
make
```

The first run takes a few minutes: it builds the three images, initialises the
database and installs WordPress. Later runs start in a few seconds because the
volumes already hold the data.

### Check that it started

```bash
make ps
```

All three containers should report `running`.

### Stop temporarily

```bash
make stop
```

The containers are paused but kept. `make start` resumes them.

### Stop and remove the containers

```bash
make down
```

The containers and the network are removed. **The data is preserved**, so a
later `make` brings the site back exactly as it was.

### Delete everything, including the data

```bash
make fclean
```

This removes the containers, the images, the volumes and the contents of
`/home/fgalvez-/data`. **The website and the database are permanently lost.**
Only use it to start over from scratch.

---

## 3. Accessing the website

### Before the first access

The domain must resolve locally. Add this line to `/etc/hosts` on the machine
running the browser:

```
127.0.0.1 fgalvez-.42.fr
```

On Windows the file is at `C:\Windows\System32\drivers\etc\hosts` and must be
edited as administrator.

### The public site

Open:

```
https://fgalvez-.42.fr
```

The site only answers on HTTPS. Port 80 is closed, so `http://` will fail to
connect; that is intentional.

The TLS certificate is self-signed, so the browser will show a security warning
the first time. This is expected in a local project and the warning can safely be
accepted.

### The administration panel

```
https://fgalvez-.42.fr/wp-admin
```

Two accounts exist:

| Account | Role | What it can do |
|---|---|---|
| `fgalvez` | Administrator | Full control: pages, posts, users, settings |
| `redactor` | Author | Write and publish its own posts, leave comments |

---

## 4. Managing credentials

### Where the passwords are

Every password lives in a plain text file inside the `secrets/` directory at the
root of the repository:

| File | Used for |
|---|---|
| `db_root_password.txt` | MariaDB root account |
| `db_password.txt` | The database user WordPress connects with |
| `wp_admin_password.txt` | The WordPress administrator |
| `wp_user_password.txt` | The second WordPress user |

These files are readable only by their owner (`chmod 600`) and are excluded from
version control. They are never committed.

To read one:

```bash
cat secrets/wp_admin_password.txt
```

### How they reach the containers

The files are mounted as Docker secrets under `/run/secrets/` inside the
containers that need them, on a memory-backed filesystem. They are not stored in
any image and are not visible in the container's environment variables.

To confirm:

```bash
docker exec mariadb ls -la /run/secrets/
```

### Changing a WordPress password

Change it from the administration panel, under Users. The file in `secrets/`
is only used at first installation, so editing it afterwards has no effect on an
existing site.

### Changing a database password

This requires reinitialising the database and is therefore destructive. Edit the
file in `secrets/`, then run `make fclean` followed by `make`. All site content
will be lost.

### If the secrets are missing

Running `make` regenerates any missing secret file automatically with a random
value. Existing files are never overwritten.

---

## 5. Checking that everything works

### Container state

```bash
make ps
```

Look for `running` on all three. A container stuck in `restarting` is crashing
repeatedly.

### Logs

```bash
make logs
```

Or for one service:

```bash
docker logs nginx
docker logs wordpress
docker logs mariadb
```

Healthy output looks like this:

- `mariadb` ends with `ready for connections`
- `wordpress` ends with the installation message, or reports that WordPress is
  already installed
- `nginx` is normally silent unless there is traffic or an error

### The site responds over HTTPS

```bash
curl -kI https://fgalvez-.42.fr
```

Expected: an HTTP 200 response.

### HTTP is refused

```bash
curl -I http://fgalvez-.42.fr
```

Expected: a connection failure. If this returns a page, port 80 is open and
should not be.

### TLS version

```bash
curl -kv --tlsv1.2 --tls-max 1.2 https://fgalvez-.42.fr 2>&1 | grep "SSL connection"
```

Expected: a successful connection using TLSv1.2. Older versions are rejected by
the server.

### The database holds data

```bash
docker exec mariadb mysql -u root -p"$(cat secrets/db_root_password.txt)" \
  -e "USE wordpress; SHOW TABLES;"
```

Expected: the list of WordPress tables.

### The data is on the host

```bash
ls /home/fgalvez-/data/mariadb
ls /home/fgalvez-/data/wordpress
```

Both should be populated.

---

## 6. Common problems

**The browser cannot reach the site.** Check the `/etc/hosts` entry on the
machine running the browser, then confirm with `make ps` that NGINX is running.

**"Error establishing a database connection".** MariaDB is not running or not
ready. Check `docker logs mariadb`.

**A container restarts in a loop.** Read its logs; the error is almost always in
the last lines before it exits.

**The site shows the WordPress installation screen.** The WordPress volume was
emptied without the database being reset. Run `make fclean` and then `make` to
rebuild both consistently.
