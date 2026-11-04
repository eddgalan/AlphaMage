# AlphaMage

A project based on **Magento Open Source 2.4.8**, with a local Docker Compose environment.

## Services

| Compose service | Technology | Access from the host machine |
| --- | --- | --- |
| `alpha-mage` | Apache, PHP 8.3 and Composer 2.8.11 | http://localhost:8084 |
| `mariadb` | MariaDB 11.4 | `127.0.0.1:3307` |
| `opensearch3` | OpenSearch 3, with the security plugin disabled | http://localhost:9201 |

The source code is mounted at `/var/www/html`. MariaDB data is stored in `containers/mariadb/db` and its logs in `containers/mariadb/logs`. OpenSearch does not have a persistent volume configured.

## Requirements

- Git and Docker with Docker Compose v2 (`docker compose`). On macOS or Windows, you can use Docker Desktop.
- Docker running and ports `8084`, `3307` and `9201` available.
- Magento Marketplace access keys to download dependencies from `repo.magento.com`: the public key as the username and the private key as the password.

PHP, Composer, MariaDB and OpenSearch run in containers; you do not need to install them on the host machine. Run the following commands from the repository root.

## Local installation

### 1. Clone the project and prepare the network

```bash
git clone git@github.com:eddgalan/AlphaMage.git AlphaMage
cd AlphaMage
docker network inspect alpha-network >/dev/null 2>&1 || docker network create alpha-network
```

The `alpha-network` network is declared as external in `docker-compose.yml`, so it must exist before starting the services. If you have already cloned the project, go directly to its directory.

### 2. Build and start the containers

```bash
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 mariadb opensearch3
```

Wait for MariaDB and OpenSearch to finish starting. You can check them with:

```bash
docker compose exec mariadb mariadb-admin ping -uroot -p
curl http://localhost:9201
```

When MariaDB prompts for a password, enter the one configured in `docker-compose.yml` (currently `12345678a`). OpenSearch should return JSON containing node information.

### 3. Install PHP dependencies

Configure your Marketplace keys by replacing the placeholders:

```bash
docker compose exec -e COMPOSER_ALLOW_SUPERUSER=1 alpha-mage composer config --global --auth http-basic.repo.magento.com '<PUBLIC_KEY>' '<PRIVATE_KEY>'
docker compose exec -e COMPOSER_ALLOW_SUPERUSER=1 alpha-mage composer install
```

`composer install` uses the repository's `composer.lock`. The keys are stored in Composer's global configuration inside the container; you will need to configure them again if you recreate it. Avoid sharing them or committing them to Git. The `auth.json.sample` file shows the authentication format, but `auth.json` is not currently excluded in `.gitignore`.

### 4. Create the database

Open the MariaDB client and enter the password described in step 2:

```bash
docker compose exec mariadb mariadb -uroot -p
```

Run:

```sql
CREATE DATABASE IF NOT EXISTS alpha_mage CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EXIT;
```

Compose only configures the root password; it does not automatically create the `alpha_mage` database.

### 5. Configure permissions and install Magento

```bash
docker compose exec alpha-mage bash configFiles/filePermissions.sh
```

For a new installation, run the following command, replacing the administrator email and password. Keep the password in quotes if it contains special characters.

```bash
docker compose exec --user www-data alpha-mage php bin/magento setup:install \
  --base-url=http://localhost:8084/ \
  --db-host=mariadb \
  --db-name=alpha_mage \
  --db-user=root \
  --db-password=12345678a \
  --admin-firstname=Admin \
  --admin-lastname=Local \
  --admin-email=admin@example.com \
  --admin-user=admin \
  --admin-password='<ADMIN_PASSWORD>' \
  --language=en_US \
  --currency=MXN \
  --timezone=America/Mexico_City \
  --use-rewrites=1 \
  --search-engine=opensearch \
  --opensearch-host=opensearch3 \
  --opensearch-port=9200 \
  --opensearch-index-prefix=magento2 \
  --opensearch-timeout=15
```

Use an administrator password with at least 8 characters, including letters and numbers. If you changed the MariaDB password, update `--db-password` as well.

Inside the Docker network, use service names and their internal ports (`mariadb:3306` and `opensearch3:9200`), rather than the ports published on the host machine.

A similar command exists in `configFiles/setup-install.sh`, but it contains personal information, hardcoded credentials and a different time zone. Review those values before using it. Do not run `setup:install` on an existing installation; restoring one requires its database and `app/etc/env.php` configuration.

### 6. Prepare the development environment

```bash
docker compose exec --user www-data alpha-mage php bin/magento deploy:mode:set developer
docker compose exec --user www-data alpha-mage php bin/magento indexer:reindex
docker compose exec --user www-data alpha-mage php bin/magento cache:flush
docker compose exec --user www-data alpha-mage php bin/magento info:adminuri
```

Open http://localhost:8084. To access the admin panel, append the path returned by `info:adminuri` to that address and use the credentials defined during installation. Admin access may require setting up two-factor authentication; this Compose configuration does not include a mail server.

## Daily use

```bash
# Start or stop the environment without removing containers
docker compose start
docker compose stop

# View Apache/PHP logs
docker compose logs -f alpha-mage

# Open a shell in the application container
docker compose exec alpha-mage bash

# Apply module changes and flush the cache
docker compose exec --user www-data alpha-mage php bin/magento setup:upgrade
docker compose exec --user www-data alpha-mage php bin/magento cache:flush

# Run Magento scheduled tasks once
docker compose exec --user www-data alpha-mage php bin/magento cron:run
```

Compose does not configure a cron service. For automatic processing, schedule periodic execution of `cron:run` in your environment.

`docker compose down` removes the containers and keeps the MariaDB files on the host machine. Since OpenSearch has no volume, you may need to run `indexer:reindex` to rebuild the indexes after recreating it.

## Troubleshooting

- **Network does not exist:** create `alpha-network` using the command in step 1.
- **Name or port conflicts:** Compose assigns the names `alpha-mage`, `mariadb` and `opensearch3`. Check whether another project is already using them.
- **Composer returns 401/403:** check your Marketplace keys and access to `repo.magento.com`.
- **Magento cannot connect to the database or search engine:** wait until both services are ready and check their logs. Verify the internal names and ports from step 5.
- **OpenSearch does not start:** check `docker compose logs opensearch3`. If the demo installer requests `OPENSEARCH_INITIAL_ADMIN_PASSWORD`, configure that variable in the service and recreate it. If the log reports an insufficient `vm.max_map_count` limit, adjust the host or Docker virtual machine limit to the requested value.
- **Permission errors:** run `configFiles/filePermissions.sh` inside the container again and use `--user www-data` for the Magento CLI.

This configuration is intended for local development: it exposes the database and OpenSearch, uses hardcoded credentials and disables OpenSearch security. It requires adjustments before deployment to a public environment.
