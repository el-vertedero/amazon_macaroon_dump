#!/bin/sh
run_platform_update_verifier_hook() {
    platform_update_verifier_hook="/etc/platform-update-verifier-hook.sh"
    if [ -f "$platform_update_verifier_hook" ]; then
        echo "Running platform update verifier hook: $platform_update_verifier_hook $1 $2"
        $platform_update_verifier_hook $1 $2
        if [ $? -ne 0 ]; then
            echo "Platform update verifier hook failed: $platform_update_verifier_hook $1 $2"
            exit 1
        fi
    fi
}

validate_misc_partition() {
    local misc_device=""
    local device_type=""
    # Try to find misc partition (block first, then UBI)
    if [ -L "/dev/disk/by-partlabel/misc" ]; then
        misc_device=$(readlink -f /dev/disk/by-partlabel/misc)
        device_type="block"
        echo "Found misc via partlabel symlink: $misc_device"
    elif [ -b "/dev/block/platform/misc" ]; then
        misc_device=$(readlink -f /dev/block/platform/misc)
        device_type="block"
        echo "Found misc via platform block device: $misc_device"
    else
        # Search block devices (eMMC and UFS)
        for dev in /dev/mmcblk*p* /dev/sd*[0-9]* /dev/ufs*p* ; do
            if [ -b "$dev" ]; then
                label=$(blkid -s PARTLABEL -o value "$dev" 2>/dev/null)
                if [ "$label" = "misc" ]; then
                    misc_device="$dev"
                    device_type="block"
                    break
                fi
            fi
        done
        # If no block device found, search UBI devices
        if [ -z "$misc_device" ]; then
            for ubi_dev in /dev/ubi*_*; do
                if [ -c "$ubi_dev" ]; then
                    ubi_name=$(cat "/sys/class/ubi/${ubi_dev#/dev/}/name" 2>/dev/null)
                    if [ "$ubi_name" = "misc" ]; then
                        misc_device="$ubi_dev"
                        device_type="ubi"
                        break
                    fi
                fi
            done
        fi
    fi
    # Validate device exists
    if [ -z "$misc_device" ]; then
        echo "ERROR: Misc partition not found"
        return 1
    fi
    # Check permissions and group
    local perms=$(stat -c "%a" "$misc_device" 2>/dev/null)
    local group=$(stat -c "%G" "$misc_device" 2>/dev/null)
    if [ "$perms" != "660" ] || [ "$group" != "disk" ]; then
        echo "ERROR: Misc partition permissions incorrect: $perms $group (expected 660 disk)"
        return 1
    fi
    # Check SMACK permissions
    smack_label=$(ls -Z "$misc_device" 2>/dev/null | awk '{print $1}')
    if [ "$smack_label" != "*" ] && [ "$smack_label" != "System" ]; then
        echo "ERROR: Misc partition SMACK label incorrect: $smack_label (expected * or System)"
        return 1
    fi
    if [ ! -r "$misc_device" ] || [ ! -w "$misc_device" ]; then
        echo "ERROR: Misc partition not accessible"
        return 1
    fi
    echo "Misc partition validated: $misc_device ($device_type)"
    return 0
}

# Validate misc partition
if ! validate_misc_partition; then
    echo "FATAL: Misc partition validation failed"
    exit 1
fi

echo "Starting update verifier"

# Ensure misc partition permission is set correctly to read bcb
# and get active_slot as "a" or "b" based on boot_control_utility results
# $ boot_control_utility
# Slot Name   Bootable    Successful  Active 
# _a          Yes         Yes         Yes  
# _b          Yes         No          No
if output=$(boot_control_utility); then
    active_slot=$(echo "$output" | awk '$4 == "Yes" {print substr($1, 2)}')
    if [ -n "$active_slot" ]; then
        echo "Successfully detected active slot: ${active_slot}"
    else
        echo "Failed to detect active slot due to bcb read failure"
        exit 1
    fi
