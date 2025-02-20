#!/usr/bin/env bash

# to simulate script with system which has less than 1GM of RAM execute:
# sudo dd if=/dev/zero of=/myswap1 bs=1M count=1024 && sudo chown root:root /myswap1 && sudo chmod 0600 /myswap1 && sudo mkswap /myswap1 && sudo swapon /myswap1 && free -m && sudo dd if=/dev/zero of=/myswap2 bs=1M count=1024 && sudo chown root:root /myswap2 && sudo chmod 0600 /myswap2 && sudo mkswap /myswap2 && sudo swapon /myswap2 && free -m && echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# exit on any failure
set -e

# print commands
set -o xtrace

# don't prompt for service restarts during "apt install"
[[ -f /etc/needrestart/conf.d/no-prompt.conf ]] || echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/no-prompt.conf

# Get the name of the primary adapter
ETHERNET_DEVICE=$(ip --brief link | awk '$1 !~ "lo" { print $1}' | tail -1)

# stealing naming from docker containers at 
# https://hub.docker.com/r/zabbix/zabbix-server-pgsql
# default zabbix_server.conf values:
ZBX_CACHESIZE="384M"
ZBX_HANODENAME="$(hostname -s)"
ZBX_HISTORYCACHESIZE="160M"	
ZBX_HISTORYINDEXCACHESIZE="40M"
ZBX_NODEADDRESS="$(ip -4 addr show $ETHERNET_DEVICE | grep -oP '(?<=inet\s)10+(\.\d+){3}')"
ZBX_STARTREPORTWRITERS="1"
ZBX_TRENDCACHESIZE="512M"
ZBX_TRENDFUNCTIONCACHESIZE="128M"
ZBX_VALUECACHESIZE="512M"

set +o xtrace
# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --DBHost=*)                                             DB_SERVER_HOST="${1#*=}"; shift ;;
        --DBPort=*)                                             DB_SERVER_PORT="${1#*=}"; shift ;;
        --DBPassword=*)                                      POSTGRES_PASSWORD="${1#*=}"; shift ;;
        --DBUser=*)                                              POSTGRES_USER="${1#*=}"; shift ;;
        --DBName=*)                                                POSTGRES_DB="${1#*=}"; shift ;;
        --CacheSize=*)                                           ZBX_CACHESIZE="${1#*=}"; shift ;;
        --HANodeName=*)                                         ZBX_HANODENAME="${1#*=}"; shift ;;
        --HistoryCacheSize=*)                             ZBX_HISTORYCACHESIZE="${1#*=}"; shift ;;
        --HistoryIndexCacheSize=*)                   ZBX_HISTORYINDEXCACHESIZE="${1#*=}"; shift ;;
        --NodeAddress=*)                                       ZBX_NODEADDRESS="${1#*=}"; shift ;;
        --StartReportWriters=*)                         ZBX_STARTREPORTWRITERS="${1#*=}"; shift ;;
        --TrendCacheSize=*)                                 ZBX_TRENDCACHESIZE="${1#*=}"; shift ;;
        --TrendFunctionCacheSize=*)                 ZBX_TRENDFUNCTIONCACHESIZE="${1#*=}"; shift ;;
        --ValueCacheSize=*)                                 ZBX_VALUECACHESIZE="${1#*=}"; shift ;;
        --WebServiceURL=*)                                   ZBX_WEBSERVICEURL="${1#*=}"; shift ;;
        --TARGET_ZABBIX_SERVER_PGSQL=*)             TARGET_ZABBIX_SERVER_PGSQL="${1#*=}"; shift ;;
        --TARGET_ZABBIX_AGENT2=*)                         TARGET_ZABBIX_AGENT2="${1#*=}"; shift ;;
        --POSTGRES_SUPER_USER=*)                           POSTGRES_SUPER_USER="${1#*=}"; shift ;;
        --POSTGRES_SUPER_PASS=*)                           POSTGRES_SUPER_PASS="${1#*=}"; shift ;;
        --NETINT=*)                                                     NETINT="${1#*=}"; shift ;;
        --Server=*)                                            ZBX_SERVER_HOST="${1#*=}"; shift ;;
        --ServerActive=*)                                    ZBX_ACTIVESERVERS="${1#*=}"; shift ;;
        --Repo=*)                                                     ZBX_REPO="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done
set -o xtrace

# Set mandatory arguments
if [[ -z "$DB_SERVER_HOST" || -z "$DB_SERVER_PORT" || -z "$POSTGRES_PASSWORD" || -z "$POSTGRES_USER" || -z "$POSTGRES_DB" || -z "$TARGET_ZABBIX_SERVER_PGSQL" || -z "$TARGET_ZABBIX_AGENT2" || -z "$ZBX_WEBSERVICEURL" || -z "$POSTGRES_SUPER_USER" || -z "$POSTGRES_SUPER_PASS" || -z "$ZBX_SERVER_HOST" || -z "$ZBX_ACTIVESERVERS" ]]; then
   echo "Usage:"
   echo "$0 --DBHost='10.133.112.87' --DBPort='5432' --DBPassword='zabbix' --DBUser='zabbix' --DBName='zabbix' --TARGET_ZABBIX_SERVER_PGSQL='7.2.3' --TARGET_ZABBIX_AGENT2='7.2.3' --WebServiceURL='http://10.133.253.45:10053/report' --POSTGRES_SUPER_USER='postgres' --POSTGRES_SUPER_PASS='zabbix' --Server='app1,app2' --ServerActive='app1;app2' --Repo='https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.2+ubuntu22.04_all.deb'"
   exit 1
fi

# from https://www.postgresql.org/download/linux/ubuntu/
sudo apt-get -y install curl ca-certificates lsb-release
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo chmod 644 /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

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

