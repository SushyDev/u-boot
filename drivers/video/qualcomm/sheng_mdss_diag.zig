// SPDX-License-Identifier: GPL-2.0+
//
// Bring-up diagnostics for the sheng MDSS driver: register sweeps and
// audits that diff live hardware against a known-good reference.
//
// Built ONLY when CONFIG_VIDEO_SHENG_MDSS_DEBUG=y. Everything here is
// reference data and comparison loops -- roughly 20KB of .rodata that a
// normal boot has no use for, on a board whose image size is a real
// budget.
//
// Reference values were captured from this device while a working Linux
// drove the panel, at explicit offsets only. NEVER sweep a blind
// address range: reading an unclocked MDSS sub-block wedges the AHB bus
// and recovery is fastboot.
//
// Constants are duplicated from sheng_mdss_hw.zig rather than imported.
// Zig compiles each of these to its own object, and importing that file
// would emit its exports here too.

fn mmioRead32(base: usize, offset: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(base + offset);
    return ptr.*;
}


const BYTE0_DIV_CLK_SRC: usize = 0x8120;
const BYTE1_DIV_CLK_SRC: usize = 0x813c;
const CMN_CLK_CFG0: usize = 0x010;
const CMN_CLK_CFG1: usize = 0x014;
const CMN_PHY_STATUS: usize = 0x140;
const CTL_DSC_ACTIVE: usize = 0x0e8;
const CTL_FETCH_PIPE_ACTIVE: usize = 0x0fc;
const CTL_INTF_ACTIVE: usize = 0x0f4;
const CTL_INTF_MASTER: usize = 0x134;
const CTL_LAYER0: usize = 0x000; // CTL_LAYER(LM_0): (lm-LM_0)*4
const CTL_LAYER1: usize = 0x004; // CTL_LAYER(LM_1)
const CTL_LAYER_EXT2_0: usize = 0x070; // CTL_LAYER_EXT2(LM_0): 0x70+(lm-LM_0)*4
const CTL_LAYER_EXT2_1: usize = 0x074; // CTL_LAYER_EXT2(LM_1)
const CTL_TOP: usize = 0x014;
const DSC_CLK_CTRL: usize = 0x0c;
const DSI_VID_CFG1: usize = 0x01c;
const INTF_PANEL_FORMAT_RGB888: u32 = (0x21 << 8) | (0x3) | (0x3 << 2) | (0x3 << 4);
const PHY_AUDIT_CLK_CFG1_BIT: u6 = 63;
const PLL_COMMON_STATUS_ONE: usize = 0x1b0;
const PLL_PLL_OUTDIV_RATE: usize = 0x154;
const VBIF_QOS_LVL_REMAP_BASE: usize = 0x590;
const VBIF_QOS_REMAP_BASE: usize = 0x550;
const VBIF_XIN_MEMTYPE_0: usize = 0x160;
const VBIF_XIN_MEMTYPE_1: usize = 0x164;
const VBIF_XIN_MEMTYPE_VALUE: u32 = 0x33333333;


const vbif_qos_remap_values = [8]u32{
    0x00000030, 0x11111131, 0x22222242, 0x33333343,
    0x44444454, 0x55555555, 0x66666666, 0x77777767,
};

/// Bitmask audit of the VBIF block against the traced/live values.
export fn sheng_mdss_vbif_audit(vbif_base: usize) callconv(.c) i64 {
    var mask: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (mmioRead32(vbif_base, VBIF_QOS_REMAP_BASE + i * 8) != vbif_qos_remap_values[i])
            mask |= (@as(u64, 1) << @intCast(i));
        if (mmioRead32(vbif_base, VBIF_QOS_LVL_REMAP_BASE + i * 8) != vbif_qos_remap_values[i])
            mask |= (@as(u64, 1) << @intCast(i + 8));
    }
    if (mmioRead32(vbif_base, VBIF_XIN_MEMTYPE_0) != VBIF_XIN_MEMTYPE_VALUE) mask |= 1 << 16;
    if (mmioRead32(vbif_base, VBIF_XIN_MEMTYPE_1) != VBIF_XIN_MEMTYPE_VALUE) mask |= 1 << 17;
    return @bitCast(mask);
}

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
    // DSI LANE_CTRL (0x0a8) entry removed: the kernel never writes it, so
    // any 'live' expectation for it is just our own prior write read back.
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
    // INTF1 PANEL_FORMAT: we WRITE 0x213F (matching the kernel, see
    // INTF_PANEL_FORMAT_RGB888) but the register READS BACK 0x2100 -- the
    // three 2-bit colour-depth fields are write-only. Measured: setting
    // this entry to 0x213F lit verify bit39 while the neighbouring
    // PROG_FETCH_START entry stayed clear, proving the write itself lands.
    // This is also why the original live capture of this register said
    // 0x2100 and hid the missing field in the first place.
    .{ .block = 1, .off = 0x35090, .expect = 0x00002100 }, // INTF1 PANEL_FORMAT (readback masks bit-depth)
    .{ .block = 1, .off = 0x35170, .expect = 0x0014CA28 }, // INTF1 PROG_FETCH_START
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
    .{ .off = 0x010, .expect = 0x31211101 }, // undocumented; POR value, we no longer write it
    .{ .off = 0x01c, .expect = 0x00000000 }, // VID_CFG1 -- real offset, see DSI_VID_CFG1
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

