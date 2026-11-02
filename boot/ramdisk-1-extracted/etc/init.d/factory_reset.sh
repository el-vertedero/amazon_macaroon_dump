#!/bin/sh

# Partition definitions
DATA_DEVICE="/dev/block/platform/userdata"
MISC_DEVICE="/dev/block/platform/misc"
CACHE_DEVICE="/dev/block/platform/cache"

# Partition mount config
DATA_MOUNT="/rootfs.rw"
USERDATA_PREFIX="${DATA_MOUNT}/upperdir"
ROOT_MOUNT="/rootfs.ro"
CACHE_MOUNT="/cache"
CACHE_FR_DIR="${CACHE_MOUNT}/recovery"
VENDOR_MOUNT="/vendor"
BACKUP_SCRATCH_DIR="/tmp"
DISK_ENCRYPTION_ERROR="/tmp/disk-encryption-error"
DISK_ENCRYPTION_SCRIPT="${ROOT_MOUNT}/sbin/disk-encryption.sh"

# Command definitions
DISCARD_TOOL="blkdiscard"
UBI_DISCARD_TOOL="ubiupdatevol"
DISCARD_COMMAND="${DISCARD_TOOL} -s"
UBI_DISCARD_COMMAND="${UBI_DISCARD_TOOL} -t"
BOOTMETA_TOOL="bootmeta_utility"
SET_BOOT_MODE_COMMAND="${BOOTMETA_TOOL} -m"
GET_BOOT_MODE_COMMAND="${BOOTMETA_TOOL} -g"
SET_BOOT_STATUS_COMMAND="${BOOTMETA_TOOL} -s"
IS_BOOT_RETRYABLE_COMMAND="${BOOTMETA_TOOL} -i"
GET_BOOT_ARGS_COMMAND="${BOOTMETA_TOOL} -u"
SET_BOOT_ARGS_COMMAND="${BOOTMETA_TOOL} -t"
IS_BOOT_FLAG_ENABLED_COMMAND="${BOOTMETA_TOOL} -e"
TOYBOX_COMMAND="${ROOT_MOUNT}/bin/toybox"
CP_COMMAND="${TOYBOX_COMMAND} cp"
if [ ! -f "${TOYBOX_COMMAND}" ]; then
    CP_COMMAND="cp"
fi

FR_ANIMATION="/usr/bin/fanimation"
FR_ALLOWLIST_CLI="${ROOT_MOUNT}/usr/bin/vfr-allowlist"

# Variable definitions
BOOT_MODE=""
BOOT_MODE_NORMAL="0" # "normal" mode
BOOT_STATUS="0" # BOOTMETA_STATUS_SUCCESS
FR_DISABLED_BOOT_FLAG=0
FR_TYPE=""
LOCALE="en_US" # default to US english
ALLOWLIST_PATH=""
ALLOWLIST_ENCRYPTED_CONTENT="n"
ENCRYPTION_BOOT_MODE="recovery"
ENCRYPTION_POLICY_CONF="${ROOT_MOUNT}/etc/disk-encryption.conf"
RESTORE_FLAG="FALSE"
BEFORE_RECOVERY_REBOOT_LOG_FILE=${CACHE_FR_DIR}/frlog
FR_LOG_FILE=${CACHE_FR_DIR}/log
FR_METRICS_FILE=${CACHE_FR_DIR}/metrics
UPTIME_CMD="awk '{print \$1}' /proc/uptime"
UPTIME_IN_MS_CMD="awk '{print \$1*1000}' /proc/uptime"
FRTAB_PATH="/etc/factory-reset-config/frtab"
FRTAB_FLAG="FALSE"
RESCUE_PARTY="0"
RESCUE_PARTY_ARGUMENTS=""
RESCUE_PARTY_USER_SELECTION_FILE="${CACHE_FR_DIR}/rescueparty_user_selection"
RESCUE_PARTY_UI="/usr/bin/rescue-party-recovery-ui"
DSN_PATH="/proc/idme/serial"
OS_RELEASE_PATH="${ROOT_MOUNT}/etc/os-release"
DSN=""
SYSTEM_VERSION=""
RESCUE_PARTY_UI_ARGS=""
RESCUE_PARTY_SELECTION_REBOOT="REBOOT"
RESCUE_PARTY_SELECTION_FACTORY_RESET="FACTORY_RESET"
RESCUE_PARTY_SELECTION_ERROR="ERROR"
# Note: Any exit code other than 0 (reboot) or 1 (factory reset) is treated as error.
RESCUE_PARTY_EXIT_REBOOT=0
RESCUE_PARTY_EXIT_FACTORY_RESET=1
MINIMUM_PROCESS_TIME_IN_MS=3000
DROPBOX_SYSTEM_PATH="${USERDATA_PREFIX}/var/lib/data/ace/dropbox/vault/system/var_log"
DROPBOX_KERNEL_PATH="${USERDATA_PREFIX}/var/lib/data/ace/dropbox/vault/kernel/var_log"

