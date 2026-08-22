// SPDX-License-Identifier: GPL-2.0+
//
// MDSS/DISPCC/DSI/DPU register sequencing for SM8550, called from the
// UCLASS_VIDEO driver in sheng_mdss.c.
//
// Freestanding: no libc, no allocator. Every function takes its MMIO
// base from the caller. The only calls back into U-Boot are udelay(),
// flush_dcache_range() and timer_get_us().
//
// See ARCHITECTURE.md for the bring-up order and the clock tree.

const ENOSYS: c_int = -38;

// nt36532e init sequence, from the panel driver's own table. Sent to
// DSI0 only -- qcom,sync-dual-dsi mirrors each write to DSI1 in
// hardware. Every entry is a short DCS write.
//
// Stops before "Enable DSC" (0x90 0x03). From there on -- DSC enable,
// PPS, 0x9d, framerate, exit-sleep, display-on -- the sequence is not
// static bytes, so dsiPanelInit() issues it explicitly.
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
/// Packed the same way drm_dsc_pps_payload_pack() and
/// drm_dsc_compute_rc_parameters() do, against the DSC 1.1
/// rc_parameters_pre_scr table for bpp=8 bpc=8.
///
/// Sent as a MIPI_DSI_PICTURE_PARAMETER_SET (type 0x0A) long packet,
/// not a generic DCS long write.
pub const nt36532e_pps_144hz = [128]u8{
    // pic_height is PPS6-7, pic_width is PPS8-9. pic_width must be 3048:
    // the panel is ONE 3048-wide display driven across both links, so its
    // decoder has to be told the full width even though each encoder
    // handles 2 slices of 762.
    //
    // The PPS is a transmitted blob, not a register, so
    // sheng_mdss_verify_pipeline() cannot check it against the DPU-side
    // encoder config. If the two disagree the panel receives a stream it
    // cannot decode and shows black with every register reading correct.
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

// Linked in from the rest of the U-Boot binary.
extern fn udelay(usec: c_ulong) callconv(.c) void;
extern fn flush_dcache_range(start: usize, stop: usize) callconv(.c) void;
/// Microsecond timer, used to time command DMA in bbCmdTrace().
extern fn timer_get_us() callconv(.c) c_ulong;

// ===========================================================================
// ULTRA-DEBUG BLACKBOX
// ===========================================================================
//
// An ASCII log in a fixed DRAM window, read back from Linux through
// /dev/mem. The other channel -- sheng.* on the kernel command line --
// is capped at 512 bytes by CONFIG_SYS_CBSIZE; this one holds ~512KB.
//
// ASCII on purpose: `dd | strings` reads it with no decoder to keep in
// sync with the emitter.
//
// Layout at BB_BASE:
//   +0  u32 magic 'SHGB'  -- written LAST, so a torn/partial log is
//                            detectable rather than silently half-read
//   +4  u32 byte length of the payload
//   +8  u32 overflow flag (payload was truncated at BB_CAP)
//   +12 u32 reserved
//   +16 payload, NUL-padded ASCII
//
// 0xa5000000 clears the framebuffer (ends ~0xa4b10000) and sits inside
// free System RAM. Linux would allocate over it, so the kernel DT
// reserves it too; the magic check catches a clobber either way.
const BB_BASE: usize = 0xa5000000;
const BB_MAGIC: u32 = 0x53484742; // 'SHGB'
const BB_HDR: usize = 16;
const BB_CAP: usize = 512 * 1024;

var g_bb_len: usize = 0;
var g_bb_on: bool = false;
var g_bb_overflow: bool = false;

fn bbByte(c: u8) void {
    if (!g_bb_on) return;
    if (g_bb_len >= BB_CAP - BB_HDR) {
        g_bb_overflow = true;
        return;
    }
    const p: *volatile u8 = @ptrFromInt(BB_BASE + BB_HDR + g_bb_len);
    p.* = c;
    g_bb_len += 1;
}

fn bbStr(s: []const u8) void {
    for (s) |c| bbByte(c);
}

var g_bb_flushed: usize = 0;
var g_cmd_trace_n: u32 = 0;
var g_timeout_logged: u32 = 0;
var g_intr_at_dma_done: u32 = 0;

/// One compact line per DCS command. Columns are chosen so the whole
/// 87-command init fits in a screen and a change mid-sequence stands out:
///
///   cmd <n> len=<l> pre=<STATUS0>/<LANE> mid=<STATUS0>/<LANE>/<FIFO>
///           post=<STATUS0>/<LANE> ack=<ACK_ERR> r0=<ret0> r1=<ret1>
///
/// LANE bits 0-4 are per-lane STOPSTATE. "mid" is sampled between the DMA
/// trigger and the completion poll, so mid LANE = 0x1f1f (everything still
/// parked) while the engine reports success is the smoking gun for a
/// command that was accepted but never transmitted.
fn bbCmdTrace(n: u32, len: usize, t_us: u32, st_pre: u32, lane_pre: u32,
    st_mid: u32, lane_mid: u32, fifo_mid: u32, st_post: u32, lane_post: u32,
    ack: u32, r0: c_int, r1: c_int) void {
    bbStr("cmd ");
    bbDec(n);
    bbStr(" len=");
    bbDec(len);
    // THE DISCRIMINATOR. A short packet in LP escape mode cannot physically
    // clock out in less than a few microseconds; the 132-byte PPS packet
    // needs on the order of 100us. A transfer that "completes" in ~0us moved
    // no bytes, however cleanly the engine reported success. This is the one
    // measurement that separates "the DMA drained its FIFO" from "the packet
    // went on the wire", and it needs no external hardware.
    bbStr(" us=");
    bbDec(t_us);
    bbStr(" pre=");
    bbHex(st_pre, 2);
    bbByte('/');
    bbHex(lane_pre, 4);
    bbStr(" mid=");
    bbHex(st_mid, 2);
    bbByte('/');
    bbHex(lane_mid, 4);
    bbByte('/');
    bbHex(fifo_mid, 8);
    bbStr(" post=");
    bbHex(st_post, 2);
    bbByte('/');
    bbHex(lane_post, 4);
    bbStr(" ack=");
    bbHex(ack, 8);
    bbStr(" r=");
    bbDec(@intCast(if (r0 < 0) -r0 else r0));
    bbByte(',');
    bbDec(@intCast(if (r1 < 0) -r1 else r1));
    bbByte('\n');
    bbSeal();
}

/// Make everything written so far readable, RIGHT NOW.
///
/// The first version of this only sealed in sheng_bb_finish() at the end of
/// probe, which made the log unreadable in precisely the situation it
/// exists for: b74 wrote its payload correctly (0xa5000010 read back
/// "=== SHEN") but probe returned early, finish() never ran, the header
/// stayed zero, and the reader refused it as clobbered.
///
/// So seal after every record instead. The header is 3 words and the
/// flush is incremental -- only the bytes appended since the last seal --
/// so this stays cheap even across the big register-block dumps. The magic
/// is still written after the length, so a reader can never see a length
/// that is longer than the data actually flushed.
fn bbSeal() void {
    if (!g_bb_on) return;

    if (g_bb_len > g_bb_flushed) {
        flush_dcache_range(BB_BASE + BB_HDR + g_bb_flushed,
            BB_BASE + BB_HDR + g_bb_len + 64);
        g_bb_flushed = g_bb_len;
    }

    const len_p: *volatile u32 = @ptrFromInt(BB_BASE + 4);
    len_p.* = @truncate(g_bb_len);
    const ov_p: *volatile u32 = @ptrFromInt(BB_BASE + 8);
    ov_p.* = if (g_bb_overflow) 1 else 0;
    const magic_p: *volatile u32 = @ptrFromInt(BB_BASE);
    magic_p.* = BB_MAGIC;
    flush_dcache_range(BB_BASE, BB_BASE + 64);
}

fn bbCStr(s: [*:0]const u8) void {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) bbByte(s[i]);
}

fn bbHex(v: u64, digits: usize) void {
    var i = digits;
    while (i > 0) {
        i -= 1;
        const nib: u8 = @truncate((v >> @intCast(i * 4)) & 0xf);
        bbByte(if (nib < 10) '0' + nib else 'a' + (nib - 10));
    }
}

fn bbDec(v: u64) void {
    if (v >= 10) bbDec(v / 10);
    bbByte('0' + @as(u8, @truncate(v % 10)));
}

/// Arm the blackbox. Safe to call before any MDSS clock is up -- it only
/// touches DRAM.
export fn sheng_bb_init() callconv(.c) void {
    g_bb_on = true;
    g_bb_len = 0;
    g_bb_overflow = false;
    // Invalidate the magic immediately so a stale log from the PREVIOUS
    // boot can never be mistaken for this one's.
    const m: *volatile u32 = @ptrFromInt(BB_BASE);
    m.* = 0;
    bbStr("=== SHENG U-BOOT BLACKBOX ===\n");
}

/// Bare marker: "> name\n". Use liberally to trace control flow.
export fn sheng_bb_mark(name: [*:0]const u8) callconv(.c) void {
    bbStr("> ");
    bbCStr(name);
    bbByte('\n');
    bbSeal();
}

/// "name = 0x<hex> (<dec>)\n"
export fn sheng_bb_val(name: [*:0]const u8, v: u64) callconv(.c) void {
    bbStr("  ");
    bbCStr(name);
    bbStr(" = 0x");
    bbHex(v, 8);
    bbStr(" (");
    bbDec(v);
    bbStr(")\n");
    bbSeal();
}

/// Signed variant, for the -(10000+idx) style error returns.
export fn sheng_bb_sval(name: [*:0]const u8, v: i64) callconv(.c) void {
    bbStr("  ");
    bbCStr(name);
    bbStr(" = ");
    if (v < 0) {
        bbByte('-');
        bbDec(@intCast(-v));
    } else bbDec(@intCast(v));
    bbByte('\n');
    bbSeal();
}

/// Single register read: "name[off] = value".
export fn sheng_bb_reg(name: [*:0]const u8, base: usize, off: usize) callconv(.c) void {
    const v = mmioRead32(base, off);
    bbStr("  ");
    bbCStr(name);
    bbStr("[0x");
    bbHex(off, 3);
    bbStr("] = 0x");
    bbHex(v, 8);
    bbByte('\n');
    bbSeal();
}

/// Dump a whole register block, 8 values per line, offsets labelled. This
/// is the thing the 512-byte cmdline could never carry: actual values
/// rather than "first mismatch + count".
export fn sheng_bb_block(name: [*:0]const u8, base: usize, start: usize, count: usize) callconv(.c) void {
    bbStr("--- ");
    bbCStr(name);
    bbStr(" base=0x");
    bbHex(base, 8);
    bbStr(" start=0x");
    bbHex(start, 3);
    bbStr(" count=");
    bbDec(count);
    bbByte('\n');
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = start + i * 4;
        if (i % 8 == 0) {
            bbStr("  0x");
            bbHex(off, 3);
            bbByte(':');
        }
        bbByte(' ');
        bbHex(mmioRead32(base, off), 8);
        if (i % 8 == 7) bbByte('\n');
    }
    if (count % 8 != 0) bbByte('\n');
    bbSeal();
}

/// Seal the log: write length, overflow flag, then the magic last, and
/// flush the whole thing out of the CPU's caches so Linux (which reads it
/// through a fresh mapping after a reboot) sees the real DRAM contents.
export fn sheng_bb_finish() callconv(.c) void {
    if (!g_bb_on) return;
    bbStr("=== END len=");
    bbDec(g_bb_len);
    if (g_bb_overflow) bbStr(" OVERFLOW");
    bbStr(" ===\n");

    const len_p: *volatile u32 = @ptrFromInt(BB_BASE + 4);
    len_p.* = @truncate(g_bb_len);
    const ov_p: *volatile u32 = @ptrFromInt(BB_BASE + 8);
    ov_p.* = if (g_bb_overflow) 1 else 0;
    const magic_p: *volatile u32 = @ptrFromInt(BB_BASE);
    magic_p.* = BB_MAGIC;

    flush_dcache_range(BB_BASE, BB_BASE + BB_HDR + g_bb_len + 64);
}

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

// DISP_CC_MDSS_CORE_BCR. Only .reg is set in the kernel's reset map, so
// the mask is BIT(0).
//
// msm_mdss_init() pulses this first, before GDSC and before any clock is
// parsed. It is a plain write into DISPCC, which is reachable pre-GDSC
// because the AHB config path rides the always-on GCC_DISP_AHB_CLK, so
// nothing in the power sequence blocks doing it this early.
const MDSS_CORE_BCR_OFFSET: usize = 0x8000;
const MDSS_CORE_BCR_MASK: u32 = 1 << 0;

/// Assert then deassert DISP_CC_MDSS_CORE_BCR. Held ~20ms -- the reset
/// needs roughly one frame to take.
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

/// gdsc_disable()'s GDSC_OFF path: hand control back from hardware
/// trigger mode, assert SW_COLLAPSE, settle. Fixed delay rather than a
/// poll -- there is no documented OFF status bit.
///
/// Used for a real cold-start power cycle so the logic gates start from
/// power-on defaults rather than whatever ABL left behind.
/// Power both DSI PHYs down. The safe part of a controller cold-start
/// this early in probe.
///
/// Do NOT call sheng_mdss_full_teardown() here instead. That is terminal
/// by construction -- it gates the DISPCC branches the rest of probe
/// needs and writes DPU registers that cannot complete with only
/// AHB-from-XO running. It hangs the board outright: no backlight, no
/// boot. Safe at handoff because nothing runs after it.
///
/// Why bother: bringing this hardware up on top of a live controller
/// does not work, and starting from a real power-down does. ABL hands
/// over a live controller.
export fn sheng_mdss_dsi_phys_off(dsi0_phy_base: usize, dsi1_phy_base: usize) callconv(.c) void {
    dsiPhyDisable(dsi0_phy_base);
    dsiPhyDisable(dsi1_phy_base);
}

/// Did MDSS_GDSC actually collapse?
///
/// gdsc_disable() asserts SW_COLLAPSE and settles but never checks. A
/// GDSC held up by another subsystem's vote just stays on, which makes
/// the whole cold-start pass a no-op and leaves ABL's controller state
/// intact underneath the bring-up.
///
/// Bit 31 of GDSCR is PWR_ON. Sampled at three points:
///   47:32  GDSCR before the collapse
///   31:16  GDSCR after the collapse (PWR_ON here == it never collapsed)
///   15:0   GDSCR after the subsequent re-enable
export fn sheng_mdss_gdsc_probe(dispcc_base: usize, slot: u32) callconv(.c) void {
    if (slot >= 3) return;
    g_gdsc_probe[slot] = mmioRead32(dispcc_base, MDSS_GDSC_OFFSET);
}

var g_gdsc_probe: [3]u32 = .{0} ** 3;

export fn sheng_mdss_gdsc_probe_result() callconv(.c) i64 {
    return (@as(i64, g_gdsc_probe[0] >> 16) << 32) |
        (@as(i64, g_gdsc_probe[1] >> 16) << 16) |
        @as(i64, g_gdsc_probe[2] >> 16);
}

/// Microseconds the GDSC took to actually drop PWR_ON, or 0xffffffff if
/// it NEVER collapsed. Read out via sheng_mdss_gdsc_collapse_us().
var g_gdsc_collapse_us: u32 = 0xffffffff;

export fn sheng_mdss_gdsc_collapse_us() callconv(.c) u32 {
    return g_gdsc_collapse_us;
}

const GDSC_PWR_ON: u32 = 1 << 31;
const GDSC_COLLAPSE_TIMEOUT_US: u32 = 20000;

