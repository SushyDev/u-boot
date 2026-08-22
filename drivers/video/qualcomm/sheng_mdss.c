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
extern unsigned int sheng_gcc_disp_hf_axi_enable(void);
extern int sheng_rsc_send_active_write(u32 resource_addr, u32 data);
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
static unsigned long sheng_tmark_us[SHENG_TMARK_MAX];
static const char *sheng_tmark_name[SHENG_TMARK_MAX];
static unsigned int sheng_tmark_n;

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
extern long long sheng_mdss_dsi_read_power_mode_single(unsigned long dsi0_base,
						       unsigned long dma_scratch);
extern long long sheng_mdss_dsi_init_fail_info(void);

/* What the DDIC says it is doing, read by U-Boot at end of probe. */
static long long sheng_panel_pm;

/* Same read, taken BEFORE we sleep and power-cycle the panel -- i.e. the
 * state ABL actually handed over.
 *
 * THE HANDOVER QUESTION. ABL leaves the rails and backlight EN high but
 * the screen dark, and we have never asked the DDIC what it thinks is
 * going on at that moment:
 *
 *   0x9c -> ABL left it fully initialised and merely stopped feeding it.
 *           We could inherit: skip the power-cycle AND the 94-command
 *           init, program the DPU, display-on, raise brightness. That is
 *           ~700ms of our ~1.2s black gap, and it is what the Android
 *           kernel's continuous-splash path does.
 *   0x08 -> ABL slept the panel; a real init is required and ~1.2s is
 *           close to a floor.
 *
 * Safe to read here even though the MDSS core reset has already run: the
 * DDIC is a separate chip and keeps its state as long as its rails stay
 * up, which they do until the power-cycle below.
 */
static long long sheng_panel_pm_pre;

/* Did we take the skip-our-own-teardown path? See its comment in probe. */
static int sheng_fastpath;

/* Whether ABL handed the panel over in the known-quiet 0x08 state. Drives
 * both the fast path and the discharge length -- kept separate because
 * the fast path may later be disabled independently while the discharge
 * still needs to know what state we started from. */
static int sheng_fastpath_state_ok;

#define SHENG_DIAG_N 9
static u32 sheng_diag[SHENG_DIAG_N];
static int sheng_panel_init_ret;

/* THE PROBE CAN RUN TWICE, and that is the intermittent-glitch bug.
 *
 * qcom_late_init() force-probes the video device with
 * uclass_get_device(). stdio_add_devices() already probed it at initcall
 * 729. Normally DM returns the cached, activated device and the second
 * call is free -- but if probe #1 FAILED, the device was never
 * activated, so that call runs the ENTIRE probe again: second GDSC
 * collapse, second MDSS core reset, second panel power-cycle, second
 * 94-command init, on a DDIC left mid-bring-up by the first attempt.
 *
 * The retry then overwrites all 11 stage codes with 0 and panel_init
 * with its own success, which is why every existing instrument reported
 * a clean boot -- including soak.sh, which called 6/6 boots good while
 * the panel was visibly corrupt.
 *
 * Keep the FIRST attempt's result separately; it is the one that says
 * why the panel is broken.
 */
/* Did we inherit ABL's live display instead of rebuilding it? Drives the
 * handover to Linux in board_preboot_os(). */
int sheng_inherited;

/* Decided in qcom_board_init() over I2C -- see its comment. */
extern int sheng_abl_splash_live;

static unsigned int sheng_probe_count;
static int sheng_panel_init_ret_first = 0x7fffffff;

int sheng_mdss_diag_fmt(char *buf, int len)
{
	return snprintf(buf, len,
			"fastpath=%d probes=%u panel_init_first=%d panel_init=%d"
			" gdsc[%012llx] collapse_us=%d"
			" status0=%08x fifo=%08x fifo_late=%08x lane=%08x"
			" ackerr=%08x timeout=%08x pll_l=%08x"
			" frames=%u->%u pm=%012llx pm_val=%02x"
			" pm_pre=%012llx pm_pre_val=%02x"
			" dsi[retries=%u failidx=%d failrc=%d]",
			sheng_fastpath, sheng_probe_count, sheng_panel_init_ret_first,
			sheng_panel_init_ret,
			(unsigned long long)sheng_mdss_gdsc_probe_result(),
			(int)sheng_mdss_gdsc_collapse_us(),
			sheng_diag[0], sheng_diag[1], sheng_diag[8],
			sheng_diag[2], sheng_diag[3], sheng_diag[4],
			sheng_diag[5], sheng_diag[6], sheng_diag[7],
			(unsigned long long)sheng_panel_pm,
			(unsigned int)(sheng_panel_pm & 0xff),
			(unsigned long long)sheng_panel_pm_pre,
			(unsigned int)(sheng_panel_pm_pre & 0xff),
			(unsigned int)(sheng_mdss_dsi_init_fail_info() >> 32),
			(int)(short)((sheng_mdss_dsi_init_fail_info() >> 16) & 0xffff),
			(int)(short)(sheng_mdss_dsi_init_fail_info() & 0xffff)) + 1;
}

static void sheng_tmark(const char *name)
{
	if (sheng_tmark_n >= SHENG_TMARK_MAX)
		return;

	sheng_tmark_name[sheng_tmark_n] = name;
	sheng_tmark_us[sheng_tmark_n] = timer_get_us();
	sheng_tmark_n++;
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
	unsigned int i;
	int n = 0;

	if (!sheng_tmark_n)
		return 0;

	n += snprintf(buf + n, len - n, "entry=%lums", sheng_tmark_us[0] / 1000);

	for (i = 1; i < sheng_tmark_n && n < len; i++)
		n += snprintf(buf + n, len - n, " %s=%lums", sheng_tmark_name[i],
			      (sheng_tmark_us[i] - sheng_tmark_us[i - 1]) / 1000);

	if (n < len)
		n += snprintf(buf + n, len - n, " total=%lums",
			      (sheng_tmark_us[sheng_tmark_n - 1] -
			       sheng_tmark_us[0]) / 1000);

	return (n < len ? n : len - 1) + 1;
}

static void sheng_tmark_report(void)
{
	unsigned int i;

	printf("sheng: probe entered at %lu ms since power-on\n",
	       sheng_tmark_us[0] / 1000);

	for (i = 1; i < sheng_tmark_n; i++)
		printf("sheng:  %-18s %6lu ms\n", sheng_tmark_name[i],
		       (sheng_tmark_us[i] - sheng_tmark_us[i - 1]) / 1000);

	printf("sheng: probe total %lu ms, done at %lu ms\n",
	       (sheng_tmark_us[sheng_tmark_n - 1] - sheng_tmark_us[0]) / 1000,
	       sheng_tmark_us[sheng_tmark_n - 1] / 1000);
}

