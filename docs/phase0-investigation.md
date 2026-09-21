# Phase 0 investigation — PB626 / Touch Lux 3 (IDIG E028 PB626-V1.6, A13)

All statements below were verified against the pinned upstream sources in
`build/src/` and the linux-sunxi wiki page for the device.

## 1. Existing device-tree support

`arch/arm/boot/dts/sun5i-a13-pocketbook-touch-lux-3.dts` is **in mainline
Linux since v5.7** (commit `cd3e42c9f745` by Ondrej Jirman, Feb 2020; moved
to `allwinner/` in v6.3 by `724ba6751532`). In v6.12.110 it is
`arch/arm/boot/dts/allwinner/sun5i-a13-pocketbook-touch-lux-3.dts` and
declares:

* model "PocketBook Touch Lux 3", compatible `pocketbook,touch-lux-3`
* console: **UART1 on PG3/PG4** (`serial0 = &uart1`, 115200)
* i2c0: **AXP209 PMIC** (mainline-supported), i2c1: pcf8563 RTC,
  i2c2: touch panel bus (no driver attached upstream)
* mmc0 = external microSD (cd-gpio PG0), **mmc2 = internal microSD**
  (non-removable, 4-bit on PC pins)
* usb OTG in peripheral mode; EHCI/OHCI host for the internal USB WiFi
* gpio-keys (page left/right), LRADC keys (Home/Menu), power LED
* pwm backlight (PB4 enable), spi2 with the e-ink NOR flash (mx25u4033)
* AXP209 battery/USB power supplies

U-Boot v2026.07 carries the same DT verbatim in
`dts/upstream/src/arm/allwinner/` (verified identical by diff).

## 2. Can current upstream U-Boot boot this board directly?

Yes — with no source patches. U-Boot sunxi boards are generic; what matters:

* **Console**: `arch/arm/mach-sunxi/board.c` muxes UART1 to PG3/PG4 for
  `CONFIG_CONS_INDEX=2` + `CONFIG_MACH_SUN5I` (both SPL and full U-Boot).
* **DRAM**: `board/sunxi/dram_sun5i_auto.c` is selected automatically for
  sun5i; it configures DDR3 with the "vendor magic" timings (default choice,
  same as Allwinner boot0) and auto-detects bus width and density
  (`dram_sun4i.c`), which covers the PB626's 256 MiB DDR3 @ 408 MHz.
* **USB gadget**: `USB_MUSB_SUNXI` (default y on ARCH_SUNXI) +
  `USB_MUSB_GADGET` gives the DFU download gadget used by the Phase 0 boot
  path (`drivers/dfu/dfu_ram.c`).
* The A13-OLinuXino_defconfig already demonstrates this combination
  (CONS_INDEX=2, CMD_DFU, DFU_RAM, MUSB_GADGET, DRAM_CLK=408).

## 3. Is a PB626-specific SPL/U-Boot patchset required?

No source patches are required. A **board defconfig is required** and is
supplied as `config/uboot-pb626-fel_defconfig` (copied into
`configs/pb626_fel_defconfig` by `scripts/build.sh`): PB626 DT as the default
device tree, UART1-PG console, DRAM_CLK=408, DFU-RAM boot over USB, and an
environment that never touches storage (`CONFIG_ENV_IS_NOWHERE` +
full default-env replacement, `config/pb626-default-env.txt`).

## 4. Kernel version/branch with the most complete working PB626 support

Two candidates:

* **Mainline** (pinned here: 6.12.110 LTS): serial, MMC (both slots),
  buttons/LED, AXP209 PMIC (battery/charger/power/ADC), RTC, USB host +
  OTG gadget, backlight, e-ink NOR flash. No e-ink panel, no touch
  driver, no WiFi driver wired up.
* **Ondrej Jirman's out-of-tree tree** (<https://xff.cz/kernels/>, device
  page <https://xnux.eu/devices/pocketbook-touch-lux-3.html>): "everything
  is supported except suspend-to-RAM" — includes e-ink display and touch
  support via additional patches. Not used in Phase 0 (not pinned-upstream,
  not needed for the UART milestone); recommended as the Phase 1+ display
  donor after review.

## 5. What remains out-of-tree

| Feature | Status |
|---|---|
| e-ink panel (ED060XD4 1024x758) | out-of-tree (Ondrej's tree); mainline has no sunxi e-ink display driver |
| Touch controller (Cypress TMA445, i2c2) | no mainline driver |
| TP65185 PMIC (charging/e-ink rails) | no mainline driver |
| WiFi RTL8188EUS (USB) | in-tree staging `r8188eu` + `rtl8xxxu` exist; needs `rtl8188eufw.bin` firmware and the AXP209 LDO3 (vcc-wifi) rail — not wired up in Phase 0 |
| Suspend/resume | not working even in the out-of-tree stack |

## 6. Console UART parameters

UART1 (PG3 = TX, PG4 = RX), 115200 8N1, 3.3 V logic. The wiki describes
"nice big pads on the side of the board", clearly marked. `chosen/stdout-path`
in the DT is `serial0:115200n8`; the kernel sees it as `ttyS0` (alias
`serial0 = &uart1`). U-Boot uses the same port (CONFIG_CONS_INDEX=2).
USB-UART adapter wiring for the UAT: `docs/phase0-uat.md` section 0 —
GND and TX/RX crossed, **VCC left unconnected** (never feed the board's
3.3 V pad into the adapter).

## 7. How e-ink support is exposed by the existing Linux implementation

Mainline: only the panel's SPI NOR flash (spi2, `macronix,mx25u4033`) and
PWM backlight are declared; the display itself is driven by PocketBook's
vendor 3.4-legacy kernel and, for modern kernels, by Ondrej's out-of-tree
patches (e-ink framebuffer + TCON reconfiguration). Phase 0 does not
require display output.

## 8. Are any vendor blobs required for the initial shell milestone?

No. The Phase 0 chain is entirely mainline: U-Boot (SPL + U-Boot), Linux,
BusyBox initramfs, and `sunxi-fel`/`dfu-util` host tools. No firmware files,
no proprietary blobs. (WiFi firmware `rtl8188eufw.bin` would only be needed
for WiFi in Phase 1+.)

## FEL entry

Per the device wiki: **the Menu button on the right side triggers FEL mode**
(hold Menu while powering the device on / connecting USB). Verify with
`sunxi-fel ver` — the A13 reports SoC id 0x1625 / "A13".
