# Stock firmware UART field notes — 2026-10-14

Hardware: PocketBook Touch Lux 3 (PB626), IDIG E028 PB626-V1.6, Allwinner A13 (sun5i).

FEX follow-up: [verified script.bin extraction and board parameters](stock-firmware-fex-2026-10-14.md).
Runtime follow-up: [I2C/input/EPDC/dmesg/sysfs evidence](stock-firmware-runtime-hardware-2026-10-14.md).

**Scope:** real-device observations of the restored **stock** firmware. This is **not** a passing result for the FEL-only mainline Phase 0 UAT in `docs/phase0-uat.md`.

## Test context and boundaries

- Original 4 GB FORESEE microSD had degraded; the previously restored stock system now runs on a replacement 16 GB card. The working card was not repartitioned, reflashed, or used for mainline boot tests in this session.
- UART adapter: Silicon Labs **CP2104**, USB VID:PID `10c4:ea60`, detected as `/dev/ttyUSB0`; communication at **115200 8N1**, flow control off, via `picocom v2024-07`.
- Stock Linux serial console accepted read-only commands (`uname`, `cat /proc/*`, `ls`, `sha256sum`). Follow `docs/phase0-uat.md` section 0 for electrical safety: **never connect the VCC pad**.
- The persistent `/mnt/secure/debug_mode` flag was enabled on the device between captures, causing verbose boot messages to be printed. Effects beyond additional logging are **not proven**.
- Device-unique serials and identifiers are intentionally excluded from this research record.

## Boot chain and stock kernel (verified)

UART excerpts:

```text
dram size =256
HELLO! BOOT0 is starting!
boot0 version : 1.5.0
Succeed in loading boot1 from sdmmc flash.
[       0.128] boot1 version : 1.5.1
[       0.217] fattype FAT16
[       0.226] storage_type=2
[       0.483] 0x40008000 0x003da514 c:\linux\bImage
DRAM: 256
```

Boot0 1.5.0 -> proprietary Allwinner Boot1 1.5.1 -> stock Linux, **not mainline U-Boot**. The log reports **256 MiB RAM**.

```text
Linux pocketbook 3.0.8-hg+default-c4548f764a28 #1 PREEMPT Fri Mar 22 16:09:53 EET 2019 armv7l GNU/Linux
console=ttyS0,115200 root=/dev/mmcblk0p7 init=/init loglevel=1 rootwait
Hardware        : sun5i
Revision        : a13b
CPU implementer : 0x41
CPU part        : 0xc08
CPU revision    : 2
```

The CPU is a Cortex-A8 (`0xC08`). The stock kernel's `ttyS0` does not independently prove the same pin/alias mapping as the existing mainline DT, which selects UART1 PG3/PG4.

### Boot configuration

`/boot/boot.ini`:

```ini
[system]
start_os_name = linux
timeout       = -1
display_device= 0
display_mode  = 0

[linux]
```

`/boot/linux/linux.ini` and `normal.ini` have identical observed contents:

```ini
[global]
commandline = console=ttyS0,115200 root=/dev/mmcblk0p7 init=/init loglevel=1 rootwait

[segment]
img_name = c:\linux\bImage
img_size = 0x800000
img_base = 0x40008000

[script_info]
script_base = 0x43000000
script_size = 0x10000

[logo_info]
logo_name = c:\linux\linux.bmp
logo_show = 1
```

- `/boot/linux/bImage` is **4,039,956 bytes**, matching the printed boot size `0x003da514`.
- `/boot/bImage` is a **different image**, 3,440,828 bytes, and was not the image named in this observed boot.
- `img_size=0x800000` and `script_size=0x10000` are declared configuration sizes, not measured file sizes.
- Which `script*.bin` Boot1 actually consumes, and the semantics of `timeout=-1`, have **not** been experimentally proven.

## Storage (verified by `/proc/partitions` and `/proc/mounts`)

The 16 GB card is presented as `mmcblk0`, **15,110,144 KiB** (~14.41 GiB).

