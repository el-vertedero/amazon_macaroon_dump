#!/bin/sh

check_misc_write_access() {
    SYMLINK="/dev/block/platform/misc"

    # Check if symlink exists
    if [ ! -L "$SYMLINK" ] ; then
        echo "WARN: $SYMLINK is not a symlink"
        return 1
    fi

    # Get real path
    REAL_PATH=$(readlink -f "$SYMLINK")
    if [ -z "$REAL_PATH" ] ; then
        echo "WARN: Could not resolve $SYMLINK"
        return 1
    fi

    # Check if real path exists
    if [ ! -e "$REAL_PATH" ] ; then
        echo "WARN: $REAL_PATH does not exist"
        return 1
    fi

    # Check write permission
    if [ ! -w "$REAL_PATH" ] ; then
        echo "WARN: $REAL_PATH is not writable"
        # Get permissions
        PERMS=$(stat -c '%a %U %G' "$REAL_PATH")
        echo "Current permissions: $PERMS"
        return 1
    fi

    # Log success
    PERMS=$(stat -c '%a %U %G' "$REAL_PATH")
    echo "OK: $SYMLINK -> $REAL_PATH is writable"
    echo "Permissions: $PERMS"
    return 0
}


if [ "$1" = "BEFORE_MARK_SLOT_SUCCESS" ]; then

    # Check for proper misc permission
    if ! check_misc_write_access; then
        exit 1
    fi

    # Run boot_control_utility command and capture its output
    output=$(boot_control_utility -j 2>&1)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "boot_control_utility error. Code: $ret, output: ${output}" >&2
        exit "${ret}"
    fi

    # Initialize a flag to indicate success
    IS_SUCCESSFUL="no"
    OTA_BOOT_VALUE=""
    active_slot="$2"
    echo "value for active slot is $active_slot"

    # Regex patterns for finding the active slot and checking if it's successful
    SUCCESSFUL_REGEX="\"_${active_slot}\":\\s*\\{\"active\":\\s*true,\"bootable\":\\s*true,\"successful\":\\s*true"

    # Parse the output to find if it's successful
    if echo "$output" | grep -qE "$SUCCESSFUL_REGEX"; then
        IS_SUCCESSFUL="yes"
    fi

    # Read the current value from /sys/kernel/ota_boot and store it in a variable
    OTA_BOOT_NODE="/sys/kernel/ota_boot"
    if [ ! -e "$OTA_BOOT_NODE" ]; then 
        echo "Error:$OTA_BOOT_NODE not found!" >&2
        exit 1
    fi

    if [ ! -r "$OTA_BOOT_NODE" ]; then 
        echo "Error:$OTA_BOOT_NODE not readable!" >&2
        exit 1 
    fi
    OTA_BOOT_VALUE=$(cat $OTA_BOOT_NODE)

    # Define the mask for the 31st bit in decimal
    OTA_STARTED_MASK=$((16#80000000))

    # Continue with the script if the slot is not successful or the 31st bit is set
    if [ "$IS_SUCCESSFUL" = "no" ] || [ $((OTA_BOOT_VALUE & OTA_STARTED_MASK)) -eq $OTA_STARTED_MASK ]; then
        echo "Continuing with successful update verifier logic..."
        echo "Clearing PR registers..."
        # Clear PR registers
        if [ ! -w "$OTA_BOOT_NODE" ]; then 
            echo "Error:$OTA_BOOT_NODE not writable!" >&2
            exit 1
        fi
        echo "0x0" > $OTA_BOOT_NODE

        # Check if amzn_mmc_utils exists
        if command -v amzn_mmc_utils >/dev/null 2>&1; then
            echo "amzn_mmc_utils found, proceeding with EXT_CSD configuration..."
            
            echo "Checking current EXT_CSD configuration..."
            current_config=$(amzn_mmc_utils extcsd read /dev/mmcblk0 | grep -E "Boot Partition [12] enabled")
            current_boot_part=$(echo "$current_config" | grep -o -E "Boot Partition [12]" | grep -o "[12]")
            echo "Current boot partition: $current_boot_part"

            echo "Changing EXT_CSD to current active slot..."
            if [ "$active_slot" = "a" ]; then
                slot_num="1"
            else
                slot_num="2"
            fi
            
            # Execute the bootpart enable command
            amzn_mmc_utils bootpart enable "$slot_num" 1 /dev/mmcblk0
            
            # Verify the new configuration
            echo "Verifying new EXT_CSD configuration..."
            new_config=$(amzn_mmc_utils extcsd read /dev/mmcblk0 | grep -E "Boot Partition [12] enabled")
            new_boot_part=$(echo "$new_config" | grep -o -E "Boot Partition [12]" | grep -o "[12]")
            echo "New boot partition: $new_boot_part"
            
            if [ "$new_boot_part" = "$slot_num" ]; then
                echo "EXT_CSD configuration successfully updated to Boot Partition $slot_num"
            else
                echo "ERROR: EXT_CSD configuration was not set correctly" >&2
                echo "Expected: $slot_num" >&2
                echo "Got: Boot Partition $new_boot_part" >&2
                exit 1
            fi
        else
            echo "amzn_mmc_utils not found, skipping EXT_CSD configuration..."
        fi
    else
        echo "The slot is successful and the 31st bit is not set. No further action needed."
    fi
fi

if [ "$1" = "AFTER_MARK_SLOT_SUCCESS" ]; then
    echo "Successful boot updating ARB counters"
    echo "Setting ARBC program register"

    ARBC_NODE="/sys/kernel/arbc_prog"
    if [ ! -e "$ARBC_NODE" ]; then 
        echo "Error:$ARBC_NODE not found!" >&2
        exit 1
    fi
    if [ ! -w "$ARBC_NODE" ]; then 
        echo "Error:$ARBC_NODE not writable!" >&2
        exit 1
    fi
    # Setting PR registers
    # only updates counter if the booted version is higher than previous
    echo 1 > $ARBC_NODE
fi
