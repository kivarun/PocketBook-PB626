# Phase 0 UAT — FEL-only boot to UART shell

Deterministic acceptance test for the PB626. Requires: PB626 in reach, a
USB A-to-microB cable, the UART1 pads wired (PG3=TX, PG4=RX, GND, 3.3 V,
115200 8N1) to a USB-UART adapter, and a Linux host with USB access.
**The external microSD must not be needed** (leave it out or empty).

## 1. Build once

```sh
docker build -t pb626-build-env .
docker run --rm -v "$PWD":/workspace pb626-build-env \
    /workspace/scripts/build.sh
```

Result: `build/artifacts/` (u-boot-sunxi-with-spl.bin, zImage,
sun5i-a13-pocketbook-touch-lux-3.dtb, initramfs.cpio.gz, boot.itb,
SHA256SUMS) and `build/host-tools/` (sunxi-fel, dfu-util).

## 2. Put the PB626 into FEL mode

1. Disconnect USB and power.
2. Hold the **Menu** button (right side).
3. Connect the USB cable (device powered by USB).
4. Release the button.

## 3. Verify FEL identifies the A13

```sh
./build/host-tools/sunxi-fel ver
```

Expected (the important part is `(A13)`, SoC id 0x1625):

```
AWUSBFEX soc=00001625(A13) 00000001 ver=0401 00 00 scratchpad=00000010 00000000 00000000
```

## 4. Run the canonical FEL boot

```sh
./scripts/fel-boot.sh --uart /dev/ttyUSB0     # adjust device name
```

The script: checks checksums, boots U-Boot over FEL (SPL output visible on
UART), waits for the U-Boot DFU gadget, pushes `boot.itb` to RAM at
0x42000000, detaches DFU — U-Boot then boots the FIT and Linux starts.

## 5. Capture UART output

`build/log/uart.log` contains the full session (SPL banner, U-Boot, kernel,
initramfs). Kernel messages show the correct device tree:

```
Machine model: PocketBook Touch Lux 3
```

## 6. From the UART shell demonstrate

```
uname -a
cat /proc/cmdline                      # console=ttyS0,115200n8 ... rdinit=/init
cat /proc/device-tree/model            # PocketBook Touch Lux 3
cat /proc/partitions                   # mmc devices listed (not mounted)
ls /sys/class/input                    # input devices present
dmesg
cat /sys/class/power_supply/*/voltage_now   # AXP209 battery state
```

## 7. Restore the device

Power-cycle the PB626 (remove USB / hold power to boot normally). The
original PocketBook system boots unchanged — nothing was written to the
internal microSD (mmc2), external microSD (mmc0), SPI NOR or U-Boot env
(`CONFIG_ENV_IS_NOWHERE`; the FEL boot never touches storage).