/// FULL DSI HOST SWEEP (SPEC.md task #5 log).
///
/// Last unswept block. The PHY is now exhaustively eliminated: all 124 CMN
/// registers matched exactly, and of 412 lane+PLL registers only three
/// differed -- 0x6c0/0x6c4 and one neighbour, which read DIFFERENT values
/// on two separate reads of the same rendering Linux, i.e. dynamic PLL
/// calibration status rather than configuration.
///
/// dsi_audit_table covers 39 offsets chosen from a previous dump. This
/// sweeps the ENTIRE host space 0x000-0x2fc as captured from this device
/// while Linux was rendering, minus the registers that are genuinely
/// dynamic or per-transfer: CTRL, STATUS0, FIFO_STATUS, DMA_BASE/LEN,
/// ACK_ERR, RDBK_DATA*, TRIG_DMA, LANE_STATUS, DLN0_PHY_ERR,
/// TIMEOUT_STATUS, INTR_CTRL, RDBK_DATA_CTRL.
///
/// Same encoding: (first mismatching offset << 32) | count.
const dsi_sweep_table = [_]DsiAuditEntry{
    .{ .off = 0x00c, .expect = 0x02009230 },
    .{ .off = 0x010, .expect = 0x31211101 },
    .{ .off = 0x014, .expect = 0x3E2E1E0E },
    .{ .off = 0x018, .expect = 0x00001900 },
    .{ .off = 0x01c, .expect = 0x00000000 },
    .{ .off = 0x020, .expect = 0x022C0030 },
    .{ .off = 0x024, .expect = 0x087C008C },
    .{ .off = 0x028, .expect = 0x08950272 },
    .{ .off = 0x02c, .expect = 0x00020000 },
    .{ .off = 0x030, .expect = 0x00000000 },
    .{ .off = 0x034, .expect = 0x00020000 },
    .{ .off = 0x038, .expect = 0x14000000 },
    .{ .off = 0x03c, .expect = 0x06100006 },
    .{ .off = 0x040, .expect = 0x00003C2C },
    .{ .off = 0x04c, .expect = 0x00000000 },
    .{ .off = 0x050, .expect = 0x00000900 },
    .{ .off = 0x054, .expect = 0x00000000 },
    .{ .off = 0x058, .expect = 0x00000000 },
    .{ .off = 0x05c, .expect = 0x00000000 },
    .{ .off = 0x060, .expect = 0x00000000 },
    .{ .off = 0x078, .expect = 0x22211211 },
    .{ .off = 0x07c, .expect = 0x001C1A02 },
    .{ .off = 0x080, .expect = 0x80001004 },
    .{ .off = 0x084, .expect = 0x00000000 },
    .{ .off = 0x088, .expect = 0x00000000 },
    .{ .off = 0x090, .expect = 0x00000000 },
    .{ .off = 0x094, .expect = 0x00000000 },
    .{ .off = 0x098, .expect = 0x00000000 },
    .{ .off = 0x09c, .expect = 0x00000000 },
    .{ .off = 0x0a0, .expect = 0x00000000 },
    .{ .off = 0x0a8, .expect = 0x01000000 },
    .{ .off = 0x0ac, .expect = 0x00000000 },
    .{ .off = 0x0b4, .expect = 0xFFFFFFFF },
    .{ .off = 0x0b8, .expect = 0x0000FFFF },
    .{ .off = 0x0c0, .expect = 0x00001A23 },
    .{ .off = 0x0c4, .expect = 0x010F0F08 },
    .{ .off = 0x0c8, .expect = 0x00000001 },
    .{ .off = 0x0cc, .expect = 0x00000000 },
    .{ .off = 0x0d0, .expect = 0x00000000 },
    .{ .off = 0x0d4, .expect = 0x00000000 },
    .{ .off = 0x0d8, .expect = 0x00000000 },
    .{ .off = 0x0dc, .expect = 0x00000000 },
    .{ .off = 0x0e0, .expect = 0x00000000 },
    .{ .off = 0x0e4, .expect = 0x00000000 },
    .{ .off = 0x0e8, .expect = 0x00000000 },
    .{ .off = 0x0ec, .expect = 0x00000000 },
    .{ .off = 0x0f0, .expect = 0x00000000 },
    .{ .off = 0x0f4, .expect = 0x00000000 },
    .{ .off = 0x0f8, .expect = 0x00000000 },
    .{ .off = 0x0fc, .expect = 0x00000000 },
    .{ .off = 0x100, .expect = 0x00000000 },
    .{ .off = 0x104, .expect = 0x00000000 },
    .{ .off = 0x108, .expect = 0x13FF3BE0 },
    .{ .off = 0x110, .expect = 0x00000000 },
    .{ .off = 0x114, .expect = 0x00000000 },
    .{ .off = 0x118, .expect = 0x0000023F },
    .{ .off = 0x11c, .expect = 0x00804343 },
    .{ .off = 0x120, .expect = 0x00000000 },
    .{ .off = 0x124, .expect = 0x00000000 },
    .{ .off = 0x128, .expect = 0x00000000 },
    .{ .off = 0x12c, .expect = 0x00000000 },
    .{ .off = 0x130, .expect = 0xFFFFFFFF },
    .{ .off = 0x134, .expect = 0xFFFFFFFF },
    .{ .off = 0x138, .expect = 0xFFFFFFFF },
    .{ .off = 0x13c, .expect = 0xFFFFFFFF },
    .{ .off = 0x140, .expect = 0x00000000 },
    .{ .off = 0x144, .expect = 0x0000FFFF },
    .{ .off = 0x148, .expect = 0x0000FFFF },
    .{ .off = 0x14c, .expect = 0x0000FFFF },
    .{ .off = 0x150, .expect = 0x0000FFFF },
    .{ .off = 0x154, .expect = 0x00000000 },
    .{ .off = 0x158, .expect = 0x00000004 },
    .{ .off = 0x15c, .expect = 0x00000000 },
    .{ .off = 0x160, .expect = 0x00000000 },
    .{ .off = 0x164, .expect = 0x00000000 },
    .{ .off = 0x168, .expect = 0x00000000 },
    .{ .off = 0x16c, .expect = 0x00000000 },
    .{ .off = 0x170, .expect = 0x00000000 },
    .{ .off = 0x174, .expect = 0x00000000 },
    .{ .off = 0x178, .expect = 0x00000000 },
    .{ .off = 0x17c, .expect = 0x00000000 },
    .{ .off = 0x180, .expect = 0x00000000 },
    .{ .off = 0x184, .expect = 0x00000000 },
    .{ .off = 0x188, .expect = 0x00000000 },
    .{ .off = 0x18c, .expect = 0x00000000 },
    .{ .off = 0x190, .expect = 0x00000000 },
    .{ .off = 0x194, .expect = 0x00000000 },
    .{ .off = 0x198, .expect = 0x00000000 },
    .{ .off = 0x19c, .expect = 0x00000000 },
    .{ .off = 0x1a0, .expect = 0x00000001 },
    .{ .off = 0x1a4, .expect = 0x00FF0000 },
    .{ .off = 0x1a8, .expect = 0x00400040 },
    .{ .off = 0x1ac, .expect = 0x000000FF },
    .{ .off = 0x1b0, .expect = 0x00000024 },
    .{ .off = 0x1b4, .expect = 0x00000006 },
    .{ .off = 0x1b8, .expect = 0x00000000 },
    .{ .off = 0x1bc, .expect = 0x00000000 },
    .{ .off = 0x1c0, .expect = 0x00000000 },
    .{ .off = 0x1c4, .expect = 0xFFFFFFFF },
    .{ .off = 0x1c8, .expect = 0x00000000 },
    .{ .off = 0x1cc, .expect = 0x00290000 },
    .{ .off = 0x1d4, .expect = 0x00000000 },
    .{ .off = 0x1d8, .expect = 0x00000000 },
    .{ .off = 0x1dc, .expect = 0x00000000 },
    .{ .off = 0x1e0, .expect = 0x00000000 },
    .{ .off = 0x1e4, .expect = 0x00000000 },
    .{ .off = 0x1e8, .expect = 0x00000000 },
    .{ .off = 0x1ec, .expect = 0x00000000 },
    .{ .off = 0x1f0, .expect = 0x03000104 },
    .{ .off = 0x1f4, .expect = 0x00000000 },
    .{ .off = 0x1f8, .expect = 0x00000000 },
    .{ .off = 0x1fc, .expect = 0x80000000 },
    .{ .off = 0x200, .expect = 0x00000000 },
    .{ .off = 0x204, .expect = 0x00000000 },
    .{ .off = 0x208, .expect = 0x00000000 },
    .{ .off = 0x20c, .expect = 0x00000000 },
    .{ .off = 0x210, .expect = 0x00000000 },
    .{ .off = 0x214, .expect = 0x00000000 },
    .{ .off = 0x218, .expect = 0x00000000 },
    .{ .off = 0x21c, .expect = 0x00000000 },
    .{ .off = 0x220, .expect = 0x00000000 },
    .{ .off = 0x224, .expect = 0x00000000 },
    .{ .off = 0x228, .expect = 0x00000000 },
    .{ .off = 0x22c, .expect = 0x00000000 },
    .{ .off = 0x230, .expect = 0x00000000 },
    .{ .off = 0x234, .expect = 0x00000000 },
    .{ .off = 0x238, .expect = 0x00000000 },
    .{ .off = 0x23c, .expect = 0x00000000 },
    .{ .off = 0x240, .expect = 0x00000000 },
    .{ .off = 0x244, .expect = 0x00000000 },
    .{ .off = 0x248, .expect = 0x00000000 },
    .{ .off = 0x24c, .expect = 0x00000000 },
    .{ .off = 0x250, .expect = 0x00000000 },
    .{ .off = 0x254, .expect = 0x00000000 },
    .{ .off = 0x258, .expect = 0x00000000 },
    .{ .off = 0x25c, .expect = 0x00000000 },
    .{ .off = 0x260, .expect = 0x00000000 },
    .{ .off = 0x264, .expect = 0x00000000 },
    .{ .off = 0x268, .expect = 0x00000000 },
    .{ .off = 0x26c, .expect = 0x00000000 },
    .{ .off = 0x270, .expect = 0x00000000 },
    .{ .off = 0x274, .expect = 0x00000000 },
    .{ .off = 0x278, .expect = 0x00000000 },
    .{ .off = 0x27c, .expect = 0x00000000 },
    .{ .off = 0x280, .expect = 0x00000000 },
    .{ .off = 0x284, .expect = 0x00000000 },
    .{ .off = 0x288, .expect = 0x00000000 },
    .{ .off = 0x28c, .expect = 0x00000000 },
    .{ .off = 0x290, .expect = 0x00000000 },
    .{ .off = 0x294, .expect = 0x00000000 },
    .{ .off = 0x298, .expect = 0x00000000 },
    .{ .off = 0x29c, .expect = 0x05F40B01 },
    .{ .off = 0x2a0, .expect = 0x00000000 },
    .{ .off = 0x2a4, .expect = 0x39003900 },
    .{ .off = 0x2a8, .expect = 0x00000000 },
    .{ .off = 0x2ac, .expect = 0x00000000 },
    .{ .off = 0x2b0, .expect = 0x00000000 },
    .{ .off = 0x2b4, .expect = 0x3E2E0600 },
    .{ .off = 0x2b8, .expect = 0x0000F000 },
    .{ .off = 0x2bc, .expect = 0x00000000 },
    .{ .off = 0x2c0, .expect = 0x00000000 },
    .{ .off = 0x2c4, .expect = 0x00000004 },
    .{ .off = 0x2c8, .expect = 0x00000000 },
    .{ .off = 0x2cc, .expect = 0x00000000 },
    .{ .off = 0x2d0, .expect = 0x00000000 },
    .{ .off = 0x2d4, .expect = 0x00000000 },
    .{ .off = 0x2d8, .expect = 0x00000000 },
    .{ .off = 0x2dc, .expect = 0x00000000 },
    .{ .off = 0x2e0, .expect = 0x00000000 },
    .{ .off = 0x2e4, .expect = 0x00000000 },
    .{ .off = 0x2e8, .expect = 0x00000000 },
    .{ .off = 0x2ec, .expect = 0x00000000 },
    .{ .off = 0x2f0, .expect = 0x00000000 },
    .{ .off = 0x2f4, .expect = 0x00000000 },
    .{ .off = 0x2f8, .expect = 0x00000000 },
    .{ .off = 0x2fc, .expect = 0x0000FFFF },
};