# prepare troubleshooting utilities, allow to fetch passive metrics, allow to deliver data on demand, JSON beautifier
sudo apt-get -y install strace zabbix-get zabbix-sender jq postgresql-client-17 zabbix-sql-scripts

# create DB, user "zabbix" must exist before
# createuser --pwprompt zabbix

PGPASSWORD=${POSTGRES_PASSWORD} PGHOST=${DB_SERVER_HOST} PGUSER=${POSTGRES_USER} PGPORT=${DB_SERVER_PORT} \
psql --tuples-only --no-align --command="
SELECT datname FROM pg_database;
" | grep -E "^${POSTGRES_DB}$"

DB_EXISTS=$?
			 

# temporarily allow failures
# the line below should fail if the DB is not initialied
set +e
PGPASSWORD=${POSTGRES_PASSWORD} PGHOST=${DB_SERVER_HOST} PGUSER=${POSTGRES_USER} PGPORT=${DB_SERVER_PORT} \
psql --tuples-only --no-align --command="
select userid from users limit 1;
"

DB_INITIALIZED=$?
set -e

if [ $DB_EXISTS -ne "0" ] | [ $DB_INITIALIZED -ne "0" ]; then
# prepare new
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | \
PGPASSWORD=${POSTGRES_PASSWORD} PGHOST=${DB_SERVER_HOST} PGUSER=${POSTGRES_USER} PGPORT=${DB_SERVER_PORT} psql ${POSTGRES_DB}

else
echo "database \"${POSTGRES_DB}\" already exist"
fi

# temporarily allow failures
# the line below should fail on the first run
set +e
# prepare backend
zabbix_server --version | grep "$TARGET_ZABBIX_SERVER_PGSQL"
if [ "$?" -ne "0" ]; then
set -e
AVAILABLE_ZABBIX_SERVER=$(apt list -a zabbix-server-pgsql | grep "${TARGET_ZABBIX_SERVER_PGSQL}" | grep -m1 -Eo "\S+:\S+" | head -1)
echo "$AVAILABLE_ZABBIX_SERVER"
# check if variable is empty
if [ -z "$AVAILABLE_ZABBIX_SERVER" ]; then
    echo "Version \"${TARGET_ZABBIX_SERVER_PGSQL}\" of \"zabbix-server-pgsql\" is not available in apt cache"
else
	zabbix_server --version | grep "$TARGET_ZABBIX_SERVER_PGSQL" || sudo apt-get -y --allow-downgrades install zabbix-server-pgsql=${AVAILABLE_ZABBIX_SERVER}
fi
fi
set -e


CONF=/etc/zabbix/zabbix_server.conf

if [ -f "$CONF" ]; then

# install settings in alphabetical order
echo "
CacheSize=${ZBX_CACHESIZE}
DBHost=${DB_SERVER_HOST}
DBName=${POSTGRES_DB}
DBPassword=${POSTGRES_PASSWORD}
DBPort=5432
DBUser=${POSTGRES_USER}
EnableGlobalScripts=0
HistoryCacheSize=${ZBX_HISTORYCACHESIZE}
HistoryIndexCacheSize=${ZBX_HISTORYINDEXCACHESIZE}
Include=/etc/zabbix/zabbix_server.d/*.conf
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=0
LogSlowQueries=3000
PidFile=/run/zabbix/zabbix_server.pid
SNMPTrapperFile=/var/log/snmptrap/snmptrap.log
SocketDir=/run/zabbix
StartReportWriters=${ZBX_STARTREPORTWRITERS}
StatsAllowedIP=127.0.0.1
Timeout=30
TrendCacheSize=${ZBX_TRENDCACHESIZE}
TrendFunctionCacheSize=${ZBX_TRENDFUNCTIONCACHESIZE}
ValueCacheSize=${ZBX_VALUECACHESIZE}
WebServiceURL=${ZBX_WEBSERVICEURL}
" | sudo tee "$CONF"

# install uniqueness per servers (this will allow to keep checksum of zabbix_server.conf the same between active/standby nodes
echo "HANodeName=${ZBX_HANODENAME}" | sudo tee /etc/zabbix/zabbix_server.d/HANodeName.conf
echo "NodeAddress=${ZBX_NODEADDRESS}" | sudo tee /etc/zabbix/zabbix_server.d/NodeAddress.conf

sudo chmod 644 $CONF
sudo chmod 644 /etc/zabbix/zabbix_server.d/HANodeName.conf
sudo chmod 644 /etc/zabbix/zabbix_server.d/NodeAddress.conf


fi

# if checksum file does not exist then create an empty one
if [ ! -f /etc/zabbix/md5sum.zabbix_server.conf ]; then
sudo touch /etc/zabbix/md5sum.zabbix_server.conf
sudo chmod 644 /etc/zabbix/md5sum.zabbix_server.conf
fi
# validate current checksum
MD5SUM_ZABBIX_SERVER_CONF=$(grep -r "=" /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.d | sort | md5sum | grep -Eo "^\S+")
# if checksum does not match with old

# temporarily allow failures
# the line below should fail when the config changes
set +e
grep "$MD5SUM_ZABBIX_SERVER_CONF" /etc/zabbix/md5sum.zabbix_server.conf
if [ "$?" -ne "0" ]; then
set -e
# restart service
sudo systemctl restart zabbix-server
# reinstall checksum
echo "$MD5SUM_ZABBIX_SERVER_CONF" | sudo tee /etc/zabbix/md5sum.zabbix_server.conf
fi
set -e


# enable at startup
sudo systemctl enable zabbix-server

# print current configuration:
grep -Eor ^[^#]+ /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.d | sort

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
