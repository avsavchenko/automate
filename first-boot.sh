#!/bin/bash

if [ -f /var/lock/first-boot ]
then
	exit 0
fi

echo "Update packages? (y/n)"
read UPDATE
if [ "$UPDATE" == "y" ]
then
	apt-get -y update
	apt-get -y upgrade
fi

git clone https://github.com/angryelectron/automate /tmp/automate

echo "Change hostname? (y/n)"
read HOST
if [ "$HOST" == "y" ]
then
	/tmp/automate/hostname.sh
fi

echo "Configure network interface? (y/n)"
read CONFIG
while [ "$CONFIG" == "y" ]
do
	/tmp/automate/network.sh
	echo "Configure another interface? (y/n)"
	read CONFIG
done

echo "Configure iSCSI target DRBD node? (y/n)"
read NODE
if [ "$NODE" == "y" ]
then
	/tmp/automate/drbd.sh
fi

touch /var/lock/first-boot
