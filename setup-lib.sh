#!/bin/bash

DIRNAME=`dirname $0`

#
# Setup our core vars
#
. "$DIRNAME/setup-parameters.sh"

if [ -z "$EUID" ]; then
    EUID=`id -u`
fi
SUDO=
if [ ! $EUID -eq 0 ] ; then
    SUDO=sudo
fi

[ ! -d $OURDIR ] && ($SUDO mkdir -p $OURDIR && $SUDO chown $SWAPPER $OURDIR)
[ ! -e $SETTINGS ] && touch $SETTINGS
[ ! -e $LOCALSETTINGS ] && touch $LOCALSETTINGS
cd $OURDIR

# Setup time logging stuff early
TIMELOGFILE=$OURDIR/setup-time.log
FIRSTTIME=0
if [ ! -f $OURDIR/setup-lib-first ]; then
    touch $OURDIR/setup-lib-first
    FIRSTTIME=`date +%s`
fi

logtstart() {
    area=$1
    varea=`echo $area | sed -e 's/[^a-zA-Z_0-9]/_/g'`
    stamp=`date +%s`
    date=`date`
    eval "LOGTIMESTART_$varea=$stamp"
    echo "START $area $stamp $date" >> $TIMELOGFILE
}

logtend() {
    area=$1
    #varea=${area//-/_}
    varea=`echo $area | sed -e 's/[^a-zA-Z_0-9]/_/g'`
    stamp=`date +%s`
    date=`date`
    eval "tss=\$LOGTIMESTART_$varea"
    tsres=`expr $stamp - $tss`
    resmin=`perl -e 'print '"$tsres"' / 60.0 . "\n"'`
    echo "END $area $stamp $date" >> $TIMELOGFILE
    echo "TOTAL $area $tsres $resmin" >> $TIMELOGFILE
}

if [ $FIRSTTIME -ne 0 ]; then
    logtstart "libfirsttime"
fi

#
# Setup apt-get to not prompt us
#
if [ ! -e $OURDIR/apt-configured ]; then
    echo "force-confdef" | $SUDO tee -a /etc/dpkg/dpkg.cfg.d/cloudlab
    echo "force-confold" | $SUDO tee -a /etc/dpkg/dpkg.cfg.d/cloudlab
    touch $OURDIR/apt-configured
fi
export DEBIAN_FRONTEND=noninteractive
# -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" 
DPKGOPTS=''
APTGETINSTALLOPTS='-y'
APTGETINSTALL="$SUDO apt-get $DPKGOPTS install $APTGETINSTALLOPTS"
# Don't install/upgrade packages if this is not set
if [ ${DO_APT_INSTALL} -eq 0 ]; then
    APTGETINSTALL="/bin/true ${APTGETINSTALL}"
fi

do_apt_update() {
    if [ ! -f $OURDIR/apt-updated -a "${DO_APT_UPDATE}" = "1" ]; then
	$SUDO apt-get update
	touch $OURDIR/apt-updated
    fi
}

are_packages_installed() {
    retval=1
    while [ ! -z "$1" ] ; do
	dpkg -s "$1" >/dev/null 2>&1
	if [ ! $? -eq 0 ] ; then
	    retval=0
	fi
	shift
    done
    return $retval
}

maybe_install_packages() {
    if [ ! ${DO_APT_UPGRADE} -eq 0 ] ; then
        # Just do an install/upgrade to make sure the package(s) are installed
	# and upgraded; we want to try to upgrade the package.
	$APTGETINSTALL $@
	return $?
    else
	# Ok, check if the package is installed; if it is, don't install.
	# Otherwise, install (and maybe upgrade, due to dependency side effects).
	# Also, optimize so that we try to install or not install all the
	# packages at once if none are installed.
	are_packages_installed $@
	if [ $? -eq 1 ]; then
	    return 0
	fi

	retval=0
	while [ ! -z "$1" ] ; do
	    are_packages_installed $1
	    if [ $? -eq 0 ]; then
		$APTGETINSTALL $1
		retval=`expr $retval \| $?`
	    fi
	    shift
	done
	return $retval
    fi
}

##
## Figure out the system python version.
##
python --version
if [ ! $? -eq 0 ]; then
    python3 --version
    if [ $? -eq 0 ]; then
	PYTHON=python3
    else
	are_packages_installed python3
	success=`expr $? = 0`
	# Keep trying again with updated cache forever;
	# we must have python.
	while [ ! $success -eq 0 ]; do
	    do_apt_update
	    $SUDO apt-get $DPKGOPTS install $APTGETINSTALLOPTS python3
	    success=$?
	done
	PYTHON=python3
    fi
else
    PYTHON=python
fi
$PYTHON --version | grep -q "Python 3"
if [ $? -eq 0 ]; then
    PYVERS=3
    PIP=pip3
else
    PYVERS=2
    PIP=pip
