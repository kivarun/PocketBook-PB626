# PB626 stock kernel: runtime hardware evidence — 2026-10-14

Scope: **restored stock PocketBook firmware** on PB626, vendor Linux
`3.0.8-hg+default-c4548f764a28` (built 2019-03-22), Allwinner A13 / sun5i.
Observed by UART shell after removing `/mnt/secure/debug_mode`. Sources:
read-only `/sys/bus/i2c/devices`, `/proc/bus/input/devices`, `dmesg`,
`/sys/class/graphics/fb0/device/` directory listing, plus the extracted
`script.bin` in [FEX analysis](stock-firmware-fex-2026-10-14.md).
These are **stock-runtime observations**, not Phase 0 FEL/mainline UAT results.
Do not include device serial numbers in committed field notes.

## I2C enumeration and driver bindings

| Linux client | Sysfs `name` | Bound driver | Finding |
| --- | --- | --- | --- |
| `0-0034` | `axp20_mfd` | `axp_mfd` | AXP20-family system PMIC, dmesg CHIP ID `0x41` |
| `1-0051` | `pcf8563` | `pcf8563` | RTC, registered as `rtc0` |
| `1-0068` | `tps65185` | **none** (`driver` link absent) | I2C client is registered, standard I2C driver is not bound |
| `2-0024` | `cyttsp4_i2c_adapter` | `cyttsp4_i2c_adapter` | Cypress TrueTouch Gen4+ family |

Runtime touch input (from `/proc/bus/input/devices`):

```text
N: Name="cyttsp4_mt"
P: Phys=2-0024/input0
H: Handlers=event2
```

Relevant vendor boot lines:

```text
[ 0.919636] [cyttsp4_i2c_detect] Chip detected, adapter 2, address 0x24
[ 0.919920] [allwinner_init_gpio] tp_wakeup request gpio fail!
[ 0.919965] SetLDO1_8V: script_parser_fetch err. Use default
[ 0.920847] SelectTPVoltage: script_parser_fetch err. Use default
[ 1.774740] cyttsp4_i2c_adapter 2-0024: cyttsp4_startup_: cyttsp4_exit startup r=0...
[ 1.775237] input: cyttsp4_mt as /devices/platform/sun5i-i2c.2/i2c-2/2-0024/input/input2
[ 1.775450] cyttsp4_i2c_init: Cypress TTSP v4+ I2C Driver (Built 20140430) rc=0
```

**Important correction:** FEX `[ctp_para] ctp_name="ft5x_ts"` is **not** the
driver active in the stock kernel. The running kernel uses `cyttsp4` and
registered multitouch `event2` at I2C2/0x24. This establishes the Cypress
**family / driver stack**, **not** an exact silicon model such as TMA445.
FEX touch GPIOs (`PG11` IRQ, `PB3` reset, `PE5` power) remain candidates,
not fully runtime-verified: the vendor driver reports missing FEX keys and
uses fallbacks. Do not blindly translate FEX touch settings into mainline DTS.

## Proprietary software EPDC and panel power

From stock kernel `dmesg`:

```text
[ 0.474222] Software EPDC driver (build Mar 22 2019 16:09:58)
[ 0.474239] Copyright (c) 2013 by Obreey Products
[ 0.477431] loading waveform file: /boot/default.wbf
[ 0.481686] waveform size: 256594
[ 0.501065]   waveform name:  320_G110_AA9224_ED060XD4U2_TC
[ 0.501085]   waveform type:  60
[ 0.501092]   frame rate:     85
[ 0.501101]   timing mode:    3
[ 0.501113]   waveform modes: 8
[ 0.501119]   temp ranges:    14
[ 0.543553] found AMEPD: 'ED060XD4'
[ 0.543576] waveforms loaded
[ 0.548465] [epdc_pmic_init] param pmic=TPS65185
[ 0.548480] [epdc_pmic_init] select "TPS65185" EPDC PMIC driver
[ 0.560672] pmic vcom: -2960
[ 0.581456] update 0,0,1024,758 wf=1 flags=40
```

- The stock kernel uses vendor **Software EPDC / `sw-epdc`**, not an
  unmodified mainline display driver. The initial panel geometry is
  **1024 × 758**; stock user space later rotates to **758 × 1024**, 8 bpp.
- The waveform actively loaded on boot is `/boot/default.wbf`, reported as
  **256,594 bytes** and named `320_G110_AA9224_ED060XD4U2_TC` internally.
  Do not conflate the **loaded path** with similarly named `/boot/*.wbf` files.
- The vendor EPDC explicitly selects a `TPS65185` PMIC backend and reports
  raw `pmic vcom: -2960` (consistent with -2960 mV, but the log does not
  specify units). The absence of an I2C `driver` symlink at `1-0068` is
  compatible with a separate vendor PMIC backend; the exact access path
  has **not** been traced.
- VCOM and power sequencing are hardware-sensitive and should not be
  altered merely to explore the sysfs interface.

## EPDC sysfs interface observed

Path: `/sys/class/graphics/fb0/device/`.
Platform driver symlink resolves under `/sys/bus/platform/drivers/sw-epdc`.
`ls -la` shows the following **names and modes** (contents not yet read):

