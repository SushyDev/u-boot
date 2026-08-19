## Task #5 status: DPU register bus won't come up -- power/clock/interconnect sequencing incomplete

GDSC, DISPCC, both DSI PHYs, and the full DSI panel DCS init are all
solid on real hardware (many repeated successful boots, confirmed via
the status relay). The DPU pixel pipeline itself (SSPP/LM/DSC/PP/CTL/
INTF register writes, implemented in `sheng_mdss_dpu_start()` in
`sheng_mdss_hw.zig`) is fully written, but **every attempt to touch
even a single DPU register (e.g. just `SSPP_SRC_SIZE`) hangs the CPU
indefinitely** -- confirmed via extensive bisection that this is not
about which registers are written, just that the DPU register block
(`mdss_mdp@ae01000`, physical base `0xae01000`) is unreachable at all
from the CPU's AHB config bus until some additional platform sequencing
we haven't fully replicated has happened. `sheng_mdss_probe()` in
`sheng_mdss.c` currently `return 0`s right before this point, so the
device boots reliably instead of hanging -- **do not remove that
early return until the DPU register bus is confirmed reachable**,
or every boot attempt will hang requiring a physical power cycle.

### What's been tried (traced from the real kernel driver, all still
### insufficient -- the DPU register bus still hangs on first touch)

`mdss_mdp@ae01000`'s devicetree node (sm8550.dtsi) declares dependencies
the top-level `mdss` wrapper node doesn't:
```
mdss_mdp: display-controller@ae01000 {
    clocks = <&gcc GCC_DISP_AHB_CLK>, <&gcc GCC_DISP_HF_AXI_CLK>,
             <&dispcc DISP_CC_MDSS_AHB_CLK>, <&dispcc DISP_CC_MDSS_MDP_LUT_CLK>,
             <&dispcc DISP_CC_MDSS_MDP_CLK>, <&dispcc DISP_CC_MDSS_VSYNC_CLK>;
    power-domains = <&rpmhpd RPMHPD_MMCX>;
    interconnects = <&mmss_noc MASTER_MDP ... &mc_virt SLAVE_EBI1 ...>,
                    <&gem_noc MASTER_APPSS_PROC ... &config_noc SLAVE_DISPLAY_CFG ...>;
};
```
(the `mdss` wrapper's own node only needs `DISP_CC_MDSS_AHB_CLK`,
`GCC_DISP_AHB_CLK`, `GCC_DISP_HF_AXI_CLK`, `DISP_CC_MDSS_MDP_CLK` and
`MDSS_GDSC` -- which is why DISPCC/DSI PHY/DSI host, all gated only by
the wrapper's requirements, have worked fine all session without any
of what follows.)

