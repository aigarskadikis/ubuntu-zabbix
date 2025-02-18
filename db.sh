#!/usr/bin/env bash

# DB name, user, password
ZBX_DB="zabbix"
ZBX_USER="zabbix"
ZBX_PASS="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24};echo;)"

# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# from https://www.postgresql.org/download/linux/ubuntu/
sudo apt -y install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo apt update
sudo apt -y install postgresql-client-17
# sudo apt -y install postgresql-17

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