export fn sheng_mdss_dsi_sweep(dsi_base: usize) callconv(.c) i64 {
    var count: u32 = 0;
    var first: u32 = 0xffff;
    for (dsi_sweep_table) |e| {
        if (mmioRead32(dsi_base, e.off) != e.expect) {
            if (first == 0xffff) first = @intCast(e.off);
            count += 1;
        }
    }
    return (@as(i64, first) << 32) | @as(i64, count);
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

// ===========================================================================
// DSI PHY AUDIT (SPEC.md task #5 log)
//
// Until now the PHY had NO automated verification at all -- 46 register
// writes with nothing checking them, while DSI0, DSI1 and the DPU each had
// tables. The "31/31 PHY registers match" claim carried in this project for
// a long time was a manual, self-selected comparison, and it only ever
// covered the CMN block below +0x200. The PLL sub-block at phy+0x500 --
// 29 registers, every one of them programmed by this driver -- had never
// been compared to anything.
//
// That is exactly the blind spot that hid CTL_FETCH_PIPE_ACTIVE, DSC_CLK_
// CTRL and the MDSS UBWC block: a self-selected offset list cannot find a
// register nobody thought to look at. It also hid the slave PLL being left
// entirely unconfigured (see sheng_mdss_dsi_phy_init()'s comment).
//
// Every value below was read off THIS device with devmem, explicit single
// offsets only (never a range scan -- those wedge this hardware's bus),
// while Linux was driving the panel in the same 144Hz DSC bonded mode.
//
// CLK_CFG1 (0x014) is the one genuinely master/slave-dependent entry:
// 0x30 on the master, 0x34 on the slave (BITCLK_SEL bit2 set).
//
// Returns a bitmask: bit N set == entry N differs from live silicon.
const PhyAuditEntry = struct { off: usize, expect: u32 };

const phy_audit_table = [_]PhyAuditEntry{
    // --- CMN block
    .{ .off = 0x010, .expect = 0x00000061 }, // CLK_CFG0 (bit_clk_div | pix_clk_div<<4)
    .{ .off = 0x018, .expect = 0x00000000 }, // GLBL_CTRL
    .{ .off = 0x01c, .expect = 0x00000001 }, // RBUF_CTRL
    .{ .off = 0x020, .expect = 0x00000044 }, // VREG_CTRL_0
    .{ .off = 0x024, .expect = 0x0000007F }, // CTRL_0
    .{ .off = 0x02c, .expect = 0x00000040 }, // CTRL_2 (full-rate dphy)
    .{ .off = 0x030, .expect = 0x00000004 }, // CTRL_3
    .{ .off = 0x034, .expect = 0x00000021 }, // LANE_CFG0
    .{ .off = 0x038, .expect = 0x00000084 }, // LANE_CFG1
    .{ .off = 0x03c, .expect = 0x00000001 }, // PLL_CNTRL -- 1 on BOTH phys
    .{ .off = 0x0a0, .expect = 0x0000001F }, // LANE_CTRL0
    .{ .off = 0x0ec, .expect = 0x00000088 }, // GLBL_HSTX_STR_CTRL_0
    .{ .off = 0x0f4, .expect = 0x0000003C }, // GLBL_RESCODE_OFFSET_TOP_CTRL
    .{ .off = 0x0f8, .expect = 0x00000038 }, // GLBL_RESCODE_OFFSET_BOT_CTRL
    .{ .off = 0x100, .expect = 0x00000055 }, // GLBL_LPTX_STR_CTRL
    .{ .off = 0x104, .expect = 0x00000000 }, // GLBL_PEMPH_CTRL_0
    .{ .off = 0x10c, .expect = 0x00000000 }, // GLBL_STR_SWI_CAL_SEL_CTRL
    .{ .off = 0x110, .expect = 0x00000019 }, // VREG_CTRL_1
    .{ .off = 0x114, .expect = 0x00000004 }, // CTRL_4
    .{ .off = 0x140, .expect = 0x0000001F }, // PHY_STATUS (read-only; we only ever checked bit0)
    .{ .off = 0x1ac, .expect = 0x00000001 }, // GLBL_DIGTOP_SPARE10 (REFGEN vote)
    // --- PLL sub-block (phy+0x500)
    .{ .off = 0x504, .expect = 0x00000003 }, // ANALOG_CONTROLS_TWO
    .{ .off = 0x510, .expect = 0x00000000 }, // ANALOG_CONTROLS_THREE
    .{ .off = 0x518, .expect = 0x00000001 }, // ANALOG_CONTROLS_FIVE
    .{ .off = 0x520, .expect = 0x00000000 }, // DSM_DIVIDER
    .{ .off = 0x524, .expect = 0x0000004E }, // FEEDBACK_DIVIDER
    .{ .off = 0x544, .expect = 0x00000040 }, // CALIBRATION_SETTINGS
    .{ .off = 0x568, .expect = 0x000000BA }, // BAND_SEL_CAL_SETTINGS_THREE
    .{ .off = 0x578, .expect = 0x0000000C }, // FREQ_DETECT_SETTINGS_ONE
    .{ .off = 0x590, .expect = 0x0000002F }, // PFILT
    .{ .off = 0x594, .expect = 0x0000003F }, // IFILT
    .{ .off = 0x5a8, .expect = 0x00000000 }, // OUTDIV
    .{ .off = 0x654, .expect = 0x00000000 }, // PLL_PLL_OUTDIV_RATE -- see its comment
    .{ .off = 0x5b8, .expect = 0x00000000 }, // CORE_OVERRIDE
    .{ .off = 0x5bc, .expect = 0x00000012 }, // CORE_INPUT_OVERRIDE
    .{ .off = 0x5c8, .expect = 0x00000008 }, // PLL_DIGITAL_TIMERS_TWO
    .{ .off = 0x5e0, .expect = 0x0000001F }, // DECIMAL_DIV_START_1
    .{ .off = 0x5e4, .expect = 0x00000078 }, // FRAC_DIV_START_LOW_1  (was 0x77)
    .{ .off = 0x5e8, .expect = 0x00000008 }, // FRAC_DIV_START_MID_1
    .{ .off = 0x5ec, .expect = 0x00000000 }, // FRAC_DIV_START_HIGH_1
    .{ .off = 0x658, .expect = 0x00000040 }, // PLL_LOCKDET_RATE_1
    .{ .off = 0x660, .expect = 0x0000000A }, // PLL_PROP_GAIN_RATE_1
    .{ .off = 0x668, .expect = 0x000000C0 }, // PLL_BAND_SEL_RATE_1
    .{ .off = 0x670, .expect = 0x00000082 }, // PLL_INT_GAIN_IFILT_BAND_1
    .{ .off = 0x678, .expect = 0x0000004C }, // PLL_FL_INT_GAIN_PFILT_BAND_1
    .{ .off = 0x690, .expect = 0x00000080 }, // PLL_LOCK_OVERRIDE
    .{ .off = 0x694, .expect = 0x00000006 }, // PLL_LOCK_DELAY
    .{ .off = 0x6b0, .expect = 0x00000051 }, // PLL_COMMON_STATUS_ONE (bit0 = LOCK)
    .{ .off = 0x740, .expect = 0x00000008 }, // VCO_CONFIG_1
    .{ .off = 0x748, .expect = 0x000000A0 }, // CLOCK_INVERTERS_1
    .{ .off = 0x750, .expect = 0x00000010 }, // CMODE_1 (dphy)
    .{ .off = 0x758, .expect = 0x00000001 }, // ANALOG_CONTROLS_FIVE_1
    .{ .off = 0x760, .expect = 0x00000022 }, // PERF_OPTIMIZE
};

/// DISPCC AUDIT (SPEC.md task #5 log).
///
/// DISPCC was the last block in the display path with no verification at
/// all -- and it was hiding a real bug: pclk1/byte1 were sourced from
/// DSI1's own PHY PLL instead of the master's. Every other block had a
/// table; the clock controller did not, so nothing compared it.
///
/// Values read off this device with devmem while Linux drove the panel.
/// Offsets are the RCG CFG registers (cmd_rcgr + 0x4), dispcc_base
/// relative. Returns a bitmask: bit N set == entry N differs from live.
const DispccAuditEntry = struct { off: usize, expect: u32 };

const dispcc_audit_table = [_]DispccAuditEntry{
    .{ .off = 0x80ac, .expect = 0x00000101 }, // PCLK0_CLK_SRC CFG  src_sel=1 DSI0 DSICLK
    .{ .off = 0x810c, .expect = 0x00000201 }, // BYTE0_CLK_SRC CFG  src_sel=2 DSI0 BYTECLK
    .{ .off = 0x80c4, .expect = 0x00000101 }, // PCLK1_CLK_SRC CFG  src_sel=1 DSI0 DSICLK (master's PLL)
    .{ .off = 0x8128, .expect = 0x00000201 }, // BYTE1_CLK_SRC CFG  src_sel=2 DSI0 BYTECLK (master's PLL)
    .{ .off = 0x8120, .expect = 0x00000001 }, // BYTE0_DIV_CLK_SRC  /2
    .{ .off = 0x813c, .expect = 0x00000001 }, // BYTE1_DIV_CLK_SRC  /2
};

export fn sheng_mdss_dispcc_audit(dispcc_base: usize) callconv(.c) i64 {
    var mask: u64 = 0;
    for (dispcc_audit_table, 0..) |e, i| {
        if (mmioRead32(dispcc_base, e.off) != e.expect) mask |= (@as(u64, 1) << @intCast(i));
    }
    return @bitCast(mask);
}

/// Raw PHY state, so the audit's bitmask never has to be guessed at.
/// [63:48] PHY0 CMN_PHY_STATUS, [47:32] PHY0 CMN_CLK_CFG1,
/// [31:16] PHY1 CMN_PHY_STATUS, [15:0]  PHY1 CMN_CLK_CFG1.
/// Live under a working display: PHY_STATUS 0x1F on both,
/// CLK_CFG1 0x30 master / 0x34 slave.
export fn sheng_mdss_phy_state(phy0_base: usize, phy1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(phy0_base, CMN_PHY_STATUS) & 0xffff) << 48) |
        (@as(i64, mmioRead32(phy0_base, CMN_CLK_CFG1) & 0xffff) << 32) |
        (@as(i64, mmioRead32(phy1_base, CMN_PHY_STATUS) & 0xffff) << 16) |
        @as(i64, mmioRead32(phy1_base, CMN_CLK_CFG1) & 0xffff);
}

/// FULL CMN-BLOCK SWEEP (SPEC.md task #5 log).
///
/// The existing phy_audit_table covers 53 offsets I chose -- the ones the
/// kernel writes. That is the same self-selected-sample blindness that hid
/// VID_CFG1, PLL_PLL_OUTDIV_RATE, SPLIT_DISPLAY, VBIF and the SSPP pixel
/// extension: a register NEITHER side writes, but which differs because
/// our resets leave it somewhere else, cannot appear in it.
///
/// So sweep the whole CMN block instead. Every 4-byte offset 0x000-0x1fc
/// captured from this device while Linux was rendering. Excludes 0x000
/// (revision), 0x140 (PHY_STATUS) and 0x1b0/0x1b4, which are read-only or
/// status.
///
/// Returns (first mismatching offset << 32) | mismatch count, so a single
/// value names both how bad it is and exactly where to look -- no bitmask
/// index arithmetic.
const cmn_sweep_table = [_]PhyAuditEntry{
    .{ .off = 0x004, .expect = 0x00000000 },
    .{ .off = 0x008, .expect = 0x00000002 },
    .{ .off = 0x00c, .expect = 0x00000000 },
    .{ .off = 0x010, .expect = 0x00000061 },
    .{ .off = 0x014, .expect = 0x00000030 },
    .{ .off = 0x018, .expect = 0x00000000 },
    .{ .off = 0x01c, .expect = 0x00000001 },
    .{ .off = 0x020, .expect = 0x00000044 },
    .{ .off = 0x024, .expect = 0x0000007F },
    .{ .off = 0x028, .expect = 0x00000000 },
    .{ .off = 0x02c, .expect = 0x00000040 },
    .{ .off = 0x030, .expect = 0x00000004 },
    .{ .off = 0x034, .expect = 0x00000021 },
    .{ .off = 0x038, .expect = 0x00000084 },
    .{ .off = 0x03c, .expect = 0x00000001 },
    .{ .off = 0x040, .expect = 0x000000B8 },
    .{ .off = 0x044, .expect = 0x00000000 },
    .{ .off = 0x048, .expect = 0x0000007F },
    .{ .off = 0x04c, .expect = 0x0000007F },
    .{ .off = 0x050, .expect = 0x00000000 },
    .{ .off = 0x054, .expect = 0x000000FF },
    .{ .off = 0x058, .expect = 0x000000FF },
    .{ .off = 0x05c, .expect = 0x00000000 },
    .{ .off = 0x060, .expect = 0x0000003F },
    .{ .off = 0x064, .expect = 0x0000003F },
    .{ .off = 0x068, .expect = 0x0000003E },
    .{ .off = 0x06c, .expect = 0x00000041 },
    .{ .off = 0x070, .expect = 0x00000041 },
    .{ .off = 0x074, .expect = 0x0000007F },
    .{ .off = 0x078, .expect = 0x00000000 },
    .{ .off = 0x07c, .expect = 0x00000000 },
    .{ .off = 0x080, .expect = 0x00000000 },
    .{ .off = 0x084, .expect = 0x00000000 },
    .{ .off = 0x088, .expect = 0x000000FF },
    .{ .off = 0x08c, .expect = 0x000000FF },
    .{ .off = 0x090, .expect = 0x000000FF },
    .{ .off = 0x094, .expect = 0x00000010 },
    .{ .off = 0x098, .expect = 0x00000000 },
    .{ .off = 0x09c, .expect = 0x00000000 },
    .{ .off = 0x0a0, .expect = 0x0000001F },
    .{ .off = 0x0a4, .expect = 0x00000000 },
    .{ .off = 0x0a8, .expect = 0x00000000 },
    .{ .off = 0x0ac, .expect = 0x00000000 },
    .{ .off = 0x0b0, .expect = 0x00000000 },
    .{ .off = 0x0b4, .expect = 0x00000000 },
    .{ .off = 0x0b8, .expect = 0x00000027 },
    .{ .off = 0x0bc, .expect = 0x0000000A },
    .{ .off = 0x0c0, .expect = 0x0000000C },
    .{ .off = 0x0c4, .expect = 0x00000027 },
    .{ .off = 0x0c8, .expect = 0x00000025 },
    .{ .off = 0x0cc, .expect = 0x0000000A },
    .{ .off = 0x0d0, .expect = 0x0000000B },
    .{ .off = 0x0d4, .expect = 0x00000007 },
    .{ .off = 0x0d8, .expect = 0x00000002 },
    .{ .off = 0x0dc, .expect = 0x00000004 },
    .{ .off = 0x0e0, .expect = 0x00000000 },
    .{ .off = 0x0e4, .expect = 0x00000023 },
    .{ .off = 0x0e8, .expect = 0x0000001A },
    .{ .off = 0x0ec, .expect = 0x00000088 },
    .{ .off = 0x0f0, .expect = 0x00000000 },
    .{ .off = 0x0f4, .expect = 0x0000003C },
    .{ .off = 0x0f8, .expect = 0x00000038 },
    .{ .off = 0x0fc, .expect = 0x00000000 },
    .{ .off = 0x100, .expect = 0x00000055 },
    .{ .off = 0x104, .expect = 0x00000000 },
    .{ .off = 0x108, .expect = 0x00000000 },
    .{ .off = 0x10c, .expect = 0x00000000 },
    .{ .off = 0x110, .expect = 0x00000019 },
    .{ .off = 0x114, .expect = 0x00000004 },
    .{ .off = 0x118, .expect = 0x00000000 },
    .{ .off = 0x11c, .expect = 0x00000000 },
    .{ .off = 0x120, .expect = 0x00000000 },
    .{ .off = 0x124, .expect = 0x000000FF },
    .{ .off = 0x128, .expect = 0x00000000 },
    .{ .off = 0x12c, .expect = 0x00000000 },
    .{ .off = 0x130, .expect = 0x00000000 },
    .{ .off = 0x134, .expect = 0x00000000 },
    .{ .off = 0x138, .expect = 0x00000097 },
    .{ .off = 0x13c, .expect = 0x0000000B },
    .{ .off = 0x144, .expect = 0x00000058 },
    .{ .off = 0x148, .expect = 0x0000001F },
    .{ .off = 0x14c, .expect = 0x0000003F },
    .{ .off = 0x150, .expect = 0x000000FF },
    .{ .off = 0x154, .expect = 0x000000FF },
    .{ .off = 0x158, .expect = 0x000000FF },
    .{ .off = 0x15c, .expect = 0x000000FF },
    .{ .off = 0x160, .expect = 0x000000FF },
    .{ .off = 0x164, .expect = 0x000000FF },
    .{ .off = 0x168, .expect = 0x000000FF },
    .{ .off = 0x16c, .expect = 0x000000FF },
    .{ .off = 0x170, .expect = 0x00000000 },
    .{ .off = 0x174, .expect = 0x00000000 },
    .{ .off = 0x178, .expect = 0x00000000 },
    .{ .off = 0x17c, .expect = 0x00000000 },
    .{ .off = 0x180, .expect = 0x00000000 },
    .{ .off = 0x184, .expect = 0x00000001 },
    .{ .off = 0x188, .expect = 0x000000FF },
    .{ .off = 0x18c, .expect = 0x0000000F },
    .{ .off = 0x190, .expect = 0x000000F0 },
    .{ .off = 0x194, .expect = 0x00000000 },
    .{ .off = 0x198, .expect = 0x00000000 },
    .{ .off = 0x19c, .expect = 0x00000005 },
    .{ .off = 0x1a0, .expect = 0x000000FF },
    .{ .off = 0x1a4, .expect = 0x00000052 },
    .{ .off = 0x1a8, .expect = 0x00000000 },
    .{ .off = 0x1ac, .expect = 0x00000001 },
    .{ .off = 0x1b8, .expect = 0x00000000 },
    .{ .off = 0x1bc, .expect = 0x00000000 },
    .{ .off = 0x1c0, .expect = 0x00000000 },
    .{ .off = 0x1c4, .expect = 0x00000000 },
    .{ .off = 0x1c8, .expect = 0x00000000 },
    .{ .off = 0x1cc, .expect = 0x00000000 },
    .{ .off = 0x1d0, .expect = 0x00000000 },
    .{ .off = 0x1d4, .expect = 0x00000000 },
    .{ .off = 0x1d8, .expect = 0x00000000 },
    .{ .off = 0x1dc, .expect = 0x00000000 },
    .{ .off = 0x1e0, .expect = 0x00000000 },
    .{ .off = 0x1e4, .expect = 0x00000000 },
    .{ .off = 0x1e8, .expect = 0x00000000 },
    .{ .off = 0x1ec, .expect = 0x00000000 },
    .{ .off = 0x1f0, .expect = 0x00000000 },
    .{ .off = 0x1f4, .expect = 0x00000000 },
    .{ .off = 0x1f8, .expect = 0x00000000 },
    .{ .off = 0x1fc, .expect = 0x00000000 },
};

