#!/bin/bash
#
# Copyright 2020-2023 Amazon.com, Inc. or its affiliates. All rights reserved.
#
# AMAZON PROPRIETARY/CONFIDENTIAL
#
# You may not use this file except in compliance with the terms and conditions
# set forth in the accompanying LICENSE.TXT file. This file is a
# Modifiable File, as defined in the accompanying LICENSE.TXT file.
#
# THESE MATERIALS ARE PROVIDED ON AN "AS IS" BASIS. AMAZON SPECIFICALLY
# DISCLAIMS, WITH RESPECT TO THESE MATERIALS, ALL WARRANTIES, EXPRESS,
# IMPLIED, OR STATUTORY, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.
#

# This script enables firewall settings for the device
# Should be placed in /etc directory on the device.
IPTABLES=/usr/sbin/iptables
P2PIF=p2p-p2p0-0
APIF=wlan0
IP=10.201.126.241
SRCIP=10.201.126.242
SRCPORT=443
DESTIP=10.201.126.243
DESTPORT=1555
COMMONFWFILE=/run/common_fw
AHEFWFILE=/run/ahe_fw
IP6TABLES=/usr/sbin/ip6tables
COMMONIPV6FWFILE=/run/common_ipv6_fw

set_default_rules_for_interface() {
    local interface=$1
    local fw_name=/run/ipv4_fw_$1

    if [ -f $fw_name ]; then
        echo "IPv4 firewall rules have been set"
        return
    fi

    echo "Setting up default firewall rules for interface $interface"

    # Accept RELATED,ESTABLISHED connections on interface (device initiated)
    $IPTABLES -A INPUT -i $interface -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Spotify Connect login server.
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 4070 -j ACCEPT

    # Whatify Spotify Connect login server.
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 4071 -j ACCEPT

    # SIP Calling support
    $IPTABLES -A INPUT -i $interface -p udp --dport 16384:32767 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 16384:32767 -j ACCEPT

    # TPH traffic on interface. TPH/phd listens on port 40317
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 49317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 33434 -j ACCEPT

    # Whole Home Audio traffic on interface.  The whad listens on:
    # udp port 55442 for audio distribution
    # tcp port 55442 for audio distribution
    # tcp port 55443 for control plane behavior,
    # udp port 55444 for timestamp exchange
    # udp port 55445 for Quantum UDP WHASP
    # tcp port 55445 for TCP WHASP
    # udp port 55446 for multi-tier timestamp exchange
    $IPTABLES -A INPUT -i $interface -p udp --dport 55442 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 55442:55443 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 55444:55446 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 55445 -j ACCEPT

    # CMB. Allow packets on port 5000
    $IPTABLES -A INPUT -i $interface -p udp --dport 5000 -j ACCEPT

    # Allow LocalAdapterPlatform to listen to UDP Broadcasts from Tuya
    $IPTABLES -A INPUT -i $interface -p udp --dport 6667 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Matter use
    $IPTABLES -A INPUT -i $interface -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5541 -j ACCEPT

    # DIAL use
    $IPTABLES -A INPUT -i $interface -p tcp --dport 60000 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 8009 -j ACCEPT

    # Netflix Gibbon debug port
    $IPTABLES -A INPUT -i $interface -p tcp --dport 9536 -j ACCEPT
    # Netflix MDX port
    $IPTABLES -A INPUT -i $interface -p tcp --dport 9080 -j ACCEPT

    # UPnP:
    # Allow traffic on Dst Port 1900 which are UPnP advertisements and Bye Bye
    # Allow traffic on Dst Port 50000 and 50001 which is used in SmartHome Wifi Adapter
    # and LocalMediator respectively as source port.
    $IPTABLES -A INPUT -i $interface  -p udp --dport 1900 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp --dport 50000 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp --dport 50001 -j ACCEPT

    # mDNS: Avahi Publish of Spotify Connect service.
    $IPTABLES -A INPUT -i $interface  -p udp --dport 5353 -j ACCEPT

    # Allow all outgoing traffic on interface
    $IPTABLES -A OUTPUT -o $interface -j ACCEPT

    # Allows LocalAdapterPlatform to perform UDP/SSDP Broadcast discovery for LifX, TPLink, Yeelight
    # Allows traffic only from RFC 1918 IP Addresses, ie IP-endoints on local network
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allows Local Integrations Adapter to perform UDP broadcast discovery / control for Wiz, Govee Magic Home
    # Wiz
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Govee
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Magic Home
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # AICF Messenger.
    $IPTABLES -A INPUT -i $interface -p tcp --dport 10001 -j ACCEPT

    echo " " > $fw_name
}

