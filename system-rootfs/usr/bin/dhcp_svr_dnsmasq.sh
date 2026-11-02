#!/bin/sh
ARGS="--bind-interfaces --no-poll --dhcp-authoritative --dhcp-option-force=43"
ARGS=" ${ARGS} --interface=$1 --except-interface=lo"
ARGS=" ${ARGS} --pid-file=/var/run/dnsmasq/dhcps_dnsmasq_$1.pid"
ARGS=" ${ARGS} --resolv-file=/etc/resolv.conf"
ARGS=" ${ARGS} --dhcp-leasefile=/var/lib/dnsmasq/dnsmasq_$1.lease"
IP=$2
DHCPRANGE=$3
EXTRA1=$4
EXTRA2=$5

#log -p i -t dhcp_svc_dnsmasq.sh "starting dnsmasq"


if [ -n "$IP" ]
then
    ARGS=" ${ARGS} -a ${IP}"
fi

if [ -n "$DHCPRANGE" ]
then
    ARGS=" -F ${DHCPRANGE} ${ARGS}"
fi

if [ -n "$EXTRA1" ]
then
    ARGS=" ${ARGS} ${EXTRA1}"
fi

if [ -n "$EXTRA2" ]
then
    ARGS=" ${ARGS} ${EXTRA2}"
fi

echo "$ARGS"
#log -p i -t dhcp_svc_dnsmasq.sh "CALLING DNSMASQ WITH: $* $ARGS"
/usr/bin/dnsmasq $ARGS
