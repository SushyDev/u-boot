// SPDX-License-Identifier: GPL-2.0+
//
// Bare-metal MDSS/DISPCC/DSI/DPU register sequencing for SM8550, called
// from the C UCLASS_VIDEO shim in sheng_mdss.c. Freestanding, no libc,
// no allocator -- every function operates on caller-supplied MMIO bases.
//
// Register offsets/values are filled in per-block as each phase of the
// bring-up (GDSC/DISPCC -> DSI PHY/host -> DPU pipeline) is ported from
// the mainline Linux drm/msm driver and verified against the live device
// over the exec.sh serial bridge. Until then, each stage is a stub that
// returns -ENOSYS (-38) so the C shim can report "not yet implemented"
// instead of silently pretending to succeed.

const ENOSYS: c_int = -38;

// Transcribed verbatim from sheng_tianma_init_sequence() in
// drivers/gpu/drm/panel/panel-novatek-nt36532e.c (mainline sm8550 kernel
// checkout, xiaomi,sheng-nt36532e / novatek,nt36532e panel). Sent to the
// DSI0 host only -- qcom,sync-dual-dsi mirrors each write to DSI1 in
// hardware. Every entry here is a short DCS write (1-byte command + N
// data bytes); the PPS long-write and the 120Hz/144Hz branch are handled
// separately by the caller (sheng_mdss_dsi_panel_init in task #4), since
// they aren't static byte sequences (PPS is packed from DscConfig at
// runtime, and the b2/b3 framerate registers depend on the selected mode).
//
// This table stops right before "Enable DSC" (0x90 0x03); everything
// from there on (DSC enable, PPS, 0x9d, framerate ctrl, exit-sleep,
// 120ms delay, display-on) is sequenced explicitly in
// sheng_mdss_dsi_panel_init once the DSI host is real.
pub const DcsCmd = struct {
    cmd: u8,
    args: []const u8,
};

pub const nt36532e_init_sequence = [_]DcsCmd{
    // Timings Page 3 Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0x26} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} },
    .{ .cmd = 0xcd, .args = &[_]u8{ 0x3a, 0x46 } },
    .{ .cmd = 0xce, .args = &[_]u8{ 0x39, 0x46 } },

    // Timings Page 2 Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0x25} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} },
    .{ .cmd = 0x05, .args = &[_]u8{0x00} }, // Disable auto VBP/VFP, must set in 0x3b

    // Timings Page 4 Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0x27} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} },
    .{ .cmd = 0xd0, .args = &[_]u8{0x31} },
    .{ .cmd = 0xd1, .args = &[_]u8{0x20} },
    .{ .cmd = 0xd2, .args = &[_]u8{0x38} },
    .{ .cmd = 0xde, .args = &[_]u8{0x43} },
    .{ .cmd = 0xdf, .args = &[_]u8{0x02} },
    .{ .cmd = 0x13, .args = &[_]u8{0x00} },
    .{ .cmd = 0x14, .args = &[_]u8{0x11} },

    // CABC Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0x23} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} },
    .{ .cmd = 0x00, .args = &[_]u8{0x80} },
    .{ .cmd = 0x01, .args = &[_]u8{0x84} },
    .{ .cmd = 0x05, .args = &[_]u8{0xf6} },
    .{ .cmd = 0x06, .args = &[_]u8{0x02} },
    .{ .cmd = 0x11, .args = &[_]u8{0x03} },
    .{ .cmd = 0x12, .args = &[_]u8{0xc7} },
    .{ .cmd = 0x15, .args = &[_]u8{0xae} },
    .{ .cmd = 0x16, .args = &[_]u8{0x16} },
    // CABC: UI mode
    .{ .cmd = 0x29, .args = &[_]u8{0x0a} },
    .{ .cmd = 0x30, .args = &[_]u8{0xff} },
    .{ .cmd = 0x31, .args = &[_]u8{0xfe} },
    .{ .cmd = 0x32, .args = &[_]u8{0xfd} },
    .{ .cmd = 0x33, .args = &[_]u8{0xfb} },
    .{ .cmd = 0x34, .args = &[_]u8{0xf8} },
    .{ .cmd = 0x35, .args = &[_]u8{0xf5} },
    .{ .cmd = 0x36, .args = &[_]u8{0xf3} },
    .{ .cmd = 0x37, .args = &[_]u8{0xf2} },
    .{ .cmd = 0x38, .args = &[_]u8{0xf2} },
    .{ .cmd = 0x39, .args = &[_]u8{0xf2} },
    .{ .cmd = 0x3a, .args = &[_]u8{0xef} },
    .{ .cmd = 0x3b, .args = &[_]u8{0xec} },
    .{ .cmd = 0x3d, .args = &[_]u8{0xe9} },
    .{ .cmd = 0x3f, .args = &[_]u8{0xe5} },
    .{ .cmd = 0x40, .args = &[_]u8{0xe5} },
    .{ .cmd = 0x41, .args = &[_]u8{0xe5} },
    // CABC: STILL mode
    .{ .cmd = 0x2a, .args = &[_]u8{0x13} },
    .{ .cmd = 0x45, .args = &[_]u8{0xff} },
    .{ .cmd = 0x46, .args = &[_]u8{0xf4} },
    .{ .cmd = 0x47, .args = &[_]u8{0xe7} },
    .{ .cmd = 0x48, .args = &[_]u8{0xda} },
    .{ .cmd = 0x49, .args = &[_]u8{0xcd} },
    .{ .cmd = 0x4a, .args = &[_]u8{0xc0} },
    .{ .cmd = 0x4b, .args = &[_]u8{0xb3} },
    .{ .cmd = 0x4c, .args = &[_]u8{0xb1} },
    .{ .cmd = 0x4d, .args = &[_]u8{0xb1} },
    .{ .cmd = 0x4e, .args = &[_]u8{0xb1} },
    .{ .cmd = 0x4f, .args = &[_]u8{0x95} },
    .{ .cmd = 0x50, .args = &[_]u8{0x79} },
    .{ .cmd = 0x51, .args = &[_]u8{0x5c} },
    .{ .cmd = 0x52, .args = &[_]u8{0x58} },
    .{ .cmd = 0x53, .args = &[_]u8{0x58} },
    .{ .cmd = 0x54, .args = &[_]u8{0x58} },
    // CABC: MOVING mode
    .{ .cmd = 0x2b, .args = &[_]u8{0x0e} },
    .{ .cmd = 0x58, .args = &[_]u8{0xff} },
    .{ .cmd = 0x59, .args = &[_]u8{0xfb} },
    .{ .cmd = 0x5a, .args = &[_]u8{0xf7} },
    .{ .cmd = 0x5b, .args = &[_]u8{0xf3} },
    .{ .cmd = 0x5c, .args = &[_]u8{0xef} },
    .{ .cmd = 0x5d, .args = &[_]u8{0xe3} },
    .{ .cmd = 0x5e, .args = &[_]u8{0xd8} },
    .{ .cmd = 0x5f, .args = &[_]u8{0xd6} },
    .{ .cmd = 0x60, .args = &[_]u8{0xd6} },
    .{ .cmd = 0x61, .args = &[_]u8{0xd6} },
    .{ .cmd = 0x62, .args = &[_]u8{0xc8} },
    .{ .cmd = 0x63, .args = &[_]u8{0xb7} },
    .{ .cmd = 0x64, .args = &[_]u8{0xaa} },
    .{ .cmd = 0x65, .args = &[_]u8{0xa8} },
    .{ .cmd = 0x66, .args = &[_]u8{0xa8} },
    .{ .cmd = 0x67, .args = &[_]u8{0xa8} },

    // IC Transfer Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0xf0} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} },
    .{ .cmd = 0xfa, .args = &[_]u8{0x05} },
    .{ .cmd = 0x76, .args = &[_]u8{0x16} },

    // User Cmd Set
    .{ .cmd = 0xff, .args = &[_]u8{0x10} },
    .{ .cmd = 0xfb, .args = &[_]u8{0x01} }, // don't reload registers from MTP/default
    .{ .cmd = 0x35, .args = &[_]u8{0x00} }, // tear on
    .{ .cmd = 0x3b, .args = &[_]u8{ 0x03, 0x8c, 0x1a, 0x04, 0x04, 0x00 } }, // VBP+VSYNC, VFP timings
    .{ .cmd = 0x51, .args = &[_]u8{ 0x0f, 0xff } }, // brightness
    .{ .cmd = 0x53, .args = &[_]u8{0x24} }, // backlight on, no dimming
};

// After nt36532e_init_sequence, the caller must additionally send (in
// order): 0x90 0x03 (enable DSC), the packed DSC PPS long-write, 0x9d
// 0x01, the 144Hz framerate branch (0xb2 0x91 / 0xb3 0x40), exit-sleep,
// a 120ms delay, then display-on. DSC config for the 144Hz mode:
pub const DscConfig = struct {
    dsc_version_major: u8 = 1,
    dsc_version_minor: u8 = 1,
    slice_height: u16 = 16,
    slice_width: u16 = 762,
    slice_count: u8 = 2,
    bits_per_component: u8 = 8,
    bits_per_pixel_x16: u16 = 8 << 4, // 8.0 bpp, fixed-point x16 like drm_dsc_config
    block_pred_enable: bool = true,
};

pub const nt36532e_dsc_144hz = DscConfig{};