# Add default firewall settings here
default_firewall_setup () {
    local interface=$1

    echo "Setting up default firewall settings for $interface"

    if [ -f $COMMONFWFILE ]; then
        echo "Common firewall rules have been set"
    else
        $IPTABLES --flush

        # Default policy for all chains: DROP
        $IPTABLES -P INPUT DROP
        $IPTABLES -P OUTPUT DROP
        $IPTABLES -P FORWARD DROP

        # ICMP. Allow only responses to local connections
        $IPTABLES -A INPUT -p icmp -m state --state RELATED,ESTABLISHED -j ACCEPT

        # Accept all on the loopback interface
        $IPTABLES -A INPUT -i lo -j ACCEPT
        $IPTABLES -A OUTPUT -o lo -j ACCEPT

        #Overwrite default policy for Thread interface
        $IPTABLES -I INPUT -i ot0 -j ACCEPT
        $IPTABLES -I OUTPUT -o ot0 -j ACCEPT
        $IPTABLES -I FORWARD -i ot0 -j ACCEPT
        $IPTABLES -I FORWARD -o ot0 -j ACCEPT
        $IPTABLES -t mangle -I PREROUTING -i ot0 -j MARK --set-mark 0x1001
        $IPTABLES -t nat -I POSTROUTING -m mark --mark 0x1001 -j MASQUERADE

        # allowing traffic on tcp port 5555 for adb access
        echo "Allow ADB over Wifi traffic on tcp port 5555"
        $IPTABLES -A INPUT -p tcp --dport 5555 -j ACCEPT
        $IPTABLES -A OUTPUT -p tcp --sport 5555 -j ACCEPT

        # Set flag to indicate common rules have been set
        echo " " > $COMMONFWFILE
    fi

    set_default_rules_for_interface $interface
}

set_default_ipv6_rules_for_interface() {
    local interface=$1
    local fw_name=/run/ipv6_fw_$1

    if [ -f $fw_name ]; then
        echo "IPv6 firewall rules have been set"
        return
    fi

    echo "Setting up default IPv6 firewall rules for interface $interface"

    # Accept RELATED,ESTABLISHED connections on interface (device initiated)
    $IP6TABLES -A INPUT -i $interface -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Spotify Connect login server.
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 4070 -j ACCEPT

    # Whatify Spotify Connect login server.
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 4071 -j ACCEPT

    # SIP Calling support
    $IP6TABLES -A INPUT -i $interface -p udp --dport 16384:32767 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 16384:32767 -j ACCEPT

    # TPH traffic on interface. TPH/phd listens on port 40317
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 40317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 40317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 49317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 33434 -j ACCEPT

    # Whole Home Audio traffic on interface.  The whad listens on:
    # udp port 55442 for audio distribution
    # tcp port 55442 for audio distribution
    # tcp port 55443 for control plane behavior,
    # udp port 55444 for timestamp exchange
    # udp port 55445 for Quantum UDP WHASP
    # tcp port 55445 for TCP WHASP
    # udp port 55446 for multi-tier timestamp exchange
    $IP6TABLES -A INPUT -i $interface -p udp --dport 55442 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 55442:55443 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 55444:55446 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 55445 -j ACCEPT

    # CMB. Allow packets on port 5000
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5000 -j ACCEPT

    # DHCPv6 client port
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 546 -j ACCEPT

    # Allow LocalAdapterPlatform to listen to UDP Broadcasts from Tuya
    $IP6TABLES -A INPUT -i $interface -p udp --dport 6667 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Matter use
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5540 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5541 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 5540 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 5541 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p udp --dport 5540 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p udp --dport 5541 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p tcp --dport 5540 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p tcp --dport 5541 -j ACCEPT

    # DIAL use
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 60000 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 8009 -j ACCEPT

    # Netflix Gibbon debug port
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 9536 -j ACCEPT
    # Netflix MDX port
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 9080 -j ACCEPT

    # UPnP:
    # Allow traffic on Dst Port 1900 which are UPnP advertisements and Bye Bye
    # Allow traffic on Dst Port 50000 and 50001 which is used in SmartHome Wifi Adapter
    # and LocalMediator respectively as source port.
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 1900 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 50000 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 50001 -j ACCEPT

    # mDNS: Avahi Publish of Spotify Connect service.
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 5353 -j ACCEPT

    # Allow all outgoing traffic on interface
    $IP6TABLES -A OUTPUT -o $interface -j ACCEPT

    # AICF Messenger.
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 10001 -j ACCEPT

    echo " " > $fw_name
}