/// FULL LANE + PLL SWEEP (SPEC.md task #5 log).
///
/// Companion to cmn_sweep_table, which came back with ZERO mismatches
/// across all 124 CMN registers -- so the PHY's control block is fully
/// identical to live, not merely the 53 offsets we had chosen.
///
/// This covers the remaining PHY address space: the per-lane block
/// (0x200-0x4ff, five lanes at 0x80 stride) and the PLL block
/// (0x500-0x8ff), captured from this device while Linux was rendering.
/// Excludes 0x6b0/0x6b4, the PLL lock-status registers, which are dynamic.
///
/// Same encoding as the CMN sweep: (first mismatching offset << 32) |
/// count.
const lanepll_sweep_table = [_]PhyAuditEntry{
    .{ .off = 0x500, .expect = 0x00000000 },
    .{ .off = 0x504, .expect = 0x00000003 },
    .{ .off = 0x508, .expect = 0x0000003F },
    .{ .off = 0x50c, .expect = 0x00000000 },
    .{ .off = 0x510, .expect = 0x00000000 },
    .{ .off = 0x514, .expect = 0x00000000 },
    .{ .off = 0x518, .expect = 0x00000001 },
    .{ .off = 0x51c, .expect = 0x00000080 },
    .{ .off = 0x520, .expect = 0x00000000 },
    .{ .off = 0x524, .expect = 0x0000004E },
    .{ .off = 0x528, .expect = 0x000000C0 },
    .{ .off = 0x52c, .expect = 0x00000000 },
    .{ .off = 0x530, .expect = 0x00000010 },
    .{ .off = 0x534, .expect = 0x00000020 },
    .{ .off = 0x538, .expect = 0x00000010 },
    .{ .off = 0x53c, .expect = 0x00000002 },
    .{ .off = 0x540, .expect = 0x0000001C },
    .{ .off = 0x544, .expect = 0x00000040 },
    .{ .off = 0x548, .expect = 0x00000000 },
    .{ .off = 0x54c, .expect = 0x00000002 },
    .{ .off = 0x550, .expect = 0x00000020 },
    .{ .off = 0x554, .expect = 0x00000000 },
    .{ .off = 0x558, .expect = 0x000000FF },
    .{ .off = 0x55c, .expect = 0x00000000 },
    .{ .off = 0x560, .expect = 0x0000000A },
    .{ .off = 0x564, .expect = 0x00000025 },
    .{ .off = 0x568, .expect = 0x000000BA },
    .{ .off = 0x56c, .expect = 0x0000004F },
    .{ .off = 0x570, .expect = 0x0000000A },
    .{ .off = 0x574, .expect = 0x00000000 },
    .{ .off = 0x578, .expect = 0x0000000C },
    .{ .off = 0x57c, .expect = 0x00000020 },
    .{ .off = 0x580, .expect = 0x00000000 },
    .{ .off = 0x584, .expect = 0x000000FF },
    .{ .off = 0x588, .expect = 0x00000010 },
    .{ .off = 0x58c, .expect = 0x00000046 },
    .{ .off = 0x590, .expect = 0x0000002F },
    .{ .off = 0x594, .expect = 0x0000003F },
    .{ .off = 0x598, .expect = 0x00000054 },
    .{ .off = 0x59c, .expect = 0x00000000 },
    .{ .off = 0x5a0, .expect = 0x00000000 },
    .{ .off = 0x5a4, .expect = 0x00000040 },
    .{ .off = 0x5a8, .expect = 0x00000000 },
    .{ .off = 0x5ac, .expect = 0x00000004 },
    .{ .off = 0x5b0, .expect = 0x00000000 },
    .{ .off = 0x5b4, .expect = 0x00000000 },
    .{ .off = 0x5b8, .expect = 0x00000000 },
    .{ .off = 0x5bc, .expect = 0x00000012 },
    .{ .off = 0x5c0, .expect = 0x00000000 },
    .{ .off = 0x5c4, .expect = 0x00000008 },
    .{ .off = 0x5c8, .expect = 0x00000008 },
    .{ .off = 0x5cc, .expect = 0x00000041 },
    .{ .off = 0x5d0, .expect = 0x000000AB },
    .{ .off = 0x5d4, .expect = 0x0000006A },
    .{ .off = 0x5d8, .expect = 0x00000000 },
    .{ .off = 0x5dc, .expect = 0x00000000 },
    .{ .off = 0x5e0, .expect = 0x0000001F },
    .{ .off = 0x5e4, .expect = 0x00000078 },
    .{ .off = 0x5e8, .expect = 0x00000008 },
    .{ .off = 0x5ec, .expect = 0x00000000 },
    .{ .off = 0x5f0, .expect = 0x00000027 },
    .{ .off = 0x5f4, .expect = 0x00000000 },
    .{ .off = 0x5f8, .expect = 0x00000040 },
    .{ .off = 0x5fc, .expect = 0x00000000 },
    .{ .off = 0x600, .expect = 0x00000003 },
    .{ .off = 0x604, .expect = 0x00000000 },
    .{ .off = 0x608, .expect = 0x00000000 },
    .{ .off = 0x60c, .expect = 0x00000000 },
    .{ .off = 0x610, .expect = 0x00000000 },
    .{ .off = 0x614, .expect = 0x00000000 },
    .{ .off = 0x618, .expect = 0x00000000 },
    .{ .off = 0x61c, .expect = 0x00000000 },
    .{ .off = 0x620, .expect = 0x00000000 },
    .{ .off = 0x624, .expect = 0x00000000 },
    .{ .off = 0x628, .expect = 0x00000000 },
    .{ .off = 0x62c, .expect = 0x00000000 },
    .{ .off = 0x630, .expect = 0x00000000 },
    .{ .off = 0x634, .expect = 0x00000000 },
    .{ .off = 0x638, .expect = 0x00000000 },
    .{ .off = 0x63c, .expect = 0x00000000 },
    .{ .off = 0x640, .expect = 0x00000000 },
    .{ .off = 0x644, .expect = 0x00000000 },
    .{ .off = 0x648, .expect = 0x00000000 },
    .{ .off = 0x64c, .expect = 0x00000000 },
    .{ .off = 0x650, .expect = 0x00000000 },
    .{ .off = 0x654, .expect = 0x00000000 },
    .{ .off = 0x658, .expect = 0x00000040 },
    .{ .off = 0x65c, .expect = 0x00000040 },
    .{ .off = 0x660, .expect = 0x0000000A },
    .{ .off = 0x664, .expect = 0x0000000A },
    .{ .off = 0x668, .expect = 0x000000C0 },
    .{ .off = 0x66c, .expect = 0x00000000 },
    .{ .off = 0x670, .expect = 0x00000082 },
    .{ .off = 0x674, .expect = 0x00000054 },
    .{ .off = 0x678, .expect = 0x0000004C },
    .{ .off = 0x67c, .expect = 0x0000004C },
    .{ .off = 0x680, .expect = 0x00000003 },
    .{ .off = 0x684, .expect = 0x00000000 },
    .{ .off = 0x688, .expect = 0x00000000 },
    .{ .off = 0x68c, .expect = 0x00000000 },
    .{ .off = 0x690, .expect = 0x00000080 },
    .{ .off = 0x694, .expect = 0x00000006 },
    .{ .off = 0x698, .expect = 0x00000019 },
    .{ .off = 0x69c, .expect = 0x00000000 },
    .{ .off = 0x6a0, .expect = 0x00000000 },
    .{ .off = 0x6a4, .expect = 0x00000040 },
    .{ .off = 0x6a8, .expect = 0x00000020 },
    .{ .off = 0x6ac, .expect = 0x00000000 },
    .{ .off = 0x6c0, .expect = 0x00000088 },
    .{ .off = 0x6c4, .expect = 0x00000097 },
    .{ .off = 0x6c8, .expect = 0x00000006 },
    .{ .off = 0x6cc, .expect = 0x00000000 },
    .{ .off = 0x6d0, .expect = 0x00000000 },
    .{ .off = 0x6d4, .expect = 0x0000008B },
    .{ .off = 0x6d8, .expect = 0x00000005 },
    .{ .off = 0x6dc, .expect = 0x00000002 },
    .{ .off = 0x6e0, .expect = 0x00000014 },
    .{ .off = 0x6e4, .expect = 0x00000000 },
    .{ .off = 0x6e8, .expect = 0x00000002 },
    .{ .off = 0x6ec, .expect = 0x00000000 },
    .{ .off = 0x6f0, .expect = 0x0000004F },
    .{ .off = 0x6f4, .expect = 0x00000053 },
    .{ .off = 0x6f8, .expect = 0x00000004 },
    .{ .off = 0x6fc, .expect = 0x00000000 },
    .{ .off = 0x700, .expect = 0x00000000 },
    .{ .off = 0x704, .expect = 0x00000000 },
    .{ .off = 0x708, .expect = 0x00000000 },
    .{ .off = 0x70c, .expect = 0x00000000 },
    .{ .off = 0x710, .expect = 0x00000000 },
    .{ .off = 0x714, .expect = 0x00000000 },
    .{ .off = 0x718, .expect = 0x00000095 },
    .{ .off = 0x71c, .expect = 0x00000082 },
    .{ .off = 0x720, .expect = 0x00000000 },
    .{ .off = 0x724, .expect = 0x00000000 },
    .{ .off = 0x728, .expect = 0x0000001D },
    .{ .off = 0x72c, .expect = 0x0000001C },
    .{ .off = 0x730, .expect = 0x000000FF },
    .{ .off = 0x734, .expect = 0x00000022 },
    .{ .off = 0x738, .expect = 0x00000009 },
    .{ .off = 0x73c, .expect = 0x00000000 },
    .{ .off = 0x740, .expect = 0x00000008 },
    .{ .off = 0x744, .expect = 0x00000000 },
    .{ .off = 0x748, .expect = 0x000000A0 },
    .{ .off = 0x74c, .expect = 0x00000000 },
    .{ .off = 0x750, .expect = 0x00000010 },
    .{ .off = 0x754, .expect = 0x00000010 },
    .{ .off = 0x758, .expect = 0x00000001 },
    .{ .off = 0x75c, .expect = 0x00000003 },
    .{ .off = 0x760, .expect = 0x00000022 },
    .{ .off = 0x764, .expect = 0x00000000 },
    .{ .off = 0x768, .expect = 0x00000000 },
    .{ .off = 0x76c, .expect = 0x00000000 },
    .{ .off = 0x770, .expect = 0x00000000 },
    .{ .off = 0x774, .expect = 0x0000005A },
    .{ .off = 0x778, .expect = 0x00000000 },
    .{ .off = 0x77c, .expect = 0x00000000 },
    .{ .off = 0x780, .expect = 0x00000000 },
    .{ .off = 0x784, .expect = 0x00000002 },
    .{ .off = 0x788, .expect = 0x00000008 },
    .{ .off = 0x78c, .expect = 0x00000020 },
    .{ .off = 0x790, .expect = 0x00000000 },
    .{ .off = 0x794, .expect = 0x00000000 },
    .{ .off = 0x798, .expect = 0x00000000 },
    .{ .off = 0x79c, .expect = 0x00000000 },
    .{ .off = 0x7a0, .expect = 0x00000000 },
    .{ .off = 0x7a4, .expect = 0x00000000 },
    .{ .off = 0x7a8, .expect = 0x00000000 },
    .{ .off = 0x7ac, .expect = 0x00000000 },
    .{ .off = 0x7b0, .expect = 0x00000000 },
    .{ .off = 0x7b4, .expect = 0x00000000 },
    .{ .off = 0x7b8, .expect = 0x00000000 },
    .{ .off = 0x7bc, .expect = 0x00000000 },
    .{ .off = 0x7c0, .expect = 0x00000000 },
    .{ .off = 0x7c4, .expect = 0x00000000 },
    .{ .off = 0x7c8, .expect = 0x00000000 },
    .{ .off = 0x7cc, .expect = 0x00000000 },
    .{ .off = 0x7d0, .expect = 0x00000000 },
    .{ .off = 0x7d4, .expect = 0x00000000 },
    .{ .off = 0x7d8, .expect = 0x00000000 },
    .{ .off = 0x7dc, .expect = 0x00000000 },
    .{ .off = 0x7e0, .expect = 0x00000000 },
    .{ .off = 0x7e4, .expect = 0x00000000 },
    .{ .off = 0x7e8, .expect = 0x00000000 },
    .{ .off = 0x7ec, .expect = 0x00000000 },
    .{ .off = 0x7f0, .expect = 0x00000000 },
    .{ .off = 0x7f4, .expect = 0x00000000 },
    .{ .off = 0x7f8, .expect = 0x00000000 },
    .{ .off = 0x7fc, .expect = 0x00000000 },
    .{ .off = 0x800, .expect = 0x00000025 },
    .{ .off = 0x804, .expect = 0x00000000 },
    .{ .off = 0x808, .expect = 0x00000002 },
    .{ .off = 0x80c, .expect = 0x00000000 },
    .{ .off = 0x810, .expect = 0x00000061 },
    .{ .off = 0x814, .expect = 0x00000030 },
    .{ .off = 0x818, .expect = 0x00000000 },
    .{ .off = 0x81c, .expect = 0x00000001 },
    .{ .off = 0x820, .expect = 0x00000044 },
    .{ .off = 0x824, .expect = 0x0000007F },
    .{ .off = 0x828, .expect = 0x00000000 },
    .{ .off = 0x82c, .expect = 0x00000040 },
    .{ .off = 0x830, .expect = 0x00000004 },
    .{ .off = 0x834, .expect = 0x00000021 },
    .{ .off = 0x838, .expect = 0x00000084 },
    .{ .off = 0x83c, .expect = 0x00000001 },
    .{ .off = 0x840, .expect = 0x000000B8 },
    .{ .off = 0x844, .expect = 0x00000000 },
    .{ .off = 0x848, .expect = 0x0000007F },
    .{ .off = 0x84c, .expect = 0x0000007F },
    .{ .off = 0x850, .expect = 0x00000000 },
    .{ .off = 0x854, .expect = 0x000000FF },
    .{ .off = 0x858, .expect = 0x000000FF },
    .{ .off = 0x85c, .expect = 0x00000000 },
    .{ .off = 0x860, .expect = 0x0000003F },
    .{ .off = 0x864, .expect = 0x0000003F },
    .{ .off = 0x868, .expect = 0x0000003E },
    .{ .off = 0x86c, .expect = 0x00000041 },
    .{ .off = 0x870, .expect = 0x00000041 },
    .{ .off = 0x874, .expect = 0x0000007F },
    .{ .off = 0x878, .expect = 0x00000000 },
    .{ .off = 0x87c, .expect = 0x00000000 },
    .{ .off = 0x880, .expect = 0x00000000 },
    .{ .off = 0x884, .expect = 0x00000000 },
    .{ .off = 0x888, .expect = 0x000000FF },
    .{ .off = 0x88c, .expect = 0x000000FF },
    .{ .off = 0x890, .expect = 0x000000FF },
    .{ .off = 0x894, .expect = 0x00000010 },
    .{ .off = 0x898, .expect = 0x00000000 },
    .{ .off = 0x89c, .expect = 0x00000000 },
    .{ .off = 0x8a0, .expect = 0x0000001F },
    .{ .off = 0x8a4, .expect = 0x00000000 },
    .{ .off = 0x8a8, .expect = 0x00000000 },
    .{ .off = 0x8ac, .expect = 0x00000000 },
    .{ .off = 0x8b0, .expect = 0x00000000 },
    .{ .off = 0x8b4, .expect = 0x00000000 },
    .{ .off = 0x8b8, .expect = 0x00000027 },
    .{ .off = 0x8bc, .expect = 0x0000000A },
    .{ .off = 0x8c0, .expect = 0x0000000C },
    .{ .off = 0x8c4, .expect = 0x00000027 },
    .{ .off = 0x8c8, .expect = 0x00000025 },
    .{ .off = 0x8cc, .expect = 0x0000000A },
    .{ .off = 0x8d0, .expect = 0x0000000B },
    .{ .off = 0x8d4, .expect = 0x00000007 },
    .{ .off = 0x8d8, .expect = 0x00000002 },
    .{ .off = 0x8dc, .expect = 0x00000004 },
    .{ .off = 0x8e0, .expect = 0x00000000 },
    .{ .off = 0x8e4, .expect = 0x00000023 },
    .{ .off = 0x8e8, .expect = 0x0000001A },
    .{ .off = 0x8ec, .expect = 0x00000088 },
    .{ .off = 0x8f0, .expect = 0x00000000 },
    .{ .off = 0x8f4, .expect = 0x0000003C },
    .{ .off = 0x8f8, .expect = 0x00000038 },
    .{ .off = 0x8fc, .expect = 0x00000000 },
    .{ .off = 0x200, .expect = 0x00000000 },
    .{ .off = 0x204, .expect = 0x00000000 },
    .{ .off = 0x208, .expect = 0x0000000A },
    .{ .off = 0x20c, .expect = 0x00000000 },
    .{ .off = 0x210, .expect = 0x00000000 },
    .{ .off = 0x214, .expect = 0x00000003 },
    .{ .off = 0x218, .expect = 0x00000040 },
    .{ .off = 0x21c, .expect = 0x00000000 },
    .{ .off = 0x220, .expect = 0x000000FF },
    .{ .off = 0x224, .expect = 0x00000000 },
    .{ .off = 0x228, .expect = 0x00000000 },
    .{ .off = 0x22c, .expect = 0x00000000 },
    .{ .off = 0x230, .expect = 0x00000000 },
    .{ .off = 0x234, .expect = 0x00000000 },
    .{ .off = 0x238, .expect = 0x00000055 },
    .{ .off = 0x23c, .expect = 0x000000FF },
    .{ .off = 0x240, .expect = 0x00000000 },
    .{ .off = 0x244, .expect = 0x00000000 },
    .{ .off = 0x248, .expect = 0x00000000 },
    .{ .off = 0x24c, .expect = 0x00000000 },
    .{ .off = 0x250, .expect = 0x00000000 },
    .{ .off = 0x254, .expect = 0x00000000 },
    .{ .off = 0x258, .expect = 0x00000000 },
    .{ .off = 0x25c, .expect = 0x00000000 },
    .{ .off = 0x260, .expect = 0x000000FF },
    .{ .off = 0x264, .expect = 0x000000FF },
    .{ .off = 0x268, .expect = 0x000000FF },
    .{ .off = 0x26c, .expect = 0x00000000 },
    .{ .off = 0x270, .expect = 0x00000000 },
    .{ .off = 0x274, .expect = 0x00000000 },
    .{ .off = 0x278, .expect = 0x00000000 },
    .{ .off = 0x27c, .expect = 0x0000002A },
    .{ .off = 0x280, .expect = 0x00000000 },
    .{ .off = 0x284, .expect = 0x00000000 },
    .{ .off = 0x288, .expect = 0x0000000A },
    .{ .off = 0x28c, .expect = 0x00000000 },
    .{ .off = 0x290, .expect = 0x00000000 },
    .{ .off = 0x294, .expect = 0x00000000 },
    .{ .off = 0x298, .expect = 0x00000040 },
    .{ .off = 0x29c, .expect = 0x00000000 },
    .{ .off = 0x2a0, .expect = 0x000000FF },
    .{ .off = 0x2a4, .expect = 0x00000000 },
    .{ .off = 0x2a8, .expect = 0x00000000 },
    .{ .off = 0x2ac, .expect = 0x00000000 },
    .{ .off = 0x2b0, .expect = 0x00000000 },
    .{ .off = 0x2b4, .expect = 0x00000000 },
    .{ .off = 0x2b8, .expect = 0x00000055 },
    .{ .off = 0x2bc, .expect = 0x000000FF },
    .{ .off = 0x2c0, .expect = 0x00000000 },
    .{ .off = 0x2c4, .expect = 0x00000000 },
    .{ .off = 0x2c8, .expect = 0x00000000 },
    .{ .off = 0x2cc, .expect = 0x00000000 },
    .{ .off = 0x2d0, .expect = 0x00000000 },
    .{ .off = 0x2d4, .expect = 0x00000000 },
    .{ .off = 0x2d8, .expect = 0x00000000 },
    .{ .off = 0x2dc, .expect = 0x00000000 },
    .{ .off = 0x2e0, .expect = 0x000000FF },
    .{ .off = 0x2e4, .expect = 0x000000FF },
    .{ .off = 0x2e8, .expect = 0x000000FF },
    .{ .off = 0x2ec, .expect = 0x00000000 },
    .{ .off = 0x2f0, .expect = 0x00000000 },
    .{ .off = 0x2f4, .expect = 0x00000000 },
    .{ .off = 0x2f8, .expect = 0x00000000 },
    .{ .off = 0x2fc, .expect = 0x0000002A },
    .{ .off = 0x300, .expect = 0x00000000 },
    .{ .off = 0x304, .expect = 0x00000000 },
    .{ .off = 0x308, .expect = 0x0000000A },
    .{ .off = 0x30c, .expect = 0x00000000 },
    .{ .off = 0x310, .expect = 0x00000000 },
    .{ .off = 0x314, .expect = 0x00000000 },
    .{ .off = 0x318, .expect = 0x00000040 },
    .{ .off = 0x31c, .expect = 0x00000000 },
    .{ .off = 0x320, .expect = 0x000000FF },
    .{ .off = 0x324, .expect = 0x00000000 },
    .{ .off = 0x328, .expect = 0x00000000 },
    .{ .off = 0x32c, .expect = 0x00000000 },
    .{ .off = 0x330, .expect = 0x00000000 },
    .{ .off = 0x334, .expect = 0x00000000 },
    .{ .off = 0x338, .expect = 0x00000055 },
    .{ .off = 0x33c, .expect = 0x000000FF },
    .{ .off = 0x340, .expect = 0x00000000 },
    .{ .off = 0x344, .expect = 0x00000000 },
    .{ .off = 0x348, .expect = 0x00000000 },
    .{ .off = 0x34c, .expect = 0x00000000 },
    .{ .off = 0x350, .expect = 0x00000000 },
    .{ .off = 0x354, .expect = 0x00000000 },
    .{ .off = 0x358, .expect = 0x00000000 },
    .{ .off = 0x35c, .expect = 0x00000000 },
    .{ .off = 0x360, .expect = 0x000000FF },
    .{ .off = 0x364, .expect = 0x000000FF },
    .{ .off = 0x368, .expect = 0x000000FF },
    .{ .off = 0x36c, .expect = 0x00000000 },
    .{ .off = 0x370, .expect = 0x00000000 },
    .{ .off = 0x374, .expect = 0x00000000 },
    .{ .off = 0x378, .expect = 0x00000000 },
    .{ .off = 0x37c, .expect = 0x0000002A },
    .{ .off = 0x380, .expect = 0x00000000 },
    .{ .off = 0x384, .expect = 0x00000000 },
    .{ .off = 0x388, .expect = 0x0000000A },
    .{ .off = 0x38c, .expect = 0x00000000 },
    .{ .off = 0x390, .expect = 0x00000000 },
    .{ .off = 0x394, .expect = 0x00000000 },
    .{ .off = 0x398, .expect = 0x00000046 },
    .{ .off = 0x39c, .expect = 0x00000000 },
    .{ .off = 0x3a0, .expect = 0x000000FF },
    .{ .off = 0x3a4, .expect = 0x00000000 },
    .{ .off = 0x3a8, .expect = 0x00000000 },
    .{ .off = 0x3ac, .expect = 0x00000000 },
    .{ .off = 0x3b0, .expect = 0x00000000 },
    .{ .off = 0x3b4, .expect = 0x00000000 },
    .{ .off = 0x3b8, .expect = 0x00000055 },
    .{ .off = 0x3bc, .expect = 0x000000FF },
    .{ .off = 0x3c0, .expect = 0x00000000 },
    .{ .off = 0x3c4, .expect = 0x00000000 },
    .{ .off = 0x3c8, .expect = 0x00000000 },
    .{ .off = 0x3cc, .expect = 0x00000000 },
    .{ .off = 0x3d0, .expect = 0x00000000 },
    .{ .off = 0x3d4, .expect = 0x00000000 },
    .{ .off = 0x3d8, .expect = 0x00000000 },
    .{ .off = 0x3dc, .expect = 0x00000000 },
    .{ .off = 0x3e0, .expect = 0x000000FF },
    .{ .off = 0x3e4, .expect = 0x000000FF },
    .{ .off = 0x3e8, .expect = 0x000000FF },
    .{ .off = 0x3ec, .expect = 0x00000000 },
    .{ .off = 0x3f0, .expect = 0x00000000 },
    .{ .off = 0x3f4, .expect = 0x00000000 },
    .{ .off = 0x3f8, .expect = 0x00000000 },
    .{ .off = 0x3fc, .expect = 0x0000002A },
    .{ .off = 0x400, .expect = 0x00000000 },
    .{ .off = 0x404, .expect = 0x00000000 },
    .{ .off = 0x408, .expect = 0x0000008A },
    .{ .off = 0x40c, .expect = 0x00000000 },
    .{ .off = 0x410, .expect = 0x00000000 },
    .{ .off = 0x414, .expect = 0x00000000 },
    .{ .off = 0x418, .expect = 0x00000041 },
    .{ .off = 0x41c, .expect = 0x00000000 },
    .{ .off = 0x420, .expect = 0x000000FF },
    .{ .off = 0x424, .expect = 0x00000000 },
    .{ .off = 0x428, .expect = 0x00000000 },
    .{ .off = 0x42c, .expect = 0x00000000 },
    .{ .off = 0x430, .expect = 0x00000000 },
    .{ .off = 0x434, .expect = 0x00000000 },
    .{ .off = 0x438, .expect = 0x00000055 },
    .{ .off = 0x43c, .expect = 0x000000FF },
    .{ .off = 0x440, .expect = 0x00000000 },
    .{ .off = 0x444, .expect = 0x00000000 },
    .{ .off = 0x448, .expect = 0x00000000 },
    .{ .off = 0x44c, .expect = 0x00000000 },
    .{ .off = 0x450, .expect = 0x00000000 },
    .{ .off = 0x454, .expect = 0x00000000 },
    .{ .off = 0x458, .expect = 0x00000000 },
    .{ .off = 0x45c, .expect = 0x00000000 },
    .{ .off = 0x460, .expect = 0x000000FF },
    .{ .off = 0x464, .expect = 0x000000FF },
    .{ .off = 0x468, .expect = 0x000000FF },
    .{ .off = 0x46c, .expect = 0x00000000 },
    .{ .off = 0x470, .expect = 0x00000000 },
    .{ .off = 0x474, .expect = 0x00000000 },
    .{ .off = 0x478, .expect = 0x00000000 },
    .{ .off = 0x47c, .expect = 0x0000002A },
};

