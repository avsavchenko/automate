#!/bin/bash
#Script to configure Ubuntu network interface

IFNAME=eth1
IFTYPE="static"
IFADDRESS="10.0.1.1"

#
# check for permissions
#
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root/sudo user"
	exit 1
fi 

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
	cat >> /etc/network/interfaces << EOL

auto $IFNAME
iface $IFNAME inet static
address $IFADDRESS 
netmask 255.255.255.0
EOL

elif [ "$IFTYPE" == "dhcp" ]
then
	cat >> /etc/network/interfaces << EOL

auto $IFNAME
iface $IFNAME inet dhcp
EOL

fi
