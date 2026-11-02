#!/bin/bash
# This script puts back the smack workaround rules
# which are removed in multimodal images.
#
# On compatible targets this script is run during the 
# deploy phase.
#
# Otherwise it should be run manually after 
# flashing the build image.
#
# Since this script alters SMACK policy on device,
# devs should do a full multimodal image to test their
# changes once feature development using incremental
# builds is done.
#
# Usage:
# $ cd /usr/bin/
# $ ./add_smack_exception_for_development.sh

set -e

OLD_SYS_RULE='"~PROCESS~ System -w-----",'
NEW_SYS_RULE='"~PROCESS~ System rwx----",'

OLD_SYSPRIV_RULE='"~PROCESS~ System::Privileged -w-----",'
NEW_SYSPRIV_RULE='"~PROCESS~ System::Privileged rwx----",'

PLATFORM_CONFIG=/etc/securitymgrd/platform-config.conf

# check if we are running an older version, if yes add workaround
# rules and increment version
#TODO (@nmckibb) - Rewrite using parser APPFWK-4508
if grep -q "$OLD_SYS_RULE" "$PLATFORM_CONFIG" ;
then   
    echo "Adding back smack workaround, to allow incremental builds and deploy."
   
    sed -i "s/$OLD_SYS_RULE/$NEW_SYS_RULE/" "$PLATFORM_CONFIG"
    sed -i "s/$OLD_SYSPRIV_RULE/$NEW_SYSPRIV_RULE/" "$PLATFORM_CONFIG"

    systemctl restart security-manager
fi
