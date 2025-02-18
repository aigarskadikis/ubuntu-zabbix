#!/usr/bin/env bash

# sudo dd if=/dev/zero of=/myswap1 bs=1M count=1024 && sudo chown root:root /myswap1 && sudo chmod 0600 /myswap1 && sudo mkswap /myswap1 && sudo swapon /myswap1 && free -m && sudo dd if=/dev/zero of=/myswap2 bs=1M count=1024 && sudo chown root:root /myswap2 && sudo chmod 0600 /myswap2 && sudo mkswap /myswap2 && sudo swapon /myswap2 && free -m && echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# pick up arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ZBX_SERVER_HOST=*)              ZBX_SERVER_HOST="${1#*=}"; shift ;;
        --TARGET_PRX_VERSION=*)        TARGET_PRX_VERSION="${1#*=}"; shift ;;
        --TARGET_GNT_VERSION=*)        TARGET_GNT_VERSION="${1#*=}"; shift ;;
        --TARGET_JMX_VERSION=*)        TARGET_JMX_VERSION="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done


if [[ -z "$ZBX_SERVER_HOST" || -z "$TARGET_PRX_VERSION" || -z "$TARGET_GNT_VERSION" || -z "$TARGET_JMX_VERSION" ]]; then
   echo "Usage: $0 --ZBX_SERVER_HOST='10.133.253.44' --TARGET_PRX_VERSION='7.2.3' --TARGET_GNT_VERSION='7.2.0' --TARGET_JMX_VERSION='7.2.0'"
   exit 1
fi



# erase old repository
rm -rf "/tmp/zabbix-release.dep"
# download desired zabbix repository
curl https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb -o /tmp/zabbix-release.dep
# install
sudo dpkg -i /tmp/zabbix-release.dep && rm -rf "/tmp/zabbix-release.dep"
# update apt cache
sudo apt update
# prepare troubleshooting utilities. allow to fetch passive metrics. allow to deliver data on demand (via cronjob). JSON beautifier
sudo apt -y install strace zabbix-get zabbix-sender jq


zabbix_proxy --version | grep "$TARGET_PRX_VERSION"
if [ "$?" -ne "0" ]; then
PRX_VERSION_AVAILABLE=$(apt list -a zabbix-proxy-sqlite3 | grep "${TARGET_PRX_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
echo "$PRX_VERSION_AVAILABLE"
# check if variable is empty
if [ -z "$PRX_VERSION_AVAILABLE" ]; then
    echo "Version \"${TARGET_PRX_VERSION}\" of \"zabbix-proxy-sqlite3\" is not available in apt cache"
else
	sudo apt -y --allow-downgrades install zabbix-proxy-sqlite3=${PRX_VERSION_AVAILABLE}
fi

fi


# create home for service user
mkdir -p /var/lib/zabbix

# enable include for exceptions. will be required only for special occasions when proxy have bigger load
mkdir -p /etc/zabbix/zabbix_proxy.d

# dependencies to setup PSK
sudo apt -y install openssl

# if PSK has been never configured, then install one
[[ ! -f /var/lib/zabbix/.key.psk ]] && openssl rand -hex 32 > /var/lib/zabbix/.key.psk

# do not allow files to be accessible by other linux users
sudo chown -R zabbix. /var/lib/zabbix

# full setings and documentation
# https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/conf/zabbix_proxy.conf?at=refs%2Fheads%2Frelease%2F7.2

# specify overrides (in alphabetical order)
echo "
CacheSize=512M
DBName=/var/lib/zabbix/zabbix_proxy.sqlite3
DBUser=zabbix
EnableRemoteCommands=1
Fping6Location=
FpingLocation=/usr/bin/fping
HostnameItem=system.hostname[shorthost]
Include=/etc/zabbix/zabbix_proxy.d/*.conf
JavaGateway=127.0.0.1
JavaGatewayPort=10052
LogFile=/var/log/zabbix/zabbix_proxy.log
LogRemoteCommands=1
LogSlowQueries=3000
PidFile=/run/zabbix/zabbix_proxy.pid
ProxyBufferMode=hybrid
ProxyMemoryBufferSize=160M
ProxyMode=1
Server=127.0.0.1
SocketDir=/run/zabbix
StatsAllowedIP=127.0.0.1
TLSAccept=psk
TLSConnect=psk
TLSPSKFile=/var/lib/zabbix/.key.psk
TLSPSKIdentity=ZabbixProxyIdentity
Timeout=29
" | sudo tee /etc/zabbix/zabbix_proxy.conf

grep -Eor ^[^#]+ /etc/zabbix/zabbix_proxy.conf /etc/zabbix/zabbix_proxy.d | sort


# force agent2 to be on specific version
GNT_VERSION_AVAILABLE=$(apt list -a zabbix-agent2 | grep "${TARGET_GNT_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
# check if variable is empty
if [ -z "$GNT_VERSION_AVAILABLE" ]; then
    echo "Version \"${GNT_VERSION_AVAILABLE}\" of zabbix-agent2 is not available in apt cache"
else
    # install Zabbix agent
	sudo apt -y --allow-downgrades install zabbix-agent2=${GNT_VERSION_AVAILABLE}
fi
# delete static hostname
sudo sed -i '/^Hostname=Zabbix server$/d' /etc/zabbix/zabbix_agent2.conf
# set agent 2 to not use FQDN but a short hostname (same as reported behind 'hostname -s')
sudo sed -i "s|^.*HostnameItem=.*|HostnameItem=system.hostname[shorthost]|" /etc/zabbix/zabbix_agent2.conf
# restart 
sudo systemctl restart zabbix-agent2
# enable at startup
sudo systemctl enable zabbix-agent2


# force Zabbix Java Gateway to be on specific version
JMX_VERSION_AVAILABLE=$(apt list -a zabbix-java-gateway | grep "${TARGET_JMX_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
# check if variable is empty
if [ -z "$JMX_VERSION_AVAILABLE" ]; then
    echo "Version \"${JMX_VERSION_AVAILABLE}\" of zabbix-java-gateway is not available in apt cache"
else
    # install Zabbix agent
	sudo apt -y --allow-downgrades install zabbix-java-gateway=${JMX_VERSION_AVAILABLE}
fi
# restart 
sudo systemctl restart zabbix-java-gateway
# enable at startup
sudo systemctl enable zabbix-java-gateway

# proxy, agent, gateway must be in listening state
ss --tcp --listen --numeric | grep -E "(10051|10050|10052)"

