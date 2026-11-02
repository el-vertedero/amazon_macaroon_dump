#!/bin/sh

export PATH=/bin:/usr/bin:$PATH
# ramoops log: convert this log file to kcr
KERNEL_RAMOOPS_LOG="/var/lib/systemd/pstore/console-ramoops-0"
# directory to save kcr file
KCR_DIR="/var/log"
# kcr file prefix
KCR_PREFIX="kern_critical"
# kcr file suffix
KCR_SUFFIX=".log"
# .kcr_info file to pass CrashDescriptor to other process,
#  like Comet.
KCR_PANIC_INFO_FILE=".kcr_panic.info"

# The default log is in syslog, and you can monitor log by
# adb shell tail -f /var/log/syslog
# Uncomment below to show log on console/journal, so monitor log by
# adb shell journalctl -f
# DEBUG=yes

# node list for info related to kernel crash.
NODE_LCR="/proc/life_cycle_reason"
NODE_PLATFORM_INFO="/etc/platform-info"
NODE_OS_RELEASE="/etc/os-release"
NODE_LAST_DEBUG_INFO="/proc/last_debug_info"
NODE_CMDLINE="/proc/cmdline"

# Cached os-release from previous boot (persists across OTA and factory reset)
KCR_CACHE_DIR="/cache/kcr"
SAVED_OS_RELEASE="$KCR_CACHE_DIR/os-release"

# extra handling for KCR:
KCR_EXTRA_HANDLER="${KCR_EXTRA_HANDLER:-/usr/bin/amzn-kcr-extra.sh}"

# Platform-specific initialization handler
PLATFORM_INIT_HANDLER="${PLATFORM_INIT_HANDLER:-/usr/bin/amzn-kcr-platform-init.sh}"

# Configurable pattern lists for abnormal LCR detection
LCR_WARMBOOT_BY_KERNEL_PANIC="*Kernel Panic*"

# Abnormal LCR keyword list - one per line
# Platform can append via LCR_PATTERN_LIST_PLATFORM_APPEND in PLATFORM_INIT_HANDLER
LCR_PATTERN_LIST="Watchdog
Thermal Shutdown
Life Cycle Reason Not Available
Fireboot Resume Failed
Fireboot Snapshot Create Failed
Cold Boot By Brown Out
Warm Boot By Mrdump Smart Reset
Warm Boot By Vendor Hang Detect
Warm Boot By LK Crash
Warm Boot By Dm Verity Corruption
Warm Boot By SPM Request
Warm Boot By SPM Thermal
Warm Boot By SoC Thermal HW
Cold Reboot By PMIC Full Reset
Warm Boot By Security Reboot
Warm Boot By Voltage Glitch Detection Unit
Warm Boot By Power Good Detection Unit
Warm Boot By PMIC Trigger WDT Reboot
Warm Boot By EINT Trigger WDT Reboot
Warm Boot By DRAM Controller Reboot
Warm Boot By MCUPM WDT Timeout
Warm Boot By EFUSE Checksum Error Detction"

# Check if message contains any keyword from the pattern list
match_LCR_pattern() {
    echo "$1" | grep -qF "$(printf '%s\n' "$LCR_PATTERN_LIST")"
}

#logging function
KCR_LOG() {
    # please note that this could be link to toolbox, not executable
    if [ x"$DEBUG" = x"yes" ]; then
        echo $@
    elif [ -e "/usr/bin/logger" ]; then
        #log to syslog
        logger -p "local0.err" -t "amzn-kcr" "$@"
    else
        #log to console
        echo $@
    fi
}

