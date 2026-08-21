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
/// U-Boot microsecond timer (include/time.h). Used to measure how long a
/// command DMA actually takes -- see bbCmdTrace().
extern fn timer_get_us() callconv(.c) c_ulong;

// ===========================================================================
// ULTRA-DEBUG BLACKBOX
// ===========================================================================
//
// Every diagnostic in this project has had to be smuggled out as a sheng.*
// entry on the kernel command line, which CONFIG_SYS_CBSIZE caps at 512
// bytes. That budget has shaped -- and repeatedly distorted -- the whole
// investigation: variables had to be swapped out to make room, whole
// register blocks were reduced to "first mismatching offset + count" with
// the actual values never seen, and each boot answered roughly one
// question.
//
// This writes an ASCII log to a fixed DRAM window instead. Linux reads it
// back through /dev/mem (verified: CONFIG_STRICT_DEVMEM is not set on this
// kernel and a read of 0xa5000000 succeeds), so the size limit becomes
// ~512KB rather than ~512 bytes.
//
// ASCII rather than a packed binary format on purpose: `dd | strings` is
// enough to read it, with no decoder to keep in sync with the emitter --
// a decoder that silently drifts out of sync is exactly how the RDBK_DATA0
// misreading survived for so long.
//
// Layout at BB_BASE:
//   +0  u32 magic 'SHGB'  -- written LAST, so a torn/partial log is
//                            detectable rather than silently half-read
//   +4  u32 byte length of the payload
//   +8  u32 overflow flag (payload was truncated at BB_CAP)
//   +12 u32 reserved
//   +16 payload, NUL-padded ASCII
//
// 0xa5000000 sits above SHENG_MDSS_FB_ADDR (0xa3200000 + 24.8MB, ending
// ~0xa4b10000) and well inside the 0xa3080000-0xccd00000 free System RAM
// span from a live /proc/iomem. Linux will happily allocate over it later,
// so the kernel DT also reserves it -- see the reserved-memory node added
// in nixos/kernel/default.nix. The magic check makes a clobbered read
// obvious either way.
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
/// SAFE SUBSET OF THE CONTROLLER COLD-START (SPEC.md task #5 log).
///
/// b66 tried to call sheng_mdss_full_teardown() at probe and hung the
/// board outright -- no backlight, no boot. That function is TERMINAL by
/// construction: it ends with sheng_mdss_dispcc_dsi_clks_stop() and
/// sheng_mdss_core_reset(), gating the very branches the rest of probe
/// still needs, and sheng_mdss_dpu_stop() writes/polls DPU registers that
/// cannot complete with only AHB-from-XO running. Safe at handoff because
/// nothing runs after it; fatal in the middle of probe.
///
/// This is the part of it that is genuinely safe this early: power the two
/// DSI PHYs down and nothing else. PHY register access is already proven
/// safe at this point in probe -- sheng_mdss_abl_state3() reads both PHYs
/// from exactly here every boot. No DPU writes, no clock gating, no core
/// reset (the existing cold-start pulses that a few lines later anyway).
///
/// The motivation is unchanged and still the best-evidenced lead we have:
/// Linux's FIRST bring-up on top of a live controller fails a DCS read
/// (ret=-61) and its SECOND, after a full disable, succeeds (0x9e). ABL
/// hands us a live controller the same way.
export fn sheng_mdss_dsi_phys_off(dsi0_phy_base: usize, dsi1_phy_base: usize) callconv(.c) void {
    dsiPhyDisable(dsi0_phy_base);
    dsiPhyDisable(dsi1_phy_base);
}

/// Did MDSS_GDSC ACTUALLY collapse? (SPEC.md task #5 log)
///
/// sheng_mdss_gdsc_disable() sets SW_COLLAPSE and waits 200us but never
/// checks the result. A GDSC held up by another subsystem's vote simply
/// stays on, and the entire "cold-start reset pass" this driver performs
/// -- collapse the power domain, pulse the core reset -- would be a no-op,
/// leaving every scrap of ABL's controller state intact underneath our
/// bring-up. That is exactly the failure mode the Linux blank/unblank
/// experiment points at, and it has never been verified once.
///
/// Bit 31 of the GDSCR is PWR_ON (qcom gdsc.c's own PWR_ON_MASK, read by
/// gdsc_is_enabled()). Sampled at three points, low byte of the status
/// nibble each:
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

/// ROOT CAUSE, FOUND b95 -- this ran at the WRONG RATE for the entire
/// life of this driver.
///
/// `disp_cc_pll0_config` in dispcc-sm8550.c (l=0xd, alpha=0x6492) is the
/// kernel's INITIAL config, applied once by
/// clk_lucid_evo_pll_configure() at probe. It is NOT the operating rate.
/// The kernel then reprograms L/ALPHA via clk_alpha_pll_set_rate() when
/// mdp_clk_src actually requests its frequency. We copied the initial
/// config and stopped, so the PLL stayed parked at its boot rate.
///
/// The old comment here claimed those values gave "~1,000,000,000 Hz-ish".
/// That arithmetic is simply wrong, and being wrong is what hid this:
///     19.2MHz * (13 + 0x6492/0x10000) = 19.2 * 13.3929 = 257.1 MHz
/// MDP_CLK_DIV_REG_VAL below is 5, i.e. hid_div 3, matching the kernel's
/// F(514000000, P_DISP_CC_PLL0_OUT_MAIN, 3, 0, 0). A 257.1MHz parent
/// through /3 gives an 85.7MHz mdp core clock instead of 514MHz --
/// SIX TIMES too slow.
///
/// MEASURED on live rendering Linux (devmem, dispcc_base 0x0af00000):
///     0x010 L_VAL     = 0x44440050   (ours was 0x4444000d)
///     0x014 ALPHA_VAL = 0x00005000   (ours was 0x00006492)
/// Every other PLL0 register -- CONFIG_CTL/U/U1, TEST_CTL/U/U1/U2,
/// USER_CTL/U -- already matched byte-for-byte, and the 0x4444 in the
/// upper half of L_VAL is TRION_PLL_CAL_VAL shifted, which Linux keeps
/// identical. Only the rate differed.
///
///     L=0x50=80, alpha=0x5000 -> 0x5000/0x10000 = 0.3125
///     19.2MHz * 80.3125 = 1542.0 MHz, and 1542/3 = 514 MHz exactly.
///
/// This is what starved the link. The DPU could not composite fast
/// enough to feed the DSI, so the lane FIFOs ran dry -- the long-standing
/// unexplained FIFO_STATUS 0x11111210 (all four DLN*_HS_FIFO_EMPTY set)
/// against live Linux's 0x00001210 -- while every configuration register
/// still read back correct and the INTF kept counting frames, because
/// INTF timing comes off the DSI PHY PLL and is independent of mdp_clk.
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
/// REAL BUG FOUND, MEASURED OFF LIVE SILICON (SPEC.md task #5 log).
///
/// These were set to DSI1's OWN PHY PLL outputs (DSI1_PHY_PLL_OUT_DSICLK=3
/// / _BYTECLK=4). That is wrong for a bonded link, and both the devicetree
/// and the hardware say so.
///
/// sm8550-xiaomi-sheng.dts, &mdss_dsi1:
///     qcom,dual-dsi-mode;
///     qcom,sync-dual-dsi;
///     assigned-clock-parents = <&mdss_dsi0_phy 0>, <&mdss_dsi0_phy 1>;
/// i.e. DSI1's byte and pixel clocks are parented to DSI **0**'s PHY.
/// (`qcom,master-dsi` sits on &mdss_dsi0, confirming DSI0 is master.)
///
/// Read back off this device's DISPCC while Linux drove the panel:
///     pclk0 CFG=0x00000101 src_sel=1      byte0 CFG=0x00000201 src_sel=2
///     pclk1 CFG=0x00000101 src_sel=1      byte1 CFG=0x00000201 src_sel=2
/// All four source from DSI0's PHY PLL. Ours used 3 and 4 for the DSI1
/// pair.
///
/// Why this is a real fault and not cosmetic: the two PHY PLLs are
/// independent oscillators. Configured identically they run at the same
/// nominal rate, but with arbitrary phase and independent drift. A
/// stitched dual-DSI panel requires both halves clocked from ONE source --
/// that is the entire purpose of qcom,sync-dual-dsi and of BITCLK_SEL=1 on
/// the slave PHY. Feeding DSI1's packetiser from a second, free-running
/// PLL breaks the lock-step the DDIC depends on.
///
/// This escaped every audit because DISPCC has no verification table --
/// the same self-selected-sample blind spot that previously hid
/// CTL_FETCH_PIPE_ACTIVE, DSC_CLK_CTRL, the MDSS UBWC block and the
/// unconfigured slave PLL. See sheng_mdss_dispcc_audit() below.
const PCLK1_SRC_SEL_DSI1_DSICLK: u32 = 1; // DSI0_PHY_PLL_OUT_DSICLK -- master's PLL
const BYTE0_CLK_SRC_CMD_RCGR: usize = 0x8108;
const BYTE0_CLK_CBCR: usize = 0x8028;
const BYTE0_INTF_CLK_CBCR: usize = 0x802c;
// REAL GAP (SPEC.md task #5 log): the byte-interface DIVIDERS.
//
// dispcc-sm8550.c declares disp_cc_mdss_byte0_div_clk_src at .reg = 0x8120
// and byte1 at 0x813c -- clk_regmap_div, shift 0, width 4. These are the
// PARENTS of disp_cc_mdss_byte{0,1}_intf_clk, the branches this driver
// already enables at 0x802c / 0x8034.
//
// dsi_host.c sets `msm_host->byte_intf_clk_rate = msm_host->byte_clk_rate
// / 2` and calls clk_set_rate() on byte_intf_clk, which lands on these
// divider registers. clk_regmap_div encodes (divisor - 1), so /2 == 1.
//
// This driver enables the byte_intf BRANCHES but never programs their
// DIVIDERS, so they keep whatever ABL left -- most likely 0, i.e. divide
// by 1, running the DSI byte interface at twice its intended rate.
//
// It is invisible to every audit we have: DISPCC had no verify table until
// today, and even that only covers the four RCG CFG registers, not these
// standalone divider registers. Same shape as every other real find --
// state that lives outside the offsets anyone thought to compare.
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

/// AHB BRANCH ONLY -- no PLL0, no MDP/LUT/VSYNC, and critically NO
/// mdssCoreBcrReset() (SPEC.md task #5 log).
///
/// Exists solely so sheng_mdss_abl_state*() can read the MDSS register
/// space safely before this driver tears ABL's configuration down. Those
/// reads need MDSS_GDSC powered and the DISPCC AHB config clock running;
/// at the top of probe() neither is guaranteed, the AHB slave never acks,
/// and the CPU wedges with no backlight and no boot (measured -- this is
/// exactly how the first attempt at the ABL probe killed the board).
///
/// AHB_CLK_SRC parents from XO, not PLL0, so this needs none of the PLL
/// bring-up. Nothing here resets or reconfigures anything ABL left behind,
/// so the state being sampled afterwards is genuinely ABL's.
export fn sheng_mdss_dispcc_ahb_only(dispcc_base: usize) callconv(.c) c_int {
    const ret = rcg2ConfigureHidOnly(dispcc_base, AHB_CLK_SRC_CMD_RCGR, AHB_CLK_SRC_SEL_XO, AHB_CLK_DIV_REG_VAL);
    if (ret != 0) return ret;
    return clkBranchEnable(dispcc_base, AHB_CLK_CBCR);
}

/// ABL HANDOFF STATE (SPEC.md task #5 log).
///
/// board/qualcomm/sheng.env's own notes refer to the `cont_splash` region,
/// i.e. ABL uses CONTINUOUS SPLASH: it does not draw and stop, it hands
/// over with DPU, DSI, PHY and panel all actively running. For the first
/// few milliseconds of probe() this exact silicon is correctly driving this
/// exact panel -- and our first action destroys it (reset asserted,
/// avdd/avee dropped, GDSC collapsed, MDSS core BCR pulsed).
///
/// We have never looked at that state. It matters because every "matches
/// live" result in this project is against LINUX's registers, captured
/// after Linux's own full teardown and re-init with its own clock tree,
/// regulator votes and SMMU context. ABL's state is the one that works
/// WITHOUT any of that, at the exact point in boot where we run. With
/// 180+ registers now matching Linux across DSI0/DSI1/DPU/MDSS/PHY-CMN/
/// PHY-PLL and the panel still black, a different reference is worth more
/// than another Linux diff.
///
/// DSI and PHY only -- deliberately no DPU access on this first pass, so
/// the risk surface stays as small as possible while still answering the
/// question. VIDEO_MODE_ENGINE_BUSY (STATUS0 bit3) plus a locked PLL is
/// enough to say whether ABL is streaming.
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
/// FOUND BY PHY WRITE TRACE (SPEC.md task #5 log).
///
/// Distinct from PLL_OUTDIV (0x0a8) above, which this driver already
/// writes. This is REG_DSI_7nm_PHY_PLL_PLL_OUTDIV_RATE -- the PLL's
/// OUTPUT DIVIDER -- read-modify-written by dsi_7nm_pll_restore_state():
///
///     val = readl(pll_base + REG_DSI_7nm_PHY_PLL_PLL_OUTDIV_RATE);
///     val &= ~0x3;
///     val |= cached->pll_out_div;
///     writel(val, pll_base + REG_DSI_7nm_PHY_PLL_PLL_OUTDIV_RATE);
///
/// Hooking writel() inside dsi_phy_7nm.c and diffing the offsets the
/// working kernel touches against ours: CMN matched perfectly (all 35
/// offsets, and all 14 D-PHY timing values identical), but the PLL set
/// differed by exactly this one register. Invisible to our PHY audit
/// twice over -- never written by us, and never in the audit table, the
/// same shape as the VID_CFG1 offset bug the DSI host trace found.
///
/// Traced value 0x00000000, and live reads 0x00000000 on BOTH PHYs, so
/// the divider is bypassed. Left unwritten it holds whatever ABL/POR
/// leaves; a non-zero low 2 bits would divide the PLL output and put the
/// whole link off-rate. Our measured 142Hz suggests it already happens to
/// be 0 here, so this is correctness rather than a likely root cause --
/// but it is a genuine divergence and free to close.
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

