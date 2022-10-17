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

sshkeyscan() {
    #
    # Run ssh-keyscan on all nodes to build known_hosts.
    #
    ssh-keyscan $NODES >> ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
    for node in $NODES ; do
	mgmtip=`getnodeip $node`
	echo "$mgmtip $node,$mgmtip"
    done | ssh-keyscan -4 -f - >> ~/.ssh/known_hosts
}

KEYNAME=id_rsa

# Remove it if it exists...
rm -f ~/.ssh/${KEYNAME} ~/.ssh/${KEYNAME}.pub

if [ ! -f ~/.ssh/${KEYNAME} ]; then
    ssh-keygen -t rsa -f ~/.ssh/${KEYNAME} -N ''
fi

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi

if [ $GENIUSER -eq 1 ]; then
    SHAREDIR=/proj/$EPID/exp/$EEID/tmp

    $SUDO mkdir -p $SHAREDIR
    $SUDO chown $EUID $SHAREDIR

    cp ~/.ssh/${KEYNAME}.pub $SHAREDIR/$HOSTNAME

    for node in $NODES ; do
	while [ ! -f $SHAREDIR/$node ]; do
            sleep 1
	done
	echo $node is up
	cat $SHAREDIR/$node >> ~/.ssh/authorized_keys
    done
else
    for node in $NODES ; do
	if [ "$node" != "$HOSTNAME" ]; then 
	    fqdn=`getfqdn $node`
	    SUCCESS=1
	    while [ $SUCCESS -ne 0 ]; do
		su -c "$SSH  -l $SWAPPER $fqdn sudo tee -a ~/.ssh/authorized_keys" $SWAPPER < ~/.ssh/${KEYNAME}.pub
		SUCCESS=$?
		sleep 1
	    done
	fi
    done
fi

sshkeyscan

logtend "ssh-$EUID"

touch $OURDIR/setup-ssh-$EUID-done

exit 0
