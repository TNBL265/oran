#!/bin/bash

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/kubespray-done ]; then
    exit 0
fi

logtstart "kubespray"

# First, we need yq.
maybe_install_packages gnupg
maybe_install_packages software-properties-common
are_packages_installed yq
if [ ! $? -eq 1 ]; then
    if [ ! "$ARCH" = "aarch64" ]; then
	$SUDO apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64
	$SUDO add-apt-repository -y ppa:rmescandon/yq
	maybe_install_packages yq
    fi
fi
which yq
if [ ! $? -eq 0 ]; then
    fname=yq_linux_amd64
    curl -L -o /tmp/$fname.tar.gz \
	https://github.com/mikefarah/yq/releases/download/v4.13.2/$fname.tar.gz
    tar -xzvf /tmp/$fname.tar.gz -C /tmp
    chmod 755 /tmp/$fname
    $SUDO mv /tmp/$fname /usr/local/bin/yq
fi

cd $OURDIR
if [ -e kubespray ]; then
    rm -rf kubespray
fi
git clone $KUBESPRAYREPO kubespray
if [ -n "$KUBESPRAYVERSION" ]; then
    cd kubespray && git checkout "$KUBESPRAYVERSION" && cd ..
fi

#
# Get Ansible and the kubespray python reqs installed.
#
maybe_install_packages ${PYTHON}
if [ $KUBESPRAYUSEVIRTUALENV -eq 1 ]; then
    if [ -e $KUBESPRAY_VIRTUALENV ]; then
	maybe_install_packages libffi-dev
	. $KUBESPRAY_VIRTUALENV/bin/activate
    else
	maybe_install_packages virtualenv

	mkdir -p $KUBESPRAY_VIRTUALENV
	virtualenv $KUBESPRAY_VIRTUALENV --python=${PYTHON}
	. $KUBESPRAY_VIRTUALENV/bin/activate
    fi
    $PIP install -r kubespray/requirements.txt
    find $KUBESPRAY_VIRTUALENV -name ansible-playbook
    if [ ! $? -eq 0 ]; then
	$PIP install ansible==2.9
    fi
else
    maybe_install_packages software-properties-common ${PYTHON}-pip
    $SUDO add-apt-repository --yes --update ppa:ansible/ansible
    maybe_install_packages ansible libffi-dev
    $PIP install -r kubespray/requirements.txt
fi

#
# Build the kubespray inventory file.  The basic builder changes our
# hostname, and we don't want that.  So do it manually.  We generate
# .ini format because it's much simpler to do in shell.
#
INVDIR=$OURDIR/inventories/kubernetes
mkdir -p $INVDIR
cp -pR kubespray/inventory/sample/group_vars $INVDIR
mkdir -p $INVDIR/host_vars

HEAD_MGMT_IP=`getnodeip $HEAD`
HEAD_DATA_IP=`getnodeip $HEAD`
INV=$INVDIR/inventory.ini

echo '[all]' > $INV
for node in "${NODES[@]}" ; do
    mgmtip=`getnodeip $node`
    echo "$node ansible_host=$mgmtip ip=$mgmtip access_ip=$mgmtip" >> $INV

    touch $INVDIR/host_vars/$node.yml
done
# The first 2 nodes are kube-master.
echo '[kube-master]' >> $INV
for node in `echo "${NODES[@]}" | cut -d ' ' -f-2` ; do
    echo "$node" >> $INV
done
# The first 3 nodes are etcd.
etcdcount=3
if [ $NODECOUNT -lt 3 ]; then
    etcdcount=1
fi
echo '[etcd]' >> $INV
for node in `echo "${NODES[@]}" | cut -d ' ' -f-$etcdcount` ; do
    echo "$node" >> $INV
done
# The last 2--N nodes are kube-node, unless there is only one node, or
# if user allows.
kubenodecount=2
if [ $KUBEALLWORKERS -eq 1 -o "$NODES" = `echo $NODES | cut -d ' ' -f2` ]; then
    kubenodecount=1
fi
echo '[kube-node]' >> $INV
for node in `echo "${NODES[@]}" | cut -d ' ' -f${kubenodecount}-` ; do
    echo "$node" >> $INV
done
cat <<EOF >> $INV
[k8s-cluster:children]
kube-master
kube-node
EOF

if [ $NODECOUNT -eq 1 ]; then
    # We cannot use localhost; we have to use a dummy device, and that
    # works fine.  We need to fix things up because there is nothing in
    # /etc/hosts, nor have ssh keys been scanned and placed in
    # known_hosts.
    ip=`getnodeip $HEAD`
    prefix=$SUBNETMARK
    cidr=$ip/$prefix
    echo "$ip $HEAD" | $SUDO tee -a /etc/hosts
    $SUDO ip link add type dummy name dummy0
    $SUDO ip addr add $cidr dev dummy0
    $SUDO ip link set dummy0 up
    DISTRIB_MAJOR=`. /etc/lsb-release && echo $DISTRIB_RELEASE | cut -d. -f1`
    if [ $DISTRIB_MAJOR -lt 18 ]; then
	cat <<EOF | $SUDO tee /etc/network/interfaces.d/kube-single-node.conf
