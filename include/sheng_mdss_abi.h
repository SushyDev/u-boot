/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * The C <-> Zig boundary for the sheng MDSS driver.
 *
 * Everything crossing between sheng_mdss_hw.zig and its C callers is
 * declared here, once. Both board/qualcomm/sheng/sheng.c and
 * drivers/video/qualcomm/sheng_mdss.c include it, so a signature change
 * on either side is a compile error rather than a link that succeeds and
 * a board that hangs.
 *
 * These used to be bare `extern` declarations scattered through the two
 * .c files -- eight functions and two globals, none of them checked
 * against anything.
 *
 * This header is declarations only. It is safe to include with
 * CONFIG_VIDEO_SHENG_MDSS=n, where sheng_mdss.c and the Zig objects are
 * not built at all; sheng.c guards its calls at the call site.
 */

#ifndef __SHENG_MDSS_ABI_H
#define __SHENG_MDSS_ABI_H

#include <linux/build_bug.h>
#include <linux/stddef.h>
#include <linux/types.h>

/*
 * Bring-up state owned by sheng_mdss_hw.zig, mirroring `ShengDiag` there.
 *
 * The signature fields were a bare `unsigned int reg[9]`, filled by index
 * in Zig and decoded BY POSITION into column names in the C formatter.
 * Inserting one register silently relabelled every column of the
 * diagnostic used to classify glitched boots. They are named on both
 * sides now, and the asserts below pin the layout.
 */
struct sheng_diag_state {
	long long panel_pm;
	long long panel_pm_pre;
	int fastpath;
	int fastpath_state_ok;
	int panel_init_ret;
	int panel_init_ret_first;
	unsigned int probe_count;

	/* Display signature, sampled once the pipeline is streaming.
	 * frames_early/frames_late bracket a deliberate gap: a count that
	 * CHANGES is the only proof the timing engine is running rather
	 * than merely configured. */
	unsigned int status0;
	unsigned int fifo;
	unsigned int fifo_late;
	unsigned int lane;
	unsigned int ackerr;
	unsigned int timeout;
	unsigned int pll_l;
	unsigned int frames_early;
	unsigned int frames_late;
};

/* Framebuffer description produced by the Zig bring-up, mirroring
 * `ShengFb`. Nothing in Zig touches a U-Boot struct, so a U-Boot bump
 * cannot silently change a layout underneath it. */
struct sheng_fb {
	unsigned long base;
	unsigned long size;
	unsigned int xsize;
	unsigned int ysize;
	unsigned int stride;
	int inherited;
};

/*
 * LAYOUT LOCK. The same three numbers are asserted in sheng_mdss_hw.zig
 * as a comptime block. This is a pinned handshake, not a shared source of
 * truth -- deliberately so, because pulling U-Boot's header tree into a
 * freestanding `zig build-obj` is not worth the build complexity. Edit
 * either side and that side stops building with a message naming the
 * other.
 */
static_assert(sizeof(struct sheng_diag_state) == 72,
	      "ShengDiag/sheng_diag_state size drift -- update sheng_mdss_hw.zig's comptime block");
static_assert(offsetof(struct sheng_diag_state, status0) == 36,
	      "ShengDiag/sheng_diag_state signature block moved -- update sheng_mdss_hw.zig's comptime block");
static_assert(sizeof(struct sheng_fb) == 32,
	      "ShengFb/sheng_fb size drift -- update sheng_mdss_hw.zig's comptime block");

/* A stage or sample that never ran. Matches NEVER_RAN in the Zig and
 * SHENG_MDSS_STATUS_NOT_REACHED in sheng_mdss_debug.h. */
#define SHENG_NEVER_RAN 0x7fffffff

/* --- Implemented in sheng_mdss_hw.zig ------------------------------- */

void sheng_gpio_set(unsigned int gpio, bool high);
u32 sheng_gpio_read(unsigned int gpio);

int sheng_mdss_bringup(int splash_live, struct sheng_fb *fb);
void sheng_mdss_intf_stop(unsigned long dpu_base);
void sheng_mdss_dsi_panel_sleep(unsigned long dsi0_base, unsigned long dsi1_base,
				unsigned long dma_scratch);
void sheng_mdss_full_teardown(unsigned long dpu_base,
			      unsigned long dsi0_phy_base,
			      unsigned long dsi1_phy_base,
			      unsigned long dispcc_base);

struct sheng_diag_state *sheng_mdss_diag_state(void);
long long sheng_mdss_gdsc_probe_result(void);
unsigned int sheng_mdss_gdsc_collapse_us(void);
long long sheng_mdss_dsi_init_fail_info(void);
const char *sheng_mdss_tmark_get(unsigned int i, unsigned long *us);
unsigned int sheng_mdss_tmark_count(void);

int sheng_bcm_vote(u32 addr);
int sheng_regulator_vote(u32 addr, u32 millivolts);

/* --- Implemented in drivers/video/qualcomm/sheng_mdss.c ------------- */

void sheng_mdss_teardown(void);
int sheng_mdss_timing_fmt(char *buf, int len);
int sheng_mdss_diag_fmt(char *buf, int len);

/* Did we inherit ABL's live display instead of rebuilding it? Drives the
 * handover to Linux in board_preboot_os(). */
extern int sheng_inherited;

/* --- Implemented in board/qualcomm/sheng/sheng.c -------------------- */

int sheng_ktz8866_set_bias(int enable);
void sheng_breadcrumb_u32(unsigned long addr, u32 value);

/* Decided in qcom_board_init() from our own DTB, consumed by
 * sheng_mdss_probe() to choose inherit vs cold bring-up. */
extern int sheng_abl_splash_live;

/* --- Implemented in arch/arm/mach-snapdragon/board.c ---------------- */

extern unsigned long sheng_uboot_entry_us;
extern unsigned long sheng_board_init_us;

#endif /* __SHENG_MDSS_ABI_H */
