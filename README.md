# PocketBook PB626

This project explores and builds a modern Linux-based software stack for the
PocketBook Touch Lux 3 (PB626).

Target hardware:

- PocketBook Touch Lux 3 / PB626
- Allwinner A13 SoC
- ARMv7, hard-float

## Current status

- **Build and static verification: complete.** The toolchain image, the
  canonical build path and the Phase 0 boot bundle are reproducible and
  pass the static gates (`scripts/check-phase0.sh`,
  `scripts/test-build-env.sh`).
- **Real-device UAT: pending.** No hardware acceptance run has been
  performed yet; nothing here claims the PB626 boots on real hardware
  until the deterministic procedure in `docs/phase0-uat.md` has passed
  on the device.

At this stage the repository contains a reproducible build environment
plus the **Phase 0 FEL-only boot bundle**: it is designed to bring the
PB626 up over USB FEL into a mainline Linux (6.12 LTS) with an
interactive UART shell — no storage of the device is touched — and the
pending UAT is the step that establishes this on the real device.

## Phase 0 — FEL-only boot

Boot chain (one canonical path):

    FEL (hold Menu button)
      -> sunxi-fel uboot (SPL + U-Boot, console on UART1 PG3/PG4 @ 115200)
      -> U-Boot waits in USB DFU mode (bootcmd: dfu 0 ram 0)
      -> dfu-util pushes boot.itb (kernel + PB626 DTB + initramfs) to RAM
      -> U-Boot boots the FIT -> Linux -> BusyBox UART shell

Build (inside the toolchain container):

```sh
docker build -t pb626-build-env .
docker run --rm -v "$PWD":/workspace pb626-build-env \
    /workspace/scripts/build.sh
```

Boot (on the host, with the device in FEL mode; `--uart` opens an
interactive `picocom` console on the given device and logs the session
to `build/log/uart.log`; wiring per `docs/phase0-uat.md` section 0 —
never connect the board's VCC pad to the adapter):

```sh
./scripts/fel-boot.sh --uart /dev/ttyUSB0
```

Artifacts land in `build/artifacts/` with `SHA256SUMS`; host tools
(`sunxi-fel`, `dfu-util`) are built from pinned sources into
`build/host-tools/`. See `docs/phase0-investigation.md` (research record,
pinned versions) and `docs/phase0-uat.md` (acceptance test). No patches to
upstream sources are required (see `patches/README.md`); the board specifics
live in `config/`. Static gates (`scripts/check-phase0.sh`: canonical
non-overlapping RAM map, strict FEL/DFU device identity, electrically safe
UART documentation, truthful status) run before every build and in CI.

## Build environment

`Dockerfile` (Debian stable, slim variant) provides:

- native toolchain: gcc/g++, make, CMake, Ninja, pkg-config;
- ARM hard-float cross toolchain: `arm-linux-gnueabihf` gcc/g++/binutils;
- general tools: git, curl, ca-certificates, file, Python 3;
- kernel/U-Boot build dependencies: bc, bison, flex, OpenSSL and libelf
  headers, device-tree-compiler, u-boot-tools, libusb-1.0 (for the
  `sunxi-fel`/`dfu-util` host tools);
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
