#!/bin/bash
# This script will setup a clean Ubuntu 12.04 Server as one of two nodes in a
# high-availability, block-replicated, iSCSI target.  A useful resource that was
# the basis of this script can be found at
# http:/;/wiki.skytech.dk/images/4/44/Ha-iscsi.pdf
# 
# WARNING: This script modifies disks and partition tables - Use with caution! 
# If in doubt, review the Disk Setup section below before proceeding.
# 
# Prerequisites:
# 	* node has Ubuntu Server 12.04 installed 
# 	* node has one unconfigured network interface
	* node has one working network interface connected to the Internet
# 	* node has 2 blank disks attached which do not contain the OS 
# 	* disks are the same size on all nodes (For Now)
# 
# A single disk can be used if additional disks are unavailable, but the Disk 
# Setup section will have to be reviewed.  Modify the Cluster Config below, then
# run this script twice, once per node, adjusting the Node Config each time.

#
# User Config - Update this for each Node 
#
NODENAME="sr-node1"
NODE_IP="10.0.0.1"

#
# Cluster Config - must be the same on all nodes in the Cluster
#
PRIMARY_NODENAME="sr-node1"
SECONDARY_NODENAME="sr-node2"
IF="eth1"
PRIMARY_IP="10.0.0.1"
SECONDARY_IP="10.0.0.2"
ISCSI_IP="10.0.0.3"
DRBD_RESOURCE="iscsi.lun.1"
DRBD_DEVICE="/dev/drbd1"
META_DEV="/dev/xvdb1"
LUN_DEV="/dev/xvdc1"
IQN="iqn.2013-09.com.ziptrek:sr.lun.1" 


#
# Network Setup
#
HOSTNAME=$(hostname)
sed -i "s/^127\.0\.1\.1/#127\.0\.1\.1/" /etc/hosts
sed -i "s/$HOSTNAME/$NODENAME/g" /etc/hostname
sed -i "s/$HOSTNAME/$NODENAME/g" /etc/hosts
hostname $NODENAME

cat >> /etc/network/interfaces << EOL

auto $IF
iface $IF inet static
address $NODE_IP
netmask 255.255.255.0
EOL

ifup $IF
printf "\n10.0.0.1\t$PRIMARY_NODENAME\n" >> /etc/hosts
printf "10.0.0.2\t$SECONDARY_NODENAME\n" >> /etc/hosts


#
# Disk Setup - create a single Linux partition on each disk.  
# Your partition and/or disk scheme may differ.  
# TODO: create 2nd partition if using the same disk.
#

dd if=/dev/zero of=${META_DEV:0:-1} bs=512 count=1
dd if=/dev/zero of=${LUN_DEV:0:-1} bs=512 count=1
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk ${META_DEV:0:-1}
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk ${LUN_DEV:0:-1}

#
# DRBD Setup
#
apt-get -y install ntp drbd8-utils
cat > /etc/drbd.d/$DRBD_RESOURCE.res << EOL
resource $DRBD_RESOURCE {
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

            device $DRBD_DEVICE;
            disk $LUN_DEV;
            meta-disk $META_DEV[1];

            on $PRIMARY_NODENAME {
              address $PRIMARY_IP:7789;
            }

            on $SECONDARY_NODENAME {
              address $SECONDARY_IP:7789;
            }
}
EOL

drbdadm create-md $DRBD_RESOURCE
service drbd restart
if [ "$NODE_IP" == "$PRIMARY_IP" ]; then
	drbdadm -- --overwrite-data-of-peer primary $DRBD_RESOURCE
fi

#
# iSCSI - all of the config is controlled by Pacemaker 
#
apt-get -y install iscsitarget iscsitarget-dkms

#
# Pacemaker
#
apt-get -y install pacemaker cman fence-agents
cat > /etc/cluster/cluster.conf << EOL
<?xml version="1.0"?>
<cluster config_version="1" name="pacemaker1">
  <logging debug="off"/>
  <clusternodes>
        <clusternode name="$PRIMARY_NODENAME" nodeid="1">
          <fence>
            <method name="pcmk-redirect">
              <device name="pcmk" port="$PRIMARY_NODENAME"/>
            </method>
          </fence>
        </clusternode>
        <clusternode name="$SECONDARY_NODENAME" nodeid="2">
          <fence>
            <method name="pcmk-redirect">
              <device name="pcmk" port="$SECONDARY_NODENAME"/>
            </method>
          </fence>
        </clusternode>
  </clusternodes>
  <fencedevices>
        <fencedevice name="pcmk" agent="fence_pcmk"/>
  </fencedevices>
</cluster>
EOL

echo "CMAN_QUORUM_TIMEOUT=0" >> /etc/default/cman
service cman start
service pacemaker start
if [ "$NODE_IP" == "$PRIMARY_IP" ]; then
	crm configure property stonith-enabled="false"
	crm configure property no-quorum-policy="ignore"
	crm configure property default-resource-stickiness="200"
	crm configure primitive p_drbd_lun1 ocf:linbit:drbd params drbd_resource="$DRBD_RESOURCE" op monitor interval="29s" role="Master" op monitor interval="31s" role="Slave"
 	crm configure primitive p_ip_iscsi ocf:heartbeat:IPaddr params ip="$ISCSI_IP" op monitor interval="10s"
 	crm configure primitive p_iscsi_lun1 ocf:heartbeat:iSCSILogicalUnit params target_iqn="$IQN" lun="1" path="$DRBD_DEVICE" implementation="iet" op monitor interval="10s"
 	crm configure primitive p_iscsi ocf:heartbeat:iSCSITarget params iqn="$IQN" implementation="iet" tid="1" op monitor interval="10s"
 	crm configure group g_iscsi p_iscsi p_iscsi_lun1 p_ip_iscsi
 	crm configure ms ms_drbd_lun1 p_drbd_lun1 meta master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
 	crm configure colocation c_iscsi inf: g_iscsi ms_drbd_lun1:Master
	crm configure location l_iscsi_prefer_primary g_iscsi 50: $PRIMARY_NODENAME 
fi