/* Panel bias: KTZ8866 over I2C plus GPIOs 30/31. The DDIC needs it
 * before any DCS command. Without it commands go nowhere and the host
 * still reports success -- a plain DCS write needs no ACK, so an
 * unpowered panel looks identical to a live one from the host side. */

extern int sheng_ktz8866_set_bias(int enable);

static void sheng_mdss_panel_power_and_reset(void)
{
	sheng_ktz8866_set_bias(1);
	sheng_gpio_set(TLMM_PANEL_AVDD_GPIO, true);
	sheng_gpio_set(TLMM_PANEL_AVEE_GPIO, true);
	mdelay(1); /* regulator-enable-ramp-delay is 233us on both */

	SHENG_DBG_PIN("avdd", TLMM_PANEL_AVDD_GPIO);
	SHENG_DBG_PIN("avee", TLMM_PANEL_AVEE_GPIO);

	/* nt36532e_reset(). The reset line is active-low, so a logical
	 * assert is physical LOW. Delays are the panel driver's. */
	/* The vendor DT says <0 10, 1 3, 0 3, 1 15> (level, ms) --
	 * qcom,mdss-dsi-reset-sequence, see VENDOR-PANEL-REFERENCE.md.
	 * These are 1ms longer at each step, which is harmless and has
	 * always worked; left alone rather than churn the panel path,
	 * which has a known intermittent init. */
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, false);
	SHENG_DBG_PIN("rst assert1", TLMM_PANEL_RESET_GPIO);
	mdelay(11);
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, true);
	SHENG_DBG_PIN("rst deassert1", TLMM_PANEL_RESET_GPIO);
	mdelay(4);
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, false);
	SHENG_DBG_PIN("rst assert2", TLMM_PANEL_RESET_GPIO);
	mdelay(4);
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, true);
	SHENG_DBG_PIN("rst deassert2", TLMM_PANEL_RESET_GPIO);
	mdelay(16);
}

/* cmd-db lookup, then the vote itself in Zig. cmd_db_read_addr() is a
 * U-Boot API, which is the only reason these two wrappers are C. */
static int sheng_mdss_bcm_vote(const char *bcm_name)
{
	u32 addr = cmd_db_read_addr(bcm_name);

	SHENG_DBG_LOG(SHENG_LOG_CMDDB_MM0_ADDR, addr);
	if (!addr)
		return -ENODEV;

	return sheng_bcm_vote(addr);
}

/* These rails are the DSI PHY's analog supply (vdds) and the panel's
 * vddio. Nothing in the DTS marks them boot-on or always-on, so ABL is
 * not guaranteed to leave them up. A PHY running without its analog
 * supply still reports PLL lock and REFGEN ready while the HS pads
 * never swing to valid levels: frames stream, no pixels, no fault. */
static int sheng_mdss_regulator_vote(const char *rsc_name, u32 millivolts)
{
	u32 addr = cmd_db_read_addr(rsc_name);

	if (!addr)
		return -ENODEV;

	return sheng_regulator_vote(addr, millivolts);
}

/* 144Hz mode, nt36532e. Matches the DPU crtc-0 modeline and the panel
 * driver's own mode table. */
#define SHENG_PANEL_HFRONT_PORCH	142
#define SHENG_PANEL_HSYNC_WIDTH		4
#define SHENG_PANEL_HBACK_PORCH		92
#define SHENG_PANEL_VFRONT_PORCH	26
#define SHENG_PANEL_VSYNC_WIDTH		2
#define SHENG_PANEL_VBACK_PORCH		138