default_ipv6_firewall_setup () {
    local interface=$1

    echo "Setting up default IPv6 firewall settings for $interface"

    if [ -f $COMMONIPV6FWFILE ]; then
        echo "Common IPv6 firewall rules have been set"
    else
        $IP6TABLES --flush

        # Default policy for all chains: DROP
        $IP6TABLES -P INPUT DROP
        $IP6TABLES -P OUTPUT DROP
        $IP6TABLES -P FORWARD DROP

        # Allow all ICMPv6 packets
        $IP6TABLES -A INPUT -p icmpv6 -j ACCEPT
        $IP6TABLES -A OUTPUT -p icmpv6 -j ACCEPT

        # Accept all on the loopback interface
        $IP6TABLES -A INPUT -i lo -j ACCEPT
        $IP6TABLES -A OUTPUT -o lo -j ACCEPT

        #Overwrite default policy for Thread interface
        $IP6TABLES -A INPUT -i ot0 -j ACCEPT
        $IP6TABLES -A OUTPUT -o ot0 -j ACCEPT
        $IP6TABLES -A FORWARD -i ot0 -j ACCEPT
        $IP6TABLES -A FORWARD -o ot0 -j ACCEPT

        # Set flag to indicate common rules have been set
        echo " " > $COMMONIPV6FWFILE
    fi

    set_default_ipv6_rules_for_interface $interface
}

# Add Alexa hybrid firewall settings for target interface
alexa_hybrid_firewall_interface() {
    local AHE_SECURE_PORT=$1
    local interface=$2
    echo "Setting up alexa hybrid firewall settings for $interface and port $AHE_SECURE_PORT"

    if [ -z $AHE_SECURE_PORT ]; then
        echo "Invalid parameters. port=$AHE_SECURE_PORT"
        exit 1
    fi

    # Allow extensions device connecting to AHE on given interface
    $IPTABLES -A INPUT -i $interface -p tcp --dport $AHE_SECURE_PORT -j ACCEPT
}

alexa_hybrid_firewall_common() {
    AHE_CLIENT_UID=$1
    AHE_SERVICE_UID=$2
    AHE_PORT=$3

    # TODO current uid on some platforms is not set,not sure if it will work
    if [ -z $AHE_CLIENT_UID ] || [ -z $AHE_SERVICE_UID ] || [ -z $AHE_PORT ]; then
        echo "Invalid parameters. client=$AHE_CLIENT_UID, service=$AHE_SERVICE_UID, port=$AHE_PORT"
        exit 1
    fi

    # Check if AHE common part is set or not
    if [ -f $AHEFWFILE ]; then
        echo "AHE common firewall rules have been set"
        return
    else
        # Create new chain ahe_out if not exist
        $IPTABLES -N ahe_out >> /dev/null 2>&1
        # Filter OUTPUT through ahe_out
        $IPTABLES -I OUTPUT 1 -j ahe_out
        # Remove any existing rules on the ahe_out chain
        $IPTABLES --flush ahe_out
        # Drop traffic from a non alexa hybrid client user to AHE port/prevent impersonating PuffinApp process.
        # Accept packets for an ESTABLISHED connection. This is required to allow FIN packets.
        $IPTABLES -A ahe_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m state --state ESTABLISHED -j ACCEPT
        $IPTABLES -A ahe_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m owner ! --uid-owner $AHE_CLIENT_UID -j DROP
        # Drop traffic from a non alexa hybrid service user from AHE port/prevent impersonating AHE process.
        # Don't accept for ESTABLISHED connection. When client initiates connection the SYN_ACK packet is
        # considered as part of ESTABLISHED connection. We don't want that.
        # We want to include SYC_ACK packets in owner uid filter.
        $IPTABLES -A ahe_out -o lo -p tcp --sport $AHE_PORT -s 127.0.0.1 -m owner ! --uid-owner $AHE_SERVICE_UID -j DROP

        # Set flag for common AHE rules written
        echo " " > $AHEFWFILE
    fi
}

alexa_hybrid_firewall_setup () {
    echo "alexa_hybrid_firewall_setup"
    local AHE_CLIENT_UID='system'
    local AHE_SERVICE_UID='alexahybrid'
    local AHE_PORT=7802
    local AHE_SECURE_PORT=7805
    local interface=$1

    alexa_hybrid_firewall_interface ${AHE_SECURE_PORT} $interface
    alexa_hybrid_firewall_common ${AHE_CLIENT_UID} ${AHE_SERVICE_UID} ${AHE_PORT}
}

