# PocketBook PB626

This project explores and builds a modern Linux-based software stack for the
PocketBook Touch Lux 3 (PB626).

Target hardware:

- PocketBook Touch Lux 3 / PB626
- Allwinner A13 SoC
- ARMv7, hard-float

## Current status

At this stage the repository contains only a reproducible build environment:
a Docker image with the project toolchain, environment smoke tests, and CI.
There is no kernel, U-Boot, rootfs, UI, emulator, or hardware support work
yet.

The image is a project toolchain image. Agent/orchestrator tooling is
intentionally not included.

## Build environment

`Dockerfile` (Debian stable, slim variant) provides:

- native toolchain: gcc/g++, make, CMake, Ninja, pkg-config;
- ARM hard-float cross toolchain: `arm-linux-gnueabihf` gcc/g++/binutils;
- general tools: git, curl, ca-certificates, file, Python 3;
- kernel/U-Boot build dependencies: bc, bison, flex, OpenSSL and libelf
  headers, device-tree-compiler, u-boot-tools;
- QEMU user-mode (`qemu-arm`) for running ARM binaries;
- SDL2 development headers, reserved for a future simulated UI backend;
- image/rootfs utilities: cpio, rsync, xz, e2fsprogs, dosfstools, mtools,
  util-linux.

### Build the image

```sh
docker build -t pb626-build-env .
```

### Run the environment smoke tests

```sh
docker run --rm -v "$PWD":/workspace pb626-build-env \
    /workspace/scripts/test-build-env.sh
```

The tests compile and run native and ARM hard-float binaries (the ARM binary
under `qemu-arm` with the cross sysroot), compile a device tree to a DTB,
run `mkimage`, build a small project with CMake + Ninja, and build/run an
SDL2 program using the dummy video driver. Temporary files live in `mktemp`
directories and are cleaned up afterwards.

### Use the environment interactively

```sh
docker run --rm -it -v "$PWD":/workspace pb626-build-env bash
```

CI (`.github/workflows/ci.yml`) builds the image from this repository and
runs the same smoke tests inside it on every push and pull request.