export fn sheng_mdss_phy_lanepll_sweep(phy_base: usize) callconv(.c) i64 {
    var count: u32 = 0;
    var first: u32 = 0xffff;
    for (lanepll_sweep_table) |e| {
        if (mmioRead32(phy_base, e.off) != e.expect) {
            if (first == 0xffff) first = @intCast(e.off);
            count += 1;
        }
    }
    return (@as(i64, first) << 32) | @as(i64, count);
}

/// Full CMN sweep of the SLAVE PHY (DSI1).
///
/// The other two sweeps only ever run against DSI0, and the slave's only
/// other coverage skips 0x010, 0x03c, 0x140 and everything >= 0x500 as
/// "don't care". That model is wrong: Linux never WRITES those slave
/// registers, but they hold values inherited from ABL that the slave
/// link still runs on. PHY1 CMN_CLK_CFG0 reads 0x000000F1 on a rendering
/// Linux and appears nowhere in its PHY write trace -- ABL put it there
/// and Linux leaves it alone.
///
/// This driver does not leave it alone: it pulses a PHY reset, which
/// "silently changes its PLL registers to reset status". Linux repairs
/// that with msm_dsi_phy_pll_restore_state(), but only when
/// `phy->usecase != MSM_DSI_PHY_SLAVE` -- so on the slave nothing
/// restores it.
///
/// On a bonded panel a broken slave is a whole-link failure, not half an
/// image: the DDIC needs synchronised SOT on both links and rejects
/// every transaction, commands included, while the master host reports
/// flawless transmission because its own side is fine.
///
/// Expectations captured from this device at explicit offsets only.
/// Never sweep a blind range -- that wedges the bus.
///
/// Same encoding as the other sweeps: (first mismatching offset << 32) |
/// count. A count of 0 clears the slave PHY and closes the last large
/// unexamined area. Anything else is the first hard divergence found since
/// the register-shift fix.
const phy1_cmn_sweep_table = [_]PhyAuditEntry{
    .{ .off = 0x004, .expect = 0x00000000 },
    .{ .off = 0x008, .expect = 0x00000002 },
    .{ .off = 0x00c, .expect = 0x00000000 },
    .{ .off = 0x010, .expect = 0x000000f1 },
    .{ .off = 0x014, .expect = 0x00000034 },
    .{ .off = 0x018, .expect = 0x00000000 },
    .{ .off = 0x01c, .expect = 0x00000001 },
    .{ .off = 0x020, .expect = 0x00000044 },
    .{ .off = 0x024, .expect = 0x0000007f },
    .{ .off = 0x028, .expect = 0x00000000 },
    .{ .off = 0x02c, .expect = 0x00000040 },
    .{ .off = 0x030, .expect = 0x00000004 },
    .{ .off = 0x034, .expect = 0x00000021 },
    .{ .off = 0x038, .expect = 0x00000084 },
    .{ .off = 0x03c, .expect = 0x00000000 },
    .{ .off = 0x040, .expect = 0x000000b8 },
    .{ .off = 0x044, .expect = 0x00000000 },
    .{ .off = 0x048, .expect = 0x0000007f },
    .{ .off = 0x04c, .expect = 0x0000007f },
    .{ .off = 0x050, .expect = 0x00000000 },
    .{ .off = 0x054, .expect = 0x000000ff },
    .{ .off = 0x058, .expect = 0x000000ff },
    .{ .off = 0x05c, .expect = 0x00000000 },
    .{ .off = 0x060, .expect = 0x0000003f },
    .{ .off = 0x064, .expect = 0x0000003f },
    .{ .off = 0x068, .expect = 0x0000003e },
    .{ .off = 0x06c, .expect = 0x00000041 },
    .{ .off = 0x070, .expect = 0x00000041 },
    .{ .off = 0x074, .expect = 0x0000007f },
    .{ .off = 0x078, .expect = 0x00000000 },
    .{ .off = 0x07c, .expect = 0x00000000 },
    .{ .off = 0x080, .expect = 0x00000000 },
    .{ .off = 0x084, .expect = 0x00000000 },
    .{ .off = 0x088, .expect = 0x000000ff },
    .{ .off = 0x08c, .expect = 0x000000ff },
    .{ .off = 0x090, .expect = 0x000000ff },
    .{ .off = 0x094, .expect = 0x00000010 },
    .{ .off = 0x098, .expect = 0x00000000 },
    .{ .off = 0x09c, .expect = 0x00000000 },
    .{ .off = 0x0a0, .expect = 0x0000001f },
    .{ .off = 0x0a4, .expect = 0x00000000 },
    .{ .off = 0x0a8, .expect = 0x00000000 },
    .{ .off = 0x0ac, .expect = 0x00000000 },
    .{ .off = 0x0b0, .expect = 0x00000000 },
    .{ .off = 0x0b4, .expect = 0x00000000 },
    .{ .off = 0x0b8, .expect = 0x00000027 },
    .{ .off = 0x0bc, .expect = 0x0000000a },
    .{ .off = 0x0c0, .expect = 0x0000000c },
    .{ .off = 0x0c4, .expect = 0x00000027 },
    .{ .off = 0x0c8, .expect = 0x00000025 },
    .{ .off = 0x0cc, .expect = 0x0000000a },
    .{ .off = 0x0d0, .expect = 0x0000000b },
    .{ .off = 0x0d4, .expect = 0x00000007 },
    .{ .off = 0x0d8, .expect = 0x00000002 },
    .{ .off = 0x0dc, .expect = 0x00000004 },
    .{ .off = 0x0e0, .expect = 0x00000000 },
    .{ .off = 0x0e4, .expect = 0x00000023 },
    .{ .off = 0x0e8, .expect = 0x0000001a },
    .{ .off = 0x0ec, .expect = 0x00000088 },
    .{ .off = 0x0f0, .expect = 0x00000000 },
    .{ .off = 0x0f4, .expect = 0x0000003c },
    .{ .off = 0x0f8, .expect = 0x00000038 },
    .{ .off = 0x0fc, .expect = 0x00000000 },
    .{ .off = 0x100, .expect = 0x00000055 },
    .{ .off = 0x104, .expect = 0x00000000 },
    .{ .off = 0x108, .expect = 0x00000000 },
    .{ .off = 0x10c, .expect = 0x00000000 },
    .{ .off = 0x110, .expect = 0x00000019 },
    .{ .off = 0x114, .expect = 0x00000004 },
    .{ .off = 0x118, .expect = 0x00000000 },
    .{ .off = 0x11c, .expect = 0x00000000 },
    .{ .off = 0x120, .expect = 0x00000000 },
    .{ .off = 0x124, .expect = 0x000000ff },
    .{ .off = 0x128, .expect = 0x00000000 },
    .{ .off = 0x12c, .expect = 0x00000000 },
    .{ .off = 0x130, .expect = 0x00000000 },
    .{ .off = 0x134, .expect = 0x00000000 },
    .{ .off = 0x138, .expect = 0x00000097 },
    .{ .off = 0x13c, .expect = 0x0000000b },
    .{ .off = 0x144, .expect = 0x00000058 },
    .{ .off = 0x148, .expect = 0x0000001f },
    .{ .off = 0x14c, .expect = 0x0000003f },
    .{ .off = 0x150, .expect = 0x000000ff },
    .{ .off = 0x154, .expect = 0x000000ff },
    .{ .off = 0x158, .expect = 0x000000ff },
    .{ .off = 0x15c, .expect = 0x000000ff },
    .{ .off = 0x160, .expect = 0x000000ff },
    .{ .off = 0x164, .expect = 0x000000ff },
    .{ .off = 0x168, .expect = 0x000000ff },
    .{ .off = 0x16c, .expect = 0x000000ff },
    .{ .off = 0x170, .expect = 0x00000000 },
    .{ .off = 0x174, .expect = 0x00000000 },
    .{ .off = 0x178, .expect = 0x00000000 },
    .{ .off = 0x17c, .expect = 0x00000000 },
    .{ .off = 0x180, .expect = 0x00000000 },
    .{ .off = 0x184, .expect = 0x00000001 },
    .{ .off = 0x188, .expect = 0x000000ff },
    .{ .off = 0x18c, .expect = 0x0000000f },
    .{ .off = 0x190, .expect = 0x000000f0 },
    .{ .off = 0x194, .expect = 0x00000000 },
    .{ .off = 0x198, .expect = 0x00000000 },
    .{ .off = 0x19c, .expect = 0x00000005 },
    .{ .off = 0x1a0, .expect = 0x000000ff },
    .{ .off = 0x1a4, .expect = 0x00000052 },
    .{ .off = 0x1a8, .expect = 0x00000000 },
    .{ .off = 0x1ac, .expect = 0x00000001 },
    .{ .off = 0x1b8, .expect = 0x00000000 },
    .{ .off = 0x1bc, .expect = 0x00000000 },
    .{ .off = 0x1c0, .expect = 0x00000000 },
    .{ .off = 0x1c4, .expect = 0x00000000 },
    .{ .off = 0x1c8, .expect = 0x00000000 },
    .{ .off = 0x1cc, .expect = 0x00000000 },
    .{ .off = 0x1d0, .expect = 0x00000000 },
    .{ .off = 0x1d4, .expect = 0x00000000 },
    .{ .off = 0x1d8, .expect = 0x00000000 },
    .{ .off = 0x1dc, .expect = 0x00000000 },
    .{ .off = 0x1e0, .expect = 0x00000000 },
    .{ .off = 0x1e4, .expect = 0x00000000 },
    .{ .off = 0x1e8, .expect = 0x00000000 },
    .{ .off = 0x1ec, .expect = 0x00000000 },
    .{ .off = 0x1f0, .expect = 0x00000000 },
    .{ .off = 0x1f4, .expect = 0x00000000 },
    .{ .off = 0x1f8, .expect = 0x00000000 },
    .{ .off = 0x1fc, .expect = 0x00000000 },
};

