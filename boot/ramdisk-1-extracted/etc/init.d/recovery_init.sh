#!/bin/sh

MISC_DEVICE="/dev/block/platform/misc"
BOOTMETA_TOOL="bootmeta_utility"
SET_BOOT_MODE_COMMAND="${BOOTMETA_TOOL} -m"
GET_BOOT_MODE_COMMAND="${BOOTMETA_TOOL} -g"
BOOT_MODE=""
BOOT_MODE_NORMAL="0" # "normal" mode

# Wait for data and misc devices to be ready
wait_for_device() {
    local DEVICE_NAME="${1}"
    i=1
    while [ "$i" -le 30 ]; do
        if [ -e "${DEVICE_NAME}" ]; then
            echo "${DEVICE_NAME} is ready now."
            return 0
        fi
        echo "${DEVICE_NAME} is not ready.  Waited for ${i} second"
        sleep 1
        i=$((i + 1))
    done
    return 1
}

if wait_for_device "${MISC_DEVICE}"; then
    BOOT_MODE=$(${GET_BOOT_MODE_COMMAND})
    echo "Boot Mode: ${BOOT_MODE}"
fi

# get boot mode
if [ "${BOOT_MODE}" = "1" ]; then
    echo "Running FR script"
    /etc/init.d/factory_reset.sh
elif [ "${BOOT_MODE}" = "2" ]; then
    echo "Running OTA script"
    /etc/init.d/recovery_ota.sh
fi