/// Full 128-byte DSC 1.1 Picture Parameter Set for our exact panel
/// mode (bpc=8, bpp=8.0, slice_width=762, slice_height=16,
/// slice_count=2, pic 1524x2032 per DSI half), computed offline in
/// Python replicating drm_dsc_pps_payload_pack() +
/// drm_dsc_compute_rc_parameters() + the standard DSC 1.1
/// rc_parameters_pre_scr[bpp=8,bpc=8] table exactly -- see SPEC.md
/// for the full derivation and every intermediate value. Sent as a
/// MIPI_DSI_PICTURE_PARAMETER_SET (type 0x0A) long packet, not a
/// generic DCS long write.
pub const nt36532e_pps_144hz = [128]u8{
    0x11, 0x00, 0x00, 0x89, 0x30, 0x80, 0x07, 0xf0, 0x05, 0xf4, 0x00, 0x10, 0x02, 0xfa, 0x02, 0xfa,
    0x02, 0x00, 0x02, 0x7d, 0x00, 0x20, 0x01, 0xc6, 0x00, 0x0a, 0x00, 0x0c, 0x06, 0x67, 0x04, 0x82,
    0x18, 0x00, 0x10, 0xf0, 0x03, 0x0c, 0x20, 0x00, 0x06, 0x0b, 0x0b, 0x33, 0x0e, 0x1c, 0x2a, 0x38,
    0x46, 0x54, 0x62, 0x69, 0x70, 0x77, 0x79, 0x7b, 0x7d, 0x7e, 0x01, 0x02, 0x01, 0x00, 0x09, 0x40,
    0x09, 0xbe, 0x19, 0xfc, 0x19, 0xfa, 0x19, 0xf8, 0x1a, 0x38, 0x1a, 0x78, 0x1a, 0xb6, 0x2a, 0xf6,
    0x2b, 0x34, 0x2b, 0x74, 0x3b, 0x74, 0x6b, 0xf4, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

fn mmioRead32(base: usize, offset: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(base + offset);
    return ptr.*;
}

fn mmioWrite32(base: usize, offset: usize, value: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(base + offset);
    ptr.* = value;
}

fn mmioSetBits32(base: usize, offset: usize, mask: u32) void {
    const val = mmioRead32(base, offset);
    mmioWrite32(base, offset, val | mask);
}

fn mmioClearBits32(base: usize, offset: usize, mask: u32) void {
    const val = mmioRead32(base, offset);
    mmioWrite32(base, offset, val & ~mask);
}

// U-Boot's global udelay(), from <time.h> -- linked in from the rest of
// the U-Boot binary, not defined here.
extern fn udelay(usec: c_ulong) callconv(.c) void;

const ETIMEDOUT: c_int = -110;

// Offsets/bits transcribed from drivers/clk/qcom/gdsc.c (mainline sm8550
// kernel checkout) -- mdss_gdsc there is { .gdscr = 0x9000, .pwrsts =
// PWRSTS_OFF_ON, .flags = POLL_CFG_GDSCR | HW_CTRL | RETAIN_FF_ENABLE },
// no SW_RESET/CLAMP_IO/VOTABLE. Confirmed live against the running
// kernel's own regmap (both 0x9000 and 0x9004 present as readable/
// writable entries in /sys/kernel/debug/regmap/af00000.clock-controller/
// access) before ever writing to them -- see SPEC.md.
const MDSS_GDSC_OFFSET: usize = 0x9000;
const CFG_GDSCR_OFFSET: usize = 0x4;
const SW_COLLAPSE_MASK: u32 = 1 << 0;
const HW_CONTROL_MASK: u32 = 1 << 1;
const GDSC_RETAIN_FF_ENABLE: u32 = 1 << 11;
const GDSC_POWER_UP_COMPLETE: u32 = 1 << 16;
const GDSC_POLL_TIMEOUT_US: u32 = 2000;

// DISP_CC_MDSS_CORE_BCR, from disp_cc_sm8550_resets[DISP_CC_MDSS_CORE_BCR]
// = { 0x8000 } in dispcc-sm8550.c (qcom_reset_map: only .reg set, so
// .bit defaults to 0 -> mask = BIT(0)). Confirmed present and
// read/write-accessible in the live device's own regmap at
// af00000.clock-controller's offset 08000 before ever writing to it.
//
// msm_mdss_reset() in msm_mdss.c calls this via the generic
// reset-controller framework (reset_control_assert() / msleep(20) /
// reset_control_deassert()) as the FIRST thing msm_mdss_init() does --
// before GDSC, before any clock is parsed or enabled. It's a plain
// regmap write into DISPCC, which is already reachable pre-GDSC (the
// AHB config path to DISPCC is on the always-on GCC_DISP_AHB_CLK), so
// nothing about clock/power sequencing blocks doing this first. Never
// attempted before -- see SPEC.md's "Next leads, not yet tried".
const MDSS_CORE_BCR_OFFSET: usize = 0x8000;
const MDSS_CORE_BCR_MASK: u32 = 1 << 0;

/// Assert then deassert DISP_CC_MDSS_CORE_BCR, mirroring msm_mdss_reset().
/// Source holds the reset for msleep(20) ("tests indicate reset has to
/// be held for some period of time... one frame in a typical system");
/// U-Boot's udelay() is the closest equivalent to that busy-ish wait.
export fn sheng_mdss_core_reset(dispcc_base: usize) callconv(.c) void {
    mmioSetBits32(dispcc_base, MDSS_CORE_BCR_OFFSET, MDSS_CORE_BCR_MASK);
    _ = mmioRead32(dispcc_base, MDSS_CORE_BCR_OFFSET); // ensure write completion, like regmap_read() does
    udelay(20000);
    mmioClearBits32(dispcc_base, MDSS_CORE_BCR_OFFSET, MDSS_CORE_BCR_MASK);
    _ = mmioRead32(dispcc_base, MDSS_CORE_BCR_OFFSET);
}

/// Enable the MDSS GDSC power domain, mirroring gdsc_enable() in
/// gdsc.c for the mdss_gdsc case (no SW_RESET/CLAMP_IO/VOTABLE
/// branches apply to it, so this only implements what mdss_gdsc's own
/// flags actually exercise). `dispcc_base` is the qcom,sm8550-dispcc
/// reg base (0xaf00000) -- GDSC registers live inside DISPCC's regmap,
/// not the MDSS wrapper's own 4KB register window.
export fn sheng_mdss_gdsc_enable(dispcc_base: usize) callconv(.c) c_int {
    // gdsc_update_collapse_bit(false): de-assert SW_COLLAPSE (power-on
    // request).
    mmioClearBits32(dispcc_base, MDSS_GDSC_OFFSET, SW_COLLAPSE_MASK);

    // gdsc_poll_status(GDSC_ON): POLL_CFG_GDSCR means poll gdscr+0x4
    // for GDSC_POWER_UP_COMPLETE. ~1us granularity via udelay(1) per
    // iteration approximates gdsc.c's STATUS_POLL_TIMEOUT_US (2000us).
    var waited: u32 = 0;
    while (waited < GDSC_POLL_TIMEOUT_US) : (waited += 1) {
        const cfg = mmioRead32(dispcc_base, MDSS_GDSC_OFFSET + CFG_GDSCR_OFFSET);
        if ((cfg & GDSC_POWER_UP_COMPLETE) != 0) break;
        udelay(1);
    } else {
        return ETIMEDOUT;
    }

    // gdsc_enable(): "additional 4 clock cycles" / memories-settling
    // delay before touching RETAIN_FF/HW_CTRL.
    udelay(1);

    // RETAIN_FF_ENABLE flag -> gdsc_retain_ff_on().
    mmioSetBits32(dispcc_base, MDSS_GDSC_OFFSET, GDSC_RETAIN_FF_ENABLE);

    // HW_CTRL flag -> gdsc_hwctrl(true): hand off to hardware trigger
    // mode, then a settling delay before any status-bit polling could
    // observe a false "on" mid-power-cycle.
    mmioSetBits32(dispcc_base, MDSS_GDSC_OFFSET, HW_CONTROL_MASK);
    udelay(1);

    return 0;
}

// --- disp_cc_pll0 (Lucid OLE alpha PLL), from clk_alpha_pll_regs[
// CLK_ALPHA_PLL_TYPE_LUCID_OLE] and disp_cc_pll0_config in
// dispcc-sm8550.c. PLL0.offset = 0x0 relative to dispcc_base (i.e.
// these ARE absolute offsets from dispcc_base already).
const PLL_MODE_OFF: usize = 0x00;
const PLL_OPMODE_OFF: usize = 0x04;
const PLL_L_VAL_OFF: usize = 0x10;
const PLL_ALPHA_VAL_OFF: usize = 0x14;
const PLL_USER_CTL_OFF: usize = 0x18;
const PLL_USER_CTL_U_OFF: usize = 0x1c;
const PLL_CONFIG_CTL_OFF: usize = 0x20;
const PLL_CONFIG_CTL_U_OFF: usize = 0x24;
const PLL_CONFIG_CTL_U1_OFF: usize = 0x28;
const PLL_TEST_CTL_OFF: usize = 0x2c;
const PLL_TEST_CTL_U_OFF: usize = 0x30;
const PLL_TEST_CTL_U1_OFF: usize = 0x34;
const PLL_TEST_CTL_U2_OFF: usize = 0x38;

const PLL_OUTCTRL: u32 = 1 << 0;
const PLL_RESET_N: u32 = 1 << 2;
const PLL_LOCK_DET: u32 = 1 << 31;
const PLL_STANDBY: u32 = 0x0;
const PLL_RUN: u32 = 0x1;
const PLL_OUT_MASK: u32 = 0x7;
const TRION_PLL_CAL_VAL: u32 = 0x44;
const LUCID_EVO_PLL_CAL_L_VAL_SHIFT: u5 = 16;
const LUCID_OLE_PLL_RINGOSC_CAL_L_VAL_SHIFT: u5 = 24;
const PLL_LOCK_POLL_TIMEOUT_US: u32 = 1500;

/// disp_cc_pll0_config from dispcc-sm8550.c: l=0xd, alpha=0x6492 ->
/// VCO ~= 19.2MHz * (13 + 0x6492/0x10000) = ~1,000,000,000 Hz-ish
/// range feeding the 514MHz mdp_clk and others through further
/// dividers. Values are opaque calibration/config constants from the
/// vendor driver, not derived from first principles.
fn dispCcPll0Enable(dispcc_base: usize) c_int {
    mmioWrite32(dispcc_base, PLL_L_VAL_OFF, 0xd |
        (TRION_PLL_CAL_VAL << LUCID_EVO_PLL_CAL_L_VAL_SHIFT) |
        (TRION_PLL_CAL_VAL << LUCID_OLE_PLL_RINGOSC_CAL_L_VAL_SHIFT));
    mmioWrite32(dispcc_base, PLL_ALPHA_VAL_OFF, 0x6492);
    mmioWrite32(dispcc_base, PLL_CONFIG_CTL_OFF, 0x20485699);
    mmioWrite32(dispcc_base, PLL_CONFIG_CTL_U_OFF, 0x00182261);
    mmioWrite32(dispcc_base, PLL_CONFIG_CTL_U1_OFF, 0x82aa299c);
    mmioWrite32(dispcc_base, PLL_USER_CTL_OFF, 0x00000000);
    mmioWrite32(dispcc_base, PLL_USER_CTL_U_OFF, 0x00000005);
    mmioWrite32(dispcc_base, PLL_TEST_CTL_OFF, 0x00000000);
    mmioWrite32(dispcc_base, PLL_TEST_CTL_U_OFF, 0x00000003);
    mmioWrite32(dispcc_base, PLL_TEST_CTL_U1_OFF, 0x00009000);
    mmioWrite32(dispcc_base, PLL_TEST_CTL_U2_OFF, 0x00000034);

    // clk_lucid_ole_pll_configure(): disable output, standby, de-assert reset.
    mmioClearBits32(dispcc_base, PLL_MODE_OFF, PLL_OUTCTRL);
    mmioWrite32(dispcc_base, PLL_OPMODE_OFF, PLL_STANDBY);
    mmioSetBits32(dispcc_base, PLL_MODE_OFF, PLL_RESET_N);

    // alpha_pll_lucid_evo_enable(): run mode, wait for lock, enable outputs.
    mmioSetBits32(dispcc_base, PLL_MODE_OFF, PLL_RESET_N);
    mmioWrite32(dispcc_base, PLL_OPMODE_OFF, PLL_RUN);

    var waited: u32 = 0;
    while (waited < PLL_LOCK_POLL_TIMEOUT_US) : (waited += 1) {
        const mode = mmioRead32(dispcc_base, PLL_MODE_OFF);
        if ((mode & PLL_LOCK_DET) != 0) break;
        udelay(1);
    } else {
        return ETIMEDOUT;
    }

    mmioSetBits32(dispcc_base, PLL_USER_CTL_OFF, PLL_OUT_MASK);
    mmioSetBits32(dispcc_base, PLL_MODE_OFF, PLL_OUTCTRL);
    return 0;
}

// --- RCG2 (root clock generator) helper, from clk-rcg2.c's
// clk_rcg2_configure()/update_config(): CMD_REG at cmd_rcgr+0x0,
// CFG_REG at cmd_rcgr+0x4. Only handles the mnd_width==0 (HID-divider
// only, no M/N/D fractional path) case, which is all disp_cc_mdss_
// {ahb,mdp}_clk_src need for their target rates.
const RCG_CMD_OFF: usize = 0x0;
const RCG_CFG_OFF: usize = 0x4;
const RCG_CMD_UPDATE: u32 = 1 << 0;
const RCG_CFG_SRC_SEL_SHIFT: u5 = 8;
const RCG_CFG_SRC_SEL_MASK: u32 = 0x7 << RCG_CFG_SRC_SEL_SHIFT;
const RCG_CFG_SRC_DIV_MASK: u32 = 0x1f; // hid_width=5 for both clocks used here
const RCG_CFG_MODE_MASK: u32 = 0x3 << 12; // CFG_MODE_MASK, single-edge (0) for us
const RCG_UPDATE_POLL_TIMEOUT_US: u32 = 500;

/// `div_reg_val` is already converted (2*pre_div - 1), matching
/// convert_to_reg_val() in clk-rcg2.c -- e.g. divider 1 -> 1, divider
/// 3 -> 5.
fn rcg2ConfigureHidOnly(dispcc_base: usize, cmd_rcgr: usize, src_sel: u32, div_reg_val: u32) c_int {
    var cfg = mmioRead32(dispcc_base, cmd_rcgr + RCG_CFG_OFF);
    cfg &= ~(RCG_CFG_SRC_SEL_MASK | RCG_CFG_SRC_DIV_MASK | RCG_CFG_MODE_MASK);
    cfg |= (src_sel << RCG_CFG_SRC_SEL_SHIFT) & RCG_CFG_SRC_SEL_MASK;
    cfg |= div_reg_val & RCG_CFG_SRC_DIV_MASK;
    mmioWrite32(dispcc_base, cmd_rcgr + RCG_CFG_OFF, cfg);

    mmioSetBits32(dispcc_base, cmd_rcgr + RCG_CMD_OFF, RCG_CMD_UPDATE);
    var waited: u32 = 0;
    while (waited < RCG_UPDATE_POLL_TIMEOUT_US) : (waited += 1) {
        const cmd = mmioRead32(dispcc_base, cmd_rcgr + RCG_CMD_OFF);
        if ((cmd & RCG_CMD_UPDATE) == 0) return 0;
        udelay(1);
    }
    return ETIMEDOUT;
}

// --- clk_branch2 helper, from clk-branch.c's clk_branch2_enable()/
// clk_branch2_check_halt(): enable bit0, poll CBCR_CLK_OFF (bit31)
// clear. Both disp_cc_mdss_{ahb,mdp}_clk use halt_check = BRANCH_HALT
// (not BRANCH_HALT_ENABLE), so no polarity inversion.
const CBCR_ENABLE: u32 = 1 << 0;
const CBCR_CLK_OFF: u32 = 1 << 31;
const CBCR_POLL_TIMEOUT_US: u32 = 500;

fn clkBranchEnable(dispcc_base: usize, cbcr_off: usize) c_int {
    mmioSetBits32(dispcc_base, cbcr_off, CBCR_ENABLE);
    var waited: u32 = 0;
    while (waited < CBCR_POLL_TIMEOUT_US) : (waited += 1) {
        const val = mmioRead32(dispcc_base, cbcr_off);
        if ((val & CBCR_CLK_OFF) == 0) return 0;
        udelay(1);
    }
    return ETIMEDOUT;
}

// Register offsets/freq-table entries transcribed from
// dispcc-sm8550.c: disp_cc_mdss_ahb_clk_src (cmd_rcgr=0x82e8,
// parent_map_6: P_BI_TCXO=0), disp_cc_mdss_ahb_clk (enable_reg=
// halt_reg=0x80a4), disp_cc_mdss_mdp_clk_src (cmd_rcgr=0x80d8,
// parent_map_8: P_DISP_CC_PLL0_OUT_MAIN=1), disp_cc_mdss_mdp_clk
// (enable_reg=halt_reg=0x800c). Target rates (19.2MHz ahb, 514MHz
// mdp) confirmed against the live device's own clk_summary -- see
// SPEC.md.
const AHB_CLK_SRC_CMD_RCGR: usize = 0x82e8;
const AHB_CLK_CBCR: usize = 0x80a4;
const AHB_CLK_SRC_SEL_XO: u32 = 0;
const AHB_CLK_DIV_REG_VAL: u32 = 1; // F(19200000, P_BI_TCXO, 1, 0, 0) -> 2*1-1

const MDP_CLK_SRC_CMD_RCGR: usize = 0x80d8;
const MDP_CLK_CBCR: usize = 0x800c;
const MDP_CLK_SRC_SEL_PLL0: u32 = 1;
const MDP_CLK_DIV_REG_VAL: u32 = 5; // F(514000000, P_DISP_CC_PLL0_OUT_MAIN, 3, 0, 0) -> 2*3-1

// disp_cc_mdss_mdp_lut_clk (halt_reg=enable_reg=0x8018, bit0,
// BRANCH_HALT_VOTED): a plain branch off disp_cc_mdss_mdp_clk_src, the
// SAME RCG we already configure for MDP_CLK above -- no separate RCG
// programming needed, just another CBCR enable.
//
// disp_cc_mdss_vsync_clk (halt_reg=enable_reg=0x8024, bit0,
// BRANCH_HALT): sourced from its own disp_cc_mdss_vsync_clk_src RCG
// (cmd_rcgr=0x80f0, parent_map_0: P_BI_TCXO=0, mnd_width=0 i.e.
// HID-only like AHB), needs its own rcg2ConfigureHidOnly() call. Target
// 19.2MHz (XO passthrough, div=1) confirmed against the live device's
// own clk_summary -- see SPEC.md.
//
// mdss_mdp@ae01000's OWN devicetree node (distinct from the mdss
// wrapper's) lists clock-names = "bus","nrt_bus","iface","lut","core",
// "vsync" -- six clocks. dpu_runtime_resume() in dpu_kms.c does
// clk_bulk_prepare_enable() over ALL of them before dpu_kms_hw_init()
// ever reads the DPU HW_VERSION register. We had only ever enabled
// "iface" (AHB) and "core" (MDP) -- "lut" and "vsync" were never
// touched at all. The wrapper device doesn't need these (which is why
// DISPCC/DSI worked fine without them), but the DPU sub-block, a
// separate platform device with its own additional clock requirements,
// might. Never attempted before this pass.
const MDP_LUT_CLK_CBCR: usize = 0x8018;

const VSYNC_CLK_SRC_CMD_RCGR: usize = 0x80f0;
const VSYNC_CLK_CBCR: usize = 0x8024;
const VSYNC_CLK_SRC_SEL_XO: u32 = 0;
const VSYNC_CLK_DIV_REG_VAL: u32 = 1; // F(19200000, P_BI_TCXO, 1, 0, 0) -> 2*1-1

/// Bring up disp_cc_pll0, then the AHB (bus, 19.2MHz off XO) and MDP
/// (DPU core, 514MHz off PLL0) clocks, plus the MDP LUT and VSYNC
/// clocks the DPU sub-block's own devicetree node additionally
/// requires (see the comment above). pclk0/byte0/esc0 are NOT done
/// here -- they mux from the DSI PHY's own PLL output rather than
/// DISPCC's internal PLL0, so they belong with DSI PHY bring-up
/// (sheng_mdss_dsi_phy_init) instead.
export fn sheng_mdss_dispcc_init(dispcc_base: usize) callconv(.c) c_int {
    var ret = dispCcPll0Enable(dispcc_base);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, MDP_CLK_SRC_CMD_RCGR, MDP_CLK_SRC_SEL_PLL0, MDP_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, MDP_CLK_CBCR);
    if (ret != 0) return ret;

    ret = clkBranchEnable(dispcc_base, MDP_LUT_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, VSYNC_CLK_SRC_CMD_RCGR, VSYNC_CLK_SRC_SEL_XO, VSYNC_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, VSYNC_CLK_CBCR);
    if (ret != 0) return ret;

    return 0;
}