/// INTERLEAVED DUAL-PHY START (SPEC.md task #5 log).
///
/// Measured by hooking writel() in dsi_phy_7nm.c on the working kernel.
/// dsi_pll_7nm_vco_prepare() does NOT finish the master before starting on
/// the slave -- it interleaves them, one operation at a time:
///
///   P0cmn 024=7f  P0pll 528=c0     enable_pll_bias(MASTER)
///   P1cmn 024=7f  P1pll 528=c0     enable_pll_bias(SLAVE)
///   P0cmn 03c=1                    MASTER PLL START  (+ lock poll)
///   P0cmn 128=1/0                  dig_reset(master)
///   P1cmn 128=1/0                  dig_reset(slave)
///   ... then global_clk master, global_clk slave, RBUF master, RBUF slave
///
/// The slave's PLL bias is raised BEFORE the master's PLL is ever started,
/// and the slave's digital reset lands in the same window as the master's.
///
/// This driver used to run the whole master sequence (bias, start, lock,
/// dig reset, global clk, RBUF) and only then begin the slave's -- so the
/// slave was biased and reset long after the master had started AND
/// locked. Measured consequence: our slave PHY reports CMN_PHY_STATUS =
/// 0x19 where live silicon reports 0x1F, i.e. bits 1 and 2 never assert,
/// while REFGEN (bit 0) and bits 3-4 do. Every CMN value and offset on the
/// slave already matched; ordering was the only variable left.
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

/// VERBATIM KERNEL BRING-UP REPLAY (SPEC.md task #5 log).
///
/// The endpoint of the trace methodology. Every configurable register in
/// the display path is now verified identical to working silicon by
/// exhaustive sweep -- PHY CMN 124/124, PHY lane+PLL 412 (only dynamic
/// calibration status differs), DSI host 176/176 (only read-only
/// CLK_STATUS differs), plus full write-trace diffs of DPU, DISPCC, VBIF
/// and MDSS. Every clock is confirmed active including AON_ESCCLK. Every
/// command byte is confirmed correct in DRAM. And Linux renders on this
/// same hardware moments later.
///
/// So the difference is not any register VALUE. This removes the last
/// degree of freedom: instead of reproducing the kernel's end state, replay
/// its exact WRITE SEQUENCE -- every (target, offset, value) it issues to
/// both PHYs and both DSI hosts, in order, including transient values that
/// are later overwritten and repeated writes we would otherwise normalise
/// away. Captured from this device while it was rendering, truncated at
/// the first DCS command.
///
/// Waits are re-inserted where the kernel blocks: REFGEN ready after
/// GLBL_DIGTOP_SPARE10, PLL lock after CMN_PLL_CNTRL=1, and the 20ms
/// DSI_RESET hold. A blind replay without those would race the hardware.
///
/// t: 0=PHY0, 1=PHY1, 2=DSI0 host, 3=DSI1 host.
const ReplayEntry = struct { t: u8, off: usize, val: u32 };
const kernel_bringup_replay = [_]ReplayEntry{
    .{ .t = 0, .off = 0x024, .val = 0x00000020 },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x00000020 },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x00000020 },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000020 },
    .{ .t = 1, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 1, .off = 0x528, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000020 },
    .{ .t = 1, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 1, .off = 0x528, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000020 },
    .{ .t = 1, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 1, .off = 0x528, .val = 0x00000000 },
    .{ .t = 1, .off = 0x024, .val = 0x00000000 },
    .{ .t = 2, .off = 0x128, .val = 0x00000001 },
    .{ .t = 2, .off = 0x128, .val = 0x00000000 },
    .{ .t = 3, .off = 0x128, .val = 0x00000001 },
    .{ .t = 3, .off = 0x128, .val = 0x00000000 },
    .{ .t = 0, .off = 0x1ac, .val = 0x00000001 },
    .{ .t = 0, .off = 0x024, .val = 0x00000060 },
    .{ .t = 0, .off = 0x03c, .val = 0x00000000 },
    .{ .t = 0, .off = 0x01c, .val = 0x00000000 },
    .{ .t = 0, .off = 0x114, .val = 0x00000004 },
    .{ .t = 0, .off = 0x034, .val = 0x00000021 },
    .{ .t = 0, .off = 0x038, .val = 0x00000084 },
    .{ .t = 0, .off = 0x020, .val = 0x00000044 },
    .{ .t = 0, .off = 0x110, .val = 0x00000019 },
    .{ .t = 0, .off = 0x030, .val = 0x00000000 },
    .{ .t = 0, .off = 0x10c, .val = 0x00000000 },
    .{ .t = 0, .off = 0x0ec, .val = 0x00000088 },
    .{ .t = 0, .off = 0x104, .val = 0x00000000 },
    .{ .t = 0, .off = 0x0f4, .val = 0x0000003c },
    .{ .t = 0, .off = 0x0f8, .val = 0x00000038 },
    .{ .t = 0, .off = 0x100, .val = 0x00000055 },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x0a0, .val = 0x0000001f },
    .{ .t = 0, .off = 0x02c, .val = 0x00000040 },
    .{ .t = 0, .off = 0x014, .val = 0x00000010 },
    .{ .t = 0, .off = 0x0b4, .val = 0x00000000 },
    .{ .t = 0, .off = 0x0b8, .val = 0x00000027 },
    .{ .t = 0, .off = 0x0bc, .val = 0x0000000a },
    .{ .t = 0, .off = 0x0c0, .val = 0x0000000c },
    .{ .t = 0, .off = 0x0c4, .val = 0x00000027 },
    .{ .t = 0, .off = 0x0c8, .val = 0x00000025 },
    .{ .t = 0, .off = 0x0cc, .val = 0x0000000a },
    .{ .t = 0, .off = 0x0d0, .val = 0x0000000b },
    .{ .t = 0, .off = 0x0d4, .val = 0x00000007 },
    .{ .t = 0, .off = 0x0d8, .val = 0x00000002 },
    .{ .t = 0, .off = 0x0dc, .val = 0x00000004 },
    .{ .t = 0, .off = 0x0e0, .val = 0x00000000 },
    .{ .t = 0, .off = 0x0e4, .val = 0x00000023 },
    .{ .t = 0, .off = 0x0e8, .val = 0x0000001a },
    .{ .t = 0, .off = 0x214, .val = 0x00000000 },
    .{ .t = 0, .off = 0x210, .val = 0x00000000 },
    .{ .t = 0, .off = 0x294, .val = 0x00000000 },
    .{ .t = 0, .off = 0x290, .val = 0x00000000 },
    .{ .t = 0, .off = 0x314, .val = 0x00000000 },
    .{ .t = 0, .off = 0x310, .val = 0x00000000 },
    .{ .t = 0, .off = 0x394, .val = 0x00000000 },
    .{ .t = 0, .off = 0x390, .val = 0x00000000 },
    .{ .t = 0, .off = 0x414, .val = 0x00000000 },
    .{ .t = 0, .off = 0x410, .val = 0x00000000 },
    .{ .t = 0, .off = 0x214, .val = 0x00000003 },
    .{ .t = 0, .off = 0x200, .val = 0x00000000 },
    .{ .t = 0, .off = 0x204, .val = 0x00000000 },
    .{ .t = 0, .off = 0x208, .val = 0x0000000a },
    .{ .t = 0, .off = 0x218, .val = 0x00000040 },
    .{ .t = 0, .off = 0x280, .val = 0x00000000 },
    .{ .t = 0, .off = 0x284, .val = 0x00000000 },
    .{ .t = 0, .off = 0x288, .val = 0x0000000a },
    .{ .t = 0, .off = 0x298, .val = 0x00000040 },
    .{ .t = 0, .off = 0x300, .val = 0x00000000 },
    .{ .t = 0, .off = 0x304, .val = 0x00000000 },
    .{ .t = 0, .off = 0x308, .val = 0x0000000a },
    .{ .t = 0, .off = 0x318, .val = 0x00000040 },
    .{ .t = 0, .off = 0x380, .val = 0x00000000 },
    .{ .t = 0, .off = 0x384, .val = 0x00000000 },
    .{ .t = 0, .off = 0x388, .val = 0x0000000a },
    .{ .t = 0, .off = 0x398, .val = 0x00000046 },
    .{ .t = 0, .off = 0x400, .val = 0x00000000 },
    .{ .t = 0, .off = 0x404, .val = 0x00000000 },
    .{ .t = 0, .off = 0x408, .val = 0x0000008a },
    .{ .t = 0, .off = 0x418, .val = 0x00000041 },
    .{ .t = 0, .off = 0x654, .val = 0x00000000 },
    .{ .t = 0, .off = 0x010, .val = 0x000000f1 },
    .{ .t = 0, .off = 0x014, .val = 0x00000010 },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x5bc, .val = 0x00000012 },
    .{ .t = 0, .off = 0x5e0, .val = 0x0000000f },
    .{ .t = 0, .off = 0x5e4, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5e8, .val = 0x00000080 },
    .{ .t = 0, .off = 0x5ec, .val = 0x00000002 },
    .{ .t = 0, .off = 0x658, .val = 0x00000040 },
    .{ .t = 0, .off = 0x694, .val = 0x00000006 },
    .{ .t = 0, .off = 0x750, .val = 0x00000010 },
    .{ .t = 0, .off = 0x748, .val = 0x000000a0 },
    .{ .t = 0, .off = 0x758, .val = 0x00000001 },
    .{ .t = 0, .off = 0x740, .val = 0x00000008 },
    .{ .t = 0, .off = 0x518, .val = 0x00000001 },
    .{ .t = 0, .off = 0x504, .val = 0x00000003 },
    .{ .t = 0, .off = 0x510, .val = 0x00000000 },
    .{ .t = 0, .off = 0x520, .val = 0x00000000 },
    .{ .t = 0, .off = 0x524, .val = 0x0000004e },
    .{ .t = 0, .off = 0x544, .val = 0x00000040 },
    .{ .t = 0, .off = 0x568, .val = 0x000000ba },
    .{ .t = 0, .off = 0x578, .val = 0x0000000c },
    .{ .t = 0, .off = 0x5a8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5b8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5c8, .val = 0x00000008 },
    .{ .t = 0, .off = 0x660, .val = 0x0000000a },
    .{ .t = 0, .off = 0x668, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x670, .val = 0x00000084 },
    .{ .t = 0, .off = 0x670, .val = 0x00000082 },
    .{ .t = 0, .off = 0x678, .val = 0x0000004c },
    .{ .t = 0, .off = 0x690, .val = 0x00000080 },
    .{ .t = 0, .off = 0x590, .val = 0x00000029 },
    .{ .t = 0, .off = 0x590, .val = 0x0000002f },
    .{ .t = 0, .off = 0x594, .val = 0x0000002a },
    .{ .t = 0, .off = 0x594, .val = 0x0000003f },
    .{ .t = 0, .off = 0x760, .val = 0x00000022 },
    .{ .t = 1, .off = 0x760, .val = 0x00000022 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x0000005f },
    .{ .t = 1, .off = 0x1ac, .val = 0x00000001 },
    .{ .t = 1, .off = 0x024, .val = 0x00000060 },
    .{ .t = 1, .off = 0x03c, .val = 0x00000000 },
    .{ .t = 1, .off = 0x01c, .val = 0x00000000 },
    .{ .t = 1, .off = 0x114, .val = 0x00000004 },
    .{ .t = 1, .off = 0x034, .val = 0x00000021 },
    .{ .t = 1, .off = 0x038, .val = 0x00000084 },
    .{ .t = 1, .off = 0x020, .val = 0x00000044 },
    .{ .t = 1, .off = 0x110, .val = 0x00000019 },
    .{ .t = 1, .off = 0x030, .val = 0x00000000 },
    .{ .t = 1, .off = 0x10c, .val = 0x00000000 },
    .{ .t = 1, .off = 0x0ec, .val = 0x00000088 },
    .{ .t = 1, .off = 0x104, .val = 0x00000000 },
    .{ .t = 1, .off = 0x0f4, .val = 0x0000003c },
    .{ .t = 1, .off = 0x0f8, .val = 0x00000038 },
    .{ .t = 1, .off = 0x100, .val = 0x00000055 },
    .{ .t = 1, .off = 0x024, .val = 0x0000007f },
    .{ .t = 1, .off = 0x0a0, .val = 0x0000001f },
    .{ .t = 1, .off = 0x02c, .val = 0x00000040 },
    .{ .t = 1, .off = 0x014, .val = 0x00000014 },
    .{ .t = 1, .off = 0x0b4, .val = 0x00000000 },
    .{ .t = 1, .off = 0x0b8, .val = 0x00000027 },
    .{ .t = 1, .off = 0x0bc, .val = 0x0000000a },
    .{ .t = 1, .off = 0x0c0, .val = 0x0000000c },
    .{ .t = 1, .off = 0x0c4, .val = 0x00000027 },
    .{ .t = 1, .off = 0x0c8, .val = 0x00000025 },
    .{ .t = 1, .off = 0x0cc, .val = 0x0000000a },
    .{ .t = 1, .off = 0x0d0, .val = 0x0000000b },
    .{ .t = 1, .off = 0x0d4, .val = 0x00000007 },
    .{ .t = 1, .off = 0x0d8, .val = 0x00000002 },
    .{ .t = 1, .off = 0x0dc, .val = 0x00000004 },
    .{ .t = 1, .off = 0x0e0, .val = 0x00000000 },
    .{ .t = 1, .off = 0x0e4, .val = 0x00000023 },
    .{ .t = 1, .off = 0x0e8, .val = 0x0000001a },
    .{ .t = 1, .off = 0x214, .val = 0x00000000 },
    .{ .t = 1, .off = 0x210, .val = 0x00000000 },
    .{ .t = 1, .off = 0x294, .val = 0x00000000 },
    .{ .t = 1, .off = 0x290, .val = 0x00000000 },
    .{ .t = 1, .off = 0x314, .val = 0x00000000 },
    .{ .t = 1, .off = 0x310, .val = 0x00000000 },
    .{ .t = 1, .off = 0x394, .val = 0x00000000 },
    .{ .t = 1, .off = 0x390, .val = 0x00000000 },
    .{ .t = 1, .off = 0x414, .val = 0x00000000 },
    .{ .t = 1, .off = 0x410, .val = 0x00000000 },
    .{ .t = 1, .off = 0x214, .val = 0x00000003 },
    .{ .t = 1, .off = 0x200, .val = 0x00000000 },
    .{ .t = 1, .off = 0x204, .val = 0x00000000 },
    .{ .t = 1, .off = 0x208, .val = 0x0000000a },
    .{ .t = 1, .off = 0x218, .val = 0x00000040 },
    .{ .t = 1, .off = 0x280, .val = 0x00000000 },
    .{ .t = 1, .off = 0x284, .val = 0x00000000 },
    .{ .t = 1, .off = 0x288, .val = 0x0000000a },
    .{ .t = 1, .off = 0x298, .val = 0x00000040 },
    .{ .t = 1, .off = 0x300, .val = 0x00000000 },
    .{ .t = 1, .off = 0x304, .val = 0x00000000 },
    .{ .t = 1, .off = 0x308, .val = 0x0000000a },
    .{ .t = 1, .off = 0x318, .val = 0x00000040 },
    .{ .t = 1, .off = 0x380, .val = 0x00000000 },
    .{ .t = 1, .off = 0x384, .val = 0x00000000 },
    .{ .t = 1, .off = 0x388, .val = 0x0000000a },
    .{ .t = 1, .off = 0x398, .val = 0x00000046 },
    .{ .t = 1, .off = 0x400, .val = 0x00000000 },
    .{ .t = 1, .off = 0x404, .val = 0x00000000 },
    .{ .t = 1, .off = 0x408, .val = 0x0000008a },
    .{ .t = 1, .off = 0x418, .val = 0x00000041 },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x5bc, .val = 0x00000012 },
    .{ .t = 0, .off = 0x5e0, .val = 0x0000001f },
    .{ .t = 0, .off = 0x5e4, .val = 0x00000078 },
    .{ .t = 0, .off = 0x5e8, .val = 0x00000008 },
    .{ .t = 0, .off = 0x5ec, .val = 0x00000000 },
    .{ .t = 0, .off = 0x658, .val = 0x00000040 },
    .{ .t = 0, .off = 0x694, .val = 0x00000006 },
    .{ .t = 0, .off = 0x750, .val = 0x00000010 },
    .{ .t = 0, .off = 0x748, .val = 0x000000a0 },
    .{ .t = 0, .off = 0x758, .val = 0x00000001 },
    .{ .t = 0, .off = 0x740, .val = 0x00000008 },
    .{ .t = 0, .off = 0x518, .val = 0x00000001 },
    .{ .t = 0, .off = 0x504, .val = 0x00000003 },
    .{ .t = 0, .off = 0x510, .val = 0x00000000 },
    .{ .t = 0, .off = 0x520, .val = 0x00000000 },
    .{ .t = 0, .off = 0x524, .val = 0x0000004e },
    .{ .t = 0, .off = 0x544, .val = 0x00000040 },
    .{ .t = 0, .off = 0x568, .val = 0x000000ba },
    .{ .t = 0, .off = 0x578, .val = 0x0000000c },
    .{ .t = 0, .off = 0x5a8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5b8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5c8, .val = 0x00000008 },
    .{ .t = 0, .off = 0x660, .val = 0x0000000a },
    .{ .t = 0, .off = 0x668, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x670, .val = 0x00000084 },
    .{ .t = 0, .off = 0x670, .val = 0x00000082 },
    .{ .t = 0, .off = 0x678, .val = 0x0000004c },
    .{ .t = 0, .off = 0x690, .val = 0x00000080 },
    .{ .t = 0, .off = 0x590, .val = 0x00000029 },
    .{ .t = 0, .off = 0x590, .val = 0x0000002f },
    .{ .t = 0, .off = 0x594, .val = 0x0000002a },
    .{ .t = 0, .off = 0x594, .val = 0x0000003f },
    .{ .t = 0, .off = 0x760, .val = 0x00000022 },
    .{ .t = 1, .off = 0x760, .val = 0x00000022 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x0000005f },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x528, .val = 0x00000000 },
    .{ .t = 0, .off = 0x024, .val = 0x0000005f },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 1, .off = 0x024, .val = 0x0000007f },
    .{ .t = 1, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x03c, .val = 0x00000001 },
    .{ .t = 0, .off = 0x128, .val = 0x00000001 },
    .{ .t = 0, .off = 0x128, .val = 0x00000000 },
    .{ .t = 1, .off = 0x128, .val = 0x00000001 },
    .{ .t = 1, .off = 0x128, .val = 0x00000000 },
    .{ .t = 0, .off = 0x030, .val = 0x00000004 },
    .{ .t = 0, .off = 0x014, .val = 0x00000030 },
    .{ .t = 1, .off = 0x030, .val = 0x00000004 },
    .{ .t = 1, .off = 0x014, .val = 0x00000034 },
    .{ .t = 0, .off = 0x01c, .val = 0x00000001 },
    .{ .t = 1, .off = 0x01c, .val = 0x00000001 },
    .{ .t = 2, .off = 0x29c, .val = 0x05f40b01 },
    .{ .t = 2, .off = 0x020, .val = 0x022c0030 },
    .{ .t = 2, .off = 0x024, .val = 0x087c008c },
    .{ .t = 2, .off = 0x028, .val = 0x08950272 },
    .{ .t = 2, .off = 0x02c, .val = 0x00020000 },
    .{ .t = 2, .off = 0x030, .val = 0x00000000 },
    .{ .t = 2, .off = 0x034, .val = 0x00020000 },
    .{ .t = 2, .off = 0x118, .val = 0x0000023f },
    .{ .t = 2, .off = 0x114, .val = 0x00000001 },
    .{ .t = 2, .off = 0x114, .val = 0x00000000 },
    .{ .t = 2, .off = 0x00c, .val = 0x02009230 },
    .{ .t = 2, .off = 0x01c, .val = 0x00000000 },
    .{ .t = 2, .off = 0x038, .val = 0x14000000 },
    .{ .t = 2, .off = 0x080, .val = 0x80001004 },
    .{ .t = 2, .off = 0x0c0, .val = 0x00001a23 },
    .{ .t = 2, .off = 0x0c8, .val = 0x00000001 },
    .{ .t = 2, .off = 0x108, .val = 0x13ff3fe0 },
    .{ .t = 2, .off = 0x10c, .val = 0xaa20aa02 },
    .{ .t = 2, .off = 0x118, .val = 0x0000023f },
    .{ .t = 2, .off = 0x0ac, .val = 0x00000000 },
    .{ .t = 2, .off = 0x000, .val = 0x000001f1 },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x5bc, .val = 0x00000012 },
    .{ .t = 0, .off = 0x5e0, .val = 0x0000001f },
    .{ .t = 0, .off = 0x5e4, .val = 0x00000078 },
    .{ .t = 0, .off = 0x5e8, .val = 0x00000008 },
    .{ .t = 0, .off = 0x5ec, .val = 0x00000000 },
    .{ .t = 0, .off = 0x658, .val = 0x00000040 },
    .{ .t = 0, .off = 0x694, .val = 0x00000006 },
    .{ .t = 0, .off = 0x750, .val = 0x00000010 },
    .{ .t = 0, .off = 0x748, .val = 0x000000a0 },
    .{ .t = 0, .off = 0x758, .val = 0x00000001 },
    .{ .t = 0, .off = 0x740, .val = 0x00000008 },
    .{ .t = 0, .off = 0x518, .val = 0x00000001 },
    .{ .t = 0, .off = 0x504, .val = 0x00000003 },
    .{ .t = 0, .off = 0x510, .val = 0x00000000 },
    .{ .t = 0, .off = 0x520, .val = 0x00000000 },
    .{ .t = 0, .off = 0x524, .val = 0x0000004e },
    .{ .t = 0, .off = 0x544, .val = 0x00000040 },
    .{ .t = 0, .off = 0x568, .val = 0x000000ba },
    .{ .t = 0, .off = 0x578, .val = 0x0000000c },
    .{ .t = 0, .off = 0x5a8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5b8, .val = 0x00000000 },
    .{ .t = 0, .off = 0x5c8, .val = 0x00000008 },
    .{ .t = 0, .off = 0x660, .val = 0x0000000a },
    .{ .t = 0, .off = 0x668, .val = 0x000000c0 },
    .{ .t = 0, .off = 0x670, .val = 0x00000084 },
    .{ .t = 0, .off = 0x670, .val = 0x00000082 },
    .{ .t = 0, .off = 0x678, .val = 0x0000004c },
    .{ .t = 0, .off = 0x690, .val = 0x00000080 },
    .{ .t = 0, .off = 0x590, .val = 0x00000029 },
    .{ .t = 0, .off = 0x590, .val = 0x0000002f },
    .{ .t = 0, .off = 0x594, .val = 0x0000002a },
    .{ .t = 0, .off = 0x594, .val = 0x0000003f },
    .{ .t = 0, .off = 0x760, .val = 0x00000022 },
    .{ .t = 1, .off = 0x760, .val = 0x00000022 },
    .{ .t = 0, .off = 0x024, .val = 0x0000007f },
    .{ .t = 0, .off = 0x528, .val = 0x000000c0 },
    .{ .t = 3, .off = 0x29c, .val = 0x05f40b01 },
    .{ .t = 3, .off = 0x020, .val = 0x022c0030 },
    .{ .t = 3, .off = 0x024, .val = 0x087c008c },
    .{ .t = 3, .off = 0x028, .val = 0x08950272 },
    .{ .t = 3, .off = 0x02c, .val = 0x00020000 },
    .{ .t = 3, .off = 0x030, .val = 0x00000000 },
    .{ .t = 3, .off = 0x034, .val = 0x00020000 },
    .{ .t = 3, .off = 0x118, .val = 0x0000023f },
    .{ .t = 3, .off = 0x114, .val = 0x00000001 },
    .{ .t = 3, .off = 0x114, .val = 0x00000000 },
    .{ .t = 3, .off = 0x00c, .val = 0x02009230 },
    .{ .t = 3, .off = 0x01c, .val = 0x00000000 },
    .{ .t = 3, .off = 0x038, .val = 0x14000000 },
    .{ .t = 3, .off = 0x080, .val = 0x80001004 },
    .{ .t = 3, .off = 0x0c0, .val = 0x00001a23 },
    .{ .t = 3, .off = 0x0c8, .val = 0x00000001 },
    .{ .t = 3, .off = 0x108, .val = 0x13ff3fe0 },
    .{ .t = 3, .off = 0x10c, .val = 0xaa20aa02 },
    .{ .t = 3, .off = 0x118, .val = 0x0000023f },
    .{ .t = 3, .off = 0x0ac, .val = 0x00000000 },
    .{ .t = 3, .off = 0x000, .val = 0x000001f1 },
    .{ .t = 2, .off = 0x000, .val = 0x000001f3 },
    .{ .t = 3, .off = 0x000, .val = 0x000001f3 },
    .{ .t = 3, .off = 0x000, .val = 0x000001f7 },
    .{ .t = 3, .off = 0x10c, .val = 0xaa20aa02 },
    .{ .t = 2, .off = 0x000, .val = 0x000001f7 },
    .{ .t = 2, .off = 0x10c, .val = 0xaa20aa02 },
    .{ .t = 3, .off = 0x044, .val = 0x00001000 },
    .{ .t = 3, .off = 0x048, .val = 0x00000004 },
    .{ .t = 3, .off = 0x08c, .val = 0x00000001 },
    .{ .t = 2, .off = 0x044, .val = 0x00001000 },
    .{ .t = 2, .off = 0x048, .val = 0x00000004 },
};

