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
   echo "Usage: $0 --ZBX_SERVER_HOST='10.133.253.44' --TARGET_PRX_VERSION='7.2.3' --TARGET_GNT_VERSION='7.2.3' --TARGET_JMX_VERSION='7.2.3'"
   exit 1
fi

# check existence of repository
apt list -a zabbix-proxy-sqlite3 | grep ":7.2"
if [ "$?" -ne "0" ]; then
# erase old repository
rm -rf "/tmp/zabbix-release.dep"
# download desired zabbix repository
curl https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb -o /tmp/zabbix-release.dep
# install
sudo dpkg -i /tmp/zabbix-release.dep && rm -rf "/tmp/zabbix-release.dep"
fi

# refresh apt cache
sudo apt update

# list which versions of Zabbix packages are installed right now 
APT_LIST_INSTALLED=$(apt list --installed)

# prepare troubleshooting utilities. allow to fetch passive metrics. allow to deliver data on demand (via cronjob). JSON beautifier
sudo apt -y install strace zabbix-get zabbix-sender jq tcpdump

echo "${APT_LIST_INSTALLED}" | grep "zabbix-proxy-sqlite3.*${TARGET_PRX_VERSION}"
if [ "$?" -ne "0" ]; then
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
ProxyMode=0
Server=${ZBX_SERVER_HOST}
SocketDir=/run/zabbix
StatsAllowedIP=127.0.0.1
TLSAccept=psk
TLSConnect=psk
TLSPSKFile=/var/lib/zabbix/.key.psk
TLSPSKIdentity=ZabbixProxyIdentity
Timeout=29
" | sudo tee /etc/zabbix/zabbix_proxy.conf

grep -Eor ^[^#]+ /etc/zabbix/zabbix_proxy.conf /etc/zabbix/zabbix_proxy.d | sort

# if checksum file does not exist then create an empty one
[[ ! -f /etc/zabbix/md5sum.zabbix_proxy.conf ]] && sudo touch /etc/zabbix/md5sum.zabbix_proxy.conf

# validate current checksum
MD5SUM_PRX_CONF=$(md5sum /etc/zabbix/zabbix_proxy.conf | md5sum | grep -Eo "^\S+")

# if checksum does not match with old 
grep "$MD5SUM_PRX_CONF" /etc/zabbix/md5sum.zabbix_proxy.conf 
if [ "$?" -ne "0" ]; then

# restart service
sudo systemctl restart zabbix-proxy

# reinstall checksum
echo "$MD5SUM_PRX_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_proxy.conf

fi


# check if agent2 is on correct version
echo "${APT_LIST_INSTALLED}" | grep "zabbix-agent2.*${TARGET_GNT_VERSION}"
if [ "$?" -ne "0" ]; then
# force agent2 to be on specific version
GNT_VERSION_AVAILABLE=$(apt list -a zabbix-agent2 | grep "${TARGET_GNT_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
# check if variable is empty
if [ -z "$GNT_VERSION_AVAILABLE" ]; then
    echo "Version \"${GNT_VERSION_AVAILABLE}\" of zabbix-agent2 is not available in apt cache"
else
    # install Zabbix agent
	sudo apt -y --allow-downgrades install zabbix-agent2=${GNT_VERSION_AVAILABLE}
fi
fi

# delete static hostname
sudo sed -i '/^Hostname=Zabbix server$/d' /etc/zabbix/zabbix_agent2.conf
# set agent 2 to not use FQDN but a short hostname (same as reported behind 'hostname -s')
sudo sed -i "s|^.*HostnameItem=.*|HostnameItem=system.hostname[shorthost]|" /etc/zabbix/zabbix_agent2.conf
# restart 
sudo systemctl restart zabbix-agent2
# enable at startup
sudo systemctl enable zabbix-agent2


echo "${APT_LIST_INSTALLED}" | grep "zabbix-java-gateway.*${TARGET_JMX_VERSION}"
if [ "$?" -ne "0" ]; then
# force Zabbix Java Gateway to be on specific version
JMX_VERSION_AVAILABLE=$(apt list -a zabbix-java-gateway | grep "${TARGET_JMX_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
# check if variable is empty
if [ -z "$JMX_VERSION_AVAILABLE" ]; then
    echo "Version \"${JMX_VERSION_AVAILABLE}\" of zabbix-java-gateway is not available in apt cache"
else
    # install Zabbix agent
	sudo apt -y --allow-downgrades install zabbix-java-gateway=${JMX_VERSION_AVAILABLE}
fi
fi

# restart 
sudo systemctl restart zabbix-java-gateway
# enable at startup
sudo systemctl enable zabbix-java-gateway

# proxy, agent, gateway must be in listening state
ss --tcp --listen --numeric | grep -E "(10051|10050|10052)"

# query PostgreSQL ODBC support (from stock Ubuntu repository)
echo "${APT_LIST_INSTALLED}" | grep "odbc-postgresql"
if [ "$?" -ne "0" ]; then
# setup ODBC driver for PostgreSQL
sudo apt -y install odbc-postgresql
fi


echo "${APT_LIST_INSTALLED}" | grep "mssql-tools18"
if [ "$?" -ne "0" ]; then
# install MS SQL ODBC. https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver16&tabs=ubuntu18-install%2Calpine17-install%2Cdebian8-install%2Credhat7-13-install%2Crhel7-offline
# Download the package to configure the Microsoft repo
curl -sSL -O https://packages.microsoft.com/config/ubuntu/$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)/packages-microsoft-prod.deb
# Install the package
sudo dpkg -i packages-microsoft-prod.deb
# Delete the file
rm packages-microsoft-prod.deb
# Install the ODBC driver
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
# optional: for bcp and sqlcmd
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18
echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
source ~/.bashrc
# optional: for unixODBC development headers
sudo apt-get install -y unixodbc-dev
fi

sudo ldconfig -p | grep oracle
if [ "$?" -ne "0" ]; then

sudo apt-get -y install unzip
curl https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip \
-o /tmp/instantclient-basic-linux.x64-23.7.0.25.01.zip

curl https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sdk-linux.x64-23.7.0.25.01.zip \
-o /tmp/instantclient-sdk-linux.x64-23.7.0.25.01.zip

mkdir -p /opt/oracle
cd /opt/oracle
mv /tmp/instantclient* .

unzip instantclient-basic-linux.x64-23.7.0.25.01.zip
unzip instantclient-sdk-linux.x64-23.7.0.25.01.zip
mv *.zip /tmp
cd /opt/oracle/instantclient_23_7

echo "${PWD}"> /etc/ld.so.conf.d/oracle-instantclient.conf

# this should print nothing:
sudo ldconfig -p | grep oracle

# install refresh ldpath
sudo ldconfig

# this should print libraries recognized by OS
sudo ldconfig -p | grep oracle
fi


