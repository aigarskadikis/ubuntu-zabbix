#!/usr/bin/env bash

# to simulate script with system which has less than 1GM of RAM execute:
# sudo dd if=/dev/zero of=/myswap1 bs=1M count=1024 && sudo chown root:root /myswap1 && sudo chmod 0600 /myswap1 && sudo mkswap /myswap1 && sudo swapon /myswap1 && free -m && sudo dd if=/dev/zero of=/myswap2 bs=1M count=1024 && sudo chown root:root /myswap2 && sudo chmod 0600 /myswap2 && sudo mkswap /myswap2 && sudo swapon /myswap2 && free -m && echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# don't prompt for service restarts during "apt install"
[[ -f /etc/needrestart/conf.d/no-prompt.conf ]] || echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# pick up arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ZBX_SERVER_HOST=*)                          ZBX_SERVER_HOST="${1#*=}"; shift ;;
        --TARGET_ZABBIX_PROXY=*)                  TARGET_ZABBIX_PROXY="${1#*=}"; shift ;;
        --TARGET_ZABBIX_AGENT2=*)                TARGET_ZABBIX_AGENT2="${1#*=}"; shift ;;
        --TARGET_ZABBIX_JAVA_GATEWAY=*)    TARGET_ZABBIX_JAVA_GATEWAY="${1#*=}"; shift ;;
        --PSK=*)                                      PSK="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done


if [[ -z "$ZBX_SERVER_HOST" || -z "$TARGET_ZABBIX_PROXY" || -z "$TARGET_ZABBIX_AGENT2" || -z "$TARGET_ZABBIX_JAVA_GATEWAY" ]]; then
   echo "Usage:"
   echo "$0 --ZBX_SERVER_HOST='10.133.253.44' --TARGET_ZABBIX_PROXY='7.2.3' --TARGET_ZABBIX_AGENT2='7.2.3' --TARGET_ZABBIX_JAVA_GATEWAY='7.2.3' --PSK='7e26ebf6fcb6770d3827b6e59701387eab92e2a0e21669b0013b22fdf33754c4'"
   exit 1
fi


# check existence of repository
dpkg-query --showformat='${Version}' --show zabbix-release
if [ "$?" -ne "0" ]; then
# erase old repository
rm -rf "/tmp/zabbix-release.dep"
# download desired zabbix repository
curl https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb -o /tmp/zabbix-release.dep
# install
sudo dpkg -i /tmp/zabbix-release.dep && rm -rf "/tmp/zabbix-release.dep"
fi


# Microsoft repository
dpkg-query --showformat='${Version}' --show packages-microsoft-prod
if [ "$?" -ne "0" ]; then
curl -sSL -O https://packages.microsoft.com/config/ubuntu/$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)/packages-microsoft-prod.deb
# Install the package
sudo dpkg -i packages-microsoft-prod.deb
# Delete the file
rm -rf packages-microsoft-prod.deb
fi

# refresh apt cache
sudo apt update

# prepare troubleshooting utilities. allow to fetch passive metrics. allow to deliver data on demand (via cronjob). JSON beautifier
sudo apt-get -y install strace zabbix-get zabbix-sender jq tcpdump

# prepare proxy
zabbix_proxy --version | grep "$TARGET_ZABBIX_PROXY_SQLITE3"
if [ "$?" -ne "0" ]; then
AVAILABLE_ZABBIX_PROXY_SQLITE3=$(apt list -a zabbix-proxy-sqlite3 | grep "${TARGET_ZABBIX_PROXY_SQLITE3}" | grep -m1 -Eo "\S+:\S+" | head -1)
echo "$AVAILABLE_ZABBIX_PROXY_SQLITE3"
# check if variable is empty
if [ -z "$AVAILABLE_ZABBIX_PROXY_SQLITE3" ]; then
    echo "Version \"${TARGET_ZABBIX_PROXY_SQLITE3}\" of \"zabbix-proxy-sqlite3\" is not available in apt cache"
else
	zabbix_proxy --version | grep "$TARGET_ZABBIX_PROXY_SQLITE3" || sudo apt-get -y --allow-downgrades install zabbix-proxy-sqlite3=${AVAILABLE_ZABBIX_PROXY_SQLITE3}
	sudo systemctl enable zabbix-proxy
fi
fi


# create home for service user
mkdir -p /var/lib/zabbix

# enable include for exceptions. will be required only for special occasions when proxy have bigger load
mkdir -p /etc/zabbix/zabbix_proxy.d

# if PSK has been never configured, then install one
echo "${PSK}" | sudo tee /var/lib/zabbix/.key.psk

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
StartJavaPollers=5
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
MD5SUM_ZABBIX_PROXY_CONF=$(md5sum /etc/zabbix/zabbix_proxy.conf | md5sum | grep -Eo "^\S+")
# if checksum does not match with old 
grep "$MD5SUM_ZABBIX_PROXY_CONF" /etc/zabbix/md5sum.zabbix_proxy.conf 
if [ "$?" -ne "0" ]; then
# restart service
sudo systemctl restart zabbix-proxy
# reinstall checksum
echo "$MD5SUM_ZABBIX_PROXY_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_proxy.conf
fi