log() {
    # Use CPU clock for more granular time
    timestamp=$(eval ${UPTIME_CMD})
    if [ -d ${CACHE_FR_DIR} ]; then
        echo ${timestamp} $1 | tee -a ${FR_LOG_FILE}
    else
        echo ${timestamp} $1
    fi
}

add_int_metric() {
    echo "int:$1:$2" | tee -a ${FR_METRICS_FILE}
}

add_counter_metric() {
    add_int_metric $1 1
}

# Read fr specific arguments from 
# bootloader metadata
read_bootmeta_args() {
    BOOT_MODE=$(${GET_BOOT_MODE_COMMAND})
    BOOT_ARGS=$(${GET_BOOT_ARGS_COMMAND})
    log "Boot Mode: ${BOOT_MODE}"
    log "Boot Args: ${BOOT_ARGS}"
    args=$(echo $BOOT_ARGS | tr ";" "\n")
    for arg in $args; do
        optarg=$(expr "x$arg" : 'x[^=]*=\(.*\)')
        case $arg in
        type=*)
            FR_TYPE=$optarg
            ;;
        locale=*)
            LOCALE=$optarg
            ;;
        rescue_party=*)
            RESCUE_PARTY=$optarg
            ;;
        rescue_party_arguments=*)
            RESCUE_PARTY_ARGUMENTS=$optarg
            ;;
        *)
            ## Ingore the unsupported options
            log "Ignore unknown option: $arg $optarg."
            ;;
        esac
    done
}

# Wait for data and misc devices to be ready
 wait_for_device() {
    local DEVICE_NAME="${1}"
    i=1
    while [ "$i" -le 30 ]; do
         if [ -e "${DEVICE_NAME}" ]; then
             log "${DEVICE_NAME} is ready now."
             return 0
         fi
         log "${DEVICE_NAME} is not ready.  Waited for ${i} second"
         sleep 1
         i=$((i + 1))
    done
    return 1
 }

set_boot_mode_normal_and_clear_args() {
    if ${SET_BOOT_MODE_COMMAND} ${BOOT_MODE_NORMAL} &> /dev/null; then
        log "Boot mode set to normal"
	if ${SET_BOOT_ARGS_COMMAND} "" &> /dev/null; then
            log "Boot args cleared"
        else
            log "Unable to clear boot args"
        fi
    else
        log "Unable to set boot mode to normal"
    fi
}

exec_on_failure() {
    # Set error status
    if ${SET_BOOT_STATUS_COMMAND} ${BOOT_STATUS} &> /dev/null; then
        log "Error status was set to ${BOOT_STATUS}"
    fi
    # Check if we can try factory resetting again
    _retryable=$(${IS_BOOT_RETRYABLE_COMMAND})
    if [ "${_retryable}" = "0" ]; then
        log "Max reboot attempts reached, setting boot mode back to normal"
        set_boot_mode_normal_and_clear_args
        add_counter_metric "FR_MAX_REBOOT_ATTEMPT"

    else
        log "Retrying factory reset now!"
    fi
    exit
}

# This function checks if FR is disabled
# on the device. If so, update the boot
# mode back to "normal" and update the 
# boot_status, so that userspace can know
# the latest status.
safe_exit_fr_if_disabled() {
    _is_disabled=$(${IS_BOOT_FLAG_ENABLED_COMMAND} ${FR_DISABLED_BOOT_FLAG})
    if [ "${_is_disabled}" = "1" ]; then
        log "FR is disabled, do safe exit !!!"
        # Update boot mode to normal, so that device can boot normally.
        set_boot_mode_normal_and_clear_args
        
        BOOT_STATUS="12" # BOOTMETA_STATUS_FR_DISABLED	
        if ${SET_BOOT_STATUS_COMMAND} ${BOOT_STATUS} &> /dev/null; then
            log "Boot status was set to ${BOOT_STATUS}"
        fi
        # Safely exit
        exit
    fi
}

