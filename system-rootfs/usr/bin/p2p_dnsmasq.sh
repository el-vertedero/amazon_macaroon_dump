#!/bin/sh
ARGS="--bind-interfaces --no-poll --dhcp-authoritative --dhcp-option-force=43"
ARGS=" ${ARGS} --interface=$1 --except-interface=lo"
ARGS=" ${ARGS} --pid-file=/var/run/p2p_dnsmasq.pid"
ARGS=" ${ARGS} --dhcp-script=/usr/bin/p2p_dhcp_script.sh"
ARGS=" ${ARGS} --no-ping"
#ARGS=" ${ARGS} --resolv-file=/var/run/resolv.dnsmasq"
P2PIPADDRESS=$2
DHCPRANGE=$3
REG_ENDPOINT_FILE_NAME=/etc/registration_endpoint_host_names.csv

#log -p i -t p2p_dnsmasq.sh "starting dnsmasq"

read_hosts () {
    local IFS=,
    read KEY HOST_NAME
}

while read_hosts;
do
    if [ -n "$HOST_NAME" ]
    then
        DNSMASQ_ENDPOINT_ARGS="-A /$HOST_NAME/$P2PIPADDRESS"' '"${DNSMASQ_ENDPOINT_ARGS}"
    fi
done < $REG_ENDPOINT_FILE_NAME

DNSMASQ_ENDPOINT_ARGS=$(echo ${DNSMASQ_ENDPOINT_ARGS} | sort -u )

#echo "$DNSMASQ_ENDPOINT_ARGS"
if [ -n "$P2PIPADDRESS" ]
then
    ARGS=" ${ARGS} -a ${P2PIPADDRESS}"
    ARGS=" ${ARGS} ${DNSMASQ_ENDPOINT_ARGS}"
fi

if [ -n "$DHCPRANGE" ]
then
    ARGS=" -F ${DHCPRANGE}${ARGS}"
fi
#echo "$ARGS"
#log -p i -t p2p_dnsmasq.sh "CALLING DNSMASQ WITH: $* $ARGS"
# Empty lease file before starting dnsmasq because these are stale
if [ -e /var/lib/misc/dnsmasq.leases ]; then
# /var/lib/misc/dnsmasq.leases is default lease file when -l or --dhcp-leasefile is not specified.
  echo "" > /var/lib/misc/dnsmasq.leases
fi

/usr/bin/dnsmasq $ARGS
