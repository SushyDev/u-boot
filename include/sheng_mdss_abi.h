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

/* A stage or sample that never ran. Matches NEVER_RAN in the Zig. */
#define SHENG_MDSS_STATUS_NOT_REACHED 0x7fffffff

/*
 * Bring-up stages, one status slot each. There must be a slot for EVERY
 * early return in sheng_mdss_probe(): any of them aborts before the
 * framebuffer handoff, and the backlight still comes up in
 * board_late_init(), so the board shows backlight and no picture with no
 * other clue as to why.
 */
enum {
	SHENG_MDSS_STATUS_MDSS_RESET,
	SHENG_MDSS_STATUS_GDSC,
	SHENG_MDSS_STATUS_BCM_MM0,
	SHENG_MDSS_STATUS_DISPCC,
	SHENG_MDSS_STATUS_DSI0_PHY,
	SHENG_MDSS_STATUS_DSI1_PHY,
	SHENG_MDSS_STATUS_DSI_PHY_START,
	SHENG_MDSS_STATUS_DSI_LINK_CLKS,
	SHENG_MDSS_STATUS_DSI_PANEL,
	SHENG_MDSS_STATUS_DPU,
	SHENG_MDSS_STATUS_PROBE,
	SHENG_MDSS_STATUS_COUNT,
};

#define SHENG_MDSS_LOG_MAX 64

/*
 * THE POST-MORTEM BREADCRUMB REGION, as one layout.
 *
 * These slots sit in the no-map area CONFIG_PRE_CON_BUF_ADDR reserves,
 * past U-Boot's own pre-console buffer, and are relayed into /chosen by
 * ft_board_setup() because the board has no reachable UART and Linux
 * cannot read the region directly (/dev/mem gives EFAULT).
 *
 * The offsets used to be bare hex -- 0x3000, 0x3040, 0x3100, 0x3400 --
 * spread across three .c files and kept from overlapping by comments
 * ("Sits clear of the log ring, which ends at 0x3304"). ft_board_setup()
 * also hardcoded the stage array's relay length as `11 * 4` under a
 * comment saying it MUST track SHENG_MDSS_STATUS_COUNT.
 *
 * As a struct, the compiler enforces both: the padding members below fail
 * to compile if any section grows into the next, and every relay length
 * is a sizeof().
 */
struct sheng_blackbox {
	/* +0x000: one status code per bring-up stage. SHENG_MDSS_STATUS_*
	 * order; SHENG_MDSS_STATUS_NOT_REACHED, 0, or -errno. */
	s32 stage[SHENG_MDSS_STATUS_COUNT];
	u8 __pad_stage[0x040 - SHENG_MDSS_STATUS_COUNT * 4];

	/* +0x040: uclass_get_device(UCLASS_VIDEO) result, so "no video
	 * device bound" is distinguishable from "bound, probe failed". */
	s32 uclass_get_device_ret;
	u8 __pad_uclass[0x100 - 0x044];

	/* +0x100: (tag, value) log ring, written only by
	 * sheng_mdss_debug.c. Zeros without that build. */
	struct {
		u32 count;
		struct {
			u32 tag;
			u32 value;
		} entry[SHENG_MDSS_LOG_MAX];
	} log;
	u8 __pad_log[0x400 - 0x100 - 4 - SHENG_MDSS_LOG_MAX * 8];

	/* +0x400: per-chip KTZ8866 init status, [chip_a, chip_b], same
	 * convention as stage[]. */
	s32 ktz8866[2];
	u8 __pad_ktz[0x010 - 2 * 4];

	/* +0x410: KTZ8866 OUTP_CFG/OUTN_CFG as found before our writes,
	 * packed (OUTP << 8) | OUTN. 0x1e1c means ABL's bias config
	 * survived and our writes are a no-op. */
	u32 ktz8866_outcfg;
};

/* The region begins 0x3000 into the pre-console reservation: U-Boot's own
 * pre-console buffer occupies the start of it. All offsets in the struct
 * above are relative to THIS base. */
#define SHENG_BLACKBOX_OFFSET	0x3000
#define SHENG_BLACKBOX							\
	((volatile struct sheng_blackbox *)(uintptr_t)			\
	 (CONFIG_PRE_CON_BUF_ADDR + SHENG_BLACKBOX_OFFSET))

/* Pin the layout the post-mortem scrapers and every previous boot's
 * captured data expect. */
static_assert(offsetof(struct sheng_blackbox, uclass_get_device_ret) == 0x040,
	      "blackbox map drifted at uclass_get_device_ret");
static_assert(offsetof(struct sheng_blackbox, log) == 0x100,
	      "blackbox map drifted at log ring");
static_assert(offsetof(struct sheng_blackbox, ktz8866) == 0x400,
	      "blackbox map drifted at ktz8866 status");
static_assert(offsetof(struct sheng_blackbox, ktz8866_outcfg) == 0x410,
	      "blackbox map drifted at ktz8866_outcfg");

/* --- Implemented in sheng_mdss_hw.zig ------------------------------- */

u32 sheng_gpio_read(unsigned int gpio);

/* Panel reset is ACTIVE LOW and the backlight EN pin gates the KTZ8866's
 * AVDD/AVEE rather than just its LED sinks. Both used to be driven
 * through a shared sheng_gpio_set(pin, bool), where `false` meant "rail
 * off" for one pin and "reset ASSERTED" for another -- same function,
 * opposite senses, no type-level distinction. These name the operation
 * instead, and there is deliberately no way to drive backlight EN low:
 * doing so after the video probe kills the DDIC. */
void sheng_mdss_panel_power_off(void);
void sheng_backlight_enable(void);

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
u32 sheng_mdss_clk_fail_off(void);
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

/* LCD_BIAS_EN is latched over I2C, independently of the chip's enable
 * pins. Leave it set and the KTZ8866 holds the +/-5.8V rails up, the DDIC
 * never loses power, and a reset pulse cannot clear its state -- so this
 * is load-bearing for the panel power cycle, not a hint. Named rather
 * than an int flag for that reason. */
enum ktz8866_bias { KTZ8866_BIAS_OFF = 0, KTZ8866_BIAS_ON = 1 };

int sheng_ktz8866_set_bias(enum ktz8866_bias state);
void sheng_breadcrumb_u32(unsigned long addr, u32 value);

/* Decided in qcom_board_init() from our own DTB, consumed by
 * sheng_mdss_probe() to choose inherit vs cold bring-up. */
extern int sheng_abl_splash_live;

/* --- Implemented in arch/arm/mach-snapdragon/board.c ---------------- */

extern unsigned long sheng_uboot_entry_us;
extern unsigned long sheng_board_init_us;

#endif /* __SHENG_MDSS_ABI_H */