# function to handle vendor specific pre/post FR hooks
run_platform_fr_hook() {
     platform_fr_hook="/etc/platform-fr-hook.sh"
     if [ -f "$platform_fr_hook" ]; then
         log "run platform specific factory reset hook: $platform_fr_hook $@ ..."
         $platform_fr_hook $@
         [ $? -eq 0 ] || fatal "Failed to run $platform_fr_hook $@"
     fi
 }

# unmount partitions before erase/reformat
unmount_if_mounted() {
    local ERASE_MOUNT="${1}"
    if grep ${ERASE_MOUNT} /proc/mounts &> /dev/null; then
        log "${ERASE_MOUNT} is mounted, umounting..."
        local MOUNT_POINT=$(grep ${ERASE_MOUNT} /proc/mounts | awk '{print $2}')
        if ! umount ${MOUNT_POINT} 2>&1; then
            log "${ERASE_MOUNT} is mounted and can't be unmounted"
        fi
    fi
}

# mount partition
mount_fs() {
    local MOUNT_DEVICE="${1}"
    local MOUNT_POINT="${2}"
    if mountpoint -q "${MOUNT_POINT}"; then
        log "${MOUNT_DEVICE} is already mounted"
        return 0
    else
        log "Mounting ${MOUNT_DEVICE} at ${MOUNT_POINT}"
        mkdir ${MOUNT_POINT}
        if mount ${MOUNT_DEVICE} ${MOUNT_POINT}; then
            log "Successfully mounted ${MOUNT_DEVICE} at ${MOUNT_POINT}"
            return 0
        else
            log "Failed to mount ${MOUNT_DEVICE} at ${MOUNT_POINT}"
            return 1
        fi
    fi
}

# mount tmpfs for backup operation
mount_tmpfs() {
    if mountpoint -q "${BACKUP_SCRATCH_DIR}"; then
        log "${BACKUP_SCRATCH_DIR} is already mounted"
        return 0
    else
        # create backup directory with appropriate permissions
        log "Mounting tmpfs at ${BACKUP_SCRATCH_DIR}"
        mkdir -p -m777 ${BACKUP_SCRATCH_DIR}
        if mount -t tmpfs tmpfs ${BACKUP_SCRATCH_DIR}; then
            log "Successfully mounted tmpfs at ${BACKUP_SCRATCH_DIR}"
            return 0
        else
            log "Failed to mount tmpfs at ${BACKUP_SCRATCH_DIR}"
            add_counter_metric "FR_TMPFS_MOUNT_ERROR"
            return 1
        fi
    fi
}

# free tmpfs once backup and restore is complete
free_tmpfs() {
    if mountpoint -q "${BACKUP_SCRATCH_DIR}"; then
        unmount_if_mounted ${BACKUP_SCRATCH_DIR}
    else
        log "${BACKUP_SCRATCH_DIR} is not mounted, nothing to free"
    fi
}

parse_allowlist() {
    if [ "${FR_TYPE}" = "SHALLOW" ] || [ "${FR_TYPE}" = "DEEP" ]; then
        if mount_tmpfs; then
            log "Parsing allowlist file........"
            # assign FR_TYPE in lower case
            ALLOWLIST_CLI_TYPE=$(echo "$FR_TYPE" | tr '[:upper:]' '[:lower:]')
            if ${FR_ALLOWLIST_CLI} -t ${ALLOWLIST_CLI_TYPE} -s "${ROOT_MOUNT}" -d "${BACKUP_SCRATCH_DIR}" &> /dev/null; then
                ALLOWLIST_PATH="${BACKUP_SCRATCH_DIR}/allowlist.conf"
                log "Allowlist Configuration file set to: ${ALLOWLIST_PATH}"
            fi
        else
            log "Failed to mount tmpfs, Unable to parse allowlist file"
        fi
    fi
}

