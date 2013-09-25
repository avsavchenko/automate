#!/bin/bash
# Assumptions:
#	disks: 4; os, drbd meta data, iscsi config data, and iscsi LUN

#
# check for permissions
#
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root/sudo user"
	exit 1
fi 

#
# Disk Settings
#
echo "DRBD Meta Device (eg. /dev/sdb1, /dev/xvdb1)"
read DEV_DRBD
echo "iSCSI LUN Device (eg. /dev/sdb1, /dev/xvdc1)"
read DEV_ISCSI
echo "Primary Node Name (on SAN)"
read PRIMARY_HOST
echo "Secondary Node Name (on SAN)"
read SECONDARY_HOST
echo "Is this the primary node? (y/n)"
read IS_PRIMARY

PRIMARY_IP=`getent ahosts $PRIMARY_HOST | grep STREAM | awk '{print $1}'`
SECONDARY_IP=`getent ahosts $SECONDARY_HOST | grep STREAM | awk '{print $1}'`

#
# Install some packages
#
apt-get -y install ntp drbd8-utils

#
# Configure DRBD
#
for file in /sbin/drbdsetup /sbin/drbdadm /sbin/drbdmeta
do
	chgrp haclient $file
	chmod o-x $file
	chmod u+s $file
done

### begin iscsi-lun1.res ###
cat > /etc/drbd.d/iscsi-lun1.res << EOL
resource iscsi.lun.1 {
        protocol A;
 
        disk {
          on-io-error detach;
	  fencing resource-only;
        }

        net {
          cram-hmac-alg sha1;
          shared-secret "password";
        }

        syncer {
        rate 100M;
        al-extents 257;
        }

        device  /dev/drbd1;
        disk    $DEV_ISCSI;
        meta-disk $DEV_DRBD[1];

        on $PRIMARY_HOST {
          address $PRIMARY_IP:7789;
        }

        on $SECONDARY_HOST {
          address $SECONDARY_IP:7789;
        }
}
EOL
### end iscsi-lun1.res

#
# Initialize DRBD 
#
drbdadm create-md iscsi.lun.1
service drbd restart
if [ "$IS_PRIMARY" == "y" ]
then
	drbdadm -- --overwrite-data-of-peer primary iscsi.lun.1
fi
