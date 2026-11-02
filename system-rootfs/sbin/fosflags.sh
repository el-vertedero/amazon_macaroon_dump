#!/bin/sh

export FOS_FLAGS_ADB_ON=0x1
fosflagsfile="/proc/idme/fos_flags"

if [ -f $fosflagsfile ]; then
    FOSFLAGS=$(cat $fosflagsfile)
    # cut 0x prefix if present
    prefix="0x"
    if [[ $FOSFLAGS == $prefix* ]]; then
        FOSFLAGS=${FOSFLAGS#"$prefix"}
    fi
    # Ensure input is only hexadecimal
    in_size=${#FOSFLAGS}
    FOSFLAGS=${FOSFLAGS//[!^a-fA-F0-9]/}
    # If size differs, there might be something wrong
    if [ ${#FOSFLAGS} -ne $in_size ]; then
         FOSFLAGS=0
    fi
    # If empty, set safe value
    if [[ ! $FOSFLAGS ]];then
         FOSFLAGS=0
    fi
    FOSFLAGS=0x$FOSFLAGS
    if [ $(( $FOS_FLAGS_ADB_ON & $FOSFLAGS )) == 0 ]; then
        echo "ADB disabled using FOS flags" > /dev/kmsg
        exit 2
    fi
fi
