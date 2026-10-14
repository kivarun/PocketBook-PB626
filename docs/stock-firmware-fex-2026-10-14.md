# PB626 restored stock firmware — script.bin / FEX analysis (2026-10-14)

This is a **stock firmware field observation**, not a successful FEL-only mainline Linux UAT. The live device was not flashed or repartitioned. See [stock UART notes](stock-firmware-uart-2026-10-14.md) for the capture context.

## Extraction, checks and artifact

* Source: `/boot/script.bin` on the restored 16 GB internal microSD, read via the stock shell over UART (`base64 /boot/script.bin`, framed between `PB626_FEX_BEGIN` and `PB626_FEX_END`). The CP2104 was connected at 115200 8N1.
* UART extraction yields **32,980 bytes** exactly.
* SHA-256: `9371685d47dbec3f9cf3f4450cc33a7d4d0eaf4a1f88e5cb0298a148c2664c59` — matches both `/boot/script.bin` and `/boot/script0.bin` as independently hashed on the device.
* Decoded artifact: [`hardware/stock-script.fex`](../hardware/stock-script.fex). The complete original binary is archived separately (`pb626-script.bin`), not embedded in this text-only patch.
* Legacy Allwinner FEX binary header: **70 sections**, version words **1, 2** (format 1.2), header `filesize` field **0**, 616 entries: 317 integers, 32 strings, 151 GPIO records, 116 null records. All records fit inside the original file; value records occupy contiguous storage. The reconstructed FEX was **round-trip verified byte-for-byte** against the input using a matching local record parser/encoder (retaining the original binary header/offsets). This is strong evidence for the decoded fields, but it is **not** a test with the upstream `sunxi-fexc` binary.
* The FEX is documentary evidence, **not an image to flash**, and contains generic vendor/template values that can disagree with actual runtime hardware.

## Confirmed configuration *stored in FEX* (not all independently proven active)

| Subsystem | FEX values | Interpretation / evidence limit |
| --- | --- | --- |
| Serial | `[uart_para] uart_debug_port=1`, TX `PG3`, RX `PG4`; `[uart_para1] uart_used=1` | Consistent with the working UART and the mainline DTS. `uart_force_debug` separately mentions UART0 (`PF2`/`PF4`); **do not infer** the meaning of the `/mnt/secure/debug_mode` file from it. |
| DRAM | `dram_clk=408`, `dram_bus_width=16`, `dram_size=512` | Runtime Boot0 printed `dram size =256`; FEX's `512` is **not** proof of installed RAM. |
| Internal SD | `mmc2_para.sdc_used=1`, `sdc_cmd=PC6`, `sdc_clk=PC7`, data `PC8-PC11` | Consistent with the mainline DTS description of internal microSD on MMC2. |
| External SD | `mmc0_para.sdc_used=1`, pins `PF0-PF5`; MMC1 disabled | Expected A13 SD topology. |
| I²C buses | TWI0 `PB0/PB1`, TWI1 `PB15/PB16`, TWI2 `PB17/PB18` | Pin mux and use flags, not an I²C scan. |
| Main PMIC | `pmu_used=1`, TWI0 address `0x34`, battery capacity **1500 mAh** (configured) | Consistent with AXP209 DTS; capacity is configuration, not battery measurement. |
| RTC | `rtc_name="pcf8563"`, TWI1 address `0x51` | Matches previously researched DTS. |
| E-Ink PMIC | `tps65185_used=1`, TWI1 address `0x68` | PMIC model named by the stock configuration; verify physically/runtime before wiring assumptions. |
| E-Ink PMIC GPIO | Wake `PD18`, VCOM `PD19`, power-up `PE7`, power-good `PE6`, INT `PB10` | Candidate sequencing/control map for a later E-Ink driver. |
| E-Ink control | `lcd_eink_vpos=PB10`, UD `PD14`, RL `PD2`, VGG `PD18`, VCOM `PD19` | Some signals are also described in the PMIC section; hardware semantics need independent verification. |
| Panel SPI | `[spi_board0] modalias="panel_spi"`, SPI2, CS0, max 100,000 Hz | Device identification differs from the SPI NOR representation in the mainline DTS; investigate rather than assume equivalence. |
| Touch | `[ctp_para] ctp_name="ft5x_ts"`, TWI2 address `0x24`, interrupt `PG11`, reset `PB3`, power `PE5` | **Discrepancy resolved at driver-family level:** the working stock kernel binds `cyttsp4_i2c_adapter` at I2C2/0x24 and creates `cyttsp4_mt` (Cypress TrueTouch v4+). The FEX `ft5x_ts` is not the active driver. Exact chip model remains unverified. See [runtime observations](stock-firmware-runtime-hardware-2026-10-14.md). |
| Frontlight | `[BACKLIGHT] bl_ctrl=PB4`, PWM `PB2`, `lcd_pwm_freq=10000` | The observed stock boot also logs frontlight type 3. |
| Buttons | `[GPIOKEY_para]` `PG9`, `PG10` | GPIO key inputs. |
| LED | `[LED_para] GPIO_LED_PIN=PE8` | GPIO control pin. |
| USB WiFi | `usb_wifi_used=1`, `usb_wifi_usbc_num=1` | Consistent with internal USB WiFi on host controller 1. |

## Contradictions and limitations requiring attention

1. **DRAM size:** stock boot measured **256 MiB** while `dram_size=512` appears in FEX. Do not use the FEX figure to size the RAM layout. The existing Phase 0 RAM map is based on the real-device 256 MiB boundary.
2. **Panel geometry:** FEX has `lcd_x=258`, `lcd_y=620`; stock EPDC boot log instead reports an active 1024×758 framebuffer and ED060XD4 waveform. The FEX LCD fields appear to be template/unused or relate to another stage; their exact significance is unknown.
3. **Touch model:** `ft5x_ts` in FEX versus *Cypress TMA445* in `docs/phase0-investigation.md`. The actual stock I²C driver is `cyttsp4_i2c_adapter`; inspect real IRQ/reset/power wiring before implementing touch.
4. **SPI function:** stock FEX `panel_spi` and mainline SPI NOR description may represent different interpretations of the same controller/chip-select. A read-only hardware probe/source inspection is needed.
5. **Header branding:** `[product] machine="A13-EVB-V1.0"` is a generic board string; the physically observed PCB label is `IDIG E028 PB626-V1.6`.
6. **FEX provenance:** equality of `script.bin`/`script0.bin` hashes does not establish exactly which file Boot1 loads. The live boot's script base address alone does not identify the source filename.

## Recommended next investigation

After a fresh boot, inspect the stock kernel's read-only sysfs I²C bindings and available device-driver information to resolve the **touch model and PMIC**, without trying arbitrary I²C writes. Then run the already-prepared Phase 0 FEL UAT independently; keep the real-device mainline UAT marked **PENDING** until its acceptance criteria are met.