// --- DSI PHY (dsi_phy_7nm.c, DSI_PHY_7NM_QUIRK_V5_2 path -- SM8550
// uses the "7nm" driver code despite being DT-labelled "4nm", per
// dsi_phy_4nm_8550_cfgs in that file). Register offsets from
// drivers/gpu/drm/msm/registers/display/dsi_phy_7nm.xml (the
// generated dsi_phy_7nm.xml.h wasn't present in this kernel checkout,
// so offsets are taken directly from the rnndb source it's generated
// from). All CMN_* offsets are relative to dsi_phy_base; PLL_* offsets
// are relative to dsi_phy_base + PLL_BASE_OFFSET (the PLL sub-block
// starts at CMN's end); LN_* are relative to dsi_phy_base +
// LANE_BASE_OFFSET, array-strided per lane.
// Real offsets from sm8550.dtsi's mdss_dsi0_phy node (three separate
// `reg` entries: dsi_phy@+0x0/0x200, dsi_phy_lane@+0x200/0x280,
// dsi_pll@+0x500/0x400) -- NOT contiguous sub-regions of one window
// the way an earlier guess assumed. That earlier guess (PLL at +0x200,
// lane at +0x400) put every PLL register write into what's actually
// the lane sub-block, which is exactly why the PLL never locked on
// hardware: none of its real registers were ever touched.
const LANE_BASE_OFFSET: usize = 0x200;
const PLL_BASE_OFFSET: usize = 0x500;
const LANE_STRIDE: usize = 0x80;

// CMN_* (DSI_7nm_PHY_CMN domain)
const CMN_CLK_CFG0: usize = 0x010;
const CMN_CLK_CFG1: usize = 0x014;
const CMN_GLBL_CTRL: usize = 0x018;
const CMN_RBUF_CTRL: usize = 0x01c;
const CMN_VREG_CTRL_0: usize = 0x020;
const CMN_CTRL_0: usize = 0x024;
const CMN_CTRL_2: usize = 0x02c;
const CMN_CTRL_3: usize = 0x030;
const CMN_CTRL_5: usize = 0x1b0;
const CMN_LANE_CFG0: usize = 0x034;
const CMN_LANE_CFG1: usize = 0x038;
const CMN_PLL_CNTRL: usize = 0x03c;
const CMN_LANE_CTRL0: usize = 0x0a0;
const CMN_LANE_CTRL1: usize = 0x0a4;
const CMN_TIMING_CTRL_0: usize = 0x0b4;
const CMN_TIMING_CTRL_1: usize = 0x0b8;
const CMN_TIMING_CTRL_2: usize = 0x0bc;
const CMN_TIMING_CTRL_3: usize = 0x0c0;
const CMN_TIMING_CTRL_4: usize = 0x0c4;
const CMN_TIMING_CTRL_5: usize = 0x0c8;
const CMN_TIMING_CTRL_6: usize = 0x0cc;
const CMN_TIMING_CTRL_7: usize = 0x0d0;
const CMN_TIMING_CTRL_8: usize = 0x0d4;
const CMN_TIMING_CTRL_9: usize = 0x0d8;
const CMN_TIMING_CTRL_10: usize = 0x0dc;
const CMN_TIMING_CTRL_11: usize = 0x0e0;
const CMN_TIMING_CTRL_12: usize = 0x0e4;
const CMN_TIMING_CTRL_13: usize = 0x0e8;
const CMN_GLBL_HSTX_STR_CTRL_0: usize = 0x0ec;
const CMN_GLBL_RESCODE_OFFSET_TOP_CTRL: usize = 0x0f4;
const CMN_GLBL_RESCODE_OFFSET_BOT_CTRL: usize = 0x0f8;
const CMN_GLBL_LPTX_STR_CTRL: usize = 0x100;
const CMN_GLBL_PEMPH_CTRL_0: usize = 0x104;
const CMN_GLBL_STR_SWI_CAL_SEL_CTRL: usize = 0x10c;
const CMN_VREG_CTRL_1: usize = 0x110;
const CMN_CTRL_4: usize = 0x114;
const CMN_PHY_STATUS: usize = 0x140;
const CMN_GLBL_DIGTOP_SPARE4: usize = 0x128;
const CMN_GLBL_DIGTOP_SPARE10: usize = 0x1ac;

const CTRL_0_DIGTOP_PWRDN_B: u32 = 1 << 6;
const CTRL_0_PLL_SHUTDOWNB: u32 = 1 << 5;
const CLK_CFG1_BITCLK_SEL_MASK: u32 = 0x3 << 2;
const CLK_CFG1_CLK_EN: u32 = 1 << 5;
const CLK_CFG1_CLK_EN_SEL: u32 = 1 << 4;

// LN_* (DSI_7nm_PHY domain, per-lane array, stride 0x80)
const LN_CFG0: usize = 0x00;
const LN_CFG1: usize = 0x04;
const LN_CFG2: usize = 0x08;
const LN_PIN_SWAP: usize = 0x10;
const LN_LPRX_CTRL: usize = 0x14;
const LN_TX_DCTRL: usize = 0x18;

// PLL_* (DSI_7nm_PHY_PLL domain)
const PLL_ANALOG_CONTROLS_TWO: usize = 0x004;
const PLL_ANALOG_CONTROLS_THREE: usize = 0x010;
const PLL_ANALOG_CONTROLS_FIVE: usize = 0x018;
const PLL_DSM_DIVIDER: usize = 0x020;
const PLL_FEEDBACK_DIVIDER: usize = 0x024;
const PLL_SYSTEM_MUXES: usize = 0x028;
const PLL_CALIBRATION_SETTINGS: usize = 0x044;
const PLL_BAND_SEL_CAL_SETTINGS_THREE: usize = 0x068;
const PLL_FREQ_DETECT_SETTINGS_ONE: usize = 0x078;
const PLL_PFILT: usize = 0x090;
const PLL_IFILT: usize = 0x094;
const PLL_OUTDIV: usize = 0x0a8;
const PLL_CORE_OVERRIDE: usize = 0x0b8;
const PLL_CORE_INPUT_OVERRIDE: usize = 0x0bc;
const PLL_DECIMAL_DIV_START_1: usize = 0x0e0;
const PLL_FRAC_DIV_START_LOW_1: usize = 0x0e4;
const PLL_FRAC_DIV_START_MID_1: usize = 0x0e8;
const PLL_FRAC_DIV_START_HIGH_1: usize = 0x0ec;
const PLL_PLL_DIGITAL_TIMERS_TWO: usize = 0x0c8;
const PLL_PLL_LOCKDET_RATE_1: usize = 0x158;
const PLL_PLL_PROP_GAIN_RATE_1: usize = 0x160;
const PLL_PLL_BAND_SEL_RATE_1: usize = 0x168;
const PLL_PLL_INT_GAIN_IFILT_BAND_1: usize = 0x170;
const PLL_PLL_FL_INT_GAIN_PFILT_BAND_1: usize = 0x178;
const PLL_PLL_LOCK_OVERRIDE: usize = 0x190;
const PLL_PLL_LOCK_DELAY: usize = 0x194;
const PLL_COMMON_STATUS_ONE: usize = 0x1b0;
const PLL_VCO_CONFIG_1: usize = 0x240;
const PLL_CLOCK_INVERTERS_1: usize = 0x248;
const PLL_CMODE_1: usize = 0x250;
const PLL_ANALOG_CONTROLS_FIVE_1: usize = 0x258;
const PLL_PERF_OPTIMIZE: usize = 0x260;

const PLL_LOCK_STATUS_BIT: u32 = 1 << 0;
const PLL_LOCK_POLL2_TIMEOUT_US: u32 = 5000;
const REFGEN_READY_TIMEOUT_US: u32 = 1000;

// Distinct from ETIMEDOUT (-110) so the two poll points in
// sheng_mdss_dsi_phy_init/dsiPhyPllEnable can be told apart from the
// single status-relay slot the C shim records this function's return
// value into -- see sheng_mdss.c.
const EREFGENTIMEDOUT: c_int = -1110;

/// dec=0x1f, frac=0x877 for our target VCO rate of 1,190,717,578 Hz
/// (== dsi0vco_clk measured live -- see SPEC.md), computed offline
/// with dsi_pll_calc_dec_frac()'s exact integer formula: divider =
/// 19200000*2, dec = (vco*2^18)/divider / 2^18, frac = remainder.
/// Fixed since this driver only ever targets the panel's one 144Hz
/// mode -- not a general set_rate.
const PLL_DECIMAL_DIV_START: u32 = 0x1f;
const PLL_FRAC_DIV_START: u32 = 0x877;
// pll_freq (1,190,717,578) <= 1,300,000,000 -> 0xa0, DSI_PHY_7NM_QUIRK_V5_2 path.
const PLL_CLOCK_INVERTERS_VAL: u32 = 0xa0;
// vco_current_rate < 1,557,000,000 -> 0x08, V5_2 path.
const PLL_VCO_CONFIG_1_VAL: u32 = 0x08;

