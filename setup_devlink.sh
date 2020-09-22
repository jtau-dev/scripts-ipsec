#!/bin/bash
set -x #echo on

REMOTE_SERVER=${1:-10.7.159.36}
devlink dev eswitch set pci/0000:03:00.0 mode legacy
#echo none > /sys/class/net/p0/compat/devlink/ipsec_mode
echo dmfs > /sys/bus/pci/devices/0000\:03\:00.0/net/p0/compat/devlink/steering_mode
echo full > /sys/class/net/p0/compat/devlink/ipsec_mode
devlink dev eswitch set pci/0000:03:00.0 mode switchdev

#stop openvswitch
service openvswitch stop

ssh $REMOTE_SERVER -p 2222 /bin/bash << EOF
	#!/bin/bash
	set -x #echo on

	devlink dev eswitch set pci/0000:03:00.0 mode legacy
	#echo none > /sys/class/net/p0/compat/devlink/ipsec_mode
	echo dmfs > /sys/bus/pci/devices/0000\:03\:00.0/net/p0/compat/devlink/steering_mode
	echo full > /sys/class/net/p0/compat/devlink/ipsec_mode
	devlink dev eswitch set pci/0000:03:00.0 mode switchdev

	service openvswitch stop
EOF
