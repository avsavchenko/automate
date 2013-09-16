#!/bin/bash
# Hardware assumptions
#	eth0 = management and iSCSI target interface
#	eth1 = replication network, usually a direct link between nodes
#	disks: 4; os, drbd meta data, iscsi config data, and iscsi LUN

#
# User Settings (TODO: read values from user)
#
DEV_DRBD=/dev/xvdb
DEV_CONFIG=/dev/xvdc
DEV_ISCSI=/dev/xvde

PRIMARY_FQDN=primary.test.local
PRIMARY_HOST="${PRIMARY_FQDN%%.*}"
PRIMARY_LAN=192.168.7.1
PRIMARY_SAN=10.10.10.1

SECONDARY_FQDN=secondary.test.local
SECONDARY_HOST="${SECONDARY_FQDN%%.*}"
SECONDARY_LAN=192.168.7.2
SECONDARY_SAN=10.10.10.2

VIRTUAL_LAN=192.168.7.3
IS_PRIMARY=true
IQN=iqn.2013-09.com.ziptrek:iscsi.target.0

#
# Advanced Users Settings (don't need to modify in most situations)
#
PART_DRBD="$DEV_DRBD"1
PART_CONFIG="$DEV_CONFIG"1
PART_ISCSI="$DEV_ISCSI"1

#
# check for permissions
#
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root/sudo user"
	exit 1
fi 

#
# Partition.  
# Three paritions are required:  one for the DRBD metadata,
# one for config files, and one for the iSCSI target
#
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_DRBD
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_CONFIG
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_ISCSI

#
# Configure Hosts
#
echo "$PRIMARY_LAN\t$PRIMARY_FQDN\t${PRIMARY_HOST}" >> /etc/hosts
echo "$SECONDARY_LAN\t$SECONDARY_FQDN\t${SECONDARY_HOST}" >> /etc/hosts

#
# Install some packages
#
apt-get update
apt-get install ntp drbd8-utils heartbeat iscsitarget iscsitarget-dkms

#
# Configure DRBD
#
for file in /sbin/drbdsetup /sbin/drbdadmin /sbin/drbdmeta
do
	chgrp haclient $file
	chmod o-x $file
	chmod u+s $file
done

### begin iscsi.res ###
cat > /etc/drbd.d/iscsi.res << EOL
resource iscsi.config {
        protocol C;
 
        handlers {
        pri-on-incon-degr "echo o > /proc/sysrq-trigger ; halt -f";
        pri-lost-after-sb "echo o > /proc/sysrq-trigger ; halt -f";
        local-io-error "echo o > /proc/sysrq-trigger ; halt -f";
        outdate-peer "/usr/lib/heartbeat/drbd-peer-outdater -t 5";      
        }

        startup {
        degr-wfc-timeout 120;
        }

        disk {
        on-io-error detach;
        }

        net {
        cram-hmac-alg sha1;
        shared-secret "password";
        after-sb-0pri disconnect;
        after-sb-1pri disconnect;
        after-sb-2pri disconnect;
        rr-conflict disconnect;
        }

        syncer {
        rate 100M;
        verify-alg sha1;
        al-extents 257;
        }

        on $PRIMARY_HOST {
        device  /dev/drbd0;
        disk    $PART_CONFIG;
        address $PRIMARY_SAN:7788;
        meta-disk $PART_DRBD[0];
        }

        on $SECONDARY_HOST {
        device  /dev/drbd0;
        disk    $PART_CONFIG;
        address $SECONDARY_SAN:7788;
        meta-disk $PART_DRBD[0];
        }
}

resource iscsi.target.0 {
        protocol C;
 
        handlers {
        pri-on-incon-degr "echo o > /proc/sysrq-trigger ; halt -f";
        pri-lost-after-sb "echo o > /proc/sysrq-trigger ; halt -f";
        local-io-error "echo o > /proc/sysrq-trigger ; halt -f";
        outdate-peer "/usr/lib/heartbeat/drbd-peer-outdater -t 5";      
        }

        startup {
        degr-wfc-timeout 120;
        }

        disk {
        on-io-error detach;
        }

        net {
        cram-hmac-alg sha1;
        shared-secret "password";
        after-sb-0pri disconnect;
        after-sb-1pri disconnect;
        after-sb-2pri disconnect;
        rr-conflict disconnect;
        }

        syncer {
        rate 100M;
        verify-alg sha1;
        al-extents 257;
        }

        on $PRIMARY_HOST {
        device  /dev/drbd1;
        disk    $PART_ISCSI;
        address $PRIMARY_SAN:7789;
        meta-disk $PART_DRBD[1];
        }

        on $SECONDARY_HOST {
        device  /dev/drbd1;
        disk    $PART_ISCSI;
        address $SECONDARY_SAN:7789;
        meta-disk $PART_DRBD[1];
        }
}
EOL
### end iscsi.res

#
# Initialize DRBD 
#
drbdadm create-md all
service drbd restart
if $IS_PRIMARY ; then
	drbdadm -- --overwrite-data-of-peer primary all
	mkfs.jfs /dev/drbd0
	mkdir -p /mnt/config
	mount /dev/drbd0 /mnt/config
	mkdir -p /mnt/config/iet

	### begin ietd.conf
	echo > /mnt/config/iet/ietd.conf << EOL	
	Target $IQN 
        #IncomingUser geekshlby secret
        #OutgoingUser geekshlby password
        Lun 0 Path=$PART_ISCSI,Type=blockio
        Alias disk0
        MaxConnections         1
        InitialR2T             Yes
        ImmediateData          No
        MaxRecvDataSegmentLength 8192
        MaxXmitDataSegmentLength 8192
        MaxBurstLength         262144
        FirstBurstLength       65536
        DefaultTime2Wait       2
        DefaultTime2Retain     20
        MaxOutstandingR2T      8
        DataPDUInOrder         Yes
        DataSequenceInOrder    Yes
        ErrorRecoveryLevel     0
        HeaderDigest           CRC32C,None
        DataDigest             CRC32C,None
        Wthreads               8
	EOL	
	### end ietd.conf

	echo ALL ALL > /mnt/config/iet/initiators.allow	
	echo ALL $VIRTUAL_LAN > /mnt/config/iet/targets.allow
fi

#
# Setup iscsi target
#
sed -i s/false/true/ /etc/default/iscsitarget
update-rc.d -f iscsitarget remove
mv /etc/iet /etc/iet.orig
ln -s /mnt/config/iet /etc/iet

#
# Setup heartbeat
#
mv /etc/heartbeat/ha.cf /etc/heartbeat/ha.orig
cat > /etc/heartbeat/ha.orig << EOL
	logfile /var/log/ha.log
	logfacility local0
	keepalive 2
	deadtime 30
	warntime 10
	initdead 120
	bcast eth0, eth1
	auto_failback on
	node $PRIMARY_HOST
	node $SECONDARY_HOST
EOL
cat > /etc/heartbeat/authkeys << EOL
	auth 3
	3 md5 password
EOL
chmod 600 /etc/heartbeat/authkeys
cat > /etc/heartbeat/haresources << EOL
	$PRIMARY_HOST drbddisk::iscsi.config Filesystem::/dev/drbd0::/mnt/config::jfs
	$PRIMARY_HOST IPAddr::$VIRTUAL_LAN/24/eth0 drbddisk::iscsi.target.0 iscsitarget
EOL

echo Configure other node and/or reboot this node now
exit 0