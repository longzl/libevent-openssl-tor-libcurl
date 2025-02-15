#!/bin/bash
#  Builds openssl for all five current iPhone targets: iPhoneSimulator-i386,
#  iPhoneSimulator-x86_64, iPhoneOS-armv7, iPhoneOS-armv7s, iPhoneOS-arm64.
#
#  Copyright 2012 Mike Tigas <mike@tig.as>
#
#  Based on work by Felix Schulze on 16.12.10.
#  Copyright 2010 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
###########################################################################
#  Choose your openssl version and your currently-installed iOS SDK version:
#
VERSION="1.1.1t"
#VERSION="1.0.2-beta1"
USERSDKVERSION="16.2"
MINIOSVERSION="11.0"
VERIFYGPG=false

###########################################################################
#
# Don't change anything under this line!
#
###########################################################################

# No need to change this since xcode build will only compile in the
# necessary bits from the libraries we create
ARCHS="arm64 arm64e x86_64"

DEVELOPER=`xcode-select -print-path`
#DEVELOPER="/Applications/Xcode.app/Contents/Developer"

# for continuous integration
# https://travis-ci.org/mtigas/iOS-OnionBrowser
if [ "$1" == "--noverify" ]; then
    VERIFYGPG=false
fi
if [ "$2" == "--i386only" ]; then
    ARCHS="i386"
fi

#if [[ ! -z "$TRAVIS" && $TRAVIS ]]; then
#   # Travis CI highest available version
#   echo "==================== TRAVIS CI ===================="
#   SDKVERSION="7.0"
#else
#   SDKVERSION="$USERSDKVERSION"
#fi
SDKVERSION="$USERSDKVERSION"

cd "`dirname \"$0\"`"
REPOROOT=$(pwd)

# Where we'll end up storing things in the end
OUTPUTDIR="${REPOROOT}/dependencies"
mkdir -p ${OUTPUTDIR}/include
mkdir -p ${OUTPUTDIR}/lib

BUILDDIR="${REPOROOT}/build"

# where we will keep our sources and build from.
SRCDIR="${BUILDDIR}/src"
mkdir -p $SRCDIR
# where we will store intermediary builds
INTERDIR="${BUILDDIR}/built"
mkdir -p $INTERDIR

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/openssl-${VERSION}.tar.gz" ]; then
    echo "Downloading openssl-${VERSION}.tar.gz"
    curl -O https://www.openssl.org/source/openssl-${VERSION}.tar.gz
fi
echo "Using openssl-${VERSION}.tar.gz"

# see https://www.openssl.org/about/,
# up to you to set up `gpg` and add keys to your keychain
if $VERIFYGPG; then
    if [ ! -e "${SRCDIR}/openssl-${VERSION}.tar.gz.asc" ]; then
        curl -O https://www.openssl.org/source/openssl-${VERSION}.tar.gz.asc
    fi
    echo "Using openssl-${VERSION}.tar.gz.asc"
    if out=$(gpg --status-fd 1 --verify "openssl-${VERSION}.tar.gz.asc" "openssl-${VERSION}.tar.gz" 2>/dev/null) &&
    echo "$out" | grep -qs "^\[GNUPG:\] VALIDSIG"; then
        echo "$out" | egrep "GOODSIG|VALIDSIG"
        echo "Verified GPG signature for source..."
    else
        echo "$out" >&2
        echo "COULD NOT VERIFY PACKAGE SIGNATURE..."
        exit 1
    fi
fi

tar zxf openssl-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/openssl-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=`which ccache`
if [ $? == "0" ]; then
    echo "Building with ccache: $CCACHE"
    CCACHE="${CCACHE} "
else
    echo "Building without ccache"
    CCACHE=""
fi
set -e # back to regular "bail out on error" mode

export ORIGINALPATH=$PATH

for ARCH in ${ARCHS}
do
    if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
    else
        sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
        PLATFORM="iPhoneOS"
    fi
    
    mkdir -p "${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"

    export PATH="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/:${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/usr/bin/:${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin:${DEVELOPER}/usr/bin:${ORIGINALPATH}"
    export CC="${CCACHE}`which gcc` -arch ${ARCH} -miphoneos-version-min=${MINIOSVERSION}"

    if [ "${ARCH}" == "x86_64" ] || [ "${ARCH}" == "arm64" ]; then
        ./configure BSD-generic64 no-asm enable-ec_nistp_64_gcc_128 \
        --openssldir="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
    else
        ./configure BSD-generic32 no-asm \
        --openssldir="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
    fi

    # add -isysroot to configure-generated CFLAGS
    sed -ie "s!^CFLAG=!CFLAG=-isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk !" "Makefile"

    # Build the application and install it to the fake SDK intermediary dir
    # we have set up. Make sure to clean up afterward because we will re-use
    # this source tree to cross-compile other targets.
    make
    make install
    make clean
done

########################################

echo "Build library..."
OUTPUT_LIBS="libssl.a libcrypto.a"
for OUTPUT_LIB in ${OUTPUT_LIBS}; do
    INPUT_LIBS=""
    for ARCH in ${ARCHS}; do
        if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ]; then
            PLATFORM="iPhoneSimulator"
        else
            PLATFORM="iPhoneOS"
        fi
        INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
        if [ -e $INPUT_ARCH_LIB ]; then
            INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
        fi
    done
    # Combine the three architectures into a universal library.
    if [ -n "$INPUT_LIBS"  ]; then
        lipo -create $INPUT_LIBS \
        -output "${OUTPUTDIR}/lib/${OUTPUT_LIB}"
    else
        echo "$OUTPUT_LIB does not exist, skipping (are the dependencies installed?)"
    fi
done

for ARCH in ${ARCHS}; do
    if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
    else
        PLATFORM="iPhoneOS"
    fi
    cp -R ${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/include/* ${OUTPUTDIR}/include/
    if [ $? == "0" ]; then
        # We only need to copy the headers over once. (So break out of forloop
        # once we get first success.)
        break
    fi
done

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/openssl-${VERSION}"
echo "Done."
