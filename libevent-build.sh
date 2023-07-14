#!/bin/bash
set -u
 
# Setup architectures, library name and other vars + cleanup from previous runs
ARCHS=("arm64" "arm64e" "x86_64")
SDKS=("iphoneos" "iphoneos" "iphonesimulator")
# ARCHS=("x86_64")
# SDKS=("iphonesimulator")
LIB_NAME="libevent-2.1.12-stable"

TEMP_DIR="$(pwd)/tmp"
TEMP_LIB_PATH="$(pwd)/tmp/${LIB_NAME}"

# !!! User configuration required: point this at the directory the openssl headers and libs are to be found
DEPENDENCIES_DIR="$(pwd)/openssl"
DEPENDENCIES_DIR_LIB="${DEPENDENCIES_DIR}/lib"
DEPENDENCIES_DIR_HEAD="${DEPENDENCIES_DIR}/include"

PLATFORM_DEPENDENCIES_DIR="${DEPENDENCIES_DIR}/platform"

LIB_DEST_DIR="$(pwd)/libevent-dest-lib"
HEADER_DEST_DIR="$(pwd)/libevent-dest-include"

PLATFORM_LIBS=("libz.tbd") # Platform specific lib files to be copied for the build 
PLATFORM_HEADERS=("zlib.h") # Platform specific header files to be copied for the build

rm -rf "${TEMP_LIB_PATH}*" "${LIB_NAME}"
 

###########################################################################
# Unarchive library, then configure and make for specified architectures

# Copy platform dependency libs and headers
copy_platform_dependencies()
{
   echo "copy_platform_dependencies"  $1 $2
   ARCH=$1; SDK_PATH=$2;

   PLATFORM_DEPENDENCIES_DIR_H="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/include"
   PLATFORM_DEPENDENCIES_DIR_LIB="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/lib"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_H}"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_LIB}"
   
   for PLIB in "${PLATFORM_LIBS[@]}"; do
      echo "cp" "${SDK_PATH}/usr/lib/$PLIB" "${PLATFORM_DEPENDENCIES_DIR_LIB}"
      cp "${SDK_PATH}/usr/lib/$PLIB" "${PLATFORM_DEPENDENCIES_DIR_LIB}"
   done
   
   for PHEAD in "${PLATFORM_HEADERS[@]}"; do
      echo "cp" "${SDK_PATH}/usr/include/$PHEAD" "${PLATFORM_DEPENDENCIES_DIR_H}"   
      cp "${SDK_PATH}/usr/include/$PHEAD" "${PLATFORM_DEPENDENCIES_DIR_H}"   
   done
}

# Unarchive, setup temp folder and run ./configure, 'make' and 'make install'
configure_make()
{
   echo "configure_make" $1  $2 $3
   ARCH=$1; GCC=$2; SDK_PATH=$3;
   LOG_FILE_CONFIG="${TEMP_LIB_PATH}-${ARCH}-config.log"
   LOG_FILE_MAKE="${TEMP_LIB_PATH}-${ARCH}-make.log"
   LOG_FILE_INSTALL="${TEMP_LIB_PATH}-${ARCH}-install.log"
   tar xfz "${LIB_NAME}.tar.gz";
   pushd .; cd "${LIB_NAME}";
   
   copy_platform_dependencies "${ARCH}" "${SDK_PATH}"

   # Configure and make

   if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ];
   then
      HOST_FLAG="--host=${ARCH}-apple-darwin"
   else
      HOST_FLAG="--host=arm-apple-darwin11"
   fi

   echo "HOST_FLAG " $HOST_FLAG

   mkdir -p "${TEMP_LIB_PATH}-${ARCH}"

   export LDFLAGS="-L/Users/longzl/code/git/libevent-build/openssl -L/Users/longzl/code/git/libevent-build/openssl/lib"
   export CFLAGS="-I/Users/longzl/code/git/libevent-build/openssl/include/ -I/Users/longzl/code/git/libevent-build/openssl/include/openssl"
   export CPPFLAGS="-I/Users/longzl/code/git/libevent-build/openssl/include/ -I/Users/longzl/code/git/libevent-build/openssl/include/openssl"
   export OPENSSL_HOME="/Users/longzl/code/git/libevent-build/openssl-1.1.1t-build/arm64"
   export PATH="${OPENSSL_HOME}:$PATH"

   set -x
   ./configure --disable-shared --enable-static --disable-debug-mode ${HOST_FLAG}  \
   --prefix="${TEMP_LIB_PATH}-${ARCH}" \
   CC="${GCC}" \
   LDFLAGS=" -L${DEPENDENCIES_DIR_LIB}" \
   CFLAGS=" -arch ${ARCH} -I${DEPENDENCIES_DIR_HEAD} -isysroot ${SDK_PATH}" \
   CPPFLAGS=" -arch ${ARCH} -I${DEPENDENCIES_DIR_HEAD} -isysroot ${SDK_PATH}" &> "${LOG_FILE_CONFIG}"
   
   make -j$(sysctl hw.ncpu | awk '{print $2}') &> "${LOG_FILE_MAKE}"; 
   make install &> "${LOG_FILE_INSTALL}";
   set +x
   popd;
   rm -rf "${LIB_NAME}";
}
for ((i=0; i < ${#ARCHS[@]}; i++)); 
do
   SDK_PATH=$(xcrun -sdk ${SDKS[i]} --show-sdk-path)
   GCC=$(xcrun -sdk ${SDKS[i]} -find gcc)
   configure_make "${ARCHS[i]}" "${GCC}" "${SDK_PATH}"
done

# Combine libraries for different architectures into one
# Use .a files from the temp directory by providing relative paths
mkdir -p "${LIB_DEST_DIR}"
create_lib()
{
   LIB_SRC=$1; LIB_DST=$2;
   LIB_PATHS=( "${ARCHS[@]/#/${TEMP_LIB_PATH}-}" )
   LIB_PATHS=( "${LIB_PATHS[@]/%//${LIB_SRC}}" )
   lipo ${LIB_PATHS[@]} -create -output "${LIB_DST}"
}
LIBS=("libevent.a" "libevent_core.a" "libevent_extra.a" "libevent_openssl.a" "libevent_pthreads.a")
for DEST_LIB in "${LIBS[@]}";
do
   create_lib "lib/${DEST_LIB}" "${LIB_DEST_DIR}/${DEST_LIB}"
done
 
# Copy header files + final cleanups
mkdir -p "${HEADER_DEST_DIR}"
cp -R "${TEMP_LIB_PATH}-${ARCHS[0]}/include" "${HEADER_DEST_DIR}"
# rm -rf "${TEMP_DIR}"