1. **RPMh MMCX power-domain vote** (`power-domains = <&rpmhpd
   RPMHPD_MMCX>`). U-Boot's `drivers/power/domain/qcom-rpmhpd.c` had a
   `stub_desc` (no-op) for `qcom,sm8550-rpmhpd`; wired up a real
   descriptor (`sm8550_desc`, indices `RPMHPD_MMCX`/`RPMHPD_MMCX_AO`
   from `dt-bindings/power/qcom,rpmhpd.h`, both `= &mmcx`/`&mmcx_ao`,
   already-defined structs just never referenced for this chip) --
   this part of the patch is real and can stay. Tried two ways to
   *send* the vote:
   - Via the stock `power_domain_on()` / `rpmh_write()` /
     `rpmh-rsc.c` stack: worked in isolation (confirmed success via
     status relay), but when GDSC/DISPCC/DSI were run first and this
     vote fired afterward, it reliably broke the *unrelated* DSI panel
     DCS-DMA engine (DSI0/1 aren't on MMCX at all) -- suspected culprit
     was `rpmh_rsc_send_data()`'s hardcoded "always use the first
     active TCS slot" (its own comment: "U-Boot is single-threaded ...
     we'll never conflict"), unlike Linux's dynamic free-slot picking.
   - Hand-rolled raw TCS write (`rsc_send_active_write()` in
     `sheng_mdss.c`, bypassing the whole rpmh-rsc/power-domain uclass
     stack, picking whichever TCS slot hardware reports free): same
     failure mode. So the TCS-allocation theory was likely wrong too --
     something about firing *any* RPMh active-only transaction once
     GDSC/DISPCC/DSI are live has a side effect we don't understand.
     Reordering the vote to run *after* DSI panel init (instead of
     before GDSC) avoided breaking DSI, but the DPU register touch
     still hung exactly as before either way.
2. **BCM "MM0" interconnect vote**. Traced
   `drivers/gpu/drm/msm/msm_mdss.c`'s `msm_mdss_enable()`: it calls
   `icc_set_bw()` for `mdp0-mem`/`mdp1-mem` and `cpu-cfg` *before*
   `clk_bulk_prepare_enable()`, with the comment "Several components
   have AXI clocks that can only be turned on if the interconnect is
   enabled (non-zero bandwidth)". Traced the actual topology in
   `drivers/interconnect/qcom/sm8550.c`: `cpu-cfg` terminates at BCM
   `CN0` (`.keepalive = true` -- already permanently voted by
   firmware, explaining why DISPCC/DSI work without any icc code from
   us); `mdp0-mem` (`qnm_mdp`'s only link) terminates at BCM `MM0`
   (NOT keepalive -- nobody votes it). U-Boot has no sm8550
   interconnect provider at all (`drivers/interconnect/qcom/` only has
   `sm8650.c`), so sent a minimal direct BCM vote (`vote_x=vote_y=1`,
   same `BCM_TCS_CMD()` encoding and RSC path as the MMCX vote) for
   `"MM0"` via `cmd_db_read_addr("MM0")`. Still hangs.
3. **`GCC_DISP_HF_AXI_CLK`**. Plain GCC-domain clock branch (offset
   `0x2700c` in GCC at `0x100000`, bit 0, `BRANCH_HALT_SKIP` --
   no polling needed/available) that `msm_mdss_enable()`'s
   `clk_bulk_prepare_enable()` also turns on for the wrapper device,
   which we'd never touched (we only handle `DISP_CC_MDSS_AHB_CLK`/
   `DISP_CC_MDSS_MDP_CLK` in `sheng_mdss_dispcc_init()`).
   `GCC_DISP_AHB_CLK`, the other GCC clock mdss lists, is force-enabled
   unconditionally at `gcc-sm8550.c`'s own probe as a no-API always-on
   clock, so it needs no action from us. Still hangs, even with all
   three of the above stacked together.

### Next leads, not yet tried
- `msm_mdss_reset()` in `msm_mdss.c`: grabs an optional
  `reset_control` and asserts/deasserts it before `msm_mdss_init()`
  does anything else. We've never issued any reset to
  `DISP_CC_MDSS_CORE_BCR` (the `resets = <&dispcc
  DISP_CC_MDSS_CORE_BCR>;` on the `mdss` wrapper node) -- worth
  checking whether this reset line being left in an unexpected state
  (e.g. asserted, or needing a toggle) is what's actually gating the
  DPU register bus, independent of all the power/clock/interconnect
  work above.
- `dpu_kms.c`'s own bind/probe sequencing (component framework, not
  `msm_mdss.c`) hasn't been traced at all yet -- it's a separate
  driver from the `mdss` wrapper and may have its own
  `pm_runtime_resume_and_get()` / OPP-setting steps beyond what
  `msm_mdss_enable()` covers for the wrapper device.