/// SLAVE-PHY (DSI1) LANE-BLOCK SWEEP -- companion to
/// phy1_cmn_sweep_table, closing the rest of PHY1.
///
/// The CMN sweep came back 123/124 clean, so the slave PHY is very nearly
/// right and the "broken slave link" theory is mostly dead. This covers
/// the remaining 160 lane registers (0x200-0x47c, the same offsets the
/// PHY0 lanepll sweep uses below 0x500), captured live from PHY1 on a
/// rendering Linux via devmem at explicit offsets.
///
/// Worth doing even though CMN was clean: Linux's own PHY write trace
/// shows it programs 30 lane registers on PHY1, byte-identical to the
/// ones it writes on PHY0. So unlike CMN -- where master and slave
/// legitimately differ at 0x010/0x014/0x03c -- the lane block should be
/// an exact match between the two PHYs, and any divergence here is
/// unambiguous.
const phy1_lane_sweep_table = [_]PhyAuditEntry{
    .{ .off = 0x200, .expect = 0x00000000 },
    .{ .off = 0x204, .expect = 0x00000000 },
    .{ .off = 0x208, .expect = 0x0000000a },
    .{ .off = 0x20c, .expect = 0x00000000 },
    .{ .off = 0x210, .expect = 0x00000000 },
    .{ .off = 0x214, .expect = 0x00000003 },
    .{ .off = 0x218, .expect = 0x00000040 },
    .{ .off = 0x21c, .expect = 0x00000000 },
    .{ .off = 0x220, .expect = 0x000000ff },
    .{ .off = 0x224, .expect = 0x00000000 },
    .{ .off = 0x228, .expect = 0x00000000 },
    .{ .off = 0x22c, .expect = 0x00000000 },
    .{ .off = 0x230, .expect = 0x00000000 },
    .{ .off = 0x234, .expect = 0x00000000 },
    .{ .off = 0x238, .expect = 0x00000055 },
    .{ .off = 0x23c, .expect = 0x000000ff },
    .{ .off = 0x240, .expect = 0x00000000 },
    .{ .off = 0x244, .expect = 0x00000000 },
    .{ .off = 0x248, .expect = 0x00000000 },
    .{ .off = 0x24c, .expect = 0x00000000 },
    .{ .off = 0x250, .expect = 0x00000000 },
    .{ .off = 0x254, .expect = 0x00000000 },
    .{ .off = 0x258, .expect = 0x00000000 },
    .{ .off = 0x25c, .expect = 0x00000000 },
    .{ .off = 0x260, .expect = 0x000000ff },
    .{ .off = 0x264, .expect = 0x000000ff },
    .{ .off = 0x268, .expect = 0x000000ff },
    .{ .off = 0x26c, .expect = 0x00000000 },
    .{ .off = 0x270, .expect = 0x00000000 },
    .{ .off = 0x274, .expect = 0x00000000 },
    .{ .off = 0x278, .expect = 0x00000000 },
    .{ .off = 0x27c, .expect = 0x0000002a },
    .{ .off = 0x280, .expect = 0x00000000 },
    .{ .off = 0x284, .expect = 0x00000000 },
    .{ .off = 0x288, .expect = 0x0000000a },
    .{ .off = 0x28c, .expect = 0x00000000 },
    .{ .off = 0x290, .expect = 0x00000000 },
    .{ .off = 0x294, .expect = 0x00000000 },
    .{ .off = 0x298, .expect = 0x00000040 },
    .{ .off = 0x29c, .expect = 0x00000000 },
    .{ .off = 0x2a0, .expect = 0x000000ff },
    .{ .off = 0x2a4, .expect = 0x00000000 },
    .{ .off = 0x2a8, .expect = 0x00000000 },
    .{ .off = 0x2ac, .expect = 0x00000000 },
    .{ .off = 0x2b0, .expect = 0x00000000 },
    .{ .off = 0x2b4, .expect = 0x00000000 },
    .{ .off = 0x2b8, .expect = 0x00000055 },
    .{ .off = 0x2bc, .expect = 0x000000ff },
    .{ .off = 0x2c0, .expect = 0x00000000 },
    .{ .off = 0x2c4, .expect = 0x00000000 },
    .{ .off = 0x2c8, .expect = 0x00000000 },
    .{ .off = 0x2cc, .expect = 0x00000000 },
    .{ .off = 0x2d0, .expect = 0x00000000 },
    .{ .off = 0x2d4, .expect = 0x00000000 },
    .{ .off = 0x2d8, .expect = 0x00000000 },
    .{ .off = 0x2dc, .expect = 0x00000000 },
    .{ .off = 0x2e0, .expect = 0x000000ff },
    .{ .off = 0x2e4, .expect = 0x000000ff },
    .{ .off = 0x2e8, .expect = 0x000000ff },
    .{ .off = 0x2ec, .expect = 0x00000000 },
    .{ .off = 0x2f0, .expect = 0x00000000 },
    .{ .off = 0x2f4, .expect = 0x00000000 },
    .{ .off = 0x2f8, .expect = 0x00000000 },
    .{ .off = 0x2fc, .expect = 0x0000002a },
    .{ .off = 0x300, .expect = 0x00000000 },
    .{ .off = 0x304, .expect = 0x00000000 },
    .{ .off = 0x308, .expect = 0x0000000a },
    .{ .off = 0x30c, .expect = 0x00000000 },
    .{ .off = 0x310, .expect = 0x00000000 },
    .{ .off = 0x314, .expect = 0x00000000 },
    .{ .off = 0x318, .expect = 0x00000040 },
    .{ .off = 0x31c, .expect = 0x00000000 },
    .{ .off = 0x320, .expect = 0x000000ff },
    .{ .off = 0x324, .expect = 0x00000000 },
    .{ .off = 0x328, .expect = 0x00000000 },
    .{ .off = 0x32c, .expect = 0x00000000 },
    .{ .off = 0x330, .expect = 0x00000000 },
    .{ .off = 0x334, .expect = 0x00000000 },
    .{ .off = 0x338, .expect = 0x00000055 },
    .{ .off = 0x33c, .expect = 0x000000ff },
    .{ .off = 0x340, .expect = 0x00000000 },
    .{ .off = 0x344, .expect = 0x00000000 },
    .{ .off = 0x348, .expect = 0x00000000 },
    .{ .off = 0x34c, .expect = 0x00000000 },
    .{ .off = 0x350, .expect = 0x00000000 },
    .{ .off = 0x354, .expect = 0x00000000 },
    .{ .off = 0x358, .expect = 0x00000000 },
    .{ .off = 0x35c, .expect = 0x00000000 },
    .{ .off = 0x360, .expect = 0x000000ff },
    .{ .off = 0x364, .expect = 0x000000ff },
    .{ .off = 0x368, .expect = 0x000000ff },
    .{ .off = 0x36c, .expect = 0x00000000 },
    .{ .off = 0x370, .expect = 0x00000000 },
    .{ .off = 0x374, .expect = 0x00000000 },
    .{ .off = 0x378, .expect = 0x00000000 },
    .{ .off = 0x37c, .expect = 0x0000002a },
    .{ .off = 0x380, .expect = 0x00000000 },
    .{ .off = 0x384, .expect = 0x00000000 },
    .{ .off = 0x388, .expect = 0x0000000a },
    .{ .off = 0x38c, .expect = 0x00000000 },
    .{ .off = 0x390, .expect = 0x00000000 },
    .{ .off = 0x394, .expect = 0x00000000 },
    .{ .off = 0x398, .expect = 0x00000046 },
    .{ .off = 0x39c, .expect = 0x00000000 },
    .{ .off = 0x3a0, .expect = 0x000000ff },
    .{ .off = 0x3a4, .expect = 0x00000000 },
    .{ .off = 0x3a8, .expect = 0x00000000 },
    .{ .off = 0x3ac, .expect = 0x00000000 },
    .{ .off = 0x3b0, .expect = 0x00000000 },
    .{ .off = 0x3b4, .expect = 0x00000000 },
    .{ .off = 0x3b8, .expect = 0x00000055 },
    .{ .off = 0x3bc, .expect = 0x000000ff },
    .{ .off = 0x3c0, .expect = 0x00000000 },
    .{ .off = 0x3c4, .expect = 0x00000000 },
    .{ .off = 0x3c8, .expect = 0x00000000 },
    .{ .off = 0x3cc, .expect = 0x00000000 },
    .{ .off = 0x3d0, .expect = 0x00000000 },
    .{ .off = 0x3d4, .expect = 0x00000000 },
    .{ .off = 0x3d8, .expect = 0x00000000 },
    .{ .off = 0x3dc, .expect = 0x00000000 },
    .{ .off = 0x3e0, .expect = 0x000000ff },
    .{ .off = 0x3e4, .expect = 0x000000ff },
    .{ .off = 0x3e8, .expect = 0x000000ff },
    .{ .off = 0x3ec, .expect = 0x00000000 },
    .{ .off = 0x3f0, .expect = 0x00000000 },
    .{ .off = 0x3f4, .expect = 0x00000000 },
    .{ .off = 0x3f8, .expect = 0x00000000 },
    .{ .off = 0x3fc, .expect = 0x0000002a },
    .{ .off = 0x400, .expect = 0x00000000 },
    .{ .off = 0x404, .expect = 0x00000000 },
    .{ .off = 0x408, .expect = 0x0000008a },
    .{ .off = 0x40c, .expect = 0x00000000 },
    .{ .off = 0x410, .expect = 0x00000000 },
    .{ .off = 0x414, .expect = 0x00000000 },
    .{ .off = 0x418, .expect = 0x00000041 },
    .{ .off = 0x41c, .expect = 0x00000000 },
    .{ .off = 0x420, .expect = 0x000000ff },
    .{ .off = 0x424, .expect = 0x00000000 },
    .{ .off = 0x428, .expect = 0x00000000 },
    .{ .off = 0x42c, .expect = 0x00000000 },
    .{ .off = 0x430, .expect = 0x00000000 },
    .{ .off = 0x434, .expect = 0x00000000 },
    .{ .off = 0x438, .expect = 0x00000055 },
    .{ .off = 0x43c, .expect = 0x000000ff },
    .{ .off = 0x440, .expect = 0x00000000 },
    .{ .off = 0x444, .expect = 0x00000000 },
    .{ .off = 0x448, .expect = 0x00000000 },
    .{ .off = 0x44c, .expect = 0x00000000 },
    .{ .off = 0x450, .expect = 0x00000000 },
    .{ .off = 0x454, .expect = 0x00000000 },
    .{ .off = 0x458, .expect = 0x00000000 },
    .{ .off = 0x45c, .expect = 0x00000000 },
    .{ .off = 0x460, .expect = 0x000000ff },
    .{ .off = 0x464, .expect = 0x000000ff },
    .{ .off = 0x468, .expect = 0x000000ff },
    .{ .off = 0x46c, .expect = 0x00000000 },
    .{ .off = 0x470, .expect = 0x00000000 },
    .{ .off = 0x474, .expect = 0x00000000 },
    .{ .off = 0x478, .expect = 0x00000000 },
    .{ .off = 0x47c, .expect = 0x0000002a },
};

