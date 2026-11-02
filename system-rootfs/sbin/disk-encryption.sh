#!/bin/sh
# File based disk encryption

# Limit binary PATH for generic commands
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DATA_DEVICE="/dev/block/platform/userdata"
HOME_PATH="/home"
DATA_MOUNT="/rootfs.rw"
UPPERDIR="$DATA_MOUNT/upperdir"
SALT_FILE="$DATA_MOUNT/.salt"
SALT_FILE_BACKUP="$DATA_MOUNT/.salt_bak"
SALT_FILE_TMP="$DATA_MOUNT/.salt_tmp"
TEMP_PATH="$DATA_MOUNT/.disk_encryption_tmp"
ROOT_MOUNT=""
ENCRYPTION_BOOT_MODE="$1"
BOOTMETA_TOOL="/usr/bin/bootmeta_utility"
BOOT_MODE_FACTORY_RESET="1" # "factory reset" mode

set -o pipefail

set_args() {
    # Update path for recovery
    if [ "${ENCRYPTION_BOOT_MODE}" = "recovery" ]; then
        ROOT_MOUNT="/rootfs.ro"
    fi
    ENCRYPTION_POLICY="$ROOT_MOUNT/etc/disk-encryption.conf"
    FSCRYPTCTL="$ROOT_MOUNT/usr/bin/fscryptctl"
    FBE_KEY="$ROOT_MOUNT/usr/sbin/fbe-key"
    TUNE2FS="$ROOT_MOUNT/sbin/tune2fs.e2fsprogs"
    CP_COMMAND="$ROOT_MOUNT/bin/toybox cp"
}

log_kmsg() {
    echo "$@" > /dev/kmsg
}

set_policy () {
    local rc=0
    # encrypt the directory with user key
    $FSCRYPTCTL set_policy "$1" "$2"
    rc=$?
    # fallback in case first time fails.
    if [ $rc -ne 0 ] ; then
        log_kmsg "$2 is not empty for encryption"
        log_kmsg $(ls -R $2)
        # create temp path
        mkdir -p $TEMP_PATH
        mv $2/* $TEMP_PATH/
        $FSCRYPTCTL set_policy "$1" "$2"
        rc=$?
        mv $TEMP_PATH/* $2/
        rm -rf $TEMP_PATH
    fi
    if [ $rc -ne 0 ] ; then
        log_kmsg "ERROR: encryption failed in $2"
        # set diag error flag
        touch /tmp/disk-encryption-error
    fi
}

set_encryption_keys() {
    # The salt file should be wiped during factory-reset
    $TUNE2FS -O encrypt $DATA_DEVICE

    # set key for var directory
    system_key=$($FBE_KEY -s $SALT_FILE_TMP -i system -n 64 | $FSCRYPTCTL add_key $DATA_MOUNT)

    grep -h -v ^# $ENCRYPTION_POLICY | while read -r line;
    do
        # Create all directories that need to be encrypted
        # fscrypt set_policy requires directory to be empty
        mkdir -p "$UPPERDIR$line"
        if [[ $line =~ ^$HOME_PATH* ]]; then
            # Encrypt user directories. This is for fixed users.
            # If user needs to login, encrypt/decrypt after
            # user login.
            # extract user from /home path
            user=${line#"$HOME_PATH"}
            # set key for the user
            user_key=$($FBE_KEY -s $SALT_FILE_TMP -i "$user" -n 64 | $FSCRYPTCTL add_key $DATA_MOUNT)
            # encrypt the directory with user key
            set_policy "$user_key" "$UPPERDIR$line"
        else
            # Encrypt non-user directories with system key
            set_policy "$system_key" "$UPPERDIR$line"
        fi
    done
}

retry_once() {
   local rc=0
   $@
   rc=$?
   if [ $rc -ne 0 ]; then
       log_kmsg "Retry $@"
       $@
       rc=$?
   fi
   if [ $rc -ne 0 ] ; then
       log_kmsg "Error: copy failed"
       # set diag error flag
       touch /tmp/disk-encryption-error
   fi
   return $rc
}

do_encryption() {
    # device is not encrypted. Setup encryption.
    log_kmsg "encrypting user data"

    # generate 64B random number as salt for encrpytion.
    head -c 64 /dev/urandom > $SALT_FILE_TMP
    sync

    set_encryption_keys

    # copy system /var /home contents to userdata on first boot
    retry_once ${CP_COMMAND} -rf --preserve=all /rootfs.ro/var/* ${UPPERDIR}/var/
    retry_once ${CP_COMMAND} -rf --preserve=all /rootfs.ro/home/* ${UPPERDIR}/home/
    sync

    # save salt after encryption complete.
    mv "$SALT_FILE_TMP" "$SALT_FILE"
    cp "$SALT_FILE" "$SALT_FILE_BACKUP"
    sync

    log_kmsg "encrypting user data success"
}

set_decryption_keys() {
    local salt="$1"
    if [ ! -f "$salt" ]; then
        log_kmsg "Warning: Missing $1"
        return 1;
    fi

    # set key for var directory
    $FBE_KEY -s $salt -i system -n 64 | $FSCRYPTCTL add_key $DATA_MOUNT

    grep -h -v ^# $ENCRYPTION_POLICY | while read -r line;
    do
        if [[ $line =~ ^$HOME_PATH* ]]; then
            # extract user from /home path
            user=${line/#$HOME_PATH}
            # set key for the user
            $FBE_KEY -s $salt -i "$user" -n 64 | $FSCRYPTCTL add_key $DATA_MOUNT
        fi
    done

    # test if /var/lib is correctly decrypted
    if [ ! -d "${UPPERDIR}/var/lib/systemd" ]; then
        log_kmsg "ERROR: User data decryption failed"
        return 1
    fi

    return 0
}

do_decryption() {
    log_kmsg "decrypting user data"

    if set_decryption_keys "$SALT_FILE"; then
        if [ ! -f "$SALT_FILE_BACKUP" ]; then
            log_kmsg "Backup encryption salt"
            cp "$SALT_FILE" "$SALT_FILE_BACKUP"
        fi
    elif set_decryption_keys "$SALT_FILE_BACKUP"; then
        log_kmsg "Restore encryption salt"
        cp "$SALT_FILE_BACKUP" "$SALT_FILE"
    else
        trigger_factory_reset
        return 1
    fi

    log_kmsg "decrypting user data success"
    return 0
}

is_encrypted() {
    [ -f "$SALT_FILE" ] || [ -f "$SALT_FILE_BACKUP" ]
}

is_encryption_incomplete() {
    [ -f "$SALT_FILE_TMP" ]
}

trigger_factory_reset() {
    touch /tmp/disk-encryption-error
    log_kmsg "Trigger factory reset"
    ${BOOTMETA_TOOL} -m ${BOOT_MODE_FACTORY_RESET}
    reboot
}

log_kmsg "start disk encryption"

set_args

if is_encryption_incomplete; then
    log_kmsg "ERROR: user data encryption incomplete"
    trigger_factory_reset
elif is_encrypted; then
    do_decryption
else
    do_encryption
fi

# map /var and /home to userdata partition. Do not run in recovery
if [ "${ENCRYPTION_BOOT_MODE}" != "recovery" ]; then
    mount -o rw,bind ${UPPERDIR}/var /var
    mount -o rw,bind ${UPPERDIR}/home /home
fi

log_kmsg "end disk encryption"
