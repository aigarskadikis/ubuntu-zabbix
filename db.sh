#!/usr/bin/env bash

# DB name, user, password
POSTGRES_DB="zabbix"
POSTGRES_USER="zabbix"
POSTGRES_PASSWORD="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24};echo;)"



while [[ "$#" -gt 0 ]]; do
    case $1 in
        --DB_SERVER_HOST=*)        DB_SERVER_HOST="${1#*=}"; shift ;;
        --DB_SERVER_PORT=*)        DB_SERVER_PORT="${1#*=}"; shift ;;
        --POSTGRES_DB=*)              POSTGRES_DB="${1#*=}"; shift ;;
        --POSTGRES_PASSWORD=*)  POSTGRES_PASSWORD="${1#*=}"; shift ;;
        --POSTGRES_USER=*)          POSTGRES_USER="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

if [[ -z "$DB_SERVER_HOST" || -z "$DB_SERVER_PORT" || -z "$POSTGRES_DB" || -z "$POSTGRES_PASSWORD" || -z "$POSTGRES_USER" ]]; then
   echo "Usage: $0 --DB_SERVER_HOST='10.133.253.45' --DB_SERVER_PORT='5432' --POSTGRES_DB='zabbix' --POSTGRES_USER='zabbix' --POSTGRES_PASSWORD='zabbix'"
   exit 1
fi



# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# from https://www.postgresql.org/download/linux/ubuntu/
sudo apt -y install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo apt update
sudo apt -y install postgresql-client-17

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# download desired zabbix repository
curl https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb -o /tmp/zabbix-release.dep

# install
sudo dpkg -i /tmp/zabbix-release.dep

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# update all packages in cache
sudo apt update

# prepare troubleshooting utilities
sudo apt -y install strace

# allow to fetch passive metrics
sudo apt -y install zabbix-get

# allow to deliver data on demand (via cronjob)
sudo apt -y install zabbix-sender

# install zabbix sql scripts
sudo apt -y install zabbix-sql-scripts

# Create the user with the specified password
sudo -u postgres psql -c "CREATE USER ZBX_USER WITH PASSWORD '${ZBX_PASS}';"

sudo -u postgres sudo -u postgres createdb -O zabbix zabbix



# dedicated user for application layer
# psql postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${DB_SERVER_HOST}:${DB_SERVER_PORT} -c 'CREATE DATABASE ${POSTGRES_DB} WITH OWNER = ${POSTGRES_USER};'

# [[ ${seed_db} = true ]] && zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${DB_SERVER_HOST}:${DB_SERVER_PORT}/zabbix


