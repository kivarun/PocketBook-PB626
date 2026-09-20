# Patches

Phase 0 requires **no external patchsets**. Everything needed is already in
the pinned upstream sources:

| Concern | Where it is solved upstream |
|---|---|
| PB626 device tree | Linux `arch/arm/boot/dts/allwinner/sun5i-a13-pocketbook-touch-lux-3.dts` (Ondrej Jirman, added v5.7); synced verbatim into U-Boot `dts/upstream/src/arm/allwinner/` |
| UART1 on PG3/PG4 console | U-Boot `arch/arm/mach-sunxi/board.c` muxes UART1 to PG3/PG4 for `CONFIG_MACH_SUN5I` + `CONFIG_CONS_INDEX=2` |
| 256 MiB DDR3 @ 408 MHz | U-Boot `board/sunxi/dram_sun5i_auto.c` (DDR3, vendor-magic timings, auto bus-width/density detection) |
| FEL execution of SPL+U-Boot | U-Boot SPL FEL return (`common/spl/spl.c`) + `sunxi-fel uboot` |
| DFU download to RAM | U-Boot `drivers/dfu/dfu_ram.c` (`CONFIG_DFU_RAM`) + MUSB gadget (`CONFIG_USB_MUSB_GADGET`, `CONFIG_USB_GADGET_DOWNLOAD`) |

Board-specific behaviour lives only in `config/` (a U-Boot defconfig, a
default-environment file, a kernel config fragment, the FIT description and
the initramfs); no upstream source is modified.

Out-of-tree work that exists for this device but is intentionally not used
in Phase 0 (e-ink display, touchscreen driver, etc.): see
`docs/phase0-investigation.md`.