# Backup dropbox logs to recovery
backup_logs() {
    if mount_fs ${DATA_DEVICE} ${DATA_MOUNT}; then
        # Decrypt Userdata
        log "Decrypting userdata partition for dropbox log backup"
        encrypt_decrypt_userdata

        # Safety net in case decryption fails
        if [ -f "$DISK_ENCRYPTION_ERROR" ]; then
            log "Decryption failed, unable to backup dropbox logs"
            return 1
        fi

        LOG_FILE=$(ls ${DROPBOX_SYSTEM_PATH} | tail -1)
        log "copying log file ${LOG_FILE} to recovery."
        ${CP_COMMAND} ${DROPBOX_SYSTEM_PATH}/${LOG_FILE} ${CACHE_FR_DIR}/log${LOG_FILE}
        LOG_FILE=$(ls ${DROPBOX_KERNEL_PATH} | tail -1)
        log "copying log file ${LOG_FILE} to recovery."
        ${CP_COMMAND} ${DROPBOX_KERNEL_PATH}/${LOG_FILE} ${CACHE_FR_DIR}/log${LOG_FILE}

        encrypt_decrypt_userdata
        if [ -f "$DISK_ENCRYPTION_ERROR" ]; then
            log "Encryption failed after backup of dropbox logs"
        fi
        unmount_if_mounted "${DATA_DEVICE}"
    fi
}

# Backup allowlisted files to tmpfs
backup_allowlist() {
    if [ ! -z "${ALLOWLIST_PATH}" ] && [ -f "${ALLOWLIST_PATH}" ]; then

        log "All pre-requisites for ${FR_TYPE} factory reset met"

        # Mount Userdata partition
        if mount_fs ${DATA_DEVICE} ${DATA_MOUNT}; then 

            # Decrypt/Encrypt Userdata if encryption configuration exists
            if [ -f "${ENCRYPTION_POLICY_CONF}" ]; then

                # Check if encrypted files are allowlisted
                check_allowlist_contents

                if [ "${ALLOWLIST_ENCRYPTED_CONTENT}" = "y" ]; then
                    log "Decrypting userdata partition, encrypted files found in the allowlist" 

                    # Decrypt Userdata
                    encrypt_decrypt_userdata

                    # Safety net in case encryption fails
                    if [ -f "$DISK_ENCRYPTION_ERROR" ]; then
                        log "Decryption failed, file backup failed, continuing with partition wipe"
                        ALLOWLIST_ENCRYPTED_CONTENT="n"
                        return 1
                    fi
                else
                    log "Skipping userdata decryption, No encrypted files found in the allowlist"     
                fi
            fi

            # Move files to tmpfs
            log "Initiating Backup Operation........"
            avail_tmpfs=$(df | awk '/tmpfs/ {print $4}')
            add_int_metric "FR_AVAIL_BACKUP_SIZE" $avail_tmpfs
            log "Available space on tmpfs for backup: ${avail_tmpfs}"
            # Provided file list should start with /data/upperdir
            FILE_LIST=$(cat ${ALLOWLIST_PATH} | tr "\n" " ")
            total_size=0
            for arg in $FILE_LIST; do
                SOURCE_PATH=${USERDATA_PREFIX}${arg}
                log "Copying: ${SOURCE_PATH}"
                if ${CP_COMMAND} -a --parents --preserve=all ${SOURCE_PATH} ${BACKUP_SCRATCH_DIR} 2>&1; then
                    log "Successfully copied ${SOURCE_PATH}"
                    # Restore only if atleast one file was copied
                    RESTORE_FLAG="TRUE"
                else
                    log "Failed to copy ${SOURCE_PATH}"
                    # Delete the file/directory in case it was copied half way through
                    BACKUP_PATH=${BACKUP_SCRATCH_DIR}${SOURCE_PATH}
                    if [ -e "${BACKUP_PATH}" ] ; then
                        rm -rf ${BACKUP_PATH}
                    fi
                    add_counter_metric "FR_BACKUP_COPY_ERROR"
                fi
            done

            if [ "${RESTORE_FLAG}" = "TRUE" ]; then
                total_size=$(du -d 0 ${BACKUP_SCRATCH_DIR}${USERDATA_PREFIX} | awk '{print $1}')
            fi
            add_int_metric "FR_TOTAL_ALLOWLIST_SIZE" $total_size
            log "Total Allowlisted size: ${total_size}"

        else
            log "Unable to mount userdata partition, skipping allowlisting operation"
        fi
    else
        log "Pre-requisites for allowlisting not met, Performing SUPERDEEP factory reset"
    fi
    
}