/// Phase-split replay (SPEC.md task #5 log).
///
/// A single monolithic replay WEDGED THE BOARD: it issues DSI host writes,
/// but this driver enables the DSI link clocks (byte/pclk/esc) only after
/// bring-up, whereas Linux has them running before its host writes because
/// the clock framework brings them up as part of the PHY PLL enable.
/// Writing host registers into dead clock domains stalls the AHB -- the
/// backlight lit, then the CPU wedged and the watchdog looped.
///
/// So replay in two phases with the link-clock enable in between:
///   phase 0 -> PHY writes only (t == 0 or 1)
///   phase 1 -> DSI host writes only (t == 2 or 3)
/// Order within each phase is preserved exactly as captured.
export fn sheng_mdss_replay_bringup_phase(phase: u32, phy0: usize, phy1: usize, dsi0: usize, dsi1: usize) callconv(.c) c_int {
    for (kernel_bringup_replay) |e| {
        const is_phy = (e.t <= 1);
        if (phase == 0 and !is_phy) continue;
        if (phase == 1 and is_phy) continue;
        const base = switch (e.t) {
            0 => phy0,
            1 => phy1,
            2 => dsi0,
            else => dsi1,
        };
        mmioWrite32(base, e.off, e.val);
        if (is_phy) {
            if (e.off == CMN_GLBL_DIGTOP_SPARE10 and e.val == 0x1) {
                udelay(500);
                var w: u32 = 0;
                while (w < REFGEN_READY_TIMEOUT_US) : (w += 5) {
                    if ((mmioRead32(base, CMN_PHY_STATUS) & 0x1) != 0) break;
                    udelay(5);
                }
            } else if (e.off == CMN_PLL_CNTRL and e.val == 0x1) {
                var w: u32 = 0;
                while (w < PLL_LOCK_POLL2_TIMEOUT_US) : (w += 100) {
                    const st = mmioRead32(base + PLL_BASE_OFFSET, PLL_COMMON_STATUS_ONE);
                    if ((st & PLL_LOCK_STATUS_BIT) != 0) break;
                    udelay(100);
                }
            }
        } else if (e.off == DSI_RESET and e.val == 1) {
            udelay(20000);
        }
    }
    return 0;
}

export fn sheng_mdss_replay_bringup(phy0: usize, phy1: usize, dsi0: usize, dsi1: usize) callconv(.c) c_int {
    for (kernel_bringup_replay) |e| {
        const base = switch (e.t) {
            0 => phy0,
            1 => phy1,
            2 => dsi0,
            else => dsi1,
        };
        mmioWrite32(base, e.off, e.val);

        // Re-insert the blocking points the kernel has.
        if (e.t <= 1) {
            if (e.off == CMN_GLBL_DIGTOP_SPARE10 and e.val == 0x1) {
                udelay(500);
                var w: u32 = 0;
                while (w < REFGEN_READY_TIMEOUT_US) : (w += 5) {
                    if ((mmioRead32(base, CMN_PHY_STATUS) & 0x1) != 0) break;
                    udelay(5);
                }
            } else if (e.off == CMN_PLL_CNTRL and e.val == 0x1) {
                var w: u32 = 0;
                while (w < PLL_LOCK_POLL2_TIMEOUT_US) : (w += 100) {
                    const st = mmioRead32(base + PLL_BASE_OFFSET, PLL_COMMON_STATUS_ONE);
                    if ((st & PLL_LOCK_STATUS_BIT) != 0) break;
                    udelay(100);
                }
            }
        } else if (e.off == DSI_RESET and e.val == 1) {
            udelay(20000);
        }
    }
    return 0;
}

/// PHY bases, remembered so the per-command PLL re-commit below can reach
/// them without threading them through every DCS call site.
var g_phy0_base: usize = 0;
var g_phy1_base: usize = 0;