# Firewall settings for P2P interface
p2p_firewall_start () {
    if [ "$#" -ne 3 ]; then
        echo "P2P enable:Using default parameters"
    else
        P2PIF=$1
        IP=$2
        STRICT=$3
    fi
    echo "Setting up P2P firewall settings on $P2PIF strict $STRICT"

    if [ $STRICT -eq 0 ]; then
        # Allow all outgoing traffic
        $IPTABLES -A OUTPUT -o "$P2PIF" -j ACCEPT

        # Allow all incoming traffic
        $IPTABLES -A INPUT -i "$P2PIF" -j ACCEPT
        return
    fi
    # From Laser, no such port
    # COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Default policy for all chains: DROP
    $IPTABLES -P INPUT DROP
    $IPTABLES -P OUTPUT DROP
    $IPTABLES -P FORWARD DROP

    # Setup ip tables to reject all non-essential traffic
    # Redirect all DNS traffic to ourselves. This is necessary when the client device
    # has a static DNS address configured
    $IPTABLES -t nat -A PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${IP}
    # ACCEPT all DNS traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # ACCEPT all DHCP traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT

    # no such port on Laser
    #$IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Allow all outgoing traffic
    $IPTABLES -A OUTPUT -o "$P2PIF" -j ACCEPT
}

# Firewall settings for P2P interface
p2p_firewall_stop () {
    if [ "$#" -ne 3 ]; then
        echo "P2P disable:Using default parameters"
    else
        P2PIF=$1
        IP=$2
        STRICT=$3
    fi

    echo "Disabling P2P firewall settings on $P2PIF ($IP) strict $STRICT"

    if [ $STRICT -eq 0 ]; then
        # Delete all outgoing traffic
        $IPTABLES -D OUTPUT -o "$P2PIF" -j ACCEPT

        # Delete all incoming traffic
        $IPTABLES -D INPUT -i "$P2PIF" -j ACCEPT
        return
    fi
    # COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Delete all rules setup by p2p_firewall_start
    # Delete DNS redirection
    $IPTABLES -t nat -D PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${IP}
    # Delete ACCEPT all DNS traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # Delete ACCEPT all DHCP traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # Delete ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT
    # $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Delete Allow all outgoing traffic
    $IPTABLES -D OUTPUT -o "$P2PIF" -j ACCEPT
}

# Firewall settings for hostap interface
hostap_firewall_start () {
    if [ "$#" -ne 1 ]; then
        echo "Hostap enable: Using default parameters"
    else
        APIF=$1
    fi
    echo "Setting up hostap firewall settings on $APIF"

    # Allow all incoming traffic
    $IPTABLES -A INPUT -i "$APIF" -j ACCEPT

    # Allow all outgoing traffic
    $IPTABLES -A OUTPUT -o "$APIF" -j ACCEPT
}

# Firewall settings for hostap interface
hostap_firewall_stop () {
    if [ "$#" -ne 1 ]; then
        echo "Hostap disable: Using default parameters"
    else
        APIF=$1
    fi

    echo "Disabling hostap firewall settings on $APIF"

    # Delete all rules setup by hostap_firewall_start
    # Delete Allow all incoming traffic
    $IPTABLES -D INPUT -i "$APIF" -j ACCEPT

    # Delete Allow all outgoing traffic
    $IPTABLES -D OUTPUT -o "$APIF" -j ACCEPT
}

# Firewall settings for bridging
bridged_firewall_start () {
    echo "Setting up bridged firewall settings"
    # enable forwarding
    echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
    iptables -I FORWARD -j ACCEPT
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    ip6tables -I FORWARD -j ACCEPT
    # disable unicast DHCP forwarding (refer CONN-25980)
    iptables -I FORWARD -p udp --sport 67 -j DROP
    iptables -I FORWARD -p udp --sport 68 -j DROP
}

# Firewall settings for bridging
bridged_firewall_stop () {
    echo "Disabling bridged firewall settings"

    # remove disabling unicast DHCP forwarding
    iptables -D FORWARD -p udp --sport 67 -j DROP
    iptables -D FORWARD -p udp --sport 68 -j DROP
    # disable forwarding
    iptables -D FORWARD -j ACCEPT
    echo 0 > /proc/sys/net/ipv4/conf/all/forwarding
    ip6tables -D FORWARD -j ACCEPT
    echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
}

