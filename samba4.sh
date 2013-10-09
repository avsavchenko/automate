#!/bin/bash
#
# This script will setup a clean Debian Squeeze 32-bit Server as
# a Samba4 domain controller based on Sernet samba packages.
#

### Make sure user is root
if [[ $EUID -ne 0 ]]; then
echo "Must run as root/sudo user."
  exit -1
fi

### make sure this is debian 32-bit
if [ `uname -m` != "i686" ]; then 
	echo "Only 32-bit platform is supported by sernet"
	exit -1
fi
cat /etc/issue | grep Debian
if [ $? -ne 0 ]; then
	echo "Only Debian is supported by sernet"
	exit -1
fi 


### get sernet packages
if [ ! -f sernet-samba4-appliance_0.6-1_i386.deb ]; then
	wget http://ftp.sernet.de/pub/samba4AD/sernet-samba4-appliance/packages/sernet-samba4-appliance_0.6-1_i386.deb
fi
if [ ! -f sernet-samba4_4.0.0-1_i386.deb ]; then
	wget http://ftp.sernet.de/pub/samba4AD/sernet-samba4-appliance/packages/sernet-samba4_4.0.0-1_i386.deb
fi

### install
apt-get -y update
dpkg -i sernet*.deb	#this will fail but setup dependencies
apt-get -y install -f	#install the dependencies
dpkg -i sernet*.deb	#install sernet packages

### configure
/usr/share/samba4app/scripts/dcpromo.sh