/// PER-COMMAND PLL RE-COMMIT (SPEC.md task #5 log).
///
/// The last uncharacterised behavioural difference, and the only one left
/// after exhaustive register sweeps came back clean.
///
/// Tracing every PHY write the working kernel makes shows a FULL PLL rate
/// reconfiguration between every single DCS command:
///
///   P0cmn 024=7f  P0pll 528=c0            enable_pll_bias()
///   P0pll 5bc/5e0/5e4/5e8/5ec/658/694/
///         750/748                          dsi_pll_commit()
///   P0pll 758/740/518/504/510/520/524/
///         544/568/578/5a8/5b8/5c8/660/
///         668/670/678/690/590/594/760      dsi_pll_config_hzindep_reg()
///   P1pll 760=22                           slave PERF_OPTIMIZE
///
/// That is msm_dsi_host_xfer_prepare() calling link_clk_set_rate(), which
/// propagates to dsi_pll_7nm_vco_set_rate(). This driver runs that
/// sequence ONCE at bring-up; the kernel runs it before EVERY command.
///
/// The values written are identical to what is already in the registers,
/// which is precisely why 536 PHY registers and 176 DSI registers all diff
/// clean while the panel still receives nothing. If committing the PLL
/// configuration re-latches it into the analog block -- the same shape as
/// the DSI_CTRL enable-edge idea, but on the PLL -- then a register
/// comparison can never see it, and our commands would go out with the
/// analog path in a state the values do not describe.
///
/// Mirrors the traced order exactly: bias, commit rate, hz-independent
/// config, then the slave's PERF_OPTIMIZE.
fn dsiPhyPllRecommit() void {
    if (g_phy0_base == 0) return;
    mmioSetBits32(g_phy0_base, CMN_CTRL_0, CTRL_0_PLL_SHUTDOWNB);
    mmioWrite32(g_phy0_base + PLL_BASE_OFFSET, PLL_SYSTEM_MUXES, 0xc0);
    dsiPhyPllCommitRate(g_phy0_base);
    dsiPhyPllConfigHzIndep(g_phy0_base);
    if (g_phy1_base != 0)
        mmioWrite32(g_phy1_base + PLL_BASE_OFFSET, PLL_PERF_OPTIMIZE, 0x22);
}

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
    // MASTER ONLY (SPEC.md task #5 log, PHY write trace): the working
    // kernel writes CMN_CLK_CFG0 on PHY0 and NEVER on PHY1. The slave takes
    // the master's bit clock via CLK_CFG1.BITCLK_SEL, and DISPCC's pclk1/
    // byte1 source from DSI0's PHY PLL (src_sel 1/2, verified live), so the
    // slave's own dividers feed nothing.
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

    // WITHDRAWN -- THE LIVE READ WAS CONTAMINATED (SPEC.md task #5 log).
    //
    // An earlier pass removed the `if (is_master)` gate here, on the
    // strength of reading DSI1's PLL registers off the device and finding
    // them fully configured and locked (PLL_CNTRL=0x01, status=0x51,
    // dec=0x1F, frac=0x78). That reasoning was wrong: hooking writel() in
    // dsi_phy_7nm.c shows the working kernel writes only TWO PLL registers
    // on PHY1 (SYSTEM_MUXES, PERF_OPTIMIZE) and writes CMN_PLL_CNTRL=0x00
    // on it and never 0x01 -- the slave PLL is never started. Those "live"
    // values were OUR OWN U-Boot writes read back, which Linux never
    // overwrites precisely because it does not touch them.
    //
    // Lesson worth keeping: a live register read is only a valid reference
    // for registers Linux actually writes. For anything it leaves alone,
    // the read reflects whatever ran before it -- including us.
    //
    // Original (now withdrawn) reasoning follows.
    //
    // This used to run the PLL configure+start under `if (is_master)`, on
    // the reasoning that the slave (DSI1) receives its bit clock over the
    // sync-dual-dsi link and so has no PLL of its own to start. Reading
    // dsi_phy_7nm.c supports that reading -- dsi_pll_7nm_vco_prepare()
    // writes CMN_PLL_CNTRL only for `pll_7nm->phy`, and the `slave`
    // branches beside it only do bias / dig-reset / global-clk / RBUF.
    //
    // The hardware disagrees. Read off this device while Linux was driving
    // the panel, DSI1's PHY (0x0ae97000) is not a dormant PLL at all:
    //
    //   CMN_PLL_CNTRL      (+0x03c) = 0x01   <- PLL STARTED
    //   PLL_COMMON_STATUS_1(+0x6b0) = 0x51   <- and LOCKED
    //   PLL_DECIMAL_DIV_START_1     = 0x1F   } fully configured,
    //   PLL_FRAC_DIV_START_LOW_1    = 0x78   } byte-for-byte
    //   PLL_FRAC_DIV_START_MID_1    = 0x08   } identical to DSI0
    //   PLL_CMODE_1                 = 0x10   }
    //   PLL_SYSTEM_MUXES            = 0xC0   }
    //
    // Both PLLs are configured and running. The explanation consistent
    // with the source is that the clock framework prepares BOTH vco clocks
    // (each DSI host parents its byte/pixel clocks to its own PHY PLL), so
    // dsi_pll_7nm_vco_prepare() runs once per PHY and each writes its own
    // CMN_PLL_CNTRL; the `slave` pointer is only non-NULL on the master,
    // which is why the source reads as master-only.
    //
    // Under the old gate, DSI1's entire PLL sub-block (phy+0x500) was
    // never written at all -- and that sub-block was never audited either,
    // since the PHY has no verify table and the manual "31/31 CMN match"
    // covered only the CMN block below +0x200. A slave PHY whose PLL is
    // unconfigured and unlocked is a plausible reason for half a bonded
    // link to never drive its lanes, which on a stitched DDIC means no
    // usable picture at all.
    // Rate configuration only. The PLL START and the digital-reset /
    // global-clock / RBUF tail are NOT done here any more -- they have to
    // be interleaved across both PHYs, so they live in
    // sheng_mdss_dsi_phy_start_dual(), which the caller runs once after
    // BOTH phys have been through this function.
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
/// WRONG OFFSET, FOUND BY WRITE TRACE (SPEC.md task #5 log).
///
/// This was 0x010. dsi.xml puts VID_CFG1 at **0x01c** -- the register map
/// jumps straight from VID_CFG0 (0x00c) to VID_CFG1 (0x01c), and 0x010 is
/// not modelled at all. So this driver has been writing 0x31211101 into an
/// UNDOCUMENTED register believing it was VID_CFG1, and never writing the
/// real VID_CFG1 at all.
///
/// Caught by tracing every dsi_write() the working kernel makes: Linux's
/// DSI0 bring-up touches 23 offsets, and comparing that set against ours,
/// 0x01c is the ONE register Linux writes that we never did. It is
/// invisible to our audits twice over -- not written by us, and not in the
/// audit table either.
///
/// VID_CFG1 holds R_SEL(0) / G_SEL(4) / B_SEL(8) / RGB_SWAP(12:14). Note
/// 0x31211101 sets bits far outside those fields, which is independent
/// confirmation it was never a VID_CFG1 value.
///
/// Live, read off this device on both hosts: 0x01c = 0x00000000 (Linux
/// writes 0 explicitly in dsi_ctrl_enable), 0x010 = 0x31211101 on both --
/// so 0x31211101 is simply 0x010's power-on value, which is why writing it
/// looked harmless and why our audit of 0x010 always passed.
///
/// Why this can matter on a DSC panel: with compression on, the "pixel
/// stream" is compressed bytes. Channel-select/swap applied to that byte
/// stream scrambles it, the panel's DSC decoder fails to decode, and it
/// blanks -- with no error anywhere on the transmit side. It does NOT
/// explain the unanswered BTA (command mode does not use VID_CFG1), so
/// this is a real divergence, not necessarily the whole story.
const DSI_VID_CFG1: usize = 0x01c;
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
    // RE-ENABLED (b93). The previous "it answered its question -- pure
    // black with the whole DPU bypassed" result is INVALID and must not
    // be trusted: it was measured while the `0x51 0x00 0x00` write was
    // still in the init table, i.e. through a DDIC that had been
    // explicitly commanded to output black with BCTRL armed. See the
    // REMOVED-0x51 comment in dsiPanelInit() -- it names this exact test
    // ("solid fill, border-only, DSI TPG") as one of the bisects it
    // invalidated, which is why mutually exclusive hypotheses all came
    // back identically black.
    //
    // b92 established a clean panel state for the first time: with
    // SHENG_SKIP_PANEL_TOUCH the DDIC is inherited straight from ABL,
    // fully initialised and actively displaying, and we send it no DCS
    // at all -- so no 0x51 can be in effect. Re-running TPG on top of
    // that is the real bisect, and it splits the remaining search space
    // exactly in half:
    //
    //   TPG visible -> DSI host/PHY/link/panel are all fine, and the
    //     black screen is upstream in DPU/SSPP/SMMU pixel fetch.
    //   TPG black   -> nothing we transmit reaches the panel at all,
    //     and the entire DPU-side investigation is moot.
    //
    // Yes, this perturbs FIFO_STATUS (drives it to 0x55551210). That is
    // acceptable here: FIFO_STATUS is a proxy, a photograph of the
    // panel is not.
    //
    // b93 RESULT: registers verified programmed (0x158=0x31, 0x160=0xff,
    // 0x198=0x100, 0x1a0=0x05) and the panel stayed black -- but that run
    // is NOT clean either, because the link is in DSC compressed mode
    // (VIDEO_COMPRESSION_MODE_CTRL) and TPG emits UNCOMPRESSED pixels,
    // which the DDIC's DSC decoder cannot make sense of. Re-disabled: the
    // real fault turned out to be dispCcPll0Enable()'s rate, and we want
    // the genuine DPU framebuffer path visible, not a TPG overlay.
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
/// ENABLED b96. Everything above still stands, and the b95 PLL0 rate fix
/// did NOT clear the starvation: with mdp_clk finally at its correct
/// 514MHz (PLL0 L=0x50/alpha=0x5000 verified by readback, RCG CFG 0x105
/// identical to live Linux, MDP_CLK_CBCR enabled), FIFO_STATUS on BOTH
/// links still reads 0x11111210 against live Linux's 0x00001210. So the
/// DPU is still not delivering pixels, and this bisect is the cheapest
/// way to find out on which side of the mixer that starts.
/// RESULT (b96): border-only made NO difference -- FIFO_STATUS identical to
/// b95 on both links. That looked like "starvation is downstream of the
/// mixer", but the premise was wrong: the 0x11111210 reading was sampled
/// immediately after dpu_start, with INTF FRAME_COUNT still 0, i.e. before
/// a single frame existed. In the LATE dump, after 500ms of streaming, both
/// links read 0x00001210 -- byte-identical to live rendering Linux. There
/// is no starvation and there never was. Reverted.
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

/// LP-vs-HS COMMAND TRANSMISSION TEST (SPEC.md task #5 log).
///
/// Traced through the real stack, this is what our CMD_DMA_CTRL value
/// actually means -- and it is the one path in this driver that has never
/// been proven to work.
///
///   dsi.xml:            CMD_DMA_CTRL bit26 = LOW_POWER, bit28 = FROM_FRAME_BUFFER
///   dsi_ctrl_enable():  writes FROM_FRAME_BUFFER | LOW_POWER == 0x14000000
///   xfer_prepare():     `if (!(msg->flags & MIPI_DSI_MSG_USE_LPM))
///                          dsi_set_tx_power_mode(0)`  -- CLEARS LOW_POWER
///   drm_mipi_dsi.c:     `if (dsi->mode_flags & MIPI_DSI_MODE_LPM)
///                          msg->flags |= MIPI_DSI_MSG_USE_LPM`
///   nt36532e:           .mode_flags = ... | MIPI_DSI_MODE_LPM
///
/// So this panel's every DCS command is sent in LOW POWER mode, and our
/// 0x14000000 faithfully reproduces that. Faithful, and unfalsified: LP
/// transmission uses the PHY's LPTX drivers, a completely separate analog
/// path from the HS drivers that carry video.
///
/// Every failing measurement we have is on the LP path, and every passing
/// one is on the HS path:
///   HS works   -- video streams, FIFO_STATUS 0x00001210 matches live,
///                 both video engines busy, INTF at 142Hz.
///   LP unproven -- DCS writes need no ACK, so "success" only ever meant
///                 our DMA engine shifted bytes out. The single LP
///                 operation that requires the panel to answer, the BTA
///                 read, has returned nothing on every boot -- including
///                 now that it is correctly issued with CMD_MODE_EN set
///                 (sheng.rd1 = 0x01F7_0000).
///
/// If LPTX is not reaching the panel, then NO command ever has: the panel
/// never got its init sequence, never got DSC enable, never got the PPS.
/// It would sit uninitialised while we stream perfectly-formed compressed
/// video at a decoder that was never configured -- black screen, clean
/// registers, no errors anywhere. That matches every observation.
///
/// This test clears LOW_POWER so the identical command sequence goes out
/// over the HS path instead -- the path we have independently proven
/// works.
///
///   Panel lights up / anything appears -> the LP path is the fault, and
///     the entire investigation moves to the PHY's LPTX config.
///   Still black -> commands are reaching the panel over a proven-good
///     path and being acted on, so the fault is genuinely downstream and
///     the LP path is exonerated.
///
/// Either outcome is decisive. Set false to restore the faithful value.
/// RESULT: LP PATH EXONERATED (SPEC.md task #5 log). Ran with this true --
/// sheng.verify came back 0x800020, bit5 confirming CMD_DMA_CTRL really
/// did carry the HS value, so the test genuinely executed. Panel still
/// black, sheng.rd1 still 0x01F7_0000, sheng.panel still 0. Commands sent
/// over the independently-proven-good HS path behave identically to LP, so
/// the transmission mode is not the fault. Back to the faithful value.
const DSI_CMD_TX_IN_HS_TEST: bool = false;
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
const STATUS0_VIDEO_MODE_ENGINE_BUSY: u32 = 1 << 3;

