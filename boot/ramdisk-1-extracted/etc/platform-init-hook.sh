#!/bin/sh

# overlay /data directory to make it writable
if [ "$1" = "INIT_POST_MOUNT_READY" ]; then
    if ! touch /rootfs/data 2>/dev/null; then
        echo "overlay /data directory"
        USERDATA="/rootfs/rootfs.rw"
        SYSTEM="/rootfs/rootfs.ro"
        mkdir -p $USERDATA/upperdir/data $USERDATA/work/data
        mount -t overlay overlay -o lowerdir=$SYSTEM/data,upperdir=$USERDATA/upperdir/data,workdir=$USERDATA/work/data /rootfs/data
    fi

    #configure softlock time to 4 sec(2 * watchdog_thresh/hard lockup time),
    #and enabled panic by softlockup. Its worth mentioning that hard lockup
    #time, is set via file 'watchdog_thresh', and kernel automatically sets
    #the soft lockup time twice of hard lockup time.
    if [[ -f /proc/sys/kernel/softlockup_panic && \
        -f /proc/sys/kernel/watchdog_thresh ]]; then
        echo 1 > /proc/sys/kernel/softlockup_panic
        echo 2 > /proc/sys/kernel/watchdog_thresh
    fi

    #Print the tuning value of the emc
    #Temporaily mount debugfs as it may not yet mounted on /sys/kernel/debug.
    if [ -d "/rootfs/data" ]; then
        mkdir /rootfs/data/tmp-debugfs
        mount -t debugfs none /rootfs/data/tmp-debugfs
        for file in $(find /rootfs/data/tmp-debugfs -name tuning_params)
        do
            d=$(basename $(dirname $file))
            tuning_param=$(cat $file)
            echo $d: $tuning_param > /dev/kmsg
        done
        #unmount the debugfs
        umount /rootfs/data/tmp-debugfs
        rm -rf /rootfs/data/tmp-debugfs
    else
        echo "/rootfs/data(writable mount) not found, can't dump emmc tuning parameters" > /dev/kmsg
    fi

    #Appending reboot reason to boot logs
    reboot_reason=$(cat sys/kernel/reboot_reason)
    echo "reboot_reason: $reboot_reason"
fi