# Restore allowlisted files to userdata
restore_allowlist() {
    if [ "${RESTORE_FLAG}" = "TRUE" ]; then
        
        # Mount Userdata partition
        if mount_fs ${DATA_DEVICE} ${DATA_MOUNT}; then

            if [ "${ALLOWLIST_ENCRYPTED_CONTENT}" = "y" ]; then
                # Encrypt Userdata 
                encrypt_decrypt_userdata

                # Safety net in case encryption fails
                if [ -f "$DISK_ENCRYPTION_ERROR" ]; then
                    log "Encryption failed, file restore failed, exiting factory reset and booting back to normal"
                    wipe_and_reformat "${DATA_DEVICE}" "ext4"
                    BOOT_STATUS="9"
                    if ${SET_BOOT_STATUS_COMMAND} ${BOOT_STATUS} &> /dev/null; then
                        log "Error status was set to ${BOOT_STATUS}"
                    fi
                    # Set boot mode to normal for the next reboot
                    set_boot_mode_normal_and_clear_args
                    exit
                fi
            fi

            # Encryption succeeded, proceeding with file restore
            log "Initiating Restore Operation........"
            mkdir -p ${USERDATA_PREFIX}

            # Copy all the contents under backup scracth
            ALL_SUBDIR="/."
            SOURCE_PATH=${BACKUP_SCRATCH_DIR}${USERDATA_PREFIX}${ALL_SUBDIR}
            if ${CP_COMMAND} -a --preserve=all ${SOURCE_PATH} ${USERDATA_PREFIX} 2>&1; then
                log "Successfully restored files"
            else
                log "Failed to restore files"
                wipe_and_reformat "${DATA_DEVICE}" "ext4"
                add_counter_metric "FR_ALLOWLIST_RESTORE_ERROR"
            fi
        else
            log "Unable to mount userdata partition, skipping allowlisting operation"
        fi
    else
        log "RESTORE_FLAG not set, nothing to restore from tmpfs"
    fi
    free_tmpfs
}

# wipe and reformat blk partiton using blkdiscard
wipe_and_reformat_blk() {
    unmount_if_mounted "$1"
    local ERASE_MOUNT="${1}"
    local FORMAT_FS="${2}"
    local FORMAT_TOOL="mkfs.${2}"
    local FORMAT_COMMAND="${FORMAT_TOOL} ${3}"
    if which ${DISCARD_TOOL} &> /dev/null; then
        log "Wiping Partition ${ERASE_MOUNT}......"
        if ${DISCARD_COMMAND} ${ERASE_MOUNT} &> /dev/null; then
            log "Data wipe successful for ${ERASE_MOUNT}"
            if [ "${FORMAT_FS}" != "raw" ] && which ${FORMAT_TOOL} &> /dev/null; then
                if [ -f /etc/reserved-block.conf ]; then
                    . /etc/reserved-block.conf
                fi
                local SIZE_ARG=""
                if [ -n "${RESIZE_MAX_SIZE}" ] && [ "${RESIZE_MAX_SIZE}" != "0" ]; then
                    SIZE_ARG="${RESIZE_MAX_SIZE}"
                fi
                if ${FORMAT_COMMAND} -O ^resize_inode,meta_bg,^metadata_csum ${ERASE_MOUNT} ${SIZE_ARG} &> /dev/null; then
                    log "Reformat successful for ${ERASE_MOUNT} ${SIZE_ARG}"
                else
                    log "Failed to reformat ${ERASE_MOUNT} due to ${FORMAT_TOOL} error"
                    BOOT_STATUS="8" # BOOTMETA_STATUS_FR_REFORMAT_FAIL
                    add_counter_metric "FR_PARTITION_REFORMAT_ERROR"
                    exec_on_failure
                fi
            else
                if [ "${FORMAT_FS}" != "raw" ]; then
                    log "Failed to reformat ${ERASE_MOUNT} due to missing tools (${FORMAT_TOOL})"
                    BOOT_STATUS="8" # BOOTMETA_STATUS_FR_REFORMAT_FAIL
                    add_counter_metric "FR_PARTITION_REFORMAT_ERROR"
                    exec_on_failure
                fi
            fi
        else
            log "Failed to securely wipe ${ERASE_MOUNT} due to ${DISCARD_TOOL} error"
            BOOT_STATUS="7" # BOOTMETA_STATUS_FR_ERASE_FAIL
            add_counter_metric "FR_PARTITION_DISCARD_ERROR"
            exec_on_failure
        fi
    else
        log "Failed to securely wipe ${ERASE_MOUNT} due to missing tools (${DISCARD_TOOL})"
        BOOT_STATUS="7" # BOOTMETA_STATUS_FR_ERASE_FAIL
        add_counter_metric "FR_PARTITION_DISCARD_ERROR"
        exec_on_failure
    fi
}

