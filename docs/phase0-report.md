# Phase 0 report — FEL-only bring-up for PocketBook PB626 / Touch Lux 3

Status: **build complete and verified; device-side UAT pending** (needs the
PB626 with a UART adapter connected; see `docs/phase0-uat.md`). Everything
that can be validated without the physical device has been validated, see
"Local verification" below.

## 1. Starting SHA

`fdfa31f` — "Bootstrap reproducible Docker build environment with smoke
tests and CI"

## 2. Final SHA

The final SHA is the tip of the branch at delivery time — the last commit
in the ordered list below (this report commit). Its exact hash is recorded
in the delivery note accompanying this report.

## 3. Ordered commit list

| # | Commit | Subject |
|---|--------|---------|
| 0 | `fdfa31f` | Bootstrap reproducible Docker build environment with smoke tests and CI (pre-existing) |
| 1 | `5fc8a8c` | Phase 0: record PB626/A13 support investigation and patch policy |
| 2 | `46c967c` | Phase 0: build environment for kernel/U-Boot and host FEL tools |
| 3 | `508c299` | Phase 0: board configs (U-Boot defconfig, default env, kernel fragment, FIT, initramfs) |
| 4 | `4731bc0` | Phase 0: canonical build and FEL boot scripts |
| 5 | `94d0bc9` | Phase 0: README and UAT procedure |
| 6 | (this commit) | Phase 0: build results and report |

## 4. Exact upstream sources (pinned)

| Component | Version / commit | Source | Integrity |
|---|---|---|---|
| U-Boot | `v2026.07` = `ece349ade2973e220f524ce59e59711cc919263f` | github.com/u-boot/u-boot (tag) | tag-checked |
| Linux | `6.12.110` (latest 6.12 LTS) | cdn.kernel.org tarball | pinned sha256 `8cee19e1…c4c`, verified on every build (cross-checked against cdn.kernel.org `sha256sums.asc`) |
| sunxi-tools | `d7bbd172a5da601a08f94479de308c6fb714a19a` (2026-06-08; no newer tag than v1.4.2) | github.com/linux-sunxi/sunxi-tools | commit-checked by `scripts/build.sh` |
| BusyBox | `1.36.1` | busybox.net tarball | sha256 `b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314` |
| dfu-util | `0.11` | sourceforge tarball | sha256 `b4b53ba21a82ef7e3d4c47df2952adf5fa494f499b6b0b57c58c5d04ae8ff19e` |

No floating branches are used anywhere.

## 5. External patches and why

**None.** `patches/README.md` documents that no upstream source patches are
required: the PB626 DT is mainline (Linux v5.7+, synced verbatim into
U-Boot dts/upstream), the UART1/PG3-PG4 console mux and DDR3 auto-scan are
upstream U-Boot features, and DFU-to-RAM is upstream (`CONFIG_DFU_RAM`).
Board specifics are isolated in `config/` (defconfig, default env, kernel
fragment, FIT, initramfs).

## 6. Toolchain (from the `pb626-build-env` image, Debian stable/trixie)

* cross: `arm-linux-gnueabihf-gcc (Debian 14.2.0-19) 14.2.0` (armhf, hard-float)
* host gcc: `14.2.0-19`; GNU Make `4.4.1`
* `dtc 1.7.2`, `mkimage 2025.01`, libusb-1.0, libgnutls, libfdt 1.7.2
* build timestamp pinned via `SOURCE_DATE_EPOCH=946684800` and
  `KBUILD_BUILD_USER/HOST`; the kernel build number and the UTS_VERSION
  timestamp are pinned too (`KBUILD_BUILD_VERSION=1`,
  `KBUILD_BUILD_TIMESTAMP` rendered from `SOURCE_DATE_EPOCH`) — without
  them a full kernel rebuild stamps the wall clock and an incrementing
  counter into the zImage. Two consecutive **full** rebuilds (fresh
  kernel build tree) produce **byte-identical** artifacts (verified).

## 7. Produced artifacts (build/artifacts/, SHA256; fix-pass rebuild, see §13)

```
f4990b374fcf91f377fd7151286d12f37667bde6636983fc0de653b845fb6b7e  u-boot-sunxi-with-spl.bin   (600,880 B)
b4d3a3ac9893db056673ac90daab96d993227bdc8e016c156117d6ed17cb7878  zImage                      (5,632,440 B)
20244270db5c810b6b5976d788aa0e09bd77fe58cab7cc04aad0d83b74a7d448  sun5i-a13-pocketbook-touch-lux-3.dtb (19,116 B)
41a31920e680a2fff6286aa03b3b372a98f09f69e34c16993e76db17b24a9dc7  initramfs.cpio.gz           (1,040,623 B)
fc563a6bfc43da484698ad93a071ee7431ed16811291436979dcf8174ce9c0c4  boot.itb                    (6,694,293 B)
```

Host tools (build/host-tools/):

```
9da998c69ec44a0bc9d77ff5fe0da4171202baef237466625be985f10802728a  sunxi-fel
00ebd568f7709c7cb1a1796f7d515221d8a2373e5eb7b6eb344d7e2d26d218a9  dfu-util
```

