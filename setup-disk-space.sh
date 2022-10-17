#!/bin/bash
##
## Setup extra space.  We prefer the LVM route, using all available PVs
## to create a big VG.
##

set -x

if [ -z "$EUID" ]; then
    EUID=`id -u`
fi

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/disk-space-done ]; then
    exit 0
fi

logtstart "disk-space"

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi
if [ -f $LOCALSETTINGS ]; then
    . $LOCALSETTINGS
fi

ARCH=`uname -m`

maybe_install_packages lvm2 maybe_install_packages thin-provisioning-tools

#
# First try to make LVM volumes. We  use /storage later, so we make the dir either way.

$SUDO mkdir -p ${STORAGEDIR}
echo "STORAGEDIR=${STORAGEDIR}" >> $LOCALSETTINGS

LVM=1
VGNAME="${HOSTNAME}-vg"
LVNAME=root

# Get integer total space (G) available.
VGTOTAL=`$SUDO vgs -o vg_size --noheadings --units G $VGNAME | sed -ne 's/ *\([0-9]*\)[0-9\.]*G/\1/p'`
echo "VGNAME=${VGNAME}" >> $LOCALSETTINGS
echo "VGTOTAL=${VGTOTAL}" >> $LOCALSETTINGS
echo "LVM=${LVM}" >> $LOCALSETTINGS
echo "LVNAME=${LVNAME}" >> $LOCALSETTINGS
echo "/dev/$VGNAME/$LVNAME ${STORAGEDIR} ext4 defaults 0 0" \
    | $SUDO tee -a /etc/fstab
$SUDO mount ${STORAGEDIR}

#
# Redirect some Docker/k8s dirs into our extra storage.
#
for dir in docker kubelet ; do
    $SUDO mkdir -p $STORAGEDIR/$dir /var/lib/$dir
    $SUDO mount -o bind $STORAGEDIR/$dir /var/lib/$dir
    echo "$STORAGEDIR/$dir /var/lib/$dir none defaults,bind 0 0" \
        | $SUDO tee -a /etc/fstab
done

logtend "disk-space"
touch $OURDIR/disk-space-done