# wipe and reformat ubifs partiton
wipe_and_reformat_ubifs() {
    unmount_if_mounted "$1"
    local ERASE_MOUNT="${1}"
    local FORMAT_FS="${2}"
    local FORMAT_TOOL="mkfs.${2}"
    local FORMAT_COMMAND="${FORMAT_TOOL} ${3}"
    if which ${UBI_DISCARD_TOOL} &> /dev/null; then
        log "Wiping Partition ${ERASE_MOUNT}......"
        if ${UBI_DISCARD_COMMAND} ${ERASE_MOUNT} &> /dev/null; then
            log "Data wipe successful for ${ERASE_MOUNT}"
            local OUTPUT=$(${FORMAT_COMMAND} ${ERASE_MOUNT} 2>&1)
            local STATUS=$?
            log "${FORMAT_COMMAND} ${ERASE_MOUNT}"
            log "$OUTPUT"
            if [ $STATUS -eq 0 ]; then
                log "Reformat successful for ${ERASE_MOUNT}"
            else
                log "Failed to reformat ${ERASE_MOUNT} due to ${FORMAT_TOOL} error"
                BOOT_STATUS="8" # BOOTMETA_STATUS_FR_REFORMAT_FAIL
                add_counter_metric "FR_PARTITION_REFORMAT_ERROR"
                exec_on_failure
            fi
        else
            log "Failed to securely wipe ${ERASE_MOUNT} due to ${UBI_DISCARD_TOOL} error"
            BOOT_STATUS="7" # BOOTMETA_STATUS_FR_ERASE_FAIL
            add_counter_metric "FR_PARTITION_DISCARD_ERROR"
            exec_on_failure
        fi
    else
        log "Failed to securely wipe ${ERASE_MOUNT} due to missing tools (${UBI_DISCARD_TOOL})"
        BOOT_STATUS="7" # BOOTMETA_STATUS_FR_ERASE_FAIL
        add_counter_metric "FR_PARTITION_DISCARD_ERROR"
        exec_on_failure
    fi
}

# wipe and reformat partition
wipe_and_reformat() {
    local device_path="$1"
    if [ -b "$device_path" ]; then
        wipe_and_reformat_blk "${1}" "${2}" "${3}"
    else
        wipe_and_reformat_ubifs "${1}" "${2}" "${3}"
    fi
}

# run through the partition list and wipe
reset_partitions() {
    t_start=$(eval ${UPTIME_IN_MS_CMD})

    if [ "${FRTAB_FLAG}" = "TRUE" ]; then
        log "Wiping partitions listed in frtab"
        i=1
        partArr=$( cat ${FRTAB_PATH}  | awk -F '\t' '{print $1;}')
        for partition in $partArr
        do
            filesystem=$( cat ${FRTAB_PATH}  | awk -v row=$i 'NR==row {print $2}' )
            option=$( cat ${FRTAB_PATH}  | awk -v row=$i 'NR==row {$1=$2=""; print $0}' )
            i=$((i + 1))
            # ensure the values are non-zero
            if [ -z "${partition}" ] | [ -z "${filesystem}" ]; then
                continue
            fi
            # ensure the device exists and is ready
            if wait_for_device "${partition}"; then
                log "Wiping ${partition} and reformatting with ${filesystem}"
                wipe_and_reformat "${partition}" "${filesystem}" "${option}"
            fi
        done
    elif [ -b "${DATA_DEVICE}" ]; then
        # Wipe userdata partition by default, reformat with ext4
        log "Wiping ${DATA_DEVICE} and reformatting with ext4"
        wipe_and_reformat "${DATA_DEVICE}" "ext4"
    else
        # Wipe userdata partition by default, reformat with ubifs
        log "Wiping ${DATA_DEVICE} and reformatting with ubifs"
        wipe_and_reformat "${DATA_DEVICE}" "ubifs"
    fi

    t_end=$(eval ${UPTIME_IN_MS_CMD})
    tt=$((${t_end} - ${t_start}))
    log "Partition erase time taken: ${tt} milliseconds"
    add_int_metric "FR_PARTITION_ERASE_TIME" ${tt}
}

# Encrypt/Decrypt userdata partition
encrypt_decrypt_userdata() {
    # Some platforms my not support encryption so see if the file exists first
    if [ -f "$DISK_ENCRYPTION_SCRIPT" ]; then
        log "Run disk encryption script"
        source ${DISK_ENCRYPTION_SCRIPT} ${ENCRYPTION_BOOT_MODE}
    fi
}

