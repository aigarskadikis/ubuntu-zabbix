#!/usr/bin/env bash

# don't prompt for service restarts during "apt install"
echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# stealing naming from docker containers at 
# https://hub.docker.com/r/zabbix/zabbix-server-pgsql
# default zabbix_server.conf values:
DB_SERVER_HOST="10.133.253.45"
DB_SERVER_PORT="5432"
POSTGRES_DB="zabbix"
POSTGRES_PASSWORD="zabbix"
POSTGRES_USER="zabbix"
ZBX_CACHESIZE="384M"
ZBX_HANODENAME="$(hostname -s)"
ZBX_HISTORYCACHESIZE="160M"
ZBX_HISTORYINDEXCACHESIZE="40M"
ZBX_NODEADDRESS="$(ip a | grep -Eo "[0-9]+\.133\.[0-9]+\.[0-9]+" | grep -v "10.133.255.255")"
ZBX_STARTREPORTWRITERS="1"
ZBX_TRENDCACHESIZE="512M"
ZBX_TRENDFUNCTIONCACHESIZE="128M"
ZBX_VALUECACHESIZE="512M"
ZBX_WEBSERVICEURL="http://web.local.lan:10053/report"


# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --DBHost=*)                                     DB_SERVER_HOST="${1#*=}"; shift ;;
        --DBPort=*)                                     DB_SERVER_PORT="${1#*=}"; shift ;;
        --DBPassword=*)                              POSTGRES_PASSWORD="${1#*=}"; shift ;;
        --DBUser=*)                                      POSTGRES_USER="${1#*=}"; shift ;;
        --DBName=*)                                        POSTGRES_DB="${1#*=}"; shift ;;
        --CacheSize=*)                                   ZBX_CACHESIZE="${1#*=}"; shift ;;
        --HANodeName=*)                                 ZBX_HANODENAME="${1#*=}"; shift ;;
        --HistoryCacheSize=*)                     ZBX_HISTORYCACHESIZE="${1#*=}"; shift ;;
        --HistoryIndexCacheSize=*)           ZBX_HISTORYINDEXCACHESIZE="${1#*=}"; shift ;;
        --NodeAddress=*)                               ZBX_NODEADDRESS="${1#*=}"; shift ;;
        --StartReportWriters=*)                 ZBX_STARTREPORTWRITERS="${1#*=}"; shift ;;
        --TrendCacheSize=*)                         ZBX_TRENDCACHESIZE="${1#*=}"; shift ;;
        --TrendFunctionCacheSize=*)         ZBX_TRENDFUNCTIONCACHESIZE="${1#*=}"; shift ;;
        --ValueCacheSize=*)                         ZBX_VALUECACHESIZE="${1#*=}"; shift ;;
        --WebServiceURL=*)                           ZBX_WEBSERVICEURL="${1#*=}"; shift ;;
        --TARGET_SRV_VERSION=*)                     TARGET_SRV_VERSION="${1#*=}"; shift ;;
        --TARGET_GNT_VERSION=*)                     TARGET_GNT_VERSION="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done


# Set mandatory arguments
if [[ -z "$DB_SERVER_HOST" || -z "$DB_SERVER_PORT" || -z "$POSTGRES_PASSWORD" || -z "$POSTGRES_USER" || -z "$POSTGRES_DB"  || -z "$TARGET_SRV_VERSION"  || -z "$TARGET_GNT_VERSION" ]]; then
   echo "Usage: $0 --DBHost='10.133.253.45' --DBPort='5432' --DBPassword='zabbix' --DBUser='zabbix' --DBName='zabbix' --TARGET_SRV_VERSION='7.2.3' --TARGET_GNT_VERSION='7.2.0'"
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

# prepare troubleshooting utilities
sudo apt -y install strace

# allow to fetch passive metrics
sudo apt -y install zabbix-get

# allow to deliver data on demand (via cronjob)
sudo apt -y install zabbix-sender

# JSON beautifier 
sudo apt -y install jq

# prepare Zabbix application server

zabbix_server --version | grep "$TARGET_SRV_VERSION"
if [ "$?" -ne "0" ]; then

