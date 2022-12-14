#!/bin/bash

EXPTTYPE="ORAN/Kubernetes"

# Build config
HOSTNAME=`hostname`
SWAPPER=$USER
NODECOUNT=2
NODES=( "node-0" "node-1" )
NODESIP=( "10.0.2.183" "10.0.2.10" )

INSTALLORANSC=1
INSTALLONFSDRAN=0
BUILDSRSLTE=1
BUILDOAI=0
BUILDORANSC=0
DOKPIMONDEPLOY=0
DONEXRANDEPLOY=0
RICBRONZE=2
RICCHERRY=3
RICDAWN=4
RICRELEASE=dawn


# Filesystem config
DO_APT_INSTALL=1
DO_APT_UPGRADE=0
DO_APT_DIST_UPGRADE=0
DO_APT_UPDATE=1
OURDIR=/local/setup
WWWPRIV=$OURDIR
WWWPUB=/local/profile-public
SETTINGS=$OURDIR/settings
LOCALSETTINGS=$OURDIR/settings.local
STORAGEDIR=/storage
DONFS=1
NFSASYNC=0
NFSEXPORTDIR=$STORAGEDIR/nfs
NFSMOUNTDIR=/nfs


# Network config
SUBNETMARK=24
SINGLENODE_MGMT_IP=10.10.1.1
SINGLENODE_MGMT_NETMASK=255.255.0.0
SINGLENODE_MGMT_NETBITS=16
SINGLENODE_MGMT_CIDR=${SINGLENODE_MGMT_IP}/${SINGLENODE_MGMT_NETBITS}


# Kubespray
HEAD="node-0"
DOLOCALREGISTRY=1
KUBESPRAYREPO="https://github.com/kubernetes-incubator/kubespray.git"
KUBESPRAYUSEVIRTUALENV=1
KUBESPRAY_VIRTUALENV=kubespray-virtualenv
KUBESPRAYVERSION=release-2.16
DOCKERVERSION=
DOCKEROPTIONS=
KUBEVERSION=
HELMVERSION=v3.5.4
KUBENETWORKPLUGIN=calico
KUBEENABLEMULTUS=0
KUBEPROXYMODE=ipvs
KUBEPODSSUBNET="192.168.0.0/17"
KUBESERVICEADDRESSES="192.168.128.0/17"
KUBEDOMETALLB=0
KUBEFEATUREGATES=[SCTPSupport=true,EphemeralContainers=true]
KUBELETCUSTOMFLAGS=[--allowed-unsafe-sysctls=net.*]
KUBELETMAXPODS=120
KUBEALLWORKERS=0
KEYNAME=id_rsa


# SSL
SSLCERTTYPE=none
SSLCERTCONFIG=proxy
