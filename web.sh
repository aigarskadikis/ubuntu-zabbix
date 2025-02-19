#!/usr/bin/env bash

# to simulate script with system which has less than 1GM of RAM execute:
# sudo dd if=/dev/zero of=/myswap1 bs=1M count=1024 && sudo chown root:root /myswap1 && sudo chmod 0600 /myswap1 && sudo mkswap /myswap1 && sudo swapon /myswap1 && free -m && sudo dd if=/dev/zero of=/myswap2 bs=1M count=1024 && sudo chown root:root /myswap2 && sudo chmod 0600 /myswap2 && sudo mkswap /myswap2 && sudo swapon /myswap2 && free -m && echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# don't prompt for service restarts during "apt install"
[[ -f /etc/needrestart/conf.d/no-prompt.conf ]] || echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# pick up arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --DB_SERVER=*)                                               DB_SERVER="${1#*=}"; shift ;;
        --DB_PORT=*)                                                   DB_PORT="${1#*=}"; shift ;;
        --DB_DATABASE=*)                                           DB_DATABASE="${1#*=}"; shift ;;
        --DB_USER=*)                                                   DB_USER="${1#*=}"; shift ;;
        --DB_PASSWORD=*)                                           DB_PASSWORD="${1#*=}"; shift ;;
        --TARGET_ZABBIX_WEB_SERVICE=*)               TARGET_ZABBIX_WEB_SERVICE="${1#*=}"; shift ;;
        --TARGET_ZABBIX_FRONTEND_PHP=*)             TARGET_ZABBIX_FRONTEND_PHP="${1#*=}"; shift ;;
        --TARGET_ZABBIX_AGENT2=*)                         TARGET_ZABBIX_AGENT2="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