export fn sheng_mdss_phy1_lane_sweep(phy_base: usize) callconv(.c) i64 {
    var count: u32 = 0;
    var first: u32 = 0xffff;
    for (phy1_lane_sweep_table) |e| {
        if (mmioRead32(phy_base, e.off) != e.expect) {
            if (first == 0xffff) first = @intCast(e.off);
            count += 1;
        }
    }
    return (@as(i64, first) << 32) | @as(i64, count);
}

export fn sheng_mdss_phy_status_raw(phy0_base: usize, phy1_base: usize) callconv(.c) i64 {
    const a = mmioRead32(phy0_base, 0x140) & 0xffff;
    const b = mmioRead32(phy0_base, 0x144) & 0xffff;
    const c = mmioRead32(phy1_base, 0x140) & 0xffff;
    const d = mmioRead32(phy1_base, 0x144) & 0xffff;
    return (@as(i64, a) << 48) | (@as(i64, b) << 32) |
        (@as(i64, c) << 16) | @as(i64, d);
}

export fn sheng_mdss_phy1_cmn_sweep(phy_base: usize) callconv(.c) i64 {
    var count: u32 = 0;
    var first: u32 = 0xffff;
    for (phy1_cmn_sweep_table) |e| {
        if (mmioRead32(phy_base, e.off) != e.expect) {
            if (first == 0xffff) first = @intCast(e.off);
            count += 1;
        }
    }
    return (@as(i64, first) << 32) | @as(i64, count);
}

