#!/usr/bin/env bash
# Canonical FEL-only boot for the PocketBook PB626 / Touch Lux 3.
#
# Runs on the host (needs USB access to the device in FEL mode):
#   1. verifies the device in FEL mode is an Allwinner A13 (SoC id 0x1625)
#   2. boots U-Boot via sunxi-fel (console on UART1, PG3/PG4, 115200 8N1)
#   3. U-Boot automatically waits in DFU mode (bootcmd: "dfu 0 ram 0")
#   4. pushes the FIT image (kernel+DTB+initramfs) to RAM via USB DFU
#   5. detaches DFU; U-Boot boots the FIT; Linux gives a UART shell
#
# Nothing is written to the device's storage (internal or external
# microSD); the boot is entirely RAM-resident.
#
# Usage: scripts/fel-boot.sh [--uart /dev/ttyUSB0]
#
# UART: pass --uart DEV to capture the console into build/log/uart.log
# (read-only observation; the shell stays interactive on your terminal).
#
# Requirements: sunxi-fel and dfu-util in build/host-tools/ (produced by
# scripts/build.sh) or in PATH. Both need libusb-1.0 at runtime.
#
# Do NOT run with dfu-util's -R flag anywhere: with U-Boot, a bus reset
# after DFU detach makes U-Boot reset the whole board and the downloaded
# image is lost.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ART="$REPO_ROOT/build/artifacts"
HOST_TOOLS="$REPO_ROOT/build/host-tools"
LOG="$REPO_ROOT/build/log"
UART_DEV=""
UBOOT="${UBOOT:-u-boot-sunxi-with-spl.bin}"
FIT="${FIT:-boot.itb}"
DFU_ALT="boot"
# Canonical RAM addresses (single source of truth: config/ram-map.sh;
# verified against config/fit.its and the default env by
# scripts/check-phase0.sh on every build).
# shellcheck source=../config/ram-map.sh
. "$REPO_ROOT/config/ram-map.sh"
# U-Boot's sunxi download gadget enumerates as 1f3a:1010 (the
# CONFIG_USB_GADGET_VENDOR_NUM / CONFIG_USB_GADGET_PRODUCT_NUM defaults
# for ARCH_SUNXI); the FEL device itself is 1f3a:efe8 and has no DFU
# interface, so detection goes through dfu-util's own DFU probe (see
# dfu_matches below: VID:PID plus the exact alt setting/name).
DFU_VIDPID="1f3a:1010"
DFU_WAIT_S=15

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --uart) UART_DEV="${2:?device required}"; shift 2 ;;
        --uart=*) UART_DEV="${1#*=}"; shift ;;
        *) die "unknown argument: $1 (usage: fel-boot.sh [--uart DEV])" ;;
    esac
done

find_tool() {
    local name="$1"
    if [ -x "$HOST_TOOLS/$name" ]; then
        echo "$HOST_TOOLS/$name"
    elif command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
    else
        die "$name not found; run scripts/build.sh first (or install $name)"
    fi
}
FEL="$(find_tool sunxi-fel)"
DFU_UTIL="$(find_tool dfu-util)"

say "Checking artifacts ($ART)"
[ -f "$ART/$UBOOT" ] || die "$ART/$UBOOT missing; run scripts/build.sh"
[ -f "$ART/$FIT" ] || die "$ART/$FIT missing; run scripts/build.sh"
(cd "$ART" && sha256sum -c SHA256SUMS) \
    || die "artifact checksum mismatch; rebuild with scripts/build.sh"

say "Verifying FEL device (plug the PB626 in FEL mode: hold the Menu button)"
FEL_VER="$("$FEL" ver)" || die "no FEL device found (usb mode? permissions? see docs/phase0-uat.md)"
echo "$FEL_VER"
echo "$FEL_VER" | grep -q 'soc=00001625' \
    || die "FEL device reports the wrong SoC id (expected 0x1625 = A13); refusing to continue"
echo "$FEL_VER" | grep -qF '(A13)' \
    || die "FEL device is not an A13 (PB626 expected)"

# Start UART capture before U-Boot runs so the SPL output is logged too.
UART_PID=""
if [ -n "$UART_DEV" ]; then
    [ -w "$UART_DEV" ] || die "cannot write $UART_DEV (permissions? sudo needed?)"
    mkdir -p "$LOG"
    : > "$LOG/uart.log"
    stty -F "$UART_DEV" 115200 cs8 -cstopb -parenb -echo raw
    cat "$UART_DEV" | tee "$LOG/uart.log" &
    UART_PID=$!
    trap '[ -n "$UART_PID" ] && kill "$UART_PID" 2>/dev/null' EXIT
    sleep 1
    say "UART capture running: $LOG/uart.log"
fi

say "Booting U-Boot via FEL"
"$FEL" uboot "$ART/$UBOOT"

# The expected U-Boot download gadget, and nothing else: VID:PID
# 1f3a:1010 (CONFIG_USB_GADGET_VENDOR_NUM / CONFIG_USB_GADGET_PRODUCT_NUM
# defaults for ARCH_SUNXI) with alt setting 0 named exactly "boot" (from
# dfu_alt_info). The FEL device itself (1f3a:efe8) has no DFU interface
# and never matches; anything else or ambiguous fails closed.
dfu_matches() {
    "$DFU_UTIL" -l 2>/dev/null \
        | grep -E "Found DFU: \[$DFU_VIDPID\].*alt=0, name=\"$DFU_ALT\""
}

say "Waiting for the U-Boot DFU gadget (USB $DFU_VIDPID, alt 0 \"$DFU_ALT\")"
found=no
for _ in $(seq 1 "$DFU_WAIT_S"); do
    if dfu_matches | grep -q . ; then
        found=yes; break
    fi
    sleep 1
done
[ "$found" = yes ] || die "U-Boot DFU gadget ($DFU_VIDPID, alt 0 \"$DFU_ALT\") did not appear in $DFU_WAIT_S s.
If you see a U-Boot prompt on the UART instead, use the manual fallback:
  loadx $FIT_ADDR    (then: sx -k $ART/$FIT < /dev/ttyUSB0 > /dev/ttyUSB0)
  iminfo $FIT_ADDR && bootm $FIT_ADDR"
n="$(dfu_matches | grep -c . || true)"
[ "$n" -eq 1 ] || die "ambiguous DFU state: $n matching $DFU_VIDPID alt \"$DFU_ALT\" gadget(s); refusing to proceed"

say "Downloading $FIT over USB DFU (alt: $DFU_ALT) to RAM $FIT_ADDR"
"$DFU_UTIL" -a "$DFU_ALT" -D "$ART/$FIT"

say "Detaching DFU (U-Boot will now boot the FIT)"
"$DFU_UTIL" -a "$DFU_ALT" -e

say "Kernel booting; shell prompt appears on the UART (115200 8N1)."
if [ -n "$UART_PID" ]; then
    echo "Log: $LOG/uart.log (Ctrl-C stops the capture)"
    wait "$UART_PID" 2>/dev/null || true
fi
echo "When done: power-cycle the PB626; the original PocketBook system boots unchanged."