export fn sheng_mdss_gdsc_disable(dispcc_base: usize) callconv(.c) void {
    mmioClearBits32(dispcc_base, MDSS_GDSC_OFFSET, HW_CONTROL_MASK);
    udelay(1);
    mmioSetBits32(dispcc_base, MDSS_GDSC_OFFSET, SW_COLLAPSE_MASK);

    // WAIT FOR IT, do not assume it. The old code asserted SW_COLLAPSE
    // and slept a flat 200us with no check, which is the difference
    // between a real cold start and a no-op: a GDSC still held up by
    // another subsystem's vote stays on, ABL's controller state
    // survives underneath the whole bring-up, and the result is the
    // intermittent glitched/black boot.
    //
    // Poll PWR_ON (GDSCR bit 31) instead, and record how long it took
    // so a marginal collapse is distinguishable from a healthy one and
    // from one that never happened at all.
    var waited: u32 = 0;
    while (waited < GDSC_COLLAPSE_TIMEOUT_US) : (waited += 1) {
        if ((mmioRead32(dispcc_base, MDSS_GDSC_OFFSET) & GDSC_PWR_ON) == 0) {
            g_gdsc_collapse_us = waited;
            break;
        }
        udelay(1);
    } else {
        g_gdsc_collapse_us = 0xffffffff;
    }

    // Settle after the rail is genuinely down, not instead of checking.
    udelay(200);
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

/// Bring up disp_cc_pll0 at its OPERATING rate, L=0x50 alpha=0x5000:
///
///     19.2MHz * (80 + 0x5000/0x10000) = 1542 MHz, /3 = 514 MHz mdp_clk
///
/// Do NOT use disp_cc_pll0_config from dispcc-sm8550.c (l=0xd,
/// alpha=0x6492). That is the kernel's INITIAL config, applied once at
/// probe; it reprograms L/ALPHA later when mdp_clk_src requests its
/// frequency. Those values give a 257MHz parent and an 85.7MHz mdp_clk,
/// six times too slow.
///
/// A slow mdp_clk starves the link: the DPU cannot composite fast enough
/// to feed the DSI and the lane FIFOs run dry -- FIFO_STATUS 0x11111210
/// instead of 0x00001210 -- while every configuration register still
/// reads back correct and the INTF keeps counting frames, because INTF
/// timing comes off the DSI PHY PLL and does not depend on mdp_clk.
fn dispCcPll0Enable(dispcc_base: usize) c_int {
    mmioWrite32(dispcc_base, PLL_L_VAL_OFF, 0x50 |
        (TRION_PLL_CAL_VAL << LUCID_EVO_PLL_CAL_L_VAL_SHIFT) |
        (TRION_PLL_CAL_VAL << LUCID_OLE_PLL_RINGOSC_CAL_L_VAL_SHIFT));
    mmioWrite32(dispcc_base, PLL_ALPHA_VAL_OFF, 0x5000);
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

// The DPU's own DT node lists six clocks: bus, nrt_bus, iface, lut,
// core, vsync. dpu_runtime_resume() enables all of them before reading
// the DPU HW_VERSION register. iface (AHB) and core (MDP) are not
// enough for the DPU sub-block even though the wrapper works without
// the rest.
//
// mdp_lut branches off the same RCG as MDP_CLK, so it needs only a CBCR
// enable. vsync has its own HID-only RCG at 0x80f0 and runs at 19.2MHz,
// XO passthrough.
const MDP_LUT_CLK_CBCR: usize = 0x8018;

const VSYNC_CLK_SRC_CMD_RCGR: usize = 0x80f0;
const VSYNC_CLK_CBCR: usize = 0x8024;
const VSYNC_CLK_SRC_SEL_XO: u32 = 0;
const VSYNC_CLK_DIV_REG_VAL: u32 = 1; // F(19200000, P_BI_TCXO, 1, 0, 0) -> 2*1-1

// The eight DSI link clocks: byte0/1, byte0/1_intf, pclk0/1, esc0/1.
// pclk drives INTF_FRAME_COUNT and INTF_LINE_COUNT, not MDP_CLK -- with
// these off the frame counters sit at 0 no matter what MDP_CLK does.
//
// Source selects from disp_cc_parent_map_2: DSI0 DSICLK=1, DSI0
// BYTECLK=2, DSI1 DSICLK=3, DSI1 BYTECLK=4.
//
// Must run AFTER both PHY PLLs lock, unlike the PLL0-sourced clocks
// above which do not depend on the DSI PHY at all.
const PCLK0_CLK_SRC_CMD_RCGR: usize = 0x80a8;
const PCLK0_CLK_CBCR: usize = 0x8004;
const PCLK0_SRC_SEL_DSI0_DSICLK: u32 = 1;
const PCLK1_CLK_SRC_CMD_RCGR: usize = 0x80c0;
const PCLK1_CLK_CBCR: usize = 0x8008;
/// DSI1's pixel and byte clocks parent to DSI **0**'s PHY PLL, not its
/// own. Both halves of a stitched panel must be clocked from ONE source
/// -- that is what qcom,sync-dual-dsi and BITCLK_SEL=1 on the slave PHY
/// exist for.
///
/// The two PHY PLLs are independent oscillators. Configured identically
/// they run at the same nominal rate with arbitrary phase and their own
/// drift, so feeding DSI1's packetiser from the second one breaks the
/// lock-step the DDIC depends on.
///
/// Live reference, all four sourcing DSI0:
///     pclk0/pclk1 CFG=0x00000101 src_sel=1
///     byte0/byte1 CFG=0x00000201 src_sel=2
const PCLK1_SRC_SEL_DSI1_DSICLK: u32 = 1; // DSI0_PHY_PLL_OUT_DSICLK -- master's PLL
const BYTE0_CLK_SRC_CMD_RCGR: usize = 0x8108;
const BYTE0_CLK_CBCR: usize = 0x8028;
const BYTE0_INTF_CLK_CBCR: usize = 0x802c;
// Byte-interface dividers, the parents of byte{0,1}_intf_clk. The
// kernel runs byte_intf at byte_clk / 2. clk_regmap_div encodes
// (divisor - 1), so /2 is 1.
//
// Enabling the branches without programming these leaves whatever ABL
// left -- most likely 0, running the byte interface at twice its
// intended rate. Standalone registers, so no RCG CFG audit covers
// them.
const BYTE0_DIV_CLK_SRC: usize = 0x8120;
const BYTE1_DIV_CLK_SRC: usize = 0x813c;
const BYTE_DIV_WIDTH_MASK: u32 = 0xf; // width 4, shift 0
const BYTE_DIV_BY_2: u32 = 1; // clk_regmap_div encodes (divisor - 1)
const BYTE0_SRC_SEL_DSI0_BYTECLK: u32 = 2;
const BYTE1_CLK_SRC_CMD_RCGR: usize = 0x8124;
const BYTE1_CLK_CBCR: usize = 0x8030;
const BYTE1_INTF_CLK_CBCR: usize = 0x8034;
const BYTE1_SRC_SEL_DSI1_BYTECLK: u32 = 2; // DSI0_PHY_PLL_OUT_BYTECLK -- master's PLL, see PCLK1_SRC_SEL_DSI1_DSICLK
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
    // byte_intf divider (/2) BEFORE enabling its branch -- see
    // BYTE0_DIV_CLK_SRC's comment.
    {
        var d = mmioRead32(dispcc_base, BYTE0_DIV_CLK_SRC);
        d = (d & ~BYTE_DIV_WIDTH_MASK) | BYTE_DIV_BY_2;
        mmioWrite32(dispcc_base, BYTE0_DIV_CLK_SRC, d);
    }
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
    {
        var d = mmioRead32(dispcc_base, BYTE1_DIV_CLK_SRC);
        d = (d & ~BYTE_DIV_WIDTH_MASK) | BYTE_DIV_BY_2;
        mmioWrite32(dispcc_base, BYTE1_DIV_CLK_SRC, d);
    }
    ret = clkBranchEnable(dispcc_base, BYTE1_INTF_CLK_CBCR);
    if (ret != 0) return ret;

    ret = rcg2ConfigureHidOnly(dispcc_base, ESC1_CLK_SRC_CMD_RCGR, ESC_SRC_SEL_XO, DSI_CLK_DIV_REG_VAL_PASSTHROUGH);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, ESC1_CLK_CBCR);
}

// The MDSS wrapper node declares resets = <&dispcc
// DISP_CC_MDSS_CORE_BCR>, a bit0 read-modify-write at dispcc+0x8000.
// msm_mdss_init() asserts it first thing, holds ~20ms, deasserts --
// before the mdss mmio is ioremapped, before any clock is enabled.
//
// This covers the shared MDSS-wide block. Each host's own DSI_RESET
// (0x114) only resets that host's local state, so it is not a
// substitute.
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

/// AHB branch only: no PLL0, no MDP/LUT/VSYNC, and NO core reset.
///
/// Exists so the abl_state*() reads can touch MDSS registers safely
/// before this driver tears ABL's configuration down. Those reads need
/// MDSS_GDSC powered and the AHB config clock running; without both the
/// AHB slave never acks and the CPU wedges -- no backlight, no boot.
///
/// AHB_CLK_SRC parents from XO, so this needs no PLL bring-up, and it
/// reconfigures nothing, so what gets sampled afterwards is genuinely
/// ABL's state.
export fn sheng_mdss_dispcc_ahb_only(dispcc_base: usize) callconv(.c) c_int {
    const ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
}

/// Sample ABL's handoff state.
///
/// ABL uses continuous splash: it hands over with DPU, DSI, PHY and
/// panel all running. For the first few milliseconds of probe this
/// silicon is correctly driving this panel, and the cold start destroys
/// it. That state is a reference the Linux register dumps cannot give,
/// because Linux's numbers come after its own teardown and re-init with
/// its own clock tree, regulator votes and SMMU context.
///
/// DSI and PHY only, no DPU access -- VIDEO_MODE_ENGINE_BUSY (STATUS0
/// bit 3) plus a locked PLL is enough to say whether ABL is streaming.
///
/// abl1 = DSI0 CTRL << 32 | DSI0 STATUS0
export fn sheng_mdss_abl_state1(dsi0_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_CTRL)) << 32) |
        @as(i64, mmioRead32(dsi0_base, DSI_STATUS0));
}

/// abl2 = DSI0 FIFO_STATUS << 32 | DSI1 STATUS0
export fn sheng_mdss_abl_state2(dsi0_base: usize, dsi1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_FIFO_STATUS)) << 32) |
        @as(i64, mmioRead32(dsi1_base, DSI_STATUS0));
}

/// abl3 = [63:48] PHY0 PLL_CNTRL, [47:32] PHY0 PLL_COMMON_STATUS_ONE,
///        [31:16] PHY1 PLL_CNTRL, [15:0]  PHY1 PLL_COMMON_STATUS_ONE.
/// Live-while-Linux-drives reads 0x0001_0051_0001_0051 (both started, both
/// locked). If ABL hands over with these already set, its PHYs are live.
export fn sheng_mdss_abl_state3(phy0_base: usize, phy1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(phy0_base, CMN_PLL_CNTRL) & 0xffff) << 48) |
        (@as(i64, mmioRead32(phy0_base + PLL_BASE_OFFSET, PLL_COMMON_STATUS_ONE) & 0xffff) << 32) |
        (@as(i64, mmioRead32(phy1_base, CMN_PLL_CNTRL) & 0xffff) << 16) |
        @as(i64, mmioRead32(phy1_base + PLL_BASE_OFFSET, PLL_COMMON_STATUS_ONE) & 0xffff);
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

// --- DSI PHY. SM8550 uses the "7nm" driver code despite the DT label
// saying 4nm, on the V5_2 quirk path.
//
// The PHY is THREE separate reg entries, not sub-regions of one window:
//     phy   +0x000 len 0x200   CMN_*
//     lane  +0x200 len 0x280   LN_*, strided per lane
//     pll   +0x500 len 0x400   PLL_*
// Guessing contiguous sub-regions puts every PLL write into the lane
// block, and the PLL never locks because none of its registers are ever
// touched.
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
/// The PLL's OUTPUT DIVIDER, distinct from PLL_OUTDIV (0x0a8) above.
/// dsi_7nm_pll_restore_state() read-modify-writes it:
///
///     val = readl(pll_base + REG_DSI_7nm_PHY_PLL_PLL_OUTDIV_RATE);
///     val &= ~0x3;
///     val |= cached->pll_out_div;
///     writel(val, pll_base + REG_DSI_7nm_PHY_PLL_PLL_OUTDIV_RATE);
///
/// Wants 0: the divider is bypassed, and that is what both PHYs read on
/// a live system. Left unwritten it holds whatever ABL or POR leaves,
/// and nonzero low bits divide the PLL output and put the whole link
/// off-rate.
const PLL_PLL_OUTDIV_RATE: usize = 0x154;
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
// CORRECTED against live silicon (SPEC.md task #5 log): computed offline
// as 0x877, but this device's own PHY reads FRAC_DIV_START_LOW_1 = 0x78 /
// MID_1 = 0x08 on BOTH PHYs while Linux drives the panel, i.e. 0x878. A
// one-LSB VCO difference is not going to be the black screen, but the
// whole method here is to match measured silicon rather than our own
// arithmetic, and this is a free correction.
const PLL_FRAC_DIV_START: u32 = 0x878;
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
    // PLL output divider: clear the low 2 bits (divider bypassed), matching
    // dsi_7nm_pll_restore_state()'s RMW with cached pll_out_div == 0.
    mmioWrite32(pll, PLL_PLL_OUTDIV_RATE, mmioRead32(pll, PLL_PLL_OUTDIV_RATE) & ~@as(u32, 0x3));
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
fn dsiPhyDigReset(phy_base: usize) void {
    mmioWrite32(phy_base, CMN_GLBL_DIGTOP_SPARE4, 0x1);
    mmioWrite32(phy_base, CMN_GLBL_DIGTOP_SPARE4, 0x0);
}

fn dsiPhyEnableGlobalClk(phy_base: usize) void {
    mmioWrite32(phy_base, CMN_CTRL_3, 0x04);
    mmioSetBits32(phy_base, CMN_CLK_CFG1, CLK_CFG1_CLK_EN | CLK_CFG1_CLK_EN_SEL);
}

fn dsiPhyPllBias(phy_base: usize) void {
    mmioSetBits32(phy_base, CMN_CTRL_0, CTRL_0_PLL_SHUTDOWNB);
    mmioWrite32(phy_base + PLL_BASE_OFFSET, PLL_SYSTEM_MUXES, 0xc0);
    udelay(1);
}

