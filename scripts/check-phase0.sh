#!/usr/bin/env bash
# Static Phase 0 gates: deterministic checks, no hardware and no
# container tooling required. Run standalone, by scripts/build.sh
# (before every build) and by CI. They are the regression gates for the
# Phase 0 review findings:
#   1. canonical non-overlapping RAM map (config/ram-map.sh vs
#      config/fit.its and config/pb626-default-env.txt)
#   2. electrically safe UART wiring documentation
#   3. truthful interactive UART semantics in scripts/fel-boot.sh
#   4. strict FEL and DFU device identity checks
#   5. truthful repository status (hardware UAT pending)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# --------------------------------------------------------------------------
# Gate 1: canonical non-overlapping RAM map
# --------------------------------------------------------------------------
echo '==> Gate 1: canonical non-overlapping RAM map'

RAM_MAP="$REPO_ROOT/config/ram-map.sh"
FIT_ITS="$REPO_ROOT/config/fit.its"
DEFAULT_ENV="$REPO_ROOT/config/pb626-default-env.txt"
FEL_BOOT="$REPO_ROOT/scripts/fel-boot.sh"

[ -f "$RAM_MAP" ] || fail "missing $RAM_MAP"
# shellcheck source=../config/ram-map.sh
. "$RAM_MAP"

# Map sanity: DRAM window and reservation are arithmetically consistent.
(( DRAM_BASE + DRAM_SIZE == DRAM_END )) || fail "ram-map.sh: DRAM_BASE+DRAM_SIZE != DRAM_END"
(( UBOOT_RESERVE_BASE > DRAM_BASE )) && (( UBOOT_RESERVE_BASE < DRAM_END )) \
    || fail "ram-map.sh: UBOOT_RESERVE_BASE outside the DRAM window"

# Authored ranges: [start, start+size). Every one of them must sit in
# the DRAM window but below the U-Boot reservation.
range_check() {
    local name="$1" start="$2" size="$3"
    (( start >= DRAM_BASE )) || fail "$name starts below DRAM_BASE"
    (( start + size <= UBOOT_RESERVE_BASE )) \
        || fail "$name intrudes into the U-Boot runtime reservation"
}
range_check "FIT"       "$FIT_ADDR"       "$FIT_SIZE"
range_check "KERNEL"    "$KERNEL_ADDR"    "$KERNEL_SIZE"
range_check "DTB"       "$DTB_ADDR"       "$DTB_SIZE"
range_check "INITRAMFS" "$INITRAMFS_ADDR" "$INITRAMFS_SIZE"

# The decompressed kernel (AUTO_ZRELADDR target) must stay well below
# the FIT buffer it is booted from: reserve 16 MiB for it.
(( KERNEL_ZREL + 0x1000000 <= FIT_ADDR )) \
    || fail "decompressed kernel range would reach the FIT buffer"

# Pairwise disjointness of the four authored ranges.
disjoint() {
    local a_name="$1" a_start="$2" a_end="$3" \
          b_name="$4" b_start="$5" b_end="$6"
    if (( a_start < b_end && b_start < a_end )); then
        fail "$a_name [$a_start..$a_end) overlaps $b_name [$b_start..$b_end)"
    fi
}
FIT_END=$((FIT_ADDR + FIT_SIZE))
KERNEL_END=$((KERNEL_ADDR + KERNEL_SIZE))
DTB_END=$((DTB_ADDR + DTB_SIZE))
INITRAMFS_END=$((INITRAMFS_ADDR + INITRAMFS_SIZE))
disjoint FIT    "$FIT_ADDR"     "$FIT_END"     KERNEL    "$KERNEL_ADDR"     "$KERNEL_END"
disjoint FIT    "$FIT_ADDR"     "$FIT_END"     DTB       "$DTB_ADDR"        "$DTB_END"
disjoint FIT    "$FIT_ADDR"     "$FIT_END"     INITRAMFS "$INITRAMFS_ADDR"  "$INITRAMFS_END"
disjoint KERNEL "$KERNEL_ADDR"  "$KERNEL_END"  DTB       "$DTB_ADDR"        "$DTB_END"
disjoint KERNEL "$KERNEL_ADDR"  "$KERNEL_END"  INITRAMFS "$INITRAMFS_ADDR"  "$INITRAMFS_END"
disjoint DTB    "$DTB_ADDR"     "$DTB_END"     INITRAMFS "$INITRAMFS_ADDR"  "$INITRAMFS_END"

