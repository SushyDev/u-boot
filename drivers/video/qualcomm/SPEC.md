## Task #5 continuation (2026-08-19 evening session): DISP_CC_MDSS_CORE_BCR reset + bisection in progress

Implemented the one lead from "Next leads, not yet tried" below that hadn't
been touched at all: `msm_mdss_reset()` in the real driver
(`drivers/gpu/drm/msm/msm_mdss.c`) asserts/deasserts `DISP_CC_MDSS_CORE_BCR`
as the *very first* thing `msm_mdss_init()` does, before GDSC or any clock.
Traced the exact bit/offset from `disp_cc_sm8550_resets[]` in
`drivers/clk/qcom/dispcc-sm8550.c` (mainline checkout at
`/Users/sushy/Documents/Projects/sm8550-mainline`): offset `0x8000` relative
to dispcc base (`0xaf00000`), bit 0 (`qcom_reset_map` with only `.reg` set,
so `.bit` defaults to 0). `qcom_reset.c`'s generic reset controller does
`regmap_update_bits` (assert=write 1, deassert=write 0) with a readback
after each; `msm_mdss_reset()` holds the assert for `msleep(20)` ("tests
indicate reset has to be held for some period of time... one frame").
Confirmed offset `08000` exists and is read/write-accessible in the live
device's own regmap (`/sys/kernel/debug/regmap/af00000.clock-controller/
access`) before ever writing to it.

Implementation: `sheng_mdss_core_reset(dispcc_base)` in `sheng_mdss_hw.zig`
(assert bit0, `udelay(20000)`, deassert, with a dummy readback after each
write mirroring `regmap_read()`), called first thing in
`sheng_mdss_probe()` before `sheng_mdss_gdsc_enable()`. New status-relay
slot `SHENG_MDSS_STATUS_MDSS_RESET` added (now 9 stages total -- also
fixed `board.c`'s `ft_board_setup()` relay copy length, which was
hardcoded to 24 bytes/6 slots when it should've already been 32 for the
prior 8-stage array -- a pre-existing latent bug, now 36 bytes for 9).

### D-cache breadcrumb bug found and fixed (unrelated to the reset itself,
### but blocked diagnosing it)

First attempt at reading the failure post-mortem (warm-reset + read
`CONFIG_PRE_CON_BUF_ADDR` = `0x81200000` from a diagnostic Linux boot) came
back all zeros. Root cause: this board runs with D-cache ON
(`CONFIG_SYS_DCACHE_OFF` is not set in `sm8550_defconfig`), so the
`sheng_mdss_log()`/`sheng_mdss_status_set()` breadcrumb writes -- plain
`volatile u32 *` stores into normal cacheable DRAM -- could sit dirty in a
cache line indefinitely; if the CPU hard-hangs on the very next
instruction, that dirty line never reaches physical DRAM. Fixed by adding
`sheng_mdss_breadcrumb_flush()` (calls `flush_dcache_range()` +
`dsb()`) after every write in all three functions.

**Even with that fix, a second post-hang read still came back all zeros.**
This means the D-cache theory, while real and worth fixing, was not the
(sole) blocker -- DRAM plainly isn't retaining content across the
warm-reset recovery path used on this hardware (most likely XBL reclaims/
clears `xbl-ramdump-region@81200000` early in its own boot before Linux
ever runs, independent of self-refresh). **Conclusion: the DRAM-breadcrumb
post-mortem technique is a dead end on this hardware as currently used.**
Don't spend more time on it without first finding a way to read memory
*before* XBL/U-Boot's own next boot stage touches it (e.g. real hardware
debug UART, JTAG -- out of scope for now).

Also investigated three mystery `/chosen` properties present on every
boot (`sheng,preconsole-buf`, `sheng,initcall-breadcrumb`,
`sheng,main-reached-stash`) on the theory they might be a simpler existing
relay -- confirmed via `git log --all -S` that none of these names appear
*anywhere* in this repo's history. They're injected by something outside
this tree (likely ABL/XBL itself, or a lost out-of-tree experiment) and
`sheng,preconsole-buf`'s content is binary, not ASCII console text -- not
useful, don't chase this further.

### Bisection in progress (reverted to the proven method instead: build
### images that stop early and see if they reach Linux, rather than trying
### to read state after a hang)

All `.output/boot-core-bcr-*.img` below have `sheng_mdss_core_reset()`
running first, then stop at increasing points to isolate whether adding
the reset call broke anything that used to work standalone:

| Image | Runs | Result |
|---|---|---|
| `boot-core-bcr-isolate.img` | reset only | **booted** |
| `boot-core-bcr-gdsc.img` | reset + GDSC | **booted** |
| `boot-core-bcr-dispcc.img` | reset + GDSC + DISPCC | **booted** |
| `boot-core-bcr-dsiphy.img` | reset + GDSC + DISPCC + both DSI PHYs | **booted** |
| `boot-core-bcr-panel.img` | + DSI panel init (= old known-good stopping point, now with reset first) | **booted** |
| `boot-core-bcr-dpuread.img` | + MMCX/BCM/GCC vote + single DPU read (exact config that always hung before) | **HUNG** |
| `boot-core-bcr-safe.img` | reset + GDSC + DISPCC + DSI PHY/panel init only (early return restored before MMCX) | booted -- current safe default, matches `sheng_mdss.c`'s committed state |

**Result: `DISP_CC_MDSS_CORE_BCR` does NOT fix the DPU register bus hang.**
Bisection cleanly isolated this -- the reset toggle itself and everything
through DSI panel init is proven safe standalone, but the moment
MMCX+BCM+GCC+DPU-read run (identical to the pre-reset-toggle hang), it
hangs exactly as before. The reset call is harmless but not the answer.
`sheng_mdss.c` is back to the safe stopping point (`return 0` restored
right before the MMCX vote) as of this log entry -- do not remove that
return blind.

### Next leads (in priority order, none tried yet this session)

1. **XPU/TrustZone SMC unlock.** Reads hang on XPU access-control
   violations the same way an unclocked bus does -- this hasn't been ruled
   out as distinct from the power/clock theory the whole session so far
   has assumed. Grep the live kernel and mainline source for `qcom_scm`
   calls anywhere in the MDSS/DPU probe path (`msm_mdss.c`, `dpu_kms.c`,
   `drivers/firmware/qcom/qcom_scm.c`) -- if the real driver/firmware
   makes an SMC call to hand DPU register access to the non-secure world
   before touching it, and we've never replicated that, this would
   explain a hang that's completely invisible to power/clock sequencing
   no matter how correct.
2. **MDP RCG rate sanity check.** `disp_cc_mdss_mdp_clk` reads 514MHz on
   the live (different-boot-path) captured `clk_summary` -- so an
   unconfigured/zero RCG rate is *probably* not it, since our
   `sheng_mdss_dispcc_init()` targets the same 514MHz via the same
   PLL0/RCG path -- but worth double-checking our own RCG programming
   actually lands correctly (read back `MDP_CLK_SRC_CMD_RCGR`'s CFG
   register after `sheng_mdss_dispcc_init()` and confirm src_sel/div
   match, since we've never actually verified this readback, only that
   `clkBranchEnable()`'s CBCR polling succeeded).
3. **VBIF (`0xaeb0000`).** `mdss_mdp`'s second `reg` range
   (`reg-names = "mdp", "vbif"`), never touched -- may need its own QoS/
   priority/halt-state register init before the "mdp" range becomes
   reachable, per how VBIF blocks behave on other Qualcomm SoCs.
4. **`dpu_kms.c`'s own probe/bind sequencing.** Distinct from
   `msm_mdss.c` (component framework, not the wrapper device) -- diff
   for `pm_runtime_resume_and_get()`/OPP-setting steps beyond what
   `msm_mdss_enable()` covers, never traced at all.

### Lead #1 (XPU/SMC) ruled out from source; lead #2 (RCG rate) confirmed
### correct via readback; **lead #4 turned up something concrete: wrong
### MMCX corner**

Lead #1: no `qcom_scm`/SMC calls exist anywhere in `msm_mdss.c` or
`dpu_kms.c` -- the only SMC usage in the whole `drm/msm` tree is Adreno
GPU and HDMI HDCP. If there's an XPU gate, mainline Linux's own driver
doesn't unlock it either, so there's nothing to replicate from source.
Not chasing further without hardware debug access (JTAG/UART).

Lead #2: added a log entry (`SHENG_LOG_MDP_RCG_CFG_READBACK`) reading back
`MDP_CLK_SRC_CMD_RCGR`'s CFG register (dispcc-relative `0x80d8+0x4`) right
after `sheng_mdss_dispcc_init()`, on a build that stops at the
already-proven panel-init point (`boot-mdp-rcg-check.img`, no warm-reset
needed). Result: `0x105` -- decodes to src_sel=1 (PLL0) and src_div=5
(`/3`), exactly matching `rcg2ConfigureHidOnly()`'s intended 514MHz
programming and the live `clk_summary` capture. **Confirmed correct, not
the bug.** (Side finding: the status array's last slot, `SHENG_MDSS_
STATUS_DPU`, read back as `0` instead of the expected NOT_REACHED
sentinel on this same boot, despite that code path being provably
unreachable -- likely U-Boot's own verbose console-text pre-buffering
encroaching into the tail of the `+0x3000` status region before
`ft_board_setup()` runs. The status/log breadcrumb region isn't as
isolated from console text as its placement comment assumed; worth
moving further from the console buffer's growth range if this becomes a
real problem later.)

While reading `dpu_kms.c` for lead #4, found `dpu_kms_init()` calls
`dev_pm_opp_set_rate(dev, max_freq)` on the DPU's own platform device,
*before* `dpu_kms_hw_init()`'s first register read. This is a DPU-scoped
OPP/interconnect vote, entirely separate from `msm_mdss_enable()`'s
generic wrapper-device icc handling we'd already tried to replicate.
Traced `mdss_mdp`'s own `operating-points-v2 = <&mdp_opp_table>` in
`sm8550.dtsi`: the `opp-514000000` entry (our exact MDP clock rate)
requires `required-opps = <&rpmhpd_opp_nom>`. `rpmhpd_opp_nom` is
labelled `opp-256` in the rpmhpd OPP table, i.e.
`RPMH_REGULATOR_LEVEL_NOM = 256`.

**Found the bug:** `sheng_mdss_mmcx_power_on()` was picking the *first
nonzero* corner from `cmd_db_read_aux_data("mmcx.lvl", ...)` -- i.e. the
lowest available voltage corner, unconditionally -- rather than the
corner matching the actual required performance level. Cross-checked
against the real driver: `rpmhpd_set_performance_state()` in
`drivers/pmdomain/qcom/rpmhpd.c` picks the *smallest corner whose level
is >= the requested level* (`for (i...) if (level <= pd->level[i])
break;`), clamping to the max corner if none qualifies. We were
under-volting MMCX for the 514MHz clock rate we actually request --
a very plausible root cause for a bus that clocks correctly (confirmed
via lead #2's readback) but still hangs on first register access
(insufficiently-margined internal logic locking up rather than a clean
bus timeout).

**Fix applied:** `sheng_mdss_mmcx_power_on()` now finds the smallest
corner where `levels[i] >= RPMH_REGULATOR_LEVEL_NOM (256)`, mirroring
`rpmhpd_set_performance_state()` exactly (including the clamp-to-max
fallback). Added `SHENG_LOG_MMCX_LEVEL_PICKED` to log the actual level
value at the chosen corner for verification. Re-enabled the path through
MMCX/BCM/GCC/DPU-read. Built as `.output/boot-mmcx-nom-corner.img` --
**HUNG**, same spot as before. Correct clock rate + correct MMCX voltage
corner still isn't enough. `sheng_mdss.c` restored to the safe stopping
point again.

### Lead #4 (dpu_kms.c trace) found something new and concrete: two DPU
### clocks never enabled at all

Traced `dpu_runtime_resume()` in `dpu_kms.c`: `clk_bulk_prepare_enable
(dpu_kms->num_clocks, dpu_kms->clocks)` runs before `dpu_kms_hw_init()`
ever reads the DPU HW_VERSION register (`readl_relaxed(dpu_kms->mmio +
0x0)`). `dpu_kms->clocks` is parsed from `mdss_mdp@ae01000`'s **own**
devicetree node -- `clock-names = "bus","nrt_bus","iface","lut","core",
"vsync"` (six clocks) -- which is separate from the `mdss` wrapper
node's clock list that `msm_mdss_enable()` handles. We had only ever
enabled `"iface"` (`DISP_CC_MDSS_AHB_CLK`) and `"core"`
(`DISP_CC_MDSS_MDP_CLK`) in `sheng_mdss_dispcc_init()`. **`"lut"`
(`DISP_CC_MDSS_MDP_LUT_CLK`) and `"vsync"` (`DISP_CC_MDSS_VSYNC_CLK`)
were never touched at all.** This is the first lead that targets
something specific to the DPU sub-block's own requirements rather than
the wrapper's (which explains why DISPCC/DSI have always worked fine
without them -- the wrapper doesn't need these two).

Offsets from `dispcc-sm8550.c`:
- `disp_cc_mdss_mdp_lut_clk`: halt_reg=enable_reg=`0x8018`, bit0,
  `BRANCH_HALT_VOTED`. A plain branch off `disp_cc_mdss_mdp_clk_src` --
  the *same* RCG already configured for the MDP core clock, so just
  another CBCR enable, no new RCG programming.
- `disp_cc_mdss_vsync_clk`: halt_reg=enable_reg=`0x8024`, bit0,
  `BRANCH_HALT`. Sourced from its own `disp_cc_mdss_vsync_clk_src` RCG
  (`cmd_rcgr=0x80f0`, HID-only like AHB). Target 19.2MHz (XO
  passthrough, div=1) -- matches the live `clk_summary` capture in
  SPEC.md (`disp_cc_mdss_vsync_clk = 19,200,000 Hz`).

**Fix applied:** `sheng_mdss_dispcc_init()` in `sheng_mdss_hw.zig` now
also enables `MDP_LUT_CLK_CBCR` (direct branch enable) and configures +
enables `VSYNC_CLK_SRC_CMD_RCGR`/`VSYNC_CLK_CBCR` (XO src, div=1),
after the existing AHB/MDP setup.

**Also added** (per the "zero-risk diagnostic" idea): a read of the
MDSS wrapper's own HW_REV register (`0xae00000+0x0`, already proven
reachable all session) logged right before the existing DPU read, so a
successful boot's log would show whether the wrapper stayed reachable
right up to the DPU touch. Caveat: this only yields information if the
boot *succeeds* enough to reach Linux and relay the log -- the
DRAM-breadcrumb dead end (above) means we still can't distinguish
"which read hung" from a hang itself, only from a successful boot's log
contents.

**Result: HUNG again.** Since we can't read a hung boot's log, built a
clean isolation image instead (`boot-wrapper-read-isolate.img`): runs
MMCX/BCM/GCC, then reads *only* the wrapper (`0xae00000`), stopping
before ever touching the DPU block at all. **Also HUNG.** This is a
major pivot: the wrapper -- reachable via DISPCC/DSI all session,
never gated by anything DPU-specific -- now hangs too, in a build that
runs our hand-rolled RSC votes (MMCX + BCM MM0) *before* touching it.

This fits a pattern already documented earlier in this file: "bisection
showed DSI panel init reliably hangs when it runs *after* this [MMCX]
vote, even though DSI0/1 aren't on the MMCX rail at all" -- which is
literally why DSI panel init got reordered to run *before* MMCX in the
first place. The new wrapper hang is consistent with the same
mechanism: our `rsc_send_active_write()` (the hand-rolled RSC/TCS
transaction backing both `sheng_mdss_mmcx_power_on()` and
`sheng_mdss_bcm_vote()`) may have a bug that breaks *any* subsequent
AHB access to this address space, regardless of target -- not
MDSS/DPU-specific gating at all. Every previous "hangs on DPU touch"
result is confounded by MMCX/BCM having *just run* immediately before
it; we have never tested touching new territory in this address range
*without* RSC in the picture.

**Decisive test built:** `boot-wrapper-read-no-rsc.img` -- reads the
wrapper immediately after DSI panel init, with `sheng_mdss_mmcx_power_on()`
and `sheng_mdss_bcm_vote()` **never called at all** on this path. If
this survives, the RSC vote mechanism itself is the real bug, not
DPU/VBIF/clock gating -- and the fix is in `rsc_send_active_write()`'s
TCS trigger sequence, not anywhere near the DPU. **Result: BREAKTHROUGH --
reached Linux.** Logged `WRAPPER_READ = 0x90000001`, a real, structured
HW_VERSION value (not garbage/all-1s/all-0s) -- clean confirmation the
read genuinely succeeded. **The MDSS wrapper was never natively gated by
hardware. Every "hang" observed all session on any register in this
address space was confounded by `rsc_send_active_write()` (the
hand-rolled RSC/TCS transaction backing `sheng_mdss_mmcx_power_on()`/
`sheng_mdss_bcm_vote()`) having just run immediately before the touch
that "hung".** The bug is in the RSC vote mechanism itself, not
DPU/VBIF/clock gating -- reframes the entire task #5 investigation.

**Immediate next test built:** `boot-dpu-read-no-rsc.img` -- same
position (right after DSI panel init, RSC never called), but reads the
DPU block (`0xae01000+0x24000`) instead of the wrapper. Two outcomes:
- **Survives:** MMCX/BCM were never actually required at all (ABL/
  firmware already left the necessary rails/votes active) -- the RSC
  code can likely be dropped entirely, and the path is clear to move on
  to the actual pixel pipeline (panel DCS tail, SSPP multirect, DSC
  engines, INTF, CTL flush -- see the continuation guide below).
- **Hangs:** the DPU specifically does need the MMCX/MM0 vote (unlike
  the wrapper), and the real bug is inside `rsc_send_active_write()`
  itself (TCS slot selection via `RSC_DRV_STATUS`, the `RSC_DRV_ID`-
  based register-layout version selection, or the completion polling)
  -- next step would be single-stepping that function's correctness
  against `rpmh_rsc_send_data()`/`__tcs_buffer_write()` in
  `rpmh-rsc.c` far more carefully than the original port did.

**Result: BREAKTHROUGH CONFIRMED -- reached Linux.** Logged
`DPU_PRE_WRITE_READ = 0x00000000` (`SSPP_SRC_SIZE`, an unconfigured
register -- a plausible cold-boot default, not a fault indicator) with
`RET=1`. **The DPU register bus was reachable the entire session.**
Root cause of every single hang since task #5 began:
`rsc_send_active_write()` (backing `sheng_mdss_mmcx_power_on()` and
`sheng_mdss_bcm_vote()`) breaks subsequent AHB access to the whole
`0xae00000`-`0xae01000+` address range, regardless of target. MMCX and
BCM MM0 were never actually required -- ABL/firmware already leaves
whatever's necessary active. This whole session's power/clock leads
(reset toggle, MMCX corner, MDP LUT/VSYNC clocks) were real
correctness fixes worth keeping, but none of them were ever the actual
blocker.

### Immediate next step: drop RSC entirely, proceed to the real pixel pipeline

`sheng_mdss_probe()` should skip `sheng_mdss_mmcx_power_on()` and
`sheng_mdss_bcm_vote()` entirely (leave `sheng_mdss_gcc_disp_hf_axi_clk_
enable()` -- that's a plain register write, not RSC-based, unrelated to
this bug). With RSC out of the picture, re-enable
`sheng_mdss_dpu_start()` itself (still never tested this session) and
bisect from there if needed -- it's a much larger register-write surface
than the single read just proven safe, so don't assume it's automatically
fine. If it hangs, that's a new, distinct problem from everything above.

If/when `rsc_send_active_write()` is ever needed again for something
else, its bug (TCS slot selection, RSC_DRV_ID-based register-layout
version selection, or completion polling -- see the function itself in
`sheng_mdss.c`) still needs fixing; nothing in this session's testing
diagnosed *why* it corrupts subsequent AHB access, only *that* it does.

### RSC removed, sheng_mdss_dpu_start() enabled for the first time this session

`sheng_mdss_probe()` cleaned up: dropped the `sheng_mdss_mmcx_power_on()`/
`sheng_mdss_bcm_vote()` calls entirely (kept `sheng_mdss_gcc_disp_hf_axi_
clk_enable()` -- plain register write, unrelated), removed the early
return, and let `sheng_mdss_dpu_start()` (SSPP/LM/DSC/CTL/INTF register
writes, `sheng_mdss_hw.zig`, never actually executed on real hardware
before this build) run for real. Built as `.output/boot-dpu-start-no-
rsc.img`.

**This is a much larger, previously fully-untested write surface** --
every single register write in `sheng_mdss_dpu_start()` is new territory,
unlike the single reads proven safe above. A hang here would be a
genuinely new problem, not a continuation of the RSC bug.

**Result: HUNG**, inside `sheng_mdss_dpu_start()`'s own
`DPU_TEST_STOP_STAGE=1` boundary (already the minimum stage in a
pre-existing staged-bisection mechanism in `sheng_mdss_hw.zig` -- i.e.
within the ~19-register SSPP config block alone, before LM/DSC/CTL/INTF
are ever touched).

### The real signature: reads work, writes don't -- independent of RSC

This reproduces this file's own original header comment ("confirmed by
bisection: even a lone SSPP_SRC_SIZE write... hangs identically"), but
that earlier test still had RSC running first, so it was equally
confounded by the bug just found above. Built a maximally isolated test:
a single write to `SSPP_SRC_SIZE` (`dpu_base+0x24000`), RSC fully
removed, followed by a readback -- both logged
(`boot-dpu-single-write-no-rsc.img`).

**Result: HUNG.** The exact same register that read back cleanly as
`0x0` earlier this session (`boot-dpu-read-no-rsc.img`, RSC also
removed) hangs the instant it's *written* to, RSC or no RSC.

**This is the real signature of the whole task #5 problem, now isolated
for the first time**: reads to the DPU register block succeed
unconditionally; writes hang unconditionally; power/clock/RSC sequencing
was never the actual blocker (every earlier "successful DPU write" claim
in this file's history was pre-RSC-discovery and likely never actually
happened -- a write attempt would have hung the same way, RSC-corrupted
bus or not, so those old writes never ran either).

This is the classic signature of an **XPU (execution/access-control
unit) write-protection violation** -- reads permitted, writes blocked
until something unlocks the range -- not a power-gating problem at all.
Lead #1 (XPU/TrustZone), ruled out earlier for lack of source evidence
(no `qcom_scm` calls anywhere in `msm_mdss.c`/`dpu_kms.c`), is revived
with much stronger *empirical* evidence than before. If real, the
implication is serious: mainline Linux's driver doesn't call any SMC to
unlock this, meaning whatever unlocks DPU writes for a normal
Android/GKI boot happens entirely in ABL/XBL or TrustZone, invisible to
any OS-level source we have access to. This may be a genuine hard wall
for what's achievable without binary reverse-engineering of ABL/TZ
images or real hardware debug access (JTAG) -- a materially different
category of problem than everything solved so far this session.

`sheng_mdss.c` restored to the safe stopping point (built as
`boot-safe-post-rsc.img`) -- do not remove that early return blind.

### Where task #5 actually stands now

Confirmed and fixed this session (all worth keeping regardless of what's
next): `DISP_CC_MDSS_CORE_BCR` reset toggle, correct MDP RCG clock rate
(was already correct), correct MMCX voltage corner, `DISP_CC_MDSS_MDP_
LUT_CLK`/`DISP_CC_MDSS_VSYNC_CLK` enablement, and -- the big one --
removal of the RSC vote mechanism that was corrupting all subsequent AHB
access. None of these were ever the actual blocker. The actual blocker,
newly isolated: **DPU register writes hang unconditionally; DPU register
reads never do.** Next step, if pursued: look for any XPU/access-control
register exposed anywhere in the SoC's own address space (GCC/TCSR/
security-config blocks sometimes expose these), or accept this as the
edge of what's reachable from pure Linux-source-driven reverse
engineering.

### Unrelated bug found the hard way: sheng_mdss_bind() was missing entirely

After the DPU-write-hang finding above, tried to build the next "safe"
default (`boot-safe-post-rsc.img`: GDSC/DISPCC/DSI/panel-init +
GCC_DISP_HF_AXI_CLK, stopping before ever touching DPU) -- **this HUNG
too, even after a genuine full power cycle** (ruling out accumulated
state from prior crashes). This was alarming since the code path looked
identical to two builds that already booted successfully.

Traced it by diffing exactly what differed from the last known-good
build: this was the first RSC-free build that actually set
`uc_priv->xsize/ysize/bpix` and `plat->size` (matching the panel's real
3048x2032 XRGB8888 mode) before returning. Confirmed the GCC clock write
itself was NOT the cause (`boot-gcc-hf-axi-isolate.img`, isolating just
that one call, booted fine).

Root cause: U-Boot's video uclass (`drivers/video/video-uclass.c`)
calls `alloc_fb()` from `video_post_bind()` -- which runs at **bind**
time, before `.probe` -- to reserve the actual framebuffer DRAM from the
`CONFIG_VIDEO` carve-out. `alloc_fb()` only does anything if
`plat->size` is already nonzero at that point (`if (!plat->size) return
0;`). `sheng_mdss.c`'s `U_BOOT_DRIVER(sheng_mdss)` never defined a
`.bind` op -- `plat->size` was only ever set inside `sheng_mdss_probe()`,
far too late. So `alloc_fb()` always saw size=0, never reserved real
memory, and `plat->base` stayed unset. `video_post_probe()` (which runs
*after* `.probe`, once plat->size and uc_priv->xsize/ysize are set)
unconditionally calls `video_clear(dev)` -- a ~25MB write loop starting
at whatever garbage `plat->base` was left at, not a real reserved DRAM
region. **This is a pure U-Boot driver-plumbing bug, entirely unrelated
to DPU/GCC/RSC/XPU or any hardware gating investigated above.** It just
happened to only manifest once a build finally got far enough to set a
real framebuffer size for the first time.

**Fix applied:** added `sheng_mdss_bind()`, setting `plat->size =
3048*2032*4` at bind time (hardcoded, matching the values
`sheng_mdss_probe()` sets on `uc_priv` -- can't derive one from the
other since `uc_priv` isn't allocated yet at bind time), wired up via
`.bind = sheng_mdss_bind` in the `U_BOOT_DRIVER` table. Built as
`boot-fb-bind-fix.img`, stopping right before `sheng_mdss_dpu_start()`
(still disabled -- separate, already-confirmed problem).

**Result: HUNG again**, even after a genuine full power cycle. The
`.bind` fix alone wasn't sufficient.

### 1-pixel isolation test

Two candidate explanations remain for `video_post_probe()`'s automatic
`video_clear()` hanging: (a) `alloc_fb()`'s computed `plat->base` lands
outside actually-populated/mapped DRAM (the real ~25MB carve-out might
not fit within whatever `CONFIG_VIDEO`'s pre-relocation `video_reserve()`
actually reserved, or the reserved region itself might sit above real
RAM), or (b) something about the sheer size of the write (or its
alignment/cache behavior) is the problem rather than the address being
wrong. Isolate by shrinking `plat->size` to a single pixel (4 bytes,
1x1 XRGB8888) in both `sheng_mdss_bind()` and `sheng_mdss_probe()`
(kept in sync -- `video_post_probe()` derives `fb_size` from
`uc_priv->xsize/ysize`, so both must shrink together or the clear will
still overrun the tiny buffer). Also logs `plat->base` itself via the
existing log mechanism for a sanity check on the actual address if this
boots. This time `video_post_probe()` is allowed to actually run (no
early return before it) -- that's the entire point of the test. Built
as `boot-fb-1px-test.img`.

- **Boots:** the mechanism is sound; the real 3048x2032 size specifically
  is what's failing (wrong carve-out size, alignment, or genuinely
  landing outside mapped memory only at that scale) -- next step is
  checking `CONFIG_VIDEO`'s actual reserved carve-out size against the
  needed ~25MB, and where in the real memory map it lands.
- **Still hangs:** the problem is in `.bind`/`alloc_fb()`'s mechanism
  itself, independent of size (e.g. `plat->base` computed from an
  entirely wrong/unmapped base pointer, or a null-pointer-adjacent bug
  in how `sheng_mdss_bind()` accesses `dev`/`plat` this early).

**Result: HUNG.** 1-pixel size also hung -- rules out size entirely.
Reasoned further and got the real answer the safe way instead of
guessing blind: added an early, unconditional `return -EIO;` as
`sheng_mdss_probe()`'s very first line (before touching any hardware at
all), verified directly in `drivers/core/device.c` that DM's
`uclass_post_probe_device()` (which calls `video_post_probe()`) is only
invoked if `.probe` returns 0 -- so this build genuinely could not reach
`video_post_probe()`/`video_clear()` no matter what.

**Result: HUNG ANYWAY.** This eliminated the entire video framework as
a suspect -- the hang was inside our own driver code (`sheng_mdss_bind()`
or `sheng_mdss_probe()`), not U-Boot's video-uclass machinery at all.

### Root cause found: sheng_mdss_bind() itself, not its logic

Bisected with two more builds:
- `boot-ghost-probe.img`: `.bind` still wired up (setting `plat->size`),
  `.probe` fails as its literal first line, zero hardware touched at
  all. **HUNG.**
- `boot-no-bind-ghost.img`: `.bind` removed from the `U_BOOT_DRIVER`
  table entirely, `.probe` still fails immediately. **BOOTED.**

Conclusive: `sheng_mdss_bind()` itself -- not its logic (`dev_get_uclass_
plat(dev)` + one struct field write, about as trivial as C gets) -- is
what hangs. This maps onto the *same class* of pre-relocation fragility
this board already has documented history with: see "RESOLVED:
CONFIG_VIDEO early-boot hang" further down this file, where U-Boot's
generic pre-relocation early-stack computation (`arch/arm/cpu/armv8/
start.S`) was found to wander into ABL/TrustZone-reserved memory once
the binary grew past a size threshold. `.bind` runs during a
pre-relocation DM bind pass (per video-uclass.c's own doc comment:
"Before relocation each device is bound") -- exactly the fragile
pre-relocation window. The earlier fix decoupled the early stack from
image size, but evidently didn't make touching uclass platdata safe at
that stage for this specific path; the *why* wasn't chased further
(would need real hardware debug access to see the actual fault), only
confirmed empirically that avoiding `.bind` entirely sidesteps it.

**Fix applied:** removed `.bind` from `U_BOOT_DRIVER(sheng_mdss)`
entirely (deleted `sheng_mdss_bind()`). Instead, self-allocate the
framebuffer directly in `sheng_mdss_probe()` (stable, post-relocation
context) by setting `plat->base` manually -- `alloc_fb()` in
`video-uclass.c` explicitly supports this per its own comment ("Allow
drivers to allocate the frame buffer themselves": `if (plat->base)
return 0;`), completely bypassing the fragile bind-time reservation
path. New `SHENG_MDSS_FB_ADDR = 0xa0200000` (2MB into real DRAM, clear
of `SHENG_MDSS_DSI_DMA_SCRATCH` at 1MB in, ~24.8MB needed, ending well
below the next known reserved region). `uc_priv->xsize/ysize` restored
to the real 3048x2032 (no longer need the 1-pixel shrink -- that was
only ever needed to test the size-based `alloc_fb()` path we're no
longer using). `video_post_probe()` allowed to run this time (no early
return). Built as `boot-fb-self-alloc.img`.

**Result: BOOTED.** Framebuffer self-allocation works. `sheng_mdss_dpu_
start()` stays disabled (separate, already-confirmed problem: DPU
writes hang unconditionally, see above) until that's resolved.

### Cross-checked against real downstream Qualcomm/Xiaomi kernel source
### (Xiaomi_Kernel_sheng, map220v/sm8550-mainline, Xiaomi-pad-6s-pro-
### Linux-1 -- cloned to scratchpad for this) -- confirms no missing
### step, and the firewall boundary is now pinned exactly

Cloned and searched Qualcomm's actual downstream kernel fork for this
device (much closer to what real production firmware runs than
mainline). Findings, all consistent with -- not contradicting -- this
session's mainline-based work:

- **No SCM/XPU/TrustZone call anywhere in display/MDSS code in this
  tree either** (only Adreno GPU and HDMI HDCP use `qcom_scm`, same as
  mainline). Two independent kernel trees now agree: there is no
  OS-level SMC call that unlocks this.
- **Kalama's (SM8550's actual codename) reset map** (`disp_cc_kalama.c`)
  has only the one `DISP_CC_MDSS_CORE_BCR` (`0x8000`) we already toggle
  -- no separate MDP-specific BCR exists, ruling out that specific
  theory.
- **`dpu_mdss_enable()`** (downstream's `msm_mdss_enable()` equivalent)
  writes UBWC config (`UBWC_STATIC`/`UBWC_CTRL_2`/`UBWC_PREDICTION_MODE`,
  offsets `0x144`/`0x150`/`0x154`, all within the *wrapper's* own
  register window) based on a switch on the HW_REV value read back --
  but only for chip generations `DPU_HW_VER_{500,501,600,620,720}`. Our
  chip's actual HW_REV (`0x90000001`, already captured earlier this
  session) decodes to major version 9 -- none of those cases match, so
  this switch is a dead end for us specifically, though it does confirm
  wrapper-space writes based on HW_REV are a real, precedented pattern
  in Qualcomm's own driver evolution.
- **`dpu_kms_hw_init()`** in this downstream tree does the same thing
  in the same order as mainline: map registers, enable clocks via the
  same ops chain, read the version register. No hidden step.
- **The wrapper's actual known register map** (per both kernel trees)
  is genuinely just `HW_VERSION` (`0x0`), `HW_INTR_STATUS` (`0x10`),
  and (older chips only) the three UBWC registers above -- no
  "access control"/"permission"/"master config" register anywhere in
  either tree's knowledge of this address range.

### The firewall boundary, pinned precisely

Per the devicetree (re-confirmed directly): `mdss` (wrapper) has
`power-domains = <&dispcc MDSS_GDSC>` -- exactly the GDSC we already
enable, poll, and have proven live (DSI/DISPCC writes have succeeded on
this same rail dozens of times this session). `mdss_mdp` (DPU) has
*only* `power-domains = <&rpmhpd RPMHPD_MMCX>` -- no separate GDSC.
There is no hidden DPU-specific power domain in the hardware
description; DPU shares the wrapper's physical GDSC.

Also re-verified U-Boot's own memory map (`board.c`'s `build_mem_map()`):
everything below real DRAM (`0x1000` through `0xa0000000`) -- GCC,
DISPCC, the MDSS wrapper, *and* the DPU -- is one single
`MT_DEVICE_NGNRNE` block. GCC and DISPCC writes have succeeded dozens
of times under this exact attribute; if alignment/ordering semantics of
that memory type were the problem, those would show the same symptom.
They don't. Rules out a memory-attribute explanation.

**New test, the first-ever WRITE to the wrapper itself**
(`boot-wrapper-write-test.img`): write-back to `HW_VERSION`
(`0xae00000+0x0`, nominally read-only, chosen specifically so only the
bus-ack behavior is being tested, not any register side effect), right
before the already-proven-working framebuffer self-alloc path.

**Result: BOOTED.** Wrapper writes are fine. **This pins the firewall
boundary exactly at `0xae01000`** (the DPU core's own base address) --
not somewhere within the wrapper, not a broader region. Every
power/clock/reset/memory-attribute/GDSC mechanism has now been checked
and ruled out, in two independent kernel trees, with a register map
that contains nothing resembling an access-control register in the
wrapper's own space. If a hardware region lock is what's happening
here, its configuration is not visible to any OS-level source
available -- it would need to be found via ABL/XBL/TZ binary analysis
or observed directly via hardware debug access (JTAG). This is the
edge of what source-level investigation can determine.

### DPU-bypass proof-of-concept: direct DSI command-mode pixel push

Since the DPU register bus write hang is a wall, tried going around it
instead of through it: the DSI command-mode DMA engine is proven solid
(the full panel init DCS blast has succeeded reliably every single boot
this session), and MIPI panels start in command mode before anything
switches them to video mode -- so pixels can be pushed directly via DCS
`write_memory_start` (`0x2C`), entirely without touching `0xae01000+`.

Added `enable_dsc: bool` parameter to `sheng_mdss_dsi_panel_init()` --
real use needs DSC (video-mode pixel rate requires it), but this
experiment needs it OFF: DSC-enabled means the panel expects compressed
frames, and our raw/uncompressed test patch would get DSC-decoded as
garbage otherwise. `false` skips the `0x90`/PPS/`0x9d`/framerate-branch
block, keeps exit-sleep + display-on (still needed regardless of DSC).

Added `sheng_mdss_dsi_test_patch()`: sets a 16x16 pixel column/page
address window (DCS `0x2A`/`0x2B`), then sends `write_memory_start`
(`0x2C`) as a DCS long write with 256 solid-red RGB888 pixels (768
bytes) as payload -- built directly in the DMA scratch buffer (not via
`dsiSendDcs()`, whose internal buffer is only 16 bytes) using the same
MSM command-packet framing `buildMsmCmdPacket()` uses for its own
long-write path.

Wired into `sheng_mdss_probe()` right after (DSC-disabled) panel init,
stopping immediately after. Built as `boot-dsi-test-patch.img`.

**Result: BOOTED -- confirmed success, not just "didn't hang".** Status
relay shows `DSI_PANEL=0` and the DPU slot (reused for this experiment)
also `=0`: both the `0x2A`/`0x2B` column/page-address DCS writes and the
768-byte `write_memory_start` long-write DMA transfer completed cleanly
with no timeout. **This is a real, working, DPU-independent pixel path
-- we can push pixel data to this panel from U-Boot right now,
completely bypassing the still-unsolved `0xae01000+` write hang.**

Still can't visually confirm a red square appeared -- backlight is off
(see below). That's the immediate next step to actually see this work.

### Backlight: reviving earlier GPIO 128 work

A prior session (commits `d17e2634`/`bfdf514f`/`5d83f5ed`) already
identified the backlight chain for this panel: **GPIO 128** (TLMM,
active-high) is the backlight IC's enable line, independently verified
working via a raw trap-based test at the time. The actual brightness/PWM
control chip is a **KTZ8866A on I2C1**, which needs I2C to configure --
still broken (QUP GENI firmware loader timing issue, `dm_i2c_probe()`
hangs waiting for an ACK that never comes since the protocol firmware
isn't loaded into the sequencer in time). That I2C problem is untouched
this session; only the GPIO enable line is being revisited here, on the
chance the IC has a sane default brightness without I2C configuration.

The devicetree already has a `backlight-gpio` node (`enable-gpios =
<&tlmm 128 GPIO_ACTIVE_HIGH>`, `default-on`) from that earlier session,
but `CONFIG_BACKLIGHT` is currently disabled in `sm8550_defconfig`, so
nothing acts on it. Deliberately did NOT re-enable `CONFIG_BACKLIGHT`/
`CONFIG_BACKLIGHT_GPIO` (the standard U-Boot gpio-backlight uclass
driver) -- this session found that even a trivial `.bind` hook hangs
this board via pre-relocation DM fragility (see above), and
gpio-backlight would be a completely new, untested driver-model
interaction. Went raw MMIO instead, matching everything else this
session: `sheng_mdss_backlight_gpio_enable()` in `sheng_mdss.c`, TLMM
register layout confirmed from `pinctrl-sm8550.c`'s `PINGROUP` macro
(mainline kernel checkout) -- per-pin `0x1000` stride from `tlmm@f100000`,
`ctl_reg` at `+0` (mux_bit=2 selects native GPIO function, oe_bit=9 for
output-enable), `io_reg` at `+0x4` (out_bit=1 to drive high). `vph_pwr`
(the panel's power rail) needs no action -- it's `regulator-always-on`/
`regulator-boot-on` with no GPIO control at all, a pure board-level
always-on supply.

Wired to run right before the DSI test patch, so backlight is on by the
time pixels land. Built as `boot-backlight-test.img`.

**Result: booted cleanly, no visible backlight.** Confirmed via a live
Linux session on the same real boot: `backlight:ktz8866-backlight` is a
real, working kernel backlight class device (`geniqup@ac0000/a84000.i2c/
i2c-4/4-0011`) -- the chip and I2C wiring are fine in hardware, driven
over I2C under Linux without issue. This confirms the GPIO-alone theory:
GPIO 128 brings the KTZ8866 out of shutdown but doesn't drive LED
current -- the KTZ886x family needs I2C register writes (current-sink
enables + brightness) to actually turn on backlight output. Pulled the
exact register map from the real kernel driver (`drivers/video/backlight/
ktz8866.c`, mainline checkout): `BL_EN` (`0x08`, bit 6 = master enable,
bits 0-5 = per-channel current sinks) and `BL_BRT_LSB`/`BL_BRT_MSB`
(`0x04`/`0x05`, 11-bit brightness).

### I2C: found `i2c1` was already enabled, wired up a real transaction

Went looking for how to get these 3 register writes onto the bus.
Checked U-Boot's GENI I2C firmware-loader (`drivers/misc/qcom_geni.c`):
firmware loading and standard driver probing turned out to be
inseparable in the existing code (`probe_children_load_firmware()`
binds the child then calls `device_probe()` directly, and firmware
loading happens *inside* that driver's own probe) -- so "hand-roll a
raw I2C transaction with zero DM" would actually mean re-implementing
*both* the ELF-firmware-partition loader (~90 lines, block/partition
reads) *and* a full GENI FIFO-mode I2C protocol implementation from
scratch, not just the transaction itself.

Before committing to that scope, checked the board's own devicetree
directly and found `&i2c1 { status = "okay"; };` **already present** --
along with `&qupv3_id_0 { status = "okay"; }` (the QUP wrapper). Meaning
U-Boot's automatic `EVT_LAST_STAGE_INIT` firmware-loader + standard
`geni_i2c.c` driver bind/probe have likely been running successfully on
*every single boot this entire session* already, just never exercised
by an actual transaction (no child device previously attempted to talk
to address `0x11`). This changes the risk calculus for going through DM
here -- the scary part (SE firmware load + bus driver probe) may already
be proven safe by every successful boot so far.

Note on risk framing: earlier in this session it was suggested that
DT-triggered (`status = "okay"`) binding is inherently safer than
"manual" binding, distinct from the `.bind` hang found earlier. That
distinction doesn't hold up -- `sheng_mdss`'s `.bind` hung via the exact
same standard, declarative `U_BOOT_DRIVER(...).bind` + `.of_match`
mechanism being described as safe here. What actually differs this time
is that `i2c1`'s bind/probe path has already run to completion,
successfully, on every prior boot -- that's real evidence of safety, not
the DT-vs-manual distinction.

**Implemented**: `sheng_ktz8866_backlight_init()` in `board.c`, called
from `board_late_init()`. Gets the `i2c1` bus via `ofnode_path("/soc@0/
geniqup@ac0000/i2c@a84000")` + `uclass_get_device_by_ofnode()`,
`dm_i2c_probe()`s address `0x11` (dynamically, no static DT child node
needed for a plain register write), then `dm_i2c_write()`s `0x08=0x7F`,
`0x04=0x07`, `0x05=0xFF` (max brightness). Also had to add
`CONFIG_DM_I2C`/`CONFIG_SYS_I2C_GENI` to `sm8550_defconfig` -- neither
was actually enabled before (only `CONFIG_QCOM_GENI`, the firmware-
loader/misc driver, was; the I2C uclass and GENI I2C bus driver itself
were not compiled in at all). Built as `boot-ktz8866-i2c-test.img`.

**Result: booted, no visible backlight.** Read back the ACTUAL live
hardware registers via `/sys/kernel/debug/regmap/4-0011/registers`
under the booted Linux kernel to check whether the write really landed
(not just whether the API call returned success) -- and it had:
`BL_EN=0x5F` (master enable + 5/6 sinks), brightness `0x07`/`0xFF`
(max), exactly as intended. So the single-chip write was genuinely
correct. Backlight still didn't appear -- even forcing max brightness
live via `echo 2047 > .../brightness` under Linux's own complete,
correct driver produced nothing. This ruled out our code being wrong
and pointed at something more fundamental.

### Found: KTZ8866 is a PAIRED pair of chips, and we only ever touched one

`compatible = "kinetic,ktz8866a"` on the device we'd been testing
(`4-0011`) -- not plain `ktz8866`. The real driver
(`drivers/video/backlight/ktz8866.c`) has `ktz8866a`/`ktz8866b` id
variants that mirror every write to each other
(`ktz8866_write()`/`update_bits()` write to both `ktz->regmap` and a
paired `ktz_b->regmap`). Found the actual paired "B" chip live:
`kinetic,ktz8866b` at `0-0011`, on a **completely different physical
I2C controller** (`9c0000.geniqup`/`988000.i2c`, an I2C
*master-hub*-type wrapper -- distinct compatible
`"qcom,geni-se-i2c-master-hub"` from `i2c1`'s plain
`"qcom,geni-se-qup"`, with its own separate firmware-loading pass in
`qcom_geni.c`). U-Boot's `sheng_ktz8866_backlight_init()` had only ever
touched chip A. If the panel's two DSI halves are each driven by their
own chip (plausible for a dual-DSI split-link panel, which this is),
missing B entirely would explain total darkness despite A's registers
being perfectly correct.

Also found via the same live regmap dump: chip A's `LCD_BIAS_CFG1`
(register `0x09`) reads `0x9F` (`LCD_BIAS_EN`, set by Linux's own
`ktz8866_init()`, gated on the `kinetic,enable-lcd-bias` DT boolean
property present on this board) while chip B's reads `0x98` -- the real
driver's own `regmap_write()` for this register is **not** part of the
mirrored-write path, so it only ever reaches whichever chip instance
directly owns the `dev.of_node` with that property (chip A here). Our
U-Boot code never wrote this register on either chip.

**Fix applied:** `sheng_ktz8866_backlight_init()` now writes both
chips (`sheng_ktz8866_write_chip()`, called for both the `i2c1`/`a84000`
path and the new `geniqup@9c0000`/`988000` path), plus `LCD_BIAS_CFG1 =
0x9F` on both (cheap, low-risk extra write; not certain the real
driver's A-only behavior is intentional-by-hardware-design vs an
oversight, so covering both is the safe choice). Enabled the second
I2C path in the board dts: `&i2c_master_hub_0 { status = "okay"; }` +
`&i2c_hub_2 { status = "okay"; }` (both `status = "disabled"` by
default in the shared `sm8550.dtsi`; confirmed via `geni_i2c.c`'s own
source that both the master-hub wrapper compatible and its child bus
compatible already have real driver support in this U-Boot tree, no
new driver code needed). Also added a 5-second `mdelay()` after both
writes (requested explicitly, to rule out a timing race with whatever
runs next) and a new status-relay region (`sheng,ktz8866-status`,
`SHENG_KTZ8866_STATUS_ADDR`, same cache-flush-on-write pattern as
`sheng_mdss.c`'s breadcrumbs) so the per-chip write result is readable
after boot, since `board.c` had no visibility into whether these calls
actually succeeded before now. Built as `boot-ktz8866-instrumented.img`.

**Result: pending.**

### Aside: NixOS/Linux-side backlight+display investigation (separate from U-Boot)

While chasing this, discovered `nixos/kernel/default.nix` had
`CONFIG_DRM_MSM` (the real, normally-working display driver for this
exact panel) disabled -- a leftover from a completed "cont_splash
investigation" that was never reverted, with a matching `getty@tty1`
mask in `hardware.nix`. Reverted both. This is entirely independent of
U-Boot's own driver work above -- Linux boots with its own, separately
maintained devicetree (confirmed: `/sys/firmware/devicetree/base/
framebuffer*` doesn't exist under the currently-running kernel even
though a `framebuffer` node exists in U-Boot's own `dts/upstream/...`
source -- they are different DTBs). Rebuilding the NixOS image to test
this hit an unrelated infrastructure issue: the remote aarch64-linux
builder's sandbox can't resolve DNS for several external patch-fetch
URLs (`gitlab.postmarketos.org`, `raw.githubusercontent.com`), breaking
multiple packages (`sheng-iio-sensor-proxy`, `libssc`, and their
dependents). Worked around by temporarily excluding
`sheng-iio-sensor-proxy` from `xiaomi-sheng-services.nix`; hit the same
issue on `libssc`/`wait_for_qmi_service.patch` next and left that build
in the user's hands rather than keep excluding packages one at a time.
The DRM_MSM/getty reverts themselves are correct either way and don't
need to wait on that infra issue being resolved.

### Dual-chip + LCD_BIAS fix confirmed correct via instrumentation, still no light -- likely explanation found

Added a new status relay (`sheng,ktz8866-status`, same cache-flush-on-
write pattern as `sheng_mdss.c`) since `board.c` previously had zero
visibility into whether `dm_i2c_probe()`/`dm_i2c_write()` actually
succeeded. Result after flashing `boot-ktz8866-instrumented.img`:
**both chips report `0` (success)** -- confirmed via direct
instrumentation, not just "didn't hang". The dual-chip + `LCD_BIAS_CFG1`
fix is genuinely correct. **Still no visible backlight.**

Realized why, tracing back to something already noted much earlier in
this file: the currently-running Linux kernel has `CONFIG_DRM_MSM`
disabled (see the "Aside" section above). The KTZ8866 backlight driver
is a standalone I2C driver, independent of DRM_MSM -- it probes and
configures fine regardless, which is exactly what we're seeing. But the
**panel's own power sequencing** -- `avdd`/`avee` bias regulators +
reset-GPIO pulse, done in `nt36532e_prepare()`
(`drivers/gpu/drm/panel/panel-novatek-nt36532e.c`, confirmed live in
the `sm8550-mainline` checkout: `pinfo->supplies[] = {"vddio","avdd",
"avee"}`, `reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH)`)
-- only runs as part of the DRM/panel driver probe chain, which
requires DRM_MSM. This is a real, previously-documented gap in this
file (search "real gap, needs separate follow-up" above) that predates
this session. Many LCD panels are "normally black" -- without proper
bias voltage, the polarizer stack can block all light transmission
regardless of backlight brightness, which would explain correctly-
configured backlight registers, successfully-ACKed DSI commands, and
still zero visible light, consistently across every test tonight
(U-Boot's own DSI bypass, and Linux's full sysfs-driven brightness
test).

Went looking for this board's actual `avdd`/`avee`/`reset-gpios` wiring
values (needed regardless of whether the NixOS/DRM_MSM path pans out,
since `sheng_mdss.c`'s own panel init would eventually need them too)
across all three cloned repos
(`Xiaomi_Kernel_sheng`, `Xiaomi-pad-6s-pro-Linux-1`,
`map220v/sm8550-mainline`) -- none contain the actual board-side
devicetree source (the first two are kernel/build-script repos without
board DTS at all; only the *driver's own* expected property names came
from the local `sm8550-mainline` checkout, not this board's specific
values). Left unresolved -- if the DRM_MSM path doesn't pan out, this
is the next concrete thing to chase, but needs a real devicetree source
we don't have yet, not more guessing.

### Cross-checked against a known-working debian-sheng+KDE reference boot, found the actual board dts, and traced the real remaining gap to sheng_mdss.c itself

Got direct SSH access to a booted debian-sheng+KDE image on this exact
unit (backlight and display both confirmed visually working). Compared
everything findable:

- `ktz8866.c` driver: byte-identical to our pinned kernel commit.
- `backlight@11` devicetree node (found via the actual board DTS,
  `sm8550-mainline`'s `arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts`
  -- the real Linux-side devicetree, previously undiscovered):
  byte-identical property values to what we'd already independently
  reverse-engineered, **except one real bug this surfaced**:
  `current-num-sinks = <5>`, not 6. We had written `BL_EN = 0x7f` (all
  6 sinks); the real driver computes `0x5f` (5 sinks + master enable).
  Fixed in `board.c`, along with two other registers the real driver
  writes that we'd missed entirely (`BL_CFG2`/`BL_DIMMING`, both
  DT-property-driven, both confirmed matching the real driver's
  computed values against our own earlier live register dump).
- Base kernel `.config`: effectively identical (one unrelated
  `CONFIG_STRICT_DEVMEM` diff).
- GPIO 30/31/128 (avdd/avee/backlight-enable) end-state: identical
  between both systems.
- Boot method (`fastboot boot` vs genuine flash + full power cycle):
  ruled out by direct test -- doesn't change anything.
- `PWM2DIG_LSBs`/`MSBs` (registers `0x12`/`0x13`): the one register
  that actually differs (`0xff,0x07` on the working system, `0x00,0x00`
  on ours) -- confirmed via a raw I2C write (bypassing the kernel
  driver via `/dev/i2c-*` + `I2C_SLAVE_FORCE`, since the driver never
  writes these itself) that this is a genuine hardware-read-only status
  register; our write ACK'd but didn't stick. Whatever sets this comes
  from outside I2C entirely -- most likely a PMIC LPG channel, but nothing
  in Linux's own PWM subsystem references it (`pwmchip0` exists,
  `npwm=4`, but zero channels are exported and no devicetree node
  anywhere has a `pwms = <...>` property on either system) -- so if
  real, it's set below the OS entirely.

**The actual lead:** a previously-working commit,
`2d6803ccfa39ea5bb02c97f413449fe0dc8ff457` (2026-08-15, "sheng: use
real, verified multi-bank /memory node"), confirmed via `git cat-file`
to predate `sheng_mdss.c`'s existence entirely -- at that point U-Boot
was a pure bootloader (load kernel, jump), touching zero display
hardware, and debian-sheng's own drm/msm handled 100% of the hardware
bring-up from a pristine, ABL-left state. Every boot since
`sheng_mdss.c` was added runs a real hardware-poking sequence (GDSC
enable, DISPCC PLL0 programming, DSI PHY bring-up, full DSI panel DCS
blast, GCC clock enable, MDSS core reset toggle) *before* Linux ever
starts. Plausible that this leaves something (plausibly PMIC/LPG-
adjacent, matching the PWM2DIG finding above) in a state Linux's own
driver init doesn't fully recover from, even though DPU/DSI itself is
tolerant enough to still bind and render regardless.

**Test built:** `CONFIG_VIDEO`/`CONFIG_VIDEO_SHENG_MDSS` disabled
entirely in `sm8550_defconfig` -- U-Boot reverted to a pure bootloader,
matching the known-working commit's hardware conditions exactly, with
the NixOS kernel (DRM_MSM enabled) otherwise unchanged. Built as
`boot-no-mdss-driver.img`. **Result: pending.**

If this confirms the theory, the real fix is making `sheng_mdss_probe()`
properly quiesce/restore the hardware it touches before handing off to
Linux (or simply not touch it when the goal is Linux driving the
display, as opposed to our own DPU-bypass pixel work), not another
register chase.

**Result: CONFIRMED. Backlight works.** Flashed `boot-no-mdss-driver.img`
-- visually confirmed working backlight on real hardware. Verified via
`exec.sh`: `PWM2DIG_LSBs`/`MSBs` now read `0xff`/`0x07` on both chips,
exactly matching the debian-sheng reference (was `0x00`/`0x00` on every
build with `sheng_mdss.c` active, all session). `msm_dpu` still bound
successfully (`ae94000.dsi`, `ae96000.dsi`, `fb0: msmdrmfb`) -- the
display pipeline itself is unaffected either way.

**This is the actual, complete answer to tonight's central mystery,**
found the hard way through hours of register-level investigation that
all turned out to be correct-but-insufficient: `sheng_mdss.c`'s hardware
bring-up (GDSC/DISPCC/DSI-PHY/panel-init/RSC, all run unconditionally on
every boot since it was added) leaves something -- almost certainly
PMIC/LPG-adjacent, given the exact register that flips -- in a state
Linux's own driver init can't recover from, even though DPU/DSI
themselves are tolerant enough to still bind and render regardless.
Every earlier finding in this file (RSC corruption, `.bind` hang, DPU
write hang, MMCX corner, LUT/VSYNC clocks, dual-chip backlight I2C,
`BL_EN` sink count) was real and worth keeping -- none of them were
wrong, they just weren't sufficient on their own, because the actual
blocker was one layer up: our own driver running at all, before Linux
gets a chance to configure the same hardware from a clean state.

### What this means going forward

For a **working display with backlight**, the answer today is: don't
run `sheng_mdss_probe()` at all -- let U-Boot be a pure bootloader
(`CONFIG_VIDEO`/`CONFIG_VIDEO_SHENG_MDSS` off) and let Linux's own
`drm/msm` + `ktz8866` drivers do 100% of the bring-up, exactly like
debian-sheng and the pre-`sheng_mdss.c` commit history. This is a
completely different use case from `sheng_mdss.c`'s original goal
(U-Boot itself drawing pixels, e.g. for an early splash before Linux
even starts) -- both are legitimate, they just can't currently coexist
on one boot. If `sheng_mdss.c` is needed again later (for its own
DSI-bypass pixel work, which independently works and is unaffected by
any of this), it would need to properly quiesce/restore GDSC, DISPCC,
DSI PHY, and the MDSS core reset line back to a state Linux's own probe
expects before handing off -- not attempted here, real follow-up work
if that combination is ever needed.

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
4. **Read-vs-write test**: with all three of the above in place, tried
   a single plain *read* (not write) of `SSPP_SRC_SIZE`
   (`dpu_base+0x24000`) instead of ever writing -- also hung. This
   rules out write-protection/XPU access control as the mechanism;
   whatever's gating the DPU register block blocks reads and writes
   identically, consistent with a genuine unclocked/unpowered AHB
   slave rather than a permissions issue.

Also added a general-purpose log buffer (`sheng_mdss_log()` in
`sheng_mdss.c`, relayed via `/proc/device-tree/chosen/sheng,mdss-log`,
same mechanism as the status relay) that records actual values --
`RSC_DRV_ID`, cmd-db lookup addresses for `mmcx.lvl`/`MM0`, the chosen
TCS slot, the GCC_DISP_HF_AXI_CLK CBCR readback, etc. -- not just
pass/fail codes, for whenever a future attempt gets far enough to boot
and its log can be read back. It was NOT read back this session because
every build that reached the DPU read/write step hung before reaching
Linux (the log is only readable from a successful boot, so it's only
useful for narrowing which of several new steps in a single attempt
got furthest -- not for anything that hangs on the very first new step,
which is what's happened every time DPU is touched at all so far).

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
