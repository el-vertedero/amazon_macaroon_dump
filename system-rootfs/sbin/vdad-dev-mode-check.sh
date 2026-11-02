#!/bin/sh

VDAD_NETWORK_MODE="com.amazon.devconf/system/developer/vda_network_mode"
VDAD_DEVELOPER_MODE="com.amazon.devconf/system/security/developer_mode"

count=0
while [[ $count -le 10 ]]; do
    NETWORK_MODE=$(vdcm get ${VDAD_NETWORK_MODE} | awk '{print $3}' | tr -d "\'")
    net_rc=$?
    DEVELOPER_MODE=$(vdcm get ${VDAD_DEVELOPER_MODE} | awk '{print $3}' | tr -d "\'")
    dev_rc=$?
    if [[ $net_rc -eq 0 && $dev_rc -eq 0 ]];then
        break
    fi
    sleep 1
    ((count++))
done


VDAD_STATE=$(systemctl is-active amzn-vdad.service)

if [[ "${NETWORK_MODE}" == "enable" ]];then
    echo "VDAD network mode enabled"  >> /dev/kmsg
    exit 0
elif [[ "${DEVELOPER_MODE}" == "enable" ]];then
    echo "VDAD developer mode enabled"  >> /dev/kmsg
    exit 0
elif [ ${VDAD_STATE} != "active" ];then
    echo "VDAD service not running, restart"  >> /dev/kmsg
    exit 0
fi
echo "VDAD service is running" >> /dev/kmsg
exit -1
