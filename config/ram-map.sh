# Canonical RAM map for the PB626 Phase 0 FEL-only boot (A13, 256 MiB).
#
# This file is the single source of truth for every RAM address used by
# the boot chain. scripts/build.sh, scripts/fel-boot.sh and
# scripts/check-phase0.sh source it; config/fit.its and
# config/pb626-default-env.txt carry the same values as literals and are
# checked against this file by scripts/check-phase0.sh on every build.
# Do not hardcode these numbers anywhere else.
#
# DRAM window (auto-detected by the SPL DRAM init): 256 MiB at
# 0x40000000..0x50000000. The top 32 MiB are reserved for relocated
# U-Boot (code, heap, stacks) and for bootm's own relocations of the
# fdt and the ramdisk near the top of memory; nothing we author is
# placed there.
#
#    0x40000000..0x40008000    kernel decompression work area / page tables
#    0x40008000..~0x40e00000   decompressed kernel (AUTO_ZRELADDR target,
#                              derived from KERNEL_ADDR; <16 MiB)
#    FIT_ADDR..+FIT_SIZE       FIT download buffer (USB DFU destination,
#                              bootm input blob; ~6.7 MiB of it used)
#    KERNEL_ADDR..+KERNEL_SIZE zImage load/entry (copied out of the FIT
#                              buffer by bootm; decompresses to
#                              KERNEL_ZREL and never overlaps the blob)
#    DTB_ADDR..+DTB_SIZE       device tree blob load address
#    INITRAMFS_ADDR..+INITRAMFS_SIZE  initramfs load address
#    UBOOT_RESERVE_BASE..DRAM_END  reserved for U-Boot runtime + bootm
#                              fdt/ramdisk relocations (do not use)
#
# All ranges are disjoint; scripts/check-phase0.sh verifies this on
# every build and fails the build otherwise.

DRAM_BASE=0x40000000
DRAM_SIZE=0x10000000
DRAM_END=0x50000000

# USB DFU download destination of the whole FIT image (dfu_alt_info
# "boot ram <FIT_ADDR> <FIT_SIZE>"); bootm also parses the FIT here.
FIT_ADDR=0x42000000
FIT_SIZE=0x2000000

# Linux zImage: copied here by bootm from the FIT blob at FIT_ADDR,
# self-decompresses to KERNEL_ZREL (CONFIG_AUTO_ZRELADDR).
KERNEL_ADDR=0x44000000
KERNEL_SIZE=0x800000
KERNEL_ENTRY="$KERNEL_ADDR"
KERNEL_ZREL=0x40008000

# Device tree blob (bootm may relocate it into the U-Boot reserve).
DTB_ADDR=0x44800000
DTB_SIZE=0x100000

# Phase 0 initramfs (bootm may relocate it into the U-Boot reserve).
INITRAMFS_ADDR=0x45000000
INITRAMFS_SIZE=0x1000000

# U-Boot runtime reservation (top of DRAM): relocated U-Boot, heap,
# stacks, and the bootm-relocated fdt/ramdisk live here.
UBOOT_RESERVE_BASE=0x4E000000
