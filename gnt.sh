#!/usr/bin/env bash

# this script maintains /etc/zabbix/zabbix_agent2.conf and restarts service if necessary

# to install agent2 for various Linux OS, follow wizard from:
# https://www.zabbix.com/download?zabbix=7.2&os_distribution=ubuntu&os_version=22.04&components=agent_2&db=&ws=

ZBX_SERVER="127.0.0.1"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ServerActive=*)                        ZBX_SERVERACTIVE="${1#*=}"; shift ;;
        --Server=*)                                    ZBX_SERVER="${1#*=}"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

if [[ -z "$ZBX_SERVERACTIVE" || -z "$ZBX_SERVER" ]]; then
   echo "Usage:"
   echo "$0 --ServerActive='prx1;prx2;prx3' --Server='prx1,prx2,prx3'"
   echo "$0 --ServerActive='prx1;prx2;prx3' --Server='127.0.0.1'"
   echo "$0 --ServerActive='127.0.0.1' --Server='127.0.0.1'"
   exit 1
fi

# all possible agent2 7.2 settings on Linux
# https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/src/go/conf/zabbix_agent2.conf?at=refs%2Fheads%2Frelease%2F7.2

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
Server=${ZBX_SERVER}
ServerActive=${ZBX_SERVERACTIVE}
Timeout=28
UnsafeUserParameters=0
" | grep -vE "^$" | sudo tee /etc/zabbix/zabbix_agent2.conf


# INSTALL CUSTOM CAPABILITIES

# print all TCP listening ports
echo '
# print all TCP listening ports
UserParameter=ss.tcp.listen.numeric.process,sudo /usr/bin/ss --tcp --tcp --listen --numeric --process
' | grep -vE "^$" | sudo tee /etc/zabbix/zabbix_agent2.d/ss.tcp.listen.numeric.process.conf
cd /etc/sudoers.d
echo 'zabbix ALL=(ALL) NOPASSWD: /usr/bin/ss --tcp --tcp --listen --numeric --process' | sudo tee zabbix_ss_tcp_listen_numeric_process
sudo chmod 0440 zabbix_ss_tcp_listen_numeric_process


# print biggest folders in root
echo '
# print biggest folders in root
UserParameter=big.dirs.root,sudo /usr/bin/du / 2>/dev/null | sort -n -r | head -n 50
' | grep -vE "^$" | sudo tee /etc/zabbix/zabbix_agent2.d/big.dirs.root.conf
cd /etc/sudoers.d
echo 'zabbix ALL=(ALL) NOPASSWD: /usr/bin/du / 2>/dev/null | sort -n -r | head -n 50' | sudo tee zabbix_big_dirs_root
sudo chmod 0440 zabbix_big_dirs_root


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