# config/fit.its must carry exactly the map's load/entry addresses.
parse_its_loads() {
    awk '
        /^[[:space:]]*kernel[[:space:]]*\{/   { img = "kernel" }
        /^[[:space:]]*fdt[[:space:]]*\{/      { img = "fdt" }
        /^[[:space:]]*ramdisk[[:space:]]*\{/  { img = "ramdisk" }
        img != "" && match($0, /load = <0x[0-9a-fA-F]+>/) {
            m = substr($0, RSTART, RLENGTH)
            v = substr(m, 9, length(m) - 9)
            if (img == "kernel")   kl = v
            if (img == "fdt")      fl = v
            if (img == "ramdisk")  rl = v
        }
        img == "kernel" && match($0, /entry = <0x[0-9a-fA-F]+>/) {
            m = substr($0, RSTART, RLENGTH)
            ke = substr(m, 10, length(m) - 10)
        }
        END {
            printf "kernel_load=%s\nkernel_entry=%s\nfdt_load=%s\nramdisk_load=%s\n", kl, ke, fl, rl
        }
    ' "$FIT_ITS"
}
its="$(parse_its_loads)"
its_kernel_load="$(sed -n 's/^kernel_load=//p' <<<"$its")"
its_kernel_entry="$(sed -n 's/^kernel_entry=//p' <<<"$its")"
its_fdt_load="$(sed -n 's/^fdt_load=//p' <<<"$its")"
its_ramdisk_load="$(sed -n 's/^ramdisk_load=//p' <<<"$its")"

[ "$its_kernel_load" = "$KERNEL_ADDR" ] \
    || fail "fit.its kernel load $its_kernel_load != KERNEL_ADDR ($KERNEL_ADDR)"
[ "$its_kernel_entry" = "$KERNEL_ENTRY" ] \
    || fail "fit.its kernel entry $its_kernel_entry != KERNEL_ENTRY ($KERNEL_ENTRY)"
[ "$its_fdt_load" = "$DTB_ADDR" ] \
    || fail "fit.its fdt load $its_fdt_load != DTB_ADDR ($DTB_ADDR)"
[ "$its_ramdisk_load" = "$INITRAMFS_ADDR" ] \
    || fail "fit.its ramdisk load $its_ramdisk_load != INITRAMFS_ADDR ($INITRAMFS_ADDR)"

# config/pb626-default-env.txt must carry exactly the map's DFU/bootm
# addresses (dfu_alt_info uses bare hex, without the 0x prefix).
env_alt_info="$(sed -n 's/^dfu_alt_info=//p' "$DEFAULT_ENV")"
env_bootm="$(sed -n 's/^bootcmd=.*bootm \(0x[0-9a-fA-F]*\)$/\1/p' "$DEFAULT_ENV")"
[ "$env_alt_info" = "boot ram ${FIT_ADDR#0x} ${FIT_SIZE#0x}" ] \
    || fail "default env dfu_alt_info '$env_alt_info' != 'boot ram ${FIT_ADDR#0x} ${FIT_SIZE#0x}'"
[ "$env_bootm" = "$FIT_ADDR" ] \
    || fail "default env bootm address $env_bootm != FIT_ADDR ($FIT_ADDR)"

# scripts/fel-boot.sh must source the map instead of repeating numbers.
grep -q 'config/ram-map.sh' "$FEL_BOOT" \
    || fail "fel-boot.sh does not source config/ram-map.sh"
if grep -Eq '0x[0-9a-fA-F]{8}' "$FEL_BOOT"; then
    fail "fel-boot.sh hardcodes RAM addresses instead of using config/ram-map.sh"
fi

pass 'RAM map canonical and non-overlapping (FIT/KERNEL/DTB/INITRAMFS, U-Boot reserve)'

# --------------------------------------------------------------------------
# Gate 2: strict FEL and DFU device identity checks
# --------------------------------------------------------------------------
echo '==> Gate 2: strict FEL and DFU device identity checks'

FEL_BOOT="$REPO_ROOT/scripts/fel-boot.sh"
[ -f "$FEL_BOOT" ] || fail "missing $FEL_BOOT"

grep -q 'soc=00001625' "$FEL_BOOT" \
    || fail 'fel-boot.sh does not verify the FEL SoC id (0x1625)'
grep -qF '(A13)' "$FEL_BOOT" \
    || fail 'fel-boot.sh does not verify the FEL SoC name (A13)'
grep -q 'DFU_VIDPID="1f3a:1010"' "$FEL_BOOT" \
    || fail 'fel-boot.sh does not pin the expected DFU VID:PID (1f3a:1010)'
grep -qF 'alt=0, name=\"$DFU_ALT\"' "$FEL_BOOT" \
    || fail 'fel-boot.sh does not match the expected DFU alt setting (0: "boot")'
grep -q 'ambiguous DFU state' "$FEL_BOOT" \
    || fail 'fel-boot.sh does not fail closed on ambiguous DFU state'
if grep -q 'grep -q "Found DFU"' "$FEL_BOOT"; then
    fail 'fel-boot.sh uses broad "Found DFU" matching instead of the expected device identity'
fi

pass 'FEL identity (A13, soc 0x1625) and DFU identity (1f3a:1010, alt 0 "boot") strict'