/// dsi_wait4video_eng_busy() -- NEVER IMPLEMENTED HERE (SPEC.md task #5).
///
/// The kernel calls this before EVERY command, from dsi_cmd_dma_tx():
///
///     if (!(mode_flags & MIPI_DSI_MODE_VIDEO)) return;
///     data = dsi_read(REG_DSI_STATUS0);
///     if (!(data & DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY)) return;
///     if (power_on && enabled) {
///             dsi_wait4video_done(msm_host);
///             mdelay(4);       /* delay 4 ms to skip BLLP */
///     }
///
/// i.e. when the video engine is transmitting, wait for the frame to
/// finish and then sit 4ms inside the blanking period before issuing the
/// command. This driver has never done it -- we trigger the DMA whenever
/// we feel like it.
///
/// This panel is MIPI_DSI_MODE_VIDEO and our host is in video mode during
/// init (matching the kernel's measured ordering), and sheng.vrb1 shows
/// STATUS0 bit3 VIDEO_MODE_ENGINE_BUSY SET. So we have been injecting DCS
/// packets into a link that is actively transmitting video, with no
/// blanking-window synchronisation at all. The command DMA still runs and
/// still reports done -- which is exactly what we measure -- but the
/// packet collides with the video stream on the wire and the DDIC never
/// sees a well-formed command.
///
/// That is the one behavioural difference left that no register
/// comparison could ever show, and it explains why our bytes are perfect
/// and the panel is deaf: the bytes are right, the timing on the link is
/// not.
/// VIDEO_DONE lives in INTR_CTRL (already declared above as 0x10c, matching
/// dsi.xml's `<reg32 offset="0x0010c" name="INTR_CTRL" type="DSI_IRQ"/>`).
///
/// Note for anyone tempted to "correct" that offset: the DSI_6G_REG_SHIFT
/// is carried entirely by SM8550_MDSS_DSI0_BASE (0x0ae94000 + 4), NOT by
/// the per-register offsets. dsi.xml gives CTRL=0x000, STATUS0=0x004,
/// FIFO_STATUS=0x008 -- byte-identical to this file's constants -- so
/// offsets are used as-is against the shifted base.
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
    // EXACT KERNEL ORDER (SPEC.md task #5 log).
    //
    // Rewritten to follow the sequence traced from every dsi_write() the
    // working kernel makes, in order:
    //
    //   0x29c compression, 0x020/024/028/02c/030/034 timing   <- dsi_timing_setup()
    //   0x118 CLK_CTRL
    //   0x114 RESET 1 -> 0                                    <- dsi_sw_reset()
    //   0x00c VID_CFG0, 0x01c VID_CFG1, 0x038 CMD_DMA_CTRL,
    //   0x080 TRIG_CTRL, 0x0c0 CLKOUT, 0x0c8 EOT,
    //   0x108 ERR_INT_MASK0, 0x10c INTR_CTRL, 0x118 CLK_CTRL,
    //   0x0ac LANE_SWAP                                       <- dsi_ctrl_enable()
    //   0x000 CTRL = 0x1f1  then  0x1f3
    //
    // This driver previously enabled the controller (CTRL = 0x1f1, which
    // sets DSI_CTRL_ENABLE) and only programmed the timing registers
    // afterwards, in a separate switch-to-video step. The kernel programs
    // the entire timing block BEFORE the software reset and before the
    // controller is ever enabled -- dsi_timing_setup() is called from
    // msm_dsi_host_power_on() ahead of dsi_sw_reset() and dsi_ctrl_enable().
    //
    // Enabling a DSI controller before its active-window/compression
    // configuration exists is a real sequencing error, and it is invisible
    // to every audit we have: the final register values are identical
    // either way, which is exactly why this survived 39 builds of
    // register-by-register comparison.

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
    mmioWrite32(dsi_base, DSI_CMD_DMA_CTRL, if (DSI_CMD_TX_IN_HS_TEST)
        CMD_DMA_CTRL_HS_VALUE
    else
        CMD_DMA_CTRL_VALUE);
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
/// REAL BUG FOUND (SPEC.md task #5 log): this function never did the
/// msm_dsi_host_xfer_prepare() CMD_MODE_EN|ENABLE OR-in that
/// dsiCmdDmaTxDualOnce() does. That was harmless while the whole init
/// ran in command mode. It is NOT harmless now: the host is switched to
/// VIDEO mode before panel init (matching the kernel's measured
/// ordering), so by the time its only caller --
/// sheng_mdss_dsi_read_power_mode_single(), our one two-way liveness
/// test -- runs, CMD_MODE_EN is clear.
///
/// Measured this boot: sheng.vrb1 = 0x1F3_00000008, i.e. DSI0 CTRL =
/// 0x000001F3 (VID_MODE_EN set, CMD_MODE_EN CLEAR) with the video engine
/// busy. Every "read" this driver has ever issued went out with the
/// controller not in command mode.
///
/// That predicts the exact result pair we have always seen and never
/// explained: sheng.rd1 = 0 (RDBK_DATA_CTRL COUNT = 0, no bytes) AND
/// sheng.errst = 0 (TIMEOUT_STATUS = 0, no BTA timeout). A BTA that is
/// genuinely attempted and gets no answer should time out. Zero bytes
/// AND zero timeout means no bus turnaround was ever attempted -- our
/// bug, not evidence about the panel.
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
/// link, and msm's rx path is explicitly single-host, so this function
/// was written to do the read on DSI0 alone.
///
/// CORRECTION (SPEC.md task #5 log): "single-host" is only half true, and
/// the half it gets wrong is the half that matters. Reading dsi_manager.c
/// directly:
///
///   msm_dsi_manager_cmd_xfer():         need_sync = IS_SYNC_NEEDED() && !is_read
///   msm_dsi_manager_cmd_xfer_trigger(): no is_read check at all
///
/// So for a read the kernel skips only the DSI1 xfer_prepare/restore --
/// the DMA TRIGGER still fires on DSI1 and then DSI0, off the same
/// dma_base, exactly as for a write. Only the RDBK read-back is DSI0-only.
/// The kernel therefore does neither what this function does (trigger DSI0
/// alone) nor what dsiCmdDmaTxDual() does (prepare AND trigger both); it
/// sits precisely between them. On a stitched panel that expects
/// synchronised SOT across both links, a command arriving on one link only
/// is a plausible reason for the DDIC to ignore it entirely.
///
/// Both variants are therefore reported side by side this boot --
/// sheng.rd1 from here (DSI0-only trigger) and sheng.pm from
/// sheng_mdss_dsi_read_power_mode() (both triggered) -- which brackets the
/// kernel's actual behaviour without guessing which half matters.
///
///   non-zero data_id/payload -> the panel RECEIVES, DECODES and RESPONDS.
///     Everything upstream is proven good and the fault is confined to
///     the video path.
///   still zero on BOTH -> two-way communication genuinely fails on a link
///     whose every register matches working silicon.
///   zero on one, data on the other -> the trigger pattern itself is the
///     difference, and it applies to every command we have ever sent.
/// INSTRUMENT CHECK: read an ARBITRARY DCS register, not just 0x0A.
///
/// Every read this driver has ever done returns payload 0x08. That is the
/// correct "alive but uninitialised" power-mode value, so it looks right --
/// but a decode that always yields 0x08 would look identical. Reading a
/// different register proves the difference: 0x0C (get_pixel_format) must
/// NOT return 0x08 on a live panel (expect 0x70/0x77-class), and 0x04
/// (get_display_id) returns vendor bytes.
///
/// If every register reads 0x08, the read path is fabricating it and every
/// conclusion drawn from "the panel answers 0x08" collapses.
export fn sheng_mdss_dsi_read_dcs_reg_max(dsi0_base: usize, dma_scratch: usize, reg: u8, maxsz: u8) callconv(.c) i64 {
    // DOES ANY WRITE LAND? 0x37 (set maximum return packet size) is an
    // ordinary short WRITE. If writes never reach the panel, changing maxsz
    // cannot change anything. If they do, the response must change shape:
    // a 1-byte answer comes back as data_id 0x21, a 2-byte one as 0x22, and
    // a longer one as a long-read response 0x1A. Reading 0x04
    // (get_display_id, 3 bytes on a real panel) with maxsz=1 vs 3 is
    // therefore a direct test of write delivery that does not depend on the
    // panel executing any state-changing command.
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    const ctrl_restore = mmioRead32(dsi0_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    defer mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore);

    dst[0] = maxsz;
    dst[1] = 0;
    dst[2] = 0x37;
    dst[3] = 0x80;
    if (dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4) != 0) return -1;

    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, RDBK_DATA_CTRL_CLR);
    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, 0);

    dst[0] = reg;
    dst[1] = 0x00;
    dst[2] = 0x06;
    dst[3] = 0x80 | 0x20;
    if (dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4) != 0) return -2;

    var w: u32 = 0;
    while (w < 20000) : (w += 20) {
        if ((mmioRead32(dsi0_base, DSI_INTR_CTRL) & (1 << 20)) != 0) break;
        udelay(20);
    }
    return (@as(i64, mmioRead32(dsi0_base, DSI_RDBK_DATA0)) << 32) | @as(i64, maxsz);
}

export fn sheng_mdss_dsi_read_dcs_reg(dsi0_base: usize, dma_scratch: usize, reg: u8) callconv(.c) i64 {
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    const ctrl_restore = mmioRead32(dsi0_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    defer mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore);

    dst[0] = 1;
    dst[1] = 0;
    dst[2] = 0x37; // set maximum return packet size = 1
    dst[3] = 0x80;
    if (dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4) != 0) return -1;

    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, RDBK_DATA_CTRL_CLR);
    mmioWrite32(dsi0_base, DSI_RDBK_DATA_CTRL, 0);

    dst[0] = reg;
    dst[1] = 0x00;
    dst[2] = 0x06; // DCS read, no parameter
    dst[3] = 0x80 | 0x20;
    if (dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4) != 0) return -2;

    var waited: u32 = 0;
    while (waited < 20000) : (waited += 20) {
        if ((mmioRead32(dsi0_base, DSI_INTR_CTRL) & (1 << 20)) != 0) break;
        udelay(20);
    }
    const rdbk = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    return (@as(i64, rdbk) << 32) | @as(i64, reg);
}

export fn sheng_mdss_dsi_read_power_mode_single(dsi0_base: usize, dma_scratch: usize) callconv(.c) i64 {
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);

    // Hold the host in command mode across the ENTIRE read, not just each
    // individual DMA. dsiCmdDmaTxOne() now does its own prepare/restore,
    // but that restores to video mode the instant the DMA completes --
    // i.e. during the ~20ms window in which the panel is supposed to turn
    // the bus around and drive the response back. The BTA reception has to
    // happen with CMD_MODE_EN still asserted, so span the whole sequence.
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
    dst[3] = 0x80 | 0x20;

    // KERNEL-FAITHFUL READ TRIGGER (SPEC.md task #5 log).
    //
    // This is the one asymmetry with Linux we have never replicated. In
    // dsi_manager.c:
    //
    //   msm_dsi_manager_cmd_xfer():         need_sync = IS_SYNC_NEEDED() && !is_read
    //   msm_dsi_manager_cmd_xfer_trigger(): NO is_read check at all
    //
    // So for a read the kernel skips only DSI1's xfer_prepare -- it still
    // fires the DMA on DSI1 *and* DSI0 off the same dma_base, and reads
    // RDBK back from DSI0 alone. Our single-host read triggered DSI0 only;
    // our dual read prepared AND triggered both. The kernel sits exactly
    // between them, and on a stitched panel that expects synchronised SOT
    // across both links, a read arriving on one link only is a plausible
    // reason for the DDIC never to turn the bus around -- which is exactly
    // what we measure (BTA_DONE never fires across 1000 samples/20ms).
    //
    // DSI1 is deliberately NOT put into command mode here, matching the
    // skipped xfer_prepare. Base is SM8550_MDSS_DSI1_BASE (0x0ae96000 +
    // DSI_6G_REG_SHIFT); this function only receives dsi0_base.
    const dsi1_base: usize = 0x0ae96004;

    dsiCmdDmaTrigger(dsi1_base, dma_scratch, 4);
    dsiCmdDmaTrigger(dsi0_base, dma_scratch, 4);
    _ = dsiCmdDmaWait(dsi1_base);
    ret = dsiCmdDmaWait(dsi0_base);
    if (ret != 0) return -2;

    // IS THE BTA EVEN BEING ATTEMPTED? (SPEC.md task #5 log)
    //
    // Transmission is now PROVEN: timing the command DMA shows the 132-byte
    // PPS packet takes 114us against ~21us for a 4-byte command, i.e. ~0.73
    // us/byte == ~9.6Mbps == exactly LP escape rate. Bytes physically go on
    // the wire, so "our commands never reach the DDIC" is dead as a theory.
    //
    // Which makes the silent read the sharpest remaining clue -- but only
    // if we can tell WHICH silence it is:
    //   (a) the host never turned the bus around, or
    //   (b) it did, and the panel said nothing.
    //
    // TIMEOUT_STATUS has never distinguished them because LP_TIMER_CTRL's
    // BTA_TO field is 0xFFFF (maximum), so an unanswered turnaround takes
    // far longer to expire than our 20ms wait -- it reads 0 either way, and
    // that zero has been quietly treated as evidence for years.
    //
    // Shorten BTA_TO drastically for the duration of the read. Now:
    //   TIMEOUT_STATUS nonzero -> a real BTA was issued and went unanswered
    //     => the panel is genuinely not responding (case b).
    //   TIMEOUT_STATUS still 0 -> no turnaround was ever attempted
    //     => our RX path is broken (case a), the panel may well have been
    //        answering all along, and the read is not evidence about the
    //        panel at all.
    const lp_timer_saved = mmioRead32(dsi0_base, DSI_LP_TIMER_CTRL);
    // Minimum BTA_TO. If TIMEOUT_STATUS never sets even at the smallest
    // possible turnaround timeout, then "no timeout" was never evidence of
    // anything -- the mechanism itself does not report here. Calibrating
    // the instrument before trusting it, the same way the backlight
    // detector was calibrated on Linux and rejected.
    mmioWrite32(dsi0_base, DSI_LP_TIMER_CTRL, (lp_timer_saved & 0x0000ffff) | (0x0001 << 16));

    // POLL FOR THE TURNAROUND ACROSS THE WHOLE WAIT.
    //
    // The previous probe sampled BTA_DONE at CMD_DMA_DONE time -- i.e. the
    // instant our packet finished going out, BEFORE the panel could
    // possibly have driven a reply back. It was structurally too early to
    // ever see the event, and reading 0 there meant nothing. Watch the
    // entire 20ms window instead and record the FIRST moment anything
    // appears, plus what RDBK held at that moment.
    var bta_seen_us: u32 = 0;
    var bta_intr: u32 = 0;
    var bta_rdbk: u32 = 0;
    var tmo_seen: u32 = 0;
    var waited_us: u32 = 0;
    while (waited_us < 20000) : (waited_us += 20) {
        const ic = mmioRead32(dsi0_base, DSI_INTR_CTRL);
        if (bta_seen_us == 0 and (ic & (1 << 20)) != 0) {
            bta_seen_us = waited_us + 1;
            bta_intr = ic;
            bta_rdbk = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
        }
        if (tmo_seen == 0) {
            const t = mmioRead32(dsi0_base, DSI_TIMEOUT_STATUS);
            if (t != 0) tmo_seen = t;
        }
        udelay(20);
    }

    bbStr("BTA poll: first_bta_us=");
    bbDec(bta_seen_us);
    bbStr(" intr_at_bta=");
    bbHex(bta_intr, 8);
    bbStr(" rdbk_at_bta=");
    bbHex(bta_rdbk, 8);
    bbStr(" timeout_seen=");
    bbHex(tmo_seen, 8);
    bbByte('\n');
    bbSeal();

    bbStr("BTA probe: lp_timer ");
    bbHex(lp_timer_saved, 8);
    bbStr(" -> ");
    bbHex(mmioRead32(dsi0_base, DSI_LP_TIMER_CTRL), 8);
    bbStr(" timeout_status=");
    bbHex(mmioRead32(dsi0_base, DSI_TIMEOUT_STATUS), 8);
    bbStr(" ack_err=");
    bbHex(mmioRead32(dsi0_base, DSI_ACK_ERR_STATUS), 8);
    bbStr(" rdbk=");
    bbHex(mmioRead32(dsi0_base, DSI_RDBK_DATA0), 8);
    bbStr(" int=");
    bbHex(mmioRead32(dsi0_base, DSI_INTR_CTRL), 8);
    bbStr(" int_at_dma_done=");
    bbHex(g_intr_at_dma_done, 8);
    bbStr(" BTA_DONE=");
    bbDec((g_intr_at_dma_done >> 20) & 1);
    bbByte('\n');
    bbSeal();

    mmioWrite32(dsi0_base, DSI_LP_TIMER_CTRL, lp_timer_saved);

    // SELF-DIAGNOSING ENCODING (SPEC.md task #5 log). The old return was
    // (RDBK_DATA_CTRL << 32) | RDBK_DATA0, so an all-zero result -- which
    // is what this test has returned for its entire history -- could not
    // distinguish "the panel did not answer" from "we never asked
    // properly". That ambiguity is exactly what hid the missing
    // xfer_prepare (see dsiCmdDmaTxOne()'s comment) for so long.
    //
    // DECODE BUG FOUND (SPEC.md task #5 log). The previous encoding put
    // RDBK_DATA_CTRL in the high half and `resp & 0xff` in the low byte.
    // BOTH halves were wrong, and together they could make a SUCCESSFUL
    // read look exactly like a dead link:
    //
    //   * RDBK_DATA_CTRL has no readable COUNT field. dsi_host.c only ever
    //     WRITES it (CLR then 0, in msm_dsi_host_cmd_rx) and never reads it
    //     back for anything. Treating a zero there as "0 bytes captured"
    //     was an invention; it reads 0 regardless.
    //
    //   * dsi_cmd_dma_rx() does `*temp++ = ntohl(data)` and then indexes
    //     the result as bytes, so on this little-endian CPU the response
    //     byte order within RDBK_DATA0 is REVERSED relative to the raw
    //     register. buf[0] (the data_id) is bits 31:24, and
    //     dsi_short_read1_resp() takes the actual payload from buf[1] --
    //     bits 23:16. The low byte this driver was reporting is the tail
    //     of the packet, which is legitimately 0x00 on a good short read.
    //
    // So a real reply of data_id 0x21 / payload 0x9C lands in RDBK_DATA0 as
    // 0x219C0000: RDBK_DATA_CTRL = 0 and `resp & 0xff` = 0 -- byte-for-byte
    // the "sheng.rd1 = 0x01F7_0000, panel is silent" result this project
    // has been treating as its central piece of evidence. Report the WHOLE
    // register instead so the answer is unambiguous.
    //
    //   63:32  RDBK_DATA0 RAW, all 32 bits. Decode per the kernel:
    //          31:24 = data_id (0x21/0x1A DCS short read 1-byte response,
    //          0x22/0x1C = 2-byte, 0x02 = ack+error report), 23:16 =
    //          payload. Any nonzero value here means the panel ANSWERED.
    //   31:16  DSI_CTRL low half AS IT STOOD DURING THE READ. 0x01F7
    //          means CMD_MODE_EN(bit2) was genuinely asserted, i.e. the
    //          BTA was properly issued. 0x01F3 means CMD_MODE_EN was clear
    //          and the result says nothing about the panel at all.
    //   15:8   TIMEOUT_STATUS low byte.
    //   7:0    the decoded Get Power Mode payload (bits 23:16 of RDBK_DATA0)
    //          -- expect bit2 DISPLAY_ON | bit3 NORMAL_MODE | bit4 SLEEP_OUT,
    //          i.e. 0x9C on a live, initialised NT36532E.
    const resp = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    const ctrl_during = mmioRead32(dsi0_base, DSI_CTRL);
    const tmo = mmioRead32(dsi0_base, DSI_TIMEOUT_STATUS);

    return (@as(i64, resp) << 32) |
        (@as(i64, ctrl_during & 0xffff) << 16) |
        (@as(i64, tmo & 0xff) << 8) |
        @as(i64, (resp >> 16) & 0xff);
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

    // Same decode fix as sheng_mdss_dsi_read_power_mode_single(): the raw
    // RDBK_DATA0 in the high half (31:24 = data_id, 23:16 = payload), the
    // kernel-decoded payload byte in the low half. RDBK_DATA_CTRL is not
    // reported -- it has no readable COUNT field.
    const resp = mmioRead32(dsi0_base, DSI_RDBK_DATA0);
    return (@as(i64, resp) << 32) | @as(i64, (resp >> 16) & 0xff);
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

