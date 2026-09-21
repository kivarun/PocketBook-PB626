#!/usr/bin/env bash
# Canonical build for the PocketBook PB626 Phase 0 FEL-only boot bundle.
#
# Runs inside the pb626-build-env container:
#   docker build -t pb626-build-env .
#   docker run --rm -v "$PWD":/workspace pb626-build-env \
#       /workspace/scripts/build.sh
#
# Produces one artifact set in build/artifacts/:
#   u-boot-sunxi-with-spl.bin                 FEL stage (SPL + U-Boot)
#   zImage, sun5i-a13-pocketbook-touch-lux-3.dtb, initramfs.cpio.gz
#   boot.itb                                  single canonical FIT boot image
#   SHA256SUMS
# and host-side boot tools in build/host-tools/ (sunxi-fel, dfu-util).
#
# All sources are pinned; see docs/phase0-investigation.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/build/src"
OUT="$REPO_ROOT/build/artifacts"
HOST_TOOLS="$REPO_ROOT/build/host-tools"
INITRAMFS_ROOT="$REPO_ROOT/build/initramfs/root"
LOGDIR="$REPO_ROOT/build/log"

# --------------------------------------------------------------------------
# Pinned sources (verified before every build)
# --------------------------------------------------------------------------
UBOOT_TAG="v2026.07"
UBOOT_COMMIT="ece349ade2973e220f524ce59e59711cc919263f"
LINUX_VERSION="6.12.110"
SUNXI_TOOLS_COMMIT="d7bbd172a5da601a08f94479de308c6fb714a19a"
DFU_UTIL_VERSION="0.11"
DFU_UTIL_SHA256="b4b53ba21a82ef7e3d4c47df2952adf5fa494f499b6b0b57c58c5d04ae8ff19e"
BUSYBOX_VERSION="1.36.1"
BUSYBOX_SHA256="b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314"

CROSS=arm-linux-gnueabihf-
JOBS="$(nproc)"
DTB_NAME="sun5i-a13-pocketbook-touch-lux-3.dtb"

# Fixed build timestamp so that repeated builds of the same pinned sources
# produce identical artifacts (kernel, U-Boot and mkimage honour this).
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-946684800}"
# Kernel: keep the embedded build user/host stable across hosts/containers.
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-builder}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-pb626-build-env}"

say() { printf '\n==> %s\n' "$*"; }

verify_pins() {
    say "Verifying pinned sources"
    local rev
    rev="$(git -C "$SRC/u-boot" rev-parse HEAD)"
    [ "$rev" = "$UBOOT_COMMIT" ] \
        || { echo "u-boot commit mismatch: $rev" >&2; exit 1; }

    rev="$(git -C "$SRC/sunxi-tools" rev-parse HEAD)"
    [ "$rev" = "$SUNXI_TOOLS_COMMIT" ] \
        || { echo "sunxi-tools commit mismatch: $rev" >&2; exit 1; }

    echo "$BUSYBOX_SHA256  $SRC/busybox-$BUSYBOX_VERSION.tar.bz2" | sha256sum -c - || exit 1
    echo "$DFU_UTIL_SHA256  $SRC/dfu-util-$DFU_UTIL_VERSION.tar.gz" | sha256sum -c - || exit 1

    local ver
    ver="$(make -C "$SRC/linux" -s kernelversion 2>/dev/null || true)"
    [ "$ver" = "$LINUX_VERSION" ] \
        || { echo "linux version mismatch: '$ver'" >&2; exit 1; }
    say "pins OK: u-boot $UBOOT_TAG, linux $LINUX_VERSION, busybox $BUSYBOX_VERSION, dfu-util $DFU_UTIL_VERSION"
}

build_uboot() {
    say "Building U-Boot $UBOOT_TAG"
    cd "$SRC/u-boot"
    cp "$REPO_ROOT/config/uboot-pb626-fel_defconfig" configs/pb626_fel_defconfig
    cp "$REPO_ROOT/config/pb626-default-env.txt" pb626-default-env.txt
    make O=out CROSS_COMPILE="$CROSS" pb626_fel_defconfig
    make O=out CROSS_COMPILE="$CROSS" -j"$JOBS"
    cp out/u-boot-sunxi-with-spl.bin "$OUT/"
}

build_linux() {
    say "Building Linux $LINUX_VERSION"
    cd "$SRC/linux"
    make O=out ARCH=arm CROSS_COMPILE="$CROSS" sunxi_defconfig
    KCONFIG_CONFIG=out/.config ./scripts/kconfig/merge_config.sh -m \
        out/.config "$REPO_ROOT/config/linux-pb626-fel.config"
    make O=out ARCH=arm CROSS_COMPILE="$CROSS" olddefconfig
    make O=out -j"$JOBS" ARCH=arm CROSS_COMPILE="$CROSS" zImage \
        "allwinner/$DTB_NAME"
    cp out/arch/arm/boot/zImage "$OUT/"
    cp "out/arch/arm/boot/dts/allwinner/$DTB_NAME" "$OUT/"
}