/// Precomputed msm_dsi_dphy_timing_calc_v4() output for bitclk_rate =
/// 1,190,717,578 Hz, escclk_rate = 19,200,000 Hz -- see SPEC.md for
/// the derivation. Fixed for the same reason as the PLL constants
/// above: this driver targets one exact panel mode, not a general
/// timing calculator.
const TIMING_CLK_PREPARE: u32 = 10;
const TIMING_CLK_ZERO: u32 = 39;
const TIMING_CLK_TRAIL: u32 = 12;
const TIMING_HS_PREPARE: u32 = 10;
const TIMING_HS_ZERO: u32 = 37;
const TIMING_HS_TRAIL: u32 = 11;
const TIMING_HS_RQST: u32 = 7;
const TIMING_HS_EXIT: u32 = 39;
const TIMING_CLK_POST: u32 = 26;
const TIMING_CLK_PRE: u32 = 35;

fn dsiPhyPllConfigHzIndep(phy_base: usize) void {
    const pll = phy_base + PLL_BASE_OFFSET;
    mmioWrite32(pll, PLL_ANALOG_CONTROLS_FIVE_1, 0x01);
    mmioWrite32(pll, PLL_VCO_CONFIG_1, PLL_VCO_CONFIG_1_VAL);
    mmioWrite32(pll, PLL_ANALOG_CONTROLS_FIVE, 0x01);
    mmioWrite32(pll, PLL_ANALOG_CONTROLS_TWO, 0x03);
    mmioWrite32(pll, PLL_ANALOG_CONTROLS_THREE, 0x00);
    mmioWrite32(pll, PLL_DSM_DIVIDER, 0x00);
    mmioWrite32(pll, PLL_FEEDBACK_DIVIDER, 0x4e);
    mmioWrite32(pll, PLL_CALIBRATION_SETTINGS, 0x40);
    mmioWrite32(pll, PLL_BAND_SEL_CAL_SETTINGS_THREE, 0xba);
    mmioWrite32(pll, PLL_FREQ_DETECT_SETTINGS_ONE, 0x0c);
    mmioWrite32(pll, PLL_OUTDIV, 0x00);
    mmioWrite32(pll, PLL_CORE_OVERRIDE, 0x00);
    mmioWrite32(pll, PLL_PLL_DIGITAL_TIMERS_TWO, 0x08);
    mmioWrite32(pll, PLL_PLL_PROP_GAIN_RATE_1, 0x0a);
    mmioWrite32(pll, PLL_PLL_BAND_SEL_RATE_1, 0xc0);
    mmioWrite32(pll, PLL_PLL_INT_GAIN_IFILT_BAND_1, 0x82); // second write in source wins over first (0x84)
    mmioWrite32(pll, PLL_PLL_FL_INT_GAIN_PFILT_BAND_1, 0x4c);
    mmioWrite32(pll, PLL_PLL_LOCK_OVERRIDE, 0x80);
    mmioWrite32(pll, PLL_PFILT, 0x2f); // second write in source wins over first (0x29)
    // DSI_PHY_7NM_QUIRK_V5_2 is not QUIRK_V4_0, so IFILT = 0x3f, and
    // PERF_OPTIMIZE = 0x22 also applies.
    mmioWrite32(pll, PLL_IFILT, 0x3f);
    mmioWrite32(pll, PLL_PERF_OPTIMIZE, 0x22);
}

fn dsiPhyPllCommitRate(phy_base: usize) void {
    const pll = phy_base + PLL_BASE_OFFSET;
    mmioWrite32(pll, PLL_CORE_INPUT_OVERRIDE, 0x12);
    mmioWrite32(pll, PLL_DECIMAL_DIV_START_1, PLL_DECIMAL_DIV_START);
    mmioWrite32(pll, PLL_FRAC_DIV_START_LOW_1, PLL_FRAC_DIV_START & 0xff);
    mmioWrite32(pll, PLL_FRAC_DIV_START_MID_1, (PLL_FRAC_DIV_START & 0xff00) >> 8);
    mmioWrite32(pll, PLL_FRAC_DIV_START_HIGH_1, (PLL_FRAC_DIV_START & 0x30000) >> 16);
    mmioWrite32(pll, PLL_PLL_LOCKDET_RATE_1, 0x40);
    mmioWrite32(pll, PLL_PLL_LOCK_DELAY, 0x06);
    mmioWrite32(pll, PLL_CMODE_1, 0x10); // dphy mode (not cphy)
    mmioWrite32(pll, PLL_CLOCK_INVERTERS_1, PLL_CLOCK_INVERTERS_VAL);
}

/// dsi_pll_enable_pll_bias() + rate commit (dsi_pll_7nm_vco_set_rate),
/// matching source call order: bias -> config -> commit -> hzindep.
/// This does NOT start the PLL -- that's a genuinely separate clk_ops
/// step (.prepare = dsi_pll_7nm_vco_prepare, not .set_rate) that
/// writes CMN_PLL_CNTRL and waits for lock, done by dsiPhyPllStart()
/// below. (First attempt at this driver conflated the two and never
/// actually started the PLL, which is why it just timed out waiting
/// for a lock bit that could never assert -- confirmed on hardware.)
fn dsiPhyPllConfigure(phy_base: usize) void {
    // dsi_pll_enable_pll_bias(): PLL_SHUTDOWNB + SYSTEM_MUXES=0xc0.
    mmioSetBits32(phy_base, CMN_CTRL_0, CTRL_0_PLL_SHUTDOWNB);
    mmioWrite32(phy_base + PLL_BASE_OFFSET, PLL_SYSTEM_MUXES, 0xc0);
    // Source wants ndelay(250); U-Boot only exports udelay(), so round
    // up to the finest available granularity.
    udelay(1);

    dsiPhyPllCommitRate(phy_base);
    dsiPhyPllConfigHzIndep(phy_base);
    // SSC is disabled in the vendor driver (dsi_pll_setup_config():
    // config->enable_ssc = false, "TODO: ssc enable") -- no SSC writes.
}

/// dsi_pll_7nm_vco_prepare(): actually start the PLL (CMN_PLL_CNTRL
/// bit0) and wait for lock. Master-PHY-only -- the slave receives its
/// bit clock over the sync-dual-dsi hardware link once the master is
/// running, it has no PLL of its own to start.
fn dsiPhyPllStart(phy_base: usize) c_int {
    mmioWrite32(phy_base, CMN_PLL_CNTRL, 0x1);

    var waited: u32 = 0;
    while (waited < PLL_LOCK_POLL2_TIMEOUT_US) : (waited += 100) {
        const status = mmioRead32(phy_base + PLL_BASE_OFFSET, PLL_COMMON_STATUS_ONE);
        if ((status & PLL_LOCK_STATUS_BIT) != 0) return 0;
        udelay(100);
    }
    return ETIMEDOUT;
}

/// dsi_pll_phy_dig_reset() + dsi_pll_enable_global_clk() +
/// REG_DSI_7nm_PHY_CMN_RBUF_CTRL=1, from the tail of
/// dsi_pll_7nm_vco_prepare(). Applies to BOTH master and slave PHYs
/// (source calls these for pll_7nm and, if present, pll_7nm->slave --
/// each write targets that specific PHY's own `base`, there's no
/// cross-PHY register access here despite this being logically part
/// of the "master's prepare" call in the clk-framework model).
fn dsiPhyDigResetAndClkEnable(phy_base: usize) void {
    // Reset the PHY digital domain (pulse).
    mmioWrite32(phy_base, CMN_GLBL_DIGTOP_SPARE4, 0x1);
    mmioWrite32(phy_base, CMN_GLBL_DIGTOP_SPARE4, 0x0);

    mmioWrite32(phy_base, CMN_CTRL_3, 0x04);
    mmioSetBits32(phy_base, CMN_CLK_CFG1, CLK_CFG1_CLK_EN | CLK_CFG1_CLK_EN_SEL);

    mmioWrite32(phy_base, CMN_RBUF_CTRL, 0x1);
}

fn dsiPhyLaneSettings(phy_base: usize) void {
    const lane = phy_base + LANE_BASE_OFFSET;
    const tx_dctrl = [5]u32{ 0x40, 0x40, 0x40, 0x46, 0x41 }; // !QUIRK_V4_0 table

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        mmioWrite32(lane, i * LANE_STRIDE + LN_LPRX_CTRL, 0);
        mmioWrite32(lane, i * LANE_STRIDE + LN_PIN_SWAP, 0);
    }
    // Enable LPRX/CDRX only for the physical lane matching logical
    // lane 0 (phy_lane_0 = 0; lane swap config not supported here).
    mmioWrite32(lane, 0 * LANE_STRIDE + LN_LPRX_CTRL, 0x3);

    i = 0;
    while (i < 5) : (i += 1) {
        mmioWrite32(lane, i * LANE_STRIDE + LN_CFG0, 0x0);
        mmioWrite32(lane, i * LANE_STRIDE + LN_CFG1, 0x0);
        mmioWrite32(lane, i * LANE_STRIDE + LN_CFG2, if (i == 4) @as(u32, 0x8a) else @as(u32, 0xa));
        mmioWrite32(lane, i * LANE_STRIDE + LN_TX_DCTRL, tx_dctrl[i]);
    }
}

/// Bring up the DSI PHY (voltage swing, PLL lock) for the given DSI
/// instance. `dsi_phy_base` is qcom,sm8550-dsi-phy-4nm reg base.
/// `is_master` selects DSI0 (true, drives its own internal PLL) vs
/// DSI1 (false, sources its bit clock from DSI0's PLL over the
/// qcom,sync-dual-dsi link) -- see dsi_7nm_set_usecase() /
/// MSM_DSI_PHY_MASTER/SLAVE. Our panel is dual-DSI split-link, so
/// this must be called for both DSI0 (is_master=true) and DSI1
/// (is_master=false).
export fn sheng_mdss_dsi_phy_init(dsi_phy_base: usize, is_master: bool) callconv(.c) c_int {
    // Request REFGEN READY (DSI_PHY_7NM_QUIRK_V5_2 path).
    mmioWrite32(dsi_phy_base, CMN_GLBL_DIGTOP_SPARE10, 0x1);
    udelay(500);

    var waited: u32 = 0;
    while (waited < REFGEN_READY_TIMEOUT_US) : (waited += 5) {
        const status = mmioRead32(dsi_phy_base, CMN_PHY_STATUS);
        if ((status & 0x1) != 0) break;
        udelay(5);
    } else {
        return EREFGENTIMEDOUT;
    }

    // less_than_1500_mhz path (bitclk_rate 1,190,717,578 <= 1.5GHz),
    // !cphy_mode, DSI_PHY_7NM_QUIRK_V5_2 branch.
    const vreg_ctrl_0: u32 = 0x44;
    const vreg_ctrl_1: u32 = 0x19;
    const glbl_hstx_str_ctrl_0: u32 = 0x88;
    const glbl_pemph_ctrl_0: u32 = 0x00;
    const lane_ctrl0: u32 = 0x1f;
    const glbl_str_swi_cal_sel_ctrl: u32 = 0x00;
    const glbl_rescode_top_ctrl: u32 = 0x3c;
    const glbl_rescode_bot_ctrl: u32 = 0x38;

    // de-assert digital and pll power down
    mmioWrite32(dsi_phy_base, CMN_CTRL_0, CTRL_0_DIGTOP_PWRDN_B | CTRL_0_PLL_SHUTDOWNB);
    // assert PLL core reset
    mmioWrite32(dsi_phy_base, CMN_PLL_CNTRL, 0x00);
    // turn off resync FIFO
    mmioWrite32(dsi_phy_base, CMN_RBUF_CTRL, 0x00);
    // minor_ver 2 chipset (V5_2 quirk applies unconditionally here)
    mmioWrite32(dsi_phy_base, CMN_CTRL_4, 0x04);

    // lane swap (identity -- not calculated, matches upstream TODO)
    mmioWrite32(dsi_phy_base, CMN_LANE_CFG0, 0x21);
    mmioWrite32(dsi_phy_base, CMN_LANE_CFG1, 0x84);

    mmioWrite32(dsi_phy_base, CMN_VREG_CTRL_0, vreg_ctrl_0);
    mmioWrite32(dsi_phy_base, CMN_VREG_CTRL_1, vreg_ctrl_1);
    mmioWrite32(dsi_phy_base, CMN_CTRL_3, 0x00);
    mmioWrite32(dsi_phy_base, CMN_GLBL_STR_SWI_CAL_SEL_CTRL, glbl_str_swi_cal_sel_ctrl);
    mmioWrite32(dsi_phy_base, CMN_GLBL_HSTX_STR_CTRL_0, glbl_hstx_str_ctrl_0);
    mmioWrite32(dsi_phy_base, CMN_GLBL_PEMPH_CTRL_0, glbl_pemph_ctrl_0);
    mmioWrite32(dsi_phy_base, CMN_GLBL_RESCODE_OFFSET_TOP_CTRL, glbl_rescode_top_ctrl);
    mmioWrite32(dsi_phy_base, CMN_GLBL_RESCODE_OFFSET_BOT_CTRL, glbl_rescode_bot_ctrl);
    mmioWrite32(dsi_phy_base, CMN_GLBL_LPTX_STR_CTRL, 0x55);

    // remove power down from all blocks
    mmioWrite32(dsi_phy_base, CMN_CTRL_0, 0x7f);
    mmioWrite32(dsi_phy_base, CMN_LANE_CTRL0, lane_ctrl0);
    // full-rate mode (dphy, not cphy)
    mmioWrite32(dsi_phy_base, CMN_CTRL_2, 0x40);

    // dsi_7nm_set_usecase(): BITCLK_SEL=0 (internal PLL) for master
    // (DSI0), =1 (external/shared PLL) for slave (DSI1).
    {
        var cfg1 = mmioRead32(dsi_phy_base, CMN_CLK_CFG1);
        cfg1 &= ~CLK_CFG1_BITCLK_SEL_MASK;
        if (!is_master) cfg1 |= (0x1 << 2) & CLK_CFG1_BITCLK_SEL_MASK;
        mmioWrite32(dsi_phy_base, CMN_CLK_CFG1, cfg1);
    }

    // DSI PHY timings (dphy, not cphy)
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_0, 0x00);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_1, TIMING_CLK_ZERO);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_2, TIMING_CLK_PREPARE);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_3, TIMING_CLK_TRAIL);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_4, TIMING_HS_EXIT);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_5, TIMING_HS_ZERO);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_6, TIMING_HS_PREPARE);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_7, TIMING_HS_TRAIL);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_8, TIMING_HS_RQST);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_9, 0x02);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_10, 0x04);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_11, 0x00);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_12, TIMING_CLK_PRE);
    mmioWrite32(dsi_phy_base, CMN_TIMING_CTRL_13, TIMING_CLK_POST);

    dsiPhyLaneSettings(dsi_phy_base);

    // Only the master (DSI0) drives its own PLL; the slave (DSI1)
    // receives its bit clock over the sync-dual-dsi link instead. Both
    // still need the digital-reset/global-clk/RBUF_CTRL tail that
    // dsi_pll_7nm_vco_prepare() applies to master+slave together.
    if (is_master) {
        dsiPhyPllConfigure(dsi_phy_base);
        const ret = dsiPhyPllStart(dsi_phy_base);
        if (ret != 0) return ret;
    }
    dsiPhyDigResetAndClkEnable(dsi_phy_base);

    return 0;
}

