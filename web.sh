#!/usr/bin/env bash

# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

DB_SERVER=10.133.112.87
DB_PORT=5432
DB_DATABASE=zabbix
DB_USER=zabbix
DB_PASSWORD=zabbix

# pick up arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --DB_SERVER=*)                               DB_SERVER="${1#*=}"; shift ;;
        --DB_PORT=*)                                   DB_PORT="${1#*=}"; shift ;;
        --DB_DATABASE=*)                           DB_DATABASE="${1#*=}"; shift ;;
        --DB_USER=*)                                   DB_USER="${1#*=}"; shift ;;
        --DB_PASSWORD=*)                           DB_PASSWORD="${1#*=}"; shift ;;
        --TARGET_REPORT_VERSION=*)       TARGET_REPORT_VERSION="${1#*=}"; shift ;;
        --TARGET_WEB_VERSION=*)             TARGET_WEB_VERSION="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

# validate if all mandatory fields are filled
if [[ -z "$DB_SERVER" || -z "$DB_PORT" || -z "$DB_DATABASE" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$TARGET_REPORT_VERSION" ]]; then
   echo "Usage: $0 --DB_SERVER='10.133.253.45' --DB_PORT='5432' --DB_DATABASE='zabbix' --DB_USER='zabbix' --DB_PASSWORD='zabbix' --TARGET_REPORT_VERSION='7.2.3' --TARGET_ZABBIX_FRONTEND_PHP='7.2.3'"
   exit 1
fi

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# download desired zabbix repository
curl https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb -o /tmp/zabbix-release.dep

# install
sudo dpkg -i /tmp/zabbix-release.dep

# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# update all packages in cache
sudo apt update

# install packages
sudo apt -y install strace zabbix-get zabbix-sender jq php8.1-pgsql zabbix-nginx-conf zabbix-agent2

# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-frontend-php | grep -P "^1:${TARGET_ZABBIX_FRONTEND_PHP}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
TARGET_ZABBIX_FRONTEND_PHP=$(apt-cache madison zabbix-frontend-php | grep "zabbix-frontend-php.*repo.zabbix.com" | grep -Eo "\S+${ZABBIX_FRONTEND_PHP}\S+")
# if variable not empty, then go for it
if [ -z "$TARGET_ZABBIX_FRONTEND_PHP" ]; then
    echo "Version \"${TARGET_ZABBIX_FRONTEND_PHP}\" of \"zabbix-frontend-php\" is not available in apt cache"
else
    sudo apt-get -y --allow-downgrades install zabbix-frontend-php=${TARGET_ZABBIX_FRONTEND_PHP}
fi
fi

# set frontend to listen on port 80
sudo sed -i "s|#        listen          8080;|        listen          80;|" /etc/nginx/conf.d/zabbix.conf

# allow to listen on any IP or any DNS
sudo sed -i "s|#        server_name     example.com;|        server_name     _;|" /etc/nginx/conf.d/zabbix.conf

# remove default site
unlink /etc/nginx/sites-enabled/default

systemctl restart nginx php8.1-fpm
systemctl enable nginx php8.1-fpm

# test if frontend recognized
curl -kL 127.0.0.1 | grep -Eo "Zabbix [0-9\.]+"

# install connection characteristics
echo "
<?php
// Zabbix GUI configuration file.

\$DB['TYPE']                     = 'POSTGRESQL';
\$DB['SERVER']                   = '${DB_SERVER}';
\$DB['PORT']                     = '${DB_PORT}';
\$DB['DATABASE']                 = '${DB_DATABASE}';
\$DB['USER']                     = '${DB_USER}';
\$DB['PASSWORD']                 = '${DB_PASSWORD}';

// Schema name. Used for PostgreSQL.
\$DB['SCHEMA']                   = 'public';

// Used for TLS connection.
\$DB['ENCRYPTION']               = false;
\$DB['KEY_FILE']                 = '';
\$DB['CERT_FILE']                = '';
\$DB['CA_FILE']                  = '';
\$DB['VERIFY_HOST']              = false;
\$DB['CIPHER_LIST']              = '';

// Vault configuration. Used if database credentials are stored in Vault secrets manager.
\$DB['VAULT']                    = '';
\$DB['VAULT_URL']                = '';
\$DB['VAULT_PREFIX']             = '';
\$DB['VAULT_DB_PATH']            = '';
\$DB['VAULT_TOKEN']              = '';
\$DB['VAULT_CERT_FILE']          = '';
\$DB['VAULT_KEY_FILE']           = '';

\$ZBX_SERVER_NAME                = 'instanceName';

\$IMAGE_FORMAT_DEFAULT   = IMAGE_FORMAT_PNG;
" | sudo tee /etc/zabbix/web/zabbix.conf.php

chown www-data. /etc/zabbix/web/zabbix.conf.php


sudo apt-get -y install zabbix-web-service

sudo systemctl enable zabbix-web-service



sudo ss --tcp --listen --numeric --process | grep 10053

dpkg-query --showformat='${Version}' --show zabbix-web-service | grep -P "^1:${TARGET_REPORT_VERSION}"


