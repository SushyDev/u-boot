# sheng MDSS display driver

Native U-Boot display driver for the Xiaomi Pad 6S Pro ("sheng"),
SM8550. Brings the panel up from cold and renders U-Boot's console on
it, then tears the pipeline down before handing off to Linux.

## Hardware

| | |
|---|---|
| SoC | SM8550, MDSS with DPU 9.0 |
| Panel | nt36532e, 3048x2032, 144Hz |
| Link | dual DSI, bonded (`qcom,sync-dual-dsi`) |
| Compression | DSC 1.1, 8bpc, 8.0bpp, 2 slices of 762x16 |
| Backlight/bias | KTZ8866 x2 over I2C |

Both DSI hosts carry half the picture each. Commands are mirrored to
both controllers from one DMA buffer rather than split, matching what
the panel driver does.

### Block addresses

Named in `sheng_mdss_regs.h`, taken from `sm8550.dtsi`. U-Boot does not
instantiate the DPU/DSI sub-nodes as separate udevices, so they are not
walked from the device tree.

From DSI6G v3 onward a `HW_VERSION` register at offset 0 shifts every
other DSI register down 4 bytes. That shift is folded into
`SM8550_MDSS_DSI0_BASE` / `..DSI1_BASE`, so register offsets elsewhere
are the raw documented ones.

## Bring-up order

Each step depends on the ones above it. `sheng_mdss_probe()` in
`sheng_mdss.c` drives it; the register work is in `sheng_mdss_hw.zig`.

1. **GDSC off, then on.** Collapse the MDSS power domain and settle
   1ms, so the digital logic starts from power-on defaults rather than
   whatever ABL left mid-configured.
2. **MDSS core reset.** `DISP_CC_MDSS_CORE_BCR`, dispcc+0x8000 bit 0.
   The kernel pulses this first thing in `msm_mdss_init()`, before any
   clock is parsed. It resets the whole MDSS wrapper; each DSI host's
   own `DSI_RESET` only covers that host.
3. **GDSC enable.** Everything below needs this rail.
4. **MM0 bandwidth vote** over RPMh. MM0 is the one BCM in the DPU's
   path to DRAM without a keepalive floor.
5. **GCC_DISP_HF_AXI_CLK.** The AXI data-path clock. Nobody else
   enables it for us; `GCC_DISP_AHB_CLK` is force-on at GCC probe.
6. **DISPCC.** PLL0, then AHB, MDP, LUT and VSYNC branches. See the
   clock tree below.
7. **UBWC.** MDSS wrapper compression settings.
8. **Regulator votes** for the PHY rails: ldoe1 880mV, ldoe3 1200mV,
   smpg3 600mV.
9. **DSI PHYs.** Reset both, init master then slave, then start both
   PLLs. pclk/byte/esc mux from the PHY PLL, not DISPCC's PLL0, which
   is why they come after this rather than in step 6.
10. **DSI link clocks** in DISPCC, now that the PHY PLLs are locked.
11. **DSI hosts** to video mode.
12. **Graceful panel restart.** ABL hands over a live, configured
    panel. Send Display Off + Sleep In, drop the rails, hold them down
    ~1.08s, then power back up and pulse reset. A DDIC that loses power
    without Sleep In can latch a state a later reset does not clear.
13. **Panel init.** 87 DCS commands plus the 128-byte PPS, paced 2ms
    apart.
14. **DPU.** SSPP, layer mixers, merge3d, pingpong, DSC encoders, CTL
    and the INTF timing engine. Video starts here.
15. **Hand the framebuffer to the video uclass** — see below.

### Timing

3048x2032. hfp 142, hbp 92, hsync 4; vfp 26, vbp 138, vsync 2.

## Clock tree

Only the part that matters:

```
XO 19.2MHz
 └─ DISP_CC_PLL0    L=0x50 (80), alpha=0x5000 (0.3125)
    │               19.2 * 80.3125 = 1542 MHz
    └─ mdp_clk_src  /3  -> 514 MHz   (RCG CFG src_sel=1, div=5)
       └─ MDP_CLK_CBCR

XO 19.2MHz
 └─ ahb_clk_src     /1  -> 19.2 MHz

DSI0/1 PHY PLL
 └─ byte / pclk / esc branches
```

