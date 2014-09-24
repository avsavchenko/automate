#!/bin/bash
# This script will setup a clean BackupPC Server on Ubuntu Server 12.04
# References;
#  http://www.tolaris.com/2012/06/14/smb-and-backuppc-on-ubuntu-12-04/
#  http://www.tolaris.com/2013/10/02/backuppc-3-3-0-packaged-for-ubuntu-precise-smb-fixed/

### Make sure user is root
if [[ $EUID -ne 0 ]]; then
echo "Must run as root/sudo user."
  exit -1
fi

### make sure this is Ubuntu 12.04 
cat /etc/issue | grep "Ubuntu 12.04" 
if [ $? -ne 0 ]; then
	echo "This script only works on Ubuntu 12.04"
	exit -1
fi 

## remove old packages installed from the stock repos
apt-get remove smbclient backuppc

## add repo for latest BackupPC packages
echo "## Updated BackupPC and fixed smbclient packages" > /etc/apt/sources.list.d/tolaris-backuppc.list
echo "deb http://www.tolaris.com/apt/ precise main" >> /etc/apt/sources.list.d/tolaris-backuppc.list
wget -q http://www.tolaris.com/apt/tolaris-keyring.gpg -O- | sudo apt-key add -

## install
apt-get -y update
apt-get -y install backuppc 
apt-get -y install smbclient=2:3.5.11~dfsg-1ubuntu2.3 samba-common=2:3.5.11~dfsg-1ubuntu2.3 samba=2:3.5.11~dfsg-1ubuntu2.3 libwbclient0=2:3.5.11~dfsg-1ubuntu2.3 samba-common-bin=2:3.5.11~dfsg-1ubuntu2.3
echo "smbclient hold" | sudo dpkg --set-selections

## verify smbclient version
smbclient -V | grep "Version 3.5.11"
if [ $? -ne 0 ]; then
	echo "smbclient version may not be compatible with BackupPc"
fi

## Make a copy of the default data structure.  Very handy in disaster recovery. 
if [ -e backuppc-datadir.default.tar.gz ]; then
  rm backuppc-datadir-default.tar.gz
fi
tar czf backuppc-datadir-default.tar.gz /var/lib/backuppc

## configure
echo "Changing password for backuppc user."
htpasswd /etc/backuppc/htpasswd backuppc