# Check if allowlist contains encrypted file paths
check_allowlist_contents() {
    # compare allowlisted paths against all paths in the encryption config
    ENCRYPTED_PATHS=$(grep -h -v ^# $ENCRYPTION_POLICY_CONF | tr "\n" " ")
    ALLOWLIST_PATHS=$(cat ${ALLOWLIST_PATH} | tr "\n" " ")
    for line in $ENCRYPTED_PATHS; do
        for arg in $ALLOWLIST_PATHS; do
            if [[ $arg =~ ^$line* ]]; then
                ALLOWLIST_ENCRYPTED_CONTENT="y"
		break
            fi
        done
	if [ "${ALLOWLIST_ENCRYPTED_CONTENT}" = "y" ]; then
            break
        fi
    done
}

# Read device identification info (DSN and system version)
# for display on the rescue party recovery UI.
read_device_info() {
    # Device Serial Number
    DSN=$(cat "${DSN_PATH}" 2>/dev/null | tr -d '\0')

    # System version string (e.g. "OS1.1 (201010528630)")
    local OS_VER=""
    local VER_NUM=""
    if [ -f "${OS_RELEASE_PATH}" ]; then
        OS_VER=$(grep "^OS_VERSION=" "${OS_RELEASE_PATH}" | cut -d'=' -f2 | tr -d '"')
        VER_NUM=$(grep "^VERSION_NUMBER=" "${OS_RELEASE_PATH}" | cut -d'=' -f2 | tr -d '"')
        SYSTEM_VERSION="OS${OS_VER} (${VER_NUM})"
    else
        SYSTEM_VERSION="unknown"
    fi
}

# Parse RESCUE_PARTY_ARGUMENTS (comma-separated key:value pairs)
# into command-line flags for the recovery UI binary.
# Sets global RESCUE_PARTY_UI_ARGS and updates LOCALE if provided.
parse_rescue_party_arguments() {
    RESCUE_PARTY_UI_ARGS=""
    local args=$(echo "${RESCUE_PARTY_ARGUMENTS}" | tr ',' '\n')
    for arg in $args; do
        case $arg in
        voiceview-enabled:1)
            RESCUE_PARTY_UI_ARGS="${RESCUE_PARTY_UI_ARGS} --voiceview-enabled"
            ;;
        debug:1)
            RESCUE_PARTY_UI_ARGS="${RESCUE_PARTY_UI_ARGS} --debug"
            ;;
        locale:*)
            local value=$(echo "$arg" | cut -d':' -f2)
            RESCUE_PARTY_UI_ARGS="${RESCUE_PARTY_UI_ARGS} --locale ${value}"
            # Update global LOCALE so factory animation uses the same locale
            LOCALE=${value}
            ;;
        *)
            log "Ignore unknown rescue party argument: $arg"
            ;;
        esac
    done
}

# Handle rescue party triggered factory reset flow.
# Clears boot args, launches the recovery UI, and
# exits the script if user chose restart or UI errored.
# Only returns (falls through) if user confirmed factory reset.
handle_rescue_party() {
    # Clear boot mode first so that if the user cannot navigate the UI
    # (e.g. remote not working), unplugging and replugging the device
    # will boot normally instead of looping back into recovery.
    set_boot_mode_normal_and_clear_args

    # Read DSN and system version for display on the recovery UI
    read_device_info

    # Parse rescue party arguments (e.g. voiceview, locale, debug)
    parse_rescue_party_arguments

    if [ ! -x "${RESCUE_PARTY_UI}" ]; then
        log "rescue-party-recovery-ui not found or not executable, skipping"
        exit
    fi

    log "---------- Launching Rescue Party Recovery UI -----------"
    # Blocks until user makes a selection.
    # Note: RESCUE_PARTY_UI_ARGS is intentionally unquoted to allow word splitting
    # into multiple arguments (e.g. "--locale en-US --voiceview-enabled").
    ${RESCUE_PARTY_UI} --dsn "${DSN}" --build "${SYSTEM_VERSION}" ${RESCUE_PARTY_UI_ARGS}
    local EXIT_CODE=$?

    # Map exit code to human-readable selection
    local SELECTION=""
    case ${EXIT_CODE} in
        ${RESCUE_PARTY_EXIT_REBOOT}) SELECTION="${RESCUE_PARTY_SELECTION_REBOOT}" ;;
        ${RESCUE_PARTY_EXIT_FACTORY_RESET}) SELECTION="${RESCUE_PARTY_SELECTION_FACTORY_RESET}" ;;
        *) SELECTION="${RESCUE_PARTY_SELECTION_ERROR}" ;;
    esac
    echo "${SELECTION}" > "${RESCUE_PARTY_USER_SELECTION_FILE}"
    log "User selected ${SELECTION}"

    if [ ${EXIT_CODE} -ne ${RESCUE_PARTY_EXIT_FACTORY_RESET} ]; then
        # User chose restart or UI failed — exit without factory reset
        exit
    fi
    # User confirmed factory reset — fall through to fr_main's reset flow
}

