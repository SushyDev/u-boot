// SPDX-License-Identifier: GPL-2.0+
/*
 * Display driver for the Qualcomm MDSS on SM8550 (Xiaomi Pad 6S Pro,
 * "sheng"). Register sequencing lives in sheng_mdss_hw.zig and is
 * called through the extern declarations below.
 *
 * See ARCHITECTURE.md for the bring-up order, the clock tree and the
 * things that will bite you.
 */

#include <dm.h>
#include <env.h>
#include <log.h>
#include <lmb.h>
#include <video.h>
#include <asm/io.h>
#include <asm/barriers.h>
#include <asm/global_data.h>
#include <cpu_func.h>
#include <soc/qcom/cmd-db.h>
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/kconfig.h>
#include <time.h>
#include <vsprintf.h>

#include "sheng_mdss_debug.h"
#include "sheng_mdss_regs.h"

DECLARE_GLOBAL_DATA_PTR;

/* Register programming lives in sheng_mdss_hw.zig. This file keeps
 * only what needs U-Boot's driver model: the uclass plumbing, the
 * cmd-db lookups, and the sequencing between them. */
extern void sheng_gpio_set(unsigned int gpio, bool high);
extern int sheng_bcm_vote(u32 addr);
extern int sheng_regulator_vote(u32 addr, u32 millivolts);

/*
 * Per-stage bring-up status, relayed into /chosen by ft_board_setup()
 * and readable from Linux at /proc/device-tree/chosen/sheng,mdss-status.
 *
 * Always built, unlike the rest of the debug channel. Every early return
 * in probe aborts before the framebuffer handoff while the backlight
 * still comes up, so without this a failed bring-up is indistinguishable
 * from any other -- backlight on, nothing rendered, no clue which stage.
 *
 * D-cache is on, so each slot must be pushed to DRAM as it is written:
 * a hang on the next instruction would otherwise leave it in a dirty
 * cache line that a post-mortem scrape never sees.
 */
#define SHENG_MDSS_STATUS_ADDR	(CONFIG_PRE_CON_BUF_ADDR + 0x3000)

