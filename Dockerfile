FROM debian:stable-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ make cmake ninja-build pkg-config \
        gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
        git curl ca-certificates file python3 python3-dev python3-setuptools \
        swig \
        bc bison flex libssl-dev libelf-dev device-tree-compiler u-boot-tools \
        libusb-1.0-0-dev xxd libgnutls28-dev libfdt-dev \
        qemu-user \
        libsdl2-dev \
        cpio rsync xz-utils bzip2 e2fsprogs dosfstools mtools util-linux fdisk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