# validate if all mandatory fields are filled
if [[ -z "$DB_SERVER" || -z "$DB_PORT" || -z "$DB_DATABASE" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$TARGET_ZABBIX_WEB_SERVICE" || -z "$TARGET_ZABBIX_FRONTEND_PHP" || -z "$TARGET_ZABBIX_AGENT2" ]]; then
   echo "Usage:"
   echo "$0 --DB_SERVER='10.133.112.87' --DB_PORT='5432' --DB_DATABASE='zabbix' --DB_USER='zabbix' --DB_PASSWORD='zabbix' --TARGET_ZABBIX_WEB_SERVICE='7.2.3' --TARGET_ZABBIX_FRONTEND_PHP='7.2.3' --TARGET_ZABBIX_AGENT2='7.2.3'"
   exit 1
fi

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

# install packages
sudo apt -y install strace zabbix-get zabbix-sender jq php8.1-pgsql zabbix-nginx-conf zabbix-agent2

# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-frontend-php | grep -P "^1:${TARGET_ZABBIX_FRONTEND_PHP}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
AVAILABLE_ZABBIX_FRONTEND_PHP=$(apt-cache madison zabbix-frontend-php | grep "zabbix-frontend-php.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_FRONTEND_PHP}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_FRONTEND_PHP" ]; then
    echo "Version \"${AVAILABLE_ZABBIX_FRONTEND_PHP}\" of \"zabbix-frontend-php\" is not available in apt cache"
else
    sudo apt-get -y --allow-downgrades install zabbix-frontend-php=${AVAILABLE_ZABBIX_FRONTEND_PHP}
fi
fi

# set frontend to listen on port 80
sudo sed -i "s|#        listen          8080;|        listen          80;|" /etc/nginx/conf.d/zabbix.conf

# allow to listen on any IP or any DNS
sudo sed -i "s|#        server_name     example.com;|        server_name     _;|" /etc/nginx/conf.d/zabbix.conf

# remove default site
ls -1 /etc/nginx/sites-enabled | grep default && unlink /etc/nginx/sites-enabled/default

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

# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-web-service | grep -P "^1:${TARGET_ZABBIX_WEB_SERVICE}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
AVAILABLE_ZABBIX_WEB_SERVICE=$(apt-cache madison zabbix-web-service | grep "zabbix-web-service.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_WEB_SERVICE}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_WEB_SERVICE" ]; then
    echo "Version \"${AVAILABLE_ZABBIX_WEB_SERVICE}\" of \"zabbix-web-service\" is not available in apt cache"
else
    sudo apt-get -y --allow-downgrades install zabbix-web-service=${AVAILABLE_ZABBIX_WEB_SERVICE}
	sudo systemctl enable zabbix-web-service
fi
fi

echo "
AllowedIP=0.0.0.0/0,::/0
DebugLevel=3
IgnoreURLCertErrors=1
ListenPort=10053
LogFile=/var/log/zabbix/zabbix_web_service.log
LogFileSize=1024
Timeout=29
" | sudo tee /etc/zabbix/zabbix_web_service.conf

# if checksum file does not exist then create an empty one
[[ ! -f /etc/zabbix/md5sum.zabbix_web_service.conf ]] && sudo touch /etc/zabbix/md5sum.zabbix_web_service.conf
# validate current checksum
MD5SUM_ZABBIX_WEB_SERVICE_CONF=$(md5sum /etc/zabbix/zabbix_web_service.conf /etc/zabbix/zabbix_web_service.d/* | md5sum | grep -Eo "^\S+")
# if checksum does not match with old 
grep "$MD5SUM_ZABBIX_WEB_SERVICE_CONF" /etc/zabbix/md5sum.zabbix_web_service.conf 
if [ "$?" -ne "0" ]; then
# restart service
sudo systemctl restart zabbix-web-service
# reinstall checksum
echo "$MD5SUM_ZABBIX_WEB_SERVICE_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_web_service.conf
fi


# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-agent2 | grep -P "^1:${TARGET_ZABBIX_AGENT2}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
AVAILABLE_ZABBIX_AGENT2=$(apt-cache madison zabbix-agent2 | grep "zabbix-agent2.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_AGENT2}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_AGENT2" ]; then
    echo "Version \"${AVAILABLE_ZABBIX_AGENT2}\" of \"zabbix-agent2\" is not available in apt cache"
else
    sudo apt-get -y --allow-downgrades install zabbix-agent2=${AVAILABLE_ZABBIX_AGENT2}
	sudo systemctl restart zabbix-agent2
	sudo systemctl enable zabbix-agent2
fi
fi

# delete static hostname
sudo sed -i '/^Hostname=Zabbix server$/d' /etc/zabbix/zabbix_agent2.conf
# set agent 2 to not use FQDN but a short hostname (same as reported behind 'hostname -s')
sudo sed -i "s|^.*HostnameItem=.*|HostnameItem=system.hostname[shorthost]|" /etc/zabbix/zabbix_agent2.conf
# restart 

# if checksum file does not exist then create an empty one
[[ ! -f /etc/zabbix/md5sum.zabbix_agent2.conf ]] && sudo touch /etc/zabbix/md5sum.zabbix_agent2.conf
# validate current checksum
MD5SUM_ZABBIX_AGENT2_CONF=$(md5sum /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.d/* | md5sum | grep -Eo "^\S+")
# if checksum does not match with old 
grep "$MD5SUM_ZABBIX_AGENT2_CONF" /etc/zabbix/md5sum.zabbix_agent2.conf 
if [ "$?" -ne "0" ]; then
# restart service
sudo systemctl restart zabbix-agent2
# reinstall checksum
echo "$MD5SUM_ZABBIX_AGENT2_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_agent2.conf
fi


dpkg-query --showformat='${Version}' --show google-chrome-stable
if [ "$?" -ne "0" ]; then
curl https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/google-chrome.deb
# Install Google Chrome
sudo apt-get -y install /tmp/google-chrome.deb
rm -rf /tmp/google-chrome.deb
fi

# see if web service, agent, nginx is at listening state
sudo ss --tcp --listen --numeric --process | grep -E "(10053|10050|80)"

