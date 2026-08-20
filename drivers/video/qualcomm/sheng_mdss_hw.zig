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
    // PPS8-9 CORRECTED (SPEC.md task #5 log): was 0x05, 0xf4 = pic_width
    // 1524. drm_dsc_pps_payload_pack() puts pic_height at PPS6-7 and
    // pic_width at PPS8-9, so this told the panel's DSC decoder the
    // picture is 1524 wide == 2 slices of 762, while the DPU encoder --
    // now cross-verified against live silicon -- encodes a 3048-wide
    // picture as 4 slices of 762 (num_active_slice_per_enc = 2 in
    // CMN_MAIN_CNF, two encoders). The panel is ONE 3048-wide display
    // driven across both links, so its decoder must be told 3048.
    //
    // This is the panel-side half of the "two independently transcribed
    // DSC parameter sets, never cross-verified against each other" gap
    // this file has flagged for a long time; sheng_mdss_verify_pipeline()
    // cannot catch it because the PPS is a transmitted blob, not a
    // register. Every other PPS field already agrees with the corrected
    // encoder config: bpc 8, line_buf_depth 9, block_pred 1,
    // convert_rgb 1, bpp 8.0, pic_height 2032, slice_height 16,
    // slice_width 762, chunk_size 762.
    0x11, 0x00, 0x00, 0x89, 0x30, 0x80, 0x07, 0xf0, 0x0b, 0xe8, 0x00, 0x10, 0x02, 0xfa, 0x02, 0xfa,
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
extern fn flush_dcache_range(start: usize, stop: usize) callconv(.c) void;

var g_earliest_ctrl_selfcheck: u32 = 0xFFFFFFFF; // sentinel: "never ran"
var g_status0_before_first_cmd: u32 = 0xFFFFFFFF; // sentinel: "never ran"
var g_fifo_status_on_timeout: u32 = 0xFFFFFFFF; // sentinel: "never ran"
var g_dln0_phy_err_on_timeout: u32 = 0xFFFFFFFF; // sentinel: "never ran"

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

/// Mirror of gdsc_disable()'s GDSC_OFF path in gdsc.c: hand control
/// back from hardware-trigger mode, assert SW_COLLAPSE, and wait for
/// the logic to actually power down (~poll timeout, best-effort --
/// unlike gdsc_poll_status(GDSC_ON) we don't have a documented "OFF"
/// status bit offset handy, so this uses a fixed settle delay instead
/// of polling). Used for a genuine cold-start power cycle before this
/// driver's own setup runs, so the GDSC's logic gates initialize from
/// true power-on defaults rather than whatever latent state ABL/XBL's
/// own splash bring-up may have left behind -- never attempted before
/// this pass (see SPEC.md task #5 log).
export fn sheng_mdss_gdsc_disable(dispcc_base: usize) callconv(.c) void {
    mmioClearBits32(dispcc_base, MDSS_GDSC_OFFSET, HW_CONTROL_MASK);
    udelay(1);
    mmioSetBits32(dispcc_base, MDSS_GDSC_OFFSET, SW_COLLAPSE_MASK);
    udelay(200); // settle: let the power rail genuinely collapse
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
// Back to the REAL rate (SPEC.md task #5 log): the SVS-tier experiment
// (192.75MHz, avoiding any MMCX vote requirement) never got tested
// together with the DSI pclk0/byte0/esc0 clock fix or the VID_CFG0/
// lane/timing register fix -- both landed while this was still at the
// lowered rate. Live clk_summary from a WORKING Linux boot (ground-
// truth confirmed: login prompt visible with sheng_mdss_probe()
// disabled entirely) shows disp_cc_mdss_mdp_clk_src genuinely running
// at 514000000, not 192750000. A DPU core clocked at roughly 1/3 its
// required rate could easily explain "INTF free-runs and counts frames
// fine (driven by pclk0/vsync_clk, an independent clock domain from
// MDP_CLK) but the pixel data itself is never processed correctly" --
// matching our exact symptom. PLL0 (1542MHz) / 3 = 514MHz, N=3 ->
// div_reg_val = 2*3-1 = 5.
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

// REAL MISSING PIECE (SPEC.md task #5 log): live clk_summary from a
// WORKING Linux boot (msm_dpu bound, fb0 registered) showed these 8
// clocks -- byte0/1_clk, byte0/1_intf_clk, pclk0/1_clk, esc0/1_clk --
// all genuinely enabled and feeding ae94000.dsi/ae96000.dsi. This
// driver never touched any of them. pclk0/1 (~198MHz from the live
// trace) is almost certainly what actually drives INTF_FRAME_COUNT/
// LINE_COUNT, not MDP_CLK -- explaining why every MDP_CLK/MMCX/BCM
// experiment left frame counters frozen at exactly 0 regardless of
// clock rate or voltage: the wrong clock domain was under
// investigation the whole time. Source select values from
// disp_cc_parent_map_2 (dispcc-sm8550.c): DSI0_PHY_PLL_OUT_DSICLK=1,
// DSI0_PHY_PLL_OUT_BYTECLK=2, DSI1_PHY_PLL_OUT_DSICLK=3,
// DSI1_PHY_PLL_OUT_BYTECLK=4. Must run AFTER both DSI PHY PLLs are
// locked (sheng_mdss_dsi_phy_init), unlike the PLL0-sourced clocks
// above which don't depend on DSI PHY at all.
const PCLK0_CLK_SRC_CMD_RCGR: usize = 0x80a8;
const PCLK0_CLK_CBCR: usize = 0x8004;
const PCLK0_SRC_SEL_DSI0_DSICLK: u32 = 1;
const PCLK1_CLK_SRC_CMD_RCGR: usize = 0x80c0;
const PCLK1_CLK_CBCR: usize = 0x8008;
const PCLK1_SRC_SEL_DSI1_DSICLK: u32 = 3;
const BYTE0_CLK_SRC_CMD_RCGR: usize = 0x8108;
const BYTE0_CLK_CBCR: usize = 0x8028;
const BYTE0_INTF_CLK_CBCR: usize = 0x802c;
const BYTE0_SRC_SEL_DSI0_BYTECLK: u32 = 2;
const BYTE1_CLK_SRC_CMD_RCGR: usize = 0x8124;
const BYTE1_CLK_CBCR: usize = 0x8030;
const BYTE1_INTF_CLK_CBCR: usize = 0x8034;
const BYTE1_SRC_SEL_DSI1_BYTECLK: u32 = 4;
const ESC0_CLK_SRC_CMD_RCGR: usize = 0x8140;
const ESC0_CLK_CBCR: usize = 0x8038;
const ESC1_CLK_SRC_CMD_RCGR: usize = 0x8158;
const ESC1_CLK_CBCR: usize = 0x803c;
const ESC_SRC_SEL_XO: u32 = 0;
// byte0/1 and esc0/1 have mnd_width=0 in the real driver (plain HID
// divider, matching rcg2ConfigureHidOnly() exactly) -- div=1 passthrough.
// pclk0/1 have mnd_width=8 (fractional M/N/D capable, clk_pixel_ops) but
// this only configures the CFG register's SRC_SEL+HID_DIV fields, same
// as every other clock here; M/N/D registers are left at their hardware
// reset default (MND divider bypassed), same integer-passthrough
// behavior as byte0/1. Good enough to test whether real clocks start
// flowing at all; not necessarily the exact panel-spec pixel rate.
const DSI_CLK_DIV_REG_VAL_PASSTHROUGH: u32 = 1; // 2*1-1

export fn sheng_mdss_dispcc_dsi_clks_init(dispcc_base: usize) callconv(.c) c_int {
    var ret = rcg2ConfigureHidOnly(dispcc_base, PCLK0_CLK_SRC_CMD_RCGR, PCLK0_SRC_SEL_DSI0_DSICLK, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, PCLK0_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, BYTE0_CLK_SRC_CMD_RCGR, BYTE0_SRC_SEL_DSI0_BYTECLK, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, BYTE0_CLK_CBCR);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, BYTE0_INTF_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, ESC0_CLK_SRC_CMD_RCGR, ESC_SRC_SEL_XO, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, ESC0_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, PCLK1_CLK_SRC_CMD_RCGR, PCLK1_SRC_SEL_DSI1_DSICLK, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, PCLK1_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, BYTE1_CLK_SRC_CMD_RCGR, BYTE1_SRC_SEL_DSI1_BYTECLK, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, BYTE1_CLK_CBCR);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, BYTE1_INTF_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, ESC1_CLK_SRC_CMD_RCGR, ESC_SRC_SEL_XO, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, ESC1_CLK_CBCR);
}

/// Bring up disp_cc_pll0, then the AHB (bus, 19.2MHz off XO) and MDP
/// (DPU core, 514MHz off PLL0) clocks, plus the MDP LUT and VSYNC
/// clocks the DPU sub-block's own devicetree node additionally
/// requires (see the comment above). pclk0/byte0/esc0 are NOT done
/// here -- they mux from the DSI PHY's own PLL output rather than
/// DISPCC's internal PLL0, so they belong with DSI PHY bring-up
/// (sheng_mdss_dsi_phy_init) instead.
// Backlight-kill bisection (see board.c/sheng_mdss.c SPEC.md task #5
// log): full sheng_mdss_dispcc_init() kills backlight even for Linux's
// later re-init; core_reset+GDSC alone don't. Narrowing inside DISPCC
// itself -- PLL0 lock vs. the AHB/MDP/LUT/VSYNC clock branch enables
// that follow it.
export fn sheng_mdss_dispcc_init_pll0_only(dispcc_base: usize) callconv(.c) c_int {
    return dispCcPll0Enable(dispcc_base);
}

export fn sheng_mdss_dispcc_init_thru_ahb(dispcc_base: usize) callconv(.c) c_int {
    var ret = dispCcPll0Enable(dispcc_base);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
}

export fn sheng_mdss_dispcc_init_thru_mdp_rcg_only(dispcc_base: usize) callconv(.c) c_int {
    var ret = dispCcPll0Enable(dispcc_base);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
    if (ret != 0) return ret;

    // MDP clock source configured (src_sel + divider written) but the
    // CBCR branch itself never enabled -- narrows whether the RCG
    // config write or the actual clock-branch-on transition is what
    // disrupts something.
    return rcg2ConfigureHidOnly(dispcc_base, MDP_CLK_SRC_CMD_RCGR, MDP_CLK_SRC_SEL_PLL0, MDP_CLK_DIV_REG_VAL);
}

export fn sheng_mdss_dispcc_init_thru_mdp(dispcc_base: usize) callconv(.c) c_int {
    var ret = dispCcPll0Enable(dispcc_base);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, MDP_CLK_SRC_CMD_RCGR, MDP_CLK_SRC_SEL_PLL0, MDP_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, MDP_CLK_CBCR);
}

// Bisection landed here: MDP_CLK_CBCR's branch-enable transition
// (clkBranchEnable) specifically kills backlight (RCG src config alone
// is harmless; AHB is harmless). The DSI-bypass pixel path
// (sheng_mdss_dsi_test_patch) never touches the DPU pixel pipeline at
// all -- it's pure DSI command-mode DMA sourced from DSI's own byte/
// pixel clocks (DSI PHY PLL) plus AHB, not the MDP core clock. So skip
// just this one branch enable and keep going through DSI PHY/panel
// init, to get backlight AND the red square in the same build.
export fn sheng_mdss_dispcc_init_no_mdp_branch(dispcc_base: usize) callconv(.c) c_int {
    var ret = dispCcPll0Enable(dispcc_base);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    ret = clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
    if (ret != 0) return ret;

    // MDP_CLK_CBCR branch enable intentionally skipped.
    ret = rcg2ConfigureHidOnly(dispcc_base, MDP_CLK_SRC_CMD_RCGR, MDP_CLK_SRC_SEL_PLL0, MDP_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, VSYNC_CLK_SRC_CMD_RCGR, VSYNC_CLK_SRC_SEL_XO, VSYNC_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, VSYNC_CLK_CBCR);
}

// REAL GAP FOUND (SPEC.md task #5 log): sm8550.dtsi's mdss node
// (display-subsystem@ae00000, the TOP-LEVEL MDSS wrapper block --
// parent of both the DPU at ae01000 and the DSI hosts at ae94000/
// ae96000, never touched anywhere in this driver before) declares
// `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>;`. msm_mdss_reset(),
// called as the literal first thing in msm_mdss_init() -- before the
// mdss mmio is even ioremapped, before any clock is enabled, before
// DPU or DSI is touched at all -- asserts this reset, holds it 20ms
// ("tests indicate reset has to be held for some period of time...
// one frame in a typical system", its own comment), then deasserts.
// DISP_CC_MDSS_CORE_BCR resolves (drivers/clk/qcom/dispcc-sm8550.c's
// disp_cc_sm8550_resets table) to a single bit0 read-modify-write at
// dispcc_base+0x8000 (Qualcomm's standard BCR/BLK_ARES convention,
// confirmed via drivers/clk/qcom/reset.c's generic reset op). This
// driver has never asserted/deasserted this line -- DSI_RESET
// (offset 0x114) only resets each DSI host's OWN local state, not
// the shared MDSS-wide block this reset line covers. Component
// binding order in the real driver guarantees this runs before the
// very first DSI command in every real boot; replicate that here,
// first thing, before any DISPCC clock is even configured.
const DISP_CC_MDSS_CORE_BCR: usize = 0x8000;

fn mdssCoreBcrReset(dispcc_base: usize) void {
    var reg = mmioRead32(dispcc_base, DISP_CC_MDSS_CORE_BCR);
    reg |= 1;
    mmioWrite32(dispcc_base, DISP_CC_MDSS_CORE_BCR, reg);
    udelay(20000);
    reg = mmioRead32(dispcc_base, DISP_CC_MDSS_CORE_BCR);
    reg &= ~@as(u32, 1);
    mmioWrite32(dispcc_base, DISP_CC_MDSS_CORE_BCR, reg);
}

