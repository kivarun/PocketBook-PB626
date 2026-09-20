FROM debian:stable-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ make cmake ninja-build pkg-config \
        gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
        git curl ca-certificates file python3 \
        bc bison flex libssl-dev libelf-dev device-tree-compiler u-boot-tools \
        qemu-user \
        libsdl2-dev \
        cpio rsync xz-utils e2fsprogs dosfstools mtools util-linux fdisk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