// --- DSI host controller (dsi_host.c). Register offsets from
// drivers/gpu/drm/msm/registers/display/dsi.xml (same missing-
// generated-header situation as the PHY -- taken from the rnndb
// source). All offsets relative to the qcom,sm8550-dsi-ctrl reg base.
const DSI_CTRL: usize = 0x000;
const DSI_STATUS0: usize = 0x004;
const DSI_DMA_BASE: usize = 0x044;
const DSI_DMA_LEN: usize = 0x048;
const DSI_TRIG_CTRL: usize = 0x080;
const DSI_TRIG_DMA: usize = 0x08c;
const DSI_CLK_CTRL: usize = 0x118;
const DSI_RESET: usize = 0x114;

const CTRL_ENABLE: u32 = 1 << 0;
const CTRL_VID_MODE_EN: u32 = 1 << 1;
const CTRL_CMD_MODE_EN: u32 = 1 << 2;
const CTRL_CLK_EN: u32 = 1 << 8;
const STATUS0_CMD_MODE_DMA_BUSY: u32 = 1 << 1;
const CLK_CTRL_ENABLE_CLKS: u32 = 0x3f | (1 << 9); // AHBS/AHBM/PCLK/DSICLK/BYTECLK/ESCCLK on + FORCE_ON_DYN_AHBM_HCLK
const TRIG_CTRL_DMA_TRIGGER_SW: u32 = 4; // dsi_cmd_trigger.TRIGGER_SW, low 3 bits
const TRIG_CTRL_TE: u32 = 1 << 31;

const DMA_BUSY_POLL_TIMEOUT_US: u32 = 20000; // 200ms, matching wait_for_completion_timeout in source

/// qcom,sm8550-dsi-phy-4nm has 4 data lanes wired (LANE0-3 = bits
/// 4-7 of DSI_CTRL) per the panel's `.lanes = 4` in
/// panel-novatek-nt36532e.c.
const CTRL_ALL_LANES: u32 = 0xf << 4;

fn dsiHostBringUp(dsi_base: usize) void {
    mmioWrite32(dsi_base, DSI_CLK_CTRL, CLK_CTRL_ENABLE_CLKS);
    mmioWrite32(dsi_base, DSI_CTRL, CTRL_CLK_EN | CTRL_ALL_LANES | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    mmioWrite32(dsi_base, DSI_TRIG_CTRL, TRIG_CTRL_TE | TRIG_CTRL_DMA_TRIGGER_SW);
}

/// Switch the DSI host from command mode (used for the panel init DCS
/// blast) to video mode, matching dsi_op_mode_config(video_mode=true)
/// in dsi_host.c. Must happen before the DPU INTF timing engine starts
/// pushing continuous pixel data -- leaving CMD_MODE_EN set while the
/// DPU drives a live video timing engine into this controller is a
/// real hardware mode mismatch, not just "wrong colors".
fn dsiHostSwitchToVideoMode(dsi_base: usize) void {
    var ctrl = mmioRead32(dsi_base, DSI_CTRL);
    ctrl &= ~CTRL_CMD_MODE_EN;
    ctrl |= CTRL_VID_MODE_EN | CTRL_ENABLE;
    mmioWrite32(dsi_base, DSI_CTRL, ctrl);
}

/// Builds the "MSM specific command format" dsi_cmd_dma_add() uses
/// (NOT the raw MIPI wire format -- the DMA engine computes DCS
/// packet ECC/CRC itself from this): 4-byte header
/// [dcs_cmd_or_len_lo, arg0_or_len_hi, data_id, flags] followed by
/// payload for long writes, then the whole thing padded to a 4-byte
/// boundary with 0xff (matching `len = (packet.size + 3) & ~0x3`).
/// Packet type selection mirrors mipi_dsi_dcs_write_buffer(): 1 byte
/// (cmd only) -> DCS_SHORT_WRITE (0x05), 2 bytes ->
/// DCS_SHORT_WRITE_PARAM (0x15), 3+ bytes -> DCS_LONG_WRITE (0x39).
/// Returns the padded length written into `buf`, or 0 if it doesn't fit.
fn buildMsmCmdPacket(buf: []u8, cmd: u8, args: []const u8) usize {
    const total_len = 1 + args.len;
    var size: usize = undefined;

    if (total_len <= 2) {
        buf[0] = cmd;
        buf[1] = if (args.len > 0) args[0] else 0;
        buf[2] = if (total_len == 1) @as(u8, 0x05) else @as(u8, 0x15);
        buf[3] = 0x80; // last packet, not long, not read
        size = 4;
    } else {
        if (4 + total_len > buf.len) return 0;
        buf[0] = @truncate(total_len & 0xff);
        buf[1] = @truncate((total_len >> 8) & 0xff);
        buf[2] = 0x39;
        buf[3] = 0x80 | 0x40; // last packet, long
        buf[4] = cmd;
        for (args, 0..) |a, i| buf[5 + i] = a;
        size = 4 + total_len;
    }

    const padded = (size + 3) & ~@as(usize, 0x3);
    var i: usize = size;
    while (i < padded) : (i += 1) buf[i] = 0xff;
    return padded;
}

/// Commits DMA_BASE/DMA_LEN and fires TRIG_DMA on one DSI host, then
/// waits for CMD_MODE_DMA_BUSY to clear -- msm_dsi_host_cmd_xfer_commit()
/// + dsi_cmd_dma_tx()'s completion wait, polled instead of IRQ-driven.
fn dsiCmdDmaTxOne(dsi_base: usize, dma_addr: usize, len: usize) c_int {
    mmioWrite32(dsi_base, DSI_DMA_BASE, @truncate(dma_addr));
    mmioWrite32(dsi_base, DSI_DMA_LEN, @truncate(len));
    mmioWrite32(dsi_base, DSI_TRIG_DMA, 1);

    var waited: u32 = 0;
    while (waited < DMA_BUSY_POLL_TIMEOUT_US) : (waited += 10) {
        const status = mmioRead32(dsi_base, DSI_STATUS0);
        if ((status & STATUS0_CMD_MODE_DMA_BUSY) == 0) return 0;
        udelay(10);
    }
    return ETIMEDOUT;
}

/// Sends one DCS command to both DSI0 and DSI1 from the SAME DMA
/// buffer -- qcom,sync-dual-dsi mirrors every command to both
/// controllers rather than splitting the buffer, matching how the
/// real panel driver only ever issues commands to dsi[0] and relies
/// on hardware mirroring (see nt36532e_init_sequence's comment in
/// this file and sheng_tianma_init_sequence() in the kernel panel
/// driver).
fn dsiSendDcs(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, cmd: u8, args: []const u8) c_int {
    var buf: [16]u8 = undefined;
    const len = buildMsmCmdPacket(&buf, cmd, args);
    if (len == 0) return -22; // -EINVAL-ish, packet too big for our scratch stack buffer

    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    for (buf[0..len], 0..) |b, i| dst[i] = b;

    var ret = dsiCmdDmaTxOne(dsi1_base, dma_scratch, len);
    if (ret != 0) return ret;
    ret = dsiCmdDmaTxOne(dsi0_base, dma_scratch, len);
    if (ret != 0) return ret;
    return 0;
}

/// Sends a raw MIPI DSI long packet with an explicit data_id (NOT a
/// DCS write -- no command-byte prefix, `payload` is the entire wire
/// payload as-is). Used for the DSC Picture Parameter Set
/// (data_id = MIPI_DSI_PICTURE_PARAMETER_SET = 0x0A), which unlike a
/// generic DCS long write isn't "command byte + args".
fn dsiSendRawLong(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, data_id: u8, payload: []const u8) c_int {
    var buf: [4 + 128 + 3]u8 = undefined; // header + PPS payload + padding slack
    if (4 + payload.len > buf.len) return -22;

    buf[0] = @truncate(payload.len & 0xff);
    buf[1] = @truncate((payload.len >> 8) & 0xff);
    buf[2] = data_id;
    buf[3] = 0x80 | 0x40; // last packet, long
    for (payload, 0..) |b, i| buf[4 + i] = b;

    const size = 4 + payload.len;
    const padded = (size + 3) & ~@as(usize, 0x3);
    var i: usize = size;
    while (i < padded) : (i += 1) buf[i] = 0xff;

    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    for (buf[0..padded], 0..) |b, j| dst[j] = b;

    var ret = dsiCmdDmaTxOne(dsi1_base, dma_scratch, padded);
    if (ret != 0) return ret;
    ret = dsiCmdDmaTxOne(dsi0_base, dma_scratch, padded);
    if (ret != 0) return ret;
    return 0;
}

/// Bring up the DSI host controllers and blast the panel's full init
/// sequence: nt36532e_init_sequence, then the DSC-enable/PPS/
/// framerate/exit-sleep/display-on tail sheng_tianma_init_sequence()
/// does in the real kernel panel driver after the point where
/// nt36532e_init_sequence's table (deliberately) stops. `dma_scratch`
/// needs to hold the largest single packet we send -- the 128-byte
/// PPS plus its 4-byte header, so >= 132 bytes.
///
/// NOT included here (real gap, needs separate follow-up): the
/// panel's own reset-gpio pulse and vddio/avdd/avee regulator enable
/// that nt36532e_prepare() does before sending any DCS command --
/// U-Boot's devicetree has no panel node to read those from (unlike
/// Linux's), so they'd need to be hardcoded from schematic/downstream
/// knowledge rather than read from DT. Without them the panel may
/// simply not be in a receptive state, independent of whether this
/// DSI command engine itself works correctly.
/// `enable_dsc`: the real panel bring-up needs DSC (video-mode pixel
/// rate requires it -- see this file's own topology comment below), but
/// the DPU write hang (SPEC.md task #5) meant the DSC-enabled panel was
/// never actually fed compressed frames. sheng_mdss_dsi_test_patch()
/// (below) is a DPU-bypass proof-of-concept that pushes a small
/// *uncompressed* RGB888 patch directly over the command-mode DSI DMA
/// engine -- if DSC were left enabled, the panel would try to DSC-decode
/// that raw data as compressed and very likely show garbage or nothing.
/// Pass false to leave DSC off (skips the 0x90/PPS/0x9d/framerate-branch
/// block entirely) for that test; real use should pass true.
export fn sheng_mdss_dsi_panel_init(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, enable_dsc: bool) callconv(.c) c_int {
    dsiHostBringUp(dsi0_base);
    dsiHostBringUp(dsi1_base);

    for (nt36532e_init_sequence) |entry| {
        const ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, entry.cmd, entry.args);
        if (ret != 0) return ret;
    }

    if (enable_dsc) {
        // Enable DSC.
        var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x90, &[_]u8{0x03});
        if (ret != 0) return ret;

        // DSC Picture Parameter Set.
        ret = dsiSendRawLong(dsi0_base, dsi1_base, dma_scratch, 0x0a, &nt36532e_pps_144hz);
        if (ret != 0) return ret;

        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x9d, &[_]u8{0x01});
        if (ret != 0) return ret;

        // 144Hz framerate control branch.
        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0xb2, &[_]u8{0x91});
        if (ret != 0) return ret;
        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0xb3, &[_]u8{0x40});
        if (ret != 0) return ret;
    }

    // Exit sleep mode (MIPI DCS 0x11, no args), then the panel needs
    // 120ms before it'll accept display-on.
    var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x11, &[_]u8{});
    if (ret != 0) return ret;
    // mdelay() is a U-Boot macro (udelay(n*1000)), not a linkable
    // symbol -- call udelay directly instead.
    udelay(120000);

    // Set display on (MIPI DCS 0x29, no args).
    ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x29, &[_]u8{});
    if (ret != 0) return ret;

    return 0;
}

