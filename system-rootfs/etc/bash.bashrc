# System wide bashrc file.

PATH="/usr/local/bin:/usr/bin:/bin"
[ "$TERM" ] || TERM="xterm-256color"

# Add /sbin & co to $PATH for the root user
if [ $(id -u) = "0" ]; then
    HOME=/home/root
    PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin
fi

# Source all profile (even for non-interactive)
if [ -d /etc/profile.d ]; then
    for i in /etc/profile.d/*.sh; do
        if [ -f $i -a -r $i ]; then
            . $i
            fi
    done
    unset i
fi

# Common routines can go here