process_kernel_ramoops_log() {
    LCR_MESSAGE=$(cat $NODE_LCR)
    KCR_LOG "Processing $1 with LCR: $LCR_MESSAGE"
    panic_found=false
    KERNEL_LOG_FILE=$1
    KERNEL_LOG_CHKSUM_FILE=$KCR_DIR/.$(basename $KERNEL_LOG_FILE).last_chksum
    log_checksum=$(md5sum $KERNEL_LOG_FILE | cut -d' ' -f1)
    if grep -q "$log_checksum" "$KERNEL_LOG_CHKSUM_FILE"; then
        KCR_LOG "kernel log is old and already uploaded. Skip"
        return 0
    fi

    line_header_regex='^[[:space:]]*\[ *[0-9]+.[0-9]+.*\][[:space:]]*'

    panic_msg_with_lineno=$(grep -niE  "${line_header_regex}kernel panic|kernel BUG at|Internal error: Oops|Unable to handle kernel" $KERNEL_LOG_FILE | tail -n 1)

    if [ -n "$panic_msg_with_lineno" ]; then
        ## kernel panic happens
        KCR_LOG "Found last kernel panic: $panic_msg_with_lineno"
        panic_found=true
    else
        case "$LCR_MESSAGE" in
          $LCR_WARMBOOT_BY_KERNEL_PANIC)
            ## kernel panic detected by LCR, but not filtered by ramoops log. Try a loose filter
            panic_msg_with_lineno=$(grep -ni "panic" $KERNEL_LOG_FILE | head -n 1)
            KCR_LOG "LCR reports $LCR_MESSAGE, log panic: $panic_msg_with_lineno"
            panic_found=true
            ;;
          *)
            if match_LCR_pattern "$LCR_MESSAGE"; then
                KCR_LOG "LCR reports $LCR_MESSAGE"
            else
                KCR_LOG "LCR reports normal boot. Skip"
                echo $log_checksum > $KERNEL_LOG_CHKSUM_FILE
                return 0
            fi
            ;;
        esac
    fi

    if [ -n "$panic_msg_with_lineno" ]; then
        panic_msg=$(echo "$panic_msg_with_lineno" | cut -d: -f2- | xargs)
        panic_msg_lineno=$(echo "$panic_msg_with_lineno" | cut -d: -f1)
        # get the line header column for panic log only
        bracket_pos=$(echo "$panic_msg" | sed 's/panic.*//I' | sed -E "s/($line_header_regex).*$/\1/" | wc -c)
        panic_msg_stripped=$(echo "$panic_msg" |  cut -c $bracket_pos- | xargs)

        # Extract UPTIME in ms from log
        UPTIME_MS=$(echo "$panic_msg" | awk -F '[].[]' '{printf "%.0f\n", $2*1000+$3/1000}')
        CRASH_REASON=$panic_msg_stripped
        # Extract kernel panic log and remove the timestamp each line.
        panic_log=$(sed -n $panic_msg_lineno,'$p' $KERNEL_LOG_FILE)
        panic_log_stripped=$(echo "$panic_log" | cut -c $bracket_pos-)
        # Extract backtrace:
        backtrace_log=$(echo "$panic_log_stripped"| sed -n '/^Backtrace:/,/^CPU/{/^CPU/q;p}')
        # Extract PC is at :
        PC_is_at_log=$(echo "$panic_log" | grep -o "PC is at.*")
        if [ -n "$PC_is_at_log" ]; then
            # Extract LR is at :
            LR_is_at_log=$(echo "$panic_log" | grep -o "LR is at.*")

            # Use PC, LR and crash reason for hash code, because even the same "PC is at" backtraces may have
            # different register dump of sp, r0-r10, etc, then cause many different CrashDescriptors and hard to track.
            KCR_FINGERPRINT=$(echo "$CRASH_REASON $PC_is_at_log $LR_is_at_log" | md5sum | cut -d' ' -f1)
        else
            # use backtrace, and crash reason for hash code.
            KCR_FINGERPRINT=$(echo "$CRASH_REASON $backtrace_log" | md5sum | cut -d' ' -f1)
        fi
    else
        # no panic log and backtrace. Use LCR message to compute the hash.
        CRASH_REASON="$LCR_MESSAGE"
        KCR_FINGERPRINT=$(echo "$CRASH_REASON" | md5sum | cut -d' ' -f1)
    fi


    ## KCR_FILE will be deleted after dropbox processes it.
    TS=$(date +%s)
    # KCR file for working:
    KCR_FILE="$KCR_DIR/.${KCR_PREFIX}.tmp"
    # KCR final file for uploading. The final file must be
    # writen once to avoid racing condition between writing
    # and uploading registration.
    KCR_FILE_FINAL=$KCR_DIR/${KCR_PREFIX}_${TS}${KCR_SUFFIX}

    # start to convert ramoops console log to kcr

    # sample meta:
    #CrashDescriptor:e9baf199db7e589713359d4cdeda493f
    #CrashType:KernelCrash
    #CrashReason:
    #CrashTimeUTC:1649282164000
    #UpTimems:1234453000
    #LifeCycleReason:Warm Boot By Kernel Panic

    echo "CrashDescriptor:$KCR_FINGERPRINT" > $KCR_FILE
    echo "CrashType:KernelCrash" >> $KCR_FILE
    echo "CrashReason:$CRASH_REASON" >> $KCR_FILE
    echo "CrashTimeUTC:$(( $TS*1000 ))" >> $KCR_FILE
    echo "UpTimems:$UPTIME_MS" >> $KCR_FILE
    echo "LifeCycleReason:$LCR_MESSAGE" >> $KCR_FILE
    echo "# os-release info:" >> $KCR_FILE
    if [ -r "$SAVED_OS_RELEASE" ]; then
        cat $SAVED_OS_RELEASE | sed -e 's/"//g' >> $KCR_FILE
    else
        cat $NODE_OS_RELEASE | sed -e 's/"//g' >> $KCR_FILE
    fi
    echo "# platform-info:" >> $KCR_FILE
    cat $NODE_PLATFORM_INFO | sed -e 's/"//g' >> $KCR_FILE
    echo "# /proc/cmdline:" >> $KCR_FILE
    cat $NODE_CMDLINE  >> $KCR_FILE
    echo "# panic log:" >> $KCR_FILE
    echo "$panic_log" >> $KCR_FILE
    if [ -r "$NODE_LAST_DEBUG_INFO" ]; then
        echo "last_debug_info:" >> $KCR_FILE
        cat $NODE_LAST_DEBUG_INFO >> $KCR_FILE
    fi

    echo $'\n\n# Full log:\n' >> $KCR_FILE
    cat $KERNEL_LOG_FILE >> $KCR_FILE

    if [ -r "$KCR_EXTRA_HANDLER" ]; then
        source "$KCR_EXTRA_HANDLER"
    fi
    # write CrashDescriptor only if kernel panic happens
    if [ "$panic_found" = true ]; then
        echo "CrashDescriptor=$KCR_FINGERPRINT" > $KCR_DIR/$KCR_PANIC_INFO_FILE
    fi

    # move the tmp file to final KCR file, and register for uploading.
    mv $KCR_FILE $KCR_FILE_FINAL
    # record log checksum that already uploaded.
    echo $log_checksum > $KERNEL_LOG_CHKSUM_FILE
}

## main

# Call platform-specific initialization if it exists
if [ -r "$PLATFORM_INIT_HANDLER" ]; then
    KCR_LOG "Loading platform init handler: $PLATFORM_INIT_HANDLER"
    source "$PLATFORM_INIT_HANDLER"
fi

# Merge platform-specific LCR patterns if defined
if [ -n "$LCR_PATTERN_LIST_PLATFORM_APPEND" ]; then
    LCR_PATTERN_LIST="$LCR_PATTERN_LIST
$LCR_PATTERN_LIST_PLATFORM_APPEND"
fi

if [ -r "$KERNEL_RAMOOPS_LOG" ]; then
    process_kernel_ramoops_log $KERNEL_RAMOOPS_LOG
    exit $?
else
    KCR_LOG "Can not access: $KERNEL_RAMOOPS_LOG"
    exit 1
fi