export fn sheng_mdss_dispcc_init(dispcc_base: usize) callconv(.c) c_int {
    mdssCoreBcrReset(dispcc_base);

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
/// bit_clk_div(1) | pix_clk_div(6) << 4 -- see the write site in
/// dsiPhyInit() for the derivation and the live-hardware confirmation.
const CMN_CLK_CFG0_VALUE: u32 = 0x61;
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
/// REAL GAP FOUND (SPEC.md task #5 log): dsi_mgr_phy_enable() in the
/// real driver (dsi_manager.c) calls msm_dsi_host_reset_phy() on BOTH
/// hosts before either PHY is enabled, for bonded/dual-DSI setups
/// specifically -- its own comment: "some registers in PHY1 have been
/// programmed during PLL0 clock's set_rate. The PHY1 reset called by
/// host1 here will silently reset those PHY1 registers. Therefore we
/// need to reset and enable both PHYs before any PLL clock
/// operation." msm_dsi_host_reset_phy() itself is trivial: pulse
/// DSI_PHY_RESET (offset 0x128, in the DSI HOST's own register block,
/// not the PHY's -- confirmed via dsi.xml, distinct from DSI_RESET at
/// 0x114 which resets the host's own logic) high for ~1ms then low.
/// This driver never wrote this register at all, on either host, ever
/// -- a genuine, sourced, dual-DSI-specific gap. Must run before
/// sheng_mdss_dsi_phy_init() is called for either PHY.
export fn sheng_mdss_dsi_reset_both_phys(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    mmioWrite32(dsi0_base, DSI_PHY_RESET, 1);
    mmioWrite32(dsi1_base, DSI_PHY_RESET, 1);
    udelay(1000);
    mmioWrite32(dsi0_base, DSI_PHY_RESET, 0);
    mmioWrite32(dsi1_base, DSI_PHY_RESET, 0);
}

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

    // REAL GAP FOUND (SPEC.md task #5 log): CMN_CLK_CFG0 holds the
    // PHY's two output dividers -- dsi_pll_7nm_restore_state() writes
    // it as `bit_clk_div | (pix_clk_div << 4)` -- and this driver
    // declared the register but never wrote it, leaving both dividers
    // at their hardware reset default. Byte clock was therefore right
    // (it comes straight off the PLL, whose VCO rate was measured live
    // and matches) while the PIXEL clock ran at the wrong divisor, so
    // the DPU fed the DSI link several times faster than it could
    // transmit.
    //
    // Measured consequence, with everything else already verified
    // correct: DSI0 FIFO_STATUS = 0xdddd1211 while streaming --
    // VIDEO_MDP_FIFO_OVERFLOW (bit0) set, and all four data lanes
    // (DLN0-3) simultaneously OVERFLOW *and* UNDERFLOW, i.e. the lane
    // FIFOs thrashing between full and empty. Classic rate mismatch,
    // not a configuration error: STATUS0 confirmed both hosts had
    // VIDEO_MODE_ENGINE_BUSY asserted and the whole DPU datapath read
    // back correct.
    //
    // 0x61 is Linux's own live value on BOTH PHYs (read via devmem on
    // this exact panel while DRM was driving it), and the arithmetic
    // independently agrees: pix_clk_div = 6 gives bitclk/6 =
    // 1,190,718,144/6 = 198,453,024 Hz, exactly dsi_get_pclk_rate()'s
    // result for this DSC-compressed bonded-DSI mode, and exactly the
    // standard bpp/lanes = 24/4 = 6 ratio.
    mmioWrite32(dsi_phy_base, CMN_CLK_CFG0, CMN_CLK_CFG0_VALUE);

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
const DSI_FIFO_STATUS: usize = 0x008;
const DSI_DLN0_PHY_ERR: usize = 0x0b0;
const DSI_VID_CFG0: usize = 0x00c;
const DSI_ACTIVE_H: usize = 0x020;
const DSI_ACTIVE_V: usize = 0x024;
const DSI_TOTAL: usize = 0x028;
const DSI_ACTIVE_HSYNC: usize = 0x02c;
const DSI_ACTIVE_VSYNC_HPOS: usize = 0x030;
const DSI_ACTIVE_VSYNC_VPOS: usize = 0x034;
const DSI_VID_CFG1: usize = 0x010;
/// REAL GAP FOUND (SPEC.md task #5 log): the DSI host's own compression
/// descriptor, offset 0x29c. This driver never referenced it AT ALL --
/// grep for "COMPRESSION" found zero hits -- so the host was never told
/// it was carrying a DSC-compressed stream, and expected uncompressed
/// RGB at the programmed timing.
///
/// That stayed invisible for as long as no pixels were actually being
/// fetched: with CTL_FETCH_PIPE_ACTIVE unset, FIFO_STATUS read a clean
/// 0x00001210 because nothing was flowing. The moment the fetch gate
/// was opened, DSI0 FIFO_STATUS went to 0xdddd1219 -- VIDEO_MDP_FIFO
/// OVERFLOW *and* UNDERFLOW plus all four lanes thrashing -- i.e. real
/// compressed data arriving at a host configured to expect something
/// else entirely.
///
/// Live value, identical on DSI0 and DSI1 (dsi.xml bitfields):
///   WC(31:16)          = 0x05F4 = 1524 compressed bytes per line
///   DATATYPE(13:8)     = 0x0B   = MIPI compressed pixel stream
///   PKT_PER_LINE(7:6)  = 0
///   EOL_BYTE_NUM(5:4)  = 0
///   EN(0)              = 1
/// DSI host built-in TEST PATTERN GENERATOR (SPEC.md task #5 log).
/// msm_dsi_host_test_pattern_en() / msm_dsi_host_video_test_pattern_setup().
///
/// This is the decisive bisect for "is the panel receiving anything at
/// all". The DSI host generates the video stream INTERNALLY and drives
/// it down the lanes: no framebuffer, no SMMU, no SSPP, no layer mixer,
/// no DSC encoder, no INTF -- the entire DPU is bypassed. It works on
/// video-mode panels, unlike the earlier DCS ALL_PIXELS_ON attempt whose
/// behaviour is implementation-defined on a RAM-less panel.
///
///   ANY visible change (checkerboard, noise, garbage, flicker)
///     -> the DSI link physically reaches the panel and the panel
///        reacts. The fault is then in the DPU -> DSI data path, and
///        every register we verified identical to live silicon is
///        genuinely fine.
///   Still pure black
///     -> nothing this SoC transmits reaches the panel's display,
///        despite PHY/host registers matching working Linux exactly.
///        That points at the panel's own power/enable state rather
///        than anything in the display pipeline.
///
/// NOTE: the panel is currently in DSC mode, so TPG's uncompressed RGB
/// will not decode into a clean checkerboard -- garbage or noise is the
/// EXPECTED positive result here. Only pure black is the negative.
const DSI_TEST_PATTERN_GEN_CTRL: usize = 0x158;
const DSI_TEST_PATTERN_GEN_VIDEO_INIT_VAL: usize = 0x160;
const DSI_TPG_MAIN_CONTROL: usize = 0x198;
const DSI_TPG_VIDEO_CONFIG: usize = 0x1a0;
/// CHECKERED_RECTANGLE_PATTERN (bit8)
const TPG_MAIN_CONTROL_CHECKERED: u32 = 1 << 8;
/// BPP = VIDEO_CONFIG_24BPP (1) | RGB (bit2)
const TPG_VIDEO_CONFIG_VALUE: u32 = 1 | (1 << 2);
/// VIDEO_PATTERN_SEL = VID_MDSS_GENERAL_PATTERN (3) at bits[5:4], EN bit0
const TPG_GEN_CTRL_VALUE: u32 = (3 << 4) | 1;

fn dsiTpgEnableOne(dsi_base: usize) void {
    mmioWrite32(dsi_base, DSI_TEST_PATTERN_GEN_VIDEO_INIT_VAL, 0xff);
    mmioWrite32(dsi_base, DSI_TPG_MAIN_CONTROL, TPG_MAIN_CONTROL_CHECKERED);
    mmioWrite32(dsi_base, DSI_TPG_VIDEO_CONFIG, TPG_VIDEO_CONFIG_VALUE);
    mmioWrite32(dsi_base, DSI_TEST_PATTERN_GEN_CTRL, TPG_GEN_CTRL_VALUE);
}

/// Master first, then slave -- matching msm_dsi_manager_tpg_enable()'s
/// own explicit "if dual dsi, trigger tpg on master first then slave".
export fn sheng_mdss_dsi_tpg_enable(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    // TPG DISABLED (SPEC.md task #5 log): it answered its question --
    // pure black with the whole DPU bypassed -- and it perturbs
    // FIFO_STATUS (drove it to 0x55551210), which is now the primary
    // instrument. Kept compiled for future use.
    if (true) return;
    dsiTpgEnableOne(dsi0_base);
    dsiTpgEnableOne(dsi1_base);
}

/// BISECT (SPEC.md task #5 log): stage NO pipe into either mixer, so
/// the mixers emit border colour and the DPU produces a frame with ZERO
/// memory fetch -- while DSC, INTF and DSI stay exactly as configured.
///
/// Live working Linux reads FIFO_STATUS = 0x00001210 (lanes FED). Our
/// current build reads 0x11111210, differing only in the four
/// DLN*_HS_FIFO_EMPTY bits: our lanes are STARVED. Everything between
/// framebuffer and lane verifies bit-identical to live, so the open
/// question is whether SSPP is actually fetching at all.
///
///   border-only FIFO_STATUS == 0x00001210 (lanes fed)
///     -> the DPU->DSC->INTF->DSI path is healthy and the starvation
///        comes from the SSPP fetch (memory/SMMU), not the pipeline.
///   border-only still 0x1111xxxx (lanes starved)
///     -> the starvation is downstream of the mixer and has nothing to
///        do with the framebuffer or SMMU at all.
///
/// Needs no visible colour to be conclusive: FIFO_STATUS carries the
/// answer either way.
const DPU_BORDER_ONLY_BISECT: bool = false;

const DSI_VIDEO_COMPRESSION_MODE_CTRL: usize = 0x29c;
const VIDEO_COMPRESSION_MODE_CTRL_VALUE: u32 = 0x05F40B01;
const DSI_DMA_BASE: usize = 0x044;
const DSI_DMA_LEN: usize = 0x048;
const DSI_CMD_DMA_CTRL: usize = 0x038;
const DSI_LP_TIMER_CTRL: usize = 0x0b4;
const DSI_HS_TIMER_CTRL: usize = 0x0b8;
const DSI_CMD_CFG0: usize = 0x03c;
const DSI_CMD_CFG1: usize = 0x040;
const DSI_CMD_MODE_MDP_CTRL2: usize = 0x1b4;
const DSI_ACK_ERR_STATUS: usize = 0x064;
const DSI_TIMEOUT_STATUS: usize = 0x0bc;
const DSI_TRIG_CTRL: usize = 0x080;
const DSI_TRIG_DMA: usize = 0x08c;
const DSI_LANE_CTRL: usize = 0x0a8;
const DSI_LANE_SWAP_CTRL: usize = 0x0ac;
const DSI_CLKOUT_TIMING_CTRL: usize = 0x0c0;
const DSI_EOT_PACKET_CTRL: usize = 0x0c8;
const DSI_CLK_CTRL: usize = 0x118;
const DSI_RESET: usize = 0x114;
const DSI_PHY_RESET: usize = 0x128; // confirmed in dsi.xml, distinct from DSI_RESET -- resets the *connected PHY*, not the host's own logic
const DSI_RDBK_DATA0: usize = 0x068; // RDBK array, stride 4, entries 0-3
const DSI_RDBK_DATA_CTRL: usize = 0x1d0;
const RDBK_DATA_CTRL_CLR: u32 = 1 << 0;

// Confirmed via real dsi.xml (registers/display/dsi.xml) at offsets 0x108/
// 0x10c. dsi_ctrl_enable() writes ERR_INT_MASK0 + sets INTR_CTRL's
// MASK_ERROR bit once at bring-up; msm_dsi_host_xfer_prepare()/
// msm_dsi_host_cmd_xfer_commit() set/clear INTR_CTRL's MASK_CMD_DMA_DONE
// bit around every single command DMA, which our driver never touched at
// all before. Real IP designs sometimes gate internal completion-status
// latching behind the same enable used for the IRQ line, so this is worth
// testing even though STATUS0 is expected to be a live combinatorial
// status independent of masking.
const DSI_ERR_INT_MASK0: usize = 0x108;
const DSI_INTR_CTRL: usize = 0x10c;
const DSI_IRQ_MASK_CMD_DMA_DONE: u32 = 1 << 1;
const DSI_IRQ_MASK_ERROR: u32 = 1 << 25;
const DSI_ERR_INT_MASK0_VALUE: u32 = 0x13ff3fe0;

// STOLEN OUTPUT, NOT RECOMPUTED (SPEC.md task #5 log): rather than port
// dsi_host.c's dsi_ctrl_enable() field-by-field (several fields turned
// out to have undocumented bits our generated-header source doesn't
// cover -- e.g. LANE_SWAP_CTRL/EOT_PACKET_CTRL have real live bits far
// beyond their one documented field each) or port dsi_phy.c's D-PHY
// timing-calculation cascade (clk_pre/clk_post -- ~100 lines of
// interdependent linear_inter() math), these are the EXACT live
// register values read directly off this same hardware via devmem
// while Linux's own real, working driver had it configured -- for
// this exact panel, exact PLL lock, exact everything. Identical on
// both DSI0 (0xae94000) and DSI1 (0xae96000), as expected for the
// dual-link panel. Confirmed real DST_FORMAT is RGB666 (1), not
// RGB888 (3) as originally assumed -- DSC changes the wire packing
// format regardless of the source pixel depth.
// RE-STOLEN (SPEC.md task #5 log): every value below was originally
// captured via devmem at the UNSHIFTED address (base+offset), before
// the DSI_6G_REG_SHIFT discovery -- meaning every one of them was
// actually reading whatever register sits one slot before the intended
// one (SM8550_MDSS_DSI0/1_BASE now bakes in the +4 shift, matching the
// real driver's ctrl_base). Re-captured live at the CORRECT address
// (base+4+offset) after the shift fix. Every single value changed.
const VID_CFG0_VALUE: u32 = 0x02009230;
const VID_CFG1_VALUE: u32 = 0x31211101;
const LANE_CTRL_VALUE: u32 = 0x01000000;
const LANE_SWAP_CTRL_VALUE: u32 = 0x00000000;
const CLKOUT_TIMING_CTRL_VALUE: u32 = 0x00001A23;
const EOT_PACKET_CTRL_VALUE: u32 = 0x00000001;
// Live-confirmed, identical on DSI0/DSI1. dsi.xml's documented
// bitfields for this register (FROM_FRAME_BUFFER|LOW_POWER, bits
// 26/28) don't match this value at all -- same incomplete-header
// situation as LANE_SWAP_CTRL/EOT_PACKET_CTRL, using the live value
// directly rather than a computed one that's demonstrably wrong.
const CMD_DMA_CTRL_VALUE: u32 = 0x14000000; // re-stolen post-shift-fix, see VID_CFG0_VALUE's comment

// REAL GAP FOUND (SPEC.md task #5 log): LP_TIMER_CTRL's BTA_TO field
// (bits 16-31) is the DSI host's own bus-turnaround timeout -- if this
// is 0 (or any value too short for the panel's actual response time),
// the host's BTA receive window closes before the panel's physical
// response ever arrives, and the host reports the transaction as
// complete with 0 bytes captured -- exactly matching every symptom in
// this project's own live BTA test. Neither the real Linux driver nor
// this driver has ever written LP_TIMER_CTRL/HS_TIMER_CTRL -- Linux
// simply inherits whatever ABL/firmware left behind. Live-confirmed
// nonzero (0x00088888/0xFFFFFFFF, identical DSI0/DSI1) on a working
// boot -- but this driver's own DSI_RESET pulse (added earlier this
// session) could plausibly reset these specific timer registers back
// to an unusable hardware POR default (most likely 0) before we ever
// read them, and there's no way to observe U-Boot's own register
// state mid-boot to check. Writing these explicitly removes that
// uncertainty entirely rather than assuming the reset leaves them
// alone.
const LP_TIMER_CTRL_VALUE: u32 = 0xFFFFFFFF; // re-stolen post-shift-fix
const HS_TIMER_CTRL_VALUE: u32 = 0x0000FFFF; // re-stolen post-shift-fix

// MOST CONSEQUENTIAL GAP FOUND (SPEC.md task #5 log): dsi_ctrl_enable()
// in the real driver has an `if (VIDEO) {...} else { /* command mode
// */ ... }` split. Every fix made to this register set before now only
// ever ported the VIDEO-mode half (VID_CFG0/VID_CFG1). The COMMAND-
// MODE half -- CMD_CFG0, CMD_CFG1, CMD_MODE_MDP_CTRL2 -- is taken every
// time the host is in command mode, i.e. for 100% of this driver's DCS
// traffic (the entire init sequence, Exit Sleep, Display On, the test
// patch, every BTA read this whole project has ever attempted) and was
// NEVER PORTED AT ALL. CMD_CFG1's INSERT_DCS_COMMAND bit in particular
// is what tells the command-mode engine to actually frame the DCS
// command byte the way this driver's own buildMsmCmdPacket() assumes
// -- without it, the hardware's own command-mode packet framing may
// not match what we're constructing in software at all. Live-verified
// values, identical DSI0/DSI1.
const CMD_CFG0_VALUE: u32 = 0x06100006; // re-stolen post-shift-fix
const CMD_CFG1_VALUE: u32 = 0x00003C2C; // re-stolen post-shift-fix
const CMD_MODE_MDP_CTRL2_VALUE: u32 = 0x00000006; // re-stolen post-shift-fix

// REAL GAP FOUND (SPEC.md task #5 log): dsi_timing_setup() in the real
// driver -- called from msm_dsi_host_power_on() BEFORE dsi_sw_reset()/
// dsi_ctrl_enable(), i.e. before VID_CFG0 is ever written -- programs
// an entire DSI-HOST-side timing register block (ACTIVE_H/V, TOTAL,
// ACTIVE_HSYNC, ACTIVE_VSYNC_HPOS/VPOS) that this driver never touched
// at all. This is separate from the DPU-side INTF_ACTIVE_HCTL/etc we
// already write -- the DSI host's own packetizer needs its own active-
// window config independent of the DPU INTF timing generator that
// drives it. The real formula involves a DSC-adjusted pclk-cycle count
// (h_total -= hdisplay; hdisplay = DIV_ROUND_UP(bytes_per_line*8,
// bits_per_pclk); h_total += hdisplay -- dependent on wide_bus_enabled,
// which wasn't traced) -- rather than risk a subtly wrong recomputation
// (the exact class of bug that already bit VID_CFG0/LANE_CTRL earlier
// in this project), these are the exact live register values read
// directly off this same hardware via devmem while Linux's own working
// driver had it configured, identical on both DSI0 and DSI1.
const ACTIVE_H_VALUE: u32 = 0x022C0030; // re-stolen post-shift-fix
const ACTIVE_V_VALUE: u32 = 0x087C008C; // re-stolen post-shift-fix
const TOTAL_VALUE: u32 = 0x08950272; // re-stolen post-shift-fix
const ACTIVE_HSYNC_VALUE: u32 = 0x00020000; // re-stolen post-shift-fix
const ACTIVE_VSYNC_HPOS_VALUE: u32 = 0x00000000; // re-stolen post-shift-fix
const ACTIVE_VSYNC_VPOS_VALUE: u32 = 0x00020000; // re-stolen post-shift-fix
const TRIG_CTRL_VALUE: u32 = 0x80001004; // re-stolen post-shift-fix

/// TRIG_CTRL for the panel-INIT phase only (SPEC.md task #5 log).
///
/// TRIG_CTRL_VALUE above is a faithful copy of Linux's live register:
/// TE(31) | BLOCK_DMA_WITHIN_FRAME(12) | DMA_TRIGGER(SW). Faithful --
/// and, in U-Boot's context, self-defeating. dsi_host.c's own comment
/// at msm_dsi_host_xfer_prepare() spells out what bit12 does:
///
///   "Since DSI6G v1.2.0, we can set DSI_TRIG_CTRL.BLOCK_DMA_WITHIN_
///    FRAME to ask H/W to wait until cmd mdp is idle. S/W wait is not
///    needed."
///
/// It is a HARDWARE INTERLOCK gating the command DMA engine on the
/// MDP/DPU pixel path's frame state. Linux may set it because by the
/// time it sends panel commands the DPU is fully up and streaming, so
/// the inter-frame window it waits for opens continuously. In this
/// driver the DPU has never been started when panel init runs --
/// dpu_start() is called only AFTER sheng_mdss_dsi_panel_init()
/// returns. Nothing is generating frames, so the window never opens.
/// Likewise TE(31) ("always assume dedicated TE pin") points the block
/// at a tear-effect signal an uninitialised panel is not pulsing.
///
/// A DMA engine told to wait for a frame boundary nobody is producing
/// asserts CMD_MODE_DMA_BUSY and holds it forever -- which is exactly
/// and only the symptom seen on every boot of this driver. Every
/// register-content theory chased so far compared our values against
/// Linux's and found them identical; the bug was never a wrong value,
/// it was a right value copied into a context where its precondition
/// (a live MDP) does not hold.
///
/// Software-trigger-only: no TE dependency, no frame-window wait.
const TRIG_CTRL_CMD_INIT_VALUE: u32 = TRIG_CTRL_DMA_TRIGGER_SW;

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

    // REAL GAP FOUND (SPEC.md task #5 log): dsi_sw_reset() in the real
    // driver -- called from msm_dsi_host_power_on() as
    // dsi_timing_setup() -> dsi_sw_reset() -> dsi_ctrl_enable(), i.e.
    // right here, between enabling DSI_CLK_CTRL and writing DSI_CTRL
    // -- pulses DSI_RESET (offset 0x114, bit 0) high for
    // DSI_RESET_TOGGLE_DELAY_MS=20ms then low, explicitly because "dsi
    // controller can only be reset while clocks are running" (its own
    // comment). This driver had DSI_RESET's offset defined as a
    // constant since early in the project but never actually wrote to
    // it anywhere -- dead code, the pulse itself was never sent. Forces
    // the DSI host's internal state machine to a genuine POR state
    // before any config register is written, instead of configuring on
    // top of whatever state ABL's own splash bring-up (or this exact
    // same controller's prior use) left behind.
    mmioWrite32(dsi_base, DSI_RESET, 1);
    udelay(20000); // mdelay() is a U-Boot macro, not linkable -- see other udelay() call sites in this file
    mmioWrite32(dsi_base, DSI_RESET, 0);

    // STICKY STATUS CLEAR TEST (SPEC.md task #5 log): force-clear any
    // residual W1C status/error bits ABL or a prior stage may have left
    // set, before any command traffic. If the command DMA state machine
    // treats an uncleared completion/error flag as "still active,"
    // triggering a new transaction on top of it could explain a clean-
    // FIFO, clean-PHY-error, permanently-busy hang.
    mmioWrite32(dsi_base, DSI_ACK_ERR_STATUS, 0xFFFFFFFF);
    mmioWrite32(dsi_base, DSI_TIMEOUT_STATUS, 0xFFFFFFFF);

    // EARLIEST-POSSIBLE self-check (SPEC.md task #5 log): the original
    // self-check ran late, after the entire 87-command init sequence,
    // Sleep Out, Display On, and the test patch had already been
    // attempted -- if those all silently failed because CTRL's mode
    // bits never latched, the controller could have drifted into a
    // DIFFERENT stuck state by the time that self-check ran, which
    // wouldn't prove whether the very first write, immediately after
    // reset, also fails. Test that specifically, before anything else
    // touches the controller. DSI0 only (g_earliest_ctrl_selfcheck is
    // a single global slot).
    if (dsi_base == 0x0ae94000) {
        const probe_val: u32 = 0xC3C3C3C3;
        mmioWrite32(dsi_base, DSI_CTRL, probe_val);
        g_earliest_ctrl_selfcheck = mmioRead32(dsi_base, DSI_CTRL);
    }

    // PHASE SPLIT TEST (SPEC.md task #5 log): the real driver's
    // dsi_ctrl_enable() writes ONLY CLK_EN | <lane bits> | ENABLE here
    // -- CMD_MODE_EN/VID_MODE_EN are never part of this write. Mode
    // selection happens separately, later, via dsi_op_mode_config()'s
    // own read-modify-write (see the CTRL_CMD_MODE_EN write at the end
    // of this function). The two approaches are functionally
    // equivalent in final register content (same bits, different
    // write count) and don't explain the write-rejection anomaly found
    // on this exact register (a write-then-immediate-read self-check
    // showed 0 bits landing at all, including on a garbage test
    // pattern unrelated to any real driver value) -- but matching the
    // real driver's exact phase ordering costs nothing and rules out
    // any sequencing-dependent hardware behavior this register might
    // have that source-reading alone can't reveal.
    mmioWrite32(dsi_base, DSI_CTRL, CTRL_CLK_EN | CTRL_ALL_LANES | CTRL_ENABLE);

    // REAL GAP FOUND (SPEC.md task #5 log): dsi_ctrl_enable() in the
    // real driver writes LANE_SWAP_CTRL/LANE_CTRL unconditionally,
    // before ANY command-mode traffic -- this driver only wrote them
    // in dsiHostSwitchToVideoMode(), which runs AFTER the entire DCS
    // init sequence, Exit Sleep, Display On, and every BTA read this
    // whole project has ever attempted. The target values themselves
    // were already correct (stolen from live hardware, confirmed
    // identical again via a live re-check) -- this was a pure
    // ordering bug: every single command-mode transaction this driver
    // has ever sent went out before the lane config it needed was
    // ever applied. CMD_DMA_CTRL (offset 0x038) was never written at
    // all anywhere in this driver -- also unconditional in the real
    // dsi_ctrl_enable(), also live-confirmed (its dsi.xml bitfield
    // description is incomplete, matching this project's established
    // pattern for this register family -- using the live value
    // directly rather than the incomplete computed one).
    mmioWrite32(dsi_base, DSI_LANE_SWAP_CTRL, LANE_SWAP_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_LANE_CTRL, LANE_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_CMD_DMA_CTRL, CMD_DMA_CTRL_VALUE);

    // BISECTION TEST (SPEC.md task #5 log): a genuine DMA timeout on
    // the very first command appeared after the DSI 6G shift fix +
    // re-stolen values. Temporarily removing these 5 writes (all
    // added earlier this same session, all previously untested in
    // combination with the shift fix) to isolate whether one of them
    // is the new cause. Re-add once isolated.
    // mmioWrite32(dsi_base, DSI_LP_TIMER_CTRL, LP_TIMER_CTRL_VALUE);
    // mmioWrite32(dsi_base, DSI_HS_TIMER_CTRL, HS_TIMER_CTRL_VALUE);
    // mmioWrite32(dsi_base, DSI_CMD_CFG0, CMD_CFG0_VALUE);
    // mmioWrite32(dsi_base, DSI_CMD_CFG1, CMD_CFG1_VALUE);
    // mmioWrite32(dsi_base, DSI_CMD_MODE_MDP_CTRL2, CMD_MODE_MDP_CTRL2_VALUE);

    // Real live value (see VID_CFG0_VALUE's comment) -- our previous
    // TRIG_CTRL_TE|TRIG_CTRL_DMA_TRIGGER_SW guess (0x80000004) was very
    // different from what's actually programmed on working hardware
    // (0x001C1A02).
    // REVERTED to Linux's exact live value (SPEC.md task #5 log).
    //
    // This briefly ran as TRIG_CTRL_CMD_INIT_VALUE (software trigger
    // only) on the theory that BLOCK_DMA_WITHIN_FRAME's "wait until cmd
    // mdp is idle" interlock was deadlocking the command DMA. That
    // theory was DISPROVEN -- the real cause was GCC_DISP_HF_AXI_CLK
    // ordering -- so the deviation bought nothing and was left in place
    // only because it appeared harmless.
    //
    // It is not obviously harmless: panel init has since failed
    // intermittently at random command indices (#5, #11, #54 observed),
    // always recoverable by a full power cycle. An unnecessary
    // divergence from a known-good trigger configuration is exactly the
    // kind of thing that produces marginal, index-independent failures,
    // so it goes back to the value working silicon uses.
    mmioWrite32(dsi_base, DSI_TRIG_CTRL, TRIG_CTRL_VALUE);

    // Phase 2: mode selection, matching dsi_op_mode_config()'s own
    // read-modify-write -- CMD_MODE_EN added only now, after every
    // other config register above is already in place.
    var ctrl_mode = mmioRead32(dsi_base, DSI_CTRL);
    ctrl_mode |= CTRL_CMD_MODE_EN | CTRL_ENABLE;
    mmioWrite32(dsi_base, DSI_CTRL, ctrl_mode);

    // DIAGNOSTIC (SPEC.md task #5 log): capture STATUS0 right here,
    // before any command has ever been triggered, to check whether
    // CMD_MODE_DMA_BUSY (bit1) is already stuck set -- now that CTRL/
    // CLK_CTRL genuinely take effect for the first time (previously
    // landing on the wrong, inert register), this may be the first
    // time "busy" has ever reflected real hardware state. DSI0 only.
    if (dsi_base == 0x0ae94004) {
        g_status0_before_first_cmd = mmioRead32(dsi_base, DSI_STATUS0);
    }

    // REAL GAP FOUND (SPEC.md task #5 log): dsi_ctrl_enable() in the
    // real driver unconditionally writes ERR_INT_MASK0 (offset 0x108,
    // confirmed via registers/display/dsi.xml) and sets INTR_CTRL's
    // (0x10c) MASK_ERROR bit (bit25) before any command traffic --
    // this driver never wrote either register at all. Unlikely to be
    // the CMD_MODE_DMA_BUSY hang itself (STATUS0 is expected to be a
    // live combinatorial status independent of IRQ masking on this
    // class of IP), but it's a real, sourced, zero-risk gap worth
    // closing rather than leaving unexamined.
    mmioWrite32(dsi_base, DSI_ERR_INT_MASK0, DSI_ERR_INT_MASK0_VALUE);
    var intr_ctrl = mmioRead32(dsi_base, DSI_INTR_CTRL);
    intr_ctrl |= DSI_IRQ_MASK_ERROR;
    mmioWrite32(dsi_base, DSI_INTR_CTRL, intr_ctrl);
}