/// DPU-bypass proof-of-concept (SPEC.md task #5): pushes a small solid-
/// color RGB888 patch directly to the panel over the already-proven
/// command-mode DSI DMA engine, entirely without touching the DPU
/// (0xae01000+, where every write has hung this session). Caller must
/// have called sheng_mdss_dsi_panel_init(..., enable_dsc=false) first --
/// DSC must stay off, or the panel will try to DSC-decode this raw data.
/// Sets a 16x16 pixel column/page address window (MIPI DCS 0x2A/0x2B),
/// then a write_memory_start (0x2C) DCS long write with 16*16=256 solid
/// red RGB888 pixels (768 bytes) as its payload. The write_memory_start
/// packet is built directly in the DMA scratch buffer rather than going
/// through dsiSendDcs() (whose internal buffer is only 16 bytes, far
/// too small here) -- same MSM command-packet framing
/// buildMsmCmdPacket() uses for its own long-write path:
/// [len_lo,len_hi,0x39,0x80|0x40][cmd byte][payload...], padded to a
/// 4-byte boundary with 0xff.
const TEST_PATCH_W: usize = 16;
const TEST_PATCH_H: usize = 16;

export fn sheng_mdss_dsi_test_patch(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) c_int {
    var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x2a, &[_]u8{ 0x00, 0x00, 0x00, @as(u8, TEST_PATCH_W - 1) });
    if (ret != 0) return ret;

    ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x2b, &[_]u8{ 0x00, 0x00, 0x00, @as(u8, TEST_PATCH_H - 1) });
    if (ret != 0) return ret;

    const npix: usize = TEST_PATCH_W * TEST_PATCH_H;
    const total_len: usize = 1 + npix * 3; // DCS cmd byte + RGB888 pixel data
    const size: usize = 4 + total_len;
    const padded: usize = (size + 3) & ~@as(usize, 0x3);

    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    dst[0] = @truncate(total_len & 0xff);
    dst[1] = @truncate((total_len >> 8) & 0xff);
    dst[2] = 0x39; // DCS long write
    dst[3] = 0x80 | 0x40; // last packet, long
    dst[4] = 0x2c; // write_memory_start

    var i: usize = 0;
    while (i < npix) : (i += 1) {
        dst[5 + i * 3 + 0] = 0xff; // R
        dst[5 + i * 3 + 1] = 0x00; // G
        dst[5 + i * 3 + 2] = 0x00; // B
    }
    var j: usize = size;
    while (j < padded) : (j += 1) dst[j] = 0xff;

    ret = dsiCmdDmaTxOne(dsi1_base, dma_scratch, padded);
    if (ret != 0) return ret;
    ret = dsiCmdDmaTxOne(dsi0_base, dma_scratch, padded);
    return ret;
}

// ---------------------------------------------------------------------
// DPU pixel pipeline (task #5)
//
// Topology confirmed from live DPU debugfs state (see SPEC.md): a
// single SSPP (sspp_8 = SSPP_DMA0, DMA-type pipe, catalog base
// +0x24000) using multirect -- rect_0 is the left half of the
// framebuffer, rect_1 the right half -- feeding two independent
// LM -> PINGPONG -> DSC -> INTF chains, one per DSI half:
//
//   sspp_8 rect_0 (left  1524x2032+0+0)    -> LM_0 -> PP_0 -> DSC_0 -> INTF_1 -> DSI0 (master)
//   sspp_8 rect_1 (right 1524x2032+1524+0) -> LM_1 -> PP_1 -> DSC_1 -> INTF_2 -> DSI1 (slave)
//   CTL_0 orchestrates + flushes all of the above atomically.
//
// INTF_0 (base +0x34000) is type INTF_DP on this catalog (dpu_9_0_sm8550.h)
// -- NOT usable for DSI. The two DSI-capable interfaces are INTF_1
// (+0x35000, controller_id 0 == DSI0) and INTF_2 (+0x36000, controller_id
// 1 == DSI1). This corrects an earlier (wrong) assumption in SPEC.md's
// continuation guide that used INTF_0/INTF_1.
//
// All register offsets/sequencing below are ported directly from
// dpu_hw_sspp.c, dpu_hw_lm.c, dpu_hw_pingpong.c, dpu_hw_dsc_1_2.c (the
// hard-slice DSC variant -- catalog/dpu_rm.c selects this over the
// plain dpu_hw_dsc.c whenever core_major_ver >= 7, which sm8550 (9.0)
// is), dpu_hw_intf.c and dpu_hw_ctl.c in the mainline kernel checkout,
// specialized to our fixed single-plane XRGB8888 / single-blendstage /
// dual-hard-slice-DSC / video-mode-DSI case -- not a general port of
// the DPU driver object model.
//
// Panel is confirmed MIPI_DSI_MODE_VIDEO (panel-novatek-nt36532e.c),
// not command mode, so the INTF timing engine drives DSI continuously;
// there's no tearing-effect/vsync wiring here since we only need one
// static frame to appear.

const SSPP_SRC_SIZE: usize = 0x00;
const SSPP_SRC_XY: usize = 0x08;
const SSPP_OUT_SIZE: usize = 0x0c;
const SSPP_OUT_XY: usize = 0x10;
const SSPP_SRC0_ADDR: usize = 0x14;
const SSPP_SRC1_ADDR: usize = 0x18;
const SSPP_SRC_YSTRIDE0: usize = 0x24;
const SSPP_SRC_FORMAT: usize = 0x30;
const SSPP_SRC_UNPACK_PATTERN: usize = 0x34;
const SSPP_SRC_OP_MODE: usize = 0x38;
const SSPP_OUT_SIZE_REC1: usize = 0x160;
const SSPP_OUT_XY_REC1: usize = 0x164;
const SSPP_SRC_XY_REC1: usize = 0x168;
const SSPP_SRC_SIZE_REC1: usize = 0x16c;
const SSPP_MULTIRECT_OPMODE: usize = 0x170;
const SSPP_SRC_FORMAT_REC1: usize = 0x174;
const SSPP_SRC_UNPACK_PATTERN_REC1: usize = 0x178;
const SSPP_SRC_OP_MODE_REC1: usize = 0x17c;

// XRGB8888, computed offline replicating dpu_hw_setup_format_impl()'s
// bit-packing for INTERLEAVED_RGBX_FMT(XRGB8888, 4, BPC8A, BPC8, BPC8,
// BPC8, C1_B_Cb, C0_G_Y, C2_R_Cr, C3_ALPHA) from mdp_format.c.
const SSPP_XRGB8888_SRC_FORMAT: u32 = 0x000236ff;
const SSPP_XRGB8888_UNPACK_PATTERN: u32 = 0x03020001;
const SSPP_OP_MODE_PE_OVERRIDE: u32 = 1 << 23;

// Multirect: TIME_MX mode with rect index in bits[1:0].
const SSPP_MULTIRECT_INDEX_REC0: u32 = 0x0;
const SSPP_MULTIRECT_INDEX_REC1: u32 = 0x1;
const SSPP_MULTIRECT_MODE_TIME_MX: u32 = 1 << 2;

const LM_OP_MODE: usize = 0x00;
const LM_OUT_SIZE: usize = 0x04;
const LM_STAGE0_OFFSET: usize = 0x20; // sdm845_lm_sblk.blendstage_base[0]
const LM_BLEND0_CONST_ALPHA: usize = 0x04;
const LM_BLEND0_OP: usize = 0x00;
// DPU_BLEND_FG_ALPHA_FG_CONST(0<<0) | DPU_BLEND_BG_ALPHA_FG_CONST(0<<8) |
// DPU_BLEND_BG_INV_ALPHA(1<<10): single opaque layer, no blending below it.
const LM_BLEND_OP_OPAQUE: u32 = 1 << 10;
const LM_CONST_ALPHA_OPAQUE: u32 = 0xff | (0xff << 16); // fg/bg alpha = 0xff (>>8 of 0xffff)

const PP_DSC_MODE: usize = 0x0a0;
const PP_DCE_DATA_OUT_SWAP: usize = 0x0c8;

const DSC_CMN_MAIN_CNF: usize = 0x00; // shared by both engines at the DCE base
const DSC_ENC_DF_CTRL: usize = 0x00; // sblk.enc-relative
const DSC_MAIN_CONF: usize = 0x30;
const DSC_PICTURE_SIZE: usize = 0x34;
const DSC_SLICE_SIZE: usize = 0x38;
const DSC_MISC_SIZE: usize = 0x3c;
const DSC_HRD_DELAYS: usize = 0x40;
const DSC_RC_SCALE: usize = 0x44;
const DSC_RC_SCALE_INC_DEC: usize = 0x48;
const DSC_RC_OFFSETS_1: usize = 0x4c;
const DSC_RC_OFFSETS_2: usize = 0x50;
const DSC_RC_OFFSETS_3: usize = 0x54;
const DSC_RC_OFFSETS_4: usize = 0x58;
const DSC_FLATNESS_QP: usize = 0x5c;
const DSC_RC_MODEL_SIZE: usize = 0x60;
const DSC_RC_CONFIG: usize = 0x64;
const DSC_RC_BUF_THRESH_0: usize = 0x68;
const DSC_RC_BUF_THRESH_1: usize = 0x6c;
const DSC_RC_BUF_THRESH_2: usize = 0x70;
const DSC_RC_BUF_THRESH_3: usize = 0x74;
const DSC_RC_MIN_QP_0: usize = 0x78;
const DSC_RC_MIN_QP_1: usize = 0x7c;
const DSC_RC_MIN_QP_2: usize = 0x80;
const DSC_RC_MAX_QP_0: usize = 0x84;
const DSC_RC_MAX_QP_1: usize = 0x88;
const DSC_RC_MAX_QP_2: usize = 0x8c;
const DSC_RC_RANGE_BPG_OFFSETS_0: usize = 0x90;
const DSC_RC_RANGE_BPG_OFFSETS_1: usize = 0x94;
const DSC_RC_RANGE_BPG_OFFSETS_2: usize = 0x98;
// sblk.ctl-relative (dce_0_0.ctl.base=+0xf00, dce_0_1.ctl.base=+0xf80)
const DSC_CTL_MUX: usize = 0x00;
const DSC_CFG: usize = 0x04;

const DSC_MODE_SPLIT_PANEL: u32 = 1 << 0;
const DSC_MODE_VIDEO: u32 = 1 << 2;

const INTF_TIMING_ENGINE_EN: usize = 0x000;
const INTF_CONFIG: usize = 0x004;
const INTF_HSYNC_CTL: usize = 0x008;
const INTF_VSYNC_PERIOD_F0: usize = 0x00c;
const INTF_VSYNC_PULSE_WIDTH_F0: usize = 0x014;
const INTF_DISPLAY_V_START_F0: usize = 0x01c;
const INTF_DISPLAY_V_END_F0: usize = 0x024;
const INTF_ACTIVE_V_START_F0: usize = 0x02c;
const INTF_ACTIVE_V_END_F0: usize = 0x034;
const INTF_DISPLAY_HCTL: usize = 0x03c;
const INTF_ACTIVE_HCTL: usize = 0x040;
const INTF_BORDER_COLOR: usize = 0x044;
const INTF_UNDERFLOW_COLOR: usize = 0x048;
const INTF_HSYNC_SKEW: usize = 0x04c;
const INTF_POLARITY_CTL: usize = 0x050;
const INTF_CONFIG2: usize = 0x060;
const INTF_DISPLAY_DATA_HCTL: usize = 0x064;
const INTF_ACTIVE_DATA_HCTL: usize = 0x068;
const INTF_FRAME_LINE_COUNT_EN: usize = 0x0a8;
const INTF_PANEL_FORMAT: usize = 0x090;
const INTF_MUX: usize = 0x25c;

const INTF_CFG2_DATABUS_WIDEN: u32 = 1 << 0;
const INTF_CFG2_DCE_DATA_COMPRESS: u32 = 1 << 1;
const INTF_CFG2_DATA_HCTL_EN: u32 = 1 << 4;
// panel_format: BPC8 (0b00) for R/G/B, unpack count field bits[9:8]=0x21 as
// captured in dpu_hw_intf_setup_timing_engine's non-YUV branch.
const INTF_PANEL_FORMAT_RGB888: u32 = 0x21 << 8;

const CTL_LAYER0: usize = 0x000; // CTL_LAYER(LM_0): (lm-LM_0)*4
const CTL_LAYER1: usize = 0x004; // CTL_LAYER(LM_1)
const CTL_LAYER_EXT2_0: usize = 0x070; // CTL_LAYER_EXT2(LM_0): 0x70+(lm-LM_0)*4
const CTL_LAYER_EXT2_1: usize = 0x074; // CTL_LAYER_EXT2(LM_1)
const CTL_TOP: usize = 0x014;
const CTL_FLUSH: usize = 0x018;
const CTL_START: usize = 0x01c;
const CTL_INTF_ACTIVE: usize = 0x0f4;
const CTL_DSC_ACTIVE: usize = 0x0e8;
const CTL_INTF_MASTER: usize = 0x134;
const CTL_DSC_FLUSH: usize = 0x104;
const CTL_INTF_FLUSH: usize = 0x110;

