#!/bin/sh
# Validates the installed rootfs image using 
# the same verity method used at runtime for any rootfs accessed data.  
# This script must run before assuming anything on the 
# target rootfs is safe to access.


ROOT_HASH=$1
DATA_BLOCK_SIZE=$2
DATA_SIZE=$3
PARTITION=$4
HASH_ALGO=$5

VERITY_CMD="veritysetup --debug --data-block-size=$DATA_BLOCK_SIZE"
if [ -n "$HASH_ALGO" ]; then
    VERITY_CMD="$VERITY_CMD --hash=$HASH_ALGO"
fi
VERITY_CMD="$VERITY_CMD --hash-offset=$DATA_SIZE verify $PARTITION $PARTITION $ROOT_HASH"

echo "Executing command: $VERITY_CMD"

if $VERITY_CMD; then
    echo "Verity validation succeeded for ${PARTITION}!!!"
    exit 0;
else
    RESULT=$?
    echo "Verity validation failed for ${PARTITION} with exit code $RESULT, installation failed!!!"
    echo "Failed command was: $VERITY_CMD"
    exit 1;
fi