/// Switch the DSI host from command mode (used for the panel init DCS
/// blast) to video mode, matching dsi_op_mode_config(video_mode=true)
/// in dsi_host.c. Must happen before the DPU INTF timing engine starts
/// pushing continuous pixel data -- leaving CMD_MODE_EN set while the
/// DPU drives a live video timing engine into this controller is a
/// real hardware mode mismatch, not just "wrong colors".
fn dsiHostSwitchToVideoMode(dsi_base: usize) void {
    // Real gap closed (SPEC.md task #5 log): dsi_ctrl_enable() in the
    // real driver writes DSI_VID_CFG0 (traffic mode / RGB format /
    // virtual channel -- literally how to format the pixel stream on
    // the wire) unconditionally for video mode, and this driver never
    // did at all. Video was streaming internally (INTF_FRAME_COUNT
    // incrementing) but the controller never knew how to actually
    // transmit it -- explaining "frames counted, nothing visible"
    // regardless of DSC on/off, since this gap exists either way.
    // dsi_timing_setup() in the real driver runs before dsi_ctrl_enable()
    // -- see ACTIVE_H_VALUE's comment. Written first here to match.
    mmioWrite32(dsi_base, DSI_ACTIVE_H, ACTIVE_H_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_V, ACTIVE_V_VALUE);
    mmioWrite32(dsi_base, DSI_TOTAL, TOTAL_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_HSYNC, ACTIVE_HSYNC_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_VSYNC_HPOS, ACTIVE_VSYNC_HPOS_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_VSYNC_VPOS, ACTIVE_VSYNC_VPOS_VALUE);

    // Tell the host it is carrying a compressed stream BEFORE enabling
    // the video engine -- see DSI_VIDEO_COMPRESSION_MODE_CTRL's comment.
    mmioWrite32(dsi_base, DSI_VIDEO_COMPRESSION_MODE_CTRL, VIDEO_COMPRESSION_MODE_CTRL_VALUE);

    mmioWrite32(dsi_base, DSI_VID_CFG0, VID_CFG0_VALUE);
    mmioWrite32(dsi_base, DSI_VID_CFG1, VID_CFG1_VALUE);
    mmioWrite32(dsi_base, DSI_LANE_SWAP_CTRL, LANE_SWAP_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_EOT_PACKET_CTRL, EOT_PACKET_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_LANE_CTRL, LANE_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_CLKOUT_TIMING_CTRL, CLKOUT_TIMING_CTRL_VALUE);

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
///
/// REAL GAP FOUND (SPEC.md task #5 log): every caller writes the DCS
/// packet into dma_scratch via plain CPU stores (through a `volatile`
/// pointer, which only stops the compiler from eliding/reordering the
/// writes -- it does nothing for the CPU's actual data cache), then
/// this function immediately triggers the DSI DMA engine, which reads
/// directly from physical DRAM and is NOT cache-coherent with the CPU.
/// sheng_mdss.c's own framebuffer fill already calls
/// flush_dcache_range() before the SSPP's DMA fetch for exactly this
/// reason -- the identical requirement was simply never applied to the
/// DSI command DMA path. Without it, the DSI engine can transmit
/// whatever stale/garbage bytes happen to physically be in DRAM,
/// compute a valid CRC over that garbage, and send a well-formed-but-
/// meaningless packet -- explaining a panel that silently drops every
/// command (matches the zero-byte BTA result) while every register
/// configuration checks out correct, because the packet content itself
/// was never valid to begin with. __asm_flush_dcache_range() ends with
/// its own dsb internally (see arch/arm/cpu/armv8/cache_v8.c), so no
/// separate barrier call is needed here.
fn dsiCmdDmaTxOne(dsi_base: usize, dma_addr: usize, len: usize) c_int {
    dsiCmdDmaTrigger(dsi_base, dma_addr, len);
    return dsiCmdDmaWait(dsi_base);
}

var g_pretrigger_snapshot_done: bool = false;
var g_snap_ctrl: u32 = 0xFFFFFFFF;
var g_snap_lane_swap: u32 = 0xFFFFFFFF;
var g_snap_lane_ctrl: u32 = 0xFFFFFFFF;
var g_snap_cmd_dma_ctrl: u32 = 0xFFFFFFFF;
var g_snap_cmd_cfg0: u32 = 0xFFFFFFFF;
var g_snap_cmd_cfg1: u32 = 0xFFFFFFFF;
var g_snap_trig_ctrl: u32 = 0xFFFFFFFF;
var g_snap_clk_ctrl: u32 = 0xFFFFFFFF;

fn dsiCmdDmaTrigger(dsi_base: usize, dma_addr: usize, len: usize) void {
    // FORENSIC PRE-TRIGGER SNAPSHOT (SPEC.md task #5 log): captured
    // exactly once, DSI0 only, at the very first TRIG_DMA this driver
    // ever fires -- the exact moment requested for direct comparison
    // against Linux's live values (CMD_DMA_CTRL=0x00020000 expected --
    // note: real logical offset, not the physical-unshifted 0x038 the
    // request used; LANE_CTRL=0x01000000 at this exact register post-
    // shift-fix, not the older 0x00001F00 pre-fix value).
    if (!g_pretrigger_snapshot_done and dsi_base == 0x0ae94004) {
        g_snap_ctrl = mmioRead32(dsi_base, DSI_CTRL);
        g_snap_lane_swap = mmioRead32(dsi_base, DSI_LANE_SWAP_CTRL);
        g_snap_lane_ctrl = mmioRead32(dsi_base, DSI_LANE_CTRL);
        g_snap_cmd_dma_ctrl = mmioRead32(dsi_base, DSI_CMD_DMA_CTRL);
        g_snap_cmd_cfg0 = mmioRead32(dsi_base, DSI_CMD_CFG0);
        g_snap_cmd_cfg1 = mmioRead32(dsi_base, DSI_CMD_CFG1);
        g_snap_trig_ctrl = mmioRead32(dsi_base, DSI_TRIG_CTRL);
        g_snap_clk_ctrl = mmioRead32(dsi_base, DSI_CLK_CTRL);
        g_pretrigger_snapshot_done = true;
    }

    // REAL GAP FOUND (SPEC.md task #5 log): msm_dsi_host_xfer_prepare()/
    // msm_dsi_host_cmd_xfer_commit() set INTR_CTRL's MASK_CMD_DMA_DONE
    // bit (bit1) before every single command DMA and clear it after
    // (msm_dsi_host_xfer_restore()) -- never done anywhere in this
    // driver before. Replicated here per-trigger since this function is
    // the real driver's cmd_xfer_commit equivalent; the wait side clears
    // it in dsiCmdDmaWait().
    var intr_ctrl_pre = mmioRead32(dsi_base, DSI_INTR_CTRL);
    intr_ctrl_pre |= DSI_IRQ_MASK_CMD_DMA_DONE;
    mmioWrite32(dsi_base, DSI_INTR_CTRL, intr_ctrl_pre);

    flush_dcache_range(dma_addr, dma_addr + ((len + 63) & ~@as(usize, 63)));

    // NEVER-VERIFIED ASSUMPTION (SPEC.md task #5 log): every theory so
    // far has assumed the DCS packet bytes actually EXIST in physical
    // DRAM at dma_addr. That has never once been proven. The scratch
    // buffer was moved to the HIGH DRAM bank (0x8bb500000) this session
    // purely on the strength of /proc/iomem -- if U-Boot's own mem_map
    // doesn't cover that bank (build_mem_map() only maps what the
    // previous bootloader handed over in gd->dram[]), or if it maps it
    // somewhere unexpected, the CPU stores land nowhere real and the
    // DSI engine fetches whatever garbage is physically there. Read the
    // first 8 bytes straight back HERE, immediately after the flush --
    // flush_dcache_range() is dc civac (clean AND invalidate), so this
    // read misses the now-invalidated line and pulls a fresh copy from
    // physical DRAM. Expected for command #0: byte0=0xFF, byte1=0x26,
    // byte2=0x15 (DCS short write, 1 param), byte3=0x80 (VC0 + ECC).
    if (!g_dmabuf_diag_done and dsi_base == 0x0ae94004) {
        const src: [*]volatile u8 = @ptrFromInt(dma_addr);
        var rb: u64 = 0;
        var b: usize = 0;
        while (b < 8) : (b += 1) rb |= @as(u64, src[b]) << @intCast(b * 8);
        g_dmabuf_readback = rb;
        g_dmabuf_diag_done = true;
    }

    // REAL GAP FOUND (SPEC.md task #5 log): DMA_BASE is a plain 32-bit
    // register (dsi.xml's reg32) and this driver's scratch buffer now
    // lives in the HIGH DRAM bank (SHENG_MDSS_DSI_DMA_SCRATCH_PHYS,
    // 0x8bb500000 -- a 35-bit address, impossible to express in 32
    // bits at all). Write the SMMU-mapped IOVA instead of the raw
    // physical pointer -- smmuBypassMdssStream() builds a real 3-level
    // page-table entry translating SMMU_MAPPED_IOVA (0x1000, matching
    // Linux's own live, proven-working IOVA choice exactly) to this
    // exact physical buffer.
    const iova: usize = SMMU_MAPPED_IOVA + (dma_addr - @as(usize, @intCast(SHENG_MDSS_DSI_DMA_SCRATCH_PHYS)));
    if (!g_iova_diag_done and dsi_base == 0x0ae94004) {
        g_iova_written = @truncate(iova);
        g_iova_dma_addr = dma_addr;
        g_iova_l3_readback = smmu_l3_table[1];
        g_iova_diag_done = true;
    }
    mmioWrite32(dsi_base, DSI_DMA_BASE, @truncate(iova));
    mmioWrite32(dsi_base, DSI_DMA_LEN, @truncate(len));
    mmioWrite32(dsi_base, DSI_TRIG_DMA, 1);
}

var g_dmabuf_diag_done: bool = false;
var g_dmabuf_readback: u64 = 0xDEADDEADDEADDEAD;

/// First 8 bytes read back out of physical DRAM at the DMA scratch
/// address, immediately after the clean+invalidate. See the comment at
/// the read site. 0x...8015_26FF (little-endian byte0=0xFF) means the
/// packet is genuinely in DRAM and the DSI engine is fetching real
/// data; anything else (0, 0xFFFFFFFF, junk) means every register-level
/// theory chased so far was investigating the wrong layer entirely.
export fn sheng_mdss_dmabuf_diag() callconv(.c) i64 {
    return @bitCast(g_dmabuf_readback);
}

var g_iova_diag_done: bool = false;
var g_iova_written: u32 = 0xFFFFFFFF;
var g_iova_dma_addr: usize = 0;
var g_iova_l3_readback: u64 = 0;

export fn sheng_mdss_iova_diag1() callconv(.c) i64 {
    // high32 = the actual DMA_BASE value written (should be near 0x1000);
    // low32 = truncated dma_addr passed in (sanity check it's our scratch phys)
    const dma_addr_low: u32 = @truncate(g_iova_dma_addr);
    return (@as(i64, g_iova_written) << 32) | @as(i64, dma_addr_low);
}
export fn sheng_mdss_iova_diag2() callconv(.c) i64 {
    return @bitCast(g_iova_l3_readback);
}

fn dsiCmdDmaWait(dsi_base: usize) c_int {
    var waited: u32 = 0;
    while (waited < DMA_BUSY_POLL_TIMEOUT_US) : (waited += 10) {
        const status = mmioRead32(dsi_base, DSI_STATUS0);
        if ((status & STATUS0_CMD_MODE_DMA_BUSY) == 0) {
            var intr_ctrl_post = mmioRead32(dsi_base, DSI_INTR_CTRL);
            intr_ctrl_post &= ~DSI_IRQ_MASK_CMD_DMA_DONE;
            mmioWrite32(dsi_base, DSI_INTR_CTRL, intr_ctrl_post);
            return 0;
        }
        udelay(10);
    }
    // DIAGNOSTIC (SPEC.md task #5 log): capture FIFO_STATUS/DLN0_PHY_ERR
    // at the moment of a genuine timeout, DSI0 only -- these weren't
    // covered by the earlier err_status diagnostic (ACK_ERR_STATUS/
    // TIMEOUT_STATUS only) and are the most direct place to see WHY a
    // real DMA transaction never completes.
    if (dsi_base == 0x0ae94004) {
        g_fifo_status_on_timeout = mmioRead32(dsi_base, DSI_FIFO_STATUS);
        g_dln0_phy_err_on_timeout = mmioRead32(dsi_base, DSI_DLN0_PHY_ERR);
    }
    var intr_ctrl_post = mmioRead32(dsi_base, DSI_INTR_CTRL);
    intr_ctrl_post &= ~DSI_IRQ_MASK_CMD_DMA_DONE;
    mmioWrite32(dsi_base, DSI_INTR_CTRL, intr_ctrl_post);
    return ETIMEDOUT;
}

/// REAL GAP FOUND (SPEC.md task #5 log): msm_dsi_host_cmd_xfer_commit()
/// in the real driver is fire-and-forget -- writes DMA_BASE/DMA_LEN/
/// TRIG_DMA and returns immediately, with no busy-poll. msm_dsi_manager
/// _cmd_xfer_trigger() calls it twice back-to-back (DSI1 then DSI0),
/// so both DMA engines are triggered cycles apart and run genuinely in
/// parallel -- the wait/completion happens separately, AFTER both are
/// already triggered. dsiCmdDmaTxOne() (used for every command this
/// driver has ever sent) is blocking: it polls CMD_MODE_DMA_BUSY to
/// completion before returning, so calling it twice in sequence
/// (dsi1 then dsi0) actually serializes the physical transmission --
/// DSI1 completes its entire burst and returns to LP-11 before DSI0
/// even starts. For a stitched dual-DSI panel expecting synchronized
/// SOT across both links, that time gap could be exactly what causes
/// the DDIC to see a desync and silently abort. This function
/// replicates the real driver's trigger-both-then-wait-both ordering.
var g_dma_retries: u32 = 0;

/// Number of command-DMA retries that were needed across the whole
/// panel init. 0 means every command went out first time.
export fn sheng_mdss_dsi_retry_count() callconv(.c) u32 {
    return g_dma_retries;
}

fn dsiCmdDmaTxDualOnce(dsi0_base: usize, dsi1_base: usize, dma_addr: usize, len: usize) c_int {
    // msm_dsi_host_xfer_prepare(): temporarily OR in CMD_MODE_EN|ENABLE
    // for the duration of the command, then restore CTRL exactly
    // (msm_dsi_host_xfer_restore()):
    //
    //   msm_host->dma_cmd_ctrl_restore = dsi_read(msm_host, REG_DSI_CTRL);
    //   dsi_write(msm_host, REG_DSI_CTRL,
    //             msm_host->dma_cmd_ctrl_restore |
    //             DSI_CTRL_CMD_MODE_EN | DSI_CTRL_ENABLE);
    //
    // This driver never needed it while the whole init ran in command
    // mode. Now that the link switches to VIDEO mode before the DCS
    // sequence (matching the panel driver's prepare_prev_first
    // ordering), CMD_MODE_EN is clear and commands cannot be issued
    // without it -- exactly what the first attempt at the reorder hit:
    // sheng.verify bit0 (DSI CTRL) mismatched and the DSC encoder went
    // back to producing nothing.
    const restore0 = mmioRead32(dsi0_base, DSI_CTRL);
    const restore1 = mmioRead32(dsi1_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, restore0 | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    mmioWrite32(dsi1_base, DSI_CTRL, restore1 | CTRL_CMD_MODE_EN | CTRL_ENABLE);

    dsiCmdDmaTrigger(dsi1_base, dma_addr, len);
    dsiCmdDmaTrigger(dsi0_base, dma_addr, len);

    const ret1 = dsiCmdDmaWait(dsi1_base);
    const ret0 = dsiCmdDmaWait(dsi0_base);

    mmioWrite32(dsi0_base, DSI_CTRL, restore0);
    mmioWrite32(dsi1_base, DSI_CTRL, restore1);

    if (ret1 != 0) return ret1;
    return ret0;
}

/// Retries a timed-out command DMA (SPEC.md task #5 log).
///
/// Panel init has been failing intermittently at RANDOM command indices
/// (#5, #11, #54 observed across many boots), always recoverable by a
/// full power cycle. The index being random rules out any per-command
/// content problem: it is a marginal/transient condition in the DMA
/// path itself. Each such boot returns -(10000+idx) and aborts probe
/// before any diagnostics are populated, costing a full test cycle.
///
/// Two retries with a short settle between them. The retry count is
/// exported as sheng.retries, so this both stabilises testing AND
/// measures how marginal the path actually is -- a non-zero count on an
/// otherwise-successful boot is real evidence the DMA path is not yet
/// reliable, which a simple pass/fail never showed.
fn dsiCmdDmaTxDual(dsi0_base: usize, dsi1_base: usize, dma_addr: usize, len: usize) c_int {
    var attempt: u32 = 0;
    while (attempt < 3) : (attempt += 1) {
        const ret = dsiCmdDmaTxDualOnce(dsi0_base, dsi1_base, dma_addr, len);
        if (ret == 0) return 0;
        g_dma_retries += 1;
        udelay(1000);
    }
    return dsiCmdDmaTxDualOnce(dsi0_base, dsi1_base, dma_addr, len);
}

/// Real DCS READ (Get Power Mode, 0x0A) with genuine BTA (bus
/// turnaround) -- every DCS command sent by this driver up to now,
/// including the panel init sequence and the test patch, has been a
/// plain write with no BTA/ACK (dsi_host.c's own comment: "no BTA/ACK
/// is required for a plain DCS write, so a completely unresponsive
/// panel looks identical to a working one from the DSI host's point
/// of view"). This is the first command in this driver that actually
/// requires the panel to respond -- a definitive test of whether
/// anything is reaching the panel at the physical layer at all,
/// separate from whether the DPU/video pipeline is configured
/// correctly. Mirrors msm_dsi_host_cmd_rx()'s real sequence: Set
/// Maximum Return Packet Size (type 0x37) first, clear RDBK_DATA_CTRL,
/// then the actual read command (data type 0x06 = DCS_READ, MSM
/// packet flags BIT(5) = read/BTA-expected, from dsi_cmd_dma_add()'s
/// `if (msg->rx_buf && msg->rx_len) data[3] |= BIT(5)`), then read the
/// response back from RDBK_DATA0. DSI0 (master) only, matching the
/// real driver's rx path (single host). Returns ((count << 8) |
/// data_byte) on success, where `count` is RDBK_DATA_CTRL's own COUNT
/// field (bits 16-23) -- the number of bytes the hardware actually
/// captured over BTA. This disambiguates a genuine "panel responded
/// with 0x00" from "panel never responded at all": RDBK_DATA_CTRL is
/// explicitly cleared right before the read, so DATA0 alone reads 0 in
/// BOTH cases -- only COUNT being nonzero proves real bytes came back
/// over the wire. Negative return = DMA-level error/timeout.
///
/// BUG FIXED (SPEC.md task #5 log): the first version of this function
/// only triggered DSI0's DMA. msm_dsi_manager_cmd_xfer_trigger() in the
/// real driver shows that for sync-dual-dsi, EVERY command commit
/// mirrors to both DSI0 and DSI1 together (DSI1 committed first, then
/// DSI0) -- including whatever becomes a read/BTA from DSI0's own
/// context. dsiSendDcs() already does this correctly for every other
/// command in this driver; this function didn't, for the trigger step
/// (RX-side register reads are correctly DSI0-only, matching the real
/// driver's single-host rx path -- only the trigger was wrong). If
/// this panel's dual-link stitching needs coordinated activity on both
/// links to respond to LP/BTA traffic at all, a DSI0-only trigger
/// could look malformed to the panel and explain a zero response on
/// its own, independent of the base driver (which never had this bug).
/// SINGLE-HOST DCS read (SPEC.md task #5 log).
///
/// This is the one test that would POSITIVELY prove the panel is alive:
/// a read requires the panel to turn the bus around and drive data
/// back. Everything else we have is one-way -- "success" has only ever
/// meant our DMA engine shipped bytes. The two liveness tests tried so
/// far were both invalid: ALL_PIXELS_ON is implementation-defined on a
/// RAM-less video-mode panel, and DCS 0x51 cannot move the backlight
/// because the KTZ8866 is in I2C-brightness mode (the visible soft-start
/// ramp is driven over I2C, not by the panel's PWM).
///
/// The existing read path issues the read on BOTH hosts at once via
/// dsiCmdDmaTxDual(). On a bonded panel each host has its own physical
/// link, and msm's rx path is explicitly single-host
/// (msm_dsi_manager_cmd_xfer() reads only from the master). Two
/// simultaneous bus-turnaround requests is not something the panel is
/// ever asked to do, so every empty read so far may be OUR bug rather
/// than evidence about the panel.
///
///   non-zero count/data -> the panel RECEIVES, DECODES and RESPONDS.
///     Everything upstream is proven good and the fault is confined to
///     the video path.
///   still zero -> two-way communication genuinely fails on a link
///     whose every register matches working silicon.
export fn sheng_mdss_dsi_read_power_mode_single(dsi0_base: usize, dma_scratch: usize) callconv(.c) i64 {
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);

    // Set Maximum Return Packet Size = 1, master only.
    dst[0] = 1;
    dst[1] = 0;
    dst[2] = 0x37;
    dst[3] = 0x80;
    var ret = dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4);
    if (ret != 0) return -1;

    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, RDBK_DATA_CTRL_CLR);
    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, 0);

    // DCS read (0x06), cmd 0x0A Get Power Mode, BTA expected.
    dst[0] = 0x0a;
    dst[1] = 0x00;
    dst[2] = 0x06;
    dst[3] = 0x80 | 0x20;
    ret = dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4);
    if (ret != 0) return -2;

    // Give the panel time to turn the bus around and reply.
    udelay(20000);

    const ctrl = mmioRead32(dsi0_base, DSI_RDBK_DATA_CTRL);
    const resp = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    const status = mmioRead32(dsi0_base, DSI_STATUS0);
    // high32 = RDBK_DATA_CTRL (bits 23:16 = byte count), low32 = data
    _ = status;
    return (@as(i64, ctrl) << 32) | @as(i64, resp);
}