build_busybox() {
    say "Building BusyBox $BUSYBOX_VERSION (static)"
    cd "$SRC"
    rm -rf busybox-$BUSYBOX_VERSION
    tar -xjf busybox-$BUSYBOX_VERSION.tar.bz2
    cd busybox-$BUSYBOX_VERSION
    make -j"$JOBS" defconfig
    # Apply the fragment (busybox has no kconfig merge helper): lines may
    # be "CONFIG_X=y" (enable) or "# CONFIG_X is not set" (disable).
    while read -r line; do
        case "$line" in
            '# CONFIG_'*' is not set')
                sym="$(echo "$line" | sed -n 's/^# CONFIG_\([^ ]*\) is not set$/\1/p')"
                sed -i -e "s|^CONFIG_$sym=.*$|# CONFIG_$sym is not set|" .config
                ;;
            'CONFIG_'*)
                sym="${line#CONFIG_}"
                sym="${sym%=y}"
                sed -i -e "s|^# CONFIG_$sym is not set$|CONFIG_$sym=y|" .config
                ;;
        esac
    done < "$REPO_ROOT/config/busybox-pb626.config"
    make -j"$JOBS" CROSS_COMPILE="$CROSS"
    file -b busybox | grep -q 'ELF 32-bit.*ARM' || { echo "busybox not ARM" >&2; exit 1; }
}

build_initramfs() {
    say "Assembling initramfs"
    rm -rf "$INITRAMFS_ROOT"
    install -d -m 0755 \
        "$INITRAMFS_ROOT"/{bin,sbin,etc,proc,sys,dev,run,tmp,root}
    install -m 0755 "$SRC/busybox-$BUSYBOX_VERSION/busybox" "$INITRAMFS_ROOT/bin/busybox"
    ln -sf busybox "$INITRAMFS_ROOT/bin/sh"
    install -m 0755 "$REPO_ROOT/config/initramfs/init" "$INITRAMFS_ROOT/init"

    cd "$INITRAMFS_ROOT"
    # Normalise timestamps for a reproducible archive.
    find . -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
    find . -print0 | cpio --null -o -H newc --owner 0:0 --reproducible \
        | gzip -9 > "$OUT/initramfs.cpio.gz"
}

build_fit() {
    say "Building FIT image boot.itb"
    cd "$REPO_ROOT"
    rm -f "$OUT/boot.itb"
    mkimage -f config/fit.its "$OUT/boot.itb"
    mkimage -l "$OUT/boot.itb"
}

build_host_tools() {
    say "Building host tools (sunxi-fel, dfu-util)"
    mkdir -p "$HOST_TOOLS"
    cd "$SRC/sunxi-tools"
    make -j"$JOBS" sunxi-fel
    cp sunxi-fel "$HOST_TOOLS/"

    cd "$SRC"
    rm -rf dfu-util-$DFU_UTIL_VERSION
    tar -xzf dfu-util-$DFU_UTIL_VERSION.tar.gz
    cd dfu-util-$DFU_UTIL_VERSION
    ./configure >/dev/null
    make -j"$JOBS"
    cp src/dfu-util "$HOST_TOOLS/"
}

record_metadata() {
    say "Recording metadata"
    mkdir -p "$LOGDIR"
    {
        echo "# Phase 0 build metadata"
        echo "date:            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "u-boot:          $UBOOT_TAG ($UBOOT_COMMIT)"
        echo "linux:           $LINUX_VERSION"
        echo "sunxi-tools:     $SUNXI_TOOLS_COMMIT"
        echo "dfu-util:        $DFU_UTIL_VERSION"
        echo "busybox:         $BUSYBOX_VERSION"
        echo "cross-toolchain: $(${CROSS}gcc --version | head -1)"
        echo "host-gcc:        $(gcc --version | head -1)"
        echo "dtc:             $(dtc -v)"
        echo "mkimage:         $(mkimage -V)"
        echo "make:            $(make -v | head -1)"
        echo "host-os:         $(uname -smr)"
    } > "$LOGDIR/build-metadata.txt"

    cd "$OUT"
    sha256sum u-boot-sunxi-with-spl.bin zImage "$DTB_NAME" \
        initramfs.cpio.gz boot.itb > SHA256SUMS
    cat SHA256SUMS
}

main() {
    mkdir -p "$OUT" "$LOGDIR" "$HOST_TOOLS"
    verify_pins
    "$REPO_ROOT/scripts/check-phase0.sh"
    build_uboot
    build_linux
    build_busybox
    build_initramfs
    build_fit
    build_host_tools
    record_metadata
    say "Done. Artifacts in build/artifacts/, host tools in build/host-tools/."
}

main "$@"
