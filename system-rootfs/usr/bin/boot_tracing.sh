CHOWN=/bin/chown
CHSMACK=/usr/bin/chsmack
MKDIR=/bin/mkdir

# Check developer mode
check_dev_mode() {
    BUILD_VARIANT=$(cat /etc/os-release | sed -n -e 's/.*BUILD_VARIANT=\"\(.*\)\"/\1/p');
    IS_DEV_MODE=$(vdcm get com.amazon.devconf/system/security/developer_mode \
    | sed -e 's/'\''//g' -e 's/ //g' | awk -F'=' '{print $2}') ;
    if [ "$IS_DEV_MODE" == "enable" ] || [ "$IS_DEV_MODE" == "authenticating" ] || [ "$IS_DEV_MODE" == "on" ];
        then
            echo 1 > /proc/sys/kernel/perf_event_paranoid
            touch /tmp/is_dev_mode
            $CHOWN trace:trace /tmp/is_dev_mode
            return 0
    fi;
    return 1
}

# Check for service launch
check_launch() {
    source /etc/tracing/tracing.conf
    # Defaults from local file
    CLI_TRIGGER_ARGS=$(echo $CLI_TRIGGER_ARGS | sed -e 's/ //g')
    CLI_STAT_ARGS=$(echo $CLI_STAT_ARGS | sed -e 's/ //g')
    TRACING_TYPE=$LOCAL_TRACING_TYPE;
    POLLING_PERIOD=$LOCAL_TRACING_POLLING_PERIOD;
    BOOT_DUR=$LOCAL_TRACING_BOOT_DUR;

    if [ -f "/tmp/is_dev_mode" ]
    then
        return 0
    fi

    #KVS doesn't work on non-rooted devices, so no reason to check these on user-external builds
    case $CONFIG_MODE in
        "LOCAL") ;;
        "KVS")
            TRACING_TYPE=$(ace hal kvs cli -g -k tracing_type | sed -n -e 's/.*Value=\(.*\)/\1/p') ;
            #if tracing is not enabled - don't fetch tracing parameters from KVS to save boot time
            if [ "$TRACING_TYPE" == "BOOT_TRACE" ] ||
               [ "$TRACING_TYPE" == "AUTO_TRACE" ] ||
               [ "$TRACING_TYPE" == "USER_TRACE" ];
            then
                KVS_POLLING_PERIOD=$(ace hal kvs cli -g -k tracing_polling_period | sed -n -e 's/.*Value=\(.*\)/\1/p') ;
                KVS_BOOT_DUR=$(ace hal kvs cli -g -k tracing_boot_dur | sed -n -e 's/.*Value=\(.*\)/\1/p') ;

                if [ "$KVS_POLLING_PERIOD" != "" ];
                then
                    POLLING_PERIOD=$KVS_POLLING_PERIOD
                fi
                if [ "$KVS_BOOT_DUR" != "" ];
                then
                    BOOT_DUR=$KVS_BOOT_DUR
                fi
            fi
            ;;
        *) TRACING_TYPE="" ;;
    esac

    # Log configuration
    echo  "CONFIG_MODE = $CONFIG_MODE
    TRACING_TYPE = $TRACING_TYPE
    POLLING_PERIOD = $POLLING_PERIOD
    BOOT_DUR = $BOOT_DUR" | systemd-cat -p info -t boot_tracing

    if [ "$TRACING_TYPE" == "BOOT_TRACE" ] ||
        [ "$TRACING_TYPE" == "AUTO_TRACE" ] ||
        [ "$TRACING_TYPE" == "USER_TRACE" ];
        then return 0;
    fi;

    return 1
}

# Pre-launch setup to allow debugfs/tracefs
# access for non-root user
# Requires: root privileges
launch_setup() {
    $CHOWN -R trace:trace /sys/kernel/tracing
    $CHSMACK -r -s -a 'System' /sys/kernel/tracing

    # With older kernels (pre 4.1) debugfs had a tracing folder which is
    # a mount point now that is auto-mounted when accessed. Below stat
    # command forces the mount and then sets the ownership/label.
    stat -f /sys/kernel/debug/tracing
    if [[ $? == "0" ]]
    then
        $CHOWN trace:trace /sys/kernel/debug/tracing
        $CHSMACK -s -a 'System' /sys/kernel/debug/tracing
    fi;

    # Setup run path for perfetto sockets
    $MKDIR -p -m 0773 /run/perfetto
    $CHOWN root:trace /run/perfetto
    $CHSMACK -a "*" /run/perfetto

    check_dev_mode
    exit 0
}

# Launch service
launch_service() {
    check_launch
    if [[ $? == "0" ]]
    then
        # We come here only if tracing needs to be enabled. Launch traced in
        # all the cases.
        traced --background --set-socket-permissions trace:0666:trace:0666
        traced_probes --background --reset-ftrace

        if [ "$TRACING_TYPE" == "BOOT_TRACE" ];
        then
            vtrace-cli begin -d $BOOT_DUR \
            --proc-metrics-tp $POLLING_PERIOD --sys-metrics-tp $POLLING_PERIOD \
            -m 65536 -p 0 \
            -s $CLI_STAT_ARGS \
            -o /tmp/boot_trace_file;
        elif [ "$TRACING_TYPE" == "AUTO_TRACE" ];
        then
            vtrace-cli begin -d 0 -r \
            --proc-metrics-tp $POLLING_PERIOD --sys-metrics-tp $POLLING_PERIOD \
            -m 32768 -p 0 -z \
            -s $CLI_STAT_ARGS \
            -t $CLI_TRIGGER_ARGS \
            -o /var/lib/data/ace/dropbox/inbox/vtrace/vtrace@trace;
        fi;
    fi;
}

#launch function from args
"$@"