- Consider whether `dpu_9_0_sm8550.h`'s catalog `.vbif` reg
  (`0xaeb0000`, `mdss_mdp`'s SECOND reg range, `reg-names = "mdp",
  "vbif"` -- we've only ever mapped/used the first "mdp" range,
  `0xae01000`) needs any setup before the "mdp" range becomes
  reachable; VBIF (video bus interface) blocks on other Qualcomm SoCs
  sometimes need their own QoS/priority register init before the AXI
  path they arbitrate for becomes live.

## Task #5 continuation guide: DPU + DSC hardware encoder

GDSC, DISPCC, DSI0/DSI1 PHY (PLL locked), and the full DSI host DCS
init blast are all confirmed working on real hardware (see task
status history below). DPU is the last real gap before pixels can
appear, and it's the single largest remaining piece -- bigger than
everything else in this driver combined. This section is the
concrete continuation plan, with real computed values already in
hand so the next pass doesn't need to re-derive them.

### Topology (confirmed from live DPU state, see the "Panel timing"
section above)
Single SSPP (multirect, NOT two separate SSPPs) split into two
parallel rectangles feeding two independent LM -> DSC -> PP -> INTF
chains, one per DSI half:
```
sspp_8 (multirect: rect_0 = left 1524x2032+0+0, rect_1 = right 1524x2032+1524+0)
  -> LM_0 -> DSC engine 0 -> PINGPONG_0 -> INTF_0 -> DSI0
  -> LM_1 -> DSC engine 1 -> PINGPONG_1 -> INTF_1 -> DSI1
CTL_0 orchestrates + flushes all of the above atomically.
```

### DPU sub-block register bases (relative to DPU base 0xae01000,
from `catalog/dpu_9_0_sm8550.h` in the mainline kernel checkout)
| Block | Offset |
|---|---|
| CTL_0 | 0x0 (len 0x494) |
| SSPP VIG0 (sspp_8 equivalent -- verify exact SSPP id against live `sspp[0]=sspp_8` before use) | 0x4000 |
| LM_0 / LM_1 | 0x44000 / 0x45000 |
| DSPP_0 / DSPP_1 (paired with LM_0/1, likely pass-through/bypass for us) | 0x54000 / 0x56000 |
| PINGPONG_0 / PINGPONG_1 | 0x69000 / 0x6a000 |
| DSC engine base (dce_0_0) | 0x80000 (dual hard-slice encoders share this base with their own sub-offsets -- re-derive exact per-slice sub-addressing from `dpu_hw_catalog.c`'s DSC entries before implementing, not fully captured in this pass) |
| INTF_0 / INTF_1 | 0x34000 / 0x35000 |

SSPP/DSC/CTL/INTF register offsets *within* each block (from
`dpu_hw_sspp.c`, `dpu_hw_dsc.c`, `dpu_hw_ctl.c`, `dpu_hw_intf.c`
respectively) were captured during this session but are extensive
(SSPP alone has ~20 registers: SRC_SIZE/XY, OUT_SIZE/XY, SRC0-3_ADDR,
YSTRIDE, SRC_FORMAT, UNPACK_PATTERN, OP_MODE, QOS_CTRL, plus a
parallel `_REC1` set for the second multirect rectangle) -- re-pull
from source rather than trusting a stale copy here, since these
weren't cross-checked against a real register map file (the
generated `.xml.h` headers aren't present in this kernel checkout;
offsets came from the rnndb XML source under
`drivers/gpu/drm/msm/registers/display/`).

### DSC config -- precisely computed for our exact panel mode

`drm_dsc_compute_rc_parameters()` (called from `dsi_host.c`'s
`dsi_populate_dsc_params()`) fills in a DSC config from a *standard*
DSC 1.1 spec table (`rc_parameters_pre_scr`, bpp=8/bpc=8 row) plus a
deterministic formula -- not hand-tuned per-panel values. Since our
config (bpc=8, bpp=8.0/128, slice_width=762, slice_height=16,
convert_rgb=1, native_420/422=0, mux_word_size=48) is entirely fixed,
these were computed offline in Python replicating the exact kernel
algorithm (see git history of this file for the derivation) -- both
for the panel-side PPS (which `sheng_mdss_hw.zig`'s
`nt36532e_dsc_144hz` struct doesn't yet carry) and for DPU's own DSC
hardware encoder registers, which need the *same* values:

```
From rc_parameters_pre_scr[bpp=8,bpc=8]:
  initial_xmit_delay = 512
  first_line_bpg_offset = 12
  initial_offset = 6144
  flatness_min_qp = 3, flatness_max_qp = 12
  rc_quant_incr_limit0 = 11, rc_quant_incr_limit1 = 11
  rc_range_params (range_min_qp, range_max_qp, range_bpg_offset), 15 entries:
    (0,4,2) (0,4,0) (1,5,0) (1,6,-2) (3,7,-4) (3,7,-6) (3,7,-8) (3,8,-8)
    (3,9,-8) (3,10,-10) (5,11,-10) (5,12,-12) (5,13,-12) (7,13,-12) (13,15,-12)

Constants: rc_model_size=8192, rc_edge_factor=6, rc_tgt_offset_high=3,
  rc_tgt_offset_low=3, mux_word_size=48
rc_buf_thresh (14 entries, >>6 of DSC spec's raw values):
  14 28 42 56 70 84 98 105 112 119 121 123 125 126

Computed (drm_dsc_compute_rc_parameters, our exact inputs):
  slice_chunk_size = 762
  groups_per_line = 254
  num_extra_mux_bits = 240
  initial_scale_value = 32
  scale_decrement_interval = 10
  final_offset = 4336
  nfl_bpg_offset = 1639
  slice_bpg_offset = 1154
  scale_increment_interval = 454
  hrd_delay = 1149
  rc_bits = 9192
  initial_dec_delay = 637
  line_buf_depth = 9
```

These same values feed BOTH:
1. The panel-side PPS long-write (`0x90 0x03` DSC-enable + PPS +
   `0x9d 0x01` + framerate ctrl `0xb2`/`0xb3` + exit-sleep + 120ms
   delay + display-on) -- **not yet implemented**: the current
   `nt36532e_init_sequence` table in `sheng_mdss_hw.zig` explicitly
   stops right before this tail (see its own comment), and
   `sheng_mdss_dsi_panel_init()` currently only sends that table,
   never the DSC-enable/PPS/display-on sequence. This means panel
   init as currently implemented is INCOMPLETE even though it tests
   as "successful" (all DMA transactions complete cleanly) -- the
   commands sent are well-formed, there just aren't enough of them
   yet.
2. DPU's own DSC hardware encoder registers (`DSC_RC_MODEL_SIZE`,
   `DSC_RC_BUF_THRESH` x14, `DSC_RANGE_MIN_QP`/`MAX_QP`/`BPG_OFFSET`
   x15 each, `DSC_FIRST_LINE_BPG_OFFSET`, `DSC_BPG_OFFSET`,
   `DSC_DSC_OFFSET`, etc.) -- both DSC engine instances (one per DSI
   half) need identical config since both process an identical-size
   half-slice.

### Immediate next steps, in order
1. Finish the panel init tail (DSC-enable + PPS pack + display-on) in
   `sheng_mdss_dsi_panel_init()` -- this is well-scoped and uses the
   values above directly; genuinely tractable as its own pass.
2. Pull exact SSPP/DSC/PP/CTL/INTF register offsets fresh from source
   (don't trust the block-base table above without re-verification)
   and implement SSPP multirect source config for a 3048x2032
   XRGB8888 framebuffer.
3. Implement DSC hardware encoder config (both instances) using the
   computed values above.
4. Implement dual-INTF timing engines using the panel timing already
   in `sheng_mdss.c` (`SHENG_PANEL_H/V*` constants), synchronized.
5. CTL flush sequencing last -- this is what actually kicks the whole
   pipeline live, get everything else right first.
6. Known separate gap, needed for the panel to respond at all
   regardless of DPU correctness: reset-gpio pulse + vddio/avdd/avee
   regulator enable that `nt36532e_prepare()` does before any DCS
   command. No DT node for this panel exists in U-Boot's devicetree
   (unlike Linux's), so these need to be hardcoded from
   schematic/downstream knowledge rather than read from DT.

## RESOLVED: CONFIG_VIDEO early-boot hang (was blocking all of the below)

Enabling `CONFIG_VIDEO=y` (needed for this driver) made U-Boot hang
completely silently, before *any* console output — confirmed via
memory-breadcrumb instrumentation (temporarily added to
`include/initcall.h`, `common/board_f.c`, `arch/arm/lib/crt0_64.S`,
relayed out through a `/chosen` DT property on a subsequent working
boot, since neither UART nor the USB serial console are available
before the hang) that not even `_main` — U-Boot's generic C-runtime
entry point, before any board/Kconfig-specific code runs — was ever
reached once the binary grew past a certain size.

Root cause: `arch/arm/cpu/armv8/start.S`'s `reset:` path computes a
temporary early stack (for the `save_boot_params()` C call, needed to
capture ABL's `x0` before anything else runs) as
`sp = _start + image_size + 0x10000`. This moves upward as the binary
grows. On this board that pushed the stack into ABL/TrustZone-reserved
memory once `u-boot.bin` grew past a certain size threshold — writing
to it faulted before any exception handler existed to report it,
hence total silence. Confirmed by ruling out an initially-suspected
simple "past 1MB absolute" explanation (an image trimmed to end just
under 1MB still hung identically) — the mechanism is real but the
exact boundary depends on where ABL actually places the image, which
turned out not to be near physical address 0 as first assumed (real
DRAM starts at `memory@a0000000`; the low addresses below that are
densely packed with `nomap` reserved regions per live `dmesg`:
`hyp-region@80000000`, `xbl-sc-region@d8100000`, `smem@81d00000`, etc.
— exactly the kind of territory a size-dependent stack computation
could wander into).

Fix: place that early stack **below** `_start` instead (in the
headroom ABL leaves below the `kernel_offset` load address), which
decouples it from image size entirely rather than just moving the
same problem to a different size threshold. See the comment at
`arch/arm/cpu/armv8/start.S`'s `reset:` label. Also trimmed
`CONFIG_VIDEO_LOGO`/BMP decode support from `configs/sm8550_defconfig`
(unneeded splash-screen code, ~20KB) as a secondary size reduction,
independent of the actual fix.

Confirmed working: `CONFIG_VIDEO=y` + `CONFIG_VIDEO_SHENG_MDSS=y`
together now boot all the way to Linux on real hardware.

# SM8550 "sheng" (Xiaomi Pad 6S Pro) display — live hardware spec

Captured over the exec.sh serial bridge from the booted mainline-derived
Linux kernel (msm_dpu), read-only, while the panel was actively
displaying the login prompt.

## Topology (from dmesg + DRM debugfs state)

This is a **dual-DSI split-link panel**, not single-DSI:

- `msm_dpu ae01000.display-controller: bound ae94000.dsi` (DSI0)
- `msm_dpu ae01000.display-controller: bound ae96000.dsi` (DSI1)
- Single connector `DSI-1` backed by both DSI controllers; DPU state
  shows one SSPP (`sspp_8`) split into two parallel multirect windows:
  `src[0]=1524x2032+0+0` (left half) and `src[1]=1524x2032+1524+0`
  (right half), i.e. each DSI controller/PHY drives one 1524-wide half
  of the 3048-wide panel in lockstep.
- **DSC (Display Stream Compression) is active**: `dsc=103 103` in the
  resource mapping (one DSC engine per half). This is why the DRM mode
  clock (below) is far higher than the physical DSI pixel clock
  measured on `disp_cc_mdss_pclk0/1_clk` — the panel's native pixel
  clock is compressed by the DSC encoder before hitting the DSI PHYs.

This means a bare-metal driver needs **two DSI hosts + two DSI PHYs +
DSC PPS (Picture Parameter Set) programming**, not the single-DSI path
originally scoped in sheng_mdss.c/.zig. Significant scope increase vs.
a typical single-DSI phone panel port.

## Panel timing (from `/sys/kernel/debug/dri/0/state`, crtc-0)

```
mode: "3048x2032": 144 1040058 3048 3190 3194 3286 2032 2058 2060 2198 0x48 0x0
```

Parsed (`drm_mode_debug_printmodeline` order: vrefresh clock hdisplay
hsync_start hsync_end htotal vdisplay vsync_start vsync_end vtotal
flags type):

| Field | Value |
|---|---|
| vrefresh | 144 Hz |
| dot clock (pre-DSC, logical) | 1,040,058 kHz (checks out: htotal×vtotal×144 ≈ 1,040,058,432) |
| hdisplay / htotal | 3048 / 3286 |
| hsync_start / hsync_end | 3190 / 3194 |
| → hfront_porch / hsync_width / hback_porch | 142 / 4 / 92 |
| vdisplay / vtotal | 2032 / 2198 |
| vsync_start / vsync_end | 2058 / 2060 |
| → vfront_porch / vsync_width / vback_porch | 26 / 2 / 138 |
| flags | 0x48 |

Per-half (each DSI controller): 1524×2032 window.

## Live clock rates (`clk_summary`, both DSI0 and DSI1 active)

| Clock | Rate | Notes |
|---|---|---|
| `disp_cc_mdss_pclk0_clk` (DSI0 pixel) | 198,452,930 Hz | post-DSC physical pixel clock |
| `disp_cc_mdss_pclk1_clk` (DSI1 pixel) | 198,452,930 Hz | identical, confirms lockstep dual-DSI |
| `disp_cc_mdss_byte0_clk` (DSI0 byte) | 148,839,697 Hz | |
| `dsi0_phy_pll_out_byteclk` | 148,839,697 Hz | DSI0 PHY PLL byte output |
| `dsi0_phy_pll_out_dsiclk` | 198,452,930 Hz | DSI0 PHY PLL pixel/dsi output |
| `dsi0vco_clk` | 1,190,717,578 Hz | DSI0 PHY PLL VCO (= byteclk × 8) |
| `disp_cc_mdss_esc0_clk` | 19,200,000 Hz | = XO, DSI0 escape clock |
| `disp_cc_mdss_esc1_clk` | 19,200,000 Hz | DSI1 escape clock |
| `disp_cc_mdss_mdp_clk` | 514,000,000 Hz | DPU/MDP core clock |
| `disp_cc_pll0` | 1,542,000,000 Hz | DISPCC source PLL for MDP clock tree |
| `disp_cc_mdss_ahb_clk` | 19,200,000 Hz | AHB bus clock, shared iface for DSI0/DSI1/DPU |
| `disp_cc_mdss_vsync_clk` | 19,200,000 Hz | |
| `gcc_disp_hf_axi_clk` | enabled (rate not read) | GCC-side display AXI, prerequisite bus clock before DISPCC |

DSI1 VCO/byteclk/pclk read as 0 in one `clk_summary` snapshot taken
moments apart from the `pclk1` reading above that showed 198,452,930 —
harmless read-time race in the dump, not a real state change (the
panel stayed on throughout). Treat pclk0 == pclk1 as ground truth.

## Register bases (`/proc/iomem`, dtsi cross-referenced)

Only the top-level MDSS wrapper shows in `/proc/iomem` (sub-blocks are
mapped by the driver without separate `request_mem_region`, so they
don't appear as their own entries):

```
0ae00000-0ae00fff : ae00000.display-subsystem mdss
```

Sub-block bases from `dts/upstream/src/arm64/qcom/sm8550.dtsi` (not
independently re-verified via `/proc/iomem` — no user-run register
pokes were attempted, per read-only device policy):

| Block | Compatible | Base |
|---|---|---|
| MDSS wrapper | `qcom,sm8550-mdss` | `0x0ae00000` |
| DPU | `qcom,sm8550-dpu` | `0x0ae01000` |
| DSI0 host | `qcom,sm8550-dsi-ctrl` | `0x0ae94000` |
| DSI0 PHY | `qcom,sm8550-dsi-phy-4nm` | `0x0ae95000` |
| DSI1 host | `qcom,sm8550-dsi-ctrl` | `0x0ae96000` |
| DSI1 PHY | `qcom,sm8550-dsi-phy-4nm` | `0x0ae97000` |
| DISPCC | `qcom,sm8550-dispcc` | `0x0af00000` (from dtsi, not yet cross-checked against a live read) |

## Panel driver source (ground truth, not reverse-engineered)

Found via `/sys/firmware/devicetree/base/.../panel@0/compatible` =
`"xiaomi,sheng-nt36532e", "novatek,nt36532e"`, matched against
`/Users/sushy/Documents/Projects/sm8550-mainline/drivers/gpu/drm/panel/panel-novatek-nt36532e.c`
(mainline-style out-of-tree panel driver, already in this machine's
kernel source checkout — this is the actual driver the booted kernel
uses, not a guess).

**Panel is dual-DSI, driven as one logical panel**: DCS commands are
issued only to `dsi[0]` (`ae94000`); the DSI host's
`qcom,sync-dual-dsi` devicetree property mirrors every command to
`dsi[1]` (`ae96000`) in hardware. A bare-metal driver can do the same
— issue commands once to the DSI0 host with dual-DSI sync configured,
rather than duplicating the DCS sequence per controller.

**DSC config** (`struct drm_dsc_config`, exact from source):
```
dsc_version_major = 1, dsc_version_minor = 1
slice_height = 16, slice_width = 762, slice_count = 2
bits_per_component = 8, bits_per_pixel = 8 << 4 (= 128, i.e. 8.0 bpp)
block_pred_enable = true
```
PPS is packed with `drm_dsc_pps_payload_pack()` and sent as a DCS long
write (opcode 0x0A / MIPI `mipi_dsi_picture_parameter_set`).

**Panel electrical/reset**: `vddio`, `avdd`, `avee` regulator supplies
(bulk-enabled before reset); reset sequence is
`high(1)->10-11ms->low(3-4ms)->high(3-4ms)->low(15-16ms)`, i.e. two
pulses, panel considered out of reset after the final 15-16ms low
period. 4 DSI data lanes, `MIPI_DSI_FMT_RGB888`,
video mode + burst + non-continuous clock + LPM flags.

**144Hz mode timings** (matches the live crtc-0 dump exactly — cross-
confirms task #2's earlier live capture was correct):
hdisplay 3048, hsync_start +142, hsync_end +4, htotal +92 (i.e.
hfront=142, hsync=4, hback=92); vdisplay 2032, vsync_start +26,
vsync_end +2, vtotal +138 (vfront=26, vsync=2, vback=138). Other
vrefresh modes (60/90/120/etc.) exist in the source with different
horizontal/vertical blanking — only 144Hz is needed for U-Boot.

**Init DCS sequence** (sent to DSI0 only, mirrored to DSI1 by
`qcom,sync-dual-dsi`): see `sheng_mdss_hw.zig`
`nt36532e_init_sequence` — transcribed verbatim from
`sheng_tianma_init_sequence()` in the panel driver, including the
144Hz-branch framerate control writes (`0xb2 0x91`, `0xb3 0x40`), DSC
enable (`0x90 0x03`) before the PPS long-write, exit-sleep +120ms
delay, then display-on.

## Not yet captured (next pass — tasks #3/#4)

- GDSC register offset/bit and PLL lock-detect bit positions, and the
  DISPCC PLL0 (1542MHz) -> byteclk/pclk divider chain — these come
  from `drivers/clk/qcom/dispcc-sm8550.c` and `gdsc.c` in the mainline
  source tree already checked out locally, not from live register
  reads (writing/probing an unclocked GDSC register from a live kernel
  risks the SError crash noted in project guidance, so this is a
  source-reading task, not a live-poke task).
- DSI PHY (`dsi-phy-4nm`) PLL programming sequence — from
  `drivers/phy/qcom/phy-qcom-dsi-phy-*` in the same source tree.
- `qcom,sync-dual-dsi` hardware mechanism in the DSI host controller
  itself (how the DSI0 host mirrors to DSI1 at the register level) —
  from `drivers/gpu/drm/msm/dsi/dsi_host.c`.

## Scope impact

Original driver scaffold (sheng_mdss.c / sheng_mdss_hw.zig, task #1)
assumed a single DSI controller + single PHY. Real hardware requires:

1. Two DSI hosts (0xae94000, 0xae96000) and two DSI PHYs (0xae95000,
   0xae97000) programmed in lockstep.
2. DSC encoder + PPS setup on both DPU DSC engines before the pixel
   pipeline can be enabled — without DSC, the physical pclk the PHYs
   are actually locked to (198.45 MHz) won't carry the panel's real
   3048×2032@144 pixel rate.
3. Panel init DCS sequence not yet located.