void sheng_mdss_stage_record(unsigned int stage, int ret)
{
	volatile int *slots = (volatile int *)(uintptr_t)SHENG_MDSS_STATUS_ADDR;

	if (!IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
		return;

	slots[stage] = ret;
	flush_dcache_range(SHENG_MDSS_STATUS_ADDR + stage * sizeof(*slots),
			   SHENG_MDSS_STATUS_ADDR + (stage + 1) * sizeof(*slots));
	dsb();
}

void sheng_mdss_stage_init(void)
{
	unsigned int i;

	for (i = 0; i < SHENG_MDSS_STATUS_COUNT; i++)
		sheng_mdss_stage_record(i, SHENG_MDSS_STATUS_NOT_REACHED);
}

/* Boot timing.
 *
 * There is no console during probe, so marks are only collected here
 * and printed as one block at the end. CONFIG_PRE_CONSOLE_BUFFER holds
 * that block until the console binds, which replays it onto the panel
 * with the rest of the startup log.
 *
 * timer_get_us() reads the ARM generic counter, which U-Boot does not
 * reset. The absolute value on the first mark therefore also measures
 * everything BEFORE us -- XBL, ABL, and U-Boot's own pre-video initcalls
 * -- which is the part no amount of trimming in this file can touch.
 *
 * Always compiled in, unlike SHENG_DBG_*: it is a handful of stores and
 * one printf, and the numbers are worth having on every boot.
 */
/* 32, not 16: the probe can run MORE THAN ONCE (see sheng_probe_count).
 * At 16 the second run's marks silently truncated the record, which is
 * how the retry went unnoticed in the first place. */
#define SHENG_TMARK_MAX 32

/* Per-boot display signature, for chasing the intermittent glitched
 * boot.
 *
 * The glitch is NOT caused by anything in the boot-time timing work --
 * proven 2026-08-22 by flashing the pristine pre-existing tree (b362),
 * which glitches identically. It is the long-standing intermittent
 * panel init.
 *
 * A glitched boot reports success everywhere the existing instruments
 * look: all 11 stage codes read 0, panel_init returns 0, and the probe
 * completes. So the stage array cannot distinguish good from bad, and
 * neither can soak.sh. These registers might: they are sampled at the
 * end of probe, once the pipeline is actually streaming, and relayed to
 * Linux so a boot can be classified without a camera.
 *
 * FRAME_COUNT is read twice with a gap: it is the one value that proves
 * the timing engine is genuinely running rather than merely configured.
 */
/* Declared here as well as further down: the diag formatter below uses
 * them and sits above that block. */
extern long long sheng_mdss_gdsc_probe_result(void);
extern unsigned int sheng_mdss_gdsc_collapse_us(void);
extern long long sheng_mdss_dsi_init_fail_info(void);





#define SHENG_DIAG_N 9

/* The probe can run twice, which corrupts a half-configured DDIC.
 *
 * stdio_add_devices() probes the video device, then qcom_late_init()
 * force-probes it again. Normally DM returns the cached device and the
 * second call is free. But if probe #1 FAILED the device was never
 * activated, so the second call reruns everything: another GDSC
 * collapse, core reset, panel power-cycle and 94-command init, on a
 * panel left mid-bring-up.
 *
 * The retry also overwrites all 11 stage codes with 0, so a failed boot
 * reports clean. Keep the FIRST attempt's result; it says why the panel
 * is broken.
 */
/* Did we inherit ABL's live display instead of rebuilding it? Drives the
 * handover to Linux in board_preboot_os(). */
int sheng_inherited;

/* Decided in qcom_board_init() over I2C -- see its comment. */


/* Bring-up state, owned by sheng_mdss_hw.zig. Mirrors ShengDiag there. */
struct sheng_diag_state {
	long long panel_pm;
	long long panel_pm_pre;
	int fastpath;
	int fastpath_state_ok;
	int panel_init_ret;
	int panel_init_ret_first;
	unsigned int probe_count;
	unsigned int reg[9];
};

extern struct sheng_diag_state *sheng_mdss_diag_state(void);
extern const char *sheng_mdss_tmark_get(unsigned int i, unsigned long *us);
extern unsigned int sheng_mdss_tmark_count(void);

int sheng_mdss_diag_fmt(char *buf, int len)
{
	const struct sheng_diag_state *d = sheng_mdss_diag_state();
	long long fail = sheng_mdss_dsi_init_fail_info();

	return snprintf(buf, len,
			"fastpath=%d probes=%u panel_init_first=%d panel_init=%d"
			" gdsc[%012llx] collapse_us=%d"
			" status0=%08x fifo=%08x fifo_late=%08x lane=%08x"
			" ackerr=%08x timeout=%08x pll_l=%08x"
			" frames=%u->%u pm=%012llx pm_val=%02x"
			" pm_pre=%012llx pm_pre_val=%02x"
			" dsi[retries=%u failidx=%d failrc=%d]",
			d->fastpath, d->probe_count, d->panel_init_ret_first,
			d->panel_init_ret,
			(unsigned long long)sheng_mdss_gdsc_probe_result(),
			(int)sheng_mdss_gdsc_collapse_us(),
			d->reg[0], d->reg[1], d->reg[8],
			d->reg[2], d->reg[3], d->reg[4],
			d->reg[5], d->reg[6], d->reg[7],
			(unsigned long long)d->panel_pm,
			(unsigned int)(d->panel_pm & 0xff),
			(unsigned long long)d->panel_pm_pre,
			(unsigned int)(d->panel_pm_pre & 0xff),
			(unsigned int)(fail >> 32),
			(int)(short)((fail >> 16) & 0xffff),
			(int)(short)(fail & 0xffff)) + 1;
}


/* Same marks, formatted for the /chosen relay in ft_board_setup().
 *
 * The printed block only ever reaches the panel -- serial is absent and
 * the pre-console buffer sits in a no-map reserved region, so Linux
 * reading /dev/mem at CONFIG_PRE_CON_BUF_ADDR gets EFAULT (measured).
 * Going through the FDT instead makes the numbers readable over SSH at
 * /proc/device-tree/chosen/sheng,boot-timing on every boot, with no
 * camera in the loop.
 *
 * Returns bytes written including the NUL, which is what fdt_setprop()
 * wants for a string property.
 */
int sheng_mdss_timing_fmt(char *buf, int len)
{
	unsigned int count = sheng_mdss_tmark_count();
	unsigned long first = 0, prev = 0, us = 0;
	unsigned int i;
	int n = 0;

	if (!count)
		return 0;

	sheng_mdss_tmark_get(0, &first);
	prev = first;
	n += snprintf(buf + n, len - n, "entry=%lums", first / 1000);

	for (i = 1; i < count && n < len; i++) {
		const char *name = sheng_mdss_tmark_get(i, &us);

		n += snprintf(buf + n, len - n, " %s=%lums", name,
			      (us - prev) / 1000);
		prev = us;
	}

	if (n < len)
		n += snprintf(buf + n, len - n, " total=%lums",
			      (prev - first) / 1000);

	return (n < len ? n : len - 1) + 1;
}


/* Panel bias: KTZ8866 over I2C plus GPIOs 30/31. The DDIC needs it
 * before any DCS command. Without it commands go nowhere and the host
 * still reports success -- a plain DCS write needs no ACK, so an
 * unpowered panel looks identical to a live one from the host side. */

extern int sheng_ktz8866_set_bias(int enable);




/* 144Hz mode, nt36532e. Matches the DPU crtc-0 modeline and the panel
 * driver's own mode table. */
#define SHENG_PANEL_HFRONT_PORCH	142
#define SHENG_PANEL_HSYNC_WIDTH		4
#define SHENG_PANEL_HBACK_PORCH		92
#define SHENG_PANEL_VFRONT_PORCH	26
#define SHENG_PANEL_VSYNC_WIDTH		2
#define SHENG_PANEL_VBACK_PORCH		138

/* sheng_mdss_hw.zig */

/* ULTRA-DEBUG BLACKBOX -- see the big comment in sheng_mdss_hw.zig.
 *
 * U-Boot appends an ASCII log to DRAM at 0xa5000000; Linux reads it back
 * through /dev/mem. This exists because CONFIG_SYS_CBSIZE caps
 * /proc/cmdline at 512 bytes, which has meant one question per boot and
 * register sweeps reported as "first mismatch + count" with the actual
 * values never visible. Budget here is ~512KB instead. */
/* Blackbox decls/macros MOVED UP -- see above the panel power/reset
 * helper, which now logs GPIO readbacks and needs them in scope. */

extern void sheng_mdss_dsi_panel_sleep(unsigned long dsi0_base, unsigned long dsi1_base,
					unsigned long dma_scratch);
extern long long sheng_mdss_gdsc_probe_result(void);
extern void sheng_mdss_full_teardown(unsigned long dpu_base,
				      unsigned long dsi0_phy_base, unsigned long dsi1_phy_base,
				      unsigned long dispcc_base);

struct sheng_mdss_priv {
	fdt_addr_t mdss_base;
};

/*
 * Reverse of probe, panel first then hardware. Called from
 * board_preboot_os() -- NOT board_late_init(), which finishes before
 * main_loop() and would destroy the display before the console banner,
 * bootcmd or the boot menu ever draw.
 *
 * Linux needs this. Without it Linux comes up with backlight and no
 * picture, and logs no fault of any kind while doing so.
 */
void sheng_mdss_teardown(void)
{
	if (!IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS))
		return;

	/* 1. Panel: Display Off (0x28) + Sleep In (0x10), while the host and
	 * PHY can still carry commands. */
	sheng_mdss_dsi_panel_sleep(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_DSI_DMA_SCRATCH);

	/* 2. Hardware: DPU timing engines + CTL_START/FLUSH cleared, both
	 * DSI PHYs powered down (lanes disabled, REFGEN vote dropped),
	 * every DSI/MDP DISPCC branch gated off, MDSS core reset pulsed
	 * once more. */
	sheng_mdss_full_teardown(SM8550_MDSS_DPU_BASE,
				  SM8550_MDSS_DSI0_PHY_BASE, SM8550_MDSS_DSI1_PHY_BASE,
				  SM8550_DISPCC_BASE);

	/* 3. Panel to cold-boot state: reset asserted, bias rails dropped.
	 * The inverse of sheng_mdss_panel_power_and_reset(), so Linux's
	 * nt36532e_prepare() finds a genuinely unpowered panel and re-runs
	 * its own init instead of assuming one already on. */
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, false); /* physical LOW = asserted */
	sheng_gpio_set(TLMM_PANEL_AVEE_GPIO, false);
	sheng_gpio_set(TLMM_PANEL_AVDD_GPIO, false);
}