export fn sheng_mdss_dsi_read_power_mode(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) i64 {
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);

    // Set Maximum Return Packet Size (type 0x37, short write, 2-byte
    // little-endian payload = requested length, here 1). Mirrored to
    // both hosts, DSI1 first, matching dsiSendDcs()'s own order.
    dst[0] = 1;
    dst[1] = 0;
    dst[2] = 0x37;
    dst[3] = 0x80; // last, short, no BTA needed for this command itself
    var ret = dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, 4);
    if (ret != 0) return ret;

    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, RDBK_DATA_CTRL_CLR);
    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, 0);

    // The actual read: data-id 0x06 (DCS_READ), cmd=0x0A (Get Power
    // Mode), BTA-expected flag set. Triggered on both hosts genuinely
    // in parallel (see dsiCmdDmaTxDual()'s comment) -- only DSI0's
    // RDBK/status registers are read back afterward, matching the real
    // driver's single-host rx path.
    dst[0] = 0x0a;
    dst[1] = 0x00;
    dst[2] = 0x06;
    dst[3] = 0x80 | 0x20; // last, short, BTA-expected (BIT(5))
    ret = dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, 4);
    if (ret != 0) return ret;

    const ctrl = mmioRead32(dsi0_base, DSI_RDBK_DATA_CTRL);
    const count: i64 = @intCast((ctrl >> 16) & 0xff);
    const resp = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    return (count << 8) | @as(i64, @intCast(resp & 0xff));
}

/// Reads ACK_ERR_STATUS and TIMEOUT_STATUS on DSI0 -- U-Boot polls a
/// single busy bit and never looks at these, so a BTA timeout or LP-RX
/// timeout during a transaction has never been visible: DSI_TRIG_DMA's
/// busy bit clearing only means the host's OWN DMA engine finished,
/// not that the transaction completed error-free. Packed as
/// (ack_err_status << 32) | timeout_status.
export fn sheng_mdss_dsi_read_error_status(dsi0_base: usize) callconv(.c) i64 {
    const ack_err = mmioRead32(dsi0_base, DSI_ACK_ERR_STATUS);
    const timeout = mmioRead32(dsi0_base, DSI_TIMEOUT_STATUS);
    return (@as(i64, @intCast(ack_err)) << 32) | @as(i64, @intCast(timeout));
}

/// Reads DSI_CTRL and DSI_LANE_CTRL on DSI0 as OUR driver's own
/// execution actually left them at the moment of the BTA attempt --
/// not Linux's later, differently-reprogrammed post-teardown value
/// (which decodes against no documented bitfield at all: 0x20070000
/// live-read has bits 16/17/18/29 set, none of which match ENABLE/
/// CLK_EN/LANE0-3/VID_MODE_EN/CMD_MODE_EN/ECC_CHECK/CRC_CHECK per
/// dsi.xml -- either genuinely undocumented bits this header doesn't
/// cover, or not directly comparable to our own driver's state at
/// all). Packed as (DSI_CTRL << 32) | DSI_LANE_CTRL.
export fn sheng_mdss_dsi_read_ctrl_state(dsi0_base: usize) callconv(.c) i64 {
    const ctrl = mmioRead32(dsi0_base, DSI_CTRL);
    const lane_ctrl = mmioRead32(dsi0_base, DSI_LANE_CTRL);
    return (@as(i64, @intCast(ctrl)) << 32) | @as(i64, @intCast(lane_ctrl));
}

/// Self-check: write a known test pattern to DSI_CTRL, read back
/// immediately (nothing else touches the register in between), restore
/// the real value. Returns the immediate readback. If this comes back
/// as 0x20070000 (or anything other than the pattern just written),
/// the write is not landing at all -- not a later overwrite, not a
/// different execution path, the bus transaction itself is being
/// dropped or aliased.
export fn sheng_mdss_dsi_ctrl_writeback_selfcheck(dsi_base: usize) callconv(.c) u32 {
    const test_pattern: u32 = 0xA5A5A5A5;
    mmioWrite32(dsi_base, DSI_CTRL, test_pattern);
    const readback = mmioRead32(dsi_base, DSI_CTRL);
    mmioWrite32(dsi_base, DSI_CTRL, CTRL_CLK_EN | CTRL_ALL_LANES | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    return readback;
}

/// Isolates whether the write-drop is specific to DSI_CTRL or affects
/// the whole DSI host block (which would point at DSI_CLK_CTRL -- the
/// block's own internal AHB clock gate -- not actually landing either,
/// leaving every sub-register in this block unable to accept writes at
/// all). Tests CLK_CTRL, LANE_SWAP_CTRL (a register already confirmed
/// correct via live steal, so its pre-test value is known), and CTRL,
/// each with an immediate write-then-read, restoring real values after.
/// Packed as (clk_ctrl_readback << 32) | (lane_swap_readback << 16) |
/// low 16 bits unused (ctrl selfcheck already covered separately).
/// Result of the write-immediately-after-reset probe done inside
/// dsiHostBringUp(), before anything else touches the controller.
/// 0xFFFFFFFF sentinel means it never ran (dsi_base mismatch).
export fn sheng_mdss_dsi_earliest_ctrl_selfcheck() callconv(.c) u32 {
    return g_earliest_ctrl_selfcheck;
}

export fn sheng_mdss_dsi_status0_before_first_cmd() callconv(.c) u32 {
    return g_status0_before_first_cmd;
}

export fn sheng_mdss_dsi_snapshot_1() callconv(.c) i64 {
    return (@as(i64, @intCast(g_snap_ctrl)) << 32) | @as(i64, @intCast(g_snap_lane_swap));
}
export fn sheng_mdss_dsi_snapshot_2() callconv(.c) i64 {
    return (@as(i64, @intCast(g_snap_lane_ctrl)) << 32) | @as(i64, @intCast(g_snap_cmd_dma_ctrl));
}
export fn sheng_mdss_dsi_snapshot_3() callconv(.c) i64 {
    return (@as(i64, @intCast(g_snap_cmd_cfg0)) << 32) | @as(i64, @intCast(g_snap_cmd_cfg1));
}
export fn sheng_mdss_dsi_snapshot_4() callconv(.c) i64 {
    return (@as(i64, @intCast(g_snap_trig_ctrl)) << 32) | @as(i64, @intCast(g_snap_clk_ctrl));
}

/// Puts TRIG_CTRL back to Linux's exact live value (TE |
/// BLOCK_DMA_WITHIN_FRAME | DMA_TRIGGER(SW)) now that panel init is
/// done and the DPU is about to start streaming -- at which point
/// bit12's "wait until cmd mdp is idle" interlock has a live MDP to
/// synchronise against and becomes correct rather than deadlocking.
/// See TRIG_CTRL_CMD_INIT_VALUE's comment for why init needs the other
/// value.
export fn sheng_mdss_dsi_trig_ctrl_restore(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    mmioWrite32(dsi0_base, DSI_TRIG_CTRL, TRIG_CTRL_VALUE);
    mmioWrite32(dsi1_base, DSI_TRIG_CTRL, TRIG_CTRL_VALUE);
}

export fn sheng_mdss_dsi_timeout_diag() callconv(.c) i64 {
    return (@as(i64, @intCast(g_fifo_status_on_timeout)) << 32) |
        @as(i64, @intCast(g_dln0_phy_err_on_timeout));
}

export fn sheng_mdss_dsi_block_writeback_selfcheck(dsi_base: usize) callconv(.c) i64 {
    const test_pattern: u32 = 0x5A5A5A5A;

    const saved_clk_ctrl = mmioRead32(dsi_base, DSI_CLK_CTRL);
    mmioWrite32(dsi_base, DSI_CLK_CTRL, test_pattern);
    const clk_ctrl_readback = mmioRead32(dsi_base, DSI_CLK_CTRL);
    mmioWrite32(dsi_base, DSI_CLK_CTRL, saved_clk_ctrl);

    const saved_lane_swap = mmioRead32(dsi_base, DSI_LANE_SWAP_CTRL);
    mmioWrite32(dsi_base, DSI_LANE_SWAP_CTRL, test_pattern);
    const lane_swap_readback = mmioRead32(dsi_base, DSI_LANE_SWAP_CTRL);
    mmioWrite32(dsi_base, DSI_LANE_SWAP_CTRL, saved_lane_swap);

    return (@as(i64, @intCast(clk_ctrl_readback)) << 32) | @as(i64, @intCast(lane_swap_readback));
}

/// Sends one DCS command to both DSI0 and DSI1 from the SAME DMA
/// buffer -- qcom,sync-dual-dsi mirrors every command to both
/// controllers rather than splitting the buffer, matching how the
/// real panel driver only ever issues commands to dsi[0] and relies
/// on hardware mirroring (see nt36532e_init_sequence's comment in
/// this file and sheng_tianma_init_sequence() in the kernel panel
/// driver).
/// Inverse of the wake-up half of sheng_mdss_dsi_panel_init(): Display
/// Off (0x28) then Sleep In (0x10), mirroring nt36532e's real
/// .disable()/.unprepare() DCS sequence. Must be sent host-side (DSI
/// still in/switched back to command mode) before the PHY/DISPCC/GPIO
/// teardown below removes the panel's ability to receive commands at
/// all. Best-effort: DSI is being torn down regardless, so a failure
/// here doesn't abort the rest of the teardown.
/// DIAGNOSTIC BISECT (SPEC.md task #5 log): MIPI DCS 0x23,
/// ALL_PIXELS_ON. The panel drives every pixel to full-on from its own
/// internal logic -- it needs NO video data, no DSC stream, no DPU
/// pipeline. It is therefore a direct test of a question none of the
/// register diagnostics can answer: does this panel actually RECEIVE
/// AND EXECUTE our commands?
///
/// Every command so far has "succeeded" only in the sense that the DSI
/// DMA engine shipped bytes down the lanes. DCS reads have never
/// returned data on this hardware (the long-standing zero-byte BTA
/// result), so sheng.power_mode=0 is a failed read rather than the
/// panel reporting itself off -- meaning we have never once confirmed
/// the panel processed anything we sent.
///
///   Screen goes WHITE -> panel is alive, command path works end to
///     end, display is genuinely on. The black screen is then isolated
///     to the video/DSC data path, and everything downstream of the
///     DSI host is what needs attention.
///   Screen stays BLACK -> the panel is not acting on commands at all.
///     Every DPU/LM/DSC/rate finding is then downstream of a dead
///     command path, and the entire DPU investigation is misdirected.
///
/// Deliberately left ACTIVE (no 0x22 restore) so the result is
/// unambiguous to the naked eye.
export fn sheng_mdss_dsi_all_pixels_on(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) c_int {
    return dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x23, &[_]u8{});
}

export fn sheng_mdss_dsi_panel_sleep(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) void {
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x28, &[_]u8{});
    udelay(20000); // datasheet-typical gap between display-off and sleep-in
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x10, &[_]u8{});
    udelay(5000);
}

fn dsiSendDcs(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, cmd: u8, args: []const u8) c_int {
    var buf: [16]u8 = undefined;
    const len = buildMsmCmdPacket(&buf, cmd, args);
    if (len == 0) return -22; // -EINVAL-ish, packet too big for our scratch stack buffer

    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    for (buf[0..len], 0..) |b, i| dst[i] = b;

    return dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, len);
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

    return dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, padded);
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
/// INVERTED TEST (SPEC.md task #5 log): skip the panel reset and the
/// entire DCS init sequence, leaving the panel in whatever state ABL
/// left it, and just bring the DSI host up and stream video at it.
///
/// ABL initialises this panel (its splash is visible before U-Boot), and
/// Linux re-initialises it successfully AFTER us on the same hardware --
/// so the panel is demonstrably re-initialisable and the silicon is
/// fine. Ours specifically does not take: a properly-formed single-host
/// DCS read with BTA returns nothing (sheng.rd1 = 0), while every
/// register in the DSI/DPU/PHY/MDSS spaces and all 128 PPS bytes are
/// identical to the working kernel.
///
/// If the panel is still live from ABL, streaming at it without
/// touching it at all should produce an image:
///   image appears -> OUR init sequence is what breaks the panel, and
///     the fault is in the command path, not the video path.
///   still black -> ABL did not leave it in a usable state, or the
///     video path itself cannot drive it, which points away from the
///     command path entirely.
///
/// Host bring-up and the video-mode switch are KEPT -- those touch the
/// SoC's DSI controller, not the panel.
const SKIP_PANEL_INIT_TEST: bool = false;

/// Host bring-up + video-mode switch, split out so it can run BEFORE
/// the panel is powered and reset (SPEC.md task #5 log).
///
/// Measured from the working kernel with a ktime-stamped trace:
///
///   691.3ms  bridge_pre_enable
///   743.0ms  host_enable_video      <-- video mode ON
///   743.058ms panel_prepare enter   <-- panel powered 8us later
///   743.48ms panel_reset enter      <-- panel reset AFTER video mode
///   778.6ms  init_seq enter
///   952.6ms  init_seq exit
///
/// So the panel is powered, reset and initialised onto a link that is
/// ALREADY in video mode. This driver did all three before the host
/// ever left command mode. An earlier attempt at this reorder moved
/// only the video-mode switch and left the reset where it was, which
/// regressed the DSC encoder -- the ordering was right, the
/// implementation was not: the reset must follow the switch, not
/// precede it.
export fn sheng_mdss_dsi_host_video_prepare(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    dsiHostBringUp(dsi0_base);
    dsiHostBringUp(dsi1_base);
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);
}

export fn sheng_mdss_dsi_panel_init(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, enable_dsc: bool) callconv(.c) c_int {
    // REAL GAP FOUND (SPEC.md task #5 log): smmuBypassMdssStream() was
    // only ever called inside sheng_mdss_dpu_start(), which runs AFTER
    // this entire panel init sequence -- meaning it was never actually
    // in effect for the DSI host's OWN command-mode DMA fetches
    // (dma_scratch), only for the DPU's later SSPP video fetch. Command
    // #0's DMA read has been hitting an unbypassed SMMU stream this
    // whole time. Moved here, before any DSI command traffic at all.
    smmuBypassMdssStream();

    // Host bring-up + video-mode switch now run in
    // sheng_mdss_dsi_host_video_prepare(), before the panel is powered
    // and reset -- matching the kernel's measured timeline.

    // ORDERING EXPERIMENT REVERTED (SPEC.md task #5 log): switching to
    // video mode HERE (before the DCS sequence, matching the panel
    // driver's prepare_prev_first flag) measurably regressed things --
    // sheng.verify bit0 (DSI CTRL) mismatched and the DSC encoder went
    // from OUT_STATUS 0x18xxxx back to 0, INT_STAT 0x7b0 back to 0x180
    // -- and it stayed regressed even after implementing the
    // xfer_prepare/restore that video-mode commands require. The
    // measurement beats the reading of prepare_prev_first; the switch
    // stays in dpu_start(). The xfer_prepare/restore is KEPT, since
    // Linux does it unconditionally regardless of link mode.

    // LP-11 settle test (SPEC.md task #5 log): U-Boot runs linearly and
    // near-instantly compared to Linux's mutex/scheduler-laden power-on
    // path -- if the panel's physical LP receiver needs the lines held
    // in LP-11 (both HIGH) for a minimum analog settle time before it
    // will accept a Start-of-Transmission burst, firing the first DCS
    // command microseconds after lane enable could look like line
    // noise to the panel rather than a real command. Brute-force test:
    // hold here before any command traffic.
    udelay(250000); // bumped 100ms -> 250ms brute-force test (SPEC.md task #5 log)

    // DIAGNOSTIC (SPEC.md task #5 log): a new, genuine DMA timeout
    // appeared after the DSI 6G register-shift fix + re-stolen values
    // (previously every command "completed" with no response; now
    // something actually hangs). Encode WHICH command failed into the
    // return value (-(10000+index) for the init-sequence loop,
    // -(20000+stage) for the named stages after it) instead of just
    // propagating the raw errno, so the failure point is visible via
    // the sheng.panel env var without needing a live console.
    var idx: i32 = 0;
    for (nt36532e_init_sequence) |entry| {
        const ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, entry.cmd, entry.args);
        if (ret != 0) return -(10000 + idx);
        idx += 1;
    }

    if (enable_dsc) {
        // Enable DSC.
        var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x90, &[_]u8{0x03});
        if (ret != 0) return -20001;

        // DSC Picture Parameter Set.
        ret = dsiSendRawLong(dsi0_base, dsi1_base, dma_scratch, 0x0a, &nt36532e_pps_144hz);
        if (ret != 0) return -20002;

        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x9d, &[_]u8{0x01});
        if (ret != 0) return -20003;

        // REAL BUG FOUND (SPEC.md task #5 log): this was mislabeled
        // "144Hz framerate control branch" and sent 0xb2=0x91/0xb3=0x40
        // -- those are actually the real driver's `cur_vrefresh == 120
        // || cur_vrefresh == 60` branch values, not 144Hz at all. The
        // real sheng_tianma_init_sequence() has three branches on
        // cur_vrefresh (120/60 -> 0x91/0x40; 90/50/48/30 -> 0x00/0x80;
        // else -> 0x00/0x00), and nt36532e_get_current_mode() returns
        // mode index 0 (the *first* entry in sheng_tianma_modes[], the
        // 144Hz mode) whenever connector->state->crtc is NULL --
        // exactly our initial-prepare()/first-boot scenario. 144
        // matches neither explicit branch, so the real driver falls
        // through to the ELSE branch: 0xb2=0x00, 0xb3=0x00. We were
        // sending the wrong branch's values.
        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0xb2, &[_]u8{0x00});
        if (ret != 0) return -20004;
        ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0xb3, &[_]u8{0x00});
        if (ret != 0) return -20005;
    }

    // ===================================================================
    // PANEL LIVENESS TEST (SPEC.md task #5 log) -- uses the BACKLIGHT as
    // the detector, which is the one output on this device we can see.
    //
    // Every measurable artifact now matches the working kernel exactly:
    // the 128-byte DSC PPS byte-for-byte, DSI0 39/39, DSI1 39/39, DPU
    // 55/55, PHY 31/31, the MDSS wrapper including its three
    // undocumented registers, the 87-command init sequence, and the DSC
    // encoder's own status. A colour generated INSIDE the DPU pipe
    // (solid fill, no memory fetch) still does not appear. Yet we have
    // never once positively confirmed the panel EXECUTES anything we
    // send -- "success" has only ever meant the DMA engine shipped the
    // bytes. ALL_PIXELS_ON was inconclusive (implementation-defined on
    // a RAM-less panel), DCS reads have never returned data, and the
    // DSI TPG cannot produce a decodable stream on a DSC panel.
    //
    // But the panel driver documents that DCS 0x51 "controls power
    // output to the ktz8866 chips" -- i.e. the panel itself drives the
    // backlight brightness. Our init already sends 0x51 0x0f 0xff (max)
    // and 0x53 0x24 (backlight control on). Re-sending 0x51 with ZERO
    // therefore has a directly VISIBLE consequence that needs no video
    // data, no DSC, and no DPU:
    //
    //   backlight goes dark/dim -> the panel RECEIVES AND EXECUTES our
    //     commands. Its display really is on, and the fault is confined
    //     to the video/DSC datapath.
    //   backlight stays fully lit -> the panel is NOT executing our
    //     commands. Every register matching live is then irrelevant,
    //     because nothing we send is being acted on, and the whole
    //     investigation belongs on the command path to the panel.
    //
    // Deliberately left applied so the result is unambiguous.
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x51, &[_]u8{ 0x00, 0x00 });
    udelay(200000);
    // ===================================================================

    // Exit sleep mode (MIPI DCS 0x11, no args), then the panel needs
    // 120ms before it'll accept display-on.
    var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x11, &[_]u8{});
    if (ret != 0) return -20006;
    // mdelay() is a U-Boot macro (udelay(n*1000)), not a linkable
    // symbol -- call udelay directly instead.
    udelay(120000);

    // Set display on (MIPI DCS 0x29, no args).
    ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x29, &[_]u8{});
    if (ret != 0) return -20007;

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
// Bumped from 16x16 (easy to miss entirely) to 300x300 -- still
// comfortably under the ~1MB gap between SHENG_MDSS_DSI_DMA_SCRATCH
// and SHENG_MDSS_FB_ADDR (270005 bytes total packet size), but large
// enough to be unmistakable on a 3048x2032 panel. The end-coordinate
// bytes below were also fixed: the old single-byte encoding
// (TEST_PATCH_W - 1 truncated to u8) only worked by accident for
// sizes <= 256; a real 4-byte MIPI DCS column/page address set needs
// the full 16-bit end value split into hi/lo bytes.
const TEST_PATCH_W: usize = 200;
const TEST_PATCH_H: usize = 200;