| Device | Size, KiB | Mount / FS | Mode |
| --- | ---: | --- | --- |
| `mmcblk0p1` | 14,604,288 | `/mnt/ext1` via `/dev/user_int`, vfat | rw |
| `mmcblk0p2` | 32,768 | `/boot`, vfat | ro |
| `mmcblk0p5` | 16,384 | not mounted in observed listing | — |
| `mmcblk0p6` | 16,384 | not mounted in observed listing | — |
| `mmcblk0p7` | 35,328 | `/` via `/dev/root`, ext2 | ro |
| `mmcblk0p8` | 250,368 | `/ebrmain`, ext2 | ro |
| `mmcblk0p9` | 100,352 | `/mnt/secure`, ext2 | rw |
| `mmcblk0p10` | 16,384 | not mounted in observed listing | — |
| `loop0` | 142,888 | `/ebrmain/cramfs`, squashfs | ro |
| `zram0` | 51,200 | swap device (not a mount) | — |

`mmcblk0p3` also appears as a one-KiB extended-partition placeholder in `/proc/partitions`.

## FEX and stock boot assets

`/boot/script.bin` and `/boot/script0.bin` are **32,980 bytes each** and have the same SHA-256:

```text
9371685d47dbec3f9cf3f4450cc33a7d4d0eaf4a1f88e5cb0298a148c2664c59  /boot/script.bin
9371685d47dbec3f9cf3f4450cc33a7d4d0eaf4a1f88e5cb0298a148c2664c59  /boot/script0.bin
```

**Completed:** `/boot/script.bin` was captured by read-only Base64 over UART, decoded to 32,980 bytes on the host, and its SHA-256 matched the value above. The complete textual FEX has been decoded and round-trip validated against the original binary; see the linked FEX analysis.

Other observed `/boot` assets: `boot.axf` (53,312 B), `sprite.axf` (386,476 B), `drv_de.drv` (339,448 B), `hwconfig` and `hwconfig.upd` (8 B each), `vcom` (5 B), and E-Ink `.wbf` waveform files. File names by themselves do not establish the complete hardware protocol.

## E-Ink, graphics and input (verified stock boot log)

```text
HWC_PLATFORM 14
HWC_DISPLAY 4
HWC_CONTROLLER 5
HWC_KEYBOARD 12
HWC_DPOS 1
HWC_TOUCHPANEL 19
HWC_AUDIO 0
epdc_default_init
epdc_default_rotate: w=1024 h=758 scan=1024 mem=786432
read_waveform_name: read /sys/class/graphics/fb0/device/waveform_name
Real waveform name: '320_G110_AA9224_ED060XD4U2_TC'
epdc_default_rotate: w=758 h=1024 scan=768 mem=786432
xres=758 yres=1024 scanline=768 vdepth=8 orient=0
```

- Stock EPDC uses a **1024×758, 8-bpp** framebuffer; a 768-byte padded stride at 1024 rows yields the reported **786,432-byte** allocation in rotated mode.
- The waveform name corresponds to `/boot/320_G110_AA9224_ED060XD4U2_TC.wbf` (**256,594 B**).
- `HWC_*` numbers are internal vendor IDs, **not** established controller chip identities.
- `init_frontlight` reports frontlight type 3; `inputThread` reports touchscreen type 19.
- `bookshelf.app`, `reader_controller.app`, `scanner.app`, etc. attach shared-memory framebuffers; some components use Qt/QML.
- These observations do **not** mean that the E-Ink controller is supported by unmodified mainline Linux.

## Debug mode, console and power management

Before enabling debugging:

```text
touch /mnt/secure/debug_mode to enable debug
Please press Enter to activate this console.
```

After the flag was enabled:

```text
rm /mnt/secure/debug_mode to disable debug
Starting monitor (multitasking Jul 30 2019 18:55:22)
[79 : 1124070496 : pocketbook] (do_suspend) boottime = 16557 ms; sleeptime 2 ms
16:54:44 S (229487)
16:54:44 W
16:54:47 S (226300)
```

The firmware calls `do_suspend` ~16.6 s after boot in the verbose trace. The subsequent complete log strengthens the interpretation of `S`/`W` as **suspend/wake**: accumulated `sleeptime` values closely track the wall-clock gaps (see shutdown timeline below). This is a high-confidence interpretation of the vendor log markers rather than a measured low-level wake-source trace. UART input was not consistently responsive once the device entered its low-power state. The hypothesis that debug mode caused the missing console remains unsupported; the flag was enabled for the captured verbose session, so its exact effect on power management has not been isolated.

Minor startup messages: `Can't restore logo` (missing `/boot/linux/logo.bak`), unavailable QML image resources, and SQLite WAL recovery followed by `quick_check: ok`. The stock UI starts successfully despite these messages.

