# Setting PS1 prompt based on PRODUCT_NAME if found
[ -e /etc/platform-info ] && \
  eval $(cat /etc/platform-info | grep PRODUCT_NAME)

# If in app sandbox
if [ -L /pkg ];then
    echo "##################################################"
    echo "#####     Welcome to Developer mode Shell    #####"
    echo "##################################################"
    PKGNAME=$(readlink -f /pkg | awk -F/ '{print $3}')
    export PS1='sh($PKGNAME):\w\$ '
else
    FLAG_FILE="/tmp/.bash_shell_warning_printed"

    # print a warning only once per boot/vdad service start,
    #  only for when device is locked and when developer invokes
    #  bash shell
    if [ ! -f "$FLAG_FILE" ]; then
        if grep -q "orpheusboot.kernel_unlocked=false" /proc/cmdline && \
           grep -q "orpheusboot.prod_device=1" /proc/cmdline; then
            echo "-----------------!!! BASH SHELL DEPRECATION WARNING !!!------------------"
            echo "   You are currently using Bash shell which will be deprecated soon   "
            echo "     Please enable Developer Mode to start using the correct shell    "
            echo " https://developer.amazon.com/docs/kepler-tv/what-is-developer-mode.html"
            echo "-----------------!!! BASH SHELL DEPRECATION WARNING !!!------------------"

            touch "$FLAG_FILE"
        fi
    fi

    if [ "$PRODUCT_NAME" ]; then
        export PS1='$PRODUCT_NAME:\w\$ '
    else
        export PS1='\h:\w\$ '
    fi
fi