export fn sheng_mdss_dsi_test_patch(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) c_int {
    const w_end: u16 = @intCast(TEST_PATCH_W - 1);
    const h_end: u16 = @intCast(TEST_PATCH_H - 1);
    var ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x2a, &[_]u8{ 0x00, 0x00, @truncate(w_end >> 8), @truncate(w_end & 0xff) });
    if (ret != 0) return ret;

    ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x2b, &[_]u8{ 0x00, 0x00, @truncate(h_end >> 8), @truncate(h_end & 0xff) });
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

    return dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, padded);
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

/// DECISIVE BISECT (SPEC.md task #5 log): SSPP SOLID FILL.
///
/// dpu_hw_sspp.c: DPU_SSPP_SOLID_FILL sets BIT(22) in SSPP_SRC_FORMAT
/// and the colour comes from SSPP_SRC_CONSTANT_COLOR (0x3c) / _REC1
/// (0x180). The pipe then SYNTHESISES pixels internally -- no memory
/// fetch, no SMMU, no framebuffer -- while everything downstream
/// (LM -> DSC -> INTF -> DSI -> panel) runs exactly as configured,
/// including real DSC compression. Unlike the DSI test pattern
/// generator, which injects downstream of the DSC encoders and so can
/// never produce a decodable stream on this DSC-mandatory panel, this
/// test IS decodable.
///
/// It settles what every current measurement leaves open: the DSC
/// encoder is verifiably running and emitting a valid compressed
/// stream -- but a valid compressed stream of a BLACK frame is exactly
/// what an SSPP delivering no pixels would produce, and every register,
/// fault and FIFO reading would still look perfect. Which is precisely
/// the state we are in.
///
///   RED appears -> mixer, DSC, INTF, DSI and panel all work; the fault
///     is the SSPP memory fetch (framebuffer/SMMU/bandwidth), despite
///     clean fault registers.
///   Still black -> the fault is downstream of the pipe, and the
///     framebuffer path is exonerated entirely.
///
/// Deliberately RED (0xFF0000FF in this panel's 0xAABBGGRR ordering) so
/// it cannot be confused with the green framebuffer fill.
const SSPP_SOLID_FILL_TEST: bool = false;
const SSPP_SRC_CONSTANT_COLOR: usize = 0x3c;
const SSPP_SRC_CONSTANT_COLOR_REC1: usize = 0x180;
const SSPP_SOLID_FILL_FORMAT_BIT: u32 = 1 << 22;
const SSPP_SOLID_FILL_COLOR: u32 = 0xFF0000FF;

/// REAL GAP FOUND (SPEC.md task #5 log): the SSPP QoS / danger-safe
/// register group. grep for "danger", "safe_lut", "qos" or "creq" in
/// this file returned ZERO hits -- none of it was ever written.
///
/// These registers decide whether the fetch pipe gets memory bandwidth
/// priority. SSPP_QOS_CTRL's only bit here is
/// SSPP_QOS_CTRL_DANGER_SAFE_EN (dpu_hw_sspp.c), which arms the whole
/// danger/safe escalation mechanism; DANGER_LUT/SAFE_LUT are the FIFO
/// fill-level thresholds at which the pipe escalates its urgency to the
/// memory controller, and CREQ_LUT_0/1 the corresponding client-request
/// priorities. Left at zero with the mechanism disarmed, the pipe never
/// signals urgency and can be starved indefinitely by other masters.
///
/// This is the failure mode that fits the current evidence exactly: the
/// DSC encoder is demonstrably RUNNING and producing output, the DSI
/// link is fed (FIFO_STATUS matches live), every register in the DSI,
/// DPU and PHY spaces is bit-identical to working silicon, and the
/// panel is black. An SSPP that cannot win bandwidth delivers no pixels
/// while everything downstream faithfully compresses and transmits a
/// BLACK frame -- no fault, no underflow flag, nothing to see.
///
/// Values are Linux's own live registers on this panel.
const SSPP_DANGER_LUT: usize = 0x60;
const SSPP_SAFE_LUT: usize = 0x64;
const SSPP_CREQ_LUT: usize = 0x68;
const SSPP_QOS_CTRL: usize = 0x6c;
const SSPP_CREQ_LUT_0: usize = 0x74;
const SSPP_CREQ_LUT_1: usize = 0x78;
const SSPP_DANGER_LUT_VALUE: u32 = 0x0003FFFF;
const SSPP_SAFE_LUT_VALUE: u32 = 0x0000FE00;
const SSPP_CREQ_LUT_VALUE: u32 = 0x00000000;
const SSPP_QOS_CTRL_DANGER_SAFE_EN: u32 = 1 << 0;
const SSPP_CREQ_LUT_0_VALUE: u32 = 0x22335777;
const SSPP_CREQ_LUT_1_VALUE: u32 = 0x00112222;

// XRGB8888, computed offline replicating dpu_hw_setup_format_impl()'s
// bit-packing for INTERLEAVED_RGBX_FMT(XRGB8888, 4, BPC8A, BPC8, BPC8,
// BPC8, C1_B_Cb, C0_G_Y, C2_R_Cr, C3_ALPHA) from mdp_format.c.
const SSPP_XRGB8888_SRC_FORMAT: u32 = 0x000236ff;
const SSPP_XRGB8888_UNPACK_PATTERN: u32 = 0x03020001;
const SSPP_OP_MODE_PE_OVERRIDE: u32 = 1 << 23;
// CROSS-VERIFIED: live SSPP SRC_OP_MODE reads 0x80000000 on both rects,
// not the bit23 PE_OVERRIDE previously assumed here.
const SSPP_OP_MODE_LIVE: u32 = 0x80000000;
// Live SSPP_MULTIRECT_OPMODE -- see the write site.
const SSPP_MULTIRECT_OPMODE_LIVE: u32 = 0x3;

// Multirect: TIME_MX mode with rect index in bits[1:0].
const SSPP_MULTIRECT_INDEX_REC0: u32 = 0x0;
const SSPP_MULTIRECT_INDEX_REC1: u32 = 0x1;
const SSPP_MULTIRECT_MODE_TIME_MX: u32 = 1 << 2;

const LM_OP_MODE: usize = 0x00;
/// REAL GAP FOUND (SPEC.md task #5 log): LM_OP_MODE was being written
/// as 0, annotated as a "right_mixer" flag. That is a misreading of the
/// register. In DPU it is written by dpu_hw_lm_setup_color3() (the
/// .setup_alpha_out op):
///
///   op_mode = (op_mode & (BIT(31) | BIT(30))) | mixer_op_mode;
///   DPU_REG_WRITE(c, LM_OP_MODE, op_mode);
///
/// where _dpu_crtc_blend_setup_mixer() builds mixer_op_mode as
/// `1 << pstate->stage`, and pstate->stage = DPU_STAGE_0 +
/// normalized_zpos. DPU_STAGE_BASE(0) is the border/background layer,
/// so DPU_STAGE_0 == 1 and a single plane at zpos 0 needs bit1 set.
///
/// Written as 0, NO blend stage is enabled and the layer mixer emits
/// border colour -- black -- regardless of how correctly the pipe
/// feeding it is configured. That was the final blocker: SSPP fetch
/// address/format, LM_OUT_SIZE, blend op, CTL routing, DSC, link rate
/// and FIFOs all read back correct and the panel still showed nothing.
///
/// This also pairs with the CTL_LAYER0 value already in use: its
/// mix field is (stage_index + 1) = 1, naming the same stage 1 that
/// this bit enables. Only one half of that pairing was programmed.
const LM_OP_MODE_STAGE0_ENABLED: u32 = 1 << 1;
const LM_OUT_SIZE: usize = 0x04;
const LM_STAGE0_OFFSET: usize = 0x20; // sdm845_lm_sblk.blendstage_base[0]
const LM_BLEND0_CONST_ALPHA: usize = 0x04;
const LM_BLEND0_OP: usize = 0x00;
// DPU_BLEND_FG_ALPHA_FG_CONST(0<<0) | DPU_BLEND_BG_ALPHA_FG_CONST(0<<8) |
// DPU_BLEND_BG_INV_ALPHA(1<<10): single opaque layer, no blending below it.
// CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log): both of
// these were hand-derived and both were wrong. Dumped from Linux's own
// LM0/LM1 via devmem while DRM drove this exact panel.
//
// blend_op: live reads 0x100 == DPU_BLEND_BG_ALPHA_BG_CONST (bit8), not
// the bit10 previously guessed here. dpu_hw_lm_setup_blend_config()
// writes whatever dpu_crtc hands it; for the bottom-most opaque layer
// that is BG_ALPHA_BG_CONST with FG_ALPHA_FG_CONST(0).
const LM_BLEND_OP_OPAQUE: u32 = 0x100;
// const_alpha: live reads 0x00FF0000 -- bg alpha 0xff in the high half,
// fg alpha 0 in the low half. The previous 0x00FF00FF set both.
const LM_CONST_ALPHA_OPAQUE: u32 = 0x00FF0000;
// LM1 additionally carries bit31, which dpu_hw_lm_setup_color3()
// deliberately preserves through its `op_mode & (BIT(31) | BIT(30))`
// read-modify-write. Writing OP_MODE blind (as this driver does, having
// no prior value to preserve) drops it unless set explicitly.
// Live: LM0 = 0x00000002, LM1 = 0x80000002.
const LM_OP_MODE_LM1_EXTRA: u32 = 1 << 31;

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
/// REAL GAP FOUND (SPEC.md task #5 log): the DSC CTL sub-block has two
/// more registers (dpu_hw_dsc_1_2.c's "DPU_DSC_CTL register offsets"
/// block) that this driver never wrote at all:
///
///   DSC_DATA_IN_SWAP (0x08) -- live 0x0002C688
///   DSC_CLK_CTRL     (0x0C) -- live 0xC0000000
///
/// DSC_CLK_CTRL is a CLOCK GATE on the DSC block. Left clear, the
/// encoder's registers remain readable over AHB and its status
/// registers still respond -- which is precisely what was measured:
/// ENC_GENERAL_STATUS and ENC_INT_STAT non-zero (block alive and
/// clocked enough to answer), ENC_HSLICE_STATUS stalled at 0x0d
/// (live 0x00140000), and ENC_OUT_STATUS = 0 against live's 0x002E0000
/// -- i.e. the encoder emits NOTHING. On a DSC-mandatory panel that
/// alone is a black screen, with every other register in the pipeline
/// bit-identical to working silicon (sheng.verify = 0).
///
/// Same shape as this session's GCC_DISP_HF_AXI_CLK bug: a clock that
/// appears in no register diff, gating a block whose configuration was
/// already correct. These are almost certainly set by ABL and then
/// wiped by our own mdssCoreBcrReset(), never to be restored.
const DSC_DATA_IN_SWAP: usize = 0x08;
const DSC_CLK_CTRL: usize = 0x0c;
const DSC_DATA_IN_SWAP_VALUE: u32 = 0x0002C688;
const DSC_CLK_CTRL_VALUE: u32 = 0xC0000000;

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

// CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log). Live
// INTF_CONFIG  = 0x80800000 (was written as 0 here).
// Live INTF_CONFIG2 = 0x00001011 = DATABUS_WIDEN(0) | DATA_HCTL_EN(4) |
// bit12 -- note DCE_DATA_COMPRESS(1), the ONLY bit this driver used to
// set, is NOT set on working hardware. Both INTF1 and INTF2 read
// identical values.
const INTF_CONFIG_LIVE: u32 = 0x80800000;
const INTF_CONFIG2_LIVE: u32 = 0x00001011;
// INTF_MUX's pingpong-select is the low nibble, but bits[19:16] read
// 0xF on live hardware and this driver writes the whole register (no
// read-modify-write), so they must be set explicitly or they get
// cleared. Live: INTF1 = 0x000F0000 (PP_0), INTF2 = 0x000F0001 (PP_1).
const INTF_MUX_LIVE_BASE: u32 = 0x000F0000;
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
/// REAL GAP FOUND (SPEC.md task #5 log): dpu_hw_ctl_set_fetch_pipe_active()
/// writes a bitmask of which SSPPs are PERMITTED TO FETCH:
///
///   for (i = 0; i < SSPP_MAX; i++)
///           if (test_bit(i, fetch_active) && fetch_tbl[i] != CTL_INVALID_BIT)
///                   val |= BIT(fetch_tbl[i]);
///   DPU_REG_WRITE(&ctx->hw, CTL_FETCH_PIPE_ACTIVE, val);
///
/// fetch_tbl[SSPP_DMA0] is 0, so the single DMA pipe this driver uses
/// needs BIT(0). Live hardware reads exactly 0x1. This driver never
/// wrote the register at all, leaving it 0 -- a hard gate in front of
/// the whole pixel path: with no pipe marked fetch-active, SSPP does
/// not fetch, and every downstream block is correctly configured to
/// carry nothing.
const CTL_FETCH_PIPE_ACTIVE: usize = 0x0fc;
const CTL_FETCH_PIPE_SSPP_DMA0: u32 = 1 << 0;

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
const DPU_TEST_STOP_STAGE: u32 = 99;

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
    // CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log): this
    // whole function's values were transcribed independently of the
    // panel-side PPS and never checked against each other -- a gap this
    // file has flagged as the prime suspect for "video streams but
    // nothing is visible" for a long time. Dumping Linux's own live DSC
    // encoder registers via devmem while DRM drove this exact panel and
    // diffing all 25 of them found 21 identical and 5 wrong. Both
    // encoder instances read back identical, so one set covers both.
    //
    // The five corrections are mutually consistent and describe a
    // single coherent error: this panel uses FOUR 762-px slices across
    // the full 3048 width, i.e. TWO soft slices per encoder, whereas
    // this code described one slice per encoder over a 1524-px picture
    // -- half the width and half the slices. A DSC decoder whose slice
    // geometry disagrees with the PPS it was sent emits nothing
    // decodable, which is precisely the observed symptom (link clean at
    // 144Hz, FIFOs healthy, panel initialised, screen black).
    //
    // DSC_CMN_MAIN_CNF: shared register, written identically by both
    // instances -- SPLIT_PANEL with num_active_slice_per_enc in
    // bits[8:7]. Live = 0x101, i.e. field value 2 (bit8), not 1 (bit7).
    dpuHwWrite(dce_base, 0, DSC_CMN_MAIN_CNF, (DSC_MODE_SPLIT_PANEL & 1) | (@as(u32, 2) << 7));

    // ENC_DF_CTRL: initial_lines(8) | VIDEO_MODE(bit9) | max_addr(bits[18+])
    // max_addr = 2400/num_softslice - 1. num_softslice is 2, not 1 (see
    // above), giving 1199 -- confirmed by live 0x12BC0202 vs our
    // previous 0x257C0202, which differ in exactly this field.
    const initial_lines: u32 = 2;
    const max_addr: u32 = 2400 / 2 - 1;
    dpuHwWrite(dce_base, enc_off, DSC_ENC_DF_CTRL, (initial_lines & 0xff) | (1 << 9) | (max_addr << 18));

    // DSC_MAIN_CONF: version_minor(28) | bpp(10, U6.4=128) |
    // block_pred_enable(20) | convert_rgb(4, =0 per panel driver) |
    // line_buf_depth(6,4bit) | bits_per_component(0,4bit)
    var main_conf: u32 = (@as(u32, 1) << 28); // dsc_version_minor = 1
    main_conf |= (@as(u32, 8 << 4)) << 10; // bits_per_pixel = 8.0bpp in U6.4
    main_conf |= 1 << 20; // block_pred_enable
    main_conf |= 1 << 4; // convert_rgb -- live hardware has this SET; the
    // previous "=0 per panel driver" reading was wrong (live 0x...0258
    // vs our 0x...0248, differing in exactly this bit)
    main_conf |= (9 & 0xf) << 6; // line_buf_depth
    main_conf |= 8 & 0xf; // bits_per_component
    dpuHwWrite(dce_base, enc_off, DSC_MAIN_CONF, main_conf);

    // pic_width is the FULL panel width, not the per-half 1524 --
    // dsi_timing_setup() sets dsc->pic_width = mode->hdisplay, and for
    // bonded DSI the DRM mode carries the complete panel width (see its
    // own comment: "the current DRM mode has the complete width of the
    // panel"). Live 0x07F00BE8 = 2032 x 3048.
    dpuHwWrite(dce_base, enc_off, DSC_PICTURE_SIZE, (3048 & 0xffff) | (@as(u32, 2032) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_SLICE_SIZE, (762 & 0xffff) | (@as(u32, 16) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_MISC_SIZE, 762 & 0xffff);
    dpuHwWrite(dce_base, enc_off, DSC_HRD_DELAYS, (512 & 0xffff) | (@as(u32, 637) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_SCALE, 32 & 0x3f);
    dpuHwWrite(dce_base, enc_off, DSC_RC_SCALE_INC_DEC, (454 & 0xffff) | (@as(u32, 10 & 0x7ff) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_1, (12 & 0x1f)); // first_line_bpg_offset only, second_line=0
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_2, (1639 & 0xffff) | (@as(u32, 1154) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_3, (6144 & 0xffff) | (@as(u32, 4336) << 16));
    dpuHwWrite(dce_base, enc_off, DSC_RC_OFFSETS_4, 0); // nsl_bpg_offset/second_line_offset_adj unused (dsc v1.1)

    // flatness det_thresh: live hardware reads 2 in this field
    // (0x0983 >> 10), not the 7 previously derived here -- the
    // drm_dsc_flatness_det_thresh() reading was wrong for bpc=8.
    const det_thresh_flatness: u32 = 2;
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
    // CROSS-VERIFIED AGAINST LIVE HARDWARE: live DSC_CFG reads 0x1801 on
    // both instances = bit0 | bit11 | bit12. Bit10 (!convert_rgb) is
    // NOT set -- which also resolves a contradiction this file carried:
    // MAIN_CONF's live value has convert_rgb SET (bit4), so its inverse
    // must be clear here. The old comment reasoned from the panel
    // driver's zero-initialised dsc struct and got both halves wrong.
    var dsc_cfg: u32 = 1 << 0; // encoder enable
    dsc_cfg |= 1 << 11; // bits_per_component == 8
    dsc_cfg |= 1 << 12; // SPLIT_PANEL mode
    dpuHwWrite(dce_base, ctl_off, DSC_CFG, dsc_cfg);

    // DSC_CTL: bind this encoder's output mux to its pingpong block.
    dpuHwWrite(dce_base, ctl_off, DSC_CTL_MUX, pp_idx & 0x7);

    // Ungate the DSC block's clock and restore the data-in swap config
    // -- see DSC_CLK_CTRL's comment. Written AFTER DSC_CFG so the
    // encoder is fully configured before its clock is enabled.
    dpuHwWrite(dce_base, ctl_off, DSC_DATA_IN_SWAP, DSC_DATA_IN_SWAP_VALUE);
    dpuHwWrite(dce_base, ctl_off, DSC_CLK_CTRL, DSC_CLK_CTRL_VALUE);
}

// THE REAL ANSWER for why U-Boot's own render never showed pixels
// (SPEC.md task #5 log): live devmem read of the apps_smmu's SCR0
// (global config, base 0x15000000) showed USFCFG=1 (bit 8) --
// unidentified/unmatched IOMMU streams FAULT rather than bypass by
// default on this hardware. The display subsystem's real stream ID
// (mdss's `iommus = <&apps_smmu 0x1c00 0x2>` in sm8550.dtsi) has a
// pre-existing, firmware-provisioned SMR entry (found by scanning all
// 105 stream-match-register groups: SMR[3] = 0x80021c00, VALID=1,
// MASK=0x2, ID=0x1c00 -- matching the devicetree exactly, at a fixed
// slot index, not something any OS driver dynamically allocates).
// Every raw physical-address SSPP fetch we ever did was almost
// certainly silently aborted by the SMMU -- explaining precisely why
// frame/line counters increment fine (pure INTF timing, no memory
// access needed) while zero real pixel content ever arrived, with no
// visible hang (the fault interrupt is enabled in SCR0 too, but
// nothing in U-Boot services it, so it just sits pending harmlessly).
// Fix: force this exact stream's S2CR entry to BYPASS (TYPE=1) before
// ever touching the framebuffer -- no page tables needed, physical
// addresses pass straight through as IOVAs. Whatever S2CR[3] held
// during U-Boot's actual prior runs can't be observed anymore (Linux's
// own SMMU driver reprograms it to real translated/context-bank mode
// during its own probe), so don't guess: just set it ourselves.
// REAL GAP FOUND (SPEC.md task #5 log, kernel pr_info trace comparison):
// a real, working Linux boot's msm_dsi_host_cmd_xfer_commit() NEVER
// passes a raw physical DRAM address into DMA_BASE -- every single
// command DMA this session's traced kernel captured used dma_base=
// 0x1000, a tiny SMMU-translated IOVA, proving the real driver
// genuinely relies on stage-1 translation for this stream, not
// passthrough. U-Boot's own in-tree ARM SMMU-500 driver
// (drivers/iommu/qcom-hyp-smmu.c, configure_smr_s2cr()'s comment,
// verbatim): "WARNING: Don't change this to use S2CR_TYPE_BYPASS!
// Some Qualcomm boards have angry hypervisor firmware that converts
// S2CR type BYPASS to type FAULT on write." smmuBypassMdssStream()
// did exactly the thing that comment warns against -- forcing
// S2CR[3] to TYPE_BYPASS(1) -- which, if SM8550 is one of those
// boards, means every DSI command DMA fetch has been silently
// FAULTED at the SMMU/interconnect boundary this entire session:
// the bus master's read never reaches the DSI PHY at all, so
// CMD_MODE_DMA_BUSY never clears and DLN0_PHY_ERR stays zero --
// exactly this session's unchanging failure signature. Replaced
// with that same driver's own proven workaround: S2CR_TYPE_TRANS
// pointing at a context bank whose stage-1 MMU is left disabled
// (SCTLR.M unset, TCR/TTBR/MAIR all zero) -- physical addresses
// still pass straight through untranslated, but the word "BYPASS"
// never appears in the S2CR write the hypervisor is watching for.
// Must match SHENG_MDSS_DSI_DMA_SCRATCH in sheng_mdss.c exactly -- the
// one physical buffer every DSI command DMA this driver ever sends
// uses, now moved to the high DRAM bank (see that constant's comment).
const SHENG_MDSS_DSI_DMA_SCRATCH_PHYS: u64 = 0x8bb500000;
const APPS_SMMU_BASE: usize = 0x15000000;
const SMMU_GR0_ID0: usize = 0x20;
const SMMU_GR0_ID1: usize = 0x24;
const SMMU_S2CR_BASE: usize = 0xc00;
const SMMU_S2CR_MDSS_INDEX: usize = 3; // SMR[3] confirmed matching ID=0x1c00 MASK=0x2
const SMMU_S2CR_TYPE_TRANS: u32 = 0;
const SMMU_CBAR_TYPE_S2_TRANS: u32 = 0;
const SMMU_CBAR_TYPE_S1_TRANS_S2_BYPASS: u32 = 1;
const SMMU_CBA2R_VA64: u32 = 1;
const SMMU_SCTLR_CFCFG: u32 = 1 << 7;
const SMMU_SCTLR_CFIE: u32 = 1 << 6;
const SMMU_SCTLR_CFRE: u32 = 1 << 5;
const SMMU_VMID_UNUSED: u32 = 0xff;

// Live-captured off the currently-running, genuinely-rendering Linux
// system's own MDSS context bank (python /dev/mem walk, SPEC.md task
// #5 log): SCTLR=0x67, TCR=0x80351c, confirming 4KB granule / T0SZ=28
// (36-bit input address size, start_level=1 for a 4KB-granule 3-level
// walk -- so a level-1 descriptor is a valid 1GB block).
const SMMU_TCR_LIVE_LINUX_VALUE: u32 = 0x80351c;
const SMMU_SCTLR_LIVE_LINUX_VALUE: u32 = 0x67;
// MAIR0 byte 0 (AttrIndx=0): Normal memory, Inner/Outer Write-Back,
// Read/Write-Allocate (0xFF, the standard ARMv8 encoding) -- our own
// choice, not required to match Linux's own index assignment since
// this is a separate table or this driver's own context bank.
const SMMU_MAIR0_NORMAL_WB: u32 = 0xff;

// REAL GAP FOUND (SPEC.md task #5 log): a live LPAE walk of the exact
// context bank the WORKING Linux system is using right now (strict-
// devmem temporarily disabled to allow the /dev/mem read) resolved
// Linux's own dma_base=0x1000 IOVA to physical 0x887368000 -- deep in
// the HIGH DRAM bank (0x880000000+), nowhere near the low <4GB bank
// this driver's scratch buffer has always lived in. A 1GB *block*
// descriptor can't express an independent IOVA->PA mapping (the
// low-order bits of input and output address must match at block
// granularity) -- reaching an arbitrary high-bank physical target
// from a small, 32-bit-representable IOVA (required since DMA_BASE
// is a plain reg32) needs genuine page-level (4KB) translation: a
// full 3-level walk, exactly mirroring Linux's own IOVA choice
// (0x1000) so this exact IOVA value, already proven to work on this
// silicon/firmware, is reused rather than picking a new untested one.
const SMMU_MAPPED_IOVA: usize = 0x1000;
// Table/page descriptor bit layout, shared by all 3 levels here:
// valid(bit0)=1, table-or-page(bit1)=1 (both L1/L2 "table" descriptors
// AND the final L3 "page" descriptor require bit1 set -- only L1/L2
// *block* descriptors would leave it clear, and we don't use those
// here). Leaf (L3) descriptors additionally need AttrIndx/SH/AF for
// the actual memory attributes; L1/L2 table descriptors ignore those
// bits (they just point at the next table).
const SMMU_DESC_TABLE: u64 = 0x1 | 0x2;
const SMMU_DESC_PAGE_ATTRS: u64 = (1 << 10) | (0b11 << 8) | (0 << 2) | 0x1 | 0x2; // AF|SH=inner|AttrIndx=0|page|valid

fn smmuTableDescriptor(next_table_phys: u64) u64 {
    return (next_table_phys & ~@as(u64, 0xfff)) | SMMU_DESC_TABLE;
}
fn smmuPageDescriptor(page_phys: u64) u64 {
    return (page_phys & ~@as(u64, 0xfff)) | SMMU_DESC_PAGE_ATTRS;
}

/// Level-1 1GB BLOCK descriptor: same attributes as a leaf page, but
/// bit1 CLEAR (block, not table) -- the one place in this file that
/// distinguishes the two. Output address must be 1GB-aligned.
fn smmuBlockDescriptor1G(block_phys: u64) u64 {
    return (block_phys & ~@as(u64, 0x3fffffff)) |
        ((1 << 10) | (0b11 << 8) | (0 << 2) | 0x1); // AF|SH=inner|AttrIndx=0|valid, bit1=0 => block
}

/// The DPU's SSPP framebuffer fetch goes through this SAME context
/// bank -- sm8550.dtsi gives the whole `mdss` node one stream mapping
/// (`iommus = <&apps_smmu 0x1c00 0x2>`), so DSI's command DMA and the
/// DPU's pixel fetch share it. Stage 1 is enabled here, which means
/// every MDSS master's addresses are now translated, not just DSI's.
///
/// The 3-level table above maps exactly ONE 4KB page (IOVA 0x1000 ->
/// the DSI scratch buffer). SHENG_MDSS_FB_ADDR, which SSPP is
/// programmed with as a raw physical address, is not in it -- so the
/// pixel fetch translation-faults, SSPP starves, and the panel shows
/// black while INTF1's frame/line counters advance perfectly normally
/// (timing generator and pixel fetch are independent).
///
/// Identity-map the whole 0x80000000-0xC0000000 GB with a single
/// level-1 block descriptor so the framebuffer's physical address is
/// also a valid IOVA. L1 index = IOVA >> 30 = 2 for 0x80000000.
const SMMU_FB_IDENTITY_BLOCK_BASE: u64 = 0x80000000;
const SMMU_FB_IDENTITY_L1_INDEX: usize = SMMU_FB_IDENTITY_BLOCK_BASE >> 30;

// 4KB-aligned 3-level translation table for the MDSS context bank's
// TTBR0 -- board.c's build_mem_map() identity-maps every DRAM bank
// (MT_NORMAL | INNER_SHARE), so these globals' own virtual addresses
// (BSS, within the low DRAM bank) equal their physical addresses.
// SMMU_MAPPED_IOVA (0x1000) needs L1 idx=0, L2 idx=0, L3 idx=1 (see
// the earlier live python walk's own index derivation).
var smmu_l1_table: [512]u64 align(4096) = [_]u64{0} ** 512;
var smmu_l2_table: [512]u64 align(4096) = [_]u64{0} ** 512;
var smmu_l3_table: [512]u64 align(4096) = [_]u64{0} ** 512;

var g_smmu_id1: u32 = 0xFFFFFFFF;
var g_smmu_cbx: i32 = -2; // -2 = function never ran; -1 = ran but found no free CB
var g_smmu_s2cr_before: u32 = 0xFFFFFFFF;
var g_smmu_s2cr_after: u32 = 0xFFFFFFFF;

fn smmuBypassMdssStream() void {
    const id1 = mmioRead32(APPS_SMMU_BASE, SMMU_GR0_ID1);
    g_smmu_id1 = id1;
    g_smmu_s2cr_before = mmioRead32(APPS_SMMU_BASE, SMMU_S2CR_BASE + 4 * SMMU_S2CR_MDSS_INDEX);
    const num_cb: u32 = id1 & 0xff;
    const pgshift: u6 = if ((id1 & (1 << 31)) != 0) 16 else 12;
    const numpagendxb: u32 = (id1 >> 28) & 0x7;
    const cb_pg_offset: usize = @as(usize, 1) << @intCast(numpagendxb + 1);
    const page_size: usize = @as(usize, 1) << pgshift;
    const gr1_base = APPS_SMMU_BASE + page_size * 1;

    var cbx: i32 = -1;
    var i: usize = 0;
    while (i < num_cb) : (i += 1) {
        const cbar = mmioRead32(gr1_base, 4 * i);
        const ctype = (cbar >> 16) & 0x3;
        const vmid = cbar & 0xff;
        // Available (matching alloc_cb()'s own check): already S2_TRANS
        // (the likely reset value), or S1_TRANS_S2_BYPASS with no VMID
        // claimed yet.
        if (ctype == SMMU_CBAR_TYPE_S2_TRANS or
            (ctype == SMMU_CBAR_TYPE_S1_TRANS_S2_BYPASS and vmid == SMMU_VMID_UNUSED))
        {
            var new_cbar = cbar & ~@as(u32, (0x3 << 16) | 0xff);
            new_cbar |= (SMMU_CBAR_TYPE_S1_TRANS_S2_BYPASS << 16);
            mmioWrite32(gr1_base, 4 * i, new_cbar);

            const cba2r_off = 0x800 + 4 * i;
            var cba2r = mmioRead32(gr1_base, cba2r_off);
            cba2r |= SMMU_CBA2R_VA64;
            mmioWrite32(gr1_base, cba2r_off, cba2r);

            cbx = @intCast(i);
            break;
        }
    }
    g_smmu_cbx = cbx;
    if (cbx < 0) return; // no free context bank -- shouldn't happen, we're first touch

    // REAL GAP FOUND (SPEC.md task #5 log, live SMMU register read off
    // the exact CB the WORKING Linux boot is using right now): SCTLR=
    // 0x67 has bit0 (M, stage-1 MMU enable) SET -- Linux genuinely runs
    // this stream through real, enabled translation, not bypass and
    // not a disabled-S1-behind-TYPE_TRANS trick. That trick (this
    // driver's previous approach, live-confirmed to leave S2CR
    // genuinely reprogrammed via smmu2/smmu3 diagnostics) still
    // produced the exact same unchanging hang -- meaning disabled-S1
    // passthrough isn't accepted as a substitute for real translation
    // on this silicon/firmware. Build an actual minimal identity
    // mapping instead: one valid 1GB block descriptor (level 1, 4KB
    // granule -- matches Linux's own live TCR's start_level=1 exactly)
    // covering the 1GB-aligned region containing both
    // SHENG_MDSS_DSI_DMA_SCRATCH (0xa3100000) and SHENG_MDSS_FB_ADDR
    // (0xa3200000, both within [0x80000000,0xc0000000)) mapped
    // identity (IOVA == PA), with SCTLR.M genuinely enabled. TCR
    // copied verbatim from Linux's own live, proven-working CB
    // register (0x80351c) rather than hand-derived, to avoid getting
    // any of its many field encodings subtly wrong.
    //
    // SUPERSEDED (still SPEC.md task #5 log): that identity mapping,
    // despite genuinely enabling S1 translation exactly like Linux,
    // still produced the identical unchanging hang -- because it was
    // still targeting the LOW bank. Real fix: page-level 3-level walk
    // mapping SMMU_MAPPED_IOVA (0x1000) to SHENG_MDSS_DSI_DMA_SCRATCH's
    // real physical address (now itself moved to the HIGH bank,
    // 0x8bb500000 -- see that constant's comment in sheng_mdss.c).
    const l2_phys: u64 = @intFromPtr(&smmu_l2_table);
    const l3_phys: u64 = @intFromPtr(&smmu_l3_table);
    smmu_l1_table[0] = smmuTableDescriptor(l2_phys);
    smmu_l2_table[0] = smmuTableDescriptor(l3_phys);
    smmu_l3_table[1] = smmuPageDescriptor(SHENG_MDSS_DSI_DMA_SCRATCH_PHYS);
    // ...and the framebuffer GB, identity-mapped, for the DPU's SSPP
    // pixel fetch through this same context bank -- see
    // SMMU_FB_IDENTITY_BLOCK_BASE's comment.
    smmu_l1_table[SMMU_FB_IDENTITY_L1_INDEX] =
        smmuBlockDescriptor1G(SMMU_FB_IDENTITY_BLOCK_BASE);

    const l1_table_addr = @intFromPtr(&smmu_l1_table);
    flush_dcache_range(l1_table_addr, l1_table_addr + @sizeOf(@TypeOf(smmu_l1_table)));
    flush_dcache_range(l2_phys, l2_phys + @sizeOf(@TypeOf(smmu_l2_table)));
    flush_dcache_range(l3_phys, l3_phys + @sizeOf(@TypeOf(smmu_l3_table)));

    const cbx_page = cb_pg_offset + @as(usize, @intCast(cbx));
    const cbx_base = APPS_SMMU_BASE + page_size * cbx_page;
    g_smmu_cbx_base = cbx_base; // for sheng_mdss_smmu_fault_diag()
    const ttbr0: u64 = @intFromPtr(&smmu_l1_table); // identity VA==PA (board.c maps all DRAM banks 1:1)
    mmioWrite32(cbx_base, 0x20, @truncate(ttbr0)); // TTBR0 low
    mmioWrite32(cbx_base, 0x24, @truncate(ttbr0 >> 32)); // TTBR0 high
    mmioWrite32(cbx_base, 0x28, 0); // TTBR1 (unused, T1SZ/EPD1 disabled)
    mmioWrite32(cbx_base, 0x38, SMMU_MAIR0_NORMAL_WB); // S1_MAIR0: index0 = Normal WB RW-Alloc
    mmioWrite32(cbx_base, 0x3c, 0); // S1_MAIR1
    mmioWrite32(cbx_base, 0x30, SMMU_TCR_LIVE_LINUX_VALUE); // TCR -- copied from Linux's own live CB
    mmioWrite32(cbx_base, 0x0, SMMU_SCTLR_LIVE_LINUX_VALUE); // SCTLR -- M bit set, matches Linux exactly

    const s2cr_val: u32 = (SMMU_S2CR_TYPE_TRANS << 16) | @as(u32, @intCast(cbx));
    mmioWrite32(APPS_SMMU_BASE, SMMU_S2CR_BASE + 4 * SMMU_S2CR_MDSS_INDEX, s2cr_val);
    g_smmu_s2cr_after = mmioRead32(APPS_SMMU_BASE, SMMU_S2CR_BASE + 4 * SMMU_S2CR_MDSS_INDEX);
}

var g_smmu_cbx_base: usize = 0;

/// Reads the MDSS context bank's fault status AFTER the DPU has been
/// streaming, plus the SMMU's global fault status. This stops the
/// SSPP-starvation question being a guess: ARM SMMUv2 latches every
/// translation fault here and holds it until written back.
///
///   CB_FSR   (0x058): TF(1)=translation fault, AFF(2), PF(3),
///                     EF(4)=external fault, TLBMCF(5), TLBLKF(6),
///                     SS(30)=stall, MULTI(31)=multiple faults
///   CB_FAR   (0x060): the faulting IOVA, 64-bit -- if SSPP is
///                     starving on an unmapped framebuffer this reads
///                     back an address inside SHENG_MDSS_FB_ADDR's
///                     region, naming the culprit outright
///   sGFSR    (0x048 in GR0): global faults, incl. USF(1) = unmatched
///                     stream -- set if our SMR/S2CR index is wrong
///                     and MDSS transactions aren't hitting our
///                     context bank at all
///
/// FSR == 0 and sGFSR == 0 means translation is NOT the problem and
/// the black screen is downstream (SSPP/LM/DSC/CTL config), which
/// redirects the search rather than leaving it ambiguous.
export fn sheng_mdss_smmu_fault_diag() callconv(.c) i64 {
    if (g_smmu_cbx_base == 0) return -1;
    const fsr = mmioRead32(g_smmu_cbx_base, 0x058);
    const gfsr = mmioRead32(APPS_SMMU_BASE, 0x048);
    return (@as(i64, fsr) << 32) | @as(i64, gfsr);
}

export fn sheng_mdss_smmu_fault_addr() callconv(.c) i64 {
    if (g_smmu_cbx_base == 0) return -1;
    const far_lo = mmioRead32(g_smmu_cbx_base, 0x060);
    const far_hi = mmioRead32(g_smmu_cbx_base, 0x064);
    return @bitCast((@as(u64, far_hi) << 32) | @as(u64, far_lo));
}

export fn sheng_mdss_smmu_diag1() callconv(.c) u32 {
    return g_smmu_id1;
}
export fn sheng_mdss_smmu_diag2() callconv(.c) i64 {
    return (@as(i64, g_smmu_cbx) << 32) | @as(i64, g_smmu_s2cr_before);
}
export fn sheng_mdss_smmu_diag3() callconv(.c) u32 {
    return g_smmu_s2cr_after;
}

/// Disable the timing engines and clear CTL_START/pending flush before
/// handing off to Linux -- previously this driver never did any
/// teardown at all, leaving the DPU actively streaming (continuous
/// memory fetch from our framebuffer) when U-Boot jumps straight into
/// booti with zero cleanup. Reprogramming IOMMU stream tables (which
/// Linux's own arm-smmu driver does during its probe) while a master
/// has live in-flight transactions is a known class of bug that can
/// corrupt IOMMU/GEM state -- matching exactly the "framebuffer is not
/// in virtual address space" GEM/vmap failure Linux hits when this
/// driver runs first. Mirrors dpu_encoder_phys_vid_disable()'s
/// approach: disable timing engines, then let CTL_START's own next
/// flush cycle naturally not re-trigger since nothing keeps poking it.
export fn sheng_mdss_dpu_stop(dpu_base: usize) callconv(.c) void {
    const ctl_base = dpu_base + 0x15000;
    const intf1_base = dpu_base + 0x35000;
    const intf2_base = dpu_base + 0x36000;

    mmioWrite32(intf1_base, INTF_TIMING_ENGINE_EN, 0);
    mmioWrite32(intf2_base, INTF_TIMING_ENGINE_EN, 0);
    mmioWrite32(ctl_base, CTL_START, 0);
    mmioWrite32(ctl_base, CTL_FLUSH, 0);
}

/// dsi_7nm_phy_disable()'s exact sequence, mirrored: drop the REFGEN
/// vote, disable LPRX/CDRX on logical lane 0, clear the lane-enable
/// bits out of CTRL_0, zero LANE_CTRL0, then power down all PHY blocks.
/// Called on both DSI0 and DSI1 PHYs during full teardown so Linux's
/// own dsi_7nm_phy_enable() starts from a genuinely powered-down PHY
/// instead of one this driver left mid-HS-burst.
fn dsiPhyDisable(phy_base: usize) void {
    const lane = phy_base + LANE_BASE_OFFSET;

    mmioWrite32(lane, 0 * LANE_STRIDE + LN_LPRX_CTRL, 0);

    mmioWrite32(phy_base, CMN_GLBL_DIGTOP_SPARE10, 0x0);
    udelay(2);

    mmioClearBits32(phy_base, CMN_CTRL_0, 0x1f);
    mmioWrite32(phy_base, CMN_LANE_CTRL0, 0x0);
    mmioWrite32(phy_base, CMN_CTRL_0, 0x0);
}

fn clkBranchDisable(dispcc_base: usize, cbcr_off: usize) void {
    mmioClearBits32(dispcc_base, cbcr_off, CBCR_ENABLE);
}

/// Inverse of sheng_mdss_dispcc_dsi_clks_init(): gate off every DSI
/// pclk/byte/byte_intf/esc branch this driver turned on, plus the MDP
/// core clock -- so Linux's own dispcc probe re-enables each branch
/// from a clean OFF state (clk_branch2_check_halt-style enable/poll)
/// instead of finding them already running with this driver's
/// configuration (wrong parent for Linux's own clk tree bookkeeping,
/// even though the physical rate happens to be correct).
export fn sheng_mdss_dispcc_dsi_clks_stop(dispcc_base: usize) callconv(.c) void {
    clkBranchDisable(dispcc_base, PCLK0_CLK_CBCR);
    clkBranchDisable(dispcc_base, PCLK1_CLK_CBCR);
    clkBranchDisable(dispcc_base, BYTE0_CLK_CBCR);
    clkBranchDisable(dispcc_base, BYTE1_CLK_CBCR);
    clkBranchDisable(dispcc_base, BYTE0_INTF_CLK_CBCR);
    clkBranchDisable(dispcc_base, BYTE1_INTF_CLK_CBCR);
    clkBranchDisable(dispcc_base, ESC0_CLK_CBCR);
    clkBranchDisable(dispcc_base, ESC1_CLK_CBCR);
    clkBranchDisable(dispcc_base, MDP_CLK_CBCR);
}

/// Full pre-handoff teardown (see board.c/sheng_mdss.c's
/// sheng_mdss_teardown()): DPU pipeline stop, both DSI PHYs powered
/// down, all DSI/MDP DISPCC branches gated off, then MDSS core reset
/// pulsed once more (msm_mdss_reset()'s own pattern -- idempotent,
/// matches what Linux's real probe does as its own first step anyway,
/// but pulsing it here too means the digital logic starts from a known
/// state even before Linux's driver runs). Panel-side reset/avdd/avee
/// teardown (DCS sleep-in, GPIO reset assert) is handled separately in
/// board.c, since those are TLMM GPIO writes, not MMIO register pokes.
export fn sheng_mdss_full_teardown(dpu_base: usize, dsi0_phy_base: usize, dsi1_phy_base: usize, dispcc_base: usize) callconv(.c) void {
    sheng_mdss_dpu_stop(dpu_base);
    dsiPhyDisable(dsi0_phy_base);
    dsiPhyDisable(dsi1_phy_base);
    sheng_mdss_dispcc_dsi_clks_stop(dispcc_base);
    sheng_mdss_core_reset(dispcc_base);
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
    enable_dsc: bool,
) callconv(.c) c_int {
    const half_w: u32 = hactive / 2; // 1524
    // msm_drv.h's align_pitch(): "adreno needs pitch aligned to 32
    // pixels" -- (hactive+31)&~31 = 3072 for hactive=3048, *4 bytes =
    // 12288, matching a live-verified working mmap test on this exact
    // panel (2032*12288 = 24,969,216 bytes, confirmed against a real
    // captured framebuffer-testing log -- see SPEC.md task #5). Our
    // own self-allocated framebuffer isn't required to match Linux's
    // GEM stolen-fb allocation, but DSC slice-boundary/SSPP burst
    // alignment could plausibly care about this even outside that
    // specific Adreno comment's stated reason, and it costs nothing to
    // match a value independently proven correct on this hardware
    // rather than the naive tightly-packed 12192 previously used here.
    const aligned_hactive: u32 = (hactive + 31) & ~@as(u32, 31);
    const stride: u32 = aligned_hactive * 4; // XRGB8888, 32px-aligned stride
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

    // Force the display's IOMMU stream to bypass before any memory
    // fetch is attempted -- see smmuBypassMdssStream()'s comment. This
    // is likely THE reason nothing has ever rendered from this driver.
    smmuBypassMdssStream();

    // -- SSPP: single DMA pipe, multirect TIME_MX, rect0=left half,
    // rect1=right half of the framebuffer.
    // CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log): each
    // multirect rect fetches a HALF-WIDTH window (rect0 at x=0, rect1 at
    // x=half_w), so SRC_SIZE is half_w -- not the full hactive this used
    // to program. Live SSPP SRC_SIZE reads 0x07F005F4 = 2032 x 1524.
    mmioWrite32(sspp_base, SSPP_SRC_SIZE, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_SRC_XY, 0);
    mmioWrite32(sspp_base, SSPP_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_OUT_XY, 0);
    mmioWrite32(sspp_base, SSPP_SRC0_ADDR, @truncate(fb_addr));
    // YSTRIDE0 packs BOTH rects' plane-0 pitch: low16=rect0, high16=rect1
    // (dpu_hw_sspp_setup_sourceaddress's non-SOLO path) -- not two planes
    // of the same rect. Both rects read the same buffer/stride here.
    mmioWrite32(sspp_base, SSPP_SRC_YSTRIDE0, (stride & 0xffff) | ((stride & 0xffff) << 16));
    // QoS / danger-safe writes REVERTED (SPEC.md task #5 log). Copying
    // Linux's live DANGER_LUT/SAFE_LUT/CREQ_LUT/QOS_CTRL values made
    // things monotonically WORSE, measured with a fixed settle delay:
    // ENC_OUT_STATUS went 0x170008 -> 0, ENC_INT_STAT 0x7b0 -> 0x180,
    // and LM0's OP_MODE stopped matching (sheng.verify bit29) when it
    // had been stable for many boots. Arming DANGER_SAFE_EN evidently
    // throttles this pipe rather than prioritising it -- plausibly
    // because the LUT thresholds are meaningful only alongside the
    // interconnect/bandwidth votes Linux also makes, which this driver
    // does not. The register definitions are kept above for reference.

    if (SSPP_SOLID_FILL_TEST) {
        mmioWrite32(sspp_base, SSPP_SRC_CONSTANT_COLOR, SSPP_SOLID_FILL_COLOR);
        mmioWrite32(sspp_base, SSPP_SRC_CONSTANT_COLOR_REC1, SSPP_SOLID_FILL_COLOR);
    }
    mmioWrite32(sspp_base, SSPP_SRC_FORMAT, if (SSPP_SOLID_FILL_TEST)
        SSPP_XRGB8888_SRC_FORMAT | SSPP_SOLID_FILL_FORMAT_BIT
    else
        SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE, SSPP_OP_MODE_LIVE);

    mmioWrite32(sspp_base, SSPP_SRC_SIZE_REC1, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_SRC_XY_REC1, half_w); // x offset = half_w, y=0
    mmioWrite32(sspp_base, SSPP_OUT_SIZE_REC1, (vactive << 16) | half_w);
    // Live OUT_XY_REC1 = 0x000005F4 (x = half_w), not 0.
    mmioWrite32(sspp_base, SSPP_OUT_XY_REC1, half_w);
    // rect1 fetches through SRC1_ADDR, not SRC0_ADDR -- same buffer base,
    // SRC_XY_REC1's x=half_w crops into the right half via YSTRIDE0's
    // high16 pitch.
    mmioWrite32(sspp_base, SSPP_SRC1_ADDR, @truncate(fb_addr));
    mmioWrite32(sspp_base, SSPP_SRC_FORMAT_REC1, if (SSPP_SOLID_FILL_TEST)
        SSPP_XRGB8888_SRC_FORMAT | SSPP_SOLID_FILL_FORMAT_BIT
    else
        SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN_REC1, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE_REC1, SSPP_OP_MODE_LIVE);
    // dpu_hw_sspp_setup_multirect() ORs DPU_SSPP_RECT_0(1) | DPU_SSPP_RECT_1(2)
    // and sets BIT(2) ONLY for TIME_MX. Live reads 0x3 -- both rects,
    // parallel, NOT time-multiplexed as this previously programmed (0x5).
    mmioWrite32(sspp_base, SSPP_MULTIRECT_OPMODE, SSPP_MULTIRECT_OPMODE_LIVE);

    _ = half_stride;

    if (DPU_TEST_STOP_STAGE <= 1) return 0;

    // -- LM: single opaque blendstage each, output = per-half size.
    mmioWrite32(lm0_base, LM_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(lm0_base, LM_OP_MODE, LM_OP_MODE_STAGE0_ENABLED);
    mmioWrite32(lm0_base, LM_STAGE0_OFFSET + LM_BLEND0_CONST_ALPHA, LM_CONST_ALPHA_OPAQUE);
    mmioWrite32(lm0_base, LM_STAGE0_OFFSET + LM_BLEND0_OP, LM_BLEND_OP_OPAQUE);

    mmioWrite32(lm1_base, LM_OUT_SIZE, (vactive << 16) | half_w);
    mmioWrite32(lm1_base, LM_OP_MODE, LM_OP_MODE_STAGE0_ENABLED | LM_OP_MODE_LM1_EXTRA);
    mmioWrite32(lm1_base, LM_STAGE0_OFFSET + LM_BLEND0_CONST_ALPHA, LM_CONST_ALPHA_OPAQUE);
    mmioWrite32(lm1_base, LM_STAGE0_OFFSET + LM_BLEND0_OP, LM_BLEND_OP_OPAQUE);

    // -- CTL_LAYER: route SSPP_DMA0 rect0 into LM_0 stage 0, rect1 into
    // LM_1 stage 0 (ctl_blend_config[SSPP_DMA0][rect] from dpu_hw_ctl.c:
    // rect0 -> idx0/shift18 in CTL_LAYER(lm); rect1 -> idx2/shift8 in
    // CTL_LAYER_EXT2(lm)). Stage index i=0 -> mix=(i+1)&0x7=1.
    // CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log):
    // dpu_hw_ctl_setup_blendstage() writes mix = (stage_index + 1) into
    // the per-SSPP field. The plane sits at DPU_STAGE_0, which is 1
    // (DPU_STAGE_BASE = 0 is the border), so the stage index is 1 and
    // mix is 2 -- the same stage 1 that LM_OP_MODE bit1 enables. This
    // previously wrote mix = 1, disagreeing with its own LM_OP_MODE.
    // Live: CTL_LAYER0 = CTL_LAYER1 = 0x01080000,
    //       CTL_LAYER_EXT2_0 = CTL_LAYER_EXT2_1 = 0x00000200.
    // Note LM1 needs the pipe staged too -- it was previously left with
    // BORDER_OUT only, i.e. the right half of the panel was explicitly
    // configured to show nothing but border colour.
    if (DPU_BORDER_ONLY_BISECT) {
        // See DPU_BORDER_ONLY_BISECT's comment: no pipe staged, mixers
        // emit border, zero memory fetch.
        mmioWrite32(ctl_base, CTL_LAYER0, CTL_MIXER_BORDER_OUT);
        mmioWrite32(ctl_base, CTL_LAYER1, CTL_MIXER_BORDER_OUT);
        mmioWrite32(ctl_base, CTL_LAYER_EXT2_0, 0);
        mmioWrite32(ctl_base, CTL_LAYER_EXT2_1, 0);
        mmioWrite32(lm0_base, LM_OP_MODE, 0);
        mmioWrite32(lm1_base, LM_OP_MODE, LM_OP_MODE_LM1_EXTRA);
    } else {
        mmioWrite32(ctl_base, CTL_LAYER0, CTL_MIXER_BORDER_OUT | (@as(u32, 2) << 18));
        mmioWrite32(ctl_base, CTL_LAYER1, CTL_MIXER_BORDER_OUT | (@as(u32, 2) << 18));
        mmioWrite32(ctl_base, CTL_LAYER_EXT2_0, @as(u32, 2) << 8);
        mmioWrite32(ctl_base, CTL_LAYER_EXT2_1, @as(u32, 2) << 8);
    }

    if (DPU_TEST_STOP_STAGE <= 2) return 0;

    // -- PP: enable DSC routing + wrapper endian-flip quirk bit. Skipped
    // entirely when enable_dsc=false -- untested whether the panel's
    // own PPS (sent by sheng_mdss_dsi_panel_init()) actually matches
    // this DPU-side DSC config, so this lets us isolate whether DSC is
    // really what's blocking a visible image, at the cost of needing
    // ~3x the bandwidth for the same resolution.
    if (enable_dsc) {
        // CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log):
        // both of these read 0 on working silicon, on BOTH pingpongs,
        // while DSC is active. This driver used to set PP_DSC_MODE=1 and
        // PP_DCE_DATA_OUT_SWAP bit18. Consistent with live INTF_CONFIG2
        // NOT carrying DCE_DATA_COMPRESS: on this hardware revision the
        // DSC path is selected through CTL_DSC_ACTIVE/CTL_DSC_FLUSH and
        // the DSC block itself, not via the pingpong. Written explicitly
        // rather than skipped so the state is deterministic regardless
        // of what the previous bootloader left behind.
        mmioWrite32(pp0_base, PP_DCE_DATA_OUT_SWAP, 0);
        mmioWrite32(pp0_base, PP_DSC_MODE, 0);
        mmioWrite32(pp1_base, PP_DCE_DATA_OUT_SWAP, 0);
        mmioWrite32(pp1_base, PP_DSC_MODE, 0);

        // -- DSC: two hard-slice encoder instances sharing the DCE base,
        // dce_0_0 sblk (enc+0x100/ctl+0xf00) for DSC_0, dce_0_1 sblk
        // (enc+0x200/ctl+0xf80) for DSC_1.
        dscConfigureInstance(dce_base, 0x100, 0xf00, 0); // -> PP_0
        dscConfigureInstance(dce_base, 0x200, 0xf80, 1); // -> PP_1
    }

    if (DPU_TEST_STOP_STAGE <= 3) return 0;

    // -- INTF: per-half timing, horizontal porches/sync halved (dual-
    // link split), vertical unchanged. Width is further reduced by the
    // DSC compression ratio (bpp=8 / (bpc=8 * 3 components) = 1/3, per
    // drm_mode_to_intf_timing_params()'s non-DP DSC branch) only when
    // DSC is actually active -- uncompressed mode uses the real
    // per-half pixel width directly.
    const half_hfront = hfront_porch / 2;
    const half_hback = hback_porch / 2;
    const half_hsync = hsync_width / 2;
    const intf_w = if (enable_dsc) half_w / 3 else half_w;

    setupIntfTiming(intf1_base, intf_w, vactive, half_hfront, half_hback, half_hsync, vfront_porch, vback_porch, vsync_width);
    setupIntfTiming(intf2_base, intf_w, vactive, half_hfront, half_hback, half_hsync, vfront_porch, vback_porch, vsync_width);

    mmioWrite32(intf1_base, INTF_MUX, INTF_MUX_LIVE_BASE | 0); // bind to PINGPONG_0
    mmioWrite32(intf2_base, INTF_MUX, INTF_MUX_LIVE_BASE | 1); // bind to PINGPONG_1

    if (DPU_TEST_STOP_STAGE <= 4) return 0;

    // -- CTL top-level routing: both INTFs + both DSC engines active,
    // INTF_1 (DSI0) is the split-link master, video mode (no cmd-mode
    // bit), default (disabled) VM group id per core_major_ver>=7.
    mmioWrite32(ctl_base, CTL_TOP, CTL_DEFAULT_GROUP_ID_SHIFTED);
    mmioWrite32(ctl_base, CTL_INTF_ACTIVE, (@as(u32, 1) << 1) | (@as(u32, 1) << 2)); // INTF_1, INTF_2
    mmioWrite32(ctl_base, CTL_DSC_ACTIVE, if (enable_dsc) @as(u32, 0x3) else 0); // DSC_0, DSC_1
    mmioWrite32(ctl_base, CTL_INTF_MASTER, @as(u32, 1) << 1); // INTF_1 is master
    // Permit SSPP_DMA0 to fetch -- see CTL_FETCH_PIPE_ACTIVE's comment.
    mmioWrite32(ctl_base, CTL_FETCH_PIPE_ACTIVE, CTL_FETCH_PIPE_SSPP_DMA0);

    if (DPU_TEST_STOP_STAGE <= 5) return 0;

    // -- Switch both DSI hosts from command mode to video mode before
    // the timing engines start pushing pixel data. Moving this earlier
    // (before the DCS sequence) was tried and measurably regressed the
    // DSC encoder -- see the note in sheng_mdss_dsi_panel_init().
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
    if (enable_dsc) {
        mmioWrite32(ctl_base, CTL_DSC_FLUSH, 0x3); // DSC_0, DSC_1
    }

    if (DPU_TEST_STOP_STAGE <= 8) return 0;

    const pending_flush = CTL_FLUSH_SSPP_DMA0 | CTL_FLUSH_LM0 | CTL_FLUSH_LM1 |
        CTL_FLUSH_MASK_CTL | CTL_FLUSH_INTF_IDX |
        (if (enable_dsc) CTL_FLUSH_DSC_IDX else 0);
    mmioWrite32(ctl_base, CTL_FLUSH, pending_flush);

    if (DPU_TEST_STOP_STAGE <= 9) return 0;

    mmioWrite32(ctl_base, CTL_START, 1);

    return 0;
}

/// Post-start datapath readback (SPEC.md task #5 log). The panel is
/// lit, DSI commands all succeed, INTF1's frame counter advances
/// (~28 frames/500ms) and the SMMU reports zero faults -- so timing,
/// link and translation are all proven good and the black screen has
/// to be a datapath-config problem between the framebuffer and the
/// mixer output. Rather than keep inspecting write-side code that
/// "looks right", read the pipeline back after it has been running.
///
/// diag1 = CTL_FLUSH  << 32 | CTL_START
///   CTL_FLUSH bits are cleared BY HARDWARE as each block's config is
///   latched. Non-zero here, hundreds of frames after CTL_START, means
///   the commit never completed and none of the SSPP/LM/DSC config
///   below ever took effect -- INTF would then happily stream timing
///   with nothing behind it, which is exactly the symptom.
/// diag2 = SSPP_SRC0_ADDR << 32 | SSPP_SRC_FORMAT
///   Confirms the fetch address and pixel format survived the commit
///   (0 => the block was reset/never latched).
/// diag3 = LM0 OUT_SIZE << 32 | LM0 blend-stage0 OP
///   The mixer's own view: output size and whether stage 0 is actually
///   blending the pipe in rather than emitting border colour (black).
/// DSI-side readback while the DPU is supposedly streaming video.
///
/// The single most informative bit here is STATUS0's
/// VIDEO_MODE_ENGINE_BUSY (bit3, per dsi.xml). If the DSI host is
/// genuinely transmitting a video stream it is ~always asserted; if it
/// reads 0 while INTF1's frame counter is advancing, then the DPU is
/// clocking out timing into a DSI host that is not actually sending
/// anything, and the black panel is explained without any of the
/// SSPP/LM/DSC config being at fault (all of which read back correct).
///
/// diag5 = DSI0 CTRL << 32 | DSI0 STATUS0
///   CTRL confirms the command->video mode switch actually stuck
///   (VID_MODE_EN bit1 set, CMD_MODE_EN bit2 clear).
/// diag6 = DSI0 FIFO_STATUS << 32 | DSI1 STATUS0
///   FIFO_STATUS shows video-path underflow (VIDEO_MDP_FIFO_UNDERFLOW
///   bit3 / OVERFLOW bit0) -- i.e. the DSI host starving or drowning
///   on pixel data from the DPU, distinct from the command-DMA FIFO
///   bits that cracked the AXI clock bug. DSI1's STATUS0 checks the
///   slave half of the bonded link is in the same state as the master.
export fn sheng_mdss_dsi_video_readback1(dsi0_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_CTRL)) << 32) |
        @as(i64, mmioRead32(dsi0_base, DSI_STATUS0));
}
export fn sheng_mdss_dsi_video_readback2(dsi0_base: usize, dsi1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_FIFO_STATUS)) << 32) |
        @as(i64, mmioRead32(dsi1_base, DSI_STATUS0));
}