# Zabbix Java Gateway
dpkg-query --showformat='${Version}' --show zabbix-java-gateway | grep -P "^1:${TARGET_ZABBIX_JAVA_GATEWAY}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
AVAILABLE_ZABBIX_JAVA_GATEWAY=$(apt-cache madison zabbix-java-gateway | grep "zabbix-java-gateway.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_JAVA_GATEWAY}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_JAVA_GATEWAY" ]; then
    echo "Version \"${TARGET_ZABBIX_JAVA_GATEWAY}\" of \"zabbix-java-gateway\" is not available in apt cache"
else
    sudo apt-get -y install openjdk-11-jre-headless
    sudo apt-get -y --allow-downgrades install zabbix-java-gateway=${AVAILABLE_ZABBIX_JAVA_GATEWAY}
	sudo systemctl enable zabbix-java-gateway
fi
fi
echo '
LISTEN_IP="0.0.0.0"
LISTEN_PORT=10052
PID_FILE="/var/run/zabbix/zabbix_java_gateway.pid"
START_POLLERS=5
TIMEOUT=3
' | sudo tee /etc/zabbix/zabbix_java_gateway.conf
# if checksum file does not exist then create an empty one
[[ ! -f /etc/zabbix/md5sum.zabbix_java_gateway.conf ]] && sudo touch /etc/zabbix/md5sum.zabbix_java_gateway.conf
# validate current checksum
MD5SUM_ZABBIX_JAVA_GATEWAY_CONF=$(md5sum /etc/zabbix/zabbix_java_gateway.conf | md5sum | grep -Eo "^\S+")
# if checksum does not match with old 
grep "$MD5SUM_ZABBIX_JAVA_GATEWAY_CONF" /etc/zabbix/md5sum.zabbix_java_gateway.conf 
if [ "$?" -ne "0" ]; then
# restart service
sudo systemctl restart zabbix-java-gateway
# reinstall checksum
echo "$MD5SUM_ZABBIX_JAVA_GATEWAY_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_java_gateway.conf
fi


# check if installed version match desired version
dpkg-query --showformat='${Version}' --show zabbix-agent2 | grep -P "^1:${TARGET_ZABBIX_AGENT2}"
if [ "$?" -ne "0" ]; then
# observe if desired is available
AVAILABLE_ZABBIX_AGENT2=$(apt-cache madison zabbix-agent2 | grep "zabbix-agent2.*repo.zabbix.com" | grep -Eo "\S+${TARGET_ZABBIX_AGENT2}\S+")
# if variable not empty, then go for it
if [ -z "$AVAILABLE_ZABBIX_AGENT2" ]; then
    echo "Version \"${TARGET_ZABBIX_AGENT2}\" of \"zabbix-agent2\" is not available in apt cache"
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
MD5SUM_ZABBIX_AGENT2_CONF=$(grep -r "=" /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.d | sort | md5sum | grep -Eo "^\S+")
# if checksum does not match with old
grep "$MD5SUM_ZABBIX_AGENT2_CONF" /etc/zabbix/md5sum.zabbix_agent2.conf 
if [ "$?" -ne "0" ]; then
# restart service
sudo systemctl restart zabbix-agent2
# reinstall checksum
echo "$MD5SUM_ZABBIX_AGENT2_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_agent2.conf
fi


# query PostgreSQL ODBC support (from stock Ubuntu repository)
dpkg-query --showformat='${Version}' --show odbc-postgresql
if [ "$?" -ne "0" ]; then
# setup ODBC driver for PostgreSQL
sudo apt-get -y install odbc-postgresql
fi


# MSSQL ODBC
dpkg-query --showformat='${Version}' --show "mssql-tools18"
if [ "$?" -ne "0" ]; then
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


# Oracle ODBC
sudo ldconfig -p | grep oracle
if [ "$?" -ne "0" ]; then

sudo apt-get -y install unzip
curl https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip \
-o /tmp/instantclient-basic-linux.x64-23.7.0.25.01.zip

curl https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-odbc-linux.x64-23.7.0.25.01.zip \
-o /tmp/instantclient-odbc-linux.x64-23.7.0.25.01.zip

curl https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip \
-o /tmp/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip

sudo mkdir -p /opt/oracle
cd /opt/oracle
sudo mv /tmp/instantclient-basic-linux.x64-23.7.0.25.01.zip .
sudo mv /tmp/instantclient-odbc-linux.x64-23.7.0.25.01.zip .
sudo mv /tmp/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip .

sudo unzip -o instantclient-basic-linux.x64-23.7.0.25.01.zip
sudo unzip -o instantclient-odbc-linux.x64-23.7.0.25.01.zip
sudo mv *.zip /tmp
cd /opt/oracle/instantclient_23_7

echo "${PWD}" | sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf

# this should print nothing:
sudo ldconfig -p | grep oracle

# install refresh ldpath
sudo ldconfig

# this should print libraries recognized by OS
sudo ldconfig -p | grep oracle
fi


# proxy, agent, gateway must be in listening state
sudo ss --tcp --listen --numeric --process | grep -E "(10051|10050|10052)"
