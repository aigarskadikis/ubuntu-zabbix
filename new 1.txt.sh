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