export fn sheng_mdss_phy_cmn_sweep(phy_base: usize) callconv(.c) i64 {
    var count: u32 = 0;
    var first: u32 = 0xffff;
    for (cmn_sweep_table) |e| {
        if (mmioRead32(phy_base, e.off) != e.expect) {
            if (first == 0xffff) first = @intCast(e.off);
            count += 1;
        }
    }
    return (@as(i64, first) << 32) | @as(i64, count);
}

export fn sheng_mdss_phy_audit(phy_base: usize, is_master: bool) callconv(.c) i64 {
    var mask: u64 = 0;
    for (phy_audit_table, 0..) |e, i| {
        // The slave PHY is deliberately NOT configured like the master:
        // the working kernel writes neither CMN_CLK_CFG0 (0x010) nor any
        // of the PLL sub-block (>= 0x500) on PHY1, so those entries are
        // don't-care there. Checking them would only re-measure our own
        // writes. See sheng_mdss_dsi_phy_init().
        // The slave PHY is deliberately configured differently, so several
        // master-derived expectations do not apply to it:
        //   0x010 CLK_CFG0   -- never written on the slave
        //   0x03c PLL_CNTRL  -- slave PLL is never started (0x00, not 0x01)
        //   >=0x500 PLL      -- slave PLL rate block is never programmed
        //   0x140 PHY_STATUS -- slave legitimately reads 0x19, not 0x1F.
        //     Verified by reading it under a WORKING Linux display while
        //     the slave PLL was not started: 0x19. An earlier 0x1F
        //     "reference" for this register was taken while OUR OWN U-Boot
        //     had started the slave PLL, so it measured our own effect.
        //     Status registers are only valid references when the
        //     configuration at read time matches the one being compared.
        if (!is_master and (e.off == 0x010 or e.off == 0x03c or
            e.off == 0x140 or e.off >= 0x500)) continue;
        if (mmioRead32(phy_base, e.off) != e.expect) mask |= (@as(u64, 1) << @intCast(i));
    }
    const clk_cfg1_expect: u32 = if (is_master) 0x30 else 0x34;
    if (mmioRead32(phy_base, CMN_CLK_CFG1) != clk_cfg1_expect)
        mask |= @as(u64, 1) << PHY_AUDIT_CLK_CFG1_BIT;
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
