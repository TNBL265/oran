#!/bin/bash

##
## Setup a ssh key on the calling node *for the calling uid*, and
## broadcast it to all the other nodes' authorized_keys file.
##

set -x

if [ -z "$EUID" ]; then
    EUID=`id -u`
fi

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-ssh-$EUID-done ]; then
    echo "setup-ssh-$EUID already ran; not running again"
    exit 0
fi

logtstart "ssh-$EUID"

KEYNAME=id_rsa

# Remove it if it exists...
rm -f ~/.ssh/${KEYNAME} ~/.ssh/${KEYNAME}.pub

if [ ! -f ~/.ssh/${KEYNAME} ]; then
    ssh-keygen -t rsa -f ~/.ssh/${KEYNAME} -N ''
fi

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi

if [ "$HOSTNAME" = "$HEAD" ]; then
    $SUDO cp ~/.ssh/${KEYNAME}.pub $NFSEXPORTDIR
    cat $NFSEXPORTDIR/${KEYNAME}.pub >> ~/.ssh/authorized_keys
else
    while [ ! -e $NFSMOUNTDIR/${KEYNAME}.pub ]; do
        echo "Waiting for server SSH public key../"
        sleep 10
    done
    cat $NFSMOUNTDIR/${KEYNAME}.pub >> ~/.ssh/authorized_keys
fi

sshkeyscan() {
    #
    # Run ssh-keyscan on all nodes to build known_hosts.
    #
    ssh-keyscan $NODES >> ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
    for node in "${NODES[@]}" ; do
	mgmtip=`getnodeip $node`
	echo "$mgmtip $node,$mgmtip"
    done | ssh-keyscan -4 -f - >> ~/.ssh/known_hosts
}
sshkeyscan

logtend "ssh-$EUID"

touch $OURDIR/setup-ssh-$EUID-done

exit 0
