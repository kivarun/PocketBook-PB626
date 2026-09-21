# Phase 0 UAT — FEL-only boot to UART shell

Deterministic acceptance test for the PB626. Requires: PB626 in reach, a
USB A-to-microB cable, a USB-UART adapter wired to the PB626 UART pads
exactly as described in section 0 below, and a Linux host with USB
access (with `picocom` installed for the interactive console session).
**The external microSD must not be needed** (leave it out or empty).

## 0. UART wiring — read before connecting anything

> **WARNING — do not connect VCC.** Never connect the board's VCC (3.3 V)
> pad to the USB-UART adapter. The adapter is powered by the host over
> USB and the PB626 is powered by its own USB cable; cross-feeding 3.3 V
> into either side is unnecessary for the FEL boot and can damage the
> adapter, the PB626, or both. Leave VCC unconnected in every setup in
> this document.

Wiring (cross TX/RX; VCC stays unconnected):

    PB626 GND -> adapter GND
    PB626 TX  -> adapter RX
    PB626 RX  -> adapter TX
    PB626 VCC -> NOT CONNECTED

Board-side, TX is UART1 TX on SoC pad PG3 and RX is UART1 RX on PG4 (the
pads are labelled on the board); settings are 115200 8N1, 3.3 V logic.

For the first passive capture (running the boot and only watching the
output), two wires are needed and sufficient:

    PB626 GND -> adapter GND
    PB626 TX  -> adapter RX

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

## 4. Run the canonical FEL boot (interactive UART session)

```sh
./scripts/fel-boot.sh --uart /dev/ttyUSB0     # adjust device name
```

The script checks checksums, verifies the FEL identity (SoC id 0x1625,
A13), boots U-Boot over FEL, waits for the U-Boot DFU gadget (USB
1f3a:1010, alt 0 "boot"), pushes `boot.itb` to RAM at 0x42000000 and
detaches DFU — U-Boot then boots the FIT and Linux starts (the kernel is
copied out of the FIT blob to 0x44000000; the canonical layout lives in
`config/ram-map.sh`).

With `--uart`, the session is **interactive**: the boot steps run in the
background while `picocom` owns your terminal, so SPL/U-Boot/kernel
output appears live and you can type at the U-Boot prompt and at the
initramfs shell. Exit picocom with `Ctrl-A Ctrl-X`; the script then
reports whether the boot job completed. Without `--uart` the boot runs
headless with no console attached.

If U-Boot ends up at a prompt instead of the DFU gadget (e.g. the host
DFU push failed), type the manual fallback from the script's error
message directly into the picocom session:

```
loadx 0x42000000    # then: sx -k build/artifacts/boot.itb < /dev/ttyUSB0 > /dev/ttyUSB0
iminfo 0x42000000 && bootm 0x42000000
```

## 5. UART log

`build/log/uart.log` is written by picocom itself (`--logfile`) and
contains the full session (SPL banner, U-Boot, kernel, initramfs and
everything typed). Kernel messages show the correct device tree:

```
Machine model: PocketBook Touch Lux 3
```

## 6. From the UART shell (inside the picocom session) demonstrate

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
