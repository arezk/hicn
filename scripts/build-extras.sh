# Copyright (c) 2017-2019 Cisco and/or its affiliates.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash
set -euxo pipefail

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
APT_PATH=`which apt-get` || true
apt_get=${APT_PATH:-"/usr/local/bin/apt-get"}

PACKAGECLOUD_RELEASE_REPO_DEB="https://packagecloud.io/install/repositories/fdio/release/script.deb.sh"
PACKAGECLOUD_RELEASE_REPO_RPM="https://packagecloud.io/install/repositories/fdio/release/script.rpm.sh"

VPP_GIT_REPO="https://git.fd.io/vpp"
VPP_BRANCH="stable/2005"

VPP_VERSION_DEB="20.05-release"
VPP_VERSION_RPM="20.05-release.x86_64"

BUILD_TOOLS_UBUNTU="build-essential doxygen"
LIBSSL_LIBEVENT_UBUNTU="libevent-dev libssl-dev"
DEPS_UBUNTU="libvppinfra=${VPP_VERSION_DEB}     \
             libvppinfra-dev=${VPP_VERSION_DEB} \
             vpp=${VPP_VERSION_DEB}             \
             vpp-dev=${VPP_VERSION_DEB}         \
             vpp-plugin-core=${VPP_VERSION_DEB}"

# BUILD_TOOLS_GROUP_CENTOS="'Development Tools'"
DEPS_CENTOS="vpp-devel-${VPP_VERSION_RPM}   \
             vpp-lib-${VPP_VERSION_RPM}     \
             centos-release-scl             \
             devtoolset-7"

LATEST_EPEL_REPO="http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"

install_cmake() {
    if ! grep -q "8.8.8.8" /etc/resolv.conf; then
        echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
    fi

    cat /etc/resolv.conf

    CMAKE_INSTALL_SCRIPT_URL="https://cmake.org/files/v3.8/cmake-3.8.0-Linux-x86_64.sh"
    CMAKE_INSTALL_SCRIPT="/tmp/install_cmake.sh"
    curl ${CMAKE_INSTALL_SCRIPT_URL} > ${CMAKE_INSTALL_SCRIPT}

    sudo mkdir -p /opt/cmake
    sudo bash ${CMAKE_INSTALL_SCRIPT} --skip-license --prefix=/opt/cmake
    export PATH=/opt/cmake/bin:${PATH}
}

# Parameters:
# $1 = Distribution id
# $2 = Distribution codename
#
setup_fdio_repo() {
    DISTRIB_ID=${1}

    if [ "${DISTRIB_ID}" == "ubuntu" ]; then
        curl -s ${PACKAGECLOUD_RELEASE_REPO_DEB} | sudo bash
    elif [ "${DISTRIB_ID}" == "centos" ]; then
        curl -s ${PACKAGECLOUD_RELEASE_REPO_RPM} | sudo bash
        curl ${LATEST_EPEL_REPO} > epel-release-latest-7.noarch.rpm
        rpm -ivh epel-release-latest-7.noarch.rpm || true
        rm epel-release-latest-7.noarch.rpm
    else
        echo "Distribution ${DISTRIB_ID} is not supported"
        exit -1
    fi
}

setup() {
    # Figure out what system we are running on
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        echo "ERROR: System configuration not recognized. Build failed"
        exit -1
    fi

    DISTRIB_ID=${ID}

    echo DISTRIBUTION: ${PRETTY_NAME}
    echo ARCHITECTURE: $(uname -m)

    ARCH=`uname -m`
    if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
        install_cmake
    fi
    setup_fdio_repo ${DISTRIB_ID}

    if [ "${DISTRIB_ID}" == "ubuntu" ]; then
        sudo ${apt_get} update || true
    fi

    # Install dependencies
    if [ ${DISTRIB_ID} == "ubuntu" ]; then
        echo ${BUILD_TOOLS_UBUNTU} ${DEPS_UBUNTU} | xargs sudo ${apt_get} install -y --allow-unauthenticated --no-install-recommends
        sudo ${apt_get} clean && sudo ${apt_get} update
        sudo ${apt_get} install -y --allow-unauthenticated --no-install-recommends libpcre3-dev
    elif [ ${DISTRIB_ID} == "centos" ]; then
        # echo ${BUILD_TOOLS_GROUP_CENTOS} | xargs sudo yum groupinstall -y --nogpgcheck
        echo ${DEPS_CENTOS} | xargs sudo yum install -y --nogpgcheck
        sudo yum install devtoolset-7 pcre-devel

        CXX_COMPILER="/opt/rh/devtoolset-7/root/usr/bin/c++"
        CC_COMPILER="/opt/rh/devtoolset-7/root/usr/bin/cc"

        ${CXX_COMPILER} --version
        ${CC_COMPILER} --version

        export CC=${CC_COMPILER} CXX=${CXX_COMPILER}
    fi
}

# Parameters:
# $1 = Package name
#
build_package() {
    setup

    echo "*******************************************************************"
    echo "********************* STARTING PACKAGE BUILD **********************"
    echo "*******************************************************************"

    mkdir -p build && pushd build

    rm -rf *
    cmake -DCMAKE_INSTALL_PREFIX=/usr   \
          -DBUILD_LIBHICN=OFF           \
          -DBUILD_UTILS=OFF             \
          -DBUILD_HICNPLUGIN=OFF        \
          -DBUILD_HICNLIGHT=OFF         \
          -DBUILD_LIBTRANSPORT=OFF      \
          -DBUILD_APPS=OFF              \
          -DBUILD_CTRL=OFF              \
          -DBUILD_SYSREPOPLUGIN=OFF     \
          -DBUILD_EXTRAS=ON             \
          ${SCRIPT_PATH}/..
    make package

    find . -type d -iname '_CPack_Packages' -print0 | xargs -0 rm -rf -- || true
    find . -iname '*Unspecified*' -print0 | xargs -0 rm -rf -- || true

    popd

    echo "*******************************************************************"
    echo "*****************  BUILD COMPLETED SUCCESSFULLY *******************"
    echo "*******************************************************************"
}

build_package

exit 0