# NAT for FFS only
nat_firewall_start () {
    if [ "$#" -ne 3 ]; then
        echo "NAT enable:Using default parameters"
    else
        P2PIF=$1
        APIF=$2
        IP=$3
    fi

    echo "Start NAT from $P2PIF ($IP) to $APIF"

    echo 1 > /proc/sys/net/ipv4/ip_forward

    $IPTABLES -C FORWARD -p tcp -s ${IP} -i ${P2PIF} -o ${APIF} -j ACCEPT
    if [ $? -ne 0 ]; then
        # Accept tcp forwarding traffic
        $IPTABLES -A FORWARD -p tcp -s ${IP} -i ${P2PIF} -o ${APIF} -j ACCEPT
        $IPTABLES -A FORWARD -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
        # Masquerade all NAT traffic
        $IPTABLES -t nat -F POSTROUTING
        $IPTABLES -t nat -A POSTROUTING -o $APIF -j MASQUERADE
    fi
}

nat_firewall_stop () {
    if [ "$#" -ne 1 ]; then
        echo "NAT disable: Using default parameters"
    else
        APIF=$1
    fi

    echo "Stop NAT"

    echo 0 > /proc/sys/net/ipv4/ip_forward
    # Stop accepting forward traffic
    $IPTABLES -F FORWARD
    # Delete NAT masquerade rule.
    $IPTABLES -t nat -D POSTROUTING -o $APIF -j MASQUERADE
}

wg_firewall_start() {
    if [ "$#" -gt 3 ] ; then
        GWIF=$1
        SRCFMT=$2
        SRCPORT=$4

        echo "Start wireguard firewall settings on $GWIF"
        $IPTABLES -A INPUT -i $GWIF -j ACCEPT
        $IPTABLES -A OUTPUT -o $GWIF -j ACCEPT
        $IP6TABLES -A INPUT -i $GWIF -j ACCEPT
        $IP6TABLES -A OUTPUT -o $GWIF -j ACCEPT
        if [ "$SRCFMT" = "IPv6" ] ; then
            $IP6TABLES -A INPUT -p udp --dport $SRCPORT -j ACCEPT
        else
            $IPTABLES -A INPUT -p udp --dport $SRCPORT -j ACCEPT
        fi
    fi
}

wg_firewall_stop() {
    if [ "$#" -gt 3 ] ; then
        GWIF=$1
        SRCFMT=$2
        SRCPORT=$4

        echo "Stop wireguard firewall settings on $GWIF"
        $IPTABLES -D INPUT -i $GWIF -j ACCEPT
        $IPTABLES -D OUTPUT -o $GWIF -j ACCEPT
        $IP6TABLES -D INPUT -i $GWIF -j ACCEPT
        $IP6TABLES -D OUTPUT -o $GWIF -j ACCEPT
        if [ "$SRCFMT" = "IPv6" ] ; then
            $IP6TABLES -D INPUT -p udp --dport $SRCPORT -j ACCEPT
        else
            $IPTABLES -D INPUT -p udp --dport $SRCPORT -j ACCEPT
        fi
    fi
}

gretap_firewall_start() {
    if [ "$#" -gt 0 ] ; then
        GREIF=$1

        echo "Start gretap firewall settings on $GREIF"
        $IPTABLES -A INPUT -i $GREIF -j ACCEPT
        $IPTABLES -A OUTPUT -o $GREIF -j ACCEPT
        $IP6TABLES -A INPUT -i $GREIF -j ACCEPT
        $IP6TABLES -A OUTPUT -o $GREIF -j ACCEPT
    fi
}

gretap_firewall_stop() {
    if [ "$#" -gt 0 ] ; then
        GREIF=$1

        echo "Stop gretap firewall settings on $GREIF"
        $IPTABLES -D INPUT -i $GREIF -j ACCEPT
        $IPTABLES -D OUTPUT -o $GREIF -j ACCEPT
        $IP6TABLES -D INPUT -i $GREIF -j ACCEPT
        $IP6TABLES -D OUTPUT -o $GREIF -j ACCEPT
    fi
}

# Enable NAT for all traffic
nat_forward_start () {
    if [ "$#" -ne 1 ]; then
        echo "NAT enable:Using default parameters"
    else
        APIF=$1
    fi

    echo "Start NAT over $APIF"

    echo 1 > /proc/sys/net/ipv4/ip_forward
    $IPTABLES -t nat -C POSTROUTING -o $APIF -j MASQUERADE
    if [ $? -ne 0 ]; then
        $IPTABLES -I FORWARD -j ACCEPT
        # Masquerade all NAT traffic
        $IPTABLES -t nat -F POSTROUTING
        $IPTABLES -t nat -A POSTROUTING -o $APIF -j MASQUERADE
    fi
}

