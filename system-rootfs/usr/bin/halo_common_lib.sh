#!/bin/sh

HALO_MNT_DIR=/run/halo
HALO_DATA_DIR=/var/lib/data/halo
HALO_PROVISION_DIR=${HALO_DATA_DIR}/provision
HALO_LOG_DIR=${HALO_DATA_DIR}/var/log
HALO_BOOT_RSN=${HALO_DATA_DIR}/reboot_reason
MFG=${HALO_MNT_DIR}/run/mfg
HLOG=${HALO_LOG_DIR}/halo_cli.log
HDIR=${HALO_MNT_DIR}/etc/hub-core.conf.d
WORKDIR=${HALO_PROVISION_DIR}/workdir
HALO_LOG=${HALO_LOG_DIR}/halo_log.log
HALO_CLI=/usr/bin/halo_cli
DEF_WORLD=prdw-hub-us.prd.rings.solutions
RINGNET_ID_MASK=0x1FFFFFFFFF

# Retry Parameters
FIRST_RETRY_IDX=0 #Attempt first provisoning retry in 30 secs
REBOOT_DELAY=180 #Retry provisioning after REBOOT_DELAY in case of reboot

halo_log_level_error=0
halo_log_level_warning=1
halo_log_level_info=2
halo_log_level_debug=3
halo_log_level_extended=4

halo_log_level=$halo_log_level_info

halo_log_error()
{
    if [ $halo_log_level_error -le $halo_log_level ]; then
        echo "E $(date) $1 $2" >> $HALO_LOG
    fi
}

halo_log_warning()
{
    if [ $halo_log_level_warning -le $halo_log_level ]; then
        echo "W $(date) $1 $2" >> $HALO_LOG
    fi
}

halo_log_info()
{
    if [ $halo_log_level_info -le $halo_log_level ]; then
        echo "I $(date) $1 $2" >> $HALO_LOG
    fi
}

halo_log_debug()
{
    if [ $halo_log_level_debug -le $halo_log_level ]; then
        echo "D $(date) $1 $2" >> $HALO_LOG
    fi
}

# Special extended logging for long strings since log -t doesn't support them.
halo_log_extended()
{
    FIRST_CHAR=1
    MAX_LOG_LEN=1023

    if [ $halo_log_level_extended -le $halo_log_level ]; then
        verbose_string=$(echo "$2")
        verbose_string_len=${#verbose_string}
        string_counter=$verbose_string_len
        string_head=$FIRST_CHAR
        while [ $string_counter -gt $MAX_LOG_LEN ]; do
            string_tail=$((string_head+MAX_LOG_LEN-FIRST_CHAR))
            cut_string=`echo "$verbose_string" | cut -c$string_head-$string_tail`
            echo "V $(date) halo-provision $cut_string" >> $HALO_LOG
            string_head=$((string_head+MAX_LOG_LEN))
            string_counter=$((string_counter-MAX_LOG_LEN))
        done
        cut_string=`echo "$verbose_string" | cut -c$string_head-$verbose_string_len`
        echo "V $(date) $1 $cut_string" >> $HALO_LOG
    fi
}