/// DSC ENCODER STATUS (SPEC.md task #5 log). dpu_hw_dsc_1_2.c names
/// these as read-only status, not config -- so there is nothing to
/// write, but they are a direct window into whether the DSC encoder is
/// actually RUNNING, which no other instrument here provides.
///
/// Live, working Linux on this exact panel reads:
///   ENC_GENERAL_STATUS (0x04) = 0x00000003
///   ENC_HSLICE_STATUS  (0x08) = 0x00140000
///   ENC_OUT_STATUS     (0x0C) = 0x002E0000
///   ENC_INT_STAT       (0x10) = 0x000007B0
///
/// This matters because the panel is DSC-mandatory: the DSI test
/// pattern generator injects pixels DOWNSTREAM of these encoders, so it
/// can never produce a decodable stream here and both TPG results were
/// uninformative. The encoder's own status is the instrument that TPG
/// could not be.
///
///   all zero -> the DSC encoder never ran. Everything upstream can be
///     bit-perfect and nothing decodable ever reaches the panel, which
///     fits every observation so far.
///   matching live -> the encoder is producing output, and the fault is
///     downstream of it (INTF/DSI/panel).
export fn sheng_mdss_dsc_status1(dpu_base: usize) callconv(.c) i64 {
    const enc0 = dpu_base + 0x80000 + 0x100;
    return (@as(i64, mmioRead32(enc0, 0x04)) << 32) | @as(i64, mmioRead32(enc0, 0x08));
}
export fn sheng_mdss_dsc_status2(dpu_base: usize) callconv(.c) i64 {
    const enc0 = dpu_base + 0x80000 + 0x100;
    return (@as(i64, mmioRead32(enc0, 0x0c)) << 32) | @as(i64, mmioRead32(enc0, 0x10));
}