/* Framebuffer description produced by the Zig bring-up. Nothing in Zig
 * touches a U-Boot struct, so a U-Boot bump cannot silently change a
 * layout underneath it. */
struct sheng_fb {
	unsigned long base;
	unsigned long size;
	unsigned int xsize;
	unsigned int ysize;
	unsigned int stride;
	int inherited;
};

extern int sheng_abl_splash_live;
extern int sheng_mdss_bringup(int splash_live, struct sheng_fb *fb);

static int sheng_mdss_probe(struct udevice *dev)
{
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);
	struct video_priv *uc_priv = dev_get_uclass_priv(dev);
	struct sheng_fb fb;
	phys_addr_t addr;
	int ret;

	/* Only to confirm the node exists; the base itself is a constant. */
	if (dev_read_addr(dev) == FDT_ADDR_T_NONE)
		return -EINVAL;

	ret = sheng_mdss_bringup(sheng_abl_splash_live, &fb);
	if (ret)
		return ret;

	plat->base = fb.base;
	plat->size = fb.size;
	uc_priv->xsize = fb.xsize;
	uc_priv->ysize = fb.ysize;
	uc_priv->line_length = fb.stride;
	uc_priv->bpix = VIDEO_BPP32;
	uc_priv->format = VIDEO_X8R8G8B8;
	uc_priv->rot = 0;
	sheng_inherited = fb.inherited;

	/* Keep U-Boot's allocator off the scanout buffer: board_late_init()
	 * runs nine lmb_alloc() calls after this.
	 *
	 * -EEXIST is the expected outcome on the inherited path: the
	 * splash_region node already covers the range, so lmb refuses to
	 * hand it out again. Only a different error means the buffer is
	 * genuinely unprotected. */
	addr = fb.base;
	ret = lmb_alloc_mem(LMB_MEM_ALLOC_ADDR, 0, &addr, fb.size, LMB_NONE);
	if (ret && ret != -EEXIST)
		log_warning("sheng_mdss: framebuffer not reserved (%d)\n", ret);

	/* Console writes go through the CPU cache; the DPU fetches DRAM. */
	video_set_flush_dcache(dev, true);

	return 0;
}

static const struct udevice_id sheng_mdss_ids[] = {
	{ .compatible = "qcom,sm8550-mdss" },
	{ }
};

/* No .bind: a .bind hook hangs this board, even one doing nothing but a
 * single struct write. The framebuffer is allocated in .probe instead.
 *
 * No .video_sync either. video_flush_dcache() already covers
 * priv->fb..fb_size; a driver op that flushed the whole 24MB was
 * redundant and blanked the panel during the boot menu's once-a-second
 * countdown redraw. */

U_BOOT_DRIVER(sheng_mdss) = {
	.name		= "sheng_mdss",
	.id		= UCLASS_VIDEO,
	.of_match	= sheng_mdss_ids,
	.probe		= sheng_mdss_probe,
	.priv_auto	= sizeof(struct sheng_mdss_priv),
};
