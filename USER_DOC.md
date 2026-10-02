# User documentation

This is for whoever has to run and operate the stack without necessarily
wanting to modify it. If you need to change something, see `DEV_DOC.md`.

## What you get

Starting the project brings up a WordPress site served over HTTPS, plus a
handful of supporting services. Each one runs in its own container.

The site itself is the work of three of them. NGINX serves everything over
HTTPS and is the only one reachable from outside, on port 443. WordPress runs
the PHP code behind it. MariaDB holds all the content, users and settings.
Neither WordPress nor the database can be reached from outside the Docker
network at all.

The other five are extras. Redis caches database queries so pages need fewer of
them. Adminer is a web interface for browsing and editing the database, on port
8080. A small static site unrelated to WordPress sits on port 8081. An FTP
server on port 21 gives access to the WordPress files. And a backup service
dumps the database every half hour, keeping the copies for a week.

Three volumes hold the data that has to survive restarts: the database in
`/home/fgalvez-/data/mariadb`, the site files in
`/home/fgalvez-/data/wordpress`, and the dumps in `/home/fgalvez-/data/backup`.

## Starting and stopping

Everything is driven from the Makefile, run from the root of the repository.

`make` starts the whole thing. The first time it has to build eight images,
initialise the database and install WordPress, so give it several minutes.
Afterwards it starts in seconds, because the volumes already hold everything.

`make ps` shows the state of the containers. All of them should say `running`.
`make logs` follows the output of all of them at once, which is usually where
the answer is when something misbehaves.

`make stop` pauses the containers without removing them, and `make start`
resumes. `make down` goes further and removes the containers and the network,
but leaves the data alone, so a later `make` brings the site back exactly as it
was.

`make fclean` is the destructive one. It removes the containers, the images,
the volumes and the contents of `/home/fgalvez-/data`. The website and the
database are gone for good. It is only there for starting over from scratch.

## Getting to the site

The domain has to resolve locally first. On the machine running the browser,
add this line to `/etc/hosts`:

```
127.0.0.1 fgalvez-.42.fr
```

On Windows the file lives at `C:\Windows\System32\drivers\etc\hosts` and has to
be edited as administrator.

Then open `https://fgalvez-.42.fr`. Note the `https`: port 80 is closed, so
plain `http://` will simply fail to connect, and that is on purpose. The
certificate is self-signed, so the browser shows a warning the first time;
accepting it is fine for a local project.

The administration panel is at `https://fgalvez-.42.fr/wp-admin`. There are two
accounts: `fgalvez`, an administrator with full control, and `redactor`, an
author who can publish posts and leave comments.

### The other services

Adminer is at `http://localhost:8080`. To log in, choose MySQL as the system,
type `mariadb` as the server (that is the container name, which Docker's
internal DNS resolves), use the value of `MYSQL_USER` from `srcs/.env` as the
username, the contents of `secrets/db_password.txt` as the password, and
`wordpress` as the database.

The static site is at `http://localhost:8081`, plain HTTP, nothing to log into.

For FTP, connect to `localhost` on port 21 as `ftpuser`, with the password in
`secrets/ftp_password.txt`. Use passive mode; with the command-line client that
means `ftp -p localhost`. It opens straight onto the WordPress site files.

Backups are written automatically every thirty minutes to
`/home/fgalvez-/data/backup`. If you want one right now:

```bash
docker exec backup /usr/local/bin/backup.sh
```

## Credentials

All of them live as plain text files in `secrets/` at the root of the
repository: `db_root_password.txt` for the MariaDB root account,
`db_password.txt` for the database user WordPress connects with,
`wp_admin_password.txt` and `wp_user_password.txt` for the two WordPress
accounts, and `ftp_password.txt` for the FTP user.

They are readable only by their owner and are excluded from version control, so
they never leave the machine. To read one, just `cat` it.

Inside the containers they are mounted read-only under `/run/secrets/`, and
only in the containers that actually need them. You can check with
`docker exec mariadb ls -la /run/secrets/`.

Changing a WordPress password is done from the administration panel, under
Users. The file in `secrets/` is only read during the first installation, so
editing it afterwards has no effect on a site that already exists.

Changing a database password is a different matter, since it means
reinitialising the database. Edit the file, then `make fclean` followed by
`make`, and accept that all the content goes with it.

If any secret file is missing, `make` generates it with a random value. It
never overwrites one that already exists.

## Checking that it works

Start with `make ps` and look for `running` on all eight. A container stuck on
`restarting` is crashing in a loop, and `docker logs <name>` will say why.

In the logs, a healthy MariaDB ends with `ready for connections`. WordPress
ends either with the installation messages or with a line saying it is already
installed. NGINX and the static site are usually silent unless something is
wrong. The FTP container ends by starting pure-ftpd, and the backup container
reports the size of the dump it took on startup.

A few quick checks from the command line:

```bash
curl -kI https://fgalvez-.42.fr
```

should return a 200. And:

```bash
curl -I http://fgalvez-.42.fr
```

should fail to connect, because nothing listens on port 80.

To confirm the TLS version:

```bash
curl -kv --tlsv1.2 --tls-max 1.2 https://fgalvez-.42.fr 2>&1 | grep "SSL connection"
```

That should connect over TLSv1.2. Anything older is refused by the server.

To see that the database holds data:

```bash
docker exec mariadb mysql -u root -p"$(cat secrets/db_root_password.txt)" \
  -e "USE wordpress; SHOW TABLES;"
```

Twelve WordPress tables should come back.

For the cache, `docker exec wordpress wp redis status --allow-root --path=/var/www/html`
should report `Connected` and a valid drop-in. If you want to watch it actually
work, flush it, reset the statistics, load the page twice and compare:

```bash
docker exec redis redis-cli FLUSHALL
docker exec redis redis-cli CONFIG RESETSTAT
curl -k -s https://fgalvez-.42.fr > /dev/null
curl -k -s https://fgalvez-.42.fr > /dev/null
docker exec redis redis-cli INFO stats | grep keyspace
```

The hits come from the second request, answered from memory instead of the
database.

And for the backups:

```bash
docker exec backup ls -lh /backups/
docker exec backup sh -c 'zcat /backups/*.sql.gz | head -20'
```

You should see compressed files of a few kilobytes containing real SQL.

## When something goes wrong

If the browser cannot reach the site at all, check the `/etc/hosts` entry on the
machine running the browser before anything else, then confirm NGINX is running.

"Error establishing a database connection" means MariaDB is not up or not ready
yet; its logs will say which.

If a change you made in the admin panel does not show up on the site, it is
almost certainly the Redis cache serving the old version.
`docker exec redis redis-cli FLUSHALL` clears it.

And if you land on the WordPress installation screen, the site volume was
emptied without the database being reset alongside it. `make fclean` and `make`
rebuilds both consistently.