/// Single DCS write, for the b2xx write-probe: does ANY write reach the
/// DDIC? The panel answers our reads (end-of-probe read returns payload
/// 0x08, the correct "alive but uninitialised" value), but a full init
/// leaves it reading 0x08 too -- byte-identical to sending nothing. So
/// send exactly one command whose effect is visible in that same read:
/// 0x11 exit_sleep_mode should flip SLEEP_OUT (bit 4), 0x08 -> 0x18.
export fn sheng_mdss_dsi_exit_sleep_only(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) c_int {
    _ = dsi1_base;
    // SINGLE-HOST write, mirroring exactly how the WORKING read sends its
    // first packet (dsiCmdDmaTxOne on DSI0, CMD_MODE_EN on DSI0 only).
    //
    // Reads provably reach the panel: RDBK_DATA0 comes back 0x21080037,
    // byte-identical in format to Linux's ground truth, payload 0x08. Writes
    // provably do not: a full 94-command init, and a lone 0x11, both leave
    // that read at 0x08. The two paths differ in exactly one way -- reads
    // start single-host, writes always go through dsiCmdDmaTxDual, which
    // enables CMD_MODE_EN on BOTH hosts and triggers both. If a write sent
    // the read's way lands (0x08 -> 0x18), the dual-host transmit is the bug.
    const dst: [*]volatile u8 = @ptrFromInt(dma_scratch);
    const ctrl_restore = mmioRead32(dsi0_base, DSI_CTRL);
    mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore | CTRL_CMD_MODE_EN | CTRL_ENABLE);
    defer mmioWrite32(dsi0_base, DSI_CTRL, ctrl_restore);

    dst[0] = 0x11; // DCS exit_sleep_mode
    dst[1] = 0x00;
    dst[2] = 0x05; // short write, no parameter
    dst[3] = 0x80; // last packet
    return dsiCmdDmaTxOne(dsi0_base, dma_scratch, 4);
}

export fn sheng_mdss_dsi_panel_sleep(dsi0_base: usize, dsi1_base: usize, dma_scratch: usize) callconv(.c) void {
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x28, &[_]u8{});
    udelay(20000); // datasheet-typical gap between display-off and sleep-in
    _ = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, 0x10, &[_]u8{});
    udelay(5000);
}

/// INTER-COMMAND GAP (b109).
///
/// Everything else is now excluded. b108 handed the panel over with a
/// clean init (panel_init_ret=0, no timeouts), a link byte-identical to a
/// rendering Linux, a transport proven working in both directions (b105
/// got the first-ever DCS reply 0x08 and BTA_DONE=1), and NO video at all
/// (lanact=0, fdel=0) -- and Linux still read the DDIC as unconfigured.
/// Meanwhile the identical 94 bytes replayed from Linux drive this exact
/// panel to 0x9c. Content, ordering, framing, rails, reset and link state
/// are all verified the same. The one measured difference left is RATE:
///
///   Linux  ~2ms per command   (init_seq 184ms for ~94 commands; a single
///                              isolated command spans 12.8ms of SHENG_W)
///   U-Boot ~24us per command  (from the per-command trace)
///
/// We transmit roughly 80x faster than the working driver, back to back
/// with no gap. A DDIC that needs time to consume each command would
/// accept the early ones, fall behind, and end up unconfigured -- which is
/// exactly what we observe, and why replaying the same bytes through
/// Linux's much slower path succeeds.
///
/// Tunable on purpose: if 1ms fixes it, bisect down to find the real
/// requirement rather than leaving a guess in the boot path.
/// 0: the init loop already paces at INIT_CMD_PACING_US = 2000us, which
/// matches Linux's measured ~2ms/command. b109 added 1ms on top on the
/// mistaken basis that we transmitted 80x faster -- the 24us in the
/// per-command trace is DMA time, not the inter-command interval. It
/// changed nothing, as expected in hindsight.
const DSI_INTER_CMD_DELAY_US: u32 = 0;

var g_init_sent: i32 = -1;
export fn sheng_mdss_init_sent() callconv(.c) i32 { return g_init_sent; }

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
    if (MINIMAL_CMD_MODE_BTA_TEST) return;
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);
}