SRV_VERSION_AVAILABLE=$(apt list -a zabbix-server-pgsql | grep "${TARGET_SRV_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
echo "$SRV_VERSION_AVAILABLE"
# check if variable is empty
if [ -z "$SRV_VERSION_AVAILABLE" ]; then
    echo "Version \"${TARGET_SRV_VERSION}\" of \"zabbix-server-pgsql\" is not available in apt cache"
else
	sudo apt -y --allow-downgrades install zabbix-server-pgsql=${SRV_VERSION_AVAILABLE}
fi

fi


CONF=/etc/zabbix/zabbix_server.conf

if [ -f "$CONF" ]; then

# set certain settings to be maintainable
grep ^CacheSize $CONF || sed -i "s|^# CacheSize=|CacheSize=|" $CONF
grep ^DBHost $CONF || sed -i "s|^# DBHost=|DBHost=|" $CONF
grep ^DBName $CONF || sed -i "s|^# DBName=|DBName=|" $CONF
grep ^DBPassword $CONF || sed -i "s|^# DBPassword=|DBPassword=|" $CONF
grep ^DBPort $CONF || sed -i "s|^# DBPort=|DBPort=|" $CONF
grep ^DBUser $CONF || sed -i "s|^# DBUser=|DBUser=|" $CONF
grep ^HistoryCacheSize $CONF || sed -i "s|^# HistoryCacheSize=|HistoryCacheSize=|" $CONF
grep ^HistoryIndexCacheSize $CONF || sed -i "s|^# HistoryIndexCacheSize=|HistoryIndexCacheSize=|" $CONF
grep ^StartReportWriters $CONF || sed -i "s|^# StartReportWriters=|StartReportWriters=|" $CONF
grep ^TrendCacheSize $CONF || sed -i "s|^# TrendCacheSize=|TrendCacheSize=|" $CONF
grep ^TrendFunctionCacheSize $CONF || sed -i "s|^# TrendFunctionCacheSize=|TrendFunctionCacheSize=|" $CONF
grep ^ValueCacheSize $CONF || sed -i "s|^# ValueCacheSize=|ValueCacheSize=|" $CONF
grep ^WebServiceURL $CONF || sed -i "s|^# WebServiceURL=|WebServiceURL=|" $CONF


# force new values
sudo sed -i "s|^CacheSize=.*|CacheSize=${ZBX_CACHESIZE}|" $CONF
sudo sed -i "s|^DBHost=.*|DBHost=${DB_SERVER_HOST}|" $CONF
sudo sed -i "s|^DBName=.*|DBName=${POSTGRES_DB}|" $CONF
sudo sed -i "s|^DBPassword=.*|DBPassword=${POSTGRES_PASSWORD}|" $CONF
sudo sed -i "s|^DBPort=.*|DBPort=${DB_SERVER_PORT}|" $CONF
sudo sed -i "s|^DBUser=.*|DBUser=${POSTGRES_USER}|" $CONF
sudo sed -i "s|^HistoryCacheSize=.*|HistoryCacheSize=${ZBX_HISTORYCACHESIZE}|" $CONF
sudo sed -i "s|^HistoryIndexCacheSize=.*|HistoryIndexCacheSize=${ZBX_HISTORYINDEXCACHESIZE}|" $CONF
sudo sed -i "s|^StartReportWriters=.*|StartReportWriters=${ZBX_STARTREPORTWRITERS}|" $CONF
sudo sed -i "s|^TrendCacheSize=.*|TrendCacheSize=${ZBX_TRENDCACHESIZE}|" $CONF
sudo sed -i "s|^TrendFunctionCacheSize=.*|TrendFunctionCacheSize=${ZBX_TRENDFUNCTIONCACHESIZE}|" $CONF
sudo sed -i "s|^ValueCacheSize=.*|ValueCacheSize=${ZBX_VALUECACHESIZE}|" $CONF
sudo sed -i "s|^WebServiceURL=.*|WebServiceURL=${ZBX_WEBSERVICEURL}|" $CONF

# enable Include
sudo mkdir -p /etc/zabbix/zabbix_server.d
grep ^Include /etc/zabbix/zabbix_server.conf || echo 'Include=/etc/zabbix/zabbix_server.d' | sudo tee --append /etc/zabbix/zabbix_server.conf

# install uniqueness per servers (this will allow to keep checksum of zabbix_server.conf the same between active/standby nodes
echo "HANodeName=${ZBX_HANODENAME}" | sudo tee /etc/zabbix/zabbix_server.d/HANodeName.conf
echo "NodeAddress=${ZBX_NODEADDRESS}" | sudo tee /etc/zabbix/zabbix_server.d/NodeAddress.conf

fi

# if checksum file does not exist then create an empty one
[[ ! -f /etc/zabbix/md5sum.zabbix_server.conf ]] && sudo touch /etc/zabbix/md5sum.zabbix_server.conf

# validate current checksum
MD5SUM_SRV_CONF=$(md5sum /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.d/* | md5sum | grep -Eo "^\S+")

# if checksum does not match with old 
grep "$MD5SUM_SRV_CONF" /etc/zabbix/md5sum.zabbix_server.conf 
if [ "$?" -ne "0" ]; then

# restart service
sudo systemctl restart zabbix-server

# reinstall checksum
echo "$MD5SUM_SRV_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_server.conf

fi


# enable at startup
sudo systemctl enable zabbix-server


# print current configuration:
grep -Eor ^[^#]+ /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.d | sort

# force agent2 to be on specific version
GNT_VERSION_AVAILABLE=$(apt list -a zabbix-agent2 | grep "${TARGET_GNT_VERSION}" | grep -m1 -Eo "\S+:\S+" | head -1)
# check if variable is empty
if [ -z "$SRV_VERSION_AVAILABLE" ]; then
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
