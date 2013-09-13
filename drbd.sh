#!/bin/bash

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
echo "DRBD Meta device (eg. /dev/xvdb)"
read DEV_DRBD
echo "Config device (eg. /dev/xvdc)"
read DEV_CONFIG
echo "iSCSI device (eg. /dev/xvde)"
read DEV_ISCSI

(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_DRBD
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_CONFIG
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk $DEV_ISCSI

PART_DRBD="$DEV_DRBD"1
PART_CONFIG="$DEV_CONFIG"1
PART_ISCSI="$DEV_ISCSI"1

#
# Configure Hosts
#
echo "Primary Hostname (fqdn)"
read PRIMARY_FQDN
PRIMARY_HOST="${PRIMARY_FQDN%%.*}"
echo "Primary LAN IP Address"
read PRIMARY_LAN
echo "Primary SAN IP Address"
read PRIMARY_SAN
 
echo "Secondary Hostname (fqdn)"
read SECONDARY_FQDN
SECONDARY_HOST="${SECONDARY_FQDN%%.*}"
echo "Secondary LAN IP Address"
read SECONDARY_LAN
echo "Secondary SAN IP Address"
read SECONDARY_SAN
 
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