fi
PYTHONBIN=`which $PYTHON`


#
# Adjust our RIC version if necessary.
#
if [ -z "$RICRELEASE" ]; then
    RICRELEASE=$RICDEFAULTRELEASE
fi
if [ "$RICRELEASE" = "bronze" ]; then
    RICVERSION=$RICBRONZE
elif [ "$RICRELEASE" = "cherry" ]; then
    RICVERSION=$RICCHERRY
elif [ "$RICRELEASE" = "dawn" ]; then
    RICVERSION=$RICDAWN
fi


# Check if our init is systemd
dpkg-query -S /sbin/init | grep -q systemd
HAVE_SYSTEMD=`expr $? = 0`

. /etc/lsb-release
DISTRIB_MAJOR=`echo $DISTRIB_RELEASE | cut -d. -f1`


# Construct parallel-ssh hosts files
if [ ! -e $OURDIR/pssh.all-nodes ]; then
    echo > $OURDIR/pssh.all-nodes
    echo > $OURDIR/pssh.other-nodes
    for node in $NODES ; do
	echo $node >> $OURDIR/pssh.all-nodes
	[ "$node" = "$NODEID" ] && continue
	echo $node >> $OURDIR/pssh.other-nodes
    done
fi


##
## Setup our Ubuntu package mirror, if necessary.
##
grep MIRRORSETUP $SETTINGS
if [ ! $? -eq 0 ]; then
    if [ ! "x${UBUNTUMIRRORHOST}" = "x" ]; then
	oldstr='us.archive.ubuntu.com'
	newstr="${UBUNTUMIRRORHOST}"

	if [ ! "x${UBUNTUMIRRORPATH}" = "x" ]; then
	    oldstr='us.archive.ubuntu.com/ubuntu'
	    newstr="${UBUNTUMIRRORHOST}/${UBUNTUMIRRORPATH}"
	fi

	echo "*** Changing Ubuntu mirror from $oldstr to $newstr ..."
	$SUDO sed -E -i.us.archive.ubuntu.com -e "s|(${oldstr})|$newstr|" /etc/apt/sources.list
    fi

    echo "MIRRORSETUP=1" >> $SETTINGS
fi

if [ ! -f $OURDIR/apt-updated -a "${DO_APT_UPDATE}" = "1" ]; then
    #
    # Attempt to handle old EOL releases; so far only need to handle utopic
    #
    . /etc/lsb-release
    grep -q old-releases /etc/apt/sources.list
    if [  $? != 0 -a "x${DISTRIB_CODENAME}" = "xutopic" ]; then
	sed -i -re 's/([a-z]{2}\.)?archive.ubuntu.com|security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
    fi
    $SUDO apt-get update
    touch $OURDIR/apt-updated
fi

if [ ! -f $OURDIR/apt-dist-upgraded -a "${DO_APT_DIST_UPGRADE}" = "1" ]; then
    # First, mark grub packages not to be upgraded; we don't want an
    # install going to the wrong place.
    PKGS="grub-common grub-gfxpayload-lists grub-pc grub-pc-bin grub2-common"
    for pkg in $PKGS; do
	$SUDO apt-mark hold $pkg
    done
    $SUDO apt-get dist-upgrade -y
    for pkg in $PKGS; do
	$SUDO apt-mark unhold $pkg
    done
    touch $OURDIR/apt-dist-upgraded
fi


#
# Process our network information.
#
netmask2prefix() {
    nm=$1
    bits=0
    IFS=.
    read -r i1 i2 i3 i4 <<EOF
$nm
EOF
    unset IFS
    for n in $i1 $i2 $i3 $i4 ; do
	v=128
	while [ $v -gt 0 ]; do
	    bits=`expr $bits + \( \( $n / $v \) % 2 \)`
	    v=`expr $v / 2`
	done
    done
    echo $bits
}

getnodeip() {
    node=$1
    if [ -z "$node" ]; then
      echo ""
      return
    fi
    ip=`grep ${node} /etc/hosts | cut -f1`
	  echo $ip
}

getnetmask() {
    network=$1

    if [ -z "$network" ]; then
	echo ""
	return
    fi

    nm=`sed -ne "s/^${network},\([0-9\.]*\),.*$/\1/p" $TOPOMAP`
    if [ "$network" = "$MGMTLAN" -a -z "$nm" ]; then
	echo $SINGLENODE_MGMT_NETMASK
    else
	echo $nm
    fi
}

getnetmaskprefix() {
    netmask=`getnetmask $1`
    if [ -z "$netmask" ]; then
	echo ""
	return
    fi
    prefix=`netmask2prefix $netmask`
    echo $prefix
}

