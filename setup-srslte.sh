#!/bin/bash

set -x

export SRC=`dirname $0`
cd $SRC
. $SRC/setup-lib.sh

if [ -f $OURDIR/setup-srslte-done ]; then
    echo "setup-srslte already ran; not running again"
    exit 0
fi

logtstart "srslte"

#
# srsLTE build
#
cd $OURDIR

maybe_install_packages \
    cmake libfftw3-dev libmbedtls-dev libboost-program-options-dev \
    libconfig++-dev libsctp-dev libzmq3-dev

git clone https://gitlab.flux.utah.edu/powderrenewpublic/srslte-ric
cd srslte-ric
mkdir -p build
cd build
cmake ../ \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DRIC_GENERATED_E2AP_BINDING_DIR=$OURDIR/E2AP-v01.01 \
    -DRIC_GENERATED_E2SM_KPM_BINDING_DIR=$OURDIR/E2SM-KPM \
    -DRIC_GENERATED_E2SM_NI_BINDING_DIR=$OURDIR/E2SM-NI \
    -DRIC_GENERATED_E2SM_GNB_NRT_BINDING_DIR=$OURDIR/E2SM-GNB-NRT
NCPUS=`grep proc /proc/cpuinfo | wc -l`
if [ -n "$NCPUS" ]; then
    make -j$NCPUS
else
    make
fi
$SUDO make install
$SUDO ./srslte_install_configs.sh service

logtend "srslte"
touch $OURDIR/setup-srslte-done