export fn sheng_mdss_dpu_readback1(dpu_base: usize) callconv(.c) i64 {
    const ctl_base = dpu_base + 0x15000;
    return (@as(i64, mmioRead32(ctl_base, CTL_FLUSH)) << 32) |
        @as(i64, mmioRead32(ctl_base, CTL_START));
}
export fn sheng_mdss_dpu_readback2(dpu_base: usize) callconv(.c) i64 {
    const sspp_base = dpu_base + 0x24000;
    return (@as(i64, mmioRead32(sspp_base, SSPP_SRC0_ADDR)) << 32) |
        @as(i64, mmioRead32(sspp_base, SSPP_SRC_FORMAT));
}
export fn sheng_mdss_dpu_readback3(dpu_base: usize) callconv(.c) i64 {
    const lm0_base = dpu_base + 0x44000;
    return (@as(i64, mmioRead32(lm0_base, LM_OUT_SIZE)) << 32) |
        @as(i64, mmioRead32(lm0_base, LM_STAGE0_OFFSET + LM_BLEND0_OP));
}
/// diag4 = CTL_LAYER0 << 32 | CTL_LAYER_EXT2_1 -- the actual routing
/// of the SSPP rects into the two mixers, read back from hardware.
export fn sheng_mdss_dpu_readback4(dpu_base: usize) callconv(.c) i64 {
    const ctl_base = dpu_base + 0x15000;
    return (@as(i64, mmioRead32(ctl_base, CTL_LAYER0)) << 32) |
        @as(i64, mmioRead32(ctl_base, CTL_LAYER_EXT2_1));
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

    // CROSS-VERIFIED AGAINST LIVE HARDWARE (SPEC.md task #5 log): this
    // interface runs a WIDENED databus -- live INTF_CONFIG2 has
    // DATABUS_WIDEN (bit0) set, and live DISPLAY_DATA_HCTL ends at 301
    // rather than 555, i.e. a data width of 254 == width/2. A widened
    // bus carries 2 pixels per pclk, halving the data-phase width.
    // This code previously asserted "our wide_bus_en is false" and
    // programmed the full width, telling INTF to expect twice as many
    // data beats per line as the DSC engine actually emits.
    const data_width = width / 2;
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
    // Live reads 0 here; 0x3 is kept deliberately because this register
    // only enables the frame/line counters this driver uses for its own
    // scanout diagnostics (sheng.f1a/f1b) and has no effect on output.
    mmioWrite32(intf_base, INTF_FRAME_LINE_COUNT_EN, 0x3);
    mmioWrite32(intf_base, INTF_CONFIG, INTF_CONFIG_LIVE);
    mmioWrite32(intf_base, INTF_PANEL_FORMAT, INTF_PANEL_FORMAT_RGB888);

    // compression_en && !wide_bus_en -> DATA_HCTL_EN would normally be
    // skipped in 1ppc+compression per the kernel comment, but our
    // wide_bus_en is false and compression_en is true, so per the exact
    // condition `!(compression_en && !wide_bus_en)` DATA_HCTL_EN stays
    // OFF here (both terms true -> negation false).
    mmioWrite32(intf_base, INTF_CONFIG2, INTF_CONFIG2_LIVE);
    mmioWrite32(intf_base, INTF_DISPLAY_DATA_HCTL, display_data_hctl);
    mmioWrite32(intf_base, INTF_ACTIVE_DATA_HCTL, 0);
}

// ===========================================================================
// SELF-VERIFICATION AGAINST LIVE-HARDWARE REFERENCE (SPEC.md task #5 log)
//
// Roughly two dozen individually-plausible register values in this driver
// turned out to be wrong, each found by dumping Linux's own registers via
// devmem while DRM drove this exact panel and diffing. Rather than keep
// discovering those one boot at a time, this table holds every reference
// value captured so far and checks the WHOLE pipeline in one shot, after
// dpu_start() has run and committed.
//
// Every entry is a value read from working silicon in the same 144Hz DSC
// bonded-DSI mode this driver targets (verified: INTF timing registers
// match ours bit-for-bit, so Linux was in the identical mode).
//
// Returns a bitmask: bit N set == entry N does NOT hold its reference
// value. 0 means the entire programmed pipeline matches working hardware,
// which would prove the remaining fault is NOT a register-content problem
// and redirect the search entirely.
// ===========================================================================

const VerifyEntry = struct {
    block: u8, // 0=dsi0, 1=dpu-absolute-offset
    off: usize,
    expect: u32,
};

// block 1 offsets are relative to dpu_base.
const verify_table = [_]VerifyEntry{
    .{ .block = 0, .off = 0x000, .expect = 0x000001F3 }, // DSI CTRL
    .{ .block = 0, .off = 0x00c, .expect = 0x02009230 }, // DSI VID_CFG0
    .{ .block = 0, .off = 0x020, .expect = 0x022C0030 }, // DSI ACTIVE_H
    .{ .block = 0, .off = 0x024, .expect = 0x087C008C }, // DSI ACTIVE_V
    .{ .block = 0, .off = 0x028, .expect = 0x08950272 }, // DSI TOTAL
    .{ .block = 0, .off = 0x038, .expect = 0x14000000 }, // DSI CMD_DMA_CTRL
    .{ .block = 0, .off = 0x080, .expect = 0x80001004 }, // DSI TRIG_CTRL
    .{ .block = 0, .off = 0x0a8, .expect = 0x01000000 }, // DSI LANE_CTRL
    .{ .block = 0, .off = 0x0ac, .expect = 0x00000000 }, // DSI LANE_SWAP_CTRL
    .{ .block = 0, .off = 0x118, .expect = 0x0000023F }, // DSI CLK_CTRL
    .{ .block = 0, .off = 0x29c, .expect = 0x05F40B01 }, // DSI VIDEO_COMPRESSION
    .{ .block = 1, .off = 0x15000, .expect = 0x01080000 }, // CTL_LAYER0
    .{ .block = 1, .off = 0x15004, .expect = 0x01080000 }, // CTL_LAYER1
    .{ .block = 1, .off = 0x15070, .expect = 0x00000200 }, // CTL_LAYER_EXT2_0
    .{ .block = 1, .off = 0x15074, .expect = 0x00000200 }, // CTL_LAYER_EXT2_1
    .{ .block = 1, .off = 0x15014, .expect = 0xF0000000 }, // CTL_TOP
    .{ .block = 1, .off = 0x150e8, .expect = 0x00000003 }, // CTL_DSC_ACTIVE
    .{ .block = 1, .off = 0x150f4, .expect = 0x00000006 }, // CTL_INTF_ACTIVE
    .{ .block = 1, .off = 0x15134, .expect = 0x00000002 }, // CTL_INTF_MASTER
    .{ .block = 1, .off = 0x150fc, .expect = 0x00000001 }, // CTL_FETCH_PIPE_ACTIVE
    .{ .block = 1, .off = 0x24000, .expect = 0x07F005F4 }, // SSPP SRC_SIZE
    .{ .block = 1, .off = 0x2400c, .expect = 0x07F005F4 }, // SSPP OUT_SIZE
    .{ .block = 1, .off = 0x24024, .expect = 0x30003000 }, // SSPP YSTRIDE0
    .{ .block = 1, .off = 0x24030, .expect = 0x000236FF }, // SSPP SRC_FORMAT
    .{ .block = 1, .off = 0x24034, .expect = 0x03020001 }, // SSPP UNPACK
    .{ .block = 1, .off = 0x24038, .expect = 0x80000000 }, // SSPP OP_MODE
    .{ .block = 1, .off = 0x24170, .expect = 0x00000003 }, // SSPP MULTIRECT_OPMODE
    .{ .block = 1, .off = 0x2416c, .expect = 0x07F005F4 }, // SSPP SRC_SIZE_REC1
    .{ .block = 1, .off = 0x24164, .expect = 0x000005F4 }, // SSPP OUT_XY_REC1
    .{ .block = 1, .off = 0x44000, .expect = 0x00000002 }, // LM0 OP_MODE
    .{ .block = 1, .off = 0x44004, .expect = 0x07F005F4 }, // LM0 OUT_SIZE
    .{ .block = 1, .off = 0x44020, .expect = 0x00000100 }, // LM0 BLEND0_OP
    .{ .block = 1, .off = 0x44024, .expect = 0x00FF0000 }, // LM0 CONST_ALPHA
    .{ .block = 1, .off = 0x45000, .expect = 0x80000002 }, // LM1 OP_MODE
    .{ .block = 1, .off = 0x35004, .expect = 0x80800000 }, // INTF1 CONFIG
    .{ .block = 1, .off = 0x35060, .expect = 0x00001011 }, // INTF1 CONFIG2
    .{ .block = 1, .off = 0x35008, .expect = 0x02730002 }, // INTF1 HSYNC_CTL
    .{ .block = 1, .off = 0x3503c, .expect = 0x022B0030 }, // INTF1 DISPLAY_HCTL
    .{ .block = 1, .off = 0x35064, .expect = 0x012D0030 }, // INTF1 DISPLAY_DATA_HCTL
    .{ .block = 1, .off = 0x35090, .expect = 0x00002100 }, // INTF1 PANEL_FORMAT
    .{ .block = 1, .off = 0x3525c, .expect = 0x000F0000 }, // INTF1 MUX
    .{ .block = 1, .off = 0x80000, .expect = 0x00000101 }, // DSC CMN_MAIN_CNF
    .{ .block = 1, .off = 0x80130, .expect = 0x10120258 }, // DSC0 MAIN_CONF
    .{ .block = 1, .off = 0x80134, .expect = 0x07F00BE8 }, // DSC0 PICTURE_SIZE
    .{ .block = 1, .off = 0x80f04, .expect = 0x00001801 }, // DSC0 CFG
    .{ .block = 1, .off = 0x690a0, .expect = 0x00000000 }, // PP0 DSC_MODE
    // Added to confirm the DSC CTL sub-block writes actually LAND --
    // writing them produced byte-identical encoder status, which is
    // only meaningful if the writes stick. See DSC_CLK_CTRL's comment.
    .{ .block = 1, .off = 0x80f08, .expect = 0x0002C688 }, // DSC0 DATA_IN_SWAP
    .{ .block = 1, .off = 0x80f0c, .expect = 0xC0000000 }, // DSC0 CLK_CTRL
    .{ .block = 1, .off = 0x80f88, .expect = 0x0002C688 }, // DSC1 DATA_IN_SWAP
    .{ .block = 1, .off = 0x80f8c, .expect = 0xC0000000 }, // DSC1 CLK_CTRL
};

var g_verify_mask: u64 = 0;


/// FULL DSI0 REGISTER-SPACE AUDIT (SPEC.md task #5 log).
///
/// The 46-entry verify table covers registers this driver chose to
/// write. That is a self-selected sample: it cannot find a register
/// that matters and was never written at all -- which is exactly how
/// CTL_FETCH_PIPE_ACTIVE and DSC_CLK_CTRL were missed for so long.
///
/// This table is built the other way round: a python3 mmap dump of the
/// ENTIRE live DSI0 register space (0x000-0x300) taken while Linux was
/// driving this panel, minus the read-only status registers
/// (STATUS0/FIFO_STATUS/DLN0_PHY_ERR/LANE_STATUS/CLK_STATUS/VERSION)
/// and the genuinely dynamic ones (DMA_BASE/DMA_LEN/TRIG_DMA). 28 of
/// these hold non-zero values on working silicon and are never written
/// by this driver; several are not even modelled in mainline's dsi.xml,
/// so they are hardware reset defaults that our own mdssCoreBcrReset()
/// may well be clearing without restoring.
///
/// Offsets are LOGICAL (live physical minus the 4-byte DSI 6G shift).
/// Returns a bitmask: bit N set == entry N differs from live.
const DsiAuditEntry = struct { off: usize, expect: u32 };
const dsi_audit_table = [_]DsiAuditEntry{
    .{ .off = 0x010, .expect = 0x31211101 },
    .{ .off = 0x014, .expect = 0x3e2e1e0e },
    .{ .off = 0x018, .expect = 0x00001900 },
    .{ .off = 0x02c, .expect = 0x00020000 },
    .{ .off = 0x034, .expect = 0x00020000 },
    .{ .off = 0x03c, .expect = 0x06100006 },
    .{ .off = 0x040, .expect = 0x00003c2c },
    .{ .off = 0x050, .expect = 0x00000900 },
    .{ .off = 0x078, .expect = 0x22211211 },
    .{ .off = 0x07c, .expect = 0x001c1a02 },
    .{ .off = 0x0b4, .expect = 0xffffffff },
    .{ .off = 0x0b8, .expect = 0x0000ffff },
    .{ .off = 0x0bc, .expect = 0x00000001 },
    .{ .off = 0x0c0, .expect = 0x00001a23 },
    .{ .off = 0x0c4, .expect = 0x010f0f08 },
    .{ .off = 0x0c8, .expect = 0x00000001 },
    .{ .off = 0x108, .expect = 0x13ff3be0 },
    .{ .off = 0x10c, .expect = 0xaa21aa00 },
    .{ .off = 0x130, .expect = 0xffffffff },
    .{ .off = 0x134, .expect = 0xffffffff },
    .{ .off = 0x138, .expect = 0xffffffff },
    .{ .off = 0x13c, .expect = 0xffffffff },
    .{ .off = 0x144, .expect = 0x0000ffff },
    .{ .off = 0x148, .expect = 0x0000ffff },
    .{ .off = 0x14c, .expect = 0x0000ffff },
    .{ .off = 0x150, .expect = 0x0000ffff },
    .{ .off = 0x158, .expect = 0x00000004 },
    .{ .off = 0x1a4, .expect = 0x00ff0000 },
    .{ .off = 0x1a8, .expect = 0x00400040 },
    .{ .off = 0x1ac, .expect = 0x000000ff },
    .{ .off = 0x1b0, .expect = 0x00000024 },
    .{ .off = 0x1b4, .expect = 0x00000006 },
    .{ .off = 0x1c4, .expect = 0xffffffff },
    .{ .off = 0x1cc, .expect = 0x00290000 },
    .{ .off = 0x1fc, .expect = 0x80000000 },
    .{ .off = 0x2a4, .expect = 0x39003900 },
    .{ .off = 0x2b4, .expect = 0x3e2e0600 },
    .{ .off = 0x2b8, .expect = 0x0000f000 },
    .{ .off = 0x2c4, .expect = 0x00000004 },
};

/// REAL GAP FOUND (SPEC.md task #5 log): the MDSS wrapper's UBWC
/// configuration block. msm_mdss_enable() writes all three of these on
/// every MDSS bring-up, BEFORE any child DSI/DPU device is touched:
///
///   UBWC_STATIC          (0x144) = 0x0000103E
///   UBWC_CTRL_2          (0x150) = 0x00000002
///   UBWC_PREDICTION_MODE (0x154) = 0x00000001
///
/// This driver never wrote any of them, and mdssCoreBcrReset() resets
/// the MDSS core -- so whatever ABL left is destroyed and never
/// restored, leaving the UBWC decoder block that sits in the MDSS
/// memory data path at zero.
///
/// Same shape as this session's other two real finds
/// (GCC_DISP_HF_AXI_CLK ordering, DSC_CLK_CTRL): top-level block state
/// that appears in no per-block register diff, because it lives above
/// the DSI/DPU register spaces that have all been audited clean
/// (sheng.verify = 0, sheng.dsiaudit = 0).
///
/// Values are Linux's own live registers on this panel.
const MDSS_UBWC_STATIC: usize = 0x144;
const MDSS_UBWC_CTRL_2: usize = 0x150;
const MDSS_UBWC_PREDICTION_MODE: usize = 0x154;
const MDSS_UBWC_STATIC_VALUE: u32 = 0x0000103E;
const MDSS_UBWC_CTRL_2_VALUE: u32 = 0x00000002;
const MDSS_UBWC_PREDICTION_MODE_VALUE: u32 = 0x00000001;

/// The three MDSS wrapper registers that hold non-zero values on live
/// silicon but appear NOWHERE in mainline's mdss.xml, so Linux never
/// writes them: they are ABL/hardware state. Our mdssCoreBcrReset()
/// resets the MDSS core, which may clear them without restoring -- the
/// same failure shape as the UBWC block above, which WAS a real gap.
/// Never checked against our own values until now.
///   0x054 = 0x40000002
///   0x068 = 0x00038044
///   0x084 = 0x0000010E
/// Returns a bitmask: bit0/1/2 set == that register differs from live.
export fn sheng_mdss_wrapper_audit(mdss_base: usize) callconv(.c) u32 {
    var mask: u32 = 0;
    if (mmioRead32(mdss_base, 0x054) != 0x40000002) mask |= 1 << 0;
    if (mmioRead32(mdss_base, 0x068) != 0x00038044) mask |= 1 << 1;
    if (mmioRead32(mdss_base, 0x084) != 0x0000010E) mask |= 1 << 2;
    return mask;
}

export fn sheng_mdss_ubwc_init(mdss_base: usize) callconv(.c) void {
    mmioWrite32(mdss_base, MDSS_UBWC_STATIC, MDSS_UBWC_STATIC_VALUE);
    mmioWrite32(mdss_base, MDSS_UBWC_CTRL_2, MDSS_UBWC_CTRL_2_VALUE);
    mmioWrite32(mdss_base, MDSS_UBWC_PREDICTION_MODE, MDSS_UBWC_PREDICTION_MODE_VALUE);
}

/// WHOLESALE STATE CAPTURE (SPEC.md task #5 log).
///
/// Block-by-block comparison with hand-picked offsets has now missed
/// three real bugs (CTL_FETCH_PIPE_ACTIVE, DSC_CLK_CTRL, the MDSS UBWC
/// block) because a self-selected offset list cannot find a register
/// nobody thought to look at. This copies the ENTIRE register state of
/// every block in the display path into a scratch DRAM region that
/// survives the handoff into Linux (same trick as the ktz8866 status
/// buffer at CONFIG_PRE_CON_BUF_ADDR + 0x3400, which is readable from
/// Linux via devmem). The identical ranges can then be dumped from the
/// live working kernel and diffed wholesale, in one boot, with no
/// guessing about which register might matter.
///
/// Layout at dst: a sequence of blocks, each [base:u32][len:u32] then
/// len/4 u32 values, terminated by base==0.
const CaptureRange = struct { base: usize, len: usize };
const capture_ranges = [_]CaptureRange{
    // REDUCED SET (SPEC.md task #5 log): the full 16-block list
    // reproducibly killed the boot before backlight -- almost certainly
    // a stalled AHB read on a block we never touch, which wedges the
    // CPU with no abort. Only blocks this driver ALREADY reads on every
    // boot are listed here, with lengths bounded by registers actually
    // observed rather than round numbers. Expand one block at a time.
    .{ .base = 0x0ae94000, .len = 0x300 }, // DSI0 host (read every boot by the audit)
    .{ .base = 0x0ae16000, .len = 0x140 }, // DPU CTL_0 (read by dpu_readback1/4)
    .{ .base = 0x0ae25000, .len = 0x190 }, // SSPP DMA0 (read by dpu_readback2)
    .{ .base = 0x0ae45000, .len = 0x40 }, // LM0 (read by dpu_readback3)
    .{ .base = 0x0ae46000, .len = 0x40 }, // LM1 (written every boot)
    .{ .base = 0x0ae81000, .len = 0x400 }, // DSC enc0/enc1 (read by dsc_status)
    .{ .base = 0x0ae81f00, .len = 0x90 }, // DSC ctl (written every boot)
};

export fn sheng_mdss_capture_state(dst: usize) callconv(.c) void {
    var out: [*]volatile u32 = @ptrFromInt(dst);
    var w: usize = 0;
    for (capture_ranges) |r| {
        out[w] = @truncate(r.base);
        w += 1;
        out[w] = @truncate(r.len);
        w += 1;
        var o: usize = 0;
        while (o < r.len) : (o += 4) {
            out[w] = mmioRead32(r.base, o);
            w += 1;
        }
    }
    out[w] = 0;
    out[w + 1] = 0;
}

export fn sheng_mdss_dsi_audit(dsi0_base: usize) callconv(.c) i64 {
    var mask: u64 = 0;
    for (dsi_audit_table, 0..) |e, i| {
        if (mmioRead32(dsi0_base, e.off) != e.expect) mask |= (@as(u64, 1) << @intCast(i));
    }
    return @bitCast(mask);
}

/// Same audit applied to DSI1, the SLAVE host (SPEC.md task #5 log).
///
/// DSI0 has been audited exhaustively (39/39 match live) but DSI1 was
/// only ever spot-checked -- ten registers read identical to DSI0 on
/// live hardware, and we assumed the rest followed because both hosts
/// go through the same code path. "Same code path" is an assumption,
/// not a measurement: dsiHostBringUp() and dsiHostSwitchToVideoMode()
/// take a base address, and anything that writes only dsi0_base by
/// mistake would leave the slave half wrong while every DSI0 reading
/// stayed perfect.
///
/// On a bonded dual-DSI panel the slave carries half the picture, so a
/// misconfigured DSI1 is a plausible cause of a black panel with a
/// flawless master. Live DSI1 reads identical to DSI0 for every
/// register checked, so the same expected-value table applies.
///
/// NOTE: these are explicit offsets from dsi.xml, NOT a range scan.
/// Blind range reads of this hardware wedge the bus -- confirmed by
/// reading register ranges over /dev/mem on the live device, which
/// reboots it outright, and by sheng_mdss_capture_state() killing the
/// U-Boot boot twice for the same reason.
export fn sheng_mdss_dsi1_audit(dsi1_base: usize) callconv(.c) i64 {
    var mask: u64 = 0;
    for (dsi_audit_table, 0..) |e, i| {
        if (mmioRead32(dsi1_base, e.off) != e.expect) mask |= (@as(u64, 1) << @intCast(i));
    }
    return @bitCast(mask);
}

export fn sheng_mdss_verify_pipeline(dpu_base: usize, dsi0_base: usize) callconv(.c) i64 {
    var mask: u64 = 0;
    for (verify_table, 0..) |e, i| {
        const base = if (e.block == 0) dsi0_base else dpu_base;
        const off = if (e.block == 0) e.off else e.off;
        const got = mmioRead32(base, off);
        if (got != e.expect) mask |= (@as(u64, 1) << @intCast(i));
    }
    g_verify_mask = mask;
    return @bitCast(mask);
}