/// MINIMAL-CONFIGURATION BTA TEST (SPEC.md task #5 log).
///
/// Everything software can check is now verified against live silicon:
/// DSI0 39/39, DSI1 39/39, DPU 50/50, MDSS wrapper 3/3, PHY 53/53 on BOTH
/// PHYs (CMN + PLL, including PHY_STATUS 0x1F and both PLLs locked), PPS
/// 128/128, panel bias GPIOs driven and reading back high at the pad, the
/// KTZ8866s' LCD_BIAS_EN set with FLAG=0 (no fault) on both chips, all
/// three rails voted and now explicitly HPM, no SMMU faults, no DSI
/// errors, no DMA timeouts, and LANE_STATUS showing the lanes genuinely
/// driven with no contention.
///
/// And the panel has never once answered a bus turnaround.
///
/// The zero-byte BTA is upstream of DSC, the DPU, the framebuffer and the
/// compressed stream -- a DCS read of 0x0A needs none of them. So strip
/// the configuration down to the smallest thing that can still fail:
///
///   - hosts stay in COMMAND mode; the video-mode switch never runs
///   - no DPU, no INTF timing, no DSC encoder, no pixel traffic
///   - the read is issued on DSI0 alone, immediately after the panel's
///     reset pulse, BEFORE any of the 87 init commands
///
/// That removes, in one step, every variable the report ranked: bonded
/// slave-link interaction, DSC, video-mode-vs-command-mode, the init
/// sequence itself, and the DPU entirely.
///
///   bytes come back -> the panel talks under simple conditions, and
///     something in the fuller sequence is what silences it. That would
///     be the first positive response in this project's history.
///   still nothing -> the panel does not respond to us under the simplest
///     possible configuration, on a link whose every register matches
///     working silicon and whose lanes are confirmed driven. At that
///     point the remaining discriminator is genuinely physical and a
///     scope on data-lane-0 P/N is the honest next instrument.
/// RE-PURPOSED: COMMAND-MODE INIT TEST (SPEC.md task #5 log).
///
/// Now established, via a kernel built to skip its own panel bring-up plus
/// a U-Boot built to skip its teardown: Linux's KNOWN-GOOD video path
/// renders nothing on a panel configured solely by our init. So our 87
/// DCS commands + PPS do not configure the DDIC, and every video-path
/// measurement this session was made against an unconfigured panel.
///
/// The command CONTENT is not the problem -- our table diffs byte-for-byte
/// against sheng_tianma_init_sequence(), 87/87 -- and the packet bytes are
/// confirmed present and correct in DRAM at fetch time (0x801526FF). So
/// the question is delivery.
///
/// This flag keeps the DSI hosts in COMMAND mode for the whole init
/// instead of switching them to VIDEO mode first. That switch was adopted
/// to match the kernel's measured ordering (host_enable_video at 632.4ms,
/// panel_reset at 633.7ms, init_seq at 668.9ms), but this driver's own
/// history records an earlier attempt at that ordering wedging the command
/// DMA at command #26 -- i.e. evidence that our video engine behaves
/// differently from the kernel's while streaming with no DPU data behind
/// it, for the ~200ms the init takes.
///
///   Linux renders -> running the init over a video-mode link is what
///     breaks command delivery, and the fix is to init in command mode.
///   Still black   -> delivery is broken independently of link mode, and
///     the fault is in the physical LP path or the panel's receive state.
const MINIMAL_CMD_MODE_BTA_TEST: bool = false; // both modes fail identically; back to the kernel-matching ordering

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
    // ENABLE-LATCH CYCLE (SPEC.md task #5 log).
    //
    // Hypothesis: this controller samples its configuration registers on
    // the DSI_CTRL ENABLE 0->1 edge into the active datapath. Config
    // written while ENABLE is already set lands in the register file --
    // so a later readback returns the right value and every audit diffs
    // clean -- but never reaches the datapath. Correct values, wrong
    // datapath. That fits every observation: registers match, packets are
    // byte-perfect in DRAM, DMA completes, and the panel receives nothing.
    //
    // Circumstantial support: dsi_sw_reset() in the kernel explicitly
    // reads DSI_CTRL, clears ENABLE if set, resets, then restores it --
    // mainline goes out of its way never to reconfigure a running
    // controller. The latch semantics themselves are not publicly
    // documented, so this is inference, not proof.
    //
    // b39 already reordered bring-up so all config precedes the ENABLE
    // write. But several things still touch config AFTER that: the
    // video-mode switch in dpu_start(), the TRIG_CTRL restore, and the
    // per-command CMD_MODE_EN OR-in. So force a clean latch immediately
    // before the first DCS byte: drop ENABLE, let it settle, set it again.
    // If the mechanism is real, this alone should change the outcome.
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

    udelay(250000); // bumped 100ms -> 250ms brute-force test (SPEC.md task #5 log)

    // COMMAND PACING (SPEC.md task #5 log).
    //
    // Everything about WHAT we send is now verified identical to the
    // working kernel: the 87-command table diffs 87/87, the transmitted
    // packets are byte-identical including the 132-byte PPS, the bytes are
    // confirmed correct in DRAM at fetch time, the ordering matches, the
    // host state at command time matches, the panel is powered and the
    // reset line physically toggles. Yet the handoff test proved our init
    // does not configure the DDIC.
    //
    // So the remaining variable is not content but RATE. Measured from the
    // kernel's own ktime trace: init_seq enter 668.875ms, exit 856.742ms
    // -- 187.9ms for ~95 commands, i.e. about 2ms per command. That is not
    // a deliberate delay in the panel driver; it is the natural cost of
    // the kernel's per-transfer path (mutex, per-transfer link clock
    // enable/disable, IRQ completion wait).
    //
    // This driver has none of that. Each command is a DMA trigger plus a
    // busy-poll that clears in microseconds, so we blast the entire
    // sequence in a small fraction of the time the panel has ever been
    // given. A DDIC that needs settling time between register writes --
    // especially across the 0xff page switches, which reconfigure which
    // register bank subsequent writes land in -- would silently drop most
    // of them while every command still reports success.
    //
    // Pace to match the kernel's measured rate.
    const INIT_CMD_PACING_US: c_ulong = 2000;

    // See the tail-only block below. ANSWERED: still black, so our commands
    // do not land at all, table or not -- the 87-command table is ruled out
    // as the cause. Restored to the faithful full sequence, which is also
    // what makes a Get Power Mode reply interpretable (0x9C = sleep-out,
    // normal mode, display on) rather than reflecting a half-configured
    // DDIC.
    const SKIP_INIT_TABLE_TEST: bool = false;

    // DIAGNOSTIC (SPEC.md task #5 log): a new, genuine DMA timeout
    // appeared after the DSI 6G register-shift fix + re-stolen values
    // (previously every command "completed" with no response; now
    // something actually hangs). Encode WHICH command failed into the
    // return value (-(10000+index) for the init-sequence loop,
    // -(20000+stage) for the named stages after it) instead of just
    // propagating the raw errno, so the failure point is visible via
    // the sheng.panel env var without needing a live console.
    // TAIL-ONLY TEST (SPEC.md task #5 log).
    //
    // Measured on this device: patching the KERNEL to skip the 87-command
    // table and send only the DSC tail (0x90, PPS, 0x9d, 0xb2/0xb3, Exit
    // Sleep, Display On) still lights the panel -- glitchy, because the
    // table is what programs the 0x3b VBP/VFP timings and 0x05=0x00
    // auto-porch disable, but unmistakably DISPLAYING.
    //
    // So the DDIC needs only ~8 commands to produce pixels. We send all 95
    // and get nothing. That raises a possibility nothing so far has tested:
    // that one of OUR 87 table commands puts the panel into a state the
    // tail cannot recover from -- most likely one of the 0xff page
    // switches, which change which register bank subsequent writes land
    // in. A mis-landed page switch would silently redirect every following
    // write, and the tail would then configure the wrong bank.
    //
    // Run exactly the kernel's experiment on our side.
    //   anything appears -> our table is what breaks it, and the search
    //     collapses onto 87 commands we can bisect.
    //   still black -> our commands do not land at all, table or not,
    //     which is consistent with everything else and rules the table out.
    if (!SKIP_INIT_TABLE_TEST) {
    var idx: i32 = 0;
    for (nt36532e_init_sequence) |entry| {
        // BISECT (b110): stop after N table commands. Everything else is
        // excluded -- transport verified both ways (b105: first-ever DCS
        // reply 0x08, BTA_DONE=1), init transmits clean with no timeouts,
        // link byte-identical to a rendering Linux, video proven
        // irrelevant (b108: no video at all, still unconfigured), and
        // pacing proven irrelevant (b109: +1ms per command, no change).
        // Yet these same 94 bytes replayed from Linux reach 0x9c.
        //
        // The INIT_STOP_AFTER bisect that used to gate this loop (send only
        // the first N commands, skip the DSC tail, and let Linux read the
        // DDIC's power mode) is gone. It was chasing "one of these commands
        // wedges the panel", which was never true: the panel was fine and
        // the display was being torn down later in board_late_init(). See
        // board_preboot_os() and sheng_ktz8866_backlight_init() in board.c.
        const ret = dsiSendDcs(dsi0_base, dsi1_base, dma_scratch, entry.cmd, entry.args);
        if (ret != 0) return -(10000 + idx);
        udelay(INIT_CMD_PACING_US);
        idx += 1;
    }
    g_init_sent = idx;
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

    // REMOVED (SPEC.md task #5 log): a `0x51 0x00 0x00` write used to sit
    // here, followed by a 200ms hold. It was the "panel liveness test" --
    // set display brightness to zero and watch for the backlight to dim,
    // proving the panel executes what we send.
    //
    // That test was retired as INVALID, because the KTZ8866 is in
    // I2C-brightness mode: its level comes over I2C (the visible
    // soft-start ramp proves it), so DCS 0x51 can never move the
    // backlight. Correct -- and it retires exactly one claim, that 0x51
    // affects the BACKLIGHT. It says nothing about whether 0x51 affects
    // the PANEL'S OWN OUTPUT, and the write was left applied anyway.
    //
    // It does. The init table sends 0x51 0x0f 0xff (max) and then
    // 0x53 0x24 == BCTRL | BL, which arms the DDIC's own brightness
    // control block and tells it to APPLY the 0x51 value. Setting that
    // value to zero with BCTRL armed is a standard way for a DDIC to
    // output black while the backlight stays fully lit -- and 0xfb 0x01
    // earlier in the sequence tells it not to reload from defaults, so it
    // survives the sleep-out/display-on that follow.
    //
    // "Backlight on, no pixels" is what this driver has been reporting.
    // Every pipe-level bisect run while this was in place -- solid fill,
    // border-only, DSI TPG -- was measured through a panel that had been
    // instructed to display nothing, which is why mutually exclusive
    // hypotheses all produced identical black.

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

// ===================================================================
// SSPP registers found by the DPU write trace (SPEC.md task #5 log).
//
// Hooking dpu_reg_write() on the working kernel and diffing the SSPP
// offsets it writes against ours found NINE registers this driver has
// never written. The important one is the pixel-extension block:
//
//   SW_PIX_EXT_C0_REQ_PIXELS  (0x108) = 0x07F005F4
//   SW_PIX_EXT_C1C2_REQ_PIXELS(0x118) = 0x07F005F4
//   SW_PIX_EXT_C3_REQ_PIXELS  (0x128) = 0x07F005F4
//
// 0x07F005F4 is (2032 << 16) | 1524 -- the same height/width as
// SSPP_SRC_SIZE. dpu_hw_sspp_setup_pe_config() programs how many pixels
// the pipe actually REQUESTS per plane. Left at zero, the fetch is
// configured, the format is right, the address is right, the pipe is
// marked fetch-active -- and it asks the bus for nothing. Everything
// downstream then faithfully compresses and transmits a black frame,
// which is exactly this driver's symptom, with every audit passing.
//
// Also written by the kernel and never by us:
//   0x330 clk_ctrl -- an SSPP CLOCK GATE, same shape as DSC_CLK_CTRL
//                     (traced 0x4 then 0x5; 0x5 is the settled value)
//   0x138 / 0x1c8 ubwc_error = 0x80000000 (rect0 / rect1)
//   0x134 / 0x13c = 0x00000009
//   0x01c / 0x020 SRC2/SRC3_ADDR = 0, 0x028 YSTRIDE1 = 0
//   0x060/0x064/0x06c/0x074/0x078 danger/safe/QoS-ctrl/creq LUTs
//
// NOTE on the QoS LUTs: an earlier pass wrote these alone and measured a
// REGRESSION, so they were reverted. That measurement was taken without
// the pixel-extension and clock-gate writes above, i.e. on a pipe that
// could never fetch anyway. They are part of what the kernel programs,
// so they go back in together rather than being cherry-picked.
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
// Back to the REAL framebuffer path (SPEC.md task #5 log). Solid fill
// answered its question -- an in-pipe colour with zero memory fetch is
// still black -- so leaving it on only masks the actual fetch path and
// pins sheng.verify at 0x800000 (bit23, SSPP_SRC_FORMAT).
const SSPP_SOLID_FILL_TEST: bool = false;

/// FETCH PROBE (SPEC.md task #5 log).
///
/// Everything in the DPU, DSI, PHY, DISPCC, VBIF and MDSS now matches the
/// working kernel write-for-write, and the panel is still black. One thing
/// has never been established either way: whether the SSPP actually issues
/// memory reads at all.
///
/// All the evidence so far is compatible with BOTH "it fetches and the
/// data is fine" and "it never fetches": SMMU CB_FSR reports no
/// translation fault (TF clear), which is what you get from a correct
/// fetch AND from no fetch whatsoever. Until b25 the pixel-extension
/// REQ_PIXELS registers were zero, so "no fetch" was entirely plausible.
///
/// This settles it. Point SSPP_SRC0/SRC1_ADDR at an address deliberately
/// OUTSIDE the 1GB identity block our SMMU context bank maps
/// (SMMU_FB_IDENTITY_BLOCK_BASE = 0x80000000, so 0x50000000 is unmapped),
/// then read CB_FSR/CB_FAR after the DPU has been streaming.
///
///   FSR shows TF (bit1) and FAR lands near 0x50000000
///     -> the SSPP IS fetching. The memory path works and the fault is in
///        what happens to the pixels afterwards.
///   FSR still clean, no fault at all
///     -> the SSPP never issues a read. Every downstream block is then
///        faithfully processing nothing, which is exactly a black screen
///        with a perfect register set, and the whole investigation moves
///        to why the fetch is not being issued.
///
/// Deliberately breaks the image -- diagnostic only, revert to false.
const SSPP_FETCH_PROBE_TEST: bool = false; // ANSWERED: FSR=0x402 (TF set), FAR=0x500017c0 -- the SSPP genuinely fetches, and the real address translates cleanly.
const SSPP_FETCH_PROBE_ADDR: u32 = 0x50000000;
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

/// PROGRAMMABLE FETCH START -- NEVER WRITTEN, WHILE ITS ENABLE BIT WAS
/// (SPEC.md task #5 log).
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
/// The trace shows exactly that on both interfaces: INTF_CONFIG written
/// 0x00800000 by the timing-engine setup, then 0x80800000 once BIT(31) is
/// OR'd in, with INTF_PROG_FETCH_START = 0x0014CA28 in between.
///
/// This driver copied the FINAL INTF_CONFIG (0x80800000) straight from a
/// live register read -- so we have had programmable fetch ENABLED all
/// along while never programming the line at which fetch starts. That
/// leaves the start point at whatever ABL/POR left. An interface told to
/// prefetch from an arbitrary point relative to vsync will not deliver a
/// coherent frame, and nothing downstream reports an error.
///
/// Classic case of a live-value copy hiding a missing write: the enable
/// bit survives into the readback, the value register does not announce
/// itself. Identical on INTF_1 and INTF_2, as expected for equal halves.
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
// VBIF -- the DPU's memory-interface block (SPEC.md task #5 log).
//
// A THIRD entire block this driver has never written, found by diffing
// which blocks dpu_reg_write() touches on the working kernel against
// ours. VBIF is where the DPU's fetch clients get their memory type and
// QoS priority; left unprogrammed, the pipe's reads are not classified
// or prioritised at the bus at all.
//
// Base is NOT dpu_base + 0x74000. VBIF is a SEPARATE ioremap --
// dpu_kms.c does msm_ioremap(pdev, "vbif") and sm8550.dtsi gives
// mdss_mdp `reg-names = "mdp", "vbif"` -- so the 0x74000 seen in the
// trace is just where that mapping happened to land in kernel VA.
// Verified by reading the real address on the device: 0x0aeb0160 and
// 0x0aeb0164 read 0x33333333, 0x0aeb0550 reads 0x00000030, matching the
// traced values exactly.
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
// Set equal to SHENG_MDSS_DSI_DMA_SCRATCH_PHYS so the IOVA computed in
// dsiCmdDmaTrigger() comes out identity (iova == dma_addr), resolved by
// the SSPP-validated identity block rather than the 3-level walk. See
// SHENG_MDSS_DSI_DMA_SCRATCH's comment in sheng_mdss.c.
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
/// Leave the MDSS context bank's stage-1 MMU disabled so DSI DMA uses
/// physical addresses directly. Set false to restore translation.
const SMMU_STAGE1_PASSTHROUGH: bool = true;
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
    // b105: THE CODE AND ITS OWN COMMENT DISAGREE.
    //
    // The block comment above smmuBypassMdssStream() describes the chosen
    // workaround as "a context bank whose stage-1 MMU is left DISABLED
    // (SCTLR.M unset, TCR/TTBR/MAIR all zero) -- physical addresses still
    // pass straight through untranslated, but the word BYPASS never
    // appears in the S2CR write the hypervisor is watching for."
    //
    // The code does the opposite: it programs real TTBR0/TCR/MAIR and sets
    // SCTLR.M, so every DSI command DMA is TRANSLATED through page tables
    // this driver builds by hand. Copying Linux's SCTLR "exactly" is the
    // wrong target -- Linux translates because it hands the engine an IOVA
    // (0x1000, seen live); we hand it a physical address (0xa3100000) and
    // then rely on a hand-built identity map to undo that.
    //
    // Everything else is now excluded: the 94-command table is proven
    // correct (replayed from Linux it drives the panel 0x08 -> 0x9c), the
    // rails genuinely power-cycle, the reset pulse physically asserts, the
    // lane state at command time matches a Linux that transmits fine, and
    // every register block is byte-identical. The one thing never verified
    // is that the DSI engine's DMA fetch actually returns the bytes we put
    // in DRAM -- the CPU readback proves only what the CPU sees.
    //
    // So do what the comment says: leave stage-1 disabled. Transactions
    // pass through untranslated, physical addresses are used as-is, and the
    // entire page-table question disappears. S2CR still reads TYPE_TRANS,
    // so the hypervisor never sees a BYPASS write.
    const sctlr: u32 = if (SMMU_STAGE1_PASSTHROUGH)
        (SMMU_SCTLR_LIVE_LINUX_VALUE & ~@as(u32, 1)) // clear M: no translation
    else
        SMMU_SCTLR_LIVE_LINUX_VALUE;
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
    mmioWrite32(sspp_base, SSPP_SRC0_ADDR, if (SSPP_FETCH_PROBE_TEST)
        SSPP_FETCH_PROBE_ADDR
    else
        @truncate(fb_addr));
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
    mmioWrite32(sspp_base, SSPP_SRC1_ADDR, if (SSPP_FETCH_PROBE_TEST)
        SSPP_FETCH_PROBE_ADDR
    else
        @truncate(fb_addr));
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
        // Disable dither on both pingpongs -- see PP_DITHER_BASE.
        mmioWrite32(pp0_base, PP_DITHER_BASE, 0);
        mmioWrite32(pp1_base, PP_DITHER_BASE, 0);

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
    mmioWrite32(ctl_base, CTL_MERGE_3D_ACTIVE, 0);
    mmioWrite32(ctl_base, CTL_DSC_ACTIVE, if (enable_dsc) @as(u32, 0x3) else 0); // DSC_0, DSC_1
    mmioWrite32(ctl_base, CTL_INTF_MASTER, @as(u32, 1) << 1); // INTF_1 is master
    // Permit SSPP_DMA0 to fetch -- see CTL_FETCH_PIPE_ACTIVE's comment.
    mmioWrite32(ctl_base, CTL_FETCH_PIPE_ACTIVE, CTL_FETCH_PIPE_SSPP_DMA0);

    // ===================================================================
    // SPLIT DISPLAY -- THE BONDED-DSI TOP-LEVEL CONFIG (SPEC.md task #5).
    //
    // Found by hooking dpu_reg_write() on the working kernel and diffing
    // which BLOCKS it touches against ours. Linux writes three blocks this
    // driver has never written at all, and this is the one that is
    // specifically about driving one panel from two interfaces.
    //
    // dpu_hw_setup_split_pipe() in dpu_hw_top.c, traced values:
    //     SSPP_SPARE                (0x028) = 0x00000000
    //     SPLIT_DISPLAY_LOWER_PIPE_CTRL (0x3f0) = 0x00000100
    //     SPLIT_DISPLAY_UPPER_PIPE_CTRL (0x2f8) = 0x00000010
    //     SPLIT_DISPLAY_EN          (0x2f4) = 0x00000001
    // in exactly that order, EN written last.
    //
    // Decoding against dpu_hw_top.c's own field definitions:
    //     FLD_INTF_1_SW_TRG_MUX = BIT(4) = 0x010
    //     FLD_INTF_2_SW_TRG_MUX = BIT(8) = 0x100
    // so upper pipe = INTF_1, lower pipe = INTF_2 -- the `else` branch of
    // that function, i.e. the master interface is INTF_1. That agrees with
    // our CTL_INTF_MASTER (bit1 = INTF_1) independently.
    //
    // Without SPLIT_DISPLAY_EN the MDP does not treat INTF_1 and INTF_2 as
    // two halves of ONE display: they are not trigger-muxed together, so
    // the two halves are not driven as a coherent frame. Every per-block
    // register can be correct -- and ours all are, every audit reads 0 --
    // while the panel is fed something it cannot assemble.
    //
    // This is a top-level block, so it appears in no per-block register
    // diff. Same shape as GCC_DISP_HF_AXI_CLK, DSC_CLK_CTRL, the MDSS UBWC
    // block and DSI VID_CFG1: state that lives above everything we audited.
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

    if (DPU_TEST_STOP_STAGE <= 5) return 0;

    // -- Switch both DSI hosts from command mode to video mode before
    // the timing engines start pushing pixel data. Moving this earlier
    // (before the DCS sequence) was tried and measurably regressed the
    // DSC encoder -- see the note in sheng_mdss_dsi_panel_init().
    dsiHostSwitchToVideoMode(dsi0_base);
    dsiHostSwitchToVideoMode(dsi1_base);

    if (DPU_TEST_STOP_STAGE <= 6) return 0;

    // TIMING ENGINE MOVED BELOW THE FLUSH (SPEC.md task #5 log).
    //
    // This used to enable both timing engines HERE, before CTL_FLUSH,
    // justified as "what dpu_encoder_phys_vid_enable() does". Checked
    // against the actual kernel this device runs (ianchb/sm8550-mainline
    // @005aa8cc): dpu_encoder_phys_vid_enable() does NOT touch the timing
    // engine at all. It only programs the timing registers and the
    // pending-flush bits. The engine is enabled later, in
    // dpu_encoder_phys_vid_handle_post_kickoff(), whose own comment is
    // explicit:
    //
    //   /*
    //    * Video mode must flush CTL before enabling timing engine
    //    * Video encoders need to turn on their interfaces now
    //    */
    //
    // So the kernel order is flush-then-enable and ours was the exact
    // inverse. This also matches the ktime-stamped trace taken off this
    // device, where intf_timing_engine enable=1 lands 2.2ms AFTER the
    // panel init sequence completes, as the last step.

    if (DPU_TEST_STOP_STAGE <= 7) return 0;

    // -- CTL flush (v1 path, core_major_ver>=5): per-block flush masks
    // written to their own registers first, then the aggregate pending
    // mask to CTL_FLUSH.
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

/// PHYSICAL LANE STATE (SPEC.md task #5 log).
///
/// The closest thing to a scope that exists in software here, and never
/// read in this project. dsi.xml's LANE_STATUS (logical 0x0a4):
///
///   DLN0-3_STOPSTATE   bits 0-3   } lane is parked in LP-11 (idle)
///   CLKLN_STOPSTATE    bit  4     }
///   DLN0-3_ULPS_ACTIVE_NOT bits 8-11  } NOT in ultra-low-power state
///   CLKLN_ULPS_ACTIVE_NOT  bit  12    }
///
/// Read off this device while Linux drove the panel:
///   DSI0 = 0x00001F00  -- ULPS_ACTIVE_NOT all set, ALL STOPSTATE CLEAR,
///                         i.e. the lanes are genuinely being driven.
///   DSI1 = 0x00001F1F  -- same, but parked at the sampling instant
///                         (expected on a burst-mode link between bursts).
///
/// This is the discriminator we have been missing between the only two
/// remaining explanations:
///
///   STOPSTATE bits CLEAR (like live DSI0) while we stream
///     -> the PHY really is driving the lanes. Everything on the SoC side
///        is doing its job and the fault is at or inside the panel.
///   STOPSTATE bits STUCK SET on both links
///     -> the lanes never leave LP-11. Nothing is physically transmitted,
///        which explains the panel ignoring commands on LP and HS alike
///        and never answering a BTA, with every register still correct.
///
/// Sampled while the DPU has been streaming, so a link that is genuinely
/// transmitting cannot read as permanently parked.
///
/// Returns DSI0 LANE_STATUS << 32 | DSI1 LANE_STATUS.
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

/// bit 63 is reserved for the master/slave-dependent CLK_CFG1 entry so the
/// table above can stay shared between both PHYs.
const PHY_AUDIT_CLK_CFG1_BIT: u6 = 63;

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

/// FULL SLAVE-PHY (DSI1) CMN SWEEP (SPEC.md task #5 log).
///
/// THE LARGEST UNVERIFIED SURFACE IN THE WHOLE DRIVER. Both existing
/// sweeps -- cmn_sweep_table (124 regs) and lanepll_sweep_table (412) --
/// are only ever run against SM8550_MDSS_DSI0_PHY_BASE. PHY1 has never
/// been swept even once. Its only coverage was phy_audit_table, which is
/// 31 entries AND deliberately skips 0x010, 0x03c, 0x140 and everything
/// >= 0x500 on the slave as "don't care".
///
/// "Don't care" is the wrong model. Linux never WRITES those slave
/// registers, but they are not therefore irrelevant -- they hold values
/// inherited from ABL that the slave link still runs on. Confirmed live
/// on a rendering Linux: PHY1 CMN_CLK_CFG0 (0x010) reads 0x000000F1 and
/// appears nowhere in the kernel's own PHY write trace. Nothing in Linux
/// put it there; ABL did, and Linux simply does not disturb it.
///
/// This driver DOES disturb it: it pulses a DSI PHY reset. dsi_phy.c's own
/// comment says "Resetting DSI PHY silently changes its PLL registers to
/// reset status", and Linux compensates with
/// msm_dsi_phy_pll_restore_state() -- which it runs only when
/// `phy->usecase != MSM_DSI_PHY_SLAVE`. So on the slave, nobody restores
/// anything, and whatever our reset destroyed stays destroyed.
///
/// On a bonded panel that is a whole-link failure, not a half-image: the
/// DDIC needs synchronised SOT on both links, so a broken slave makes it
/// reject EVERY transaction -- including commands. That matches every
/// symptom we have: black screen, no BTA response on either trigger
/// pattern, and a host that reports flawless transmission because its own
/// side really is fine.
///
/// Expectations captured register-by-register from THIS device via devmem
/// while Linux was rendering, at explicit offsets only (never a blind
/// range read -- those wedge this hardware's bus).
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

/// Raw readout of the PHY status region on BOTH PHYs.
///
/// phy1_cmn_sweep came back with exactly one mismatch, at CMN offset
/// 0x144 -- a register that does not exist in the kernel's own register
/// XML (which defines 0x140 PHY_STATUS, 0x148 LANE_STATUS0, 0x14c
/// LANE_STATUS1, and nothing at 0x144). It reads 0x58 on BOTH PHYs under
/// a rendering Linux, and PHY0 reads 0x58 under U-Boot too -- only our
/// SLAVE differs. An undocumented register wedged between status
/// registers is almost certainly itself status, so this is a symptom of
/// the slave PHY sitting in a different internal state, not a config
/// value we forgot to write.
///
/// The sweep only reports "first mismatching offset + count", never the
/// value, so the actual number has never been seen. Report the whole
/// status region raw, both PHYs, so it can be read directly:
///   63:48 PHY0 0x140   47:32 PHY0 0x144
///   31:16 PHY1 0x140   15:0  PHY1 0x144
/// Expected from live Linux: PHY0 0x140=0x1F, PHY1 0x140=0x19, both
/// 0x144=0x58. A PHY1 0x144 of 0x00 would suggest the slave block is not
/// fully powered/ready; anything else narrows what state it is stuck in.
/// BRING-UP BISECT ON THE ONE DIVERGENT PHY BIT (SPEC.md task #5 log).
///
/// After sweeping both PHYs completely (PHY0 CMN 124 + lane/PLL 412, PHY1
/// CMN 124 + lane 160) exactly ONE register disagrees with a rendering
/// Linux: CMN 0x144, which reads 0x59 under U-Boot and 0x58 under Linux.
/// That register is not in the kernel's register XML at all -- the CMN
/// domain defines 0x140 PHY_STATUS, 0x148 LANE_STATUS0, 0x14c
/// LANE_STATUS1, and nothing at 0x144.
///
/// Two live experiments on the device established what it means:
///   * Blanking the display (fb0/blank) drops 0x144 to 0x00 on both PHYs,
///     alongside PHY_STATUS going 0x1F/0x19 -> 0x00. Unblanking restores
///     0x58. So 0x58 is the "PHY up and streaming" value and 0x00 is
///     "PHY off" -- our 0x59 is the healthy value PLUS one extra bit, not
///     a not-ready state.
///   * Sampling it 300 times in a row on a rendering Linux returned
///     0x58 every single time. Bit 0 never sets there, so our persistent
///     0x59 is a stable divergence, not a transient sampled at the wrong
///     moment.
///
/// Rather than reverse-engineer an undocumented bit from the outside, use
/// it as the instrument it already is. Sample 0x144 at eight ordered
/// points through our own bring-up and pack the raw byte from each into
/// one value; the first slot where it turns 0x59 is the step that causes
/// the divergence. Slot 0 is read immediately after the GDSC comes up,
/// before this driver has touched the PHY at all, so it also answers a
/// question we have never asked: whether ABL hands the PHY over already
/// in this state, or whether we put it there.
///
/// Slot 0 is the LOW byte. Reading PHY registers needs the GDSC and AHB
/// clock up, which is why no slot is placed earlier than that.
var g_phy144_marks: [8]u8 = .{0} ** 8;

/// DID THE HOST ACTUALLY SHIFT BYTES OUT? (SPEC.md task #5 log)
///
/// Everything comparable now matches or is proven benign: both PHYs
/// completely (PHY0 CMN 124 + lane/PLL 412, PHY1 CMN 124 + lane 160), the
/// DSI host 176/176, DPU/DISPCC/VBIF/MDSS by write-trace diff, clocks
/// (INTF runs 146fps against a 144Hz panel), both power rails exonerated
/// by break-Linux probes, and the last outlier -- CMN 0x144 bit 0 -- shown
/// harmless when a rendering Linux was caught answering a DCS read at
/// 0x59, the same value we have.
///
/// And yet our transmit provably does not reach the DDIC. That leaves two
/// fundamentally different failure shapes, which every diagnostic so far
/// is blind to because both end with "DMA completed, no error":
///
///   A. The DMA never delivered the right bytes to the host (address,
///      translation or cache problem). The command FIFO would then have
///      been fed garbage or nothing.
///   B. The host received the bytes and framed them correctly, but the
///      PHY never drove them onto the pads.
///
/// FIFO_STATUS distinguishes them. It reports the command/video FIFO
/// fill and empty flags per lane, so it shows whether bytes actually
/// moved through the transmit path rather than merely whether the DMA
/// engine's busy bit cleared. This register already earned its keep once
/// on this project: it read 0xdddd1211 -- all four lanes simultaneously
/// overflowing AND underflowing -- which is what exposed the pixel-clock
/// divider bug. It has not been looked at since that was fixed.
///
/// Sampled immediately after the DCS read attempt, so it describes the
/// transmit path at the exact moment we know the panel did not answer.
///   63:32  FIFO_STATUS
///   31:16  STATUS0 low half
///   15:8   DLN0_PHY_ERR low byte (lane-level PHY errors)
///   7:0    LANE_STATUS low byte (stopstate/HS per lane -- if the lanes
///          never leave stop state, the PHY never transmitted and this is
///          case B)
/// CORRECTED (SPEC.md task #5 log). The first version of this sampled
/// before sheng_mdss_dpu_start(), i.e. with the link IDLE, and was then
/// compared against a live Linux that was mid-stream. That comparison is
/// meaningless: half the bits in both registers describe whether traffic
/// is currently flowing.
///
/// Measured that way it "found" two differences that were pure artefacts
/// of the sampling point -- FIFO_STATUS 0x11111210 vs Linux 0x00001210,
/// and LANE_STATUS low byte 0x1F (all five lanes in STOPSTATE, correct
/// for an idle link) vs Linux 0x00 with 0x1F00 set (all five lanes out of
/// ULPS and actively transmitting). DLN0_PHY_ERR read 0x88 on BOTH sides,
/// so the apparent "lane 0 PHY error" was nothing -- Linux reads
/// 0x00088888 there too, making it a config/timer register rather than an
/// error latch.
///
/// Sample after the DPU is started and has been streaming, which is the
/// same state Linux is in when read via devmem, and report both registers
/// at FULL width rather than truncating -- the ULPS bits live in the high
/// half of LANE_STATUS and were being thrown away.
///
///   63:32  FIFO_STATUS   -- Linux, streaming: 0x00001210
///   31:0   LANE_STATUS   -- Linux, streaming: 0x00001F00
///          (bits 0-4 = per-lane STOPSTATE, bits 8-12 = ULPS_ACTIVE_NOT)
///
/// If ours still shows STOPSTATE set while the DPU is streaming 146fps
/// into it, the lanes are not transmitting despite a running timing
/// engine -- which is exactly the "case B" signature: host framed the
/// bytes, PHY never drove the pads.
/// LANE ACTIVITY DISTRIBUTION -- a single sample of LANE_STATUS is
/// worthless, measured (SPEC.md task #5 log).
///
/// b62 sampled LANE_STATUS once with the DPU streaming and got
/// 0x00001F0F on both hosts: all four DATA lanes in STOPSTATE with the
/// CLOCK lane running. That looked like the whole answer -- host frames
/// bytes, data lanes never drive, panel hears nothing.
///
/// It is not, and the check that saved it was sampling a RENDERING Linux
/// 200 times at the same register:
///     191x 0x00001F00   data lanes transmitting
///       6x 0x00001F1F   everything in stop state
///       3x 0x00001F0F   data lanes in stop state, clock running
/// Our exact "smoking gun" value occurs 1.5% of the time on a working
/// link. This panel is MIPI_DSI_MODE_VIDEO_BURST with
/// MIPI_DSI_CLOCK_NON_CONTINUOUS, so data lanes legitimately drop to LP
/// between bursts and a one-shot read mostly measures luck.
///
/// The DISTRIBUTION is the real discriminator: Linux drives the data
/// lanes in ~95% of samples. So sample repeatedly here and report counts.
///
/// Spacing matters as much as count. 256 back-to-back MMIO reads span
/// well under one 6.9ms frame period and could all land inside a single
/// blanking interval, reproducing the same artefact with more samples.
/// 100us between samples spreads 256 reads over ~25ms, roughly 3.7 frames
/// at 144Hz, so every phase of the frame is covered.
///
///   63:32  samples (of 256) with all four data lanes OUT of stopstate
///   31:0   samples (of 256) with the clock lane OUT of stopstate
///
/// Linux reference: ~244/256 data-active. A result of 0 means the data
/// lanes NEVER transmit and the failure is localised to the lanes. A
/// result near 244 means they do transmit and the fault is in WHAT is on
/// the wire, not whether anything is.
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
