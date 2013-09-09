#!/bin/bash

#
# Change Ubuntu hostname 
# Copyright 2013 Andrew Bythell <abythell@ieee.org>
#
# usage: hostname.sh [fqdn]
# if fqdn not provided, user will be prompted
#

#
# check for permissions
#
if [[ $EUID -ne 0 ]]; then
	echo "Hostname can only be changed by root/sudo user"
	exit 1
fi 

#
# get new hostname 
#
if [ "$#" == "0" ]; then
	echo "Enter new fully-qualified hostname"
	read FQDN
else
	FQDN=$1
fi
OLDHOST=`hostname`
NEWHOST="${FQDN%%.*}"
DOMAIN="${FQDN#*.}"

#
# update hostname and hosts file
#
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$FQDN\t$NEWHOST/" /etc/hosts
sed -i "s/$OLDHOST/$NEWHOST/g" /etc/hostname
hostname $NEWHOST

exit 0
