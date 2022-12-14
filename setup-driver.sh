#!/bin/bash

set -x

export SRC="/local/repository"
cd $SRC
. $SRC/setup-lib.sh

ALLNODESCRIPTS="setup-disk-space.sh"
HEADNODESCRIPTS="setup-nfs-server.sh setup-ssh.sh setup-nginx.sh setup-kubespray.sh setup-kubernetes-extra.sh"
if [ $INSTALLORANSC -eq 1 ]; then
    HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-oran.sh setup-xapp-kpimon.sh setup-xapp-nexran.sh"
fi
HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-e2-bindings.sh setup-asn1c.sh setup-srslte.sh"
WORKERNODESCRIPTS="setup-nfs-client.sh setup-ssh.sh"

# Don't run setup-driver.sh twice
if [ -f $OURDIR/setup-driver-done ]; then
    echo "setup-driver already ran; not running again"
    exit 0
fi
for script in $ALLNODESCRIPTS ; do
    cd $SRC
    $SRC/$script | tee - $OURDIR/${script}.log 2>&1
done
if [ "$HOSTNAME" = "node-0" ]; then
    for script in $HEADNODESCRIPTS ; do
	cd $SRC
	$SRC/$script | tee - $OURDIR/${script}.log 2>&1
    done
else
    for script in $WORKERNODESCRIPTS ; do
	cd $SRC
	$SRC/$script | tee - $OURDIR/${script}.log 2>&1
    done
fi

exit 0