## 8. Exact FEL boot command

Canonical (one script; with `--uart DEV` it runs the boot in the
background while an interactive `picocom` session owns the terminal and
logs to `build/log/uart.log`):

```sh
./scripts/fel-boot.sh --uart /dev/ttyUSB0
```

Primitive steps it performs:

```sh
./build/host-tools/sunxi-fel ver                          # must report soc=00001625 (A13)
./build/host-tools/sunxi-fel uboot build/artifacts/u-boot-sunxi-with-spl.bin
# wait until: ./build/host-tools/dfu-util -l shows exactly one
#   Found DFU: [1f3a:1010] ... alt=0, name="boot"
# (the FEL device itself is 1f3a:efe8 and has no DFU interface)
./build/host-tools/dfu-util -a boot -D build/artifacts/boot.itb   # FIT -> RAM 0x42000000
./build/host-tools/dfu-util -a boot -e                            # detach -> U-Boot runs bootm
```

Notes:
* `dfu-util -e -R` must **not** be used: with U-Boot, a bus reset after the
  detach makes U-Boot reset the board and the downloaded image is lost.
* UART: UART1, PG3=TX / PG4=RX, 115200 8N1, 3.3 V logic. `console=ttyS0,115200n8`
  (kernel `ttyS0` = uart1 via the DT alias). Adapter wiring: PB626 GND→GND,
  TX→adapter RX, RX→adapter TX, and **VCC NOT CONNECTED** — see
  `docs/phase0-uat.md` section 0 (never connect the board's 3.3 V pad to
  the adapter).

### Canonical RAM map (`config/ram-map.sh`, verified by `scripts/check-phase0.sh`)

| Region | Range | Size |
|---|---|---|
| DRAM (A13, auto-detected) | `0x40000000`–`0x50000000` | 256 MiB |
| Decompressed kernel (AUTO_ZRELADDR target) | `0x40008000` | <16 MiB |
| FIT download buffer (DFU alt `boot`; `bootm` input) | `0x42000000`–`0x44000000` | 32 MiB declared, ~6.7 MiB used |
| zImage load/entry | `0x44000000`–`0x44800000` | 8 MiB declared |
| DTB load | `0x44800000`–`0x44900000` | 1 MiB declared |
| Initramfs load | `0x45000000`–`0x46000000` | 16 MiB declared |
| U-Boot runtime reserve (relocated U-Boot, heap/stacks, bootm-relocated fdt/ramdisk) | `0x4E000000`–`0x50000000` | 32 MiB |

The zImage loads at `0x44000000` — not `0x42000000`, which is the FIT
blob the kernel is copied out of — so the `bootm` source/destination
never overlap. Kernel, DTB and initramfs destinations are pairwise
disjoint, everything authored stays below the U-Boot runtime
reservation, and `scripts/check-phase0.sh` verifies the whole layout
against `config/ram-map.sh` and fails the build otherwise.

## 9. UART boot log