/// Start both PHYs INTERLEAVED, not one then the other.
///
/// dsi_pll_7nm_vco_prepare() does not finish the master before touching
/// the slave; it alternates, one operation at a time:
///
///   P0cmn 024=7f  P0pll 528=c0     enable_pll_bias(MASTER)
///   P1cmn 024=7f  P1pll 528=c0     enable_pll_bias(SLAVE)
///   P0cmn 03c=1                    MASTER PLL START  (+ lock poll)
///   P0cmn 128=1/0                  dig_reset(master)
///   P1cmn 128=1/0                  dig_reset(slave)
///   ... then global_clk master, global_clk slave, RBUF master, RBUF slave
///
/// The slave's PLL bias goes up BEFORE the master's PLL starts, and the
/// slave's digital reset lands in the same window as the master's.
///
/// Running the master to completion first and only then starting the
/// slave leaves the slave reporting CMN_PHY_STATUS 0x19 against live
/// silicon's 0x1F -- bits 1 and 2 never assert -- with every CMN value
/// on the slave already correct. Ordering is the only variable.
export fn sheng_mdss_dsi_phy_start_dual(phy0_base: usize, phy1_base: usize) callconv(.c) c_int {
    dsiPhyPllBias(phy0_base);
    dsiPhyPllBias(phy1_base);

    const ret = dsiPhyPllStart(phy0_base);
    if (ret != 0) return ret;

    dsiPhyDigReset(phy0_base);
    dsiPhyDigReset(phy1_base);

    dsiPhyEnableGlobalClk(phy0_base);
    dsiPhyEnableGlobalClk(phy1_base);

    mmioWrite32(phy0_base, CMN_RBUF_CTRL, 0x1);
    mmioWrite32(phy1_base, CMN_RBUF_CTRL, 0x1);
    return 0;
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

/// Pulse DSI_PHY_RESET on BOTH hosts before either PHY is enabled.
///
/// dsi_mgr_phy_enable() does this for bonded setups specifically: "some
/// registers in PHY1 have been programmed during PLL0 clock's set_rate.
/// The PHY1 reset called by host1 here will silently reset those PHY1
/// registers. Therefore we need to reset and enable both PHYs before
/// any PLL clock operation."
///
/// DSI_PHY_RESET (0x128) lives in the DSI HOST's register block and
/// resets the connected PHY -- distinct from DSI_RESET (0x114), which
/// resets the host's own logic.
///
/// Must run before sheng_mdss_dsi_phy_init() for either PHY.
export fn sheng_mdss_dsi_reset_both_phys(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    mmioWrite32(dsi0_base, DSI_PHY_RESET, 1);
    mmioWrite32(dsi1_base, DSI_PHY_RESET, 1);
    udelay(1000);
    mmioWrite32(dsi0_base, DSI_PHY_RESET, 0);
    mmioWrite32(dsi1_base, DSI_PHY_RESET, 0);
}




/// PHY bases, remembered so the per-command PLL re-commit below can reach
/// them without threading them through every DCS call site.
var g_phy0_base: usize = 0;
var g_phy1_base: usize = 0;

/// Re-commit the PLL configuration before each DCS command.
///
/// msm_dsi_host_xfer_prepare() calls link_clk_set_rate() before EVERY
/// command, which lands in dsi_pll_7nm_vco_set_rate() and reruns the
/// whole rate configuration. Doing it once at bring-up is not the same
/// thing.
///
/// The values written match what is already in the registers, so no
/// register comparison can show the difference -- what it buys is
/// re-latching the configuration into the analog block.
///
/// Order: bias, commit rate, hz-independent config, slave
/// PERF_OPTIMIZE.
fn dsiPhyPllRecommit() void {
    if (g_phy0_base == 0) return;
    mmioSetBits32(g_phy0_base, CMN_CTRL_0, CTRL_0_PLL_SHUTDOWNB);
    mmioWrite32(g_phy0_base + PLL_BASE_OFFSET, PLL_SYSTEM_MUXES, 0xc0);
    dsiPhyPllCommitRate(g_phy0_base);
    dsiPhyPllConfigHzIndep(g_phy0_base);
    if (g_phy1_base != 0)
        mmioWrite32(g_phy1_base + PLL_BASE_OFFSET, PLL_PERF_OPTIMIZE, 0x22);
}

/// Bring one DSI PHY up: voltage swing, D-PHY timings, lane settings,
/// and on the master the PLL rate configuration.
///
/// is_master selects DSI0, which drives its own PLL. DSI1 is the slave
/// and takes its bit clock from DSI0 over the sync-dual-dsi link. Call
/// this for both, then sheng_mdss_dsi_phy_start_dual() once.
export fn sheng_mdss_dsi_phy_init(dsi_phy_base: usize, is_master: bool) callconv(.c) c_int {
    if (is_master) g_phy0_base = dsi_phy_base else g_phy1_base = dsi_phy_base;
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

    // CMN_CLK_CFG0 holds the PHY's two output dividers,
    // bit_clk_div | (pix_clk_div << 4). Leaving it at reset default
    // gives a correct byte clock -- that comes straight off the PLL --
    // and a pixel clock at the wrong divisor, so the DPU feeds the link
    // faster than it can transmit. FIFO_STATUS reads 0xdddd1211: MDP
    // FIFO overflow plus all four data lanes overflowing AND
    // underflowing at once.
    //
    // 0x61: pix_clk_div = 6, i.e. bitclk/6 = 198,453,024 Hz, which is
    // both dsi_get_pclk_rate()'s answer for this DSC bonded mode and
    // the plain bpp/lanes = 24/4 ratio.
    //
    // MASTER ONLY. The kernel writes this on PHY0 and never PHY1: the
    // slave takes the master's bit clock via CLK_CFG1.BITCLK_SEL, and
    // DISPCC's pclk1/byte1 source from DSI0's PLL, so the slave's own
    // dividers feed nothing.
    if (is_master) mmioWrite32(dsi_phy_base, CMN_CLK_CFG0, CMN_CLK_CFG0_VALUE);

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

    // Rate configuration only. The PLL START and the digital-reset /
    // global-clock / RBUF tail are interleaved across both PHYs, so they
    // live in sheng_mdss_dsi_phy_start_dual(), which the caller runs once
    // after BOTH phys have been through this function.
    //
    // Master only. The slave's PLL is never started -- the kernel writes
    // exactly two PLL registers on PHY1 (SYSTEM_MUXES, PERF_OPTIMIZE) and
    // sets its CMN_PLL_CNTRL to 0, never 1.
    //
    // Reading DSI1's PLL registers off a live device suggests otherwise:
    // they come back fully configured and locked. Those are OUR OWN
    // writes read back, which Linux never overwrites precisely because it
    // does not touch them. A live register read is only a valid reference
    // for registers Linux actually writes.
    if (is_master) {
        dsiPhyPllConfigure(dsi_phy_base);
    } else {
        // The slave's only PLL register outside the shared bias is
        // PERF_OPTIMIZE, which the kernel writes from the MASTER's
        // set_rate path (`if (pll->slave) writel(0x22, slave PERF_OPTIMIZE)`).
        mmioWrite32(dsi_phy_base + PLL_BASE_OFFSET, PLL_PERF_OPTIMIZE, 0x22);
    }

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
/// VID_CFG1 is 0x01c, NOT 0x010. The map jumps from VID_CFG0 (0x00c)
/// straight to 0x01c; 0x010 is not modelled at all.
///
/// Holds R_SEL(0) / G_SEL(4) / B_SEL(8) / RGB_SWAP(12:14). Linux writes
/// 0 here explicitly. Writing a channel-swap value into a DSC stream
/// scrambles the compressed bytes, the panel's decoder fails, and it
/// blanks with no error on the transmit side.
const DSI_VID_CFG1: usize = 0x01c;
/// The host's compression descriptor. Without it the host expects
/// uncompressed RGB at the programmed timing and real DSC data arriving
/// drives FIFO_STATUS to 0xdddd1219 -- VIDEO_MDP_FIFO overflow AND
/// underflow with all four lanes thrashing.
///
/// Harmless-looking while nothing is fetched: with CTL_FETCH_PIPE_ACTIVE
/// unset FIFO_STATUS reads a clean 0x00001210 because no data flows.
///
/// Live value, identical on both hosts:
///   WC(31:16)          = 0x05F4 = 1524 compressed bytes per line
///   DATATYPE(13:8)     = 0x0B   = MIPI compressed pixel stream
///   PKT_PER_LINE(7:6)  = 0
///   EOL_BYTE_NUM(5:4)  = 0
///   EN(0)              = 1
/// CHECKERED_RECTANGLE_PATTERN (bit8)
/// BPP = VIDEO_CONFIG_24BPP (1) | RGB (bit2)
/// VIDEO_PATTERN_SEL = VID_MDSS_GENERAL_PATTERN (3) at bits[5:4], EN bit0




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

// Captured live rather than recomputed. Several of these registers have
// real bits beyond their one documented field (LANE_SWAP_CTRL and
// EOT_PACKET_CTRL both do), and the D-PHY timings are ~100 lines of
// interdependent linear_inter() math. These are what a working Linux
// had programmed for this exact panel and PLL rate, identical on both
// hosts.
//
// Capture at base+4+offset, not base+offset. Reading at the unshifted
// address returns the register one slot before the intended one and
// every value comes out wrong but plausible.
//
// DST_FORMAT is RGB666 (1), not RGB888 -- DSC changes the wire packing
// regardless of source pixel depth.
const VID_CFG0_VALUE: u32 = 0x02009230;
const VID_CFG1_VALUE: u32 = 0x00000000; // live on both hosts; Linux writes 0 in dsi_ctrl_enable()
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

const CMD_DMA_CTRL_HS_VALUE: u32 = CMD_DMA_CTRL_VALUE & ~@as(u32, 1 << 26);

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

/// TRIG_CTRL for the panel-init phase only. Software trigger, nothing
/// else: no TE dependency, no frame-window wait.
///
/// TRIG_CTRL_VALUE above is Linux's live value, TE(31) |
/// BLOCK_DMA_WITHIN_FRAME(12) | DMA_TRIGGER(SW), and copying it here
/// deadlocks. Bit 12 is a hardware interlock that makes the command DMA
/// wait until the MDP is idle; bit 31 points it at a tear-effect pulse.
/// Both hold in Linux because its DPU is already streaming when it
/// sends panel commands.
///
/// Panel init runs BEFORE dpu_start(), so nothing generates frames, the
/// window never opens, and the engine asserts CMD_MODE_DMA_BUSY
/// forever. A correct value in a context where its precondition does
/// not hold.
const TRIG_CTRL_CMD_INIT_VALUE: u32 = TRIG_CTRL_DMA_TRIGGER_SW;

const CTRL_ENABLE: u32 = 1 << 0;
const CTRL_VID_MODE_EN: u32 = 1 << 1;
const CTRL_CMD_MODE_EN: u32 = 1 << 2;
const CTRL_CLK_EN: u32 = 1 << 8;
const STATUS0_CMD_MODE_DMA_BUSY: u32 = 1 << 1;
const STATUS0_VIDEO_MODE_ENGINE_BUSY: u32 = 1 << 3;

/// dsi_wait4video_eng_busy(): when the video engine is transmitting,
/// wait for the frame to finish and then sit 4ms inside the blanking
/// period before issuing a command. The kernel does this before EVERY
/// command:
///
///     if (!(mode_flags & MIPI_DSI_MODE_VIDEO)) return;
///     data = dsi_read(REG_DSI_STATUS0);
///     if (!(data & DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY)) return;
///     if (power_on && enabled) {
///             dsi_wait4video_done(msm_host);
///             mdelay(4);       /* delay 4 ms to skip BLLP */
///     }
///
/// Without it, DCS packets are injected into a link that is actively
/// transmitting video. The DMA still runs and still reports done, but
/// the packet collides with the video stream on the wire and the DDIC
/// never sees a well-formed command -- right bytes, wrong timing, and
/// nothing a register comparison can show.
///
/// VIDEO_DONE lives in INTR_CTRL, 0x10c.
///
/// Do NOT "correct" these offsets for the DSI6G shift. It is carried
/// entirely by SM8550_MDSS_DSI0_BASE; per-register offsets are used
/// as-is against the shifted base.
const INTR_VIDEO_DONE: u32 = 1 << 16;
const INTR_MASK_VIDEO_DONE: u32 = 1 << 17;
/// Status bits in INTR_CTRL are write-1-to-clear and the mask bits live in
/// the same register, so a read-modify-write must preserve the masks and
/// touch only the one status bit being acknowledged -- writing the whole
/// read-back value (what dsi_host_irq() does) would also clear CMD_DMA_DONE
/// and BTA_DONE as a side effect.
const INTR_MASK_BITS: u32 = (1 << 1) | (1 << 9) | (1 << 17) | (1 << 21) | (1 << 25);

/// REAL BUG FOUND (SPEC.md task #5 log): this waited for the WRONG EVENT.
///
/// dsi_wait4video_done() waits on the VIDEO_DONE interrupt, which fires at
/// the END OF A FRAME -- the start of vertical blanking -- and then sleeps
/// 4ms to land inside BLLP, where the host is willing to inject a command
/// packet into the video stream.
///
/// This function instead polled STATUS0.VIDEO_MODE_ENGINE_BUSY waiting for
/// it to go CLEAR. On a continuously streaming video-mode link that bit
/// essentially never clears: the engine is always busy. So every call
/// spun the full 70ms timeout and then fired the command at an arbitrary
/// point mid-frame.
///
/// Measured consequence (b71, SHENG_PANEL_AFTER_DPU=1, i.e. the first
/// build to send the init sequence while the DPU was actually streaming):
/// sheng.panel = -10000, meaning command #0 failed outright, and
/// sheng.rd1 = -1, the Set-Maximum-Return-Packet-Size DMA failing before
/// the read even started. With the DPU stopped the same code reported
/// success -- but the panel never received anything, so that "success"
/// was the engine draining its FIFO with no video context to inject into.
/// A command engine that reports done without transmitting is exactly the
/// symptom this whole investigation has been chasing.
var g_vwait_logged: u32 = 0;

fn dsiWait4VideoEngBusy(dsi_base: usize) void {
    const st = mmioRead32(dsi_base, DSI_STATUS0);
    if ((st & STATUS0_VIDEO_MODE_ENGINE_BUSY) == 0) {
        // Early return: video engine idle, no BLLP to wait for. Logged
        // because "we never even waited" and "we waited and it worked" are
        // completely different situations that both look like success.
        if (g_vwait_logged < 8 and dsi_base == 0x0ae94004) {
            g_vwait_logged += 1;
            bbStr("vwait: skip (video idle) st=");
            bbHex(st, 8);
            bbByte('\n');
            bbSeal();
        }
        return;
    }

    // ENABLE THE MASK FIRST. dsi_wait4video_done() calls
    // dsi_intr_ctrl(msm_host, DSI_IRQ_MASK_VIDEO_DONE, 1) before waiting
    // and clears it after; b72 polled the status bit without ever setting
    // the mask, and on this hardware the status bit does not latch while
    // the source is masked off -- so the poll could never succeed, spun the
    // full 70ms, and the command went out at an arbitrary point anyway.
    var intr = mmioRead32(dsi_base, DSI_INTR_CTRL);
    mmioWrite32(dsi_base, DSI_INTR_CTRL,
        (intr & INTR_MASK_BITS) | INTR_MASK_VIDEO_DONE | INTR_VIDEO_DONE);

    // 70ms, matching the kernel's wait_for_completion_timeout. One frame at
    // 144Hz is 6.9ms, so this is ~10 frames of headroom.
    var waited: u32 = 0;
    while (waited < 70000) : (waited += 10) {
        if ((mmioRead32(dsi_base, DSI_INTR_CTRL) & INTR_VIDEO_DONE) != 0) break;
        udelay(10);
    }

    // Ack the event and mask VIDEO_DONE off again, matching the kernel's
    // dsi_intr_ctrl(..., 0) on the way out.
    const vd_intr = mmioRead32(dsi_base, DSI_INTR_CTRL);
    if (g_vwait_logged < 8 and dsi_base == 0x0ae94004) {
        g_vwait_logged += 1;
        bbStr("vwait: waited_us=");
        bbDec(waited);
        bbStr(" VIDEO_DONE=");
        bbDec((vd_intr >> 16) & 1);
        bbStr(" intr=");
        bbHex(vd_intr, 8);
        bbStr(" st0=");
        bbHex(mmioRead32(dsi_base, DSI_STATUS0), 8);
        bbStr(" lane=");
        bbHex(mmioRead32(dsi_base, DSI_LANE_STATUS), 8);
        bbByte('\n');
        bbSeal();
    }

    intr = mmioRead32(dsi_base, DSI_INTR_CTRL);
    mmioWrite32(dsi_base, DSI_INTR_CTRL,
        (intr & INTR_MASK_BITS & ~INTR_MASK_VIDEO_DONE) | INTR_VIDEO_DONE);

    udelay(4000); // "delay 4 ms to skip BLLP"
}
const CLK_CTRL_ENABLE_CLKS: u32 = 0x3f | (1 << 9); // AHBS/AHBM/PCLK/DSICLK/BYTECLK/ESCCLK on + FORCE_ON_DYN_AHBM_HCLK
const TRIG_CTRL_DMA_TRIGGER_SW: u32 = 4; // dsi_cmd_trigger.TRIGGER_SW, low 3 bits
const TRIG_CTRL_TE: u32 = 1 << 31;

const DMA_BUSY_POLL_TIMEOUT_US: u32 = 20000; // 200ms, matching wait_for_completion_timeout in source

/// qcom,sm8550-dsi-phy-4nm has 4 data lanes wired (LANE0-3 = bits
/// 4-7 of DSI_CTRL) per the panel's `.lanes = 4` in
/// panel-novatek-nt36532e.c.
const CTRL_ALL_LANES: u32 = 0xf << 4;

fn dsiHostBringUp(dsi_base: usize) void {
    // ORDER MATTERS, and the end state does not show it. Program the
    // whole timing block BEFORE the software reset and before the
    // controller is enabled. Enabling a DSI controller that has no
    // active-window or compression configuration yet is a real
    // sequencing error, and the final register values are identical
    // either way -- no register comparison can catch it.
    //
    // The kernel's order, from its own writes:
    //
    //   0x29c compression, 0x020..0x034 timing   <- dsi_timing_setup()
    //   0x118 CLK_CTRL
    //   0x114 RESET 1 -> 0                       <- dsi_sw_reset()
    //   0x00c VID_CFG0, 0x01c VID_CFG1, 0x038 CMD_DMA_CTRL,
    //   0x080 TRIG_CTRL, 0x0c0 CLKOUT, 0x0c8 EOT,
    //   0x108 ERR_INT_MASK0, 0x10c INTR_CTRL, 0x118 CLK_CTRL,
    //   0x0ac LANE_SWAP                          <- dsi_ctrl_enable()
    //   0x000 CTRL = 0x1f1 then 0x1f3

    // --- dsi_timing_setup(): compression descriptor first, then timing.
    mmioWrite32(dsi_base, DSI_VIDEO_COMPRESSION_MODE_CTRL, VIDEO_COMPRESSION_MODE_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_H, ACTIVE_H_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_V, ACTIVE_V_VALUE);
    mmioWrite32(dsi_base, DSI_TOTAL, TOTAL_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_HSYNC, ACTIVE_HSYNC_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_VSYNC_HPOS, ACTIVE_VSYNC_HPOS_VALUE);
    mmioWrite32(dsi_base, DSI_ACTIVE_VSYNC_VPOS, ACTIVE_VSYNC_VPOS_VALUE);

    mmioWrite32(dsi_base, DSI_CLK_CTRL, CLK_CTRL_ENABLE_CLKS);

    // --- dsi_sw_reset(): "dsi controller can only be reset while clocks
    // are running", hence after CLK_CTRL above.
    mmioWrite32(dsi_base, DSI_RESET, 1);
    udelay(20000);
    mmioWrite32(dsi_base, DSI_RESET, 0);

    // --- dsi_ctrl_enable(): config registers, then the controller.
    mmioWrite32(dsi_base, DSI_VID_CFG0, VID_CFG0_VALUE);
    mmioWrite32(dsi_base, DSI_VID_CFG1, VID_CFG1_VALUE);
    mmioWrite32(dsi_base, DSI_CMD_DMA_CTRL, CMD_DMA_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_TRIG_CTRL, TRIG_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_CLKOUT_TIMING_CTRL, CLKOUT_TIMING_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_EOT_PACKET_CTRL, EOT_PACKET_CTRL_VALUE);
    mmioWrite32(dsi_base, DSI_ERR_INT_MASK0, DSI_ERR_INT_MASK0_VALUE);
    {
        var intr_ctrl = mmioRead32(dsi_base, DSI_INTR_CTRL);
        intr_ctrl |= DSI_IRQ_MASK_ERROR;
        mmioWrite32(dsi_base, DSI_INTR_CTRL, intr_ctrl);
    }
    mmioWrite32(dsi_base, DSI_CLK_CTRL, CLK_CTRL_ENABLE_CLKS);
    mmioWrite32(dsi_base, DSI_LANE_SWAP_CTRL, LANE_SWAP_CTRL_VALUE);

    // CTRL last: enable + lanes + clk, then add VID_MODE_EN, exactly the
    // 0x1f1 -> 0x1f3 pair the kernel writes.
    mmioWrite32(dsi_base, DSI_CTRL, CTRL_CLK_EN | CTRL_ALL_LANES | CTRL_ENABLE);
    mmioWrite32(dsi_base, DSI_CTRL, CTRL_CLK_EN | CTRL_ALL_LANES | CTRL_ENABLE | CTRL_VID_MODE_EN);
}

/// Switch the DSI host from command mode (used for the panel init DCS
/// blast) to video mode, matching dsi_op_mode_config(video_mode=true)
/// in dsi_host.c. Must happen before the DPU INTF timing engine starts
/// pushing continuous pixel data -- leaving CMD_MODE_EN set while the
/// DPU drives a live video timing engine into this controller is a
/// real hardware mode mismatch, not just "wrong colors".
fn dsiHostSwitchToVideoMode(dsi_base: usize) void {
    // dsiHostBringUp() now leaves the host in video mode already, matching
    // the kernel's own bring-up. This remains only to make the state
    // explicit at dpu_start() time; it must NOT re-write the timing block,
    // because doing so after the controller is enabled is precisely the
    // ordering error this rewrite removes.
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
/// FLUSH THE PACKET FIRST. Callers build it with plain CPU stores --
/// `volatile` constrains the compiler, not the data cache -- and this
/// engine reads physical DRAM with no coherency with the CPU. Skip the
/// flush and it transmits whatever stale bytes are in DRAM, computes a
/// valid CRC over them, and sends a well-formed meaningless packet: the
/// panel drops every command while every register reads correct.
/// flush_dcache_range() ends in its own dsb, so no extra barrier here.
///
/// OR IN CMD_MODE_EN|ENABLE, as msm_dsi_host_xfer_prepare() does. The
/// host is in VIDEO mode by the time this runs, so without it a read
/// goes out with CMD_MODE_EN clear and no bus turnaround is ever
/// attempted.
///
/// That failure is silent in a specific, misleading way: zero bytes
/// read AND zero timeout. A BTA that is genuinely attempted and gets no
/// answer times out. Both zero means we never asked.
fn dsiCmdDmaTxOne(dsi_base: usize, dma_addr: usize, len: usize) c_int {
    const restore = mmioRead32(dsi_base, DSI_CTRL);
    mmioWrite32(dsi_base, DSI_CTRL, restore | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    dsiCmdDmaTrigger(dsi_base, dma_addr, len);
    const ret = dsiCmdDmaWait(dsi_base);
    mmioWrite32(dsi_base, DSI_CTRL, restore);
    return ret;
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

    // DID THE DMA EVER ACTUALLY START? (SPEC.md task #5 log)
    //
    // dsiCmdDmaWait() polls for CMD_MODE_DMA_BUSY to be CLEAR and returns
    // success the instant it is. That is only a valid completion test if
    // the bit was ever SET. If the engine never starts, the bit never
    // asserts, the poll succeeds on its first read, and the command
    // reports success having transmitted nothing -- which would produce
    // exactly what we measure: sheng.panel = 0, sheng.retries = 0, no
    // timeouts anywhere, and a DDIC that is never configured.
    //
    // The kernel does not have this hole: dsi_cmd_dma_tx() waits on a
    // DMA-DONE INTERRUPT (a real completion event), not on a busy bit
    // going away.
    //
    // Sample STATUS0 immediately after TRIG_DMA, on DSI0, for the first
    // few commands. Bit1 set means the engine genuinely went busy and our
    // wait is meaningful. All-clear means every "successful" command in
    // this driver's history has been a no-op.
    if (g_trigger_probe_n < 4 and dsi_base == 0x0ae94004) {
        const st = mmioRead32(dsi_base, DSI_STATUS0);
        g_trigger_probe = (g_trigger_probe << 8) | @as(u32, @truncate(st & 0xff));
        g_trigger_probe_n += 1;
    }
}

var g_trigger_probe: u32 = 0;
var g_trigger_probe_n: u32 = 0;

/// Low byte of DSI0 STATUS0 sampled immediately after each of the first
/// four TRIG_DMA writes, packed oldest-first. CMD_MODE_DMA_BUSY is bit1,
/// so a healthy engine shows 0x02 in each byte. 0x00 throughout means the
/// DMA never went busy and our completion check is vacuous.
export fn sheng_mdss_dsi_trigger_probe() callconv(.c) u32 {
    return g_trigger_probe;
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
            // Capture INTR_CTRL BEFORE the clearing read-modify-write below.
            // Status bits here are write-1-to-clear, so writing back the
            // read-back value erases BTA_DONE (bit20) as a side effect --
            // meaning every previous look at BTA_DONE was taken AFTER our
            // own code had already wiped it. That is exactly the class of
            // self-inflicted blindness that made the silent read look like
            // evidence about the panel for months.
            g_intr_at_dma_done = mmioRead32(dsi_base, DSI_INTR_CTRL);
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

    // TIMEOUT FORENSICS (SPEC.md task #5 log).
    //
    // The failure has moved. With dsiWait4VideoEngBusy() finally waiting on
    // a real VIDEO_DONE (it needed MASK_VIDEO_DONE enabled -- polling the
    // status bit while masked could never succeed), commands are issued
    // inside BLLP the way the kernel issues them, and THIS is where they
    // now die: CMD_MODE_DMA_BUSY never clears, ACK_ERR stays 0, and the
    // retry path burns four attempts per command.
    //
    // "It timed out" is not enough to act on. Record the full picture at
    // the moment of failure, plus a short time-series of STATUS0/FIFO
    // taken DURING the poll, so we can distinguish:
    //   * DMA_BUSY set and never clearing  -> engine started, stalled
    //   * DMA_BUSY never setting at all    -> trigger never took
    //   * FIFO draining vs frozen          -> bytes moving or not
    // Only the first few timeouts are logged; 87 commands x 4 retries
    // would otherwise flood the buffer with identical lines.
    if (g_timeout_logged < 6) {
        // Time-series across the stall. "It timed out" says nothing about
        // WHERE it stalled: did DMA_BUSY ever set, did the FIFO drain, did
        // the lanes ever leave stop state? Sample all three so the shape of
        // the stall is visible instead of just its endpoint.
        bbStr("   series(st0/fifo/lane, 1ms apart):");
        var k: u32 = 0;
        while (k < 10) : (k += 1) {
            bbByte(' ');
            bbHex(mmioRead32(dsi_base, DSI_STATUS0) & 0xff, 2);
            bbByte('/');
            bbHex(mmioRead32(dsi_base, DSI_FIFO_STATUS), 8);
            bbByte('/');
            bbHex(mmioRead32(dsi_base, DSI_LANE_STATUS) & 0xffff, 4);
            udelay(1000);
        }
        bbByte('\n');
        bbSeal();

        g_timeout_logged += 1;
        bbStr("!! DMA TIMEOUT base=0x");
        bbHex(dsi_base, 8);
        bbByte('\n');
        bbStr("   STATUS0=0x");
        bbHex(mmioRead32(dsi_base, DSI_STATUS0), 8);
        bbStr(" FIFO=0x");
        bbHex(mmioRead32(dsi_base, DSI_FIFO_STATUS), 8);
        bbStr(" LANE=0x");
        bbHex(mmioRead32(dsi_base, DSI_LANE_STATUS), 8);
        bbByte('\n');
        bbStr("   CTRL=0x");
        bbHex(mmioRead32(dsi_base, DSI_CTRL), 8);
        bbStr(" ACK_ERR=0x");
        bbHex(mmioRead32(dsi_base, DSI_ACK_ERR_STATUS), 8);
        bbStr(" TIMEOUT=0x");
        bbHex(mmioRead32(dsi_base, DSI_TIMEOUT_STATUS), 8);
        bbByte('\n');
        bbStr("   INTR=0x");
        bbHex(mmioRead32(dsi_base, DSI_INTR_CTRL), 8);
        bbStr(" DMA_BASE=0x");
        bbHex(mmioRead32(dsi_base, DSI_DMA_BASE), 8);
        bbStr(" DMA_LEN=0x");
        bbHex(mmioRead32(dsi_base, DSI_DMA_LEN), 8);
        bbByte('\n');
        bbStr("   DLN0_PHY_ERR=0x");
        bbHex(mmioRead32(dsi_base, DSI_DLN0_PHY_ERR), 8);
        bbStr(" PHY0_STATUS=0x");
        bbHex(mmioRead32(0x0ae95000, 0x140), 8);
        bbByte('\n');
        bbSeal();
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
    // xfer_prepare/restore: OR in CMD_MODE_EN|ENABLE for the duration of
    // the command, then put CTRL back exactly as it was.
    //
    // Required because the link is in VIDEO mode by this point, so
    // CMD_MODE_EN is clear and commands cannot be issued without it.
    // Per-command PLL re-commit, exactly as link_clk_set_rate() does in
    // msm_dsi_host_xfer_prepare(). See dsiPhyPllRecommit().
    dsiPhyPllRecommit();

    const restore0 = mmioRead32(dsi0_base, DSI_CTRL);
    const restore1 = mmioRead32(dsi1_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, restore0 | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    mmioWrite32(dsi1_base, DSI_CTRL, restore1 | CTRL_CMD_MODE_EN | CTRL_ENABLE);

    // Land the command inside the blanking window, as the kernel does
    // before every transfer -- see dsiWait4VideoEngBusy().
    dsiWait4VideoEngBusy(dsi0_base);
    dsiWait4VideoEngBusy(dsi1_base);

    // Per-command instrumentation (SPEC.md task #5 log).
    //
    // Everything measurable at probe exit is correct -- DSI0 and DSI1 are
    // byte-identical across all 192 host registers, both PHY lane blocks
    // match exactly, the four PHY CMN differences are the legitimate
    // master/slave ones, and the link is streaming video (STATUS0=0x8,
    // LANE_STATUS=0x1f00, FIFO=0x1210, all matching a rendering Linux).
    // The panel still receives nothing.
    //
    // So stop looking at end state and watch a command actually go out.
    // The decisive value is LANE_STATUS sampled BETWEEN trigger and
    // completion: bits 0-4 are per-lane STOPSTATE, so if the lanes never
    // leave stop state while the DMA claims to be running, the packet was
    // never put on the wire -- which is the "DMA completes but the panel
    // hears nothing" contradiction stated as a single measurement.
    if (g_cmd_trace_n == 0) {
        // The registers that govern whether a command may be injected into
        // a live video stream, captured once at the first command so they
        // can be diffed against Linux at the equivalent moment.
        bbStr("cmdcfg: TRIG_CTRL=");
        bbHex(mmioRead32(dsi0_base, 0x080), 8);
        bbStr(" CMD_DMA_CTRL=");
        bbHex(mmioRead32(dsi0_base, 0x038), 8);
        bbStr(" CMD_CFG0=");
        bbHex(mmioRead32(dsi0_base, 0x03c), 8);
        bbStr(" CMD_CFG1=");
        bbHex(mmioRead32(dsi0_base, 0x040), 8);
        bbStr(" CTRL=");
        bbHex(mmioRead32(dsi0_base, DSI_CTRL), 8);
        bbStr(" INTR=");
        bbHex(mmioRead32(dsi0_base, DSI_INTR_CTRL), 8);
        bbByte('\n');
        bbSeal();
    }

    const st_pre = mmioRead32(dsi0_base, DSI_STATUS0);
    const lane_pre = mmioRead32(dsi0_base, DSI_LANE_STATUS);
    const t_start = timer_get_us();

    dsiCmdDmaTrigger(dsi1_base, dma_addr, len);
    dsiCmdDmaTrigger(dsi0_base, dma_addr, len);

    // Sampled as close to the trigger as possible, while the engine should
    // still be shifting bytes out.
    const lane_mid = mmioRead32(dsi0_base, DSI_LANE_STATUS);
    const st_mid = mmioRead32(dsi0_base, DSI_STATUS0);
    const fifo_mid = mmioRead32(dsi0_base, DSI_FIFO_STATUS);

    const ret1 = dsiCmdDmaWait(dsi1_base);
    const ret0 = dsiCmdDmaWait(dsi0_base);
    const t_us: u32 = @truncate(timer_get_us() -% t_start);

    bbCmdTrace(g_cmd_trace_n, len, t_us, st_pre, lane_pre, st_mid, lane_mid,
        fifo_mid, mmioRead32(dsi0_base, DSI_STATUS0),
        mmioRead32(dsi0_base, DSI_LANE_STATUS),
        mmioRead32(dsi0_base, DSI_ACK_ERR_STATUS), ret0, ret1);
    g_cmd_trace_n += 1;

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
/// Ask the DDIC what mode it is actually in (DCS 0x0A, Get Power Mode).
///
/// THE ONLY VALID INSTRUMENT for this question. Do not judge the panel
/// from Linux -- Linux's own DSI/PHY bring-up wedges it, which is what
/// made a whole earlier round of conclusions invalid. U-Boot must read
/// it itself, at the end of its own probe.
///
/// Restored from cbd53976^ after the Zig cleanup deleted it, minus the
/// blackbox logging and the BTA-timeout calibration that were scaffolding
/// for an investigation that has since concluded. The mechanics that
/// matter are kept exactly:
///
///   * Set Maximum Return Packet Size (0x37) first, master only.
///   * Hold CMD_MODE_EN across the WHOLE read, not per-DMA: the panel
///     turns the bus around ~milliseconds after our packet goes out, and
///     a per-DMA restore drops back to video mode before the reply
///     arrives.
///   * Trigger BOTH hosts but prepare only DSI0, matching the
///     xfer_prepare the kernel skips for a read. A stitched panel
///     expects synchronised SOT across both links.
///
/// Return value packs the state the read ran in, because the raw
/// register alone is ambiguous:
///   63:32  RDBK_DATA0 raw. Bytes are REVERSED vs the register: 31:24 is
///          data_id, 23:16 the payload. A good reply is 0x219C0000 --
///          reporting `resp & 0xff` alone shows 0, indistinguishable
///          from a silent panel. That trap cost real time before.
///   31:16  DSI_CTRL low half during the read. 0x01F7 = CMD_MODE_EN was
///          asserted and the BTA genuinely issued; 0x01F3 = it was not,
///          and the result says nothing about the panel.
///   15:8   TIMEOUT_STATUS low byte.
///    7:0   decoded payload. **0x9C on a correctly initialised panel**
///          (DISPLAY_ON | NORMAL_MODE | SLEEP_OUT); 0x08 is sleep-in,
///          display-off, i.e. an init that did not take.
export fn sheng_mdss_dsi_read_power_mode_single(dsi0_base: usize, dma_scratch: usize) callconv(.c) i64 {
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);

    const ctrl_restore = mmioRead32(dsi0_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    defer mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore);

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
    dst[3] = 0x80 | 0x20; // BIT5 = read

    const dsi1_base: usize = 0x0ae96004; // SM8550_MDSS_DSI1_BASE + shift
    dsiCmdDmaTrigger(dsi1_base, dma_scratch, 4);
    dsiCmdDmaTrigger(dsi0_base, dma_scratch, 4);
    _ = dsiCmdDmaWait(dsi1_base);
    ret = dsiCmdDmaWait(dsi0_base);
    if (ret != 0) return -2;

    // Wait for the turnaround. Polling the whole window matters: sampling
    // BTA_DONE at CMD_DMA_DONE time is structurally too early -- that is
    // the instant our packet finished going OUT, before the panel could
    // have replied -- and reading 0 there means nothing.
    var waited: u32 = 0;
    while (waited < 20000) : (waited += 20) {
        if ((mmioRead32(dsi0_base, DSI_INTR_CTRL) & (1 << 20)) != 0) break;
        udelay(20);
    }

    const resp = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    const ctrl_during = mmioRead32(dsi0_base, DSI_CTRL);
    const tmo = mmioRead32(dsi0_base, DSI_TIMEOUT_STATUS);

    return (@as(i64, resp) << 32) |
        (@as(i64, ctrl_during & 0xffff) << 16) |
        (@as(i64, tmo & 0xff) << 8) |
        @as(i64, (resp >> 16) & 0xff);
}

export fn sheng_mdss_dsi_panel_sleep(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) void {
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x28, &[_]u8{});
    udelay(20000); // datasheet-typical gap between display-off and sleep-in
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x10, &[_]u8{});
    udelay(5000);
}

/// Gap between init commands.
///
/// The DDIC needs time to consume each one. Linux paces its init at
/// roughly 2ms per command; sending them back to back at ~24us each is
/// about 80x faster, and the panel accepts the early commands, falls
/// behind, and ends up unconfigured -- with correct bytes, correct
/// framing and no error anywhere.
///
/// Tunable on purpose: if 1ms fixes it, bisect down to find the real
/// requirement rather than leaving a guess in the boot path.
/// 0: the init loop already paces at INIT_CMD_PACING_US = 2000us, which
/// matches Linux's measured ~2ms/command. b109 added 1ms on top on the
/// mistaken basis that we transmitted 80x faster -- the 24us in the
/// per-command trace is DMA time, not the inter-command interval. It
/// changed nothing, as expected in hindsight.
const DSI_INTER_CMD_DELAY_US: u32 = 0;


fn dsiSendDcs(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, cmd: u8, args: []const u8) c_int {
    var buf: [16]u8 = undefined;
    const len = buildMsmCmdPacket(&buf, cmd, args);
    if (len == 0) return -22; // -EINVAL-ish, packet too big for our scratch stack buffer

    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    for (buf[0..len], 0..) |b, i| dst[i] = b;

    const rc = dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, len);
    udelay(DSI_INTER_CMD_DELAY_US);
    return rc;
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

    const rc_long = dsiCmdDmaTxDual(dsi0_base, dsi1_base, dma_scratch, padded);
    udelay(DSI_INTER_CMD_DELAY_US);
    return rc_long;
}


/// Host bring-up and the video-mode switch, separated so they can run
/// BEFORE the panel is powered and reset.
///
/// The panel must be powered, reset and initialised onto a link that is
/// ALREADY in video mode -- that is the kernel's order:
///
///   host_enable_video  ->  panel_prepare  ->  panel_reset  ->  init_seq
///
/// The reset must FOLLOW the switch. Moving the switch here while
/// leaving the reset ahead of it regresses the DSC encoder.
export fn sheng_mdss_dsi_host_video_prepare(dsi0_base: usize, dsi1_base: usize) callconv(.c) void {
    dsiHostBringUp(dsi0_base);
    dsiHostBringUp(dsi1_base);
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);
}


export fn sheng_mdss_dsi_panel_init(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize, enable_dsc: bool) callconv(.c) c_int {
    // Must run before ANY DSI command traffic, not just before the
    // DPU's video fetch: the host's own command-mode DMA reads
    // dma_scratch through the same stream, so command #0 hits an
    // unbypassed SMMU otherwise.
    smmuBypassMdssStream();

    // Host bring-up and the video-mode switch run earlier, in
    // sheng_mdss_dsi_host_video_prepare(), before the panel is powered
    // and reset -- matching the kernel's timeline.
    //
    // Do NOT move the video-mode switch here to match the panel
    // driver's prepare_prev_first flag. Tried: DSI CTRL diverges and the
    // DSC encoder drops from OUT_STATUS 0x18xxxx to 0, INT_STAT 0x7b0 to
    // 0x180, and it stays that way even with the xfer_prepare/restore
    // that video-mode commands need. The switch belongs in dpu_start().

    // Force a clean ENABLE latch before the first DCS byte: drop
    // ENABLE, settle, set it again.
    //
    // This controller appears to sample its configuration into the
    // active datapath on the DSI_CTRL ENABLE 0->1 edge. Config written
    // while ENABLE is already set reaches the register file -- so every
    // readback and audit diffs clean -- without reaching the datapath.
    // Several things do write config after the initial enable: the
    // video-mode switch in dpu_start(), the TRIG_CTRL restore, and the
    // per-command CMD_MODE_EN OR-in.
    //
    // Inference, not documented. Supporting it: dsi_sw_reset() reads
    // DSI_CTRL, clears ENABLE, resets, then restores it -- mainline goes
    // out of its way never to reconfigure a running controller.
    {
        const c0 = mmioRead32(dsi0_base, DSI_CTRL);
        const c1 = mmioRead32(dsi1_base, DSI_CTRL);
        mmioWrite32(dsi0_base, DSI_CTRL, c0 & ~CTRL_ENABLE);
        mmioWrite32(dsi1_base, DSI_CTRL, c1 & ~CTRL_ENABLE);
        _ = mmioRead32(dsi0_base, DSI_CTRL); // post the writes
        udelay(1000);
        mmioWrite32(dsi0_base, DSI_CTRL, c0 | CTRL_ENABLE);
        mmioWrite32(dsi1_base, DSI_CTRL, c1 | CTRL_ENABLE);
        _ = mmioRead32(dsi0_base, DSI_CTRL);
        udelay(1000);
    }

    // Settle after the ENABLE re-latch, before the first DCS byte.
    //
    // DO NOT LOWER. Measured on hardware 2026-08-22 (b355): at 100ms the
    // panel comes up visibly glitched -- on and scanning, content
    // corrupted. Only 250ms is known good.
    //
    // It looks like a leftover "bump it and see" test from the era when
    // the panel would not init at all (SPEC.md task #5 log), and it was
    // 100ms before that bump, so lowering it back looked free. It is
    // not: whatever this settles for is real. Worth 150ms of a 6.9s
    // boot, which is not worth another attempt at a middle value --
    // see the boot-time breakdown, 81% of the boot is ABL and not ours.
    const ENABLE_SETTLE_US: c_ulong = 250000;
    udelay(ENABLE_SETTLE_US);

    // Pace the init table.
    //
    // The kernel emits these ~2ms apart, but that 2ms is not a
    // deliberate delay in the panel driver -- it is the cost of its
    // per-transfer path: mutex, per-transfer link clock
    // enable/disable, IRQ completion wait. Here a command is a DMA
    // trigger plus a busy-poll that clears in microseconds.
    //
    // What actually needs settling time is the 0xff PAGE SWITCH: it
    // changes which register bank every following write lands in, and a
    // DDIC that has not finished switching drops them while every
    // command still reports success. So keep the full 2ms after a page
    // switch and pace the other 81 commands, which are plain writes
    // within an already-selected bank, far tighter.
    //
    // BOOT-TIME KNOB: 87 x 2ms = 174ms becomes ~52ms. If init goes
    // intermittent, put PAGE_SWITCH_PACING_US's value back into
    // INIT_CMD_PACING_US to restore the old uniform behaviour.
    const INIT_CMD_PACING_US: c_ulong = 500;
    const PAGE_SWITCH_PACING_US: c_ulong = 2000;
    const DCS_PAGE_SELECT: u8 = 0xff;

    // Failures encode WHERE, not just what: -(10000 + index) inside the
    // table loop, -(20000 + stage) for the named stages after it. There
    // is no console, so the return value is the only report.
    var idx: i32 = 0;
    for (nt36532e_init_sequence) |entry| {
        const ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, entry.cmd, entry.args);
        if (ret != 0) return -(10000 + idx);
        udelay(if (entry.cmd == DCS_PAGE_SELECT) PAGE_SWITCH_PACING_US else INIT_CMD_PACING_US);
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

    // NEVER send `0x51 0x00` here. It sets the DDIC's own brightness to
    // zero, and the init table has already sent 0x53 0x24 (BCTRL | BL),
    // which arms the brightness block and tells it to apply that value.
    // The panel then outputs black while the backlight stays fully lit,
    // and 0xfb 0x01 earlier in the table stops it reloading defaults, so
    // it survives sleep-out and display-on.
    //
    // It is tempting as a liveness test -- set brightness to zero, watch
    // the backlight dim -- but the KTZ8866 is in I2C-brightness mode, so
    // DCS 0x51 cannot move the backlight. It only blanks the panel, and
    // every pipe-level bisect run underneath it measures nothing.

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



// ---------------------------------------------------------------------
// DPU pixel pipeline (task #5)
//
// One SSPP (sspp_8 = SSPP_DMA0, a DMA-type pipe at +0x24000) in
// multirect mode -- rect_0 the left half of the framebuffer, rect_1 the
// right -- feeding two independent LM -> PINGPONG -> DSC -> INTF
// chains, one per DSI half:
//
//   sspp_8 rect_0 (left  1524x2032+0+0)    -> LM_0 -> PP_0 -> DSC_0 -> INTF_1 -> DSI0 (master)
//   sspp_8 rect_1 (right 1524x2032+1524+0) -> LM_1 -> PP_1 -> DSC_1 -> INTF_2 -> DSI1 (slave)
//   CTL_0 orchestrates + flushes all of the above atomically.
//
// INTF_0 (+0x34000) is type INTF_DP on this catalog and CANNOT drive
// DSI. The DSI-capable interfaces are INTF_1 (+0x35000, controller_id 0
// = DSI0) and INTF_2 (+0x36000, controller_id 1 = DSI1).
//
// Offsets and sequencing come from dpu_hw_{sspp,lm,pingpong,intf,ctl}.c
// and dpu_hw_dsc_1_2.c -- the hard-slice DSC variant, which dpu_rm.c
// selects for core_major_ver >= 7. Specialised to this one case: single
// plane XRGB8888, one blend stage, dual hard-slice DSC, video-mode DSI.
// Not a general port of the DPU object model.
//
// The panel is video mode, so the INTF timing engine drives DSI
// continuously and there is no TE/vsync wiring here.

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

// ===================================================================
// SSPP pixel extension, clock gate and QoS.
//
// The pixel-extension block is the one that bites:
//
//   SW_PIX_EXT_C0_REQ_PIXELS  (0x108) = 0x07F005F4
//   SW_PIX_EXT_C1C2_REQ_PIXELS(0x118) = 0x07F005F4
//   SW_PIX_EXT_C3_REQ_PIXELS  (0x128) = 0x07F005F4
//
// 0x07F005F4 is (2032 << 16) | 1524, the same geometry as
// SSPP_SRC_SIZE. It sets how many pixels the pipe REQUESTS per plane.
// Left at zero the fetch is configured, the format and address are
// right, the pipe reads as fetch-active -- and it asks the bus for
// nothing. Everything downstream compresses and transmits a black frame
// with every audit passing.
//
// The rest the kernel programs here:
//   0x330 clk_ctrl -- SSPP clock gate, settles at 0x5
//   0x138 / 0x1c8 ubwc_error = 0x80000000 (rect0 / rect1)
//   0x134 / 0x13c = 0x00000009
//   0x01c / 0x020 SRC2/SRC3_ADDR = 0, 0x028 YSTRIDE1 = 0
//   0x060/0x064/0x06c/0x074/0x078 danger/safe/QoS-ctrl/creq LUTs
//
// Write the QoS LUTs together with the rest, not on their own. Writing
// them alone measures as a regression, but that is on a pipe with no
// pixel extension and no clock gate, which could never fetch anyway.
const SSPP_SW_PIX_EXT_C0_LR: usize = 0x100;
const SSPP_SW_PIX_EXT_C0_TB: usize = 0x104;
const SSPP_SW_PIX_EXT_C0_REQ_PIXELS: usize = 0x108;
const SSPP_SW_PIX_EXT_C1C2_LR: usize = 0x110;
const SSPP_SW_PIX_EXT_C1C2_TB: usize = 0x114;
const SSPP_SW_PIX_EXT_C1C2_REQ_PIXELS: usize = 0x118;
const SSPP_SW_PIX_EXT_C3_LR: usize = 0x120;
const SSPP_SW_PIX_EXT_C3_TB: usize = 0x124;
const SSPP_SW_PIX_EXT_C3_REQ_PIXELS: usize = 0x128;
const SSPP_SRC2_ADDR: usize = 0x01c;
const SSPP_SRC3_ADDR: usize = 0x020;
const SSPP_SRC_YSTRIDE1: usize = 0x028;
const SSPP_UNK_134: usize = 0x134;
const SSPP_UBWC_ERROR: usize = 0x138;
const SSPP_UNK_13C: usize = 0x13c;
const SSPP_UBWC_ERROR_REC1: usize = 0x1c8;
const SSPP_CLK_CTRL: usize = 0x330;
const SSPP_CLK_CTRL_VALUE: u32 = 0x5;
const SSPP_UBWC_ERROR_VALUE: u32 = 0x80000000;


const SSPP_FETCH_PROBE_ADDR: u32 = 0x50000000;
const SSPP_SRC_CONSTANT_COLOR: usize = 0x3c;
const SSPP_SRC_CONSTANT_COLOR_REC1: usize = 0x180;
const SSPP_SOLID_FILL_FORMAT_BIT: u32 = 1 << 22;
const SSPP_SOLID_FILL_COLOR: u32 = 0xFF0000FF;

/// SSPP QoS / danger-safe. These decide whether the fetch pipe gets
/// memory bandwidth priority.
///
/// SSPP_QOS_CTRL's DANGER_SAFE_EN arms the escalation mechanism;
/// DANGER_LUT and SAFE_LUT are the FIFO fill levels at which the pipe
/// raises its urgency to the memory controller, and CREQ_LUT_0/1 the
/// matching client-request priorities.
///
/// Left at zero with the mechanism disarmed, the pipe never signals
/// urgency and other masters can starve it indefinitely. Everything
/// downstream then compresses and transmits a black frame -- no fault,
/// no underflow flag, nothing to see.
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
/// LM_OP_MODE is the blend-stage enable mask, NOT a right_mixer flag.
/// dpu_hw_lm_setup_color3() writes `1 << pstate->stage`, and
/// pstate->stage = DPU_STAGE_0 + zpos. DPU_STAGE_BASE(0) is the
/// border/background layer, so a single plane at zpos 0 is stage 1 and
/// needs bit 1 set.
///
/// Written as 0, no blend stage is enabled and the mixer emits border
/// colour -- black -- however correct the pipe feeding it is.
///
/// Pairs with CTL_LAYER0, whose mix field is (stage_index + 1) = 1 and
/// names the same stage. Program both or neither.
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
/// Dither sub-block base, written 0 by dpu_hw_pp_setup_dither() when no
/// dither config is supplied (`if (!cfg) { DPU_REG_WRITE(c, base, 0);
/// return; }`). Found by the DPU write trace -- we never wrote it, so it
/// held whatever ABL left. A stale dither config on the pingpong sits
/// directly in the pixel path.
const PP_DITHER_BASE: usize = 0x0e0;
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
/// Two DSC CTL registers that are easy to miss:
///
///   DSC_DATA_IN_SWAP (0x08) -- live 0x0002C688
///   DSC_CLK_CTRL     (0x0C) -- live 0xC0000000
///
/// DSC_CLK_CTRL is a clock gate. Left clear, the encoder still answers
/// over AHB and its status registers still read -- ENC_GENERAL_STATUS
/// and ENC_INT_STAT come back nonzero -- while ENC_OUT_STATUS stays 0
/// against a live 0x002E0000 and ENC_HSLICE_STATUS stalls at 0x0d. The
/// block is alive enough to reply and emits nothing.
///
/// On a DSC-mandatory panel that alone is a black screen with the whole
/// pipeline verifying clean. ABL sets these and our own core reset
/// wipes them, so they must be rewritten here.
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
/// CORRECTED BY THE DPU WRITE TRACE (SPEC.md task #5 log).
///
/// This was 0x21 << 8 == 0x2100. The working kernel writes **0x0000213F**
/// on BOTH interfaces. dpu_hw_intf_setup_timing_engine() builds it as:
///
///     panel_format = (COLOR_8BIT       ) |
///                    (COLOR_8BIT  << 2 ) |
///                    (COLOR_8BIT  << 4 ) |
///                    (0x21        << 8 );
///
/// with COLOR_8BIT == 0x3, i.e. 3 | 12 | 48 | 0x2100 = 0x213F. We had the
/// 0x21 tag and dropped the three 2-bit per-component BIT-DEPTH fields
/// entirely, telling the interface each colour component is something
/// other than 8-bit while feeding it 8-bit data.
const INTF_PANEL_FORMAT_RGB888: u32 = (0x21 << 8) | (0x3) | (0x3 << 2) | (0x3 << 4);

/// Programmable fetch start. Easy to enable without programming.
///
/// dpu_hw_intf_setup_prg_fetch():
///
///     fetch_enable = DPU_REG_READ(c, INTF_CONFIG);
///     if (fetch->enable) {
///             fetch_enable |= BIT(31);
///             DPU_REG_WRITE(c, INTF_PROG_FETCH_START, fetch->fetch_start);
///     } else {
///             fetch_enable &= ~BIT(31);
///     }
///     DPU_REG_WRITE(c, INTF_CONFIG, fetch_enable);
///
/// On both interfaces: INTF_CONFIG 0x00800000 from the timing setup,
/// then 0x80800000 once BIT(31) is OR'd in, with
/// INTF_PROG_FETCH_START = 0x0014CA28 written in between.
///
/// Copying the FINAL INTF_CONFIG from a live read enables programmable
/// fetch without ever setting the line it starts from, leaving that at
/// whatever ABL or POR left. An interface prefetching from an arbitrary
/// point relative to vsync delivers no coherent frame and reports no
/// error.
///
/// A live-value copy hides a missing write like this every time: the
/// enable bit survives into the readback, the value register does not
/// announce itself.
const INTF_PROG_FETCH_START: usize = 0x170;
const INTF_PROG_FETCH_START_VALUE: u32 = 0x0014CA28;

const CTL_LAYER0: usize = 0x000; // CTL_LAYER(LM_0): (lm-LM_0)*4
const CTL_LAYER1: usize = 0x004; // CTL_LAYER(LM_1)
const CTL_LAYER_EXT2_0: usize = 0x070; // CTL_LAYER_EXT2(LM_0): 0x70+(lm-LM_0)*4
const CTL_LAYER_EXT2_1: usize = 0x074; // CTL_LAYER_EXT2(LM_1)
const CTL_TOP: usize = 0x014;
const CTL_FLUSH: usize = 0x018;
const CTL_START: usize = 0x01c;
const CTL_INTF_ACTIVE: usize = 0x0f4;
const CTL_DSC_ACTIVE: usize = 0x0e8;
/// Traced as written 0 by the kernel; we never wrote it. No 3D merge here.
const CTL_MERGE_3D_ACTIVE: usize = 0x0e4;
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

// MDP top block (dpu_base + 0), from dpu_hw_top.c. See the write site in
// sheng_mdss_dpu_start() for why these matter on a bonded panel.
const MDP_SSPP_SPARE: usize = 0x028;
const MDP_SPLIT_DISPLAY_EN: usize = 0x2f4;
const MDP_SPLIT_DISPLAY_UPPER_PIPE_CTRL: usize = 0x2f8;
const MDP_SPLIT_DISPLAY_LOWER_PIPE_CTRL: usize = 0x3f0;
const SPLIT_INTF_1_SW_TRG_MUX: u32 = 1 << 4;
const SPLIT_INTF_2_SW_TRG_MUX: u32 = 1 << 8;

// merge_3d_0, catalog base +0x4e000.
const MERGE_3D_0_BASE: usize = 0x4e000;

// ===================================================================
// VBIF -- where the DPU's fetch clients get their memory type and QoS
// priority. Left unprogrammed, the pipe's reads are neither classified
// nor prioritised at the bus.
//
// The base is NOT dpu_base + 0x74000. VBIF is a separate ioremap
// (reg-names "mdp", "vbif"), so a 0x74000 seen in a kernel trace is
// just where that mapping landed in kernel VA. The real address is
// 0x0aeb0000.
//
//   0x160/0x164  VBIF_XIN_MEMTYPE_0/1 -- dpu_hw_set_mem_type(), written
//                per-xin as a read-modify-write, which is why the trace
//                shows them ramping 0x22222223 -> 0x33333333. The final
//                state is what matters here.
//   0x19c        VBIF_XIN_CLR_ERR -- dpu_vbif_clear_errors()
//   0x550..0x588 VBIF_XINL_QOS_RP_REMAP  (8 entries)
//   0x590..0x5c8 VBIF_XINL_QOS_LVL_REMAP (8 entries)
const SM8550_MDSS_VBIF_BASE: usize = 0x0aeb0000;
const VBIF_XIN_MEMTYPE_0: usize = 0x160;
const VBIF_XIN_MEMTYPE_1: usize = 0x164;
const VBIF_XIN_CLR_ERR: usize = 0x19c;
const VBIF_XIN_MEMTYPE_VALUE: u32 = 0x33333333;
const VBIF_QOS_REMAP_BASE: usize = 0x550;
const VBIF_QOS_LVL_REMAP_BASE: usize = 0x590;

const vbif_qos_remap_values = [8]u32{
    0x00000030, 0x11111131, 0x22222242, 0x33333343,
    0x44444454, 0x55555555, 0x66666666, 0x77777767,
};

export fn sheng_mdss_vbif_init(vbif_base: usize) callconv(.c) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        mmioWrite32(vbif_base, VBIF_QOS_REMAP_BASE + i * 8, vbif_qos_remap_values[i]);
        mmioWrite32(vbif_base, VBIF_QOS_LVL_REMAP_BASE + i * 8, vbif_qos_remap_values[i]);
    }
    mmioWrite32(vbif_base, VBIF_XIN_MEMTYPE_0, VBIF_XIN_MEMTYPE_VALUE);
    mmioWrite32(vbif_base, VBIF_XIN_MEMTYPE_1, VBIF_XIN_MEMTYPE_VALUE);
    mmioWrite32(vbif_base, VBIF_XIN_CLR_ERR, 0x0);
}

const MERGE_3D_MUX: usize = 0x000;
const MERGE_3D_MODE: usize = 0x004;
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
    // SLICE GEOMETRY MUST MATCH THE PPS. This panel is FOUR 762-px
    // slices across the full 3048 width -- TWO soft slices per encoder,
    // not one encoder over a 1524-px picture. A DSC decoder whose slice
    // geometry disagrees with the PPS it was sent emits nothing
    // decodable: link clean at 144Hz, FIFOs healthy, panel initialised,
    // screen black.
    //
    // The encoder config here and the PPS in nt36532e_pps_144hz are
    // transcribed separately and nothing cross-checks them. They must be
    // changed together.
    //
    // DSC_CMN_MAIN_CNF is shared, written identically by both
    // instances: SPLIT_PANEL with num_active_slice_per_enc in bits
    // [8:7]. 0x101 means field value 2, not 1.
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

// The MDSS stream must be pointed at a context bank, NOT set to BYPASS.
//
// apps_smmu's SCR0 has USFCFG set, so unmatched streams FAULT rather
// than bypass. The display's stream ID has a firmware-provisioned match
// entry (SMR[3] = 0x80021c00, VALID, MASK 0x2, ID 0x1c00), so raw
// physical SSPP fetches get aborted silently -- frame and line counters
// still increment, because INTF timing needs no memory access, while no
// pixel content ever arrives. The fault interrupt is enabled but
// nothing in U-Boot services it, so it sits pending harmlessly.
//
// DO NOT write S2CR_TYPE_BYPASS. From U-Boot's own qcom-hyp-smmu.c:
// "Don't change this to use S2CR_TYPE_BYPASS! Some Qualcomm boards have
// angry hypervisor firmware that converts S2CR type BYPASS to type
// FAULT on write." That turns every DSI command DMA into a silent fault
// -- CMD_MODE_DMA_BUSY never clears, DLN0_PHY_ERR stays zero.
//
// Use that driver's workaround instead: S2CR_TYPE_TRANS pointing at a
// context bank with stage-1 left disabled (SCTLR.M clear, TCR/TTBR/MAIR
// zero). Physical addresses pass through untranslated and the word
// BYPASS never appears in the write the hypervisor watches.

// Must match SHENG_MDSS_DSI_DMA_SCRATCH in sheng_mdss.c -- the one
// physical buffer every DSI command DMA uses.
const SHENG_MDSS_DSI_DMA_SCRATCH_PHYS: u64 = 0xa3100000;
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

// Read off a rendering Linux's own MDSS context bank. TCR 0x80351c is
// a 4KB granule with T0SZ=28: 36-bit input, start_level=1, so an L1
// descriptor is a valid 1GB block.
const SMMU_TCR_LIVE_LINUX_VALUE: u32 = 0x80351c;
const SMMU_SCTLR_LIVE_LINUX_VALUE: u32 = 0x67;
// MAIR0 byte 0 (AttrIndx=0): Normal, Inner/Outer Write-Back,
// Read/Write-Allocate. Our own choice -- this is our context bank, so
// it need not match Linux's index assignment.
const SMMU_MAIR0_NORMAL_WB: u32 = 0xff;

// Equal to the DMA scratch address, so the IOVA computed in
// dsiCmdDmaTrigger() comes out identity and resolves through the
// SSPP-validated 1GB identity block rather than a 3-level walk.
//
// DMA_BASE is a plain 32-bit register, so the IOVA has to be
// 32-bit-representable. Linux instead maps a small IOVA (0x1000) to a
// high-bank physical address, which a 1GB block descriptor cannot
// express -- block granularity forces the low bits of input and output
// to match -- and so needs real 4KB page-level translation.
const SMMU_MAPPED_IOVA: usize = 0xa3100000;
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
var g_smmu_sctlr: u32 = 0xFFFFFFFF;
export fn sheng_mdss_smmu_sctlr() callconv(.c) u32 { return g_smmu_sctlr; }

/// Exported so callers that issue a command DMA BEFORE
/// sheng_mdss_dsi_panel_init() can set translation up first.
///
/// This exists because of a measured failure: an early BTA read was added
/// to probe() ahead of panel_init(), and the board hung outright -- no
/// backlight, no boot. panel_init()'s very first statement is
/// smmuBypassMdssStream(); running a DSI command DMA before it means the
/// engine fetches SMMU_MAPPED_IOVA (0x1000) through a stream with no
/// mapping, on an SMMU whose SCR0 has USFCFG=1 (unmatched streams FAULT
/// rather than bypass). A stalled AXI read from that master is exactly the
/// wedge this file documents elsewhere. Idempotent -- panel_init() and
/// dpu_start() both call it already.
export fn sheng_mdss_smmu_setup() callconv(.c) void {
    smmuBypassMdssStream();
}

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

    // Build the page tables: a 1GB identity block covering both the DMA
    // scratch and the framebuffer, plus a 3-level page walk mapping
    // SMMU_MAPPED_IOVA.
    //
    // TCR is copied verbatim from a live working context bank
    // (0x80351c) rather than hand-derived -- it has many fields and
    // getting one encoding subtly wrong is silent.
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
    // Stage-1 passthrough: clear SCTLR.M so the context bank does no
    // translation at all. Physical addresses pass through as-is and the
    // page tables above go unused. S2CR still reads TYPE_TRANS, so the
    // hypervisor never sees a BYPASS write.
    //
    // Do NOT "match Linux" by setting SCTLR.M. Linux translates because
    // it hands the engine an IOVA (0x1000); this driver hands it a
    // physical address, so enabling translation only means a hand-built
    // identity map has to undo it.
    const sctlr: u32 = SMMU_SCTLR_LIVE_LINUX_VALUE & ~@as(u32, 1);
    mmioWrite32(cbx_base, 0x0, sctlr);
    g_smmu_sctlr = sctlr;

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

    // VBIF memtype + QoS remap, before any fetch is configured -- see
    // SM8550_MDSS_VBIF_BASE's comment. dpu_vbif_init_memtypes() runs in
    // dpu_kms_hw_init(), i.e. well before any plane is programmed.
    sheng_mdss_vbif_init(SM8550_MDSS_VBIF_BASE);

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

    mmioWrite32(sspp_base, SSPP_SRC_FORMAT, SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE, SSPP_OP_MODE_LIVE);

    // Pixel extension: how many pixels the pipe actually REQUESTS. Never
    // written by this driver until now -- see the block comment above.
    // req_pixels has the same (height << 16) | width packing as SRC_SIZE.
    const req_pixels: u32 = (vactive << 16) | half_w;
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C0_LR, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C0_TB, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C0_REQ_PIXELS, req_pixels);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C1C2_LR, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C1C2_TB, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C1C2_REQ_PIXELS, req_pixels);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C3_LR, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C3_TB, 0);
    mmioWrite32(sspp_base, SSPP_SW_PIX_EXT_C3_REQ_PIXELS, req_pixels);

    // Unused plane addresses / stride, written explicitly so they are
    // deterministic rather than whatever ABL left.
    mmioWrite32(sspp_base, SSPP_SRC2_ADDR, 0);
    mmioWrite32(sspp_base, SSPP_SRC3_ADDR, 0);
    mmioWrite32(sspp_base, SSPP_SRC_YSTRIDE1, 0);

    mmioWrite32(sspp_base, SSPP_UNK_134, 0x9);
    mmioWrite32(sspp_base, SSPP_UNK_13C, 0x9);
    mmioWrite32(sspp_base, SSPP_UBWC_ERROR, SSPP_UBWC_ERROR_VALUE);
    mmioWrite32(sspp_base, SSPP_UBWC_ERROR_REC1, SSPP_UBWC_ERROR_VALUE);

    // Danger/safe + CREQ QoS, exactly as the kernel programs them.
    mmioWrite32(sspp_base, SSPP_DANGER_LUT, SSPP_DANGER_LUT_VALUE);
    mmioWrite32(sspp_base, SSPP_SAFE_LUT, SSPP_SAFE_LUT_VALUE);
    mmioWrite32(sspp_base, SSPP_CREQ_LUT_0, SSPP_CREQ_LUT_0_VALUE);
    mmioWrite32(sspp_base, SSPP_CREQ_LUT_1, SSPP_CREQ_LUT_1_VALUE);
    mmioWrite32(sspp_base, SSPP_QOS_CTRL, SSPP_QOS_CTRL_DANGER_SAFE_EN);

    // SSPP clock gate -- same class as DSC_CLK_CTRL. Written last, once
    // the pipe is fully configured.
    mmioWrite32(sspp_base, SSPP_CLK_CTRL, SSPP_CLK_CTRL_VALUE);

    mmioWrite32(sspp_base, SSPP_SRC_SIZE_REC1, (vactive << 16) | half_w);
    mmioWrite32(sspp_base, SSPP_SRC_XY_REC1, half_w); // x offset = half_w, y=0
    mmioWrite32(sspp_base, SSPP_OUT_SIZE_REC1, (vactive << 16) | half_w);
    // Live OUT_XY_REC1 = 0x000005F4 (x = half_w), not 0.
    mmioWrite32(sspp_base, SSPP_OUT_XY_REC1, half_w);
    // rect1 fetches through SRC1_ADDR, not SRC0_ADDR -- same buffer base,
    // SRC_XY_REC1's x=half_w crops into the right half via YSTRIDE0's
    // high16 pitch.
    mmioWrite32(sspp_base, SSPP_SRC1_ADDR, @truncate(fb_addr));
    mmioWrite32(sspp_base, SSPP_SRC_FORMAT_REC1, SSPP_XRGB8888_SRC_FORMAT);
    mmioWrite32(sspp_base, SSPP_SRC_UNPACK_PATTERN_REC1, SSPP_XRGB8888_UNPACK_PATTERN);
    mmioWrite32(sspp_base, SSPP_SRC_OP_MODE_REC1, SSPP_OP_MODE_LIVE);
    // dpu_hw_sspp_setup_multirect() ORs DPU_SSPP_RECT_0(1) | DPU_SSPP_RECT_1(2)
    // and sets BIT(2) ONLY for TIME_MX. Live reads 0x3 -- both rects,
    // parallel, NOT time-multiplexed as this previously programmed (0x5).
    mmioWrite32(sspp_base, SSPP_MULTIRECT_OPMODE, SSPP_MULTIRECT_OPMODE_LIVE);

    _ = half_stride;


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
    mmioWrite32(ctl_base, CTL_LAYER0, CTL_MIXER_BORDER_OUT | (@as(u32, 2) << 18));
    mmioWrite32(ctl_base, CTL_LAYER1, CTL_MIXER_BORDER_OUT | (@as(u32, 2) << 18));
    mmioWrite32(ctl_base, CTL_LAYER_EXT2_0, @as(u32, 2) << 8);
    mmioWrite32(ctl_base, CTL_LAYER_EXT2_1, @as(u32, 2) << 8);


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
        // Disable dither on both pingpongs -- see PP_DITHER_BASE.
        mmioWrite32(pp0_base, PP_DITHER_BASE, 0);
        mmioWrite32(pp1_base, PP_DITHER_BASE, 0);

        // -- DSC: two hard-slice encoder instances sharing the DCE base,
        // dce_0_0 sblk (enc+0x100/ctl+0xf00) for DSC_0, dce_0_1 sblk
        // (enc+0x200/ctl+0xf80) for DSC_1.
        dscConfigureInstance(dce_base, 0x100, 0xf00, 0); // -> PP_0
        dscConfigureInstance(dce_base, 0x200, 0xf80, 1); // -> PP_1
    }


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


    // -- CTL top-level routing: both INTFs + both DSC engines active,
    // INTF_1 (DSI0) is the split-link master, video mode (no cmd-mode
    // bit), default (disabled) VM group id per core_major_ver>=7.
    mmioWrite32(ctl_base, CTL_TOP, CTL_DEFAULT_GROUP_ID_SHIFTED);
    mmioWrite32(ctl_base, CTL_INTF_ACTIVE, (@as(u32, 1) << 1) | (@as(u32, 1) << 2)); // INTF_1, INTF_2
    mmioWrite32(ctl_base, CTL_MERGE_3D_ACTIVE, 0);
    mmioWrite32(ctl_base, CTL_DSC_ACTIVE, if (enable_dsc) @as(u32, 0x3) else 0); // DSC_0, DSC_1
    mmioWrite32(ctl_base, CTL_INTF_MASTER, @as(u32, 1) << 1); // INTF_1 is master
    // Permit SSPP_DMA0 to fetch -- see CTL_FETCH_PIPE_ACTIVE's comment.
    mmioWrite32(ctl_base, CTL_FETCH_PIPE_ACTIVE, CTL_FETCH_PIPE_SSPP_DMA0);

    // ===================================================================
    // Split display: what makes INTF_1 and INTF_2 two halves of ONE
    // panel rather than two independent interfaces.
    //
    // dpu_hw_setup_split_pipe(), in this order with EN last:
    //     SSPP_SPARE                    (0x028) = 0x00000000
    //     SPLIT_DISPLAY_LOWER_PIPE_CTRL (0x3f0) = 0x00000100
    //     SPLIT_DISPLAY_UPPER_PIPE_CTRL (0x2f8) = 0x00000010
    //     SPLIT_DISPLAY_EN              (0x2f4) = 0x00000001
    //
    // FLD_INTF_1_SW_TRG_MUX is BIT(4) and FLD_INTF_2_SW_TRG_MUX is
    // BIT(8), so upper pipe = INTF_1, lower = INTF_2, and INTF_1 is
    // master -- which agrees with CTL_INTF_MASTER independently.
    //
    // Without EN the two interfaces are not trigger-muxed together and
    // the halves never form a coherent frame. Every per-block register
    // can be correct while the panel is fed something it cannot
    // assemble, and this block appears in no per-block diff.
    mmioWrite32(dpu_base, MDP_SSPP_SPARE, 0x00000000);
    mmioWrite32(dpu_base, MDP_SPLIT_DISPLAY_LOWER_PIPE_CTRL, SPLIT_INTF_2_SW_TRG_MUX);
    mmioWrite32(dpu_base, MDP_SPLIT_DISPLAY_UPPER_PIPE_CTRL, SPLIT_INTF_1_SW_TRG_MUX);
    mmioWrite32(dpu_base, MDP_SPLIT_DISPLAY_EN, 0x1);

    // MERGE_3D disabled explicitly (traced: both registers written 0).
    // We never wrote them, so they held whatever ABL/POR left. With two
    // independent LM->PP->DSC->INTF chains there is no 3D merge here, and
    // a stale non-zero mode would mis-pair the two pingpongs.
    mmioWrite32(dpu_base + MERGE_3D_0_BASE, MERGE_3D_MUX, 0x0);
    mmioWrite32(dpu_base + MERGE_3D_0_BASE, MERGE_3D_MODE, 0x0);
    // ===================================================================


    // -- Switch both DSI hosts from command mode to video mode before
    // the timing engines start pushing pixel data. Moving this earlier
    // (before the DCS sequence) was tried and measurably regressed the
    // DSC encoder -- see the note in sheng_mdss_dsi_panel_init().
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);


    // The timing engines are enabled BELOW, after CTL_FLUSH, not here.
    //
    // dpu_encoder_phys_vid_enable() only programs the timing registers
    // and the pending-flush bits; the engine comes up later in
    // handle_post_kickoff(), whose own comment says "Video mode must
    // flush CTL before enabling timing engine".


    // -- CTL flush (v1 path, core_major_ver>=5): per-block flush masks
    // written to their own registers first, then the aggregate pending
    // mask to CTL_FLUSH.
    mmioWrite32(ctl_base, CTL_INTF_FLUSH, (@as(u32, 1) << 1) | (@as(u32, 1) << 2)); // INTF_1, INTF_2
    if (enable_dsc) {
        mmioWrite32(ctl_base, CTL_DSC_FLUSH, 0x3); // DSC_0, DSC_1
    }


    const pending_flush = CTL_FLUSH_SSPP_DMA0 | CTL_FLUSH_LM0 | CTL_FLUSH_LM1 |
        CTL_FLUSH_MASK_CTL | CTL_FLUSH_INTF_IDX |
        (if (enable_dsc) CTL_FLUSH_DSC_IDX else 0);
    mmioWrite32(ctl_base, CTL_FLUSH, pending_flush);


    // CTL_START REMOVED (SPEC.md task #5 log).
    //
    // This used to write CTL_START=1 here. Verified against the kernel
    // this device actually runs (ianchb/sm8550-mainline @005aa8cc):
    // dpu_encoder_phys_vid_init_ops() never assigns ops->trigger_start,
    // and _dpu_encoder_trigger_start() is guarded by
    // `if (phys->ops.trigger_start && ...)`. So on a VIDEO-mode encoder
    // CTL_START is never written in normal operation -- it is a one-shot
    // fetch trigger for command mode / autorefresh. The only direct
    // ctl->ops.trigger_start() call in dpu_encoder.c sits in the
    // phys_cleanup/reset_intf_cfg path, not the enable path.
    //
    // In video mode the INTF timing generator free-runs and CTL_FLUSH is
    // latched by hardware at the next vsync; nothing needs to be kicked.
    // Firing a command-mode fetch trigger into a free-running video
    // pipeline is at best redundant and is a plausible way to desync the
    // fetch from the timing generator.

    // -- Timing engines LAST, after the flush -- see the block above for
    // the sourced ordering (dpu_encoder_phys_vid_handle_post_kickoff:
    // "Video mode must flush CTL before enabling timing engine").
    mmioWrite32(intf1_base, INTF_TIMING_ENGINE_EN, 1);
    mmioWrite32(intf2_base, INTF_TIMING_ENGINE_EN, 1);

    return 0;
}

