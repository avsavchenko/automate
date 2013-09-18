#!/bin/bash
# Script to configure Ubuntu network interface
# Copyright 2013, Andrew Bythell <abythell@ieee.org>
#
# Script may be run with no arguments in interactive mode, or
# by specifying command line arguments:
#
#	network.sh <ifname> dhcp
# or
#	network.sh <ifname> static <ip-address> 
# where
#	ifname=eth1, eth2, etc.

#
# check for permissions - must run as root
#
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root/sudo user"
	exit 1
fi 

#
# check for command line arguments
#
if [ $# -ne 0 ]
then
	IFNAME=$1
	IFTYPE=$2
	if [ "$IFTYPE" == "static" ]
	then
		if [ $# -ne 3 ]
		then
			echo "usage: network.sh <ifname> <static|dhcp> <ip addr>"
			exit -1
		fi
		IFADDRESS=$3
	elif [ "$IFTYPE" != "dhcp" ]
	then
		echo "type must be 'static' or 'dhcp'"
		exit -1
	fi 
else
	echo "Current network interfaces:"
	cat /etc/network/interfaces | grep iface | awk '{print $2}'
	echo 
	echo "Name of interface to configure? (eg. 'eth1')"
	read IFNAME
	echo "Network type: static or dhcp?"
	read IFTYPE
	if [ "$IFTYPE" == "static" ]
	then
		echo "IP Address?"
		read IFADDRESS
	fi
fi


if [ "$IFTYPE" == "static" ]
then
	cat >> /etc/network/interfaces << EOL

auto $IFNAME
iface $IFNAME inet static
address $IFADDRESS 
netmask 255.255.255.0
EOL
	### end interfaces

elif [ "$IFTYPE" == "dhcp" ]
then
	cat >> /etc/network/interfaces << EOL

auto $IFNAME
iface $IFNAME inet dhcp
EOL
	## end interfaces
fi

ifup $IFNAME