`mdp_clk` at 514 MHz is load-bearing. At the wrong rate the link
starves: all four `DLN*_HS_FIFO_EMPTY` bits set in `FIFO_STATUS`
(0x11111210 rather than 0x00001210) and the panel shows nothing.

## Framebuffer

24.8 MB at `0xa3200000`, XRGB8888, 1 MB above the DSI DMA scratch
buffer and clear of the next reserved region.

**Stride is 12288, not 3048*4 = 12192.** `sheng_mdss_dpu_start()`
programs `SSPP_SRC_YSTRIDE0` as `ALIGN(3048, 32) * 4`, so the DPU
fetches at that pitch. `video_post_probe()` only computes a
`line_length` when the driver has not set one, so the driver must set
it. With the naive value every console line lands 96 bytes short of
where the DPU reads and text shears progressively down the screen —
while a solid fill still looks perfect.

Format is `VIDEO_X8R8G8B8`: memory order is B,G,R,A. Left unset it
defaults to `VIDEO_UNKNOWN` and `video_clear()` paints white.

## KTZ8866

Two chips on i2c1. Each does **two** jobs:

- **Backlight** — brightness over `BL_BRIGHTNESS`, driven by
  `sheng_ktz8866_backlight_init()`.
- **Display bias** — `LCD_BIAS_CFG1` (register 0x09 = 0x9F) latches
  AVDD/AVEE.

The two are easy to conflate and the second one bites. GPIOs 30/31
*gate* the bias rails; they do not create them. Dropping the GPIOs
without also clearing `LCD_BIAS_CFG1` over I2C leaves the rails up, the
DDIC never loses power, and the power-cycle does nothing.

## Init order in U-Boot

| slot | what |
|---|---|
| `board_late_init()` | `sheng_ktz8866_backlight_init()` — runs before the video probe |
| video uclass probe | `sheng_mdss_probe()` |
| `board_preboot_os()` | `sheng_mdss_teardown()` |

The teardown must be in `board_preboot_os()`. `board_late_init()`
finishes *before* `main_loop()`, so a teardown there destroys the
display before the console banner, bootcmd or the boot menu ever draw.

Relevant config:

- `CONFIG_VIDEO_DAMAGE=y` is required, not an optimisation.
  `CONFIG_CYCLIC` is off, so `video_sync()` is never rate-limited and
  every `putc` syncs. Without damage tracking that is a 24 MB flush per
  character.
- `stdin=nulldev,button-kbd`, nulldev **first**. A bare `button-kbd`
  that fails to probe leaves no stdin and the board will not boot.

## C / Zig boundary

`sheng_mdss.c` holds what has to be C: `U_BOOT_DRIVER`, `of_match` and
the video-uclass plumbing are linker-section macros and driver-model
structs that cannot reasonably be expressed in Zig.

Two four-line wrappers also stay C, around `cmd_db_read_addr()` — a
U-Boot API that resolves an RPMh resource name to an address. Calling
it from Zig would put a U-Boot dependency inside the Zig unit, which is
what this split exists to avoid. The lookup is C; the register write
that follows is Zig.

`sheng_mdss_hw.zig` holds the register work: DISPCC and PLL
programming, DSI PHY and host bring-up, the DCS command engine, DSC,
the DPU pipeline, SMMU setup and teardown. It is built to a freestanding
aarch64 object and linked in; it calls back into U-Boot only for
`udelay`, `flush_dcache_range` and `timer_get_us`.

`sheng_mdss_diag.zig` holds the register sweeps and audits, built only
under `CONFIG_VIDEO_SHENG_MDSS_DEBUG`. It is ~20KB of reference tables
that a normal boot has no use for, and the Zig object is compiled
unconditionally, so leaving them in `sheng_mdss_hw.zig` put them in
every image. It duplicates the constants it needs rather than importing
them: Zig compiles each file to its own object, and importing would
emit `sheng_mdss_hw.zig`'s exports twice.

Building it needs `zig` on PATH.

## Edits to generic U-Boot

Board code lives in `board/qualcomm/sheng/`, selected by
`CONFIG_SYS_BOARD="sheng"`, and hooks in through `qcom_late_init()`,
`board_preboot_os()` and `ft_board_setup()` — all pre-existing
extension points. Three edits to shared files remain:

| file | why it stays |
|---|---|
| `arch/arm/cpu/armv8/start.S` | Early stack moved below `_start`. There is no hook that runs before the stack exists. Image growth pushed the temp stack into ABL/TZ memory, which corrupts the running firmware before any board code gets control. |
| `drivers/misc/qcom_geni.c` | Loads protocol firmware into `qcom,geni-se-i2c-master-hub` wrappers. The driver already does this for directly-matched wrappers and simply missed this compatible; the gap is generic, not sheng-specific. |
| `drivers/power/domain/qcom-rpmhpd.c` | Adds the SM8550 power-domain descriptor. Ordinary new-SoC support that belongs in the driver. The display driver does not use it — it sends its own RPMh commands — but the descriptor is correct and other SM8550 consumers need it. |

`cmd/sheng_trap.c` is gone. It was a bring-up reachability probe built
unconditionally into every board's `cmd/`, and the display now answers
the question it existed for.

## Debug channel

Off by default. `CONFIG_VIDEO_SHENG_MDSS_DEBUG=y` turns it on.

The board has no reachable UART, so there is no console during probe.
Two channels replace it:

- **Blackbox** — a DRAM ring written by the Zig side. Every record is
  flushed to the point of coherency as it is written, so the log
  survives a hard hang.
- **Environment** — `sheng_*` variables relayed into `/chosen` by
  `ft_board_setup()`, readable from Linux under
  `/proc/device-tree/chosen/`. CBSIZE-capped, so large payloads belong
  in the blackbox.

With the symbol off every macro in `sheng_mdss_debug.h` discards its
arguments, so the hardware reads that feed them cost nothing.

**Never put a call with a required side effect inside one** — it will
not run in a normal boot. Assign to a local, then log the local. This
has already cost one latched panel: the KTZ8866 bias clear was written
as a macro argument and silently stopped running.

To find how far a boot got with no channel at all: paint the
framebuffer a flat colour from the point in question — a DRAM write
plus `flush_dcache_range`, never MMIO — and look at the panel.

## Things that will bite you

- **Anything at a fixed DRAM address must be reserved in LMB.** This
  driver allocates its framebuffer at `0xa3200000` rather than through
  `video_reserve()`, so nothing else knows the region is in use.
  `board_late_init()` (INITCALL 758) makes nine `lmb_alloc()` calls and
  `memcpy()`s the FDT into one of them, well after the panel starts
  scanning out at INITCALL 729. Without an explicit reservation LMB
  hands out the framebuffer and the display fills with garbage.

  It fails *intermittently*: the addresses LMB returns depend on how
  much memory U-Boot has already used, so a build that changes the
  image size by a few KB can move an allocation onto the framebuffer
  with no other change. The framebuffer, the DSI DMA scratch and the
  debug blackbox are all reserved for this reason. Add a reservation
  for any new fixed-address region.
- **Never read DPU/MDSS registers from generic U-Boot code.** Once the
  display is down the MDSS is unclocked and the read wedges the AHB
  bus. Recovery is fastboot, not a reboot.
- **Do not touch KTZ8866 EN once the panel is up.** Driving it low
  drops AVDD/AVEE and the DDIC never recovers. Backlight init is
  enable-only, deliberately.
- **Clear `LCD_BIAS_CFG1` over I2C to power the panel down.** The
  GPIOs alone will not do it.
- **`video_set_flush_dcache(dev, true)` must run before probe
  returns.** `video_flush_dcache()` returns early until it is set, so
  the uclass never pushes console writes out of the CPU cache and the
  DPU scans out stale DRAM. The framebuffer then provably holds the
  console output while the panel shows black.
- **Set `plat->base`, `line_length` and `format` before probe
  returns.** Anything after the `return` is dead code; three separate
  things have been lost that way.
- **A `.bind` hook hangs the board**, even one doing nothing but a
  single struct write. The framebuffer is self-allocated in `.probe`.
- **No `.video_sync` op.** The uclass already flushes
  `priv->fb..fb_size`. A driver op that flushed the whole 24 MB blanked
  the panel during the boot menu's once-a-second countdown redraw.
- **SMMU stage-1 passthrough** (`SCTLR.M` clear) for the MDSS stream.
- **DCS commands are paced 2ms apart.** Faster and the panel drops
  them.
- **Bump `sheng.b=` in `board/qualcomm/sheng.env` on every build.** It
  is the only way to tell which image actually booted.
- **`flash-uboot.sh` and `fastboot-flash.sh` write `boot_a`/`boot_b`
  only.** Writing `xbl*`/`abl*` ends the device permanently.
