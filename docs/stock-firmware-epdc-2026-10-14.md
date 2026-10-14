# PB626 stock Obreey sw-epdc: read-only runtime values (2026-10-14)

Evidence: user-recorded UART shell on restored stock PocketBook PB626, vendor Linux
`3.0.8-hg+default-c4548f764a28`. Device at
`/sys/class/graphics/fb0/device/` binds to platform driver `sw-epdc`.
This document records **read-only sysfs values**, not a working port or
a specification for mainline Linux. No sysfs attributes were written.

## Waveform metadata and status

From `cat waveform_info` and `cat waveform_status`:

```text
Waveform type:  0x3c
Panel size:     6.0
AMEPD part no:  0x0e
Applied params: 1024x760
Frame rate:     85 Hz
Timing mode:    3
Waveforms:      1 2 3 4 5 6 7 8 15
Temp ranges:    0 3 6 9 12 15 18 21 24 27 30 33 38 43 48
waveform_status: ok
```

`Applied params: 1024x760` differs from the active framebuffer
`1024x758` observed in stock logs and the ED060XD4 logical resolution.
The meaning of the extra two lines is **unconfirmed**; do not silently
rewrite panel geometry or assume it is a typo.

There are **15 temperature boundaries** and **14 numeric values** in
each printed mode row. The numeric units and the precise mapping of these
values to panel operations have **not been established**. Do not assume
milliseconds, clock cycles, or a 1:1 mapping to the public waveform API.

### Entire waveform_info numeric table, transcribed as read

```text
mode | bin01 bin02 bin03 bin04 bin05 bin06 bin07 bin08 bin09 bin10 bin11 bin12 bin13 bin14
   1 |   870   776   682   611   517   447   376   305   258   235   211   188   164   141
   2 |  1529  1364  1200  1058   964   823   705   588   470   470   470   470   470   470
   3 |  1552  1364  1200  1058   964   823   705   588   470   470   470   470   470   470
   4 |   423   376   329   282   258   211   188   141   117   117   117   117   117   117
   5 |  1552  1364  1200  1058   964   823   705   588   470   470   470   470   470   470
   6 |   941   823   729   611   564   470   423   305   258   258   258   258   258   258
   7 |   870   776   682   611   517   447   376   305   258   235   211   188   164   141
   8 |   988   894   776   682   588   494   423   352   282   282   282   282   282   282
  15 |  1529  1364  1200  1058   964   823   705   588   470   470   470   470   470   470
```

This lists nine numerical mode identifiers, `1–8` plus `15`; an earlier
kernel boot message said `waveform modes: 8`. The discrepancy is
recorded, not interpreted as an error.

## VCOM, temperatures, voltage and power sequencing

Read-only snapshot (`cat`, without writing any values):

```text
vcom:               -2.96
vcom_offset:         0.25
temperature:         31
tempsensor:          ambient
temp_offset:         0
powerup_sequence:    vdd { 1 vneg 6 vee 6 vpos 6 vgg 4 } vcom 1
powerdown_sequence:  5 vcom 10 { vgg 6 vpos 6 vneg 48 vee } 500 vdd
powerdown_delay:     12
vhigh_level:         15000
```

`vcom=-2.96` is presented as volts by this sysfs interface and is
consistent with boot `pmic vcom: -2960` if the latter uses millivolts;
the boot-log units are not explicitly labelled. Do **not** infer the
meaning or unit of `vcom_offset=0.25`, `powerdown_delay=12` or
`vhigh_level=15000` without examining the driver.

The **exact order and grammar** in the two power-sequence strings is
preserved. They indicate named stages
`vdd`, `vneg`, `vee`, `vpos`, `vgg`, `vcom` and numeric
parameters. Whether braces mean parallel operations, nested timing,
or something else, and whether numbers represent delays or settings,
**remains unknown**. No attempt was made to apply/rewrite them.

Temperature `31` is an instantaneous sample. A contemporaneous
`tempsensor=ambient` identifies the selected source according to the
driver, but does not identify the physical sensor or justify generalizing
the reading to other operating conditions.

## Display interface timing readout (sysfs, read-only)

All 15 files under `/sys/class/graphics/fb0/device/timings/` were
successfully read on the running PB626. These are the exact values returned;
none were modified.

| Attribute | Stock value |
| --- | ---: |
| `fbl` | 4 |
| `fdl` | 758 |
| `fel` | 8 |
| `framerate` | 85 |
| `fsl` | 2 |
| `gdck_high` | 200 |
| `gdck_sta` | 4 |
| `gdoe_sta` | 0 |
| `gdsp_offset` | 80 |
| `lbl` | 6 |
| `ldl` | 256 |
| `lel` | 38 |
| `lsl` | 6 |
| `pixclk` | 20079720 |
| `sdoe_mode` | `line` |
| `sdoe_sta` | -1 |

### Exact timing closure — confirmed arithmetic

The reported clock is **exactly equal** to the aggregate line timing,
aggregate frame timing and nominal frame rate:

```text
line_total  = lsl + lbl + ldl + lel
            =   6 +   6 + 256 +  38 = 306 timing ticks/line

frame_total = fsl + fbl + fdl + fel
            =   2 +   4 + 758 +   8 = 772 lines/frame

pixclk      = line_total * frame_total * framerate
            = 306 * 772 * 85
            = 20,079,720 Hz
            = 20.07972 MHz   (exactly matches sysfs)
```

Thus the timing values form a **self-consistent configuration** for
85 frames/s; this establishes arithmetic closure but does not independently
measure the physical oscillator frequency or the actual external signal
transitions. The reciprocal nominal frame period is about 11.765 ms.

The data strongly suggest that `ldl=256` is a transfer-unit count rather
than 256 individual horizontal image pixels, since the logical image width
is 1024 and `1024/256=4`. Four pixels per transfer tick is a hypothesis,
**not yet confirmed by bus-level instrumentation or driver source**.

Similarly `fdl=758` matches the active 758 framebuffer rows, while
`fdl+fsl=758+2=760` matches the `waveform_info` declaration
`Applied params: 1024x760`. The equality is recorded as a clue; the
precise meaning of those two additional lines remains unknown.

`gdck_high=200`, `gdck_sta=4`, `gdoe_sta=0`,
`gdsp_offset=80`, `sdoe_mode=line` and `sdoe_sta=-1`
must be kept verbatim until source review establishes their units,
sign conventions and signal-level interpretation. Do not treat
`gdck_high=200` as a voltage or a duration by guesswork.

`framerate` appeared read-only, while the other timing attributes were
readable/writable according to the original directory listing. This
investigation used **read operations only**.

## Safety and future research

- **Never write** `vcom_permanent`, `register_write`, `vni_test`,
  `powerup_sequence`, `powerdown_sequence`, `vcom`, `update` or
  `fill` while merely documenting hardware. Some endpoints are
  world-writable or may program persistent voltage settings.
- Full `timings/*` contents are now captured. Do not write timing values
  to probe the hardware; analyze driver source or use noninvasive measurement.
- Compare the above sequence grammar, 14-column waveform table and
  1024x760 geometry with audited stock/out-of-tree EPDC source, rather
  than mapping unverified numerical meanings into mainline drivers.
- The observed native stack couples Obreey `sw-epdc`, waveform
  `/boot/default.wbf` (ED060XD4) and a TPS65185 backend. The I2C
  client `1-0068` has no standard bound `driver` sysfs link, but
  vendor EPDC logs show a TPS65185 backend selection.
- **Mainline Phase 0 FEL/DFU/UART hardware UAT remains PENDING**.
  This is a stock-firmware investigation, not evidence of a successful
  mainline display or kernel boot.