/// Physical lane state -- the closest thing to a scope available in
/// software.
///
///   DLN0-3_STOPSTATE        bits 0-3   } parked in LP-11, idle
///   CLKLN_STOPSTATE         bit  4     }
///   DLN0-3_ULPS_ACTIVE_NOT  bits 8-11  } NOT in ultra-low-power state
///   CLKLN_ULPS_ACTIVE_NOT   bit  12    }
///
/// Live reference: DSI0 0x00001F00 (all STOPSTATE clear, lanes driven),
/// DSI1 0x00001F1F (parked at the sampling instant, normal on a burst
/// link between bursts).
///
/// STOPSTATE stuck set on both links while streaming means the lanes
/// never leave LP-11 and nothing is physically transmitted. Must be
/// sampled with the DPU streaming, or a healthy link reads as parked.
const DSI_LANE_STATUS: usize = 0x0a4;

export fn sheng_mdss_lane_status(dsi0_base: usize, dsi1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_LANE_STATUS)) << 32) |
        @as(i64, mmioRead32(dsi1_base, DSI_LANE_STATUS));
}

/// DLN0_PHY_ERR on both links, sampled at the same moment. Live baseline
/// is 0x00088888 on both (every defined error bit clear). The two bits
/// worth watching are DLN0_ERR_CONTENTION_LP0 (12) / _LP1 (16): contention
/// means something ELSE is driving the line against us -- which on this
/// link could only be the panel, and would be the first positive evidence
/// in this project that the panel drives anything at all.
export fn sheng_mdss_phy_err_both(dsi0_base: usize, dsi1_base: usize) callconv(.c) i64 {
    return (@as(i64, mmioRead32(dsi0_base, DSI_DLN0_PHY_ERR)) << 32) |
        @as(i64, mmioRead32(dsi1_base, DSI_DLN0_PHY_ERR));
}