Pending the device-side UAT run (`build/log/uart.log` is recorded by
picocom's `--logfile` in `scripts/fel-boot.sh --uart DEV`). What is
expected at each stage:

```
SPL: (no banner until DRAM init) ...
U-Boot 2026.07-... (with "DRAM: 256 MiB")
U-Boot prompt suppressed: bootdelay=0 runs bootcmd -> DFU wait
dfu-util download, detach, then "bootm" -> Linux
[    0.000000] Booting Linux on physical CPU 0x0
Machine model: PocketBook Touch Lux 3
...
PB626 Phase 0 FEL-only Linux - initramfs UART shell ready
PB626-fel:/#
```

## 10. UAT result

Device-side UAT: pending — `docs/phase0-uat.md` gives the deterministic
procedure. Build-side verification performed here (see Local verification).

### Local verification (no hardware attached)

1. `scripts/build.sh` runs clean end-to-end inside `pb626-build-env`;
   source pins verified on every run: u-boot/sunxi-tools at the exact
   pinned commit with a clean worktree (tracked files unmodified, no
   unexpected untracked files), and linux/busybox/dfu-util by pinned
   tarball sha256 (the linux build tree is re-extracted from the
   verified tarball and stamped, never taken from elsewhere).
2. Two consecutive full rebuilds produce byte-identical artifacts.
3. Artifact sanity:
   * SPL eGON.BT0 header valid, SPL = 24 KiB (fits A13 SRAM-A1);
   * `boot.itb` FIT parses with `mkimage -l`: kernel/fdt/ramdisk entries
     with sha256 hashes, config `pb626-fel`, bootargs
     `console=ttyS0,115200n8 loglevel=7 rdinit=/init`;
   * DTB decompiles; model = "PocketBook Touch Lux 3";
   * U-Boot binary contains exactly the designed default env
     (`bootdelay=0`, `bootcmd=dfu 0 ram 0; bootm 0x42000000`,
     `dfu_alt_info=boot ram 42000000 2000000`) and the key configs
     (CONS_INDEX=2, ENV_IS_NOWHERE, DFU_RAM, MUSB_GADGET);
   * kernel `.config` verified (8250 console, MMC, AXP209 MFD/battery/
     charger/power/ADC, gpio-keys, LRADC, initrd);
   * static Phase 0 gates (`scripts/check-phase0.sh`) pass: canonical
     non-overlapping RAM map (`config/ram-map.sh` vs `config/fit.its`
     and the default env), strict FEL (A13, soc 0x1625) and DFU
     (1f3a:1010, alt 0 "boot") identity checks, electrically safe UART
     wiring documentation with a truly interactive `--uart` session,
     and truthful repository status (hardware UAT pending).
4. Initramfs smoke test: extracted and executed under `qemu-arm`
   (reports `armv7l`); `/init`, static busybox and all needed applets
   (sh, mount, dmesg, cat, ls, setsid, cttyhack, reboot, poweroff)
   present.

### Why the storage constraint holds by construction

* U-Boot: `CONFIG_ENV_IS_NOWHERE` + full default-env replacement; bootcmd
  only runs `dfu`/`bootm` (RAM). Nothing in the chain addresses MMC/NAND
  for writing; the internal microSD (mmc2) and external slot (mmc0) are
  only probed read-only by the kernel and are never mounted by `/init`.
* FIT + kernel + initramfs are executed purely from RAM.

## 11. Remaining hardware-support gaps

| Feature | Status / plan |
|---|---|
| e-ink display (ED060XD4, 1024x758) | out-of-tree (Ondrej Jirman's tree at xff.cz/kernels); no mainline sunxi e-ink driver |
| Touch (Cypress TMA445 on i2c2) | no mainline driver; DTS has the bus enabled, no device node |
| WiFi (RTL8188EUS on internal USB) | in-tree `r8188eu` staging driver exists; needs `rtl8188eufw.bin` + AXP209 LDO3 rail wiring in DT |
| TP65185 PMIC (charging, e-ink rails) | no mainline driver; battery state via AXP209 only |
| Suspend/resume | not supported anywhere for this device |

## 12. Recommendation for Phase 1

1. **Execute the UAT first** (the only unverified part of Phase 0).
2. SD-card dualboot for daily-driver experiments, keeping the internal
   microSD untouched: the mainline DTS already supports both slots; boot
   U-Boot from the external SD (mmc0) while the PocketBook system stays on
   mmc2. This also removes the per-boot FEL dependency.
3. Kernel-side: add the touch panel node once a driver is available
   (probe i2c2 at runtime; vendor firmware reports via `/sys`), keep the
   AXP209 battery/charger reporting.
4. e-ink: port/adapt Ondrej's out-of-tree display support (reviewed and
   pinned), or evaluate the mainline-first path (backlight + U-Boot
   console only) until the e-ink stack is mainlined.
5. WiFi: ship `rtl8188eufw.bin`, enable `r8188eu`/`rtl8xxxu`, verify the
   LDO3 (vcc-wifi) regulator sequencing.

## 13. Phase 0 review-fix pass record

Scope kept closed: no Phase 1 work, no new boot paths, one canonical
build and FEL boot path, `ENV_IS_NOWHERE`, RAM-only boot, no MMC writes.

Fixes applied after the review (findings 1–8 of the review pass):

1. UART wiring documentation made electrically safe: explicit cross
   wiring with `PB626 VCC -> NOT CONNECTED`, prominent warning, and a
   two-wire passive-capture note (`docs/phase0-uat.md` section 0).
2. `fel-boot.sh --uart` is now a genuinely interactive session
   (boot steps in the background, `picocom` in the foreground,
   `--logfile` records the session); no read-only capture is described
   as interactive anymore.
3. Canonical non-overlapping RAM map in `config/ram-map.sh`; zImage
   load/entry moved to `0x44000000` so the FIT download buffer and the
   kernel destination no longer overlap; statically verified by
   `scripts/check-phase0.sh` (see the map table in section 8).
4. Source pin verification strengthened: git sources need the exact
   pinned commit with a clean worktree; linux/busybox/dfu-util need the
   pinned tarball sha256 on every run; the linux build tree is
   re-extracted from the verified tarball and stamped.
5. README/report status language now distinguishes "build and static
   verification: complete" from "real-device UAT: pending".
6. DFU detection requires exactly VID:PID 1f3a:1010 with alt setting 0
   named "boot" and fails closed when ambiguous.
7. FEL identity requires both `soc=00001625` and `(A13)`.
8. `scripts/check-phase0.sh` regression gates cover all of the above
   (run by `scripts/build.sh` before every build and by CI).

Additional reproducibility defect found and fixed during the pass: the
zImage embedded the wall clock and an incrementing build counter in
`UTS_VERSION` (`KBUILD_BUILD_VERSION`/`KBUILD_BUILD_TIMESTAMP` unset);
both are now pinned and two consecutive full rebuilds were verified
byte-identical (`zImage b4d3a3ac…`, `boot.itb fc563a6b…`).

The final RAM map, the exact FEL/DFU identity checks and the UART
interaction method are documented in sections 8 and above; the final
SHA of this fix pass is recorded in the delivery note.
