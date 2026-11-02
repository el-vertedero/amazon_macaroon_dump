#!/bin/bash
#
# Copyright (c) 2023  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

AHE_SERVICE_NAME="AlexaHybridEngine.service"
AHERUNFILE=/run/ahe_restart
CRASH_RECORD="/var/lib/data/alexahybrid/files/working-directory/crashRecord.txt"

# See wiki for design choices for this restart policy
# https://wiki.labcollab.net/confluence/display/SHELBY/AHE+Process+lifecycle+on+1P+devices
# Retry intervals in minutes: 0,0,5m,1h,6h,12h,1d,3d,5d,10d
RETRY_SCHEDULE=(0 0 5 60 360 720 1440 4320 7200 14400)
RETRY_SCHEDULE_LENGTH=${#RETRY_SCHEDULE[@]}
# reset backoff attempt counter if AHE ran for more than 5 hour.
BACKOFF_RESET_DELAY_IN_SEC=18000

# seconds in a minute
RETRY_SCHEDULE_MULTIPLIER=60

update_retry_delay() {
    retry_delay=${RETRY_SCHEDULE[${1}]}
    retry_delay=$((retry_delay * RETRY_SCHEDULE_MULTIPLIER))
    # Add upto 10% jitter
    jitter=$(( RANDOM % 10 ))
    jitter=$(( jitter * retry_delay / 100 ))
    retry_delay=$(( retry_delay + jitter ))

    # Check if there is an intentional crash
    if [ -f $CRASH_RECORD ]; then
        retry_delay=0
    fi
}

update_attempt() {
    attempt=0
    last_start=$(date +%s)
    if [ -f $AHERUNFILE ]; then
        read attempt last_start <<< $(awk '{print $1, $2}' "$AHERUNFILE")
    fi

    start_time=$(date +%s)

    # Reset backoff attempt counter if AHE ran for more than BACKOFF_RESET_DELAY_IN_SEC
    if (( (${start_time} - ${last_start}) >= ${BACKOFF_RESET_DELAY_IN_SEC} )); then
        attempt=0
    fi

    if [ ! -f $CRASH_RECORD ]; then
        attempt=$((attempt + 1))
    fi

    if (( ${attempt} >= ${RETRY_SCHEDULE_LENGTH} )); then
        attempt=$((RETRY_SCHEDULE_LENGTH - 1))
    fi
}

update_must_restart() {
    AHE_MAIN_CODE=$(systemctl show -p ExecMainCode --value "$AHE_SERVICE_NAME")
    AHE_MAIN_STATUS=$(systemctl show -p ExecMainStatus --value "$AHE_SERVICE_NAME")
    # MainCode = 2 and MainStatus = 9 means Killed by SIGKILL
    if [ "$AHE_MAIN_CODE" = "2" ] && [ "$AHE_MAIN_STATUS" = "9" ]; then
        printf "AHE was terminated by a SIGKILL. Won't restart.\n"
        must_restart=false
    else
        must_restart=true
    fi
}

write_attempt_info() {
    echo "${1} ${2}" > "$AHERUNFILE"
}


printf "AHE Recovery script\n"
update_must_restart
if [ "$must_restart" = true ]; then
    printf "Attempting restart\n"
    update_attempt
    update_retry_delay ${attempt}
    printf "Sleeping for %d\n" "$retry_delay"
    sleep ${retry_delay}
    rm "$CRASH_RECORD"
    systemctl reset-failed "$AHE_SERVICE_NAME"
    systemctl start "$AHE_SERVICE_NAME"
    write_attempt_info ${attempt} ${start_time}
    printf "AHE restarted\n"
fi