const CTL_MIXER_BORDER_OUT: u32 = 1 << 24;
const CTL_FLUSH_MASK_CTL: u32 = 1 << 17;
const CTL_FLUSH_SSPP_DMA0: u32 = 1 << 11; // dpu_hw_ctl.c fetch_tbl[SSPP_DMA0]... ctl flush bit, not fetch id
const CTL_FLUSH_LM0: u32 = 1 << 6;
const CTL_FLUSH_LM1: u32 = 1 << 7;
const CTL_FLUSH_DSC_IDX: u32 = 1 << 22;
const CTL_FLUSH_INTF_IDX: u32 = 1 << 31;
const CTL_DEFAULT_GROUP_ID_SHIFTED: u32 = 0xf << 28;

// Bisection aid: since there is no working U-Boot console, we can't see
// where a hang happens directly. Each numbered checkpoint below lets a
// test build return 0 right after that phase's writes so boot proceeds
// normally to Linux and the (already working) sheng,mdss-status relay
// confirms whether we got that far without the CPU/bus wedging. Bump
// this and reflash to bisect; set to 99 for the real full sequence.
const DPU_TEST_STOP_STAGE: u32 = 1;

fn dpuHwWrite(dpu_base: usize, block_off: usize, reg_off: usize, value: u32) void {
    mmioWrite32(dpu_base, block_off + reg_off, value);
}

fn dpuHwRead(dpu_base: usize, block_off: usize, reg_off: usize) u32 {
    return mmioRead32(dpu_base, block_off + reg_off);
}

const DSC_RC_MIN_QP = [15]u32{ 0, 0, 1, 1, 3, 3, 3, 3, 3, 3, 5, 5, 5, 7, 13 };
const DSC_RC_MAX_QP = [15]u32{ 4, 4, 5, 6, 7, 7, 7, 8, 9, 10, 11, 12, 13, 13, 15 };
// 2's complement 6-bit range_bpg_offset values, per-entry: 2 0 0 -2 -4 -6 -8 -8 -8 -10 -10 -12 -12 -12 -12
const DSC_RC_BPG_OFFSET = [15]u32{
    2 & 0x3f,      0,        0,        (-2) & 0x3f, (-4) & 0x3f,
    (-6) & 0x3f,   (-8) & 0x3f, (-8) & 0x3f, (-8) & 0x3f, (-10) & 0x3f,
    (-10) & 0x3f,  (-12) & 0x3f, (-12) & 0x3f, (-12) & 0x3f, (-12) & 0x3f,
};
const DSC_RC_BUF_THRESH = [14]u32{ 14, 28, 42, 56, 70, 84, 98, 105, 112, 119, 121, 123, 125, 126 };