/// DSI0 CTRL << 32 | DSI0 STATUS0.
///
/// CTRL confirms the command-to-video mode switch stuck: VID_MODE_EN
/// set, CMD_MODE_EN clear. STATUS0's VIDEO_MODE_ENGINE_BUSY (bit 3)
/// stays asserted on a host that is genuinely transmitting -- zero
/// while INTF1's frame counter advances means the DPU is clocking
/// timing into a host that sends nothing.
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

/// CTL_FLUSH << 32 | CTL_START.
///
/// Hardware clears CTL_FLUSH bits as each block's config latches.
/// Nonzero here, hundreds of frames after CTL_START, means the commit
/// never completed and none of the SSPP/LM/DSC config took effect --
/// INTF then streams timing with nothing behind it.
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
    // Programmable fetch: write the START VALUE, then INTF_CONFIG with
    // BIT(31) set -- the order dpu_hw_intf_setup_prg_fetch() uses. See
    // INTF_PROG_FETCH_START's comment: INTF_CONFIG_LIVE already carries
    // BIT(31), so without this the feature was on with no start point.
    mmioWrite32(intf_base, INTF_PROG_FETCH_START, INTF_PROG_FETCH_START_VALUE);
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
// Whole-pipeline check against live-hardware reference values.
//
// Every entry was read from working silicon in this same 144Hz DSC
// bonded-DSI mode. Run after dpu_start() has committed.
//
// Returns a bitmask: bit N set means entry N does not hold its
// reference value. 0 means the programmed pipeline matches working
// hardware, so any remaining fault is not register content.
// ===========================================================================






