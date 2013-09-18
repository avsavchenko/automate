#!/bin/bash

if [ -f /var/run/lock/first-boot ]
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

(cd $HOME/automate; git pull)

echo "Change hostname? (y/n)"
read HOST
if [ "$HOST" == "y" ]
then
	$HOME/automate/hostname.sh
fi

echo "Configure network interface? (y/n)"
read CONFIG
while [ "$CONFIG" == "y" ]
do
	$HOME/automate/network.sh
	echo "Configure another interface? (y/n)"
	read CONFIG
done

echo "Configure iSCSI target DRBD node? (y/n)"
read NODE
if [ "$NODE" == "y" ]
then
	$HOME/automate/drbd.sh
fi

touch /var/run/lock/first-boot

echo "You can find this script at $HOME/automate/first-boot.sh, if you need to"
echo "run it again.  Remove /var/run/lock/first-boot to re-enable."