auto dummy0
iface dummy0 inet static
    address $cidr
    pre-up ip link add dummy0 type dummy
EOF
    else
	cat <<EOF | $SUDO tee /etc/systemd/network/dummy0.netdev
[NetDev]
Name=dummy0
Kind=dummy
EOF
	cat <<EOF | $SUDO tee /etc/systemd/network/dummy0.network
[Match]
Name=dummy0

[Network]
DHCP=no
Address=$cidr
IPForward=yes
EOF
    fi

    ssh-keyscan $HEAD >> ~/.ssh/known_hosts
    ssh-keyscan $ip >> ~/.ssh/known_hosts
fi

#
# Get our basic configuration into place.
#
OVERRIDES=$INVDIR/overrides.yml
cat <<EOF >> $OVERRIDES
override_system_hostname: false
disable_swap: true
ansible_python_interpreter: $PYTHONBIN
ansible_user: $SWAPPER
kube_apiserver_node_port_range: 2000-36767
kubeadm_enabled: true
dns_min_replicas: 1
dashboard_enabled: true
dashboard_token_ttl: 43200
EOF
if [ -n "${DOCKERVERSION}" ]; then
    cat <<EOF >> $OVERRIDES
docker_version: ${DOCKERVERSION}
EOF
fi
if [ -n "${KUBEVERSION}" ]; then
    cat <<EOF >> $OVERRIDES
kube_version: ${KUBEVERSION}
EOF
fi
if [ -n "$KUBEFEATUREGATES" ]; then
    echo "kube_feature_gates: $KUBEFEATUREGATES" \
	>> $OVERRIDES
fi
if [ -n "$KUBELETCUSTOMFLAGS" ]; then
    echo "kubelet_custom_flags: $KUBELETCUSTOMFLAGS" \
	>> $OVERRIDES
fi
if [ -n "$KUBELETMAXPODS" -a $KUBELETMAXPODS -gt 0 ]; then
    echo "kubelet_max_pods: $KUBELETMAXPODS" \
        >> $OVERRIDES
fi

if [ "$KUBENETWORKPLUGIN" = "calico" ]; then
    cat <<EOF >> $OVERRIDES
kube_network_plugin: calico
docker_iptables_enabled: true
calico_ip_auto_method: "can-reach=$HEAD_DATA_IP"
EOF
elif [ "$KUBENETWORKPLUGIN" = "weave" ]; then
cat <<EOF >> $OVERRIDES
kube_network_plugin: weave
EOF
elif [ "$KUBENETWORKPLUGIN" = "canal" ]; then
cat <<EOF >> $OVERRIDES
kube_network_plugin: canal
EOF
fi

if [ "$KUBEENABLEMULTUS" = "1" ]; then
cat <<EOF >> $OVERRIDES
kube_network_plugin_multus: true
multus_version: stable
EOF
fi

if [ "$KUBEPROXYMODE" = "iptables" ]; then
    cat <<EOF >> $OVERRIDES
kube_proxy_mode: iptables
EOF
elif [ "$KUBEPROXYMODE" = "ipvs" ]; then
    cat <<EOF >> $OVERRIDES
kube_proxy_mode: ipvs
EOF
fi

cat <<EOF >> $OVERRIDES
kube_pods_subnet: $KUBEPODSSUBNET
kube_service_addresses: $KUBESERVICEADDRESSES
EOF

#
# Enable helm.
#
echo "helm_enabled: true" >> $OVERRIDES
echo 'helm_stable_repo_url: "https://charts.helm.sh/stable"' >> $OVERRIDES
if [ -n "${HELMVERSION}" ]; then
    echo "helm_version: ${HELMVERSION}" >> $OVERRIDES
fi

#
# Add a bunch of options most people will find useful.
#
DOCKOPTS='--insecure-registry={{ kube_service_addresses }} {{ docker_log_opts }}'
DOCKOPTS="--insecure-registry=`getnodeip $HEAD`/$SUBNETMARK $DOCKOPTS"

cat <<EOF >> $OVERRIDES
docker_dns_servers_strict: false
kubectl_localhost: true
kubeconfig_localhost: true
docker_options: "$DOCKOPTS ${DOCKEROPTIONS}"
metrics_server_enabled: true
EOF
#kube_api_anonymous_auth: false

#
# Run ansible to build our kubernetes cluster.
#
cd $OURDIR/kubespray
ansible-playbook -i $INVDIR/inventory.ini cluster.yml -e @${OVERRIDES} -b -v \
    --private-key=~/.ssh/id_rsa

if [ ! $? -eq 0 ]; then
    cd ..
    echo "ERROR: ansible-playbook failed; check logfiles!"
    exit 1
fi
cd ..

$SUDO rm -rf /root/.kube
$SUDO mkdir -p /root/.kube
$SUDO cp -p $INVDIR/artifacts/admin.conf /root/.kube/config

kubectl wait pod -n kube-system --for=condition=Ready --all

logtend "kubespray"
touch $OURDIR/kubespray-done
