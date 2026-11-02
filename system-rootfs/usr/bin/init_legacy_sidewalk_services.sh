#!/bin/sh

HALO_PATH=/usr/bin
VETC_PATH=/etc/halo_config
DETC_PATH=/run/halo/etc

[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="sidewalk-services"

# update boot reason
if [ "$#" -eq "0" ]; then
    if [ -e ${HALO_BOOT_RSN} ]; then
        # reboot_reason file is already exist, this is a reboot
        echo "normal_reboot" > ${HALO_BOOT_RSN}
    else
        # create reboot_reason file and put initial boot reason
        touch ${HALO_BOOT_RSN}
        echo "initial_boot" > ${HALO_BOOT_RSN}
    fi
fi

halo_log_info $LOG_TAG  "*** >>> Sidewalk Services Start <<< ***"

cp -aRfP $VETC_PATH/* $DETC_PATH/.

sync /mnt/halo

if [ "$(ls $DETC_PATH/hub-core.conf.d/*.conf)" != "" ]; then
    setprop vendor.halo.hubcore.config true
fi
halo_log_info $LOG_TAG  "*** >>> Sidewalk Services Exit <<< ***"