/// Configure one DSC 1.2 hard-slice encoder instance (DSC_0 or DSC_1)
/// for our fixed panel mode. `dce_base` is the DCE block base
/// (dpu_base+0x80000, shared by both instances); `enc_off`/`ctl_off`
/// are the per-instance sblk.enc/sblk.ctl sub-offsets.
fn dscConfigureInstance(dce_base: usize, enc_off: usize, ctl_off: usize, pp_idx: u32) void {
    // DSC_CMN_MAIN_CNF: shared register, written identically by both
    // instances -- SPLIT_PANEL (dual hard-slice, one soft slice each,
    // no MULTIPLEX) with num_active_slice_per_enc=1 in bits[8:7].
    dpuHwWrite(dce_base, 0, DSC_CMN_MAIN_CNF, (DSC_MODE_SPLIT_PANEL & 1) | (@as(u32, 1) << 7));

    // ENC_DF_CTRL: initial_lines(8) | VIDEO_MODE(bit9) | max_addr(bits[18+])
    // max_addr = 2400/num_softslice - 1 = 2400/1 - 1 = 2399.
    const initial_lines: u32 = 2;
    const max_addr: u32 = 2400 - 1;
    dpuHwWrite(dce_base, enc_off, DSC_ENC_DF_CTRL, (initial_lines & 0xff) | (1 << 9) | (max_addr << 18));

    // DSC_MAIN_CONF: version_minor(28) | bpp(10, U6.4=128) |
    // block_pred_enable(20) | convert_rgb(4, =0 per panel driver) |
    // line_buf_depth(6,4bit) | bits_per_component(0,4bit)
    var main_conf: u32 = (@as(u32, 1) << 28); // dsc_version_minor = 1
    main_conf |= (@as(u32, 8 << 4)) << 10; // bits_per_pixel = 8.0bpp in U6.4
    main_conf |= 1 << 20; // block_pred_enable
    main_conf |= (9 & 0xf) << 6; // line_buf_depth
    main_conf |= 8 & 0xf; // bits_per_component
    dpuHwWrite(dce_base, enc_off, DSC_MAIN_CONF, main_conf);

    dpuHwWrite(dce_base, enc_off, DSC_PICTURE_SIZE, (1524 & 0xffff) | (@as(u32, 2032) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_SLICE_SIZE, (762 & 0xffff) | (@as(u32, 16) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_MISC_SIZE, 762 & 0xffff);
    dpuHwWrite(dce_base, enc_off, DSC_HRD_DELAYS, (512 & 0xffff) | (@as(u32, 637) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_SCALE, 32 & 0x3f);
    dpuHwWrite(dce_base, enc_off, DSC_RC_SCALE_INC_DEC, (454 & 0xffff) | (@as(u32, 10 & 0x7ff) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_1, (12 & 0x1f)); // first_line_bpg_offset only, second_line=0
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_2, (1639 & 0xffff) | (@as(u32, 1154) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_3, (6144 & 0xffff) | (@as(u32, 4336) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_4, 0); // nsl_bpg_offset/second_line_offset_adj unused (dsc v1.1)

    // flatness det_thresh = 2^(bpc-8+8)=... drm_dsc_flatness_det_thresh()
    // for bpc=8 is a fixed constant of 7 << (bpc - 8) = 7.
    const det_thresh_flatness: u32 = 7;
    dpuHwWrite(dce_base, enc_off, DSC_FLATNESS_QP, (3 & 0x1f) | (@as(u32, 12 & 0x1f) << 5) | (det_thresh_flatness << 10));
    dpuHwWrite(dce_base, enc_off, DSC_RC_MODEL_SIZE, 8192 & 0xffff);

    var rc_config: u32 = 6 & 0xf; // rc_edge_factor
    rc_config |= (11 & 0x1f) << 8; // rc_quant_incr_limit0
    rc_config |= (11 & 0x1f) << 13; // rc_quant_incr_limit1
    rc_config |= (3 & 0xf) << 20; // rc_tgt_offset_high
    rc_config |= (3 & 0xf) << 24; // rc_tgt_offset_low
    dpuHwWrite(dce_base, enc_off, DSC_RC_CONFIG, rc_config);

    dpuHwWrite(dce_base, enc_off, DSC_RC_BUF_THRESH_0, DSC_RC_BUF_THRESH[0] | (DSC_RC_BUF_THRESH[1] << 8) |
        (DSC_RC_BUF_THRESH[2] << 16) | (DSC_RC_BUF_THRESH[3] << 24));
    dpuHwWrite(dce_base, enc_off, DSC_RC_BUF_THRESH_1, DSC_RC_BUF_THRESH[4] | (DSC_RC_BUF_THRESH[5] << 8) |
        (DSC_RC_BUF_THRESH[6] << 16) | (DSC_RC_BUF_THRESH[7] << 24));
    dpuHwWrite(dce_base, enc_off, DSC_RC_BUF_THRESH_2, DSC_RC_BUF_THRESH[8] | (DSC_RC_BUF_THRESH[9] << 8) |
        (DSC_RC_BUF_THRESH[10] << 16) | (DSC_RC_BUF_THRESH[11] << 24));
    dpuHwWrite(dce_base, enc_off, DSC_RC_BUF_THRESH_3, DSC_RC_BUF_THRESH[12] | (DSC_RC_BUF_THRESH[13] << 8));

    dpuHwWrite(dce_base, enc_off, DSC_RC_MIN_QP_0, DSC_RC_MIN_QP[0] | (DSC_RC_MIN_QP[1] << 5) |
        (DSC_RC_MIN_QP[2] << 10) | (DSC_RC_MIN_QP[3] << 15) | (DSC_RC_MIN_QP[4] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_MAX_QP_0, DSC_RC_MAX_QP[0] | (DSC_RC_MAX_QP[1] << 5) |
        (DSC_RC_MAX_QP[2] << 10) | (DSC_RC_MAX_QP[3] << 15) | (DSC_RC_MAX_QP[4] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_RANGE_BPG_OFFSETS_0, DSC_RC_BPG_OFFSET[0] | (DSC_RC_BPG_OFFSET[1] << 6) |
        (DSC_RC_BPG_OFFSET[2] << 12) | (DSC_RC_BPG_OFFSET[3] << 18) | (DSC_RC_BPG_OFFSET[4] << 24));

    dpuHwWrite(dce_base, enc_off, DSC_RC_MIN_QP_1, DSC_RC_MIN_QP[5] | (DSC_RC_MIN_QP[6] << 5) |
        (DSC_RC_MIN_QP[7] << 10) | (DSC_RC_MIN_QP[8] << 15) | (DSC_RC_MIN_QP[9] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_MAX_QP_1, DSC_RC_MAX_QP[5] | (DSC_RC_MAX_QP[6] << 5) |
        (DSC_RC_MAX_QP[7] << 10) | (DSC_RC_MAX_QP[8] << 15) | (DSC_RC_MAX_QP[9] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_RANGE_BPG_OFFSETS_1, DSC_RC_BPG_OFFSET[5] | (DSC_RC_BPG_OFFSET[6] << 6) |
        (DSC_RC_BPG_OFFSET[7] << 12) | (DSC_RC_BPG_OFFSET[8] << 18) | (DSC_RC_BPG_OFFSET[9] << 24));

    dpuHwWrite(dce_base, enc_off, DSC_RC_MIN_QP_2, DSC_RC_MIN_QP[10] | (DSC_RC_MIN_QP[11] << 5) |
        (DSC_RC_MIN_QP[12] << 10) | (DSC_RC_MIN_QP[13] << 15) | (DSC_RC_MIN_QP[14] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_MAX_QP_2, DSC_RC_MAX_QP[10] | (DSC_RC_MAX_QP[11] << 5) |
        (DSC_RC_MAX_QP[12] << 10) | (DSC_RC_MAX_QP[13] << 15) | (DSC_RC_MAX_QP[14] << 20));
    dpuHwWrite(dce_base, enc_off, DSC_RC_RANGE_BPG_OFFSETS_2, DSC_RC_BPG_OFFSET[10] | (DSC_RC_BPG_OFFSET[11] << 6) |
        (DSC_RC_BPG_OFFSET[12] << 12) | (DSC_RC_BPG_OFFSET[13] << 18) | (DSC_RC_BPG_OFFSET[14] << 24));

    // DSC_CFG (wrapper enable, sblk.ctl-relative): encoder enable(0) |
    // bits_per_component==8(11) | SPLIT_PANEL(12). native_420/422 and
    // !convert_rgb(10) bits stay clear (convert_rgb=0 per panel driver
    // means we'd normally set bit10, but nt36532e's dsc struct leaves
    // convert_rgb at its zero-value default, i.e. NOT converting RGB->
    // YCoCg -- so bit10 (which fires on !convert_rgb) must be set).
    var dsc_cfg: u32 = 1 << 0; // encoder enable
    dsc_cfg |= 1 << 10; // !convert_rgb
    dsc_cfg |= 1 << 11; // bits_per_component == 8
    dsc_cfg |= 1 << 12; // SPLIT_PANEL mode
    dsc_cfg |= 1 << 17; // !VIDEO_MODE would set this -- we ARE video mode, leave clear
    dsc_cfg &= ~@as(u32, 1 << 17);
    dpuHwWrite(dce_base, ctl_off, DSC_CFG, dsc_cfg);

    // DSC_CTL: bind this encoder's output mux to its pingpong block.
    dpuHwWrite(dce_base, ctl_off, DSC_CTL_MUX, pp_idx & 0x7);
}

/// Configure the DPU SSPP to source from `fb_addr` and the INTF timing
/// engine with the panel's blanking timings, then kick off the pipeline.
/// `dpu_base` is qcom,sm8550-dpu reg base. `hactive`/`vactive` are the
/// FULL panel resolution (3048x2032); this function derives the
/// per-DSI-half (1524-wide) SSPP/LM/DSC/INTF parameters itself.
export fn sheng_mdss_dpu_start(
    dpu_base: usize,
    dsi0_base: usize,
    dsi1_base: usize,
    fb_addr: usize,
    hactive: u32,
    vactive: u32,
    hfront_porch: u32,
    hback_porch: u32,
    hsync_width: u32,
    vfront_porch: u32,
    vback_porch: u32,
    vsync_width: u32,
) callconv(.c) c_int {
    const half_w: u32 = hactive / 2; // 1524
    const stride: u32 = hactive * 4; // XRGB8888, full-scanline stride
    const half_stride: u32 = stride / 2;

    const ctl_base = dpu_base + 0x15000;
    const sspp_base = dpu_base + 0x24000;
    const lm0_base = dpu_base + 0x44000;
    const lm1_base = dpu_base + 0x45000;
    const pp0_base = dpu_base + 0x69000;
    const pp1_base = dpu_base + 0x6a000;
    const dce_base = dpu_base + 0x80000;
    const intf1_base = dpu_base + 0x35000; // DSI0 (master)
    const intf2_base = dpu_base + 0x36000; // DSI1 (slave)

    // -- SSPP: single DMA pipe, multirect TIME_MX, rect0=left half,
    // rect1=right half of the framebuffer.
    mmioWrite32(sspp_base, SSPP_SRC_SIZE, (vactive << 16) | hactive);
    mmioWrite32(sspp_base, SSPP_SRC_XY, 0);
    mmioWrite32(sspp_base, SSPP_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_OUT_XY, 0);
    mmioWrite32(sspp_base, SSPP_SRC0_ADDR, @truncate(fb_addr));
    // YSTRIDE0 packs BOTH rects' plane-0 pitch: low16=rect0, high16=rect1
    // (dpu_hw_sspp_setup_sourceaddress's non-SOLO path) -- not two planes
    // of the same rect. Both rects read the same buffer/stride here.
    mmioWrite32(sspp_base, SSPP_SRC_YSTRIDE0, (stride & 0xffff) | ((stride & 0xffff) << 16));
    mmioWrite32(sspp_base, SSPP_SRC_FORMAT, SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE, SSPP_OP_MODE_PE_OVERRIDE);
    mmioWrite32(sspp_base, SSPP_MULTIRECT_OPMODE, SSPP_MULTIRECT_INDEX_REC0 | SSPP_MULTIRECT_MODE_TIME_MX);

    mmioWrite32(sspp_base, SSPP_SRC_SIZE_REC1, (vactive << 16) | hactive);
    mmioWrite32(sspp_base, SSPP_SRC_XY_REC1, half_w); // x offset = half_w, y=0
    mmioWrite32(sspp_base, SSPP_OUT_SIZE_REC1, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_OUT_XY_REC1, 0);
    // rect1 fetches through SRC1_ADDR, not SRC0_ADDR -- same buffer base,
    // SRC_XY_REC1's x=half_w crops into the right half via YSTRIDE0's
    // high16 pitch.
    mmioWrite32(sspp_base, SSPP_SRC1_ADDR, @truncate(fb_addr));
    mmioWrite32(sspp_base, SSPP_SRC_FORMAT_REC1, SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN_REC1, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE_REC1, SSPP_OP_MODE_PE_OVERRIDE);
    mmioSetBits32(sspp_base, SSPP_MULTIRECT_OPMODE, SSPP_MULTIRECT_INDEX_REC1 | SSPP_MULTIRECT_MODE_TIME_MX);

    _ = half_stride;

    if (DPU_TEST_STOP_STAGE <= 1) return 0;

    // -- LM: single opaque blendstage each, output = per-half size.
    mmioWrite32(lm0_base, LM_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(lm0_base, LM_OP_MODE, 0); // right_mixer=0: each LM is a solo half, not a source-split pair
    mmioWrite32(lm0_base, LM_STAGE0_OFFSET + LM_BLEND0_CONST_ALPHA, LM_CONST_ALPHA_OPAQUE);
    mmioWrite32(lm0_base, LM_STAGE0_OFFSET + LM_BLEND0_OP, LM_BLEND_OP_OPAQUE);

    mmioWrite32(lm1_base, LM_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(lm1_base, LM_OP_MODE, 0);
    mmioWrite32(lm1_base, LM_STAGE0_OFFSET + LM_BLEND0_CONST_ALPHA, LM_CONST_ALPHA_OPAQUE);
    mmioWrite32(lm1_base, LM_STAGE0_OFFSET + LM_BLEND0_OP, LM_BLEND_OP_OPAQUE);

    // -- CTL_LAYER: route SSPP_DMA0 rect0 into LM_0 stage 0, rect1 into
    // LM_1 stage 0 (ctl_blend_config[SSPP_DMA0][rect] from dpu_hw_ctl.c:
    // rect0 -> idx0/shift18 in CTL_LAYER(lm); rect1 -> idx2/shift8 in
    // CTL_LAYER_EXT2(lm)). Stage index i=0 -> mix=(i+1)&0x7=1.
    mmioWrite32(ctl_base, CTL_LAYER0, CTL_MIXER_BORDER_OUT | (@as(u32, 1) << 18));
    mmioWrite32(ctl_base, CTL_LAYER1, CTL_MIXER_BORDER_OUT);
    mmioWrite32(ctl_base, CTL_LAYER_EXT2_1, @as(u32, 1) << 8);

    if (DPU_TEST_STOP_STAGE <= 2) return 0;

    // -- PP: enable DSC routing + wrapper endian-flip quirk bit.
    mmioSetBits32(pp0_base, PP_DCE_DATA_OUT_SWAP, 1 << 18);
    mmioWrite32(pp0_base, PP_DSC_MODE, 1);
    mmioSetBits32(pp1_base, PP_DCE_DATA_OUT_SWAP, 1 << 18);
    mmioWrite32(pp1_base, PP_DSC_MODE, 1);

    // -- DSC: two hard-slice encoder instances sharing the DCE base,
    // dce_0_0 sblk (enc+0x100/ctl+0xf00) for DSC_0, dce_0_1 sblk
    // (enc+0x200/ctl+0xf80) for DSC_1.
    dscConfigureInstance(dce_base, 0x100, 0xf00, 0); // -> PP_0
    dscConfigureInstance(dce_base, 0x200, 0xf80, 1); // -> PP_1

    if (DPU_TEST_STOP_STAGE <= 3) return 0;

    // -- INTF: per-half timing, horizontal porches/sync halved (dual-
    // link split), vertical unchanged, width further reduced by the
    // DSC compression ratio (bpp=8 / (bpc=8 * 3 components) = 1/3) per
    // drm_mode_to_intf_timing_params()'s non-DP DSC branch.
    const half_hfront = hfront_porch / 2;
    const half_hback = hback_porch / 2;
    const half_hsync = hsync_width / 2;
    const compressed_w = half_w / 3; // bpp_int(8) / (bpc(8)*3) == 1/3 exactly for 8bpp/8bpc

    setupIntfTiming(intf1_base, compressed_w, vactive, half_hfront, half_hback, half_hsync, vfront_porch, vback_porch, vsync_width);
    setupIntfTiming(intf2_base, compressed_w, vactive, half_hfront, half_hback, half_hsync, vfront_porch, vback_porch, vsync_width);

    mmioWrite32(intf1_base, INTF_MUX, 0); // bind to PINGPONG_0
    mmioWrite32(intf2_base, INTF_MUX, 1); // bind to PINGPONG_1

    if (DPU_TEST_STOP_STAGE <= 4) return 0;

    // -- CTL top-level routing: both INTFs + both DSC engines active,
    // INTF_1 (DSI0) is the split-link master, video mode (no cmd-mode
    // bit), default (disabled) VM group id per core_major_ver>=7.
    mmioWrite32(ctl_base, CTL_TOP, CTL_DEFAULT_GROUP_ID_SHIFTED);
    mmioWrite32(ctl_base, CTL_INTF_ACTIVE, (@as(u32, 1) << 1) | (@as(u32, 1) << 2)); // INTF_1, INTF_2
    mmioWrite32(ctl_base, CTL_DSC_ACTIVE, 0x3); // DSC_0, DSC_1
    mmioWrite32(ctl_base, CTL_INTF_MASTER, @as(u32, 1) << 1); // INTF_1 is master

    if (DPU_TEST_STOP_STAGE <= 5) return 0;

    // -- Switch both DSI hosts from command mode (panel init DCS blast)
    // to video mode before the timing engines start pushing continuous
    // pixel data -- must happen first, or the DPU's video engine and
    // the DSI controller are in mismatched modes.
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);

    if (DPU_TEST_STOP_STAGE <= 6) return 0;

    // -- Enable both timing engines before the first flush/start, as
    // dpu_encoder_phys_vid_enable() does.
    mmioWrite32(intf1_base, INTF_TIMING_ENGINE_EN, 1);
    mmioWrite32(intf2_base, INTF_TIMING_ENGINE_EN, 1);

    if (DPU_TEST_STOP_STAGE <= 7) return 0;

    // -- CTL flush (v1 path, core_major_ver>=5): per-block flush masks
    // written to their own registers first, then the aggregate pending
    // mask to CTL_FLUSH, then CTL_START kicks the whole pipeline live.
    mmioWrite32(ctl_base, CTL_INTF_FLUSH, (@as(u32, 1) << 1) | (@as(u32, 1) << 2)); // INTF_1, INTF_2
    mmioWrite32(ctl_base, CTL_DSC_FLUSH, 0x3); // DSC_0, DSC_1

    if (DPU_TEST_STOP_STAGE <= 8) return 0;

    const pending_flush = CTL_FLUSH_SSPP_DMA0 | CTL_FLUSH_LM0 | CTL_FLUSH_LM1 |
        CTL_FLUSH_MASK_CTL | CTL_FLUSH_DSC_IDX | CTL_FLUSH_INTF_IDX;
    mmioWrite32(ctl_base, CTL_FLUSH, pending_flush);

    if (DPU_TEST_STOP_STAGE <= 9) return 0;

    mmioWrite32(ctl_base, CTL_START, 1);

    return 0;
}

fn setupIntfTiming(
    intf_base: usize,
    width: u32,
    height: u32,
    hfront_porch: u32,
    hback_porch: u32,
    hsync_width: u32,
    vfront_porch: u32,
    vback_porch: u32,
    vsync_width: u32,
) void {
    const hsync_period = hsync_width + hback_porch + width + hfront_porch;
    const vsync_period = vsync_width + vback_porch + height + vfront_porch;

    const display_v_start = (vsync_width + vback_porch) * hsync_period;
    const display_v_end = (vsync_period - vfront_porch) * hsync_period -% 1;

    const hsync_start_x = hback_porch + hsync_width;
    const hsync_end_x = hsync_period -% hfront_porch -% 1;

    const hsync_ctl = (hsync_period << 16) | hsync_width;
    const display_hctl = (hsync_end_x << 16) | hsync_start_x;

    // width==xres (no border-fill split), so active_h/v stay at the
    // hardware reset value (0) and ACTIVE_H/V_EN bits stay clear --
    // matches dpu_hw_intf_setup_timing_engine's "active_h_end==0" path.
    const polarity_ctl: u32 = 0; // DSI: hsync/vsync/den polarity forced low

    const data_width = width; // compression_en, !wide_bus_en -> data_width == width (dce_bytes_per_line path skipped, 1:1 for our fixed mode)
    const hsync_data_start_x = hsync_start_x;
    const hsync_data_end_x = hsync_start_x +% data_width -% 1;
    const display_data_hctl = (hsync_data_end_x << 16) | hsync_data_start_x;

    mmioWrite32(intf_base, INTF_HSYNC_CTL, hsync_ctl);
    mmioWrite32(intf_base, INTF_VSYNC_PERIOD_F0, vsync_period * hsync_period);
    mmioWrite32(intf_base, INTF_VSYNC_PULSE_WIDTH_F0, vsync_width * hsync_period);
    mmioWrite32(intf_base, INTF_DISPLAY_HCTL, display_hctl);
    mmioWrite32(intf_base, INTF_DISPLAY_V_START_F0, display_v_start);
    mmioWrite32(intf_base, INTF_DISPLAY_V_END_F0, display_v_end);
    mmioWrite32(intf_base, INTF_ACTIVE_HCTL, 0);
    mmioWrite32(intf_base, INTF_ACTIVE_V_START_F0, 0);
    mmioWrite32(intf_base, INTF_ACTIVE_V_END_F0, 0);
    mmioWrite32(intf_base, INTF_BORDER_COLOR, 0);
    mmioWrite32(intf_base, INTF_UNDERFLOW_COLOR, 0xff);
    mmioWrite32(intf_base, INTF_HSYNC_SKEW, 0);
    mmioWrite32(intf_base, INTF_POLARITY_CTL, polarity_ctl);
    mmioWrite32(intf_base, INTF_FRAME_LINE_COUNT_EN, 0x3);
    mmioWrite32(intf_base, INTF_CONFIG, 0); // no ACTIVE_H/V_EN, no prog-fetch
    mmioWrite32(intf_base, INTF_PANEL_FORMAT, INTF_PANEL_FORMAT_RGB888);

    // compression_en && !wide_bus_en -> DATA_HCTL_EN would normally be
    // skipped in 1ppc+compression per the kernel comment, but our
    // wide_bus_en is false and compression_en is true, so per the exact
    // condition `!(compression_en && !wide_bus_en)` DATA_HCTL_EN stays
    // OFF here (both terms true -> negation false).
    const intf_cfg2 = INTF_CFG2_DCE_DATA_COMPRESS;
    mmioWrite32(intf_base, INTF_CONFIG2, intf_cfg2);
    mmioWrite32(intf_base, INTF_DISPLAY_DATA_HCTL, display_data_hctl);
    mmioWrite32(intf_base, INTF_ACTIVE_DATA_HCTL, 0);
}
