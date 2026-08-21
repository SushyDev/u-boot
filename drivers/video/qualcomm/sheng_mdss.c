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
extern int sheng_mdss_replay_bringup(unsigned long phy0, unsigned long phy1, unsigned long dsi0, unsigned long dsi1);
extern int sheng_mdss_replay_bringup_phase(u32 phase, unsigned long phy0, unsigned long phy1, unsigned long dsi0, unsigned long dsi1);
extern void sheng_mdss_dsi_reset_both_phys(unsigned long dsi0_base, unsigned long dsi1_base);
extern void sheng_mdss_dsi_host_video_prepare(unsigned long dsi0_base,
					     unsigned long dsi1_base);
extern int sheng_mdss_dsi_panel_init(unsigned long dsi0_base, unsigned long dsi1_base,
				      unsigned long dma_scratch, bool enable_dsc);
extern int sheng_mdss_dsi_test_patch(unsigned long dsi0_base, unsigned long dsi1_base,
				      unsigned long dma_scratch);
extern long long sheng_mdss_dsi_read_power_mode(unsigned long dsi0_base, unsigned long dsi1_base,
						 unsigned long dma_scratch);
extern long long sheng_mdss_dsi_read_error_status(unsigned long dsi0_base);
extern long long sheng_mdss_dsi_read_ctrl_state(unsigned long dsi0_base);
extern unsigned int sheng_mdss_dsi_ctrl_writeback_selfcheck(unsigned long dsi_base);
extern long long sheng_mdss_dsi_block_writeback_selfcheck(unsigned long dsi_base);
extern unsigned int sheng_mdss_dsi_earliest_ctrl_selfcheck(void);
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
extern void sheng_mdss_capture_state(unsigned long dst);
extern long long sheng_mdss_dsi_read_power_mode_single(unsigned long dsi0_base,
						       unsigned long dma_scratch);
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

	ret = sheng_mdss_dispcc_init(SM8550_DISPCC_BASE);
	BBS("dispcc_init_ret", ret);
	BBB("DISPCC after init", SM8550_DISPCC_BASE, 0x000, 64);
	sheng_mdss_phy144_mark(1, SM8550_MDSS_DSI0_PHY_BASE);
	SHENG_DBG_STAGE(SHENG_MDSS_STATUS_DISPCC, ret);
	/* UBWC block config, immediately after the MDSS core reset inside
	 * dispcc_init() wipes it -- see sheng_mdss_ubwc_init()'s comment.
	 * Must precede any DSI/DPU programming, matching msm_mdss_enable(). */
	sheng_mdss_ubwc_init(SM8550_MDSS_BASE);
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
	SHENG_DBG_ENV("sheng_mdss_phy_start", (unsigned long)ret);
	BBS("phy_start_dual_ret", ret);
	BBR("PHY0 STATUS", SM8550_MDSS_DSI0_PHY_BASE, 0x140);
	BBR("PHY1 STATUS", SM8550_MDSS_DSI1_PHY_BASE, 0x140);
	sheng_mdss_phy144_mark(4, SM8550_MDSS_DSI0_PHY_BASE);
	if (ret)
		return ret;

	/* byte/pclk/esc for both links. pclk drives INTF_FRAME_COUNT, not
	 * MDP_CLK -- without these the frame counters stay frozen at 0 no
	 * matter what MDP_CLK does. Must follow the PHY PLL lock above:
	 * these mux from the PHY PLL, not DISPCC's PLL0. */
	ret = sheng_mdss_dispcc_dsi_clks_init(SM8550_DISPCC_BASE);
	sheng_mdss_phy144_mark(5, SM8550_MDSS_DSI0_PHY_BASE);
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
	sheng_mdss_dsi_panel_sleep(SM8550_MDSS_DSI0_BASE,
				    SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_DSI_DMA_SCRATCH);

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


	/* The rails need a long off window to discharge. Shorter than ~1s
	 * and the DDIC keeps its state across the power cycle. Sampled
	 * twice on the way: both must read 0. */
	mdelay(20);
	SHENG_DBG_PIN("avdd during off", TLMM_PANEL_AVDD_GPIO);
	SHENG_DBG_PIN("avee during off", TLMM_PANEL_AVEE_GPIO);
	mdelay(60);
	SHENG_DBG_PIN("avdd late in off", TLMM_PANEL_AVDD_GPIO);
	SHENG_DBG_PIN("avee late in off", TLMM_PANEL_AVEE_GPIO);
	mdelay(1000);
	sheng_mdss_panel_power_and_reset();
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
