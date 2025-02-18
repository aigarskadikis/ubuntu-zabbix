#!/usr/bin/env bash

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
sudo apt -y install strace zabbix-get zabbix-sender jq zabbix-frontend-php php8.1-pgsql zabbix-nginx-conf zabbix-agent2