/* sheng_mdss_hw.zig */
extern void sheng_mdss_core_reset(unsigned long dispcc_base);
extern int sheng_mdss_gdsc_enable(unsigned long dispcc_base);
extern void sheng_mdss_gdsc_disable(unsigned long dispcc_base);
extern void sheng_mdss_ubwc_init(unsigned long mdss_base);
extern unsigned int sheng_mdss_wrapper_audit(unsigned long mdss_base);
extern int sheng_mdss_dispcc_init(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_dsi_clks_init(unsigned long dispcc_base);
extern int sheng_mdss_dsi_phy_init(unsigned long dsi_phy_base, bool is_master);
extern int sheng_mdss_dsi_phy_start_dual(unsigned long phy0_base, unsigned long phy1_base);
extern void sheng_mdss_dsi_reset_both_phys(unsigned long dsi0_base, unsigned long dsi1_base);
extern void sheng_mdss_dsi_host_video_prepare(unsigned long dsi0_base,
					     unsigned long dsi1_base);
extern int sheng_mdss_dsi_panel_init(unsigned long dsi0_base, unsigned long dsi1_base,
				      unsigned long dma_scratch, bool enable_dsc);
extern unsigned int sheng_mdss_dsi_status0_before_first_cmd(void);
extern long long sheng_mdss_dsi_timeout_diag(void);
extern long long sheng_mdss_dsi_snapshot_1(void);
extern long long sheng_mdss_dsi_snapshot_2(void);
extern long long sheng_mdss_dsi_snapshot_3(void);
extern long long sheng_mdss_dsi_snapshot_4(void);
extern unsigned int sheng_mdss_smmu_diag1(void);
extern long long sheng_mdss_smmu_diag2(void);
extern unsigned int sheng_mdss_smmu_diag3(void);
extern unsigned int sheng_mdss_smmu_sctlr(void);
extern long long sheng_mdss_iova_diag1(void);
extern long long sheng_mdss_iova_diag2(void);
extern long long sheng_mdss_dmabuf_diag(void);
extern long long sheng_mdss_smmu_fault_diag(void);
extern long long sheng_mdss_smmu_fault_addr(void);
extern void sheng_mdss_dsi_tpg_enable(unsigned long dsi0_base,
				     unsigned long dsi1_base);
extern unsigned int sheng_mdss_dsi_retry_count(void);
extern unsigned int sheng_mdss_dsi_trigger_probe(void);
extern long long sheng_mdss_dsi_audit(unsigned long dsi0_base);
extern long long sheng_mdss_dsi1_audit(unsigned long dsi1_base);
extern long long sheng_mdss_verify_pipeline(unsigned long dpu_base,
					    unsigned long dsi0_base);
extern long long sheng_mdss_dsc_status1(unsigned long dpu_base);
extern long long sheng_mdss_dsc_status2(unsigned long dpu_base);
extern long long sheng_mdss_dpu_readback1(unsigned long dpu_base);
extern long long sheng_mdss_phy_audit(unsigned long phy_base, bool is_master);
extern void sheng_mdss_smmu_setup(void);

/* ULTRA-DEBUG BLACKBOX -- see the big comment in sheng_mdss_hw.zig.
 *
 * U-Boot appends an ASCII log to DRAM at 0xa5000000; Linux reads it back
 * through /dev/mem. This exists because CONFIG_SYS_CBSIZE caps
 * /proc/cmdline at 512 bytes, which has meant one question per boot and
 * register sweeps reported as "first mismatch + count" with the actual
 * values never visible. Budget here is ~512KB instead. */
/* Blackbox decls/macros MOVED UP -- see above the panel power/reset
 * helper, which now logs GPIO readbacks and needs them in scope. */

extern long long sheng_mdss_dispcc_audit(unsigned long dispcc_base);
extern long long sheng_mdss_phy_state(unsigned long phy0_base, unsigned long phy1_base);
extern long long sheng_mdss_phy_cmn_sweep(unsigned long phy_base);
extern long long sheng_mdss_phy1_cmn_sweep(unsigned long phy_base);
extern long long sheng_mdss_phy1_lane_sweep(unsigned long phy_base);
extern long long sheng_mdss_phy_status_raw(unsigned long phy0_base, unsigned long phy1_base);
extern long long sheng_mdss_dsi_txpath_state(unsigned long dsi0_base);
extern long long sheng_mdss_dsi_lane_activity(unsigned long dsi_base);
extern void sheng_mdss_phy144_mark(unsigned int slot, unsigned long phy_base);
extern long long sheng_mdss_phy144_marks(void);
extern long long sheng_mdss_phy_lanepll_sweep(unsigned long phy_base);
extern long long sheng_mdss_dsi_sweep(unsigned long dsi_base);
extern long long sheng_mdss_vbif_audit(unsigned long vbif_base);
extern int sheng_mdss_dispcc_ahb_only(unsigned long dispcc_base);
extern long long sheng_mdss_abl_state1(unsigned long dsi0_base);
extern long long sheng_mdss_abl_state2(unsigned long dsi0_base, unsigned long dsi1_base);
extern long long sheng_mdss_abl_state3(unsigned long phy0_base, unsigned long phy1_base);
extern long long sheng_mdss_lane_status(unsigned long dsi0_base, unsigned long dsi1_base);
extern long long sheng_mdss_phy_err_both(unsigned long dsi0_base, unsigned long dsi1_base);
extern long long sheng_mdss_dsi_video_readback1(unsigned long dsi0_base);
extern long long sheng_mdss_dsi_video_readback2(unsigned long dsi0_base,
						unsigned long dsi1_base);
extern long long sheng_mdss_dpu_readback2(unsigned long dpu_base);
extern long long sheng_mdss_dpu_readback3(unsigned long dpu_base);
extern long long sheng_mdss_dpu_readback4(unsigned long dpu_base);
extern void sheng_mdss_dsi_trig_ctrl_restore(unsigned long dsi0_base,
					     unsigned long dsi1_base);
extern int sheng_mdss_dpu_start(unsigned long dpu_base,
				 unsigned long dsi0_base, unsigned long dsi1_base,
				 unsigned long fb_addr,
				 u32 hactive, u32 vactive,
				 u32 hfront_porch, u32 hback_porch, u32 hsync_width,
				 u32 vfront_porch, u32 vback_porch, u32 vsync_width,
				 bool enable_dsc);
extern void sheng_mdss_dpu_stop(unsigned long dpu_base);
extern void sheng_mdss_dsi_panel_sleep(unsigned long dsi0_base, unsigned long dsi1_base,
					unsigned long dma_scratch);
extern void sheng_mdss_dsi_phys_off(unsigned long dsi0_phy_base,
				    unsigned long dsi1_phy_base);
extern void sheng_mdss_gdsc_probe(unsigned long dispcc_base, unsigned int slot);
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

static int sheng_mdss_probe(struct udevice *dev)
{
	struct sheng_mdss_priv *priv = dev_get_priv(dev);
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);
	struct video_priv *uc_priv = dev_get_uclass_priv(dev);
	unsigned int axi_cbcr;
	int bias_ret;
	int ret;

	/* Sample ABL's handoff state before the cold start below destroys
	 * it. ABL uses continuous splash, so it hands over with DPU, DSI,
	 * PHY and panel all running.
	 *
	 * Order matters. MDSS register reads are only safe once MDSS_GDSC is
	 * powered and the DISPCC AHB clock runs; reading at the top of probe
	 * wedges the CPU with no backlight and no boot. Enable exactly those
	 * two and nothing else -- in particular not dispcc_init(), whose
	 * core reset would wipe the state being sampled.
	 *
	 * GDSC enable is idempotent, and dispcc_ahb_only() parents AHB from
	 * XO, so neither disturbs ABL's DSI/PHY configuration. */
	ret = sheng_mdss_gdsc_enable(SM8550_DISPCC_BASE);
	BBS("abl_gdsc_enable_ret", ret);
	SHENG_DBG_ENV("sheng_mdss_abl_gdsc", (unsigned long)ret);
	if (!ret) {
		ret = sheng_mdss_dispcc_ahb_only(SM8550_DISPCC_BASE);
		if (!ret) {
			SHENG_DBG_ENV("sheng_mdss_abl1",
				    (unsigned long)sheng_mdss_abl_state1(
					    SM8550_MDSS_DSI0_BASE));
			SHENG_DBG_ENV("sheng_mdss_abl2",
				    (unsigned long)sheng_mdss_abl_state2(
					    SM8550_MDSS_DSI0_BASE,
					    SM8550_MDSS_DSI1_BASE));
			SHENG_DBG_ENV("sheng_mdss_abl3",
				    (unsigned long)sheng_mdss_abl_state3(
					    SM8550_MDSS_DSI0_PHY_BASE,
					    SM8550_MDSS_DSI1_PHY_BASE));

			/* CONTINUOUS-SPLASH INHERIT.
			 *
			 * With /reserved-memory/splash_region advertised, ABL
			 * stops blanking ~2s before handover and hands over a
			 * LIVE, STREAMING display. Do not rebuild it: draw
			 * into the buffer it is already scanning and touch
			 * nothing else. That removes the entire black gap
			 * between the Xiaomi logo and U-Boot's first pixels,
			 * and it avoids the failure that made every rebuild
			 * attempt fail -- the teardown below kills a live
			 * stream mid-frame and wedges the DDIC beyond
			 * recovery.
			 *
			 * NO MDSS REGISTER MAY BE READ TO DECIDE THIS.
			 *
			 * Every block that could report "am I streaming?"
			 * needs clocks that only run WHEN IT IS STREAMING, so
			 * such a probe answers correctly in the live case and
			 * WEDGES THE AHB BUS in the case it exists to detect
			 * -- no backlight, no boot, fastboot recovery. Three
			 * of them: DPU INTF/SSPP (b386), the same behind a
			 * clock-status gate (b387), and DSI0 CLK_STATUS
			 * (b392), which is no safer for being a DSI register.
			 *
			 * Liveness comes from sheng_abl_splash_live instead,
			 * decided in qcom_board_init() from a KTZ8866 register
			 * over I2C -- independent of MDSS and always readable.
			 * See its comment there for why 0x9f/0x98, and why the
			 * test is deliberately conservative.
			 *
			 * The buffer geometry is known rather than probed:
			 *   0xb8000000  = splash_region's base, the address
			 *                 ABL was measured scanning from
			 *                 (VIG0 SRC0_ADDR, b383)
			 *   12192       = VIG0 YSTRIDE0, a TIGHT 3048*4.
			 *                 NOT this driver's own 12288
			 *                 (ALIGN(3048,32)*4) -- using that
			 *                 would shear every line.
			 */
			if (sheng_abl_splash_live) {
				plat->base = SHENG_ABL_FB_ADDR;
				plat->size = SHENG_ABL_FB_STRIDE * SHENG_PANEL_VACTIVE;
				uc_priv->xsize = SHENG_PANEL_HACTIVE;
				uc_priv->ysize = SHENG_PANEL_VACTIVE;
				uc_priv->bpix = VIDEO_BPP32;
				uc_priv->format = VIDEO_X8R8G8B8;
				uc_priv->rot = 0;
				uc_priv->line_length = SHENG_ABL_FB_STRIDE;

				/* Console writes go through the CPU cache while
				 * the DPU fetches DRAM, exactly as for our own
				 * framebuffer. */
				video_set_flush_dcache(dev, true);

				/* Keep U-Boot's allocator off the live scanout
				 * buffer: board_late_init() runs nine
				 * lmb_alloc() calls after this.
				 *
				 * -EEXIST is the EXPECTED, GOOD outcome: the
				 * splash_region reserved-memory node already
				 * covers this range, so lmb refuses to hand it
				 * out again -- which is precisely what we
				 * wanted. It was being reported as
				 * "ABL fb not reserved (-17)", i.e. success
				 * printed as a warning. Only a different error
				 * means the buffer is genuinely unprotected. */
				{
					phys_addr_t a = SHENG_ABL_FB_ADDR;
					int lret = lmb_alloc_mem(LMB_MEM_ALLOC_ADDR, 0, &a,
								 plat->size, LMB_NONE);
					if (lret && lret != -EEXIST)
						log_warning("sheng_mdss: ABL fb not reserved (%d)\n",
							    lret);
				}

				sheng_inherited = 1;
				SHENG_DBG_STAGE(SHENG_MDSS_STATUS_PROBE, 0);
				return 0;
			}
		}
	}

	/* Stop the controller, not just its power domain.
	 *
	 * Bringing this hardware up on top of a live controller does not
	 * work; starting from a real power-down does. Linux shows the same
	 * thing one level up -- its first bring-up over a still-running
	 * controller fails, and the same code succeeds after a full disable.
	 *
	 * Collapsing the GDSC and pulsing the core reset is not equivalent:
	 * it never stops the DPU timing engines, powers down the PHYs or
	 * gates the DISPCC branches. Run the teardown here, while GDSC and
	 * AHB are still up so the registers are reachable.
	 *
	 * The panel stays powered; the graceful restart further down owns
	 * the panel-side half. */
	if (!ret)
		sheng_mdss_dsi_phys_off(SM8550_MDSS_DSI0_PHY_BASE,
					 SM8550_MDSS_DSI1_PHY_BASE);

	/* Panel GPIOs as ABL left them. TLMM is always clocked, so these
	 * reads are safe this early -- MDSS registers are not. */
	SHENG_DBG_PIN("abl rst", TLMM_PANEL_RESET_GPIO);
	SHENG_DBG_PIN("abl avdd", TLMM_PANEL_AVDD_GPIO);
	SHENG_DBG_PIN("abl avee", TLMM_PANEL_AVEE_GPIO);

	sheng_mdss_stage_init();
	sheng_probe_count++;
	sheng_tmark("entry");

	priv->mdss_base = dev_read_addr(dev);
	SHENG_DBG_START();
	BBM("probe entry");
	BBV("mdss_base", priv->mdss_base);
	if (priv->mdss_base == FDT_ADDR_T_NONE)
		return -EINVAL;

	/* Cold-start the controller: collapse the GDSC, settle, pulse the
	 * MDSS core reset, then bring the GDSC back. ABL almost certainly
	 * used this same DPU/DSI hardware for its splash, so the digital
	 * logic must start from power-on defaults rather than from whatever
	 * it left mid-configured. */
	sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 0);
	sheng_mdss_gdsc_disable(SM8550_DISPCC_BASE);
	BBM("gdsc collapsed");
	sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 1);
	mdelay(1);

	/* DISP_CC_MDSS_CORE_BCR. msm_mdss_init() pulses this first, before
	 * the GDSC or any clock is parsed. It resets the whole MDSS wrapper;
	 * each host's own DSI_RESET only covers that host. */
	sheng_mdss_core_reset(SM8550_DISPCC_BASE);
	BBM("mdss core reset pulsed");
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_MDSS_RESET, 0);

	ret = sheng_mdss_gdsc_enable(SM8550_DISPCC_BASE);
	sheng_mdss_phy144_mark(0, SM8550_MDSS_DSI0_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_GDSC, ret);
	if (ret) {
		log_debug("sheng_mdss: GDSC bring-up failed (%d)\n", ret);
		return ret;
	}

	/* The DPU's path to DRAM runs qnm_mdp -> qns_mem_noc_hf -> ... ->
	 * ebi. Every BCM on it has a keepalive floor except MM0, which
	 * covers qns_mem_noc_hf exactly. Without this vote mmss_noc keeps
	 * the AXI gate for MASTER_MDP closed. */
	ret = sheng_mdss_bcm_vote("MM0");
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_BCM_MM0, ret);
	SHENG_DBG_ENV("sheng_mdss_bcm_mm0", (unsigned long)ret);

	/* GCC_DISP_HF_AXI_CLK must be on before any DSI command DMA: it is
	 * the AXI path the engine fetches packets over. Gated, the engine
	 * latches CMD_MODE_DMA_BUSY forever, having never fetched a byte and
	 * never errored. Linux enables it in the same clk_bulk as AHB and
	 * MDP, before any child DSI device runs. */
	/* Keep the call OUT of the macro: with debug off the macro discards
	 * its arguments and the clock would never be enabled. */
	axi_cbcr = sheng_gcc_disp_hf_axi_enable();
	SHENG_DBG_LOG(SHENG_LOG_GCC_HF_AXI_READBACK, axi_cbcr);
	sheng_tmark("gdsc+reset");

	ret = sheng_mdss_dispcc_init(SM8550_DISPCC_BASE);
	BBS("dispcc_init_ret", ret);
	BBB("DISPCC after init", SM8550_DISPCC_BASE, 0x000, 64);
	sheng_mdss_phy144_mark(1, SM8550_MDSS_DSI0_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DISPCC, ret);
	/* UBWC block config, immediately after the MDSS core reset inside
	 * dispcc_init() wipes it -- see sheng_mdss_ubwc_init()'s comment.
	 * Must precede any DSI/DPU programming, matching msm_mdss_enable(). */
	sheng_mdss_ubwc_init(SM8550_MDSS_BASE);
	sheng_tmark("dispcc+ubwc");
	SHENG_DBG_ENV("sheng_mdss_dispcc", (unsigned long)ret);
	if (ret)
		return ret;

	/* dispcc_init() only proves the CBCR halt-poll passed, not that the
	 * RCG CFG landed. Expect src_sel=1 (PLL0_OUT_MAIN, bits [10:8]) and
	 * src_div=5 (2*3-1 for /3, bits [4:0]) for 514MHz. */
	SHENG_DBG_LOG(SHENG_LOG_MDP_RCG_CFG_READBACK,
		      readl((void __iomem *)(uintptr_t)
			    (SM8550_DISPCC_BASE + MDP_CLK_SRC_CFG_RCGR)));

	/* Real analog supply rails for the DSI PHYs/hosts/panel logic --
	 * see sheng_mdss_regulator_vote()'s comment. Both DSI PHYs share
	 * vreg_l1e_0p88 (0.88V), both DSI hosts share vreg_l3e_1p2 (1.2V),
	 * and the panel's own vddio is vreg_s3g_0p7 -- live-confirmed on a
	 * working Linux boot at 880000uV/1200000uV/600000uV respectively.
	 * Voted here, before anything that depends on them, since none of
	 * these three has regulator-boot-on/always-on in the DTS. */
	/* cmd-db names rails "ldo<pmic><index>" / "smp<pmic><index>", not
	 * by the DTS label. vreg_l1e_0p88 is ldoe1, vreg_l3e_1p2 is ldoe3,
	 * vreg_s3g_0p7 is smpg3. */
	ret = sheng_mdss_regulator_vote("ldoe1", 880);
	SHENG_DBG_ENV("sheng_mdss_vreg_l1e", (unsigned long)ret);
	ret = sheng_mdss_regulator_vote("ldoe3", 1200);
	SHENG_DBG_ENV("sheng_mdss_vreg_l3e", (unsigned long)ret);
	ret = sheng_mdss_regulator_vote("smpg3", 600);
	BBS("regulator_votes_ret", ret);
	sheng_mdss_phy144_mark(2, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_tmark("regulators");
	SHENG_DBG_ENV("sheng_mdss_vreg_s3g", (unsigned long)ret);

	/* Dual-DSI split-link panel: DSI0 is master (drives its own PLL),
	 * DSI1 is slave (sources its bit clock from DSI0 over
	 * qcom,sync-dual-dsi) -- see sheng_mdss_dsi_phy_init()'s comment
	 * in sheng_mdss_hw.zig. Both must succeed. */
	sheng_mdss_dsi_reset_both_phys(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);
	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI0_PHY_BASE, true);
	BBS("phy0_init_ret", ret);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DSI0_PHY, ret);
	SHENG_DBG_ENV("sheng_mdss_dsi0_phy", (unsigned long)ret);
	if (ret)
		return ret;

	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI1_PHY_BASE, false);
	BBS("phy1_init_ret", ret);
	sheng_mdss_phy144_mark(3, SM8550_MDSS_DSI0_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DSI1_PHY, ret);
	SHENG_DBG_ENV("sheng_mdss_dsi1_phy", (unsigned long)ret);
	if (ret)
		return ret;

	/* PLL start + digital-reset/global-clk/RBUF, INTERLEAVED across both
	 * PHYs -- see sheng_mdss_dsi_phy_start_dual()'s comment. The kernel's
	 * dsi_pll_7nm_vco_prepare() biases the slave BEFORE starting the
	 * master's PLL and resets the slave in the same window as the master,
	 * rather than finishing one PHY then the other. Measured via a
	 * writel() hook in dsi_phy_7nm.c. */
	ret = sheng_mdss_dsi_phy_start_dual(SM8550_MDSS_DSI0_PHY_BASE,
					     SM8550_MDSS_DSI1_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DSI_PHY_START, ret);
	SHENG_DBG_ENV("sheng_mdss_phy_start", (unsigned long)ret);
	BBS("phy_start_dual_ret", ret);
	BBR("PHY0 STATUS", SM8550_MDSS_DSI0_PHY_BASE, 0x140);
	BBR("PHY1 STATUS", SM8550_MDSS_DSI1_PHY_BASE, 0x140);
	sheng_mdss_phy144_mark(4, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_tmark("dsi phys");
	if (ret)
		return ret;

	/* byte/pclk/esc for both links. pclk drives INTF_FRAME_COUNT, not
	 * MDP_CLK -- without these the frame counters stay frozen at 0 no
	 * matter what MDP_CLK does. Must follow the PHY PLL lock above:
	 * these mux from the PHY PLL, not DISPCC's PLL0. */
	ret = sheng_mdss_dispcc_dsi_clks_init(SM8550_DISPCC_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DSI_LINK_CLKS, ret);
	sheng_mdss_phy144_mark(5, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_tmark("link clks");
	SHENG_DBG_ENV("sheng_mdss_dsi_clks", (unsigned long)ret);
	if (ret)
		return ret;

	/* Bring the hosts up in video mode before touching the panel. The
	 * kernel resets the panel onto an already-streaming link, and the
	 * DSC encoder regresses if the reset comes first.
	 *
	 * The DCS init that follows runs over a link in video mode carrying
	 * no active pixels -- the INTF timing engine starts later, in
	 * dpu_start(). Commands interleave into what is effectively 100%
	 * blanking, which is what the kernel does too. */
	sheng_mdss_dsi_host_video_prepare(SM8550_MDSS_DSI0_BASE,
					  SM8550_MDSS_DSI1_BASE);

	/* ABL hands over a live, configured panel. Shut it down gracefully --
	 * Display Off, Sleep In -- before cutting power, then power-cycle it.
	 * A DDIC that loses power without Sleep In can latch a state that a
	 * later reset does not clear. */
	sheng_mdss_smmu_setup();

	/* Ask the DDIC what ABL left it in, BEFORE we sleep or power-cycle
	 * it. Placed after host_video_prepare (we need a working DSI to
	 * ask) but before panel_sleep, so it reports ABL's state, not
	 * ours. See sheng_panel_pm_pre. */
	sheng_panel_pm_pre = sheng_mdss_dsi_read_power_mode_single(
				SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH);

	/* FAST PATH: ABL already slept the panel for us.
	 *
	 * Measured (b367): ABL hands the DDIC over reading 0x08 -- sleep-in,
	 * display-off. It does not merely stop feeding a live panel, it
	 * sends Display Off + Sleep In itself. So our own Display Off +
	 * Sleep In (87ms) is re-sleeping an already-slept panel, and the
	 * rail power-cycle (248ms) exists to recover a DDIC in an UNKNOWN
	 * state -- which this demonstrably is not.
	 *
	 * A cleanly-slept DDIC plus the reset pulse below should accept a
	 * fresh init without ever losing power. Worth ~335ms of the ~1.2s
	 * black gap between the Xiaomi logo and U-Boot's first pixels.
	 *
	 * Guarded on BOTH the payload being exactly 0x08 AND the read being
	 * trustworthy (CTRL 0x01f7 = CMD_MODE_EN asserted, BTA genuinely
	 * issued). A null or untrustworthy read falls through to the proven
	 * full power-cycle -- never skip work on the strength of a
	 * measurement that might not have happened.
	 */
	sheng_fastpath_state_ok = ((sheng_panel_pm_pre & 0xff) == 0x08) &&
				  (((sheng_panel_pm_pre >> 16) & 0xffff) == 0x01f7);
	sheng_fastpath = sheng_fastpath_state_ok;

	if (!sheng_fastpath) {
	sheng_mdss_dsi_panel_sleep(SM8550_MDSS_DSI0_BASE,
				    SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_DSI_DMA_SCRATCH);
	sheng_tmark("host+abl sleep");

	/* Power-cycle in teardown order: reset, then avee, then avdd. */
	sheng_gpio_set(TLMM_PANEL_RESET_GPIO, false);
	sheng_gpio_set(TLMM_PANEL_AVEE_GPIO, false);
	sheng_gpio_set(TLMM_PANEL_AVDD_GPIO, false);
	/* GPIOs gate the rails, they do not create them. LCD_BIAS_CFG1 is
	 * latched over I2C -- clear it or the rails never collapse.
	 *
	 * Load-bearing, so the call stays out of the macro: with debug off
	 * the macro discards its arguments. */
	bias_ret = sheng_ktz8866_set_bias(0);
	BBS("bias OFF over i2c", bias_ret);

	/* The rails need an off window long enough to discharge, or the DDIC
	 * keeps its state across the power cycle. Sampled twice on the way:
	 * both must read 0.
	 *
	 * BIGGEST BOOT-TIME KNOB IN THE DRIVER, and the one most worth
	 * distrusting. The old 1080ms total was tuned in the era when
	 * LCD_BIAS_EN was still latched over I2C, so the rails never
	 * collapsed at all and NO window would have worked -- "shorter than
	 * ~1s fails" was measuring the latch, not a discharge time. Now that
	 * sheng_ktz8866_set_bias(0) genuinely drops them, what is left is an
	 * actual RC discharge, which is far shorter.
	 *
	 * 200ms is a guess with margin, not a measurement. Soak it
	 * (soak.sh) before trusting it, and if panel init goes intermittent
	 * raise this before touching either pacing knob. */
	{
		/* ADAPTIVE, because the right value depends on what ABL
		 * handed us:
		 *
		 *   0x08 (cleanly slept)  -> 200ms is proven good (b353-b374,
		 *        many boots). ABL sent Display Off + Sleep In itself,
		 *        so the DDIC is already in a known, quiet state.
		 *
		 *   anything else -> use the original 1080ms. Once
		 *        /reserved-memory/splash_region is advertised, ABL
		 *        hands over a LIVE, STREAMING panel instead (b375:
		 *        pm_pre_val=00, bias 0x9f, different GDSC state), and
		 *        200ms did NOT recover it -- no picture at all. A
		 *        panel killed mid-scan is the case the long window was
		 *        tuned for.
		 *
		 * Erring long on the unknown path costs boot time only when we
		 * cannot prove the panel was quiescent, which is the right way
		 * round.
		 */
		const unsigned int discharge_ms = sheng_fastpath_state_ok ? 200 : 1080;

		mdelay(20);
		SHENG_DBG_PIN("avdd during off", TLMM_PANEL_AVDD_GPIO);
		SHENG_DBG_PIN("avee during off", TLMM_PANEL_AVEE_GPIO);
		mdelay(60);
		SHENG_DBG_PIN("avdd late in off", TLMM_PANEL_AVDD_GPIO);
		SHENG_DBG_PIN("avee late in off", TLMM_PANEL_AVEE_GPIO);
		mdelay(discharge_ms - 80);
	}
	} /* !sheng_fastpath */

	/* Runs on BOTH paths. On the fast path the rails are already up, so
	 * the enables are idempotent and what matters is the reset pulse --
	 * a hardware reset of the DDIC's digital state, which is what
	 * actually prepares it for a fresh init. */
	sheng_mdss_panel_power_and_reset();
	sheng_tmark("panel pwr cycle");
	BBM("panel powered + reset pulsed");
	sheng_mdss_phy144_mark(6, SM8550_MDSS_DSI0_PHY_BASE);

	/* CLK_STATUS (0x11c) reports which clocks are physically active.
	 * Live while rendering: 0x00804343 -- bits 0,1 AHBM_HCLK, 6
	 * AON_BYTECLK, 8 AON_ESCCLK, 9 AON_PCLK, 14 VID_PCLK, with bit 16
	 * PLL_UNLOCKED clear.
	 *
	 * bit 8 matters most here. DCS commands go out in LP escape mode, so
	 * without the escape clock the DMA still shifts its buffer out and
	 * reports completion, raises no FIFO or PHY error, and nothing
	 * reaches the panel.
	 *
	 * Sampled before the first command and again at end of probe, so a
	 * clock that starts late is distinguishable from one that never
	 * runs. */
	SHENG_DBG_ENV("sheng_mdss_clkstat_pre",
		    (unsigned long)*(volatile u32 *)(uintptr_t)(SM8550_MDSS_DSI0_BASE + 0x11c));

	SHENG_DBG_ENV("sheng_mdss_preaud",
		    (unsigned long)sheng_mdss_dsi_audit(SM8550_MDSS_DSI0_BASE));
	SHENG_DBG_ENV("sheng_mdss_preaud1",
		    (unsigned long)sheng_mdss_dsi1_audit(SM8550_MDSS_DSI1_BASE));

	ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
					 SHENG_MDSS_DSI_DMA_SCRATCH, true);
	sheng_tmark("panel DCS init");
	sheng_panel_init_ret = ret;
	if (sheng_panel_init_ret_first == 0x7fffffff)
		sheng_panel_init_ret_first = ret;
	BBS("panel_init_ret", ret);
	BBR("DSI0 CTRL", SM8550_MDSS_DSI0_BASE, 0x000);
	BBR("DSI0 STATUS0", SM8550_MDSS_DSI0_BASE, 0x004);
	BBR("DSI0 FIFO", SM8550_MDSS_DSI0_BASE, 0x008);
	BBR("DSI0 LANE_STATUS", SM8550_MDSS_DSI0_BASE, 0x0a4);
	BBR("DSI0 ACK_ERR", SM8550_MDSS_DSI0_BASE, 0x068);
	BBR("DSI0 TIMEOUT", SM8550_MDSS_DSI0_BASE, 0x0bc);
	sheng_mdss_phy144_mark(7, SM8550_MDSS_DSI0_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DSI_PANEL, ret);
	SHENG_DBG_ENV("sheng_mdss_panel", (unsigned long)ret);
	SHENG_DBG_POST_PANEL_REPORT();
	if (ret)
		return ret;

	/* Panel init is done; the DPU is about to start streaming frames,
	 * so TRIG_CTRL's BLOCK_DMA_WITHIN_FRAME / TE interlock now has a
	 * live MDP to synchronise against. Put Linux's exact live value
	 * back. See TRIG_CTRL_CMD_INIT_VALUE in sheng_mdss_hw.zig for why
	 * panel init itself must NOT run with those bits set. */
	sheng_mdss_dsi_trig_ctrl_restore(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);

	/* Clear the framebuffer to solid black.
	 *
	 * Fill the STRIDE-ALIGNED region, not the tight one: SSPP fetches
	 * 3072 pixels per row, so the 24 pixels past column 3048 are read
	 * too and must be initialised memory.
	 *
	 * Black, not a pattern. video_clear() does not repaint this buffer,
	 * so the console draws straight on top of whatever is left here.
	 * Anything but a flat dark background makes the white-on-black text
	 * unreadable. */
	{
		volatile u32 *fb = (volatile u32 *)(uintptr_t)SHENG_MDSS_FB_ADDR;
		size_t fb_words = 3072 /* ALIGN(3048,32) */ * SHENG_PANEL_VACTIVE;
		size_t i;

		for (i = 0; i < fb_words; i++)
			fb[i] = 0xff000000u;

		flush_dcache_range(SHENG_MDSS_FB_ADDR,
				    SHENG_MDSS_FB_ADDR + fb_words * 4);
		dsb();
		SHENG_DBG_ENV("sheng_mdss_fb_readback",
			    (((unsigned long)fb[0]) << 32) |
			    (unsigned long)fb[fb_words - 1]);
	}
	sheng_tmark("fb clear");

	ret = sheng_mdss_dpu_start(SM8550_MDSS_DPU_BASE,
				    SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_FB_ADDR,
				    SHENG_PANEL_HACTIVE, SHENG_PANEL_VACTIVE,
				    SHENG_PANEL_HFRONT_PORCH,
				    SHENG_PANEL_HBACK_PORCH,
				    SHENG_PANEL_HSYNC_WIDTH,
				    SHENG_PANEL_VFRONT_PORCH,
				    SHENG_PANEL_VBACK_PORCH,
				    SHENG_PANEL_VSYNC_WIDTH,
				    true /* DSC */);
	sheng_tmark("dpu start");

	/* Sample the signature while the pipeline is live. The 40ms gap is
	 * ~6 frames at 144Hz, so a running timing engine must advance
	 * FRAME_COUNT; a stalled one will not. */
	{
		const uintptr_t d0 = SM8550_MDSS_DSI0_BASE;
		const uintptr_t intf = SM8550_MDSS_DPU_BASE + 0x35000;

		sheng_diag[0] = readl((void __iomem *)(uintptr_t)(d0 + 0x004));
		sheng_diag[1] = readl((void __iomem *)(uintptr_t)(d0 + 0x008));
		sheng_diag[2] = readl((void __iomem *)(uintptr_t)(d0 + 0x0a4));
		/* 0x064 is ACK_ERR_STATUS. 0x068 -- which this read used to
		 * use -- is RDBK_DATA0, so it was echoing the panel read's
		 * response and reporting it as an ACK error. */
		sheng_diag[3] = readl((void __iomem *)(uintptr_t)(d0 + 0x064));
		sheng_diag[4] = readl((void __iomem *)(uintptr_t)(d0 + 0x0bc));
		sheng_diag[5] = readl((void __iomem *)(uintptr_t)(SM8550_DISPCC_BASE + 0x010));
		sheng_diag[6] = readl((void __iomem *)(uintptr_t)(intf + 0x0ac));
		/* 8ms, not 40ms. Long enough for ~1 frame at 144Hz, which is
		 * all "is the timing engine advancing" needs, and this sits
		 * directly in the black gap the user sees. */
		mdelay(8);
		sheng_diag[7] = readl((void __iomem *)(uintptr_t)(intf + 0x0ac));
		/* Re-read FIFO *after* the settle. Sampled at FRAME_COUNT 0 it
		 * always reads 0x11111210 ("all lanes starved"), which is a
		 * known artifact of the pre-first-frame window and says
		 * nothing -- a healthy late sample is 0x00001210. Only this
		 * second read can distinguish a genuinely starved link. */
		sheng_diag[8] = readl((void __iomem *)(uintptr_t)(d0 + 0x008));
	}

	/* Ask the panel itself. Expect pm_val=9c; 08 means the init did not
	 * take. This is the classifier the host registers cannot provide --
	 * they read identical on a clean boot and a corrupted one. */
	sheng_panel_pm = sheng_mdss_dsi_read_power_mode_single(
				SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH);

	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DPU, ret);
	SHENG_DBG_ENV("sheng_mdss_dpu_start", (unsigned long)ret);
	BBM("dpu_start done");
	BBR("DSI0 STATUS0 post-dpu", SM8550_MDSS_DSI0_BASE, 0x004);
	BBR("DSI0 LANE_STATUS post-dpu", SM8550_MDSS_DSI0_BASE, 0x0a4);
	/* FIFO_STATUS reports a starved link directly: 0x00001210 is healthy,
	 * 0x11111210 sets all four DLN*_HS_FIFO_EMPTY bits and means mdp_clk
	 * is running slow. */
	BBR("DSI0 FIFO_STATUS post-dpu", SM8550_MDSS_DSI0_BASE, 0x008);
	BBR("DSI1 FIFO_STATUS post-dpu", SM8550_MDSS_DSI1_BASE, 0x008);
	/* PLL0 rate readback. Expect L_VAL 0x44440050, ALPHA 0x00005000.
	 * Anything else means the write did not stick because the PLL was
	 * locked, and the rate change needs a disable-reconfigure-relock. */
	BBR("DISPCC PLL0 L_VAL", SM8550_DISPCC_BASE, 0x010);
	BBR("DISPCC PLL0 ALPHA", SM8550_DISPCC_BASE, 0x014);
	BBR("INTF1 FRAME_COUNT", SM8550_MDSS_DPU_BASE + 0x35000, 0x0ac);
	if (ret)
		return ret;

	/* Everything past dpu_start is instrumentation. Costs a 550ms
	 * settle and many MMIO reads of live blocks; compiled out
	 * unless CONFIG_VIDEO_SHENG_MDSS_DEBUG=y. */
	SHENG_DBG_POST_DPU_REPORT();

	/* Hand the framebuffer to the video uclass. All of this must run
	 * BEFORE probe returns -- anything below the return is dead code and
	 * has silently swallowed three separate fixes already. With
	 * plat->base unset, video_post_probe() maps the framebuffer at NULL
	 * and every console write goes nowhere. */
	plat->base = SHENG_MDSS_FB_ADDR;

	/* RESERVE THE FRAMEBUFFER IN LMB, or something else will be given
	 * it. This driver allocates its own framebuffer at a fixed address
	 * rather than going through video_reserve(), so nothing else knows
	 * the region is in use.
	 *
	 * board_late_init() runs nine lmb_alloc() calls at INITCALL 758 and
	 * memcpy()s the FDT into one of them. The video probe is INITCALL
	 * 729, so by then the panel is already scanning this memory out. An
	 * allocation landing here writes straight into the live
	 * framebuffer.
	 *
	 * Which addresses LMB picks depends on the image size, so this
	 * fails intermittently: a build that shrinks by a few KB can move
	 * an allocation onto the framebuffer and corrupt the display with
	 * no other change. Reserve the DSI DMA scratch in the same span --
	 * it sits 1MB below and has the same problem. */
	{
		phys_addr_t fb = SHENG_MDSS_DSI_DMA_SCRATCH;
		phys_size_t len = (SHENG_MDSS_FB_ADDR - SHENG_MDSS_DSI_DMA_SCRATCH) +
				  (phys_size_t)SHENG_MDSS_FB_STRIDE * SHENG_PANEL_VACTIVE;

		ret = lmb_alloc_mem(LMB_MEM_ALLOC_ADDR, 0, &fb, len, LMB_NONE);
		if (ret)
			log_warning("sheng_mdss: framebuffer not reserved (%d)\n", ret);
		SHENG_DBG_ENV("sheng_mdss_fb_reserve", (unsigned long)ret);
	}

	uc_priv->xsize = SHENG_PANEL_HACTIVE;
	uc_priv->ysize = SHENG_PANEL_VACTIVE;
	uc_priv->bpix = VIDEO_BPP32;
	/* Memory order is B,G,R,A: a u32 0xFF0000FF renders blue. Unset, it
	 * stays VIDEO_UNKNOWN and video_clear() paints white. Alpha does not
	 * matter -- the mixers run LM_CONST_ALPHA_OPAQUE. */
	uc_priv->format = VIDEO_X8R8G8B8;
	uc_priv->rot = 0;

	/* Stride is ALIGN(3048,32)*4 = 12288, not 3048*4. The DPU fetches at
	 * this pitch. The uclass only computes a line_length if none is set,
	 * so setting it here wins. Wrong value shears every line by 96
	 * bytes. */
	uc_priv->line_length = SHENG_MDSS_FB_STRIDE;
	plat->size = (u32)SHENG_MDSS_FB_STRIDE * uc_priv->ysize;

	/* video_flush_dcache() returns early until this is set, so without
	 * it the uclass never pushes a console write out of the CPU cache
	 * and the DPU scans out stale DRAM -- panel black while the
	 * framebuffer provably holds the console's output.
	 *
	 * Needs CONFIG_VIDEO_DAMAGE=y. CONFIG_CYCLIC is off, so video_sync()
	 * is not rate-limited and every putc syncs; without damage tracking
	 * that is a 24MB flush per character. */
	video_set_flush_dcache(dev, true);

	SHENG_DBG_FINAL_DUMP();

	sheng_tmark("handoff");
	sheng_tmark_report();

	/* Reached the framebuffer handoff. Any other value in this slot
	 * means an early return above and therefore no picture. */
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_PROBE, 0);

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