else
    echo "Failed to get bcb info due to bcb read failure"
    exit 1
fi

run_platform_update_verifier_hook "BEFORE_MARK_SLOT_SUCCESS" ${active_slot}

# Mark the active slot as success (Successful as "Yes")
echo "Start post-boot ota verification."
if boot_control_utility -s | awk -v slot="_${active_slot}" '$1 == slot && $3 == "Yes"'; then
    echo "Slot ${active_slot} is marked as successful"
    echo "End post-boot ota verification."
else
    echo "Slot ${active_slot} is not marked as successful."
    exit 1
fi

# Virtual A/B: merge snapshots and remove patch partitions
# This runs AFTER marking slot successful to prevent rollback into a
# partially-merged base partition if merge times out or fails.
# Snapuserd continues serving correct data from patches until merge completes.
if command -v vega_snapshotctl >/dev/null 2>&1 && \
   { [ -e "/dev/block/platform/system_patch_${active_slot}" ] || [ -e "/dev/block/platform/vendor_patch_${active_slot}" ]; }; then
    VAB_MERGE_TIMEOUT=60

    vab_merge_snapshot() {
        local snapshot_name="$1"
        echo "Attempting to merge snapshot: $snapshot_name"
        merge_output=$(vega_snapshotctl merge "$snapshot_name" 2>&1)
        if echo "$merge_output" | grep -q "success"; then
            echo "Merge initiated for $snapshot_name, waiting for completion (timeout=${VAB_MERGE_TIMEOUT}s)..."
            local elapsed=0
            while [ $elapsed -lt $VAB_MERGE_TIMEOUT ]; do
                status_output=$(vega_snapshotctl status "$snapshot_name" 2>&1)
                if echo "$status_output" | grep -q "snapshot-merge-complete"; then
                    echo "Merge complete for $snapshot_name (${elapsed}s)"
                    return 0
                elif echo "$status_output" | grep -q "snapshot-merge"; then
                    sleep 5
                    elapsed=$((elapsed + 5))
                else
                    echo "Unexpected status for $snapshot_name: $status_output"
                    return 1
                fi
            done
            echo "ERROR: Merge timed out for $snapshot_name after ${VAB_MERGE_TIMEOUT}s"
            return 1
        fi
        echo "Merge failed for $snapshot_name: $merge_output"
        return 1
    }

    system_merge_ok=0
    vendor_merge_ok=0
    if [ -e "/dev/block/platform/system_patch_${active_slot}" ]; then
        vab_merge_snapshot "system_snapshot" && system_merge_ok=1
    else
        echo "No system_patch_${active_slot} found, skipping system merge"
        system_merge_ok=1
    fi
    if [ -e "/dev/block/platform/vendor_patch_${active_slot}" ]; then
        vab_merge_snapshot "vendor_snapshot" && vendor_merge_ok=1
    else
        echo "No vendor_patch_${active_slot} found, skipping vendor merge"
        vendor_merge_ok=1
    fi

    if [ "$system_merge_ok" = "1" ]; then
        vega_snapshotctl cleanup "system_patch_${active_slot}" /dev/block/platform/super default || true
    else
        echo "WARNING: Skipping system_patch cleanup - merge incomplete"
    fi
    if [ "$vendor_merge_ok" = "1" ]; then
        vega_snapshotctl cleanup "vendor_patch_${active_slot}" /dev/block/platform/super default || true
    else
        echo "WARNING: Skipping vendor_patch cleanup - merge incomplete"
    fi
fi

# Commit the userdata changes after a successful upgrade
AMZN_UDC_UTILITY="/usr/bin/amzn-udc-utility.sh"
if [ -f "$AMZN_UDC_UTILITY" ]; then
    $AMZN_UDC_UTILITY "COMMIT"
fi

# Ignore the error and not rollback after mark slot as success
run_platform_update_verifier_hook "AFTER_MARK_SLOT_SUCCESS" ${active_slot} || true