nat_forward_stop () {
    if [ "$#" -ne 1 ]; then
        echo "NAT disable: Using default parameters"
    else
        APIF=$1
    fi

    echo "Stop NAT"

    echo 0 > /proc/sys/net/ipv4/ip_forward
    # Stop accepting forward traffic
    $IPTABLES -F FORWARD
    # Delete NAT masquerade rule.
    $IPTABLES -t nat -D POSTROUTING -o $APIF -j MASQUERADE
}

tcp_tunnel_start () {
    if [ "$#" -ne 6 ]; then
        echo 'TCP tunnel start: Using default parameters'
    else
        SRCIP=$1
        SRCPORT=$2
        DESTIP=$3
        DESTPORT=$4
        P2PIF=$5
        IP=$6
    fi

    echo "Start TCP tunnel SrcIp($SRCIP) SrcPort($SRCPORT) DestIP($DESTIP) DestPort($DESTPORT) on P2P($P2PIF - $IP)"

    $IPTABLES -C INPUT -i ${P2PIF} -p TCP --dport ${DESTPORT} -j ACCEPT
    if [ $? -ne 0 ]; then
        $IPTABLES -A INPUT -i ${P2PIF} -p TCP --dport ${DESTPORT} -j ACCEPT
        $IPTABLES -t nat -A PREROUTING -i ${P2PIF} -p TCP --dport ${SRCPORT} -d ${SRCIP} -j DNAT --to-destination ${DESTIP}:${DESTPORT}
    fi
}

tcp_tunnel_stop () {
    if [ "$#" -ne 6 ]; then
        echo 'TCP tunnel stop: Using default parameters'
    else
        SRCIP=$1
        SRCPORT=$2
        DESTIP=$3
        DESTPORT=$4
        P2PIF=$5
        IP=$6
    fi

    echo "Stop TCP Tunnel"

    $IPTABLES -D INPUT -i ${P2PIF} -p TCP --dport ${DESTPORT} -j ACCEPT
    $IPTABLES -t nat -D PREROUTING -i ${P2PIF} -p TCP --dport ${SRCPORT} -d ${SRCIP} -j DNAT --to-destination ${DESTIP}:${DESTPORT}
}

start_setup_firewall () {

    case "$1" in
        default)
            shift
            default_firewall_setup "$@"
            default_ipv6_firewall_setup "$@"
            alexa_hybrid_firewall_setup "$@"
            ;;
        p2p)
            shift
            p2p_firewall_start "$@"
            ;;
        hostap)
            shift
            hostap_firewall_start "$@"
            ;;
        bridged)
            shift
            bridged_firewall_start
            ;;
        wg)
            shift
            wg_firewall_start "$@"
            ;;
        gretap)
            shift
            gretap_firewall_start "$@"
            ;;
        nat_forward)
            shift
            nat_forward_start "$@"
            ;;
        nat)
            shift
            nat_firewall_start "$@"
            ;;
        tcp_tunnel)
            shift
            tcp_tunnel_start "$@"
            ;;
        *)
            exit 1
            ;;
    esac
}

stop_setup_firewall () {

    case "$1" in
        p2p)
            shift
            p2p_firewall_stop "$@"
            ;;
        hostap)
            shift
            hostap_firewall_stop "$@"
            ;;
        bridged)
            shift
            bridged_firewall_stop
            ;;
        wg)
            shift
            wg_firewall_stop "$@"
            ;;
        gretap)
            shift
            gretap_firewall_stop "$@"
            ;;
        nat_forward)
            shift
            nat_forward_stop "$@"
            ;;
        nat)
            shift
            nat_firewall_stop "$@"
            ;;
        tcp_tunnel)
            shift
            tcp_tunnel_stop "$@"
            ;;
        *)
            exit 1
            ;;
    esac
}

case "$1" in
    start)
        if [ "$2" ]
        then
            shift
            # Setup any specific settings
            start_setup_firewall "$@"
            exit 0
        fi
        ;;
    stop)
        if [ "$2" ]
        then
            shift
            # Stop any specific settings
            stop_setup_firewall "$@"
            exit 0
        fi
        ;;
    *)
        exit 1
        ;;
esac

exit 1