getnetworkip() {
    node=$1
    network=$2
    nodeip=`getnodeip $node $network`
    netmask=`getnetmask $network`

    IFS=.
    read -r i1 i2 i3 i4 <<EOF
$nodeip
EOF
    read -r m1 m2 m3 m4 <<EOF
$netmask
EOF
    unset IFS
    printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

#
# Note that the `.`s are escaped enough to make it from shell into yaml into
# ansible and eventually into the golang regexp used by flanneld.  Not
# generic.
#
getnetworkregex() {
    node=$1
    network=$2
    nodeip=`getnodeip $node $network`
    netmask=`getnetmask $network`

    IFS=.
    read -r i1 i2 i3 i4 <<EOF
$nodeip
EOF
    read -r m1 m2 m3 m4 <<EOF
$netmask
EOF
    unset IFS
    REGEX=""
    if [ $m1 -ge 255 ]; then
	REGEX="${REGEX}$i1"
    else
	REGEX="${REGEX}[0-9]{1,3}"
    fi
    REGEX="${REGEX}\\\\\\\\."
    if [ $m2 -ge 255 ]; then
	REGEX="${REGEX}$i2"
    else
	REGEX="${REGEX}[0-9]{1,3}"
    fi
    REGEX="${REGEX}\\\\\\\\."
    if [ $m3 -ge 255 ]; then
	REGEX="${REGEX}$i3"
    else
	REGEX="${REGEX}[0-9]{1,3}"
    fi
    REGEX="${REGEX}\\\\\\\\."
    if [ $m4 -ge 255 ]; then
	REGEX="${REGEX}$i4"
    else
	REGEX="${REGEX}[0-9]{1,3}"
    fi
    echo "$REGEX"
}

##
## Util functions.
##
service_init_reload() {
    if [ ${HAVE_SYSTEMD} -eq 1 ]; then
	$SUDO systemctl daemon-reload
    fi
}

service_enable() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	$SUDO update-rc.d $service enable
    else
	$SUDO systemctl enable $service
    fi
}

service_disable() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	$SUDO update-rc.d $service disable
    else
	$SUDO systemctl disable $service
    fi
}

service_restart() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	$SUDO service $service restart
    else
	$SUDO systemctl restart $service
    fi
}

service_stop() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	$SUDO service $service stop
    else
	$SUDO systemctl stop $service
    fi
}

service_start() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	$SUDO service $service start
    else
	$SUDO systemctl start $service
    fi
}

GETTER=`which wget`
if [ -n "$GETTER" ]; then
    GETTEROUT="$GETTER --remote-encoding=unix -c -O"
    GETTER="$GETTER --remote-encoding=unix -c -N"
    GETTERLOGARG="-o"
else
    GETTER="/bin/false NO WGET INSTALLED!"
    GETTEROUT="/bin/false NO WGET INSTALLED!"
fi

get_url() {
    if [ -z "$GETTER" ]; then
	/bin/false
	return
    fi

    urls="$1"
    outfile="$2"
    if [ -n "$3" ]; then
	retries=$3
    else
	retries=3
    fi
    if [ -n "$4" ]; then
	interval=$4
    else
	interval=5
    fi
    if [ -n "$5" ]; then
	force="$5"
    else
	force=0
    fi

    if [ -n "$outfile" -a -f "$outfile" -a $force -ne 0 ]; then
	rm -f "$outfile"
    fi

    success=0
    tmpfile=`mktemp /tmp/wget.log.XXX`
    for url in $urls ; do
	tries=$retries
	while [ $tries -gt 0 ]; do
	    if [ -n "$outfile" ]; then
		$GETTEROUT $outfile $GETTERLOGARG $tmpfile "$url"
	    else
		$GETTER $GETTERLOGARG $tmpfile "$url"
	    fi
	    if [ $? -eq 0 ]; then
		if [ -z "$outfile" ]; then
		    # This is the best way to figure out where wget
		    # saved a file!
		    outfile=`bash -c "cat $tmpfile | sed -n -e 's/^.*Saving to: '$'\u2018''\([^'$'\u2019'']*\)'$'\u2019''.*$/\1/p'"`
		    if [ -z "$outfile" ]; then
			outfile=`bash -c "cat $tmpfile | sed -n -e 's/^.*File '$'\u2018''\([^'$'\u2019'']*\)'$'\u2019'' not modified.*$/\1/p'"`
		    fi
		fi
		success=1
		break
	    else
		sleep $interval
		tries=`expr $tries - 1`
	    fi
	done
	if [ $success -eq 1 ]; then
	    break
	fi
    done

    rm -f $tmpfile

    if [ $success -eq 1 ]; then
	echo "$outfile"
	/bin/true
    else
	/bin/false
    fi
}

# Must have these packages
maybe_install_packages curl
maybe_install_packages ethtool
maybe_install_packages pssh
maybe_install_packages autoconf
maybe_install_packages libtool
maybe_install_packages bison
maybe_install_packages flex
maybe_install_packages byacc

# Time logging
if [ $FIRSTTIME -ne 0 ]; then
    logtend "libfirsttime"
fi