## Complete shutdown sequence — same verbose UART capture (2026-10-14)

The continued capture shows repeated sleep/resume cycles followed by an **application-initiated timed shutdown**, not a crash. Device timestamps are from the stock firmware (we have not independently checked its RTC precision).

| Device log time | Evidence | Interpretation |
| --- | --- | --- |
| 16:54:29 | `Starting monitor`, RTC timestamp | Stock userspace startup |
| 16:54:44 | `S`, `do_suspend` with `boottime = 16557 ms` | First low-power entry, ~16.6 s since boot |
| 16:54:44 | `W` | Immediate wake/return logged |
| 16:54:47 | `S` | Back to suspend |
| 16:58:32 | `do_suspend ... sleeptime 224987 ms`, `W` | Wake after ~225 s accumulated sleep |
| 16:58:34 | `S` | Back to suspend |
| 17:03:59 | `do_suspend ... sleeptime 549972 ms`, `W` | Another wake; ~550 s accumulated sleep |
| 17:04:01 | `S` | Back to suspend |
| 17:04:45 | `do_suspend ... sleeptime 593957 ms`, `W` | Wake, then power-off timer events |
| 17:04:45 onward | `iv_poweroff_timer`, `Power off time has come...`, `Power-off from application` | PocketBook userspace requests power-off |
| 17:04:51 onward | `netagent ... disconnect`, unmount, SIGTERM/SIGKILL, `Power down.` | Shutdown sequence completes |

The interval between userspace start and timed power-off is approximately **10 min 16 s**; this is consistent with a configured inactivity/power-off timer, **but its actual configured value and triggering policy were not read**. The prior session's separate poweroff messages and this capture need not have the same immediate trigger.

Selected verbatim lines from the final section:

```text
[99 : /ebrmain/bin/taskmgr.app] (iv_poweroff_timer)
[94 : /ebrmain/bin/reader_controller.app] (iv_poweroff_timer)
Power off time has come...
Power-off from application
--- started logo shower (pid 176, path=/ebrmain/bin/power_off_logo.app)
/srv/jenkins/workspace/fw-builder-ng/U_626_5.20/build/inkview/src/hw_device/hw_logo.c:363 logo2off=bookcover
[176 : /ebrmain/bin/power_off_logo.app] (LoadBitmap)Cannot open bitmap: /tmp/bookcover
[176 : /ebrmain/bin/power_off_logo.app] (LoadBitmap)Cannot open bitmap: /mnt/ext1/system/logo/offlogo/bookcover.bmp
LAST BOOK: '(null)'
[79 : 1074847744 : pocketbook] (shutdown_all_tasks) shutdown_all_tasks(0)
[202:14/10/26 17:04:51] netagent called with parameters < disconnect >
fuser_kill(): error in 'fuser -k -9 -m /mnt/ext1'
umount_internal_p(): umount /mnt/ext1 && sync && sync
umount_devices() success
umount: /dev/loop0 busy - remounted read-only
umount: /dev/mmcblk0p8 busy - remounted read-only
The system is going down NOW!
Sent SIGTERM to all processes
Sent SIGKILL to all processes
Requesting system poweroff
[   33.749420] Power down.
```

**Interpretation / limitations:**

- `iv_poweroff_timer` is emitted for multiple running applications (repeatedly), followed by the explicit `Power-off from application`. This **supports a userland power-off policy**, not a watchdog fault or kernel panic. The log does not reveal *why* the timer fired.
- `power_off_logo.app` tries to display the last book cover (`logo2off=bookcover`), but the candidate paths are absent; `LAST BOOK: '(null)'`. The failure did not prevent shutdown. No assumption is made about which fallback image the screen finally showed.
- The logged `fuser_kill()` error and several `busy - remounted read-only` messages are **not proof of filesystem corruption**. The sequence also reports `umount_devices() success` and a final platform `Power down.`
- The firmware build-tree string includes `U_626_5.20`; it is a source/build path in the log, **not independent proof** of the installed firmware version.
- No kernel panic, OOPS, or watchdog reset appears in the supplied shutdown trace; absence from the capture cannot prove that all possible failures are impossible.
- This remains **stock firmware UAT evidence only**; the FEL-only mainline Phase 0 hardware acceptance status is unchanged (**PENDING**).

## Next evidence to capture