| Purpose/group | Entries | Listed access |
| --- | --- | --- |
| Waveform metadata | `waveform_name`, `waveform_info`, `waveform_status` | read-only |
| Waveform control/data | `waveform_override`, `waveform_binary`, `waveform_text` | writable; **do not modify** |
| Panel voltages | `vcom`, `vcom_offset`, `vtouch`, `vhigh_level` | mix of read-only and writable |
| Persistent voltage programming | `vcom_permanent` | write-only, world-writable; **never probe by writing** |
| Temperature | `temperature`, `tempsensor`, `temp_offset` | readable and writable |
| EPDC power sequences | `powerup_sequence`, `powerdown_sequence`, `powerdown_delay` | readable and writable |
| Update and diagnostics | `fill`, `update`, `vni_test`, `register_dump`, `register_write` | write-only; may have hardware side effects |
| Tuning and reporting | `cpu_min_freq`, `debuglevel`, `hqfilter`, `log_frames`, `log_updates`, `slow_motion`, `strength` | mix of read-only and writable |
| Internal topology | `timings/`, `graphics/`, `power/`, `driver`, `subsystem`, `modalias`, `uevent` | directory/links/metadata |

Representative exact modes from the owner's listing:

```text
-rw-rw-rw-  vcom
--w--w--w-  vcom_permanent
-r--r--r--  vcom_offset
-r--r--r--  waveform_info
-r--r--r--  waveform_name
-r--r--r--  waveform_status
-rw-rw-rw-  waveform_override
-rw-r--r--  waveform_binary
-rw-------  waveform_text
--w-------  register_dump
--w-------  register_write
--w--w--w-  fill
--w--w--w-  update
```

**Safety boundary:** no reads of sysfs attribute contents were performed in
this capture; only directory listing. For follow-ups, start with explicitly
read-only metadata (`waveform_info`, `waveform_status`, `waveform_name`) and
avoid writes to `vcom`, `vcom_permanent`, power sequences, waveform control,
register accesses, `fill`, `update` or `vni_test`. Reading an ostensibly
readable control may still invoke device-driver code; evaluate each case.

## Additional boot and power evidence

```text
[ 0.000000] Total Detected Memory: 256MB with 2 banks
[ 0.000000] Kernel command line: console=ttyS0,115200 root=/dev/mmcblk0p7 init=/init loglevel=1 rootwait
[ 0.040825] standby_mode = 1.
[ 0.056912] sunxi-uart.1: ttyS0 at MMIO 0x1c28400 (irq = 2) is a U6_16550A
[ 0.068310] axp_mfd 0-0034: AXP (CHIP ID: 0x41) detected
[ 0.069612] rtc_detect: Detected chip pcf8563 at adapter 1, address 0x51
[ 0.105914] pmu_pekoff_time = 6000
[ 0.105929] pmu_peklong_time = 1500
[ 0.105941] pmu_pekon_time = 1000
[ 0.118952] sunxi_wdt: initialized (timeout=23s, nowayout=0)
[ 0.190946] mmcblk0: 1 mmc1:0007 SD16G 14.4 GiB
[ 0.242976] EXT2-fs (mmcblk0p7): warning: mounting unchecked fs, running e2fsck is recommended
[ 0.247302] Failed to execute /init.  Attempting defaults...
[ 6.321969] Adding 51196k swap on /dev/zram0.  Priority:-1 extents:1 across:51196k SS
```

Other noteworthy but nonfatal startup messages: FEX parsing of APB frequency
failed; MMC2 SDIO CMD52/CMD5 timed out during probe, followed by successful
SDHC detection and root mount; `spi2` reports a parameter-fetch error yet
initializes (`panel_spi` on SPI2 CS0 100 kHz); some ext2 volumes were mounted
without prior filesystem checks. No kernel panic is present in this capture.
Hardware `pmu_*` timing values are logged configurations, **not** evidence of
the cause of intermittent power-on when CP2104 is attached.

## Research implications / open questions

1. Stock runtime proves **Cypress TTSP v4+** touch stack, but not exact chip
   ID, wiring or a working mainline driver. Check real IRQ/reset/power
   sequencing before changing DTS.
2. Stock runtime proves **Obreey Software EPDC**, ED060XD4 waveforms,
   `TPS65185` backend selection and a `-2960` raw VCOM report. Driver
   sources or read-only instrumentation are needed to map the E-Ink path.
3. The sysfs surface contains potentially destructive writes (especially
   `vcom_permanent` and low-level registers); do not exercise them in UAT.
4. FEX is evidence of vendor *configuration*, not necessarily the active
   behavior of the working kernel (e.g. `ft5x_ts`, `dram_size=512`, LCD
   geometry). Preserve both sources and document discrepancies.
5. Stock UART console became usable after the `/mnt/secure/debug_mode`
   marker was removed and the reader restarted. This is **correlation**;
   no controlled A/B has proven that the marker caused prior failures.
6. Mainline **Phase 0 hardware UAT remains PENDING**. No FEL/DFU/mainline
   boot has been demonstrated by these stock-firmware captures.