/// The MDSS wrapper's UBWC block, which sits in the memory data path.
/// msm_mdss_enable() writes all three on every bring-up, before any
/// child DSI or DPU device is touched:
///
///   UBWC_STATIC          (0x144) = 0x0000103E
///   UBWC_CTRL_2          (0x150) = 0x00000002
///   UBWC_PREDICTION_MODE (0x154) = 0x00000001
///
/// Must be rewritten here: mdssCoreBcrReset() destroys whatever ABL
/// left and nothing else restores it, leaving the block at zero.
///
/// Top-level state like this appears in no per-block register diff,
/// because it lives above the DSI and DPU spaces that get audited.
const MDSS_UBWC_STATIC: usize = 0x144;
const MDSS_UBWC_CTRL_2: usize = 0x150;
const MDSS_UBWC_PREDICTION_MODE: usize = 0x154;
const MDSS_UBWC_STATIC_VALUE: u32 = 0x0000103E;
const MDSS_UBWC_CTRL_2_VALUE: u32 = 0x00000002;
const MDSS_UBWC_PREDICTION_MODE_VALUE: u32 = 0x00000001;


export fn sheng_mdss_ubwc_init(mdss_base: usize) callconv(.c) void {
    mmioWrite32(mdss_base, MDSS_UBWC_STATIC, MDSS_UBWC_STATIC_VALUE);
    mmioWrite32(mdss_base, MDSS_UBWC_CTRL_2, MDSS_UBWC_CTRL_2_VALUE);
    mmioWrite32(mdss_base, MDSS_UBWC_PREDICTION_MODE, MDSS_UBWC_PREDICTION_MODE_VALUE);
}









/// bit 63 is reserved for the master/slave-dependent CLK_CFG1 entry so the
/// table above can stay shared between both PHYs.
const PHY_AUDIT_CLK_CFG1_BIT: u6 = 63;










/// Raw readout of the PHY status region on BOTH PHYs.
///
/// CMN 0x144 is undocumented -- the register XML defines 0x140
/// PHY_STATUS, 0x148 LANE_STATUS0, 0x14c LANE_STATUS1 and nothing at
/// 0x144 -- but it behaves as status, not configuration:
///
///   0x00  PHY off, both PHYs read this with the display blanked
///   0x58  PHY up and streaming
///
/// Sampled at eight ordered points through bring-up, one raw byte per
/// slot, so the first slot that diverges names the step responsible.
/// Slot 0 is the low byte, read right after the GDSC comes up and before
/// this driver touches the PHY, which also says whether ABL hands it
/// over already in that state.
///
/// No slot can sit earlier: reading PHY registers needs the GDSC and the
/// AHB clock up.
var g_phy144_marks: [8]u8 = .{0} ** 8;

/// Sample LANE_STATUS repeatedly and report the distribution.
///
/// A single sample is worthless here. This panel is
/// MIPI_DSI_MODE_VIDEO_BURST with MIPI_DSI_CLOCK_NON_CONTINUOUS, so the
/// data lanes legitimately drop to LP between bursts: a rendering Linux
/// sampled 200 times reads 0x00001F00 (transmitting) 191 times but
/// 0x00001F0F (data lanes stopped) 3 times. A one-shot read that catches
/// the 1.5% case looks exactly like a dead link.
///
/// Spacing matters as much as count. 256 back-to-back reads span well
/// under one 6.9ms frame and can all land inside one blanking interval.
/// 100us apart spreads them over ~25ms, about 3.7 frames at 144Hz.
///
///   63:32  samples (of 256) with all four data lanes OUT of stopstate
///   31:0   samples (of 256) with the clock lane OUT of stopstate
///
/// Linux reference is ~244/256 data-active. Zero means the data lanes
/// never transmit; near 244 means they do, and the fault is in WHAT is
/// on the wire.
export fn sheng_mdss_dsi_lane_activity(dsi_base: usize) callconv(.c) i64 {
    var data_active: u32 = 0;
    var clk_active: u32 = 0;
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        const v = mmioRead32(dsi_base, DSI_LANE_STATUS);
        if ((v & 0x0f) == 0) data_active += 1;
        if ((v & 0x10) == 0) clk_active += 1;
        udelay(100);
    }
    return (@as(i64, data_active) << 32) | @as(i64, clk_active);
}

/// Did the host actually shift bytes onto the wire?
///
/// "DMA completed, no error" cannot tell two failures apart:
///
///   A. the DMA never delivered the right bytes to the host -- address,
///      translation or cache
///   B. the host framed them correctly but the PHY never drove the pads
///
/// FIFO_STATUS and LANE_STATUS separate them: they report fill/empty per
/// lane and whether the lanes ever left stop state, rather than whether
/// a busy bit cleared.
///
/// MUST be sampled with the DPU streaming. Half the bits in both
/// registers describe whether traffic is flowing, so reading an idle
/// link and comparing against a mid-stream Linux compares nothing.
///
///   63:32  FIFO_STATUS   Linux, streaming: 0x00001210
///   31:0   LANE_STATUS   Linux, streaming: 0x00001F00
///          bits 0-4 per-lane STOPSTATE, bits 8-12 ULPS_ACTIVE_NOT
///
/// STOPSTATE still set while the DPU streams means the lanes are not
/// transmitting despite a running timing engine: case B.
export fn sheng_mdss_dsi_txpath_state(dsi0_base: usize) callconv(.c) i64 {
    const fifo = mmioRead32(dsi0_base, DSI_FIFO_STATUS);
    const lane = mmioRead32(dsi0_base, DSI_LANE_STATUS);
    return (@as(i64, fifo) << 32) | @as(i64, lane);
}

export fn sheng_mdss_phy144_mark(slot: u32, phy_base: usize) callconv(.c) void {
    if (slot >= 8) return;
    g_phy144_marks[slot] = @truncate(mmioRead32(phy_base, 0x144));
}

export fn sheng_mdss_phy144_marks() callconv(.c) i64 {
    var v: i64 = 0;
    for (g_phy144_marks, 0..) |m, i| {
        v |= @as(i64, m) << @intCast(i * 8);
    }
    return v;
}






// ---------------------------------------------------------------------
// Platform glue: TLMM pin control, GCC branch enable, and RPMh voting
// over the raw APPS_RSC registers.
//
// These were the last register programming left in the C file. The C
// side keeps only what needs U-Boot's driver model.
// ---------------------------------------------------------------------

const TLMM_BASE: usize = 0x00f100000;
const TLMM_PIN_STRIDE: usize = 0x1000;
const TLMM_CFG: usize = 0x0;
const TLMM_IN_OUT: usize = 0x4;
const TLMM_MUX_FUNC_MASK: u32 = 0x7 << 2;
const TLMM_OE: u32 = 1 << 9;
const TLMM_OUT: u32 = 1 << 1;

/// Drive a pin as a plain output. mux bits 0 select native GPIO, bit 9
/// is output enable, IN_OUT bit 1 carries the value.
///
/// Raw MMIO rather than the gpio uclass: a .bind hook hangs this board.
export fn sheng_gpio_set(gpio: u32, high: bool) callconv(.c) void {
    const pin = TLMM_BASE + TLMM_PIN_STRIDE * gpio;

    var v = mmioRead32(pin, TLMM_CFG);
    v &= ~TLMM_MUX_FUNC_MASK;
    v |= TLMM_OE;
    mmioWrite32(pin, TLMM_CFG, v);

    v = mmioRead32(pin, TLMM_IN_OUT);
    if (high) v |= TLMM_OUT else v &= ~TLMM_OUT;
    mmioWrite32(pin, TLMM_IN_OUT, v);
}

const GCC_BASE: usize = 0x00100000;
const GCC_DISP_HF_AXI_CBCR: usize = 0x2700c;

/// The AXI data path clock, as opposed to the AHB register path. The DSI
/// command DMA fetches packets over it; gated, the engine latches
/// CMD_MODE_DMA_BUSY forever having never fetched a byte and never
/// errored. BRANCH_HALT_SKIP, so there is no ready bit to poll.
export fn sheng_gcc_disp_hf_axi_enable() callconv(.c) u32 {
    mmioSetBits32(GCC_BASE, GCC_DISP_HF_AXI_CBCR, 1);
    // Readback proves both that the write landed and that GCC is
    // reachable at all.
    return mmioRead32(GCC_BASE, GCC_DISP_HF_AXI_CBCR);
}

// apps_rsc@17a00000: qcom,drv-id = <2>, tcs-offset 0xd00. ACTIVE_TCS is
// first in qcom,tcs-config, so it takes indices 0..2.
const APPS_RSC_DRV2_BASE: usize = 0x17a20000;
const APPS_RSC_TCS_OFFSET: usize = 0xd00;

// Slot 0 always. rpmh-rsc.c tracks free slots in a software bitmap, not
// a register, and on a fresh boot that bitmap picks slot 0 too. Every
// send here polls to completion before returning and nothing else
// touches the RSC, so there is no contention to arbitrate.
const APPS_RSC_ACTIVE_TCS_FIRST: u32 = 0;

const TCS_AMC_MODE_ENABLE: u32 = 1 << 16;
const TCS_AMC_MODE_TRIGGER: u32 = 1 << 24;
const CMD_MSGID_BASE: u32 = 8;
const CMD_MSGID_RESP_REQ: u32 = 1 << 8;
const CMD_MSGID_WRITE: u32 = 1 << 16;
const CMD_STATUS_COMPL: u32 = 1 << 16;
const RSC_POLL_TIMEOUT_US: u32 = 200000;

/// The two register layouts rpmh-rsc.c picks between on the major
/// version in RSC_DRV_ID (offset 0).
const RscRegs = struct {
    tcs_stride: usize,
    cmd_wait_for_cmpl: usize,
    control: usize,
    status: usize,
    cmd_enable: usize,
    cmd_msgid: usize,
    cmd_addr: usize,
    cmd_data: usize,
    cmd_status: usize,
};

const rsc_regs_v2_7 = RscRegs{
    .tcs_stride = 672,
    .cmd_wait_for_cmpl = 0x10, .control = 0x14, .status = 0x18,
    .cmd_enable = 0x1c, .cmd_msgid = 0x30, .cmd_addr = 0x34,
    .cmd_data = 0x38, .cmd_status = 0x3c,
};

const rsc_regs_v3_0 = RscRegs{
    .tcs_stride = 672,
    .cmd_wait_for_cmpl = 0x20, .control = 0x24, .status = 0x28,
    .cmd_enable = 0x2c, .cmd_msgid = 0x34, .cmd_addr = 0x38,
    .cmd_data = 0x3c, .cmd_status = 0x40,
};

fn rscTcsReg(regs: *const RscRegs, off: usize, tcs_id: u32) usize {
    return APPS_RSC_DRV2_BASE + APPS_RSC_TCS_OFFSET +
        regs.tcs_stride * tcs_id + off;
}

/// Write and poll until the value reads back. -ETIMEDOUT on failure.
fn rscWriteRegSync(regs: *const RscRegs, off: usize, tcs_id: u32, data: u32) c_int {
    const addr = rscTcsReg(regs, off, tcs_id);

    mmioWrite32(addr, 0, data);
    var i: u32 = 0;
    while (i < RSC_POLL_TIMEOUT_US) : (i += 1) {
        if (mmioRead32(addr, 0) == data) return 0;
        udelay(1);
    }
    return -110;
}

/// One ACTIVE_ONLY RPMh write, polled to hardware completion.
///
/// Mirrors rpmh_rsc_send_data() / __tcs_buffer_write() /
/// __tcs_set_trigger(). Do NOT write CMD_WAIT_FOR_CMPL: the
/// CMD_MSGID_RESP_REQ bit already asks for completion and the real
/// driver never touches that register. This RSC sequences rails for the
/// whole SoC, and a stray write here breaks AHB access chip-wide.
export fn sheng_rsc_send_active_write(resource_addr: u32, data: u32) callconv(.c) c_int {
    const rsc_id = mmioRead32(APPS_RSC_DRV2_BASE, 0);
    const major = (rsc_id >> 16) & 0xff;
    const regs: *const RscRegs = if (major == 3) &rsc_regs_v3_0 else &rsc_regs_v2_7;
    const tcs_id = APPS_RSC_ACTIVE_TCS_FIRST;

    mmioWrite32(rscTcsReg(regs, regs.cmd_msgid, tcs_id), 0,
        CMD_MSGID_BASE | CMD_MSGID_RESP_REQ | CMD_MSGID_WRITE);
    mmioWrite32(rscTcsReg(regs, regs.cmd_addr, tcs_id), 0, resource_addr);
    mmioWrite32(rscTcsReg(regs, regs.cmd_data, tcs_id), 0, data);
    mmioSetBits32(rscTcsReg(regs, regs.cmd_enable, tcs_id), 0, 1);

    // __tcs_set_trigger(): clear trigger, clear enable, set enable, then
    // set enable|trigger. Exact sequence, each step polled.
    var enable = mmioRead32(rscTcsReg(regs, regs.control, tcs_id), 0);
    var ret: c_int = undefined;

    enable &= ~TCS_AMC_MODE_TRIGGER;
    ret = rscWriteRegSync(regs, regs.control, tcs_id, enable);
    if (ret != 0) return ret;

    enable &= ~TCS_AMC_MODE_ENABLE;
    ret = rscWriteRegSync(regs, regs.control, tcs_id, enable);
    if (ret != 0) return ret;

    enable = TCS_AMC_MODE_ENABLE;
    ret = rscWriteRegSync(regs, regs.control, tcs_id, enable);
    if (ret != 0) return ret;

    enable |= TCS_AMC_MODE_TRIGGER;
    mmioWrite32(rscTcsReg(regs, regs.control, tcs_id), 0, enable);

    var i: u32 = 0;
    while (i < RSC_POLL_TIMEOUT_US) : (i += 1) {
        if ((mmioRead32(rscTcsReg(regs, regs.cmd_status, tcs_id), 0) &
             CMD_STATUS_COMPL) != 0) return 0;
        udelay(1);
    }
    return -110;
}

/// Interconnect bandwidth vote for one BCM.
///
/// Max in both 14-bit fields. A token vote_x/vote_y of 1 is what
/// bcm_aggregate() forces onto keepalive BCMs when nobody has asked for
/// anything: accepted, and no real bandwidth. Computing a realistic
/// value needs unit/width from cmd-db aux data; max opens the gate.
export fn sheng_bcm_vote(addr: u32) callconv(.c) c_int {
    const commit: u32 = 1 << 30;
    const valid: u32 = 1 << 29;
    const vote_max: u32 = 0x3fff;

    return sheng_rsc_send_active_write(addr,
        commit | valid | (vote_max << 14) | vote_max);
}

/// RPMh VRM regulator vote: voltage, then mode, then enable -- the order
/// the regulator core uses.
///
/// Mode must be HPM. An LDO in LPM regulates fine at static load, so a
/// voltage readback looks nominal, but it current-limits under the
/// transients a 4-lane D-PHY draws switching LP to HS: the PLL locks,
/// engines report healthy, and the pads cannot swing. 7 covers both
/// classes here -- PMIC5_LDO_MODE_HPM and PMIC5_SMPS_MODE_PWM are both
/// 7.
///
/// RPMh aggregates across masters, so this is a no-op if something else
/// already voted HPM. No change here does not exonerate a rail.
export fn sheng_regulator_vote(addr: u32, millivolts: u32) callconv(.c) c_int {
    const REG_VRM_VOLTAGE: u32 = 0x0;
    const REG_ENABLE: u32 = 0x4;
    const REG_VRM_MODE: u32 = 0x8;

    var ret = sheng_rsc_send_active_write(addr + REG_VRM_VOLTAGE, millivolts);
    if (ret != 0) return ret;

    ret = sheng_rsc_send_active_write(addr + REG_VRM_MODE, 7);
    if (ret != 0) return ret;

    return sheng_rsc_send_active_write(addr + REG_ENABLE, 1);
}