1. **DONE, 2026-10-14:** `/boot/script.bin` transferred over UART, SHA-256 validated; FEX reconstructed and round-trip checked. See [`stock-firmware-fex-2026-10-14.md`](stock-firmware-fex-2026-10-14.md) and [`../hardware/stock-script.fex`](../hardware/stock-script.fex).
2. Correlate UART availability with display wake/suspend, without altering production partitions or power settings.
3. Run the existing **Phase 0 FEL-only UAT** (`docs/phase0-uat.md`) independently of stock boot. Its acceptance status remains **PENDING**.
4. Afterwards, investigate waveform/EPDC, touch controller and power rails for a later phase.

## Direct shell reboot and repeated early suspend — 2026-10-14

**Context.** Following the UART extraction, the owner changed the stock automatic **power-off** timeout from 10 minutes to 60 minutes and ran the following commands from an interactive stock root shell, with the USB-UART adapter still attached:

```sh
sync
reboot
```

The console showed a real Linux reboot followed by a complete Boot0/Boot1 restart:

```text
umount: can't remount /dev/user_int read-only
umount: /dev/loop0 busy - remounted read-only
umount: /dev/mmcblk0p8 busy - remounted read-only
umount: can't remount tmpfs read-only
umount: none busy - remounted read-only
The system is going down NOW!
Sent SIGTERM to all processes
Requesting system reboot
[   91.776052] Restarting system.
dram size =256
super_standby_flag = 0
HELLO! BOOT0 is starting!
boot0 version : 1.5.0
Succeed in loading boot1 from sdmmc flash.
[       0.128] boot1 version : 1.5.1
[       0.485] 0x40008000 0x003da514 c:\linux\bImage
```

Stock user space subsequently started successfully (including `Task 93 initialized`, `Bookshelf started, allowing all tasks restart`, and `explorer.app`); SQLite reported `DataBase: quick_check: ok`. No panic, OOPS or fatal MMC error was present in the supplied trace. The unmount/remount warnings deserve recording but are **not evidence of filesystem damage**. The direct shell `reboot` path may not follow PocketBook Monitor's orderly application shutdown path, whereas the previous automatic power-off trace included task cleanup; the two paths should not be treated as equivalent. The shell issued `sync` before the reboot.

**Early sleep reproduced:** the RTC was logged at **17:53:16** while PocketBook Monitor initialized, followed by the console marker `17:53:30 S (229369)` after the UI reached its initialized state. This is approximately **14 seconds** later; earlier boot logs showed `S`/`W` pairs and `do_suspend`, supporting interpretation of `S` here as suspend. The log does not show a subsequent `W`, nor does it establish the exact policy that schedules the first suspend. The **60-minute automatic power-off** setting did not prevent early sleep; power-off and suspend policies must be distinguished.

**UART caveat:** intermittent inability to activate the stock shell with Enter was reported, even though input eventually worked (including a successful `echo UART_OK; cat /proc/uptime` and the direct `reboot`). This trace cannot establish whether loss of input is caused by suspend, serial wiring/contact, or a user-space console policy. The owner also observed apparent startup sensitivity with the adapter attached; that observation has **not** yet been isolated with controlled wiring tests. Do not assert electrical back-powering as a proven cause.

**Status:** this verified only the stock firmware's reboot and sleep behavior. The repository's FEL/mainline hardware UAT remains **PENDING**.

## Late follow-up: interactive console and read-only driver enumeration

With `/mnt/secure/debug_mode` **removed** and after a reboot, the user
reported the interactive stock UART console was available again. Prior
intermittent console availability while the marker existed has not been
reproduced under a controlled A/B test; marker causality is **unproven**.
A physical CP2104 connection already present at power-on was also reported
to sometimes interfere with starting the reader; no isolated two-wire
(passive RX only) test has yet established its electrical cause.

A complete stock-kernel `dmesg`, read-only I2C symlinks, input devices and
the `/sys/class/graphics/fb0/device/` listing were then captured.
The running kernel uses **Cypress `cyttsp4_i2c_adapter`** on I2C2/0x24,
registering **`cyttsp4_mt`**, in contrast to `ft5x_ts` in the FEX.
The stock **Obreey Software EPDC** reads `/boot/default.wbf`, selects its
**TPS65185** backend (VCOM log `-2960`), and exposes the `sw-epdc` sysfs
interface, including hazardous write-only low-level control nodes.
Full evidence and distinctions: [runtime hardware report](stock-firmware-runtime-hardware-2026-10-14.md).