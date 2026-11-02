#!/bin/sh
# Set the system clock to the BUILD_TIMESTAMP specifed in /etc/os-release
# if it's newer than the current time. This is before network comes up so
# we will try to set a better start timestamp.

# Default to 03/01/2022 12:00:00PM.
SENTINEL=1646164800

# Get the build timestamp from /etc/os-release
timestamp=$(cat /etc/os-release | grep BUILD_TIMESTAMP | sed 's/BUILD_TIMESTAMP=//' | sed 's/"//g')

if [ ! "$timestamp" ]; then
    timestamp=$SENTINEL
fi

# sentinel time (current time)
cur=$(date +%s)

# Updates the system clock if it's bigger than the current time
if  [ $timestamp -gt $cur ]; then
    echo "Update systemtime to $timestamp"
    date -s "@$timestamp"
fi