fr_main() {

    # Set System and Vendor library paths early so all binaries from
    # the mounted rootfs (e.g. fbe-key) can resolve their shared libs.
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${ROOT_MOUNT}/sbin:${ROOT_MOUNT}/bin:${ROOT_MOUNT}/usr/bin:${ROOT_MOUNT}/usr/lib:${VENDOR_MOUNT}/usr/lib

    # Needed for logs and metrics
    if wait_for_device "${CACHE_DEVICE}"; then
        mount_fs ${CACHE_DEVICE} ${CACHE_MOUNT}
        mkdir -p ${CACHE_FR_DIR}
    fi
    
    if [ -e ${BEFORE_RECOVERY_REBOOT_LOG_FILE} ]; then
        mv ${BEFORE_RECOVERY_REBOOT_LOG_FILE} ${FR_LOG_FILE}
    fi
    
    # Needed for FR flags and metadata
    if wait_for_device "${MISC_DEVICE}"; then
        read_bootmeta_args
    else
        # cannot continue with fr if /misc is not available
        BOOT_STATUS="4" # BOOTMETA_STATUS_DEVICE_READ_FAIL
        exec_on_failure
    fi

    safe_exit_fr_if_disabled

    # Handle rescue party reset
    if [ "${RESCUE_PARTY}" = "1" ]; then
        log "Rescue party reset detected, arguments: ${RESCUE_PARTY_ARGUMENTS}"
        handle_rescue_party
    fi

    # Track factory animation display duration
    t_start=$(eval ${UPTIME_IN_MS_CMD})

    # Run the Factory Reset Animation in background
    if [ -x ${FR_ANIMATION} ]; then
        ${FR_ANIMATION} "${LOCALE}" "/etc/animation/factory_reset_recovery.conf" &
    fi

    log "---------- Begin Factory Reset Recovery -----------"

    if [ "${BOOT_MODE}" = "1" ]; then

        # Run pre factory reset hook
        run_platform_fr_hook "PRE_FR_OPS"

        # Check if frtab exists. This is to ensure we have a way to
        # still reset the device if rootfs is corrupted
        if [ -f "${FRTAB_PATH}" ]; then              
            FRTAB_FLAG="TRUE"
        fi

        # Backup logs to recovery
        backup_logs

        # Generate allowlist.conf file
        parse_allowlist

        # Perform file backup operation
        backup_allowlist
        
        # Wipe all the necessary partitions
        reset_partitions

        # Restore allowlisted files
        restore_allowlist

        # If we reach this stage, all steps succeeded, Set FR Success status
        BOOT_STATUS="0" # BOOTMETA_STATUS_SUCCESS
        if ${SET_BOOT_STATUS_COMMAND} ${BOOT_STATUS} &> /dev/null; then
            log "FR Status was set to ${BOOT_STATUS}"
        fi

        #Run post factory reset hook
        run_platform_fr_hook "POST_FR_OPS"

        add_counter_metric "FR_COMPLETE"
    fi

    # Set boot mode to normal for the next reboot
    set_boot_mode_normal_and_clear_args

    t_end=$(eval ${UPTIME_IN_MS_CMD})
    tt=$((${t_end} - ${t_start}))
    add_int_metric "FR_TOTAL_RECOVERY_TIME" ${tt}
    
    # we want to display the animation screen for at least 3 seconds
    if [ "${tt}" -lt "${MINIMUM_PROCESS_TIME_IN_MS}" ]; then
        time_to_sleep=$(eval "awk -v tt=$tt 'BEGIN{print (${MINIMUM_PROCESS_TIME_IN_MS} - tt) / 1000}'")
        sleep $time_to_sleep
    fi
}

fr_main
