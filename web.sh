#!/usr/bin/env bash

# to simulate script with system which has less than 1GM of RAM execute:
# sudo dd if=/dev/zero of=/myswap1 bs=1M count=1024 && sudo chown root:root /myswap1 && sudo chmod 0600 /myswap1 && sudo mkswap /myswap1 && sudo swapon /myswap1 && free -m && sudo dd if=/dev/zero of=/myswap2 bs=1M count=1024 && sudo chown root:root /myswap2 && sudo chmod 0600 /myswap2 && sudo mkswap /myswap2 && sudo swapon /myswap2 && free -m && echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# exit on any failure
set -e

# print commands
set -o xtrace

# don't prompt for service restarts during "apt install"
[[ -f /etc/needrestart/conf.d/no-prompt.conf ]] || echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

set +o xtrace
# Parse arguments
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
        --Server=*)                                            ZBX_SERVER_HOST="${1#*=}"; shift ;;
        --ServerActive=*)                                    ZBX_ACTIVESERVERS="${1#*=}"; shift ;;
        --Repo=*)                                                     ZBX_REPO="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done
set -o xtrace

# validate if all mandatory fields are filled
if [[ -z "$DB_SERVER" || -z "$DB_PORT" || -z "$DB_DATABASE" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$TARGET_ZABBIX_WEB_SERVICE" || -z "$TARGET_ZABBIX_FRONTEND_PHP" || -z "$TARGET_ZABBIX_AGENT2" || -z "$ZBX_SERVER_HOST" || -z "$ZBX_ACTIVESERVERS" ]]; then
   echo "Usage:"
   echo "$0 --DB_SERVER='10.133.112.87' --DB_PORT='5432' --DB_DATABASE='zabbix' --DB_USER='zabbix' --DB_PASSWORD='zabbix' --TARGET_ZABBIX_WEB_SERVICE='7.2.3' --TARGET_ZABBIX_FRONTEND_PHP='7.2.3' --TARGET_ZABBIX_AGENT2='7.2.3' --Server='app1,app2' --ServerActive='app1;app2' --Repo='https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb'"
   exit 1
fi

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# download desired zabbix repository
curl "${ZBX_REPO}" -o /tmp/zabbix-release.dep

# install
sudo dpkg -i /tmp/zabbix-release.dep

# erase old repository
rm -rf "/tmp/zabbix-release.dep"

# update all packages in cache
sudo apt-get update

# install packages
sudo apt-get -y install strace zabbix-get zabbix-sender jq php8.1-pgsql zabbix-nginx-conf zabbix-agent2

# allow failure for the first time
set +e
# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-frontend-php | grep -P "^1:${TARGET_ZABBIX_FRONTEND_PHP}"
if [ "$?" -ne "0" ]; then
set -e
# observe if desired is available
AVAILABLE_ZABBIX_FRONTEND_PHP=$(apt-cache madison zabbix-frontend-php | grep "zabbix-frontend-php.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_FRONTEND_PHP}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_FRONTEND_PHP" ]; then
    echo "Version \"${AVAILABLE_ZABBIX_FRONTEND_PHP}\" of \"zabbix-frontend-php\" is not available in apt cache"
else
    sudo apt-get -y --allow-downgrades install zabbix-frontend-php=${AVAILABLE_ZABBIX_FRONTEND_PHP}
fi
fi
set -e


# reinstall nginx zabbix configuration
echo '
server {
        listen          80;
        server_name     _;

        root    /usr/share/zabbix/ui;

        index   index.php;

        location = /favicon.ico {
                log_not_found   off;
        }

        location / {
                try_files       $uri $uri/ =404;
        }

        location /assets {
                access_log      off;
                expires         10d;
        }

        location ~ /\.ht {
                deny            all;
        }

        location ~ /(api\/|conf[^\.]|include|locale) {
                deny            all;
                return          404;
        }

        location /vendor {
                deny            all;
                return          404;
        }

        location ~ [^/]\.php(/|$) {
                fastcgi_pass    unix:/var/run/php/zabbix.sock;
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                fastcgi_index   index.php;

                fastcgi_param   DOCUMENT_ROOT   /usr/share/zabbix/ui;
                fastcgi_param   SCRIPT_FILENAME /usr/share/zabbix/ui$fastcgi_script_name;
                fastcgi_param   PATH_TRANSLATED /usr/share/zabbix/ui$fastcgi_script_name;

                include fastcgi_params;
                fastcgi_param   QUERY_STRING    $query_string;
                fastcgi_param   REQUEST_METHOD  $request_method;
                fastcgi_param   CONTENT_TYPE    $content_type;
                fastcgi_param   CONTENT_LENGTH  $content_length;

                fastcgi_intercept_errors        on;
                fastcgi_ignore_client_abort     off;
                fastcgi_connect_timeout         60;
                fastcgi_send_timeout            180;
                fastcgi_read_timeout            180;
                fastcgi_buffer_size             128k;
                fastcgi_buffers                 4 256k;
                fastcgi_busy_buffers_size       256k;
                fastcgi_temp_file_write_size    256k;
        }
}
' | grep -vE "^$" | sudo tee /etc/nginx/conf.d/zabbix.conf

# remove default site
ls -1 /etc/nginx/sites-enabled | grep default && sudo unlink /etc/nginx/sites-enabled/default

sudo systemctl restart nginx php8.1-fpm
sudo systemctl enable nginx php8.1-fpm

# test if frontend recognized
curl -kL "http://127.0.0.1/index.php" | grep -m1 -Eo "Zabbix" | tail -1

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
" | grep -vE "^$" | sudo tee /etc/zabbix/web/zabbix.conf.php

sudo chown www-data. /etc/zabbix/web/zabbix.conf.php

# allow failure for the first time
set +e
# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-web-service | grep -P "^1:${TARGET_ZABBIX_WEB_SERVICE}"
if [ "$?" -ne "0" ]; then
set -e
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
set -e

# allow google chrome to generate tmp files in zabbix home
sudo mkdir -p /var/lib/zabbix
sudo chown -R zabbix. /var/lib/zabbix

echo "
AllowedIP=0.0.0.0/0,::/0
DebugLevel=3
IgnoreURLCertErrors=1
ListenPort=10053
LogFile=/var/log/zabbix/zabbix_web_service.log
LogFileSize=1024
Timeout=29
" | grep -vE "^$" | sudo tee /etc/zabbix/zabbix_web_service.conf

# if checksum file does not exist then create an empty one
if [ ! -f /etc/zabbix/md5sum.zabbix_web_service.conf ]; then
sudo touch /etc/zabbix/md5sum.zabbix_web_service.conf
sudo chmod 644 /etc/zabbix/md5sum.zabbix_web_service.conf
fi
# validate current checksum
MD5SUM_ZABBIX_WEB_SERVICE_CONF=$(md5sum /etc/zabbix/zabbix_web_service.conf | md5sum | grep -Eo "^\S+")
# if checksum does not match with old
set +e
grep "$MD5SUM_ZABBIX_WEB_SERVICE_CONF" /etc/zabbix/md5sum.zabbix_web_service.conf 
if [ "$?" -ne "0" ]; then
set -e
# restart service
sudo systemctl restart zabbix-web-service
# reinstall checksum
echo "$MD5SUM_ZABBIX_WEB_SERVICE_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_web_service.conf
fi
set -e


set +e
# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-agent2 | grep -P "^1:${TARGET_ZABBIX_AGENT2}"
if [ "$?" -ne "0" ]; then
set -e
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
set -e

# all possible agent2 7.2 settings on Linux
# https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/src/go/conf/zabbix_agent2.conf?at=refs%2Fheads%2Frelease%2F7.2

# Install configuration of Zabbix agent
echo "
BufferSend=5
BufferSize=65535
ControlSocket=/run/zabbix/agent.sock
DebugLevel=3
DenyKey=system.run[*]
HeartbeatFrequency=60
HostMetadataItem=system.uname
HostnameItem=system.hostname[shorthost]
Include=/etc/zabbix/zabbix_agent2.d/*.conf
Include=/etc/zabbix/zabbix_agent2.d/plugins.d/*.conf
ListenPort=10050
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=1024
PidFile=/run/zabbix/zabbix_agent2.pid
PluginSocket=/run/zabbix/agent.plugin.sock
Plugins.SystemRun.LogRemoteCommands=0
RefreshActiveChecks=5
Server=${ZBX_SERVER_HOST}
ServerActive=${ZBX_ACTIVESERVERS}
Timeout=28
UnsafeUserParameters=0
" | grep -vE "^$" | sudo tee /etc/zabbix/zabbix_agent2.conf



# if checksum file does not exist then create an empty one
if [ ! -f /etc/zabbix/md5sum.zabbix_agent2.conf ]; then
sudo touch /etc/zabbix/md5sum.zabbix_agent2.conf
sudo chmod 644 /etc/zabbix/md5sum.zabbix_agent2.conf
fi
# validate current checksum
MD5SUM_ZABBIX_AGENT2_CONF=$(grep -r "=" /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.d | sort | md5sum | grep -Eo "^\S+")
# if checksum does not match with old 
set +e
grep "$MD5SUM_ZABBIX_AGENT2_CONF" /etc/zabbix/md5sum.zabbix_agent2.conf 
if [ "$?" -ne "0" ]; then
set -e
# restart service
sudo systemctl restart zabbix-agent2
# reinstall checksum
echo "$MD5SUM_ZABBIX_AGENT2_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_agent2.conf
fi
set -e

# allow first failure
set +e
dpkg-query --showformat='${Version}' --show google-chrome-stable
if [ "$?" -ne "0" ]; then
set -e
curl https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/google-chrome.deb
# Install Google Chrome
sudo apt-get -y install /tmp/google-chrome.deb
rm -rf /tmp/google-chrome.deb
fi
set -e

# see if web service, agent, nginx is at listening state
sudo ss --tcp --listen --numeric --process | grep -E "(10053|10050|80)"

