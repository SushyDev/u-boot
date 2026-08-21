// SPDX-License-Identifier: GPL-2.0+
/*
 * Native U-Boot display driver for the Qualcomm MDSS on SM8550
 * (Xiaomi Pad 6S Pro / "sheng"). Register bring-up sequencing (GDSC,
 * DISPCC, DSI PHY/host, DPU) lives in sheng_mdss_hw.zig and is called
 * through the extern "C" declarations below.
 *
 * Sub-block addresses are taken from dts/upstream/src/arm64/qcom/
 * sm8550.dtsi (mdss_mdp@ae01000, mdss_dsi0@ae94000,
 * mdss_dsi0_phy@ae95000, dispcc@af00000) rather than walked from the
 * mdss device tree node, since U-Boot does not instantiate the DPU/DSI
 * sub-nodes as separate udevices here.
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

DECLARE_GLOBAL_DATA_PTR;

/*
 * The DPU core (unlike the MDSS wrapper/DISPCC/DSI, which live on the
 * always-present MDSS_GDSC rail we already enable) sits on its own
 * RPMh-voted MMCX power rail -- see mdss_mdp@ae01000's "power-domains
 * = <&rpmhpd RPMHPD_MMCX>" in sm8550.dtsi. Without this vote, the AHB
 * slave for the whole DPU register block (SSPP/LM/DSC/CTL/INTF, base
 * 0xae01000) never acks a transaction and the CPU hangs indefinitely
 * on the very first register write -- confirmed by bisection: even a
 * lone SSPP_SRC_SIZE write with no other DPU register touched hangs
 * identically to the full sequence.
 *
 * The obvious fix is U-Boot's stock power-domain/rpmh-rsc/rpmhpd
 * driver stack (drivers/soc/qcom/rpmh*.c, drivers/power/domain/
 * qcom-rpmhpd.c), which already implements the full RPMh vote
 * protocol and was only missing an sm8550 power-domain descriptor
 * (added alongside this file). That route was tried first and does
 * make the vote succeed (confirmed via the status relay), but probing
 * it through the normal power-domain uclass reproducibly broke the
 * *unrelated* DSI panel-init DMA command engine afterward (DSI0/1
 * live on MDSS_GDSC, nothing to do with MMCX) -- most likely because
 * rpmh_rsc_send_data() in rpmh-rsc.c hardcodes "always use the first
 * active TCS slot" (its own comment: "U-Boot is single-threaded, ...
 * we'll never conflict") rather than picking a free one dynamically
 * like Linux does, and something about going through that path
 * disturbs shared RSC/TCS state in a way this driver can't safely
 * reason about blind (no console, no way to inspect intermediate RSC
 * register state on real hardware).
 *
 * So: send the exact same single active-only RPMh command directly,
 * hand-rolled against the raw APPS_RSC registers, using only read-only
 * cmd-db lookups (already proven safe -- the stock path used the same
 * lookups successfully) and nothing from the power-domain/rpmh-rsc
 * driver/uclass machinery. This mirrors rpmh_rsc_send_data() /
 * __tcs_buffer_write() / __tcs_set_trigger() in rpmh-rsc.c exactly,
 * but picks whichever of the 3 active TCS slots the hardware itself
 * reports as free (RSC_DRV_STATUS != 0) instead of assuming slot 0,
 * and touches nothing else (no IRQ_ENABLE writes, no other TCS
 * groups, no devicetree/driver-model probing at all).
 */

/* apps_rsc@17a00000 in sm8550.dtsi: reg-names = "drv-0".."drv-3",
 * qcom,drv-id = <2> (the AP uses window drv-2). qcom,tcs-offset =
 * <0xd00>. qcom,tcs-config = <ACTIVE_TCS 3>, <SLEEP_TCS 2>,
 * <WAKE_TCS 2>, <CONTROL_TCS 0> -- ACTIVE_TCS is listed first so it
 * occupies global TCS indices 0..2. */
/*
 * Log buffer: same idea as the status relay further down, but for
 * arbitrary (tag, value) pairs instead of one fixed slot per stage --
 * lets us record actual register readback values (cmd-db lookups,
 * RSC_DRV_ID, a raw pre-write DPU register read, etc.) and inspect
 * them after boot via /proc/device-tree/chosen/sheng,mdss-log, same
 * relay mechanism via ft_board_setup() in board.c. Layout: a u32
 * entry count at offset 0, followed by up to SHENG_MDSS_LOG_MAX
 * (tag:u32, value:u32) pairs. Placed well clear of the status slots
 * (which end at +0x3020+4=0x3024) and the uclass-get-device-ret slot.
 */
#define SHENG_MDSS_LOG_ADDR		(CONFIG_PRE_CON_BUF_ADDR + 0x3100)
#define SHENG_MDSS_LOG_MAX		64

enum {
	SHENG_LOG_RSC_DRV_ID,
	SHENG_LOG_CMDDB_MMCX_ADDR,
	SHENG_LOG_CMDDB_MM0_ADDR,
	SHENG_LOG_MMCX_TCS_ID,
	SHENG_LOG_MMCX_CORNER,
	SHENG_LOG_BCM_TCS_ID,
	SHENG_LOG_GCC_HF_AXI_READBACK,
	SHENG_LOG_DPU_PRE_WRITE_READ,
	SHENG_LOG_DPU_PRE_WRITE_READ_RET,
	SHENG_LOG_MDP_RCG_CFG_READBACK,
	SHENG_LOG_MMCX_LEVEL_PICKED,
	SHENG_LOG_WRAPPER_READ,
	SHENG_LOG_WRAPPER_READ_RET,
	SHENG_LOG_DPU_SINGLE_WRITE_RET,
	SHENG_LOG_DPU_SINGLE_WRITE_READBACK,
	SHENG_LOG_PLAT_BASE,
	SHENG_LOG_GD_VIDEO_TOP,
	SHENG_LOG_GD_VIDEO_BOTTOM,
	SHENG_LOG_WRAPPER_WRITE_RET,
	SHENG_LOG_WRAPPER_WRITE_READBACK,
};

/*
 * D-cache is on for this board (CONFIG_SYS_DCACHE_OFF is not set), so a
 * plain `volatile u32 *` store into this DRAM-backed breadcrumb region
 * is just a normal cacheable write -- it can sit dirty in a cache line
 * indefinitely. If the CPU hard-hangs on the very next instruction (the
 * DPU AHB bus lockup this whole log/status mechanism exists to survive),
 * that dirty line never reaches physical DRAM and a subsequent warm-
 * reboot memory scrape reads back zeros/stale data instead of whatever
 * was actually written -- confirmed empirically: a scrape after exactly
 * this scenario read back all zeros. Every breadcrumb write must be
 * immediately pushed to the point of coherency (flush_dcache_range(),
 * arch/arm/lib/cache-pl310.c's DSB-backed implementation) and followed
 * by an explicit `dsb sy` so the write is guaranteed physically complete
 * in DRAM before control ever returns to code that might touch the DPU.
 */
static void sheng_mdss_breadcrumb_flush(uintptr_t addr, size_t len)
{
	flush_dcache_range(addr, addr + len);
	dsb();
}

static void sheng_mdss_log_reset(void)
{
	volatile u32 *count = (volatile u32 *)(uintptr_t)SHENG_MDSS_LOG_ADDR;

	if (IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
		*count = 0;
		sheng_mdss_breadcrumb_flush(SHENG_MDSS_LOG_ADDR, sizeof(*count));
	}
}

static void sheng_mdss_log(u32 tag, u32 value)
{
	volatile u32 *count = (volatile u32 *)(uintptr_t)SHENG_MDSS_LOG_ADDR;
	volatile u32 *entries = (volatile u32 *)(uintptr_t)(SHENG_MDSS_LOG_ADDR + 4);

	if (!IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
		return;
	if (*count >= SHENG_MDSS_LOG_MAX)
		return;

	entries[*count * 2] = tag;
	entries[*count * 2 + 1] = value;
	(*count)++;
	sheng_mdss_breadcrumb_flush(SHENG_MDSS_LOG_ADDR,
				     4 + (*count) * 8);
}

#define APPS_RSC_DRV2_BASE	0x17a20000
#define APPS_RSC_TCS_OFFSET	0xd00
#define APPS_RSC_ACTIVE_TCS_COUNT	3
#define APPS_RSC_ACTIVE_TCS_FIRST	0

/* Same two register layouts rpmh-rsc.c selects between based on the
 * major version read back from RSC_DRV_ID (offset 0) -- see
 * rpmh_rsc_reg_offset_ver_{2_7,3_0} there. */
struct rsc_drv_regs {
	u32 tcs_stride;
	u32 cmd_stride;
	u32 cmd_wait_for_cmpl;
	u32 control;
	u32 status;
	u32 cmd_enable;
	u32 cmd_msgid;
	u32 cmd_addr;
	u32 cmd_data;
	u32 cmd_status;
};

static const struct rsc_drv_regs rsc_regs_v2_7 = {
	.tcs_stride = 672, .cmd_stride = 20,
	.cmd_wait_for_cmpl = 0x10, .control = 0x14, .status = 0x18,
	.cmd_enable = 0x1c, .cmd_msgid = 0x30, .cmd_addr = 0x34,
	.cmd_data = 0x38, .cmd_status = 0x3c,
};

static const struct rsc_drv_regs rsc_regs_v3_0 = {
	.tcs_stride = 672, .cmd_stride = 24,
	.cmd_wait_for_cmpl = 0x20, .control = 0x24, .status = 0x28,
	.cmd_enable = 0x2c, .cmd_msgid = 0x34, .cmd_addr = 0x38,
	.cmd_data = 0x3c, .cmd_status = 0x40,
};

#define TCS_AMC_MODE_ENABLE	(1u << 16)
#define TCS_AMC_MODE_TRIGGER	(1u << 24)
#define CMD_MSGID_BASE		8u
#define CMD_MSGID_RESP_REQ	(1u << 8)
#define CMD_MSGID_WRITE		(1u << 16)
#define CMD_STATUS_COMPL	(1u << 16)

#define RSC_POLL_TIMEOUT_US	200000

static void __iomem *rsc_tcs_reg(void __iomem *tcs_base,
				  const struct rsc_drv_regs *regs,
				  u32 reg_off, int tcs_id)
{
	return tcs_base + regs->tcs_stride * tcs_id + reg_off;
}

static void __iomem *rsc_cmd_reg(void __iomem *tcs_base,
				  const struct rsc_drv_regs *regs,
				  u32 reg_off, int tcs_id)
{
	/* Single command per transfer, always cmd_id 0. */
	return rsc_tcs_reg(tcs_base, regs, reg_off, tcs_id);
}

static int rsc_write_reg_sync(void __iomem *tcs_base,
			       const struct rsc_drv_regs *regs,
			       u32 reg_off, int tcs_id, u32 data)
{
	void __iomem *addr = rsc_tcs_reg(tcs_base, regs, reg_off, tcs_id);
	unsigned int i;

	writel(data, addr);
	for (i = 0; i < RSC_POLL_TIMEOUT_US; i++) {
		if (readl(addr) == data)
			return 0;
		udelay(1);
	}
	return -ETIMEDOUT;
}

/*
 * Send one ACTIVE_ONLY RPMh write (addr/data) and wait for hardware
 * completion. Picks whichever active TCS slot is currently free
 * rather than assuming a fixed one.
 */
static int rsc_send_active_write(u32 resource_addr, u32 data)
{
	void __iomem *rsc_base = (void __iomem *)(uintptr_t)APPS_RSC_DRV2_BASE;
	void __iomem *tcs_base = rsc_base + APPS_RSC_TCS_OFFSET;
	const struct rsc_drv_regs *regs;
	u32 rsc_id, major;
	int tcs_id = -1;
	u32 cmd_msgid;
	unsigned int i;

	rsc_id = readl(rsc_base);
	sheng_mdss_log(SHENG_LOG_RSC_DRV_ID, rsc_id);
	env_set_hex("sheng_rsc_id", (unsigned long)rsc_id);
	major = (rsc_id >> 16) & 0xff;
	regs = (major == 3) ? &rsc_regs_v3_0 : &rsc_regs_v2_7;

	/* The real driver (drivers/soc/qcom/rpmh-rsc.c) tracks free/busy TCS
	 * slots purely in a SOFTWARE bitmap (drv->tcs_in_use via
	 * find_free_tcs()/find_next_zero_bit()) -- it never reads a
	 * hardware "status" register for this at all (RSC_DRV_STATUS is
	 * defined in the same regs table ours mirrors but is dead code,
	 * never referenced anywhere in the real driver). Our previous
	 * "nonzero status = free" read was an unverified guess at a
	 * register whose real semantics nobody -- including the reference
	 * driver -- actually relies on. This function is fully synchronous
	 * (always polls CMD_STATUS_COMPL below before returning) and
	 * nothing else in this single-threaded bootloader ever touches the
	 * RSC concurrently, so just always use the first active TCS slot --
	 * exactly what Linux's own bitmap would pick on a fresh boot
	 * anyway (all-zero bitmap -> find_next_zero_bit returns the first
	 * one). */
	tcs_id = APPS_RSC_ACTIVE_TCS_FIRST;
	sheng_mdss_log(SHENG_LOG_MMCX_TCS_ID, (u32)tcs_id);

	cmd_msgid = CMD_MSGID_BASE | CMD_MSGID_RESP_REQ | CMD_MSGID_WRITE;
	writel(cmd_msgid, rsc_cmd_reg(tcs_base, regs, regs->cmd_msgid, tcs_id));
	writel(resource_addr, rsc_cmd_reg(tcs_base, regs, regs->cmd_addr, tcs_id));
	writel(data, rsc_cmd_reg(tcs_base, regs, regs->cmd_data, tcs_id));

	/* Real driver (__tcs_buffer_write() in drivers/soc/qcom/rpmh-rsc.c)
	 * represents "wait for completion" entirely via CMD_MSGID_RESP_REQ
	 * in the msgid word above -- it NEVER writes RSC_DRV_CMD_WAIT_FOR_
	 * CMPL at all, despite that register existing in the same regs
	 * table our own rsc_regs_v2_7/v3_0 structs mirror. This driver used
	 * to write 1u to it here anyway (a fabricated write with no basis
	 * in the real driver) -- on a shared RSC/TCS controller block that
	 * sequences voltage rails for the whole SoC, that stray write is
	 * the most likely explanation for "AHB access breaks chip-wide"
	 * (SPEC.md task #5's original RSC corruption finding). Removed. */
	writel(readl(rsc_tcs_reg(tcs_base, regs, regs->cmd_enable, tcs_id)) | 1u,
	       rsc_tcs_reg(tcs_base, regs, regs->cmd_enable, tcs_id));

	/* __tcs_set_trigger(): clear trigger, clear enable, set enable,
	 * then set enable|trigger -- exact sequence rpmh-rsc.c uses. */
	{
		u32 enable = readl(rsc_tcs_reg(tcs_base, regs, regs->control, tcs_id));
		int ret;

		enable &= ~TCS_AMC_MODE_TRIGGER;
		ret = rsc_write_reg_sync(tcs_base, regs, regs->control, tcs_id, enable);
		if (ret)
			return ret;

		enable &= ~TCS_AMC_MODE_ENABLE;
		ret = rsc_write_reg_sync(tcs_base, regs, regs->control, tcs_id, enable);
		if (ret)
			return ret;

		enable = TCS_AMC_MODE_ENABLE;
		ret = rsc_write_reg_sync(tcs_base, regs, regs->control, tcs_id, enable);
		if (ret)
			return ret;

		enable |= TCS_AMC_MODE_TRIGGER;
		writel(enable, rsc_tcs_reg(tcs_base, regs, regs->control, tcs_id));
	}

	for (i = 0; i < RSC_POLL_TIMEOUT_US; i++) {
		u32 status = readl(rsc_cmd_reg(tcs_base, regs, regs->cmd_status, tcs_id));

		if (status & CMD_STATUS_COMPL)
			return 0;
		udelay(1);
	}

	return -ETIMEDOUT;
}

/* mdss_mdp@ae01000's own OPP table (mdp_opp_table in sm8550.dtsi) ties
 * its 514MHz entry (the exact DISP_CC_MDSS_MDP_CLK rate
 * sheng_mdss_dispcc_init() programs, confirmed correct via readback --
 * see the MDP_RCG_CFG_READBACK log entry) to `required-opps =
 * <&rpmhpd_opp_nom>`. rpmhpd_opp_nom is labelled `opp-256` in the
 * rpmhpd OPP table (sm8550.dtsi), i.e. RPMH_REGULATOR_LEVEL_NOM = 256
 * (dt-bindings/regulator/qcom,rpmh-regulator.h). We were previously
 * picking the *lowest* nonzero corner unconditionally -- an MMCX
 * under-vote for the clock rate actually requested, which is a
 * plausible root cause for a bus that clocks correctly (confirmed) but
 * still hangs on first register access. */
#define RPMH_REGULATOR_LEVEL_NOM 256

static int __maybe_unused sheng_mdss_mmcx_power_on(void)
{
	u32 addr;
	const u16 *levels;
	size_t len, count, i;
	u32 corner;

	addr = cmd_db_read_addr("mmcx.lvl");
	sheng_mdss_log(SHENG_LOG_CMDDB_MMCX_ADDR, addr);
	env_set_hex("sheng_mmcx_addr", (unsigned long)addr);
	if (!addr)
		return -ENODEV;

	levels = cmd_db_read_aux_data("mmcx.lvl", &len);
	if (IS_ERR(levels)) {
		env_set_hex("sheng_mmcx_levels_err", (unsigned long)PTR_ERR(levels));
		return PTR_ERR(levels);
	}

	count = len >> 1;
	env_set_hex("sheng_mmcx_count", (unsigned long)count);

	/* Live dmesg capture (rpmhpd.dyndbg=+p) showed the real
	 * rpmhpd_aggregate_corner() logic: `if (pd->state_synced) { use the
	 * requested corner } else { clamp to level_count - 1, the MAX
	 * corner }`. state_synced only becomes true via genpd's sync_state,
	 * a LATE event well after individual driver .probe() calls settle
	 * -- msm_dpu's own MDP-clock-rate request (and therefore its MMCX
	 * vote) happens during ITS OWN .probe(), before that. So Linux's
	 * real vote at this exact point in boot is the clamped MAX corner,
	 * not our previously-computed "smallest corner >= NOM" -- that
	 * computation matches POST-sync_state steady-state behavior, not
	 * early boot. Also: cmd_db_read_aux_data's returned count (16 for
	 * mmcx.lvl) is a padded buffer size, not the real level count --
	 * dmesg showed only hlvl 0..5 (vlvl 0,64,128,192,256,384) are real,
	 * rest is zero-padding. Find the real max corner as the last
	 * nonzero entry rather than trusting the raw buffer length. */
	corner = 0;
	for (i = 1; i < count; i++) {
		if (levels[i] != 0)
			corner = i;
	}
	sheng_mdss_log(SHENG_LOG_MMCX_CORNER, corner);
	sheng_mdss_log(SHENG_LOG_MMCX_LEVEL_PICKED, corner < count ? levels[corner] : 0);
	env_set_hex("sheng_mmcx_corner", (unsigned long)corner);
	env_set_hex("sheng_mmcx_level", (unsigned long)(corner < count ? levels[corner] : 0));

	return rsc_send_active_write(addr, corner);
}

/*
 * MMCX alone wasn't the whole fix: bisection showed the DSI panel-init
 * DMA engine (unrelated to MMCX) reliably hung once GDSC/DISPCC/DSI
 * clocks were active AND an RPMh transaction of any kind had run --
 * pointing at a missing interconnect (BCM) bandwidth vote rather than
 * a driver-implementation issue, exactly as msm_mdss.c's real probe
 * path spells out:
 *
 *   "Several components have AXI clocks that can only be turned on if
 *   the interconnect is enabled (non-zero bandwidth)."
 *   (msm_mdss_enable(), drivers/gpu/drm/msm/msm_mdss.c)
 *
 * -- and it calls icc_set_bw() for the "mdp0-mem"/"mdp1-mem" and
 * "cpu-cfg" interconnect paths *before* clk_bulk_prepare_enable().
 * Tracing those paths through drivers/interconnect/qcom/sm8550.c:
 *   - "cpu-cfg" terminates at qhs_display_cfg, part of BCM "CN0",
 *     which has .keepalive = true -- already permanently voted by
 *     firmware, which is why DISPCC/DSI (also gated through CN0) have
 *     worked fine all along with zero icc code from us.
 *   - "mdp0-mem" (qnm_mdp's only link) terminates at qns_mem_noc_hf,
 *     part of BCM "MM0", which is NOT keepalive -- nobody has voted
 *     it, so mmss_noc's internal AXI clock gate for MASTER_MDP (i.e.
 *     our SSPP block) stays closed and the very first register write
 *     into it hangs the AHB bus. This is the real missing piece.
 *
 * U-Boot has no sm8550 interconnect provider (drivers/interconnect/
 * qcom/ only has sm8650.c), so the generic icc_set_bw() aggregation
 * path isn't available; sending a minimal direct BCM vote for "MM0"
 * (vote_x=vote_y=1, mirroring bcm_aggregate()'s own keepalive-BCM
 * fallback of "1" when nothing else has voted, i.e. "just enough to
 * not be zero") over the same raw RSC path as the MMCX vote is the
 * equivalent of Linux's minimum-bandwidth icc_set_bw() call, without
 * needing to port the whole provider/aggregation framework.
 */
/*
 * gcc@100000's GCC_DISP_HF_AXI_CLK (gcc-sm8550.c: halt_reg/enable_reg
 * = 0x2700c, enable_mask = BIT(0), halt_check = BRANCH_HALT_SKIP i.e.
 * no ready-status polling needed/available). msm_mdss_enable() enables
 * this alongside DISP_CC_MDSS_AHB_CLK/DISP_CC_MDSS_MDP_CLK (which we
 * already do via sheng_mdss_dispcc_init) as part of the SAME clk_bulk
 * for the mdss wrapper device. GCC_DISP_AHB_CLK (the other GCC clock
 * mdss lists) is force-enabled unconditionally at gcc-sm8550.c's own
 * probe() as an always-on clock with no software enable/disable API,
 * which is presumably why DISPCC/DSI have worked fine without us ever
 * touching it -- but GCC_DISP_HF_AXI_CLK (the AXI *data* path clock,
 * as opposed to AHB register/config path) is a normal, individually
 * gated consumer clock nobody else enables for us. Cheap, simple,
 * un-polled register set -- try this before any more RPMh/BCM work.
 */
/* DON'T-TOUCH-THE-PANEL TEST (SPEC.md task #5 log).
 *
 * Established facts, as of this test:
 *   - Linux renders correctly on this panel (green NixOS prompt + login
 *     visible) AFTER this driver has run, so the panel, the physical link
 *     and the DDIC all work, and nothing we do breaks them permanently.
 *   - The SSPP genuinely fetches: pointing it at an unmapped IOVA produced
 *     CB_FSR=0x402 (TF) with CB_FAR=0x500017c0, while the real address
 *     faults not at all.
 *   - Every register in DISPCC, both DSI hosts, both PHYs, the DPU (CTL,
 *     SSPP, LM, PP, INTF, DCE), the MDSS wrapper and VBIF matches the
 *     working kernel write-for-write, verified by tracing every write the
 *     kernel makes.
 *
 * So the video path is correct and the panel is good -- yet our frames are
 * not visible. The remaining untested split is: is it our VIDEO path that
 * fails, or our PANEL INIT?
 *
 * ABL initialises this panel for its own splash. The DDIC keeps that
 * configuration as long as it stays powered and un-reset -- and ABL's
 * teardown only stops the SoC side (measured: DSI CTRL=0, both PHY PLLs
 * stopped at handoff), it does not necessarily reset the panel.
 *
 * This test therefore does not touch the panel AT ALL: no cold-start bias
 * teardown, no reset pulse, no DCS init sequence. Everything on the SoC
 * side runs exactly as before and we stream video at whatever state ABL
 * left the DDIC in.
 *
 *   image appears -> our VIDEO path is fine and our PANEL INIT is what
 *     breaks it. That is a completely different search, on a much smaller
 *     surface (87 DCS commands + PPS), and it explains every "everything
 *     matches and it is still black" result so far.
 *   still black -> our video path cannot drive even a panel that is
 *     already initialised and known-good, despite matching the kernel
 *     write-for-write.
 *
 * Diagnostic only -- set to 0 for a normal boot.
 */
#define SHENG_SKIP_PANEL_TOUCH 0

#define SM8550_GCC_BASE			0x00100000
#define GCC_DISP_HF_AXI_CLK_CBCR_OFF		0x2700c

static void sheng_mdss_gcc_disp_hf_axi_clk_enable(void)
{
	volatile u32 *cbcr = (volatile u32 *)(uintptr_t)(SM8550_GCC_BASE + GCC_DISP_HF_AXI_CLK_CBCR_OFF);

	*cbcr |= 1u;
	/* Sanity readback: confirms both that this write landed AND that
	 * the GCC block itself is reachable (if this read also hung, we'd
	 * never reach the log call after it). */
	sheng_mdss_log(SHENG_LOG_GCC_HF_AXI_READBACK, *cbcr);
}

/* Backlight enable, GPIO 128 (TLMM), active-high -- matches the
 * `backlight-gpio` / `enable-gpios = <&tlmm 128 GPIO_ACTIVE_HIGH>` DT
 * node already present in sm8550-xiaomi-sheng.dts (added in an earlier
 * session, CONFIG_BACKLIGHT currently disabled so that node has no
 * driver acting on it). GPIO 128 itself was independently verified
 * working in that earlier session via a raw trap-based test; the
 * backlight IC downstream of it is a KTZ8866A on I2C1, which needs its
 * own (unrelated, still-broken -- QUP firmware loader timing) I2C probe
 * for brightness/PWM control, but the enable line alone may be enough
 * to get default-brightness output, worth trying on its own first.
 *
 * Deliberately raw MMIO here rather than U-Boot's gpio-backlight uclass
 * driver: this session found that even a trivial .bind hook (see
 * sheng_mdss_probe()'s own history) reliably hangs this board via a
 * pre-relocation DM bind-pass fragility, and gpio-backlight is a
 * completely untested (for us) driver-model path. A raw TLMM poke
 * carries none of that risk and matches this whole session's approach.
 *
 * Register layout confirmed from drivers/pinctrl/qcom/pinctrl-sm8550.c's
 * PINGROUP macro (mainline kernel checkout): per-pin 0x1000 stride from
 * the tlmm block (0xf100000, sm8550.dtsi's tlmm@f100000), ctl_reg at
 * +0, io_reg at +0x4; mux_bit=2 (3 bits, msm_mux_gpio=0 selects native
 * GPIO function), oe_bit=9 (output enable), out_bit=1 (in io_reg,
 * drive value once OE=1).
 */
#define SM8550_TLMM_BASE		0x00f100000
#define TLMM_GPIO_REG_SIZE		0x1000
#define TLMM_BACKLIGHT_GPIO		128
#define TLMM_MUX_FUNC_MASK		(0x7u << 2)
#define TLMM_OE_BIT			(1u << 9)
#define TLMM_OUT_BIT			(1u << 1)

static void sheng_mdss_raw_gpio_set(unsigned int gpio, int high)
{
	volatile u32 *ctl = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * gpio);
	volatile u32 *io = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * gpio);
	u32 v;

	v = *ctl;
	v &= ~TLMM_MUX_FUNC_MASK; /* native GPIO function (msm_mux_gpio = 0) */
	v |= TLMM_OE_BIT;
	*ctl = v;

	v = *io;
	if (high)
		v |= TLMM_OUT_BIT;
	else
		v &= ~TLMM_OUT_BIT;
	*io = v;
}

/* Currently unreferenced -- the KTZ8866 is brought up over I2C rather than
 * by this GPIO, and the DDIC gates its output via DCS 0x51/0x53 anyway.
 * Kept because the backlight turned out to be a direct visible indicator of
 * whether our DCS traffic reaches the panel, so a manual override is worth
 * having to hand. __maybe_unused so it doesn't trip -Werror. */
static void __maybe_unused sheng_mdss_backlight_gpio_enable(void)
{
	sheng_mdss_raw_gpio_set(TLMM_BACKLIGHT_GPIO, 1);
}

/* Real board devicetree (sm8550-mainline's arch/arm64/boot/dts/qcom/
 * sm8550-xiaomi-sheng.dts): panel's avdd-supply=<&bl_vddpos_5p8> is a
 * regulator-fixed node on `gpio = <&tlmm 30 GPIO_ACTIVE_HIGH>`, avee-
 * supply=<&bl_vddneg_5p8> on GPIO 31, both with regulator-enable-ramp-
 * delay=<233> (us). panel-novatek-nt36532e.c's nt36532e_prepare()
 * enables these via regulator_bulk_enable() BEFORE nt36532e_reset() --
 * a gap this driver never closed until now (see sheng_mdss_hw.zig's
 * sheng_mdss_dsi_panel_init() doc comment: "NOT included here (real
 * gap...)"). Without panel bias power, DCS commands over DSI go
 * nowhere even though the host-side command-mode DMA reports success
 * sending them -- no BTA/ACK is required for a plain DCS write, so a
 * completely unresponsive panel looks identical to a working one from
 * the DSI host's point of view. */
#define TLMM_PANEL_AVDD_GPIO		30
#define TLMM_PANEL_AVEE_GPIO		31
#define TLMM_PANEL_RESET_GPIO		133

extern void sheng_bb_init(void);
extern void sheng_bb_mark(const char *name);
extern void sheng_bb_val(const char *name, unsigned long long v);
extern void sheng_bb_sval(const char *name, long long v);
extern void sheng_bb_reg(const char *name, unsigned long base, unsigned long off);
extern void sheng_bb_block(const char *name, unsigned long base,
			    unsigned long start, unsigned long count);
extern void sheng_bb_finish(void);

#define BBM(n)			sheng_bb_mark(n)
#define BBV(n, v)		sheng_bb_val((n), (unsigned long long)(v))
#define BBS(n, v)		sheng_bb_sval((n), (long long)(v))
#define BBR(n, b, o)		sheng_bb_reg((n), (unsigned long)(b), (unsigned long)(o))
#define BBB(n, b, s, c)		sheng_bb_block((n), (unsigned long)(b), \
					       (unsigned long)(s), (unsigned long)(c))

extern int sheng_ktz8866_set_bias(int enable);

static void sheng_mdss_panel_power_and_reset(void)
{
	sheng_ktz8866_set_bias(1);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 1);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 1);
	mdelay(1); /* regulator-enable-ramp-delay=233us on both, rounded up */

	/* PANEL BIAS ENABLE READBACK (SPEC.md task #5 log).
	 *
	 * Never measured, in the whole project. GPIO 133 (reset) has been read
	 * back every boot for a long time and always looks right, but the two
	 * pins that actually POWER the panel -- avdd (bl_vddpos_5p8, GPIO 30)
	 * and avee (bl_vddneg_5p8, GPIO 31), the KTZ8866's +/-5.8V rails --
	 * have only ever been written, never verified.
	 *
	 * If either write is not landing (pin owned elsewhere, wrong mux, OE
	 * never set), the panel is simply UNPOWERED. That single fact would
	 * explain every observation at once, with no exotic PHY theory needed:
	 * an unpowered panel ignores commands on LP and on HS alike, never
	 * answers a BTA (sheng.rd1 = 0 on every boot and every transmission
	 * mode), and shows black while every SoC-side register legitimately
	 * matches working silicon.
	 *
	 * Same read-only TLMM access already proven safe on GPIO 133 -- this
	 * is a plain register read on a block that is always clocked, not the
	 * MDSS-range read that wedged the bus earlier.
	 *
	 * Packed: [63:48] GPIO30 CFG, [47:32] GPIO30 IN_OUT,
	 *         [31:16] GPIO31 CFG, [15:0]  GPIO31 IN_OUT.
	 * Healthy looks like CFG with OE (bit9) set and mux bits [4:2] zero,
	 * and IN_OUT == 0x3 (bit0 = driven value high, bit1 = pad reads high).
	 * IN_OUT low, or OE clear, names the culprit outright.
	 */
	{
		volatile u32 *avdd_ctl = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVDD_GPIO);
		volatile u32 *avdd_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVDD_GPIO);
		volatile u32 *avee_ctl = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVEE_GPIO);
		volatile u32 *avee_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVEE_GPIO);

		/* Into the blackbox too: computed every boot since it was added
		 * and never once read out, because the cmdline is CBSIZE-capped
		 * and this never made the list. */
		BBV("biasgpio(avddCFG|avddIO|aveeCFG|aveeIO)",
		    (((unsigned long long)(*avdd_ctl & 0xffff)) << 48) |
		    (((unsigned long long)(*avdd_io & 0xffff)) << 32) |
		    (((unsigned long long)(*avee_ctl & 0xffff)) << 16) |
		    ((unsigned long long)(*avee_io & 0xffff)));
		env_set_hex("sheng_mdss_biasgpio",
			    (((unsigned long)(*avdd_ctl & 0xffff)) << 48) |
			    (((unsigned long)(*avdd_io & 0xffff)) << 32) |
			    (((unsigned long)(*avee_ctl & 0xffff)) << 16) |
			    ((unsigned long)(*avee_io & 0xffff)));
	}

	/* nt36532e_reset(): reset_gpio is GPIO_ACTIVE_LOW in the real DT,
	 * requested GPIOD_OUT_HIGH (idle = logical 0 = physical HIGH, not
	 * in reset). gpiod_set_value_cansleep(gpio, 1) means *logical*
	 * assert, which the gpiod core inverts to *physical* LOW for an
	 * active-low line -- translating the real driver's exact sequence
	 * to raw physical pin levels: */
	/* RESET PULSE VERIFICATION (SPEC.md task #5 log).
	 *
	 * We have only ever read this pin's FINAL state (sheng.rstgpio =
	 * CFG 0x3c1, IN_OUT 0x3 -- driven high, deasserted). That proves the
	 * pad follows when driven HIGH. It says nothing about whether it
	 * actually goes LOW, i.e. whether the panel is ever really reset.
	 *
	 * This matters now: the handoff test proved our init does not
	 * configure the DDIC, while the command bytes, packets, DMA and every
	 * register are all verified correct. A reset that never physically
	 * asserts would leave the panel in whatever state ABL left it, and a
	 * DDIC that never saw a reset can legitimately ignore a fresh init
	 * sequence.
	 *
	 * IN_OUT bit0 is the value we drive, bit1 is what the pad actually
	 * reads back. Sample right after each transition, while it is held.
	 * A driven-LOW pad must read 0x0; if it reads 0x3 or 0x2 the line is
	 * being held high by something else and the pulse never happens.
	 *
	 * Packed, 4 bits per sample, oldest first:
	 *   [15:12] after assert #1   [11:8] after deassert #1
	 *   [7:4]   after assert #2   [3:0]  after deassert #2
	 * Healthy = 0x0303.
	 */
	{
		volatile u32 *rio = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_RESET_GPIO);
		unsigned long pulse = 0;

		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* physical LOW: reset asserted */
		pulse |= ((unsigned long)(*rio & 0xf)) << 12;
		mdelay(11);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 1); /* physical HIGH: deasserted */
		pulse |= ((unsigned long)(*rio & 0xf)) << 8;
		mdelay(4);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* physical LOW: asserted again */
		pulse |= ((unsigned long)(*rio & 0xf)) << 4;
		mdelay(4);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 1); /* physical HIGH: panel ready */
		pulse |= ((unsigned long)(*rio & 0xf));
		mdelay(16);

		/* THE measurement this build exists for. Healthy = 0x0303.
		 * Nibbles are IN_OUT&0xf sampled while each level is held,
		 * oldest first: assert1, deassert1, assert2, deassert2.
		 * bit0 = value driven, bit1 = what the pad actually reads.
		 * A driven-LOW pad MUST read 0x0. Any 0x3 or 0x2 in an
		 * assert slot means the line is held high by something else
		 * and the panel is NEVER physically reset -- which would
		 * explain the SHENG_NOINIT result (ret=-61) exactly. */
		BBV("rstpulse(a1,d1,a2,d2 expect 0303)", pulse);
		env_set_hex("sheng_mdss_rstpulse", pulse);
	}

	/* Read the reset/bias pins back (SPEC.md task #5 log). Every
	 * register we can compare -- all 46 DPU registers, the DSI host,
	 * and 31/31 PHY registers -- now matches live working silicon, the
	 * framebuffer verifiably contains green, and the panel is still
	 * black. Three independent signals say the PANEL never acts on
	 * anything we send: ALL_PIXELS_ON (which needs no video data) did
	 * nothing, DCS reads have never returned a byte, and the screen is
	 * uniformly black rather than showing garbage. A panel that never
	 * received a valid reset behaves exactly like that.
	 *
	 * GPIO 133's TARGET value was checked against Linux (CFG 0x2C0 =
	 * GPIO func + OE, IN_OUT 0x3 = driving high, reset deasserted) but
	 * it has never been confirmed that OUR writes actually land -- if
	 * the pin stays an input, the panel is never reset and every
	 * perfect measurement downstream is irrelevant.
	 * high32 = GPIO_CFG, low32 = GPIO_IN_OUT. Expect 0x2C0 / 0x3. */
	{
		volatile u32 *rst_ctl = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * TLMM_PANEL_RESET_GPIO);
		volatile u32 *rst_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_RESET_GPIO);
		BBV("rstgpio(CFG<<32|IN_OUT)", (((unsigned long long)*rst_ctl) << 32) |
		     (unsigned long long)*rst_io);
		env_set_hex("sheng_mdss_rstgpio",
			    (((unsigned long)*rst_ctl) << 32) | (unsigned long)*rst_io);
	}
}

static int sheng_mdss_bcm_vote(const char *bcm_name)
{
	u32 addr;
	u32 data;

	addr = cmd_db_read_addr(bcm_name);
	sheng_mdss_log(SHENG_LOG_CMDDB_MM0_ADDR, addr);
	if (!addr)
		return -ENODEV;

	/* First attempt used vote_x=1/vote_y=1 -- accepted (CMD_STATUS_COMPL)
	 * but made no visible difference. That's the exact same symbolic
	 * "not literally zero" floor bcm-voter.c's bcm_aggregate() forces
	 * onto keepalive BCMs (MC0/SH0) when no real master requests
	 * anything -- not a realistic bandwidth grant. Real masters instead
	 * get vote_x/vote_y computed from actual requested bandwidth via
	 * bcm_div(bw * vote_scale, aux_data.unit), which needs live
	 * unit/width values from cmd_db_read_aux_data("MM0") to compute
	 * precisely. Rather than guess that scaling blind, vote the
	 * maximum representable value in this 14-bit field instead of a
	 * token "1" -- tests whether magnitude (not just non-zero-ness) is
	 * what actually opens the NoC QoS gate for real video bandwidth. */
	data = (1u << 30) /* commit */ | (1u << 29) /* valid */ |
	       ((0x3fffu) << 14) /* vote_x, max */ | (0x3fffu) /* vote_y, max */;

	return rsc_send_active_write(addr, data);
}

/* RPMh VRM regulator vote (qcom-rpmh-regulator.c's own mechanism --
 * same underlying RSC/TCS transport as sheng_mdss_bcm_vote() and the
 * earlier-abandoned MMCX corner vote, but a genuinely different target
 * and a much simpler encoding: a plain millivolt value, not a
 * bandwidth-bucket x/y pair. Real driver's sequence when a regulator
 * has never been touched (vreg->enabled == -EINVAL): voltage-select
 * write first, then enable write -- mirrored here exactly.
 *
 * NEVER ATTEMPTED BEFORE THIS PASS (SPEC.md task #5 log): reading the
 * board's actual DTS overlay (not just the generic sm8550.dtsi, which
 * doesn't show board-specific overrides) found &mdss_dsi0_phy has
 * vdds-supply = <&vreg_l1e_0p88> -- the D-PHY's OWN analog supply --
 * and panel@0 has vddio-supply = <&vreg_s3g_0p7>, neither ever touched
 * by this driver (only avdd/avee GPIOs were ever handled). Neither
 * regulator has regulator-boot-on/always-on in the DTS, so nothing
 * guarantees ABL leaves them on; confirmed live on a working Linux
 * boot that both are "enabled" (vreg_l1e_0p88=880000uV,
 * vreg_s3g_0p7=600000uV) -- but that's Linux's OWN driver turning them
 * on during its probe, not proof of their state during U-Boot's
 * earlier run. If the D-PHY's analog transmitters are running without
 * a real supply, digital control/status registers (PLL lock bit,
 * REFGEN ready) could still read back fine while the actual HS
 * differential signal never reaches valid levels -- exactly matching
 * "frames streaming, zero pixels, no fault" with no software-visible
 * symptom. Resource names/millivolt values match cmd-db's own lowercase
 * regulator-ID convention and the live-confirmed voltages above. */
static int sheng_mdss_regulator_vote(const char *rsc_name, u32 millivolts)
{
	u32 addr;
	int ret;

	addr = cmd_db_read_addr(rsc_name);
	if (!addr)
		return -ENODEV;

	ret = rsc_send_active_write(addr + 0x0 /* RPMH_REGULATOR_REG_VRM_VOLTAGE */,
				     millivolts);
	if (ret)
		return ret;

	/* REAL GAP: RPMH_REGULATOR_REG_VRM_MODE (SPEC.md task #5 log).
	 *
	 * qcom-rpmh-regulator.c defines THREE per-resource command offsets:
	 *   RPMH_REGULATOR_REG_VRM_VOLTAGE 0x0
	 *   RPMH_REGULATOR_REG_ENABLE      0x4
	 *   RPMH_REGULATOR_REG_VRM_MODE    0x8   <-- never written here
	 *
	 * All three display rails carry `regulator-initial-mode =
	 * <RPMH_REGULATOR_MODE_HPM>` in this board's DTS, and the regulator
	 * core applies that during registration via ->set_mode, i.e.
	 * rpmh_regulator_vrm_set_mode(), which sends exactly one command to
	 * addr+0x8. We were writing voltage and enable and simply never
	 * sending mode, so each rail sits in whatever mode RPMh aggregation
	 * or the POR default leaves it.
	 *
	 * Why that can matter here, and why no readback would ever show it:
	 * an LDO in LPM regulates correctly at static/no load -- so a
	 * voltage readback is nominal -- but current-limits under fast
	 * transient load. A 4-lane D-PHY switching between LP and HS draws
	 * well above the 30mA hpm_min_load_uA that pmic5 LDOs use as the
	 * HPM threshold. The result is a PLL that locks, digital engines
	 * that report healthy, lanes that read as driven, and pads that
	 * cannot actually swing -- which is the exact state this driver is
	 * in.
	 *
	 * Mode value, traced end to end through mainline rather than
	 * guessed:
	 *   DTS RPMH_REGULATOR_MODE_HPM = 3
	 *   LDO:  of_map_mode -> REGULATOR_MODE_NORMAL
	 *         pmic_mode_map_pmic5_ldo[NORMAL]  = PMIC5_LDO_MODE_HPM  = 7
	 *   SMPS: of_map_mode -> REGULATOR_MODE_FAST
	 *         pmic_mode_map_pmic5_smps[FAST]   = PMIC5_SMPS_MODE_PWM = 7
	 * Both regulator classes land on 7, so one value covers all three
	 * rails (ldoe1, ldoe3 are LDOs; smpg3 is an SMPS).
	 *
	 * Sent BEFORE enable, matching the core's own ordering (constraints
	 * are applied at registration, before any consumer enables).
	 *
	 * NOTE: RPMh aggregates votes across masters. If a rail is already
	 * HPM by someone else's vote this write is a no-op, so "no change"
	 * here does not by itself exonerate the supply.
	 */
	ret = rsc_send_active_write(addr + 0x8 /* RPMH_REGULATOR_REG_VRM_MODE */,
				     7 /* PMIC5_{LDO_MODE_HPM,SMPS_MODE_PWM} */);
	if (ret)
		return ret;

	return rsc_send_active_write(addr + 0x4 /* RPMH_REGULATOR_REG_ENABLE */, 1);
}

/*
 * Status relay: this board has no working UART/console access during
 * U-Boot's own boot stage, so there's no way to see log_debug() output
 * from a probe failure. Instead, each stage's return code is written
 * to a fixed physical address (inside the same CONFIG_PRE_CON_BUF_ADDR
 * region already used/verified safe by the platform's own pre-console
 * buffering) that arch/arm/mach-snapdragon/board.c's ft_board_setup()
 * relays into a /chosen property on whichever boot actually reaches
 * Linux -- readable via /proc/device-tree/chosen/sheng,mdss-status
 * with no /dev/mem restrictions. 5 slots, one per stage below;
 * SHENG_MDSS_STATUS_NOT_REACHED marks a stage that never ran.
 */
#define SHENG_MDSS_STATUS_ADDR		(CONFIG_PRE_CON_BUF_ADDR + 0x3000)
#define SHENG_MDSS_STATUS_NOT_REACHED	0x7fffffff

enum {
	SHENG_MDSS_STATUS_MDSS_RESET,
	SHENG_MDSS_STATUS_BCM_MM0,
	SHENG_MDSS_STATUS_MMCX,
	SHENG_MDSS_STATUS_GDSC,
	SHENG_MDSS_STATUS_DISPCC,
	SHENG_MDSS_STATUS_DSI0_PHY,
	SHENG_MDSS_STATUS_DSI1_PHY,
	SHENG_MDSS_STATUS_DSI_PANEL,
	SHENG_MDSS_STATUS_DPU,
	SHENG_MDSS_STATUS_COUNT,
};

static void sheng_mdss_status_set(unsigned int stage, int ret)
{
	volatile int *slots = (volatile int *)(uintptr_t)SHENG_MDSS_STATUS_ADDR;

	if (IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
		slots[stage] = ret;
		sheng_mdss_breadcrumb_flush(SHENG_MDSS_STATUS_ADDR + stage * sizeof(*slots),
					     sizeof(*slots));
	}
}

#define SM8550_MDSS_WRAPPER_BASE	0x0ae00000
/* Scratch DRAM for sheng_mdss_capture_state(), clear of the pre-console
 * buffer regions already in use at CONFIG_PRE_CON_BUF_ADDR + 0x3000.. */
#define SHENG_MDSS_CAPTURE_ADDR		0x82000000
#define SM8550_MDSS_BASE		0x0ae00000
#define SM8550_MDSS_DPU_BASE		0x0ae01000

/* ROOT CAUSE FOUND (SPEC.md task #5 log): dsi_host.c's dsi_get_version()
 * comment, verbatim: "From DSI6G(v3), addition of a 6G_HW_VERSION
 * register at offset 0 makes all other registers 4-byte shifted down."
 * SM8550 is DSI6G -- confirmed by the driver's own MSM_DSI_VER_MAJOR_6G
 * checks throughout dsi_host.c, and by dsi.xml documenting TWO
 * different registers at offset 0x00000: "CTRL" (the generic/older
 * register map dsi.xml also carries) and "6G_HW_VERSION" (MAJOR
 * bits31-28, MINOR bits27-16). Every register offset this driver has
 * ever used (CTRL, VID_CFG0/1, TRIG_CTRL, DMA_BASE/LEN, LANE_CTRL,
 * LANE_SWAP_CTRL, CLK_CTRL, RESET, CMD_CFG0/1, CMD_MODE_MDP_CTRL2,
 * LP/HS_TIMER_CTRL, RDBK_DATA, ACK_ERR_STATUS, TIMEOUT_STATUS,
 * ACTIVE_H/V/TOTAL/HSYNC/VSYNC_HPOS/VPOS, EOT_PACKET_CTRL,
 * CLKOUT_TIMING_CTRL) was taken directly from dsi.xml's unshifted
 * offsets -- meaning every single one of them has been off by 4 bytes
 * this entire project. dsi_write()/dsi_read() apply the shift once, at
 * probe time, by baking DSI_6G_REG_SHIFT (dsi_cfg.h, .io_offset) into
 * ctrl_base itself -- msm_host->ctrl_base = ioremap(...) + io_offset.
 * Replicated here the same way: shift baked into the base address
 * constant, so every existing offset in sheng_mdss_hw.zig (already
 * matching dsi.xml exactly) now resolves correctly without needing to
 * touch every individual offset. This explains EVERYTHING: our CTRL
 * writes were landing on the real, read-only 6G_HW_VERSION register
 * (hence the unconditional, from-the-first-write rejection -- MAJOR=2,
 * MINOR=7 decodes cleanly from 0x20070000, matching a real HW version
 * register far better than it ever matched CTRL's documented fields),
 * while VID_CFG0/LANE_CTRL/etc's "live-stolen" values, read via devmem
 * at the SAME unshifted offsets we were using, were actually reading
 * whatever real register sits 4 bytes before the one we intended --
 * meaning even those "confirmed correct" values were never actually
 * verified against the register we meant to check. This is the single
 * root cause underlying the DSI host command/BTA path's complete
 * silence all session; the DPU/PHY/DISPCC/GDSC/regulator paths are
 * unaffected (different register blocks, no such HW_VERSION insertion
 * documented for those). */
#define DSI_6G_REG_SHIFT		4
#define SM8550_MDSS_DSI0_BASE		(0x0ae94000 + DSI_6G_REG_SHIFT)
#define SM8550_MDSS_DSI0_PHY_BASE	0x0ae95000
#define SM8550_MDSS_DSI1_PHY_BASE	0x0ae97000
#define SM8550_MDSS_DSI1_BASE		(0x0ae96000 + DSI_6G_REG_SHIFT)
#define SM8550_DISPCC_BASE		0x0af00000

/* ROOT CAUSE FOUND (SPEC.md task #5 log): 0xa0100000/0xa0200000 (the
 * old addresses here) sit squarely inside adspslpi_mem, the Audio DSP
 * remoteproc's own `no-map` reserved-memory carveout (devicetree:
 * adspslpi-region@9ea00000, reg = <0 0x9ea00000 0 0x4680000>, i.e.
 * 0x9ea00000-0xa3080000) -- confirmed live via a running kernel's own
 * /proc/iomem, which shows exactly "9ea00000-a307ffff :
 * 6800000.remoteproc adspslpi-region@9ea00000" nested under a
 * "reserved" span, and confirmed via a genuine SIGBUS from `devmem` on
 * 0xa0200000 post-boot (no-map means Linux never maps it into the
 * linear map at all -- a completely different failure mode than the
 * ordinary /dev/mem permission-denied case). This driver has been
 * writing its entire framebuffer directly into the ADSP's private
 * firmware memory this whole time -- a different subsystem entirely,
 * whose remoteproc firmware loader can and likely does stomp on this
 * region independent of anything the display pipeline does. This is
 * very likely the real reason nothing has ever rendered, despite every
 * DSI/DPU register-level fix confirmed correct via live comparison
 * (D-PHY timing, VID_CFG, LANE_CTRL, CTL_FLUSH bit assignments all
 * verified byte-for-byte against a working kernel). Moved into
 * 0xa3080000-0xccd00000 ("a3080000-cccfffff : System RAM" in a live
 * kernel's own /proc/iomem, ~700MB, genuinely free, no reserved-memory
 * node covers any of it) -- comfortably above where kernel_addr_r
 * (0x83000000), fdt_addr_r (0x86000000), and ramdisk_addr_r
 * (0x87100000) load later in board_late_init.
 *
 * MOVED to the HIGH DRAM bank (SPEC.md task #5 log): a real ARM LPAE
 * page-table walk of the exact context bank the WORKING Linux system
 * is using right now (TTBR0 read live off /dev/mem, strict-devmem
 * temporarily disabled in the kernel build to allow it) resolved
 * Linux's own dma_base=0x1000 IOVA to physical 0x887368000 -- deep in
 * the HIGH bank (0x880000000+, where /proc/iomem also shows this
 * exact kernel's own "Kernel code" living, at ~0x9e6c00000), nowhere
 * near this low <4GB bank at all. DMA_BASE is a plain 32-bit register
 * (dsi.xml's reg32, and the real msm_dsi_host_cmd_xfer_commit()'s own
 * `u32 dma_base` parameter) -- it can never express a high-bank
 * address directly, which is *why* Linux relies on real SMMU
 * translation for this stream instead of a raw physical pointer.
 * Every SMMU configuration this driver has tried (original firmware
 * TRANS/CB, our BYPASS, disabled-S1 passthrough, and a genuine
 * enabled-S1 identity mapping matching Linux's own live SCTLR/TCR
 * exactly) targeted this LOW bank and produced the identical
 * unchanging hang every time -- the one variable never tested was
 * whether the interconnect/NoC routes this master to the low bank at
 * all, independent of SMMU validity. Moved to 0x8bb500000 (a real,
 * unreserved System RAM window confirmed via the same live
 * /proc/iomem dump, comfortably clear of the kernel/reserved region
 * at 0x9b6c00000+) with a genuine page-level (not block-level) SMMU
 * mapping from IOVA 0x1000 -- matching Linux's own exact IOVA choice
 * -- built in smmuBypassMdssStream()'s replacement. */
/* DMA-CONTENT TEST (SPEC.md task #5 log). Everything about the transmit
 * path is now proven good EXCEPT what the command DMA actually fetches:
 * lane activity measured 241/256 against Linux's 244/256, FIFO_STATUS is
 * structurally healthy, every register in both PHYs and the DSI host
 * matches, and DCS reads provably work on this link (Linux gets 0x9e).
 * A DMA that fetches the WRONG BYTES produces exactly this: lanes drive,
 * FIFO flows, no error anywhere, and the DDIC discards every packet.
 *
 * The high-bank choice above was correct reasoning at the time -- but its
 * evidence against the low bank was "the identical unchanging hang", and
 * that symptom is gone (retries=0, panel=0, DMA completes). Meanwhile the
 * framebuffer at 0xa3200000 lives in the LOW bank and the SSPP provably
 * fetches it through this very context bank (FSR/FAR translate cleanly),
 * so low-bank translation is demonstrably working now in a way it was not
 * when that call was made.
 *
 * So move the command buffer into the identity-mapped 1GB block that the
 * SSPP already validates, making IOVA == PA and removing the 3-level
 * page-walk from the equation entirely. One variable.
 *   commands start landing -> the IOVA 0x1000 / high-bank path was broken
 *     and this is the bug.
 *   no change -> the DMA fetch is exonerated and the fault is in the
 *     packet content or framing, not in addressing.
 * Revert to 0x8bb500000 if this shows nothing; see the note above for why
 * that address mirrors Linux. */
#define SHENG_MDSS_DSI_DMA_SCRATCH	0xa3100000

/* 24.8MB (3048*2032*4 XRGB8888), starting 1MB above
 * SHENG_MDSS_DSI_DMA_SCRATCH, ending ~0xa4b10000 -- comfortably within
 * the same free System RAM span, well clear of the next reserved
 * region (0xccd00000, rmtfs_mem). See SHENG_MDSS_DSI_DMA_SCRATCH's
 * comment for why this moved from its old 0xa0200000. */
/* ALIGN(3048, 32) * 4 bytes -- the stride sheng_mdss_dpu_start()
 * programs into SSPP_SRC_YSTRIDE0. */
#define SHENG_MDSS_FB_STRIDE		12288
#define SHENG_MDSS_FB_ADDR		0xa3200000

/* 144Hz mode, xiaomi,sheng-nt36532e panel. Confirmed against the live
 * DPU crtc-0 modeline AND panel-novatek-nt36532e.c's sheng_tianma_modes[]
 * -- see SPEC.md. */
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
extern int sheng_mdss_dispcc_init_pll0_only(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_ahb(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_mdp(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_mdp_rcg_only(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_no_mdp_branch(unsigned long dispcc_base);
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
extern long long sheng_mdss_dsi_read_dcs_reg_max(unsigned long dsi0_base,
						 unsigned long dma_scratch,
						 unsigned char reg, unsigned char maxsz);
extern long long sheng_mdss_dsi_read_dcs_reg(unsigned long dsi0_base,
					     unsigned long dma_scratch, unsigned char reg);
extern int sheng_mdss_dsi_exit_sleep_only(unsigned long dsi0_base, unsigned long dsi1_base,
					   unsigned long dma_scratch);
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
extern int sheng_mdss_dsi_all_pixels_on(unsigned long dsi0_base,
					unsigned long dsi1_base,
					unsigned long dma_scratch);
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

static void sheng_mdss_final_dump(void);
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

/* Called from board.c at the very end of misc_init_r(), AFTER the
 * backlight bring-up's own 5s visual hold -- gives the picture time to
 * actually be seen before tearing the pipeline down cleanly right
 * before U-Boot jumps into Linux.
 *
 * Full reverse of sheng_mdss_probe()'s own setup, in the mirror order
 * (panel first, hardware last), per the "U-Boot must clean up after
 * itself" principle: a bootloader that leaves the display pipeline
 * mid-stream and hands off to Linux with zero cleanup is asking for
 * exactly the class of "framebuffer is not in virtual address space"
 * GEM/vmap corruption seen earlier, even if that specific message
 * turned out to be cosmetic -- there's no reason to leave DPU/DSI/PHY
 * state dangling across the handoff regardless. No-op if
 * CONFIG_VIDEO_SHENG_MDSS isn't even enabled (sheng_mdss.c/
 * sheng_mdss_hw.o aren't even compiled in that case). */
/* HANDOFF TEST (SPEC.md task #5 log): leave the panel exactly as this
 * driver configured it, instead of returning it to cold state.
 *
 * Pairs with a kernel built to SKIP its own panel bring-up
 * (SHENG_NOPREP). Together they answer the one question U-Boot cannot ask
 * directly -- this panel implements no DCS reads, so the DDIC cannot be
 * interrogated -- namely: does our 87-command init + PPS actually
 * configure the panel?
 *
 *   Linux renders -> our panel init WORKS, and the fault is confined to
 *     our video path.
 *   Linux black   -> our panel init never takes, and every video-path
 *     measurement this session was made against an unconfigured panel.
 *
 * The first attempt at this test left the teardown ENABLED, which sends
 * Display Off + Sleep In and then asserts reset and drops avdd/avee. That
 * guarantees Linux sees a cold panel no matter how well our init worked,
 * so the result was meaningless. This flag is the fix.
 *
 * Diagnostic only: with this set, U-Boot hands Linux a live panel and a
 * still-configured DPU/DSI, which is exactly what the teardown exists to
 * avoid. Set back to 0 for normal boots.
 */
#define SHENG_GRACEFUL_RESTART 1
#define SHENG_REPLAY_BRINGUP 0 /* WITHDRAWN: the captured trace contains deferred-probe retries (bring-up runs 3x, early passes end with PLL bias disabled), so a verbatim replay does not produce a coherent end state -- measured phy0=0x801fff7c7ebc7e1d, zero frames. Our own bring-up matches live exhaustively; use it. */
/* PAIRED WITH THE KERNEL'S SHENG_PRE PROBE (SPEC.md task #5 log).
 *
 * Set to 1 so the panel is handed to Linux still powered and un-reset,
 * preserving whatever DCS state U-Boot actually managed to write. Yes,
 * skipping the teardown breaks Linux's own render -- that is fine and
 * irrelevant here, because the instrument is a DCS READ of the panel's
 * power mode taken before Linux resets it, not what appears on screen.
 * That is precisely what makes this test unconfounded where the old
 * SHENG_NOINIT one was not: it never looks at the display.
 *
 * Set back to 0 once the answer is in. */
/* The SHENG_HOSTDUMP/SHENG_PHYDUMP experiment this enabled is DONE, and it
 * came back negative in a useful way: across all 192 DSI host registers and
 * 128 PHY registers on both links, the state inherited before a FAILING
 * bring-up was byte-identical to the state inherited before a SUCCEEDING
 * one -- and identical again whether it was inherited from U-Boot or from
 * Linux itself. The dump point (just before dsi_timing_setup) sits after
 * pm_runtime/GDSC and link-clock enable, which normalises the block, so it
 * cannot see the difference it was built to find. Restored to 0 so Linux
 * gets a proper hand-off and renders again. */
#define SHENG_SKIP_TEARDOWN 0

/* Forward-bisect master switch -- see its block comment at the top of
 * sheng_mdss_probe(). 1 = probe touches no hardware at all and ABL's
 * live display is handed straight through. Requires
 * SHENG_SKIP_TEARDOWN=1 above. Set both back to 0 for normal boots. */
#define SHENG_MDSS_DO_NOTHING 0

/* b108: hand the panel over initialised but with NO video streaming. */
#define SHENG_SKIP_DPU_START 0

/* b2xx: send exactly one DCS write and look for its effect. */
#define SHENG_WRITE_PROBE 0

/* Send the panel init sequence AFTER dpu_start(), so the DCS commands go
 * out onto an already-streaming link the way the kernel does it. See the
 * call site after sheng_mdss_dpu_start() for the full reasoning.
 *
 * TESTED AND REVERTED -- it is strictly worse (b71 and b72):
 *
 *              init BEFORE dpu   init AFTER dpu
 *   sheng.panel        0          -10000 (command #0 failed)
 *   sheng.rd1   0x01F7_0000       -1 (max-pkt-size DMA failed)
 *   sheng.lanact   241/256        0/256
 *
 * b72 additionally fixed dsiWait4VideoEngBusy() to wait on the real
 * VIDEO_DONE interrupt instead of a bit that never clears, and the result
 * was byte-identical -- so landing inside BLLP is not what the command
 * engine is missing.
 *
 * Ordering is dpu_start -> panel_init -> lane sampling, so the failed
 * command comes first and WEDGES the host: video then never reaches the
 * lanes either (0/256), whereas the old order's vacuous init "success"
 * at least left the host streaming (241/256). Both end black, but the
 * pre-DPU order is the better baseline and keeps Linux rendering.
 *
 * Kept as a flag rather than deleted: it is still the ordering the kernel
 * uses, so if the command path is ever fixed this is worth retrying. */
/* RE-ENABLED on hard evidence (b77 per-command trace).
 *
 * LANE_STATUS sampled between DMA trigger and completion, over all 100
 * commands of a boot:
 *     mid LANE = 0x1f1f (every lane in STOPSTATE) on 98 of 100
 *     mid LANE = 0x1f00 (data lanes DRIVING)      on 2 of 100
 * and those 2 are exactly the commands where STATUS0 had bit 3 set --
 * VIDEO_MODE_ENGINE_BUSY. Every one of them reported ret=0 with ACK_ERR=0.
 *
 * So commands only reach the wire while the video engine is streaming.
 * With panel_init before dpu_start there is no video, the lanes never
 * leave stop state, and all 87 init commands are silently discarded --
 * which is precisely the "DMA succeeds, panel receives nothing, every
 * register still correct" contradiction this driver has had all along.
 *
 * Paired with the dsiWait4VideoEngBusy() mask fix; b71/b72 tried this
 * ordering and died at command 0 because that wait could never see
 * VIDEO_DONE with the interrupt masked off. */
/* Back to 0. b78 tried this ordering WITH the dsiWait4VideoEngBusy() mask
 * fix and panel_init still aborted after ~3 commands (12 failed attempts,
 * 4 retries each), ACK_ERR=0 throughout.
 *
 * And the b77 reasoning that motivated it was wrong: the two commands
 * showing mid LANE=0x1f00 were the dual DCS read running after dpu_start,
 * so LANE_STATUS at that sample point was reporting VIDEO traffic on the
 * lanes, not command transmission. b78 falsified it outright -- 12
 * commands ran with VIDEO_MODE_ENGINE_BUSY set and the lanes still read
 * 0x1f1f.
 *
 * What survives: with the mask fix the BLLP wait genuinely works now, and
 * commands issued inside BLLP time out. That is a different failure from
 * the silent vacuous success, and a sharper one -- Linux issues commands
 * in exactly that window and succeeds. */
/* CONFIRMED FAILING -- do not re-enable without new information.
 *
 * Tested three times now (b71, b78, b88). b88 was a deliberate retry after
 * b87 exposed this driver's documented intermittent fault live, which made
 * b78's single failing boot untrustworthy. b88 reproduced it exactly on a
 * clean boot:
 *
 *     sheng.panel = -10000   (command #0 failed)
 *     16 commands, 12 of them ETIMEDOUT (r=110)
 *     sheng.lanact = 0       (video never reaches the lanes afterwards)
 *
 * versus the pre-DPU ordering on the same build: panel_init_ret = 0, 100
 * commands, zero timeouts.
 *
 * So it is real, and it is a SPECIFIC divergence from Linux worth keeping
 * in view: our command DMA transmits fine with no video running (proven --
 * the 132-byte PPS takes 114us at LP escape rate) but times out the moment
 * the DPU is streaming. Linux issues its commands into exactly that window
 * and succeeds. TRIG_CTRL matches bit-for-bit (0x80001004, including
 * BLOCK_DMA_WITHIN_FRAME), the INTF timing/porches are identical, and
 * dsiWait4VideoEngBusy() now genuinely waits on VIDEO_DONE. Whatever lets
 * the kernel interleave commands with live video, we have not found it. */
/* CONFIRMED BROKEN (b71/b78/b88), and b90 captured WHY.
 *
 * With the DPU streaming before panel_init, the DSI video engine goes busy
 * but never completes a frame:
 *
 *     vwait: waited_us=70000 VIDEO_DONE=0 intr=02220200 st0=0b lane=00001f1f
 *     series(st0/fifo/lane): 0b/55551011/1f1f  x10, stable over 10ms
 *
 * MASK_VIDEO_DONE is enabled and VIDEO_DONE never fires in 70ms -- about
 * ten frame periods at 144Hz. LANE_STATUS bit4 (CLKLN_STOPSTATE) is SET,
 * so the CLOCK LANE never enters HS; the working ordering reads 0x1f00
 * with that bit clear. FIFO_STATUS goes 0x11111210 (healthy) -> 0x55551011,
 * i.e. the video FIFO backs up and stops draining.
 *
 * So the command timeouts are a CONSEQUENCE, not the cause: the video
 * engine stalls with a parked clock lane, no frame ever completes, the
 * BLLP wait burns its full 70ms, and every command then times out.
 *
 * The real finding: video only streams if the DCS init ran FIRST. Something
 * in the panel-init sequence is what gets the clock lane into HS. That is
 * the specific divergence from Linux worth chasing -- the kernel streams
 * video and injects commands into it without needing that ordering. */
#define SHENG_PANEL_AFTER_DPU 0

void sheng_mdss_teardown(void)
{
	if (!IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS))
		return;

	if (SHENG_SKIP_TEARDOWN)
		return;

	/* DIAGNOSTIC TEST RESULT (SPEC.md task #5 log): temporarily
	 * disabling this teardown reproduced the exact same silent
	 * "backlight only, no picture" Linux symptom -- confirmed via dmesg
	 * that NONE of arm-smmu context faults, dsi_tx_timeout/DCS errors,
	 * or PLL lock timeouts appear. msm_dpu/msm_dsi/adreno gpu all bind
	 * and initialize cleanly regardless. Whatever U-Boot leaves behind
	 * that disrupts Linux's render is silent at the kernel fault/
	 * timeout level -- not a logged hardware fault. This teardown is
	 * the confirmed, working fix; do not disable it again without a
	 * specific new hypothesis to test. */

	/* 1. Panel: Display Off (0x28) + Sleep In (0x10) over the DSI
	 * command channel, while the host/PHY can still carry commands. */
	sheng_mdss_dsi_panel_sleep(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_DSI_DMA_SCRATCH);

	/* 2. Hardware: DPU timing engines + CTL_START/FLUSH cleared, both
	 * DSI PHYs powered down (lanes disabled, REFGEN vote dropped),
	 * every DSI/MDP DISPCC branch gated off, MDSS core reset pulsed
	 * once more. */
	sheng_mdss_full_teardown(SM8550_MDSS_DPU_BASE,
				  SM8550_MDSS_DSI0_PHY_BASE, SM8550_MDSS_DSI1_PHY_BASE,
				  SM8550_DISPCC_BASE);

	/* 3. Panel back to its cold-boot state: reset line asserted
	 * (active-low, physical LOW), avdd/avee bias rails dropped -- the
	 * exact inverse of sheng_mdss_panel_power_and_reset(), so Linux's
	 * own nt36532e_prepare() sees a genuinely fresh, unpowered panel
	 * and re-runs its full init sequence rather than finding a panel
	 * it thinks is already on. */
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* logical 1 = physical LOW: reset asserted */
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 0);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 0);
}

static int sheng_mdss_probe(struct udevice *dev)
{
	struct sheng_mdss_priv *priv = dev_get_priv(dev);
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);
	struct video_priv *uc_priv = dev_get_uclass_priv(dev);
	int ret;

	/* ABL HANDOFF STATE, SAFELY SEQUENCED (SPEC.md task #5 log).
	 *
	 * sheng.env's own notes reference the `cont_splash` region: ABL uses
	 * CONTINUOUS SPLASH, so it hands over with DPU/DSI/PHY/panel all
	 * actively running. For the first milliseconds of this function, this
	 * exact silicon is correctly driving this exact panel -- and the
	 * cold-start block immediately below destroys it. That state has never
	 * been measured, and it is the only known-good configuration of this
	 * hardware that exists at the point in boot where we actually run.
	 *
	 * THE SEQUENCING IS THE WHOLE POINT. A previous attempt put these
	 * reads at the very top of probe() and hung the board outright -- no
	 * backlight, no boot. MDSS register reads are only safe once MDSS_GDSC
	 * is powered AND the DISPCC AHB config clock is running; at the top of
	 * probe neither is guaranteed, so the AHB slave never acks and the CPU
	 * wedges. Bring up exactly those two things first -- and nothing else,
	 * in particular NOT dispcc_init(), whose mdssCoreBcrReset() would wipe
	 * the very state we are trying to sample -- then read.
	 *
	 * GDSC enable is idempotent if ABL already left it on, and
	 * sheng_mdss_dispcc_ahb_only() parents AHB from XO, so neither
	 * disturbs ABL's DSI/PHY configuration.
	 */
	ret = sheng_mdss_gdsc_enable(SM8550_DISPCC_BASE);
	BBS("abl_gdsc_enable_ret", ret);
	env_set_hex("sheng_mdss_abl_gdsc", (unsigned long)ret);
	if (!ret) {
		ret = sheng_mdss_dispcc_ahb_only(SM8550_DISPCC_BASE);
		if (!ret) {
			env_set_hex("sheng_mdss_abl1",
				    (unsigned long)sheng_mdss_abl_state1(
					    SM8550_MDSS_DSI0_BASE));
			env_set_hex("sheng_mdss_abl2",
				    (unsigned long)sheng_mdss_abl_state2(
					    SM8550_MDSS_DSI0_BASE,
					    SM8550_MDSS_DSI1_BASE));
			env_set_hex("sheng_mdss_abl3",
				    (unsigned long)sheng_mdss_abl_state3(
					    SM8550_MDSS_DSI0_PHY_BASE,
					    SM8550_MDSS_DSI1_PHY_BASE));
		}
	}

	/* COLD-START THE CONTROLLER, NOT JUST THE POWER DOMAIN (SPEC.md task
	 * #5 log). THE MOST DIRECTLY EVIDENCED CHANGE IN THIS WHOLE EFFORT.
	 *
	 * Measured this boot, with SHENG_SKIP_TEARDOWN=1 so U-Boot handed
	 * Linux a still-running display:
	 *
	 *   [ 0.915] SHENG_RD: get_power_mode ret=-61   <- Linux's FIRST
	 *                                                  bring-up FAILED
	 *   [118.078] SHENG_RD: get_power_mode ret=0 val=0x9e  <- after a
	 *                                                  blank/unblank it
	 *                                                  SUCCEEDED
	 *
	 * Same kernel, same panel, same code path -- the only difference is
	 * that the second bring-up started from Linux's own full disable.
	 * Linux layered on top of a live controller cannot talk to the panel;
	 * Linux starting from a proper power-down can. That is EXACTLY our
	 * situation one level up: ABL hands us a live, configured, probably
	 * still-scanning controller (sheng.ablgpio confirms reset deasserted
	 * with both bias rails high) and we build on top of it.
	 *
	 * The existing cold-start below collapses the GDSC and pulses
	 * DISP_CC_MDSS_CORE_BCR, which is not the same thing. It never stops
	 * the DPU timing engines, never powers down the DSI PHYs, never gates
	 * the DISPCC branches. That is the controller half of what Linux's
	 * disable does, and it is the half we skip.
	 *
	 * We already own a proven-correct implementation of it:
	 * sheng_mdss_full_teardown() is what runs at handoff, and Linux
	 * successfully brings the display up after it on every single boot.
	 * It has simply never been run BEFORE our own bring-up.
	 *
	 * Run it here, while GDSC and the AHB clock are up so the register
	 * space is reachable, and before the GDSC collapse + core reset
	 * below. The panel is deliberately left powered: SHENG_GRACEFUL_RESTART
	 * still owns the panel-side half (bring DSI up, send Display Off +
	 * Sleep In, then power-cycle), which mirrors the panel half of Linux's
	 * disable. Together they reproduce, for our own init, the starting
	 * conditions that demonstrably make a bring-up succeed. */
	if (!ret)
		sheng_mdss_dsi_phys_off(SM8550_MDSS_DSI0_PHY_BASE,
					 SM8550_MDSS_DSI1_PHY_BASE);

	/* Earlier note kept for the record -- the failure it describes is real
	 * and is why the block above enables GDSC + AHB first (SPEC.md task #5
	 * log).
	 *
	 * A pair of sheng_mdss_abl_state1/2() calls used to sit here, reading
	 * DSI0 and DPU INTF_1 registers before anything else ran, to capture
	 * the state ABL hands over. They were justified as "pure reads of
	 * registers this driver already reads every boot". That justification
	 * was wrong: those reads are only safe once MDSS_GDSC is on and the
	 * DISPCC AHB clock is running. At the TOP of probe neither is true
	 * yet, so the AHB slave never acks and the CPU wedges -- no backlight,
	 * no boot at all, exactly the failure this file documents for the DPU
	 * register block.
	 *
	 * Reading ABL's handoff state is still a worthwhile experiment, but it
	 * has to happen after sheng_mdss_gdsc_enable() and the DISPCC AHB
	 * branch and before the cold-start teardown -- which means reordering
	 * probe, not just inserting a read. Do not re-add it here.
	 */

	/* PANEL GPIO STATE AT PROBE ENTRY, before this driver writes anything
	 * (SPEC.md task #5 log). TLMM is always clocked, so unlike the MDSS
	 * register spaces these reads are safe this early.
	 *
	 * This validates the SHENG_SKIP_PANEL_TOUCH test. That test assumes
	 * ABL hands the panel over still powered and un-reset, so its DDIC
	 * retains ABL's initialisation. If instead avdd/avee are low or reset
	 * is asserted at this point, the DDIC is dead on arrival and a black
	 * result says nothing about our video path.
	 *
	 * Packed: [63:48] GPIO133 CFG, [47:32] GPIO133 IN_OUT,
	 *         [31:16] GPIO30 IN_OUT (avdd), [15:0] GPIO31 IN_OUT (avee).
	 * Alive looks like reset IN_OUT=0x3 (driven high, deasserted) with
	 * both bias IN_OUT=0x3. */
	{
		volatile u32 *r_ctl = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * TLMM_PANEL_RESET_GPIO);
		volatile u32 *r_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_RESET_GPIO);
		volatile u32 *p_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVDD_GPIO);
		volatile u32 *n_io = (volatile u32 *)(uintptr_t)
			(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVEE_GPIO);

		env_set_hex("sheng_mdss_ablgpio",
			    (((unsigned long)(*r_ctl & 0xffff)) << 48) |
			    (((unsigned long)(*r_io & 0xffff)) << 32) |
			    (((unsigned long)(*p_io & 0xffff)) << 16) |
			    ((unsigned long)(*n_io & 0xffff)));
	}

	priv->mdss_base = dev_read_addr(dev);
	sheng_bb_init();
	BBM("probe entry");
	BBV("mdss_base", priv->mdss_base);
	if (priv->mdss_base == FDT_ADDR_T_NONE)
		return -EINVAL;

	/* FORWARD BISECT (b94) -- the strategy this driver has never tried.
	 *
	 * Every build for months has bisected BACKWARD: bring the whole
	 * pipeline up from zero, find it black, and hunt for the broken
	 * step. That search has now exhausted itself -- b92 (inherit ABL's
	 * live DDIC, send zero DCS) and b93 (DSI TPG, whole DPU bypassed)
	 * are black through two paths whose only shared element is the link
	 * itself, while every register we can compare matches live Linux.
	 *
	 * But ABL hands us a display that is ALREADY WORKING: GDSC on
	 * (sheng.gdscp reads 0xf822 at probe entry), panel powered with
	 * reset deasserted (sheng.abl = 0x03C1_0003_0003_0003), DDIC
	 * initialised, almost certainly still showing its splash. And the
	 * first thing this probe does to it is collapse that GDSC and pulse
	 * the MDSS core reset.
	 *
	 * So start from working instead. With this set, probe touches NOTHING
	 * -- no GDSC collapse, no core reset, no PHY, no DSI, no DPU, no panel
	 * -- and hands ABL's state straight through.
	 *
	 *   ABL's image stays on screen through U-Boot
	 *     -> panel, link, PHY, DSC and DPU are all provably alive, and it
	 *        is our own bring-up that destroys a working display. Bisect
	 *        FORWARD from here one step at a time until it goes black;
	 *        that step is the bug. Better still, ABL's framebuffer is
	 *        live and writable -- blitting into it is pixels TODAY,
	 *        with no bring-up at all.
	 *   Screen black even with U-Boot doing nothing
	 *     -> ABL is not driving the panel by the time we run, the
	 *        "inherit a live panel" premise behind b92/b93 is weaker
	 *        than assumed, and those two results need reinterpreting.
	 *
	 * MUST be paired with SHENG_SKIP_TEARDOWN=1: the teardown writes DPU
	 * and DISPCC registers, and with probe skipped there is no guarantee
	 * the AHB branch it needs is clocked -- that is the documented way to
	 * wedge the CPU with no backlight and no boot. Skipping it is also
	 * correct on its own terms here: Linux only ever needed our teardown
	 * because we half-configured the hardware. Touch nothing and Linux
	 * gets the pristine ABL state that debian-sheng's drm/msm booted from
	 * successfully before sheng_mdss.c existed at all. */
	if (SHENG_MDSS_DO_NOTHING) {
		BBM("DO_NOTHING: probe returning immediately, ABL state untouched");
		sheng_bb_finish();
		return 0;
	}

	for (unsigned int i = 0; i < SHENG_MDSS_STATUS_COUNT; i++)
		sheng_mdss_status_set(i, SHENG_MDSS_STATUS_NOT_REACHED);

	/* COLD-START RESET PASS (SPEC.md task #5 log): never attempted
	 * before this pass -- every prior version of this driver assumed a
	 * clean power-on-reset state and built additively on top of
	 * whatever ABL/XBL already left behind. This explicitly forces
	 * everything to a true zero state FIRST: panel bias/reset off, GDSC
	 * power domain collapsed and settled, MDSS core reset pulsed, THEN
	 * GDSC brought back up -- so the digital logic gates genuinely
	 * initialize from power-on defaults rather than whatever latent
	 * state ABL's own splash/init sequence (which very plausibly uses
	 * this exact same DPU/DSI hardware for its own boot logo) may have
	 * left mid-configured. Panel bias/reset off first, matching a real
	 * cold boot's power sequencing (panel unpowered while the
	 * controller itself resets). */
	/* GRACEFUL RESTART (SPEC.md task #5 log).
	 *
	 * Linux could not initialise this panel until U-Boot gained a proper
	 * teardown. That means Linux's init depends on its STARTING state:
	 * a panel that was told Display Off + Sleep In, then reset-asserted
	 * and unpowered. Our own init has never had that luxury -- ABL hands
	 * us a LIVE panel (measured: sheng.ablgpio showed reset deasserted
	 * with both bias rails high), still configured and probably still
	 * displaying its splash, and we yank its power with no DCS shutdown
	 * at all. A DDIC that loses power without Sleep In can latch into a
	 * state a subsequent reset does not clear.
	 *
	 * We have never been able to fix that, because by the time our DSI
	 * host is up the panel is already unpowered -- a chicken-and-egg. So
	 * break it: leave ABL's panel powered here, bring the DSI up, send it
	 * a graceful Display Off + Sleep In, and only THEN power-cycle it and
	 * run the real init. That reproduces, for our own init, exactly the
	 * starting conditions that make Linux's init work. */
	if (!SHENG_SKIP_PANEL_TOUCH && !SHENG_GRACEFUL_RESTART) {
		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* reset asserted */
		sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 0);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 0);
	}
	sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 0);
	sheng_mdss_gdsc_disable(SM8550_DISPCC_BASE);
	BBM("gdsc collapsed");
	sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 1);
	mdelay(1);

	/* msm_mdss_reset() in the real driver toggles DISP_CC_MDSS_CORE_BCR
	 * as the very first thing msm_mdss_init() does, before GDSC or any
	 * clock is even parsed -- see sheng_mdss_core_reset()'s comment in
	 * sheng_mdss_hw.zig. Never attempted before this pass; matching
	 * that exact ordering here since the DPU register bus has stayed
	 * unreachable through every power/clock/interconnect step tried
	 * so far. This is a void C ABI call (msm_mdss_reset() itself
	 * always returns 0 for a present reset line), so we still track it
	 * via the status relay to confirm it actually ran.
	 */
	sheng_mdss_core_reset(SM8550_DISPCC_BASE);
	BBM("mdss core reset pulsed");
	sheng_mdss_status_set(SHENG_MDSS_STATUS_MDSS_RESET, 0);

	/* BISECTION: reset-toggle + GDSC confirmed reaching Linux. Next:
	 * add DISPCC (PLL0 + AHB/MDP clocks) back and stop right after it,
	 * before DSI PHY.
	 */
	ret = sheng_mdss_gdsc_enable(SM8550_DISPCC_BASE);
	sheng_mdss_phy144_mark(0, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_GDSC, ret);
	if (ret) {
		log_debug("sheng_mdss: GDSC bring-up failed (%d)\n", ret);
		return ret;
	}

	/* NEW LEAD (SPEC.md task #5 log): traced the real mdp0-mem
	 * interconnect path (devicetree: &mmss_noc MASTER_MDP -> &mc_virt
	 * SLAVE_EBI1) all the way through sm8550.c's icc-rpmh node graph --
	 * qnm_mdp -> qns_mem_noc_hf -> qnm_mnoc_hf -> ... -> gem_noc
	 * (bcm_sh0) -> mc_virt (bcm_mc0) -> ebi. Both bcm_sh0 and bcm_mc0
	 * are marked .keepalive=true in the driver (a permanent non-zero
	 * RPMh floor vote regardless of what any individual master
	 * requests -- why CPU/U-Boot's own DRAM access has always worked
	 * fine, that's a completely different, always-on guarantee). The
	 * ONE BCM in the whole chain WITHOUT a keepalive floor is MM0,
	 * covering exactly qns_mem_noc_hf -- the node qnm_mdp (the DPU)
	 * sits on. bcm_mm1 doesn't apply (camera masters only, not MDP).
	 * This is the same MM0 this file's sheng_mdss_bcm_vote() was always
	 * built for (see SHENG_LOG_CMDDB_MM0_ADDR) but never actually
	 * wired into the active path -- the earlier "MMCX voting dead end"
	 * finding was about a DIFFERENT vote (MMCX power-domain corner, not
	 * this bandwidth BCM) and predates the DSI clock/VID_CFG/stride
	 * fixes, so it doesn't rule this out. Same reliability caveat as
	 * before applies (CMD_STATUS_COMPL only proves local TCS-controller
	 * acceptance, not confirmed remote RPMh execution) -- but this is a
	 * real, previously-untested gap in the actual DMA bandwidth path,
	 * not another register-content check. */
	ret = sheng_mdss_bcm_vote("MM0");
	env_set_hex("sheng_mdss_bcm_mm0", (unsigned long)ret);

	/* MMCX voting dead end (see git history/SPEC.md task #5): tried
	 * both the computed NOM corner and the sync_state-clamped MAX
	 * corner (matching the real driver's pre-sync_state behavior
	 * exactly, confirmed via live dmesg capture with rpmhpd.dyndbg=+p)
	 * -- neither fixes the MDP_CLK_CBCR disruption, despite our
	 * rsc_send_active_write() reporting success (CMD_STATUS_COMPL) in
	 * both cases. Every AP-side detail (RSC DRV-2 base, TCS offsets,
	 * tcs-config ordering, corner/level values) verified correct
	 * against the real driver source. Conclusion: CMD_STATUS_COMPL is
	 * most likely a local TCS-controller artifact confirming our
	 * command was accepted/processed by the AP-side hardware, not
	 * proof the vote actually reached and was executed by the remote
	 * RPMh/PMIC firmware -- a layer bare register pokes can't fully
	 * verify or fix without the real IRQ/wake handshake infrastructure
	 * the kernel driver sets up around this same controller. Back to
	 * the verified-safe path: skip MMCX voting and the MDP core clock
	 * branch entirely. The DSI-bypass pixel path doesn't need it. */
	/* Order-flip attempt (see SPEC.md task #5 log): I2C/GPIO ftrace
	 * proved the digital state (I2C bytes, GPIO128) is identical
	 * whether backlight works or not -- pointing at a real analog
	 * effect (inrush/UVLO trip in the KTZ8866, or a supply-rail sag)
	 * during the MDP_CLK_CBCR transition. Board.c now runs THIS video
	 * probe (full dispcc, MDP_CLK_CBCR included) BEFORE backlight
	 * init, with a settle delay after -- if the chip's boost converter
	 * has a latching fault, hitting it with the clock transient before
	 * ever powering it up, then bringing it up clean afterward with a
	 * GPIO fault-clear cycle + soft-start brightness ramp, might avoid
	 * tripping the latch in the first place. */
	/* ORDERING BUG (SPEC.md task #5 log): this call used to live ~170
	 * lines below, AFTER sheng_mdss_dsi_panel_init(). GCC_DISP_HF_AXI_
	 * CLK is the AXI *data* path clock -- the bus the DSI command DMA
	 * engine uses to fetch its packet out of DRAM. Gated, that read
	 * never returns: the engine latches CMD_MODE_DMA_BUSY and holds it
	 * forever with nothing to show for it.
	 *
	 * That is exactly what STATUS/FIFO forensics show. FIFO_STATUS on
	 * timeout reads 0x11111010 -- DLN0-3_HS_FIFO_EMPTY and DLN0_LP_
	 * FIFO_EMPTY set, and CMD_DMA_FIFO_RD_WATERMARK_REACH(8) / WR_
	 * WATERMARK_REACH(9) / UNDERFLOW(10) all CLEAR -- while DLN0_PHY_
	 * ERR (0x00088888) has every defined error bit clear. Not a
	 * stalled transmitter (that would leave the HS FIFOs full): the
	 * engine never fetched a single byte, and never errored, because
	 * its AXI read had no clock to complete on.
	 *
	 * Linux never has this problem because msm_mdss_enable() brings
	 * this up in the SAME clk_bulk as DISP_CC_MDSS_AHB_CLK/MDP_CLK for
	 * the mdss wrapper -- before any child DSI device does anything.
	 * See the comment on the function itself. Enable it here, with the
	 * rest of the MDSS clock bulk, which is where it always belonged. */
	sheng_mdss_gcc_disp_hf_axi_clk_enable();

	ret = sheng_mdss_dispcc_init(SM8550_DISPCC_BASE);
	BBS("dispcc_init_ret", ret);
	BBB("DISPCC after init", SM8550_DISPCC_BASE, 0x000, 64);
	sheng_mdss_phy144_mark(1, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DISPCC, ret);
	/* UBWC block config, immediately after the MDSS core reset inside
	 * dispcc_init() wipes it -- see sheng_mdss_ubwc_init()'s comment.
	 * Must precede any DSI/DPU programming, matching msm_mdss_enable(). */
	sheng_mdss_ubwc_init(SM8550_MDSS_BASE);
	env_set_hex("sheng_mdss_dispcc", (unsigned long)ret);
	if (ret)
		return ret;

	/* Lead #2 (SPEC.md task #5 log): sheng_mdss_dispcc_init() only
	 * confirms clkBranchEnable()'s CBCR halt-poll succeeded, never
	 * that the RCG's CFG register (src_sel/div) actually landed as
	 * rcg2ConfigureHidOnly() intended. Read it back: MDP_CLK_SRC_CMD_RCGR
	 * = 0x80d8 (dispcc_base-relative), CFG at +0x4. Expect src_sel=1
	 * (P_DISP_CC_PLL0_OUT_MAIN, bits [10:8]) and src_div=5 (2*3-1 for
	 * /3, bits [4:0]) if our 514MHz MDP-clock programming actually took.
	 */
	sheng_mdss_log_reset();
	{
		volatile u32 *mdp_rcg_cfg =
			(volatile u32 *)(uintptr_t)(SM8550_DISPCC_BASE + 0x80d8 + 0x4);
		sheng_mdss_log(SHENG_LOG_MDP_RCG_CFG_READBACK, *mdp_rcg_cfg);
	}

	/* Bisection resolved: MDP_CLK_CBCR's branch enable was the sole
	 * backlight disruptor, and it's now skipped above
	 * (sheng_mdss_dispcc_init_no_mdp_branch). Proceeding into DSI PHY/
	 * panel init/test patch for real now. */

	/* Real analog supply rails for the DSI PHYs/hosts/panel logic --
	 * see sheng_mdss_regulator_vote()'s comment. Both DSI PHYs share
	 * vreg_l1e_0p88 (0.88V), both DSI hosts share vreg_l3e_1p2 (1.2V),
	 * and the panel's own vddio is vreg_s3g_0p7 -- live-confirmed on a
	 * working Linux boot at 880000uV/1200000uV/600000uV respectively.
	 * Voted here, before anything that depends on them, since none of
	 * these three has regulator-boot-on/always-on in the DTS. */
	/* First attempt guessed "l1e"/"l3e"/"s3g" and then "L1E"/"L3E"/
	 * "S3G" (matching the DTS regulator label convention) -- both
	 * wrong, -ENODEV. Read the real cmd-db contents live off a working
	 * boot via /sys/kernel/debug/cmd-db (confirmed accessible,
	 * unlike the no-map cmd-db reserved-memory region itself) --
	 * actual naming convention is "ldo<pmic-letter><index>"/
	 * "smp<pmic-letter><index>", e.g. "ldoe1", "ldoe3", "smpg3", not
	 * the DTS label's "l1e"/"s3g" shorthand at all. vreg_l1e_0p88 =
	 * LDO1 on PMIC E = "ldoe1"; vreg_l3e_1p2 = LDO3 on PMIC E =
	 * "ldoe3"; vreg_s3g_0p7 = SMPS3 on PMIC G = "smpg3". */
	ret = sheng_mdss_regulator_vote("ldoe1", 880);
	env_set_hex("sheng_mdss_vreg_l1e", (unsigned long)ret);
	ret = sheng_mdss_regulator_vote("ldoe3", 1200);
	env_set_hex("sheng_mdss_vreg_l3e", (unsigned long)ret);
	ret = sheng_mdss_regulator_vote("smpg3", 600);
	BBS("regulator_votes_ret", ret);
	sheng_mdss_phy144_mark(2, SM8550_MDSS_DSI0_PHY_BASE);
	env_set_hex("sheng_mdss_vreg_s3g", (unsigned long)ret);

	/* Dual-DSI split-link panel: DSI0 is master (drives its own PLL),
	 * DSI1 is slave (sources its bit clock from DSI0 over
	 * qcom,sync-dual-dsi) -- see sheng_mdss_dsi_phy_init()'s comment
	 * in sheng_mdss_hw.zig. Both must succeed. */
	/* VERBATIM REPLAY of the kernel's bring-up write sequence -- see
	 * sheng_mdss_replay_bringup()'s comment. Replaces our own PHY reset,
	 * per-PHY init, dual PLL start and DSI host bring-up with the exact
	 * 347 writes the working kernel issues, in order. Everything before
	 * this (GDSC, DISPCC, UBWC, regulators) and after it (DSI link clocks,
	 * panel power/reset, DCS init, DPU) is unchanged. */
	if (SHENG_REPLAY_BRINGUP) {
		/* Phase 0: PHY writes only. The DSI host half must wait until
		 * the link clocks exist -- see the phase function's comment. */
		sheng_mdss_replay_bringup_phase(0,
						 SM8550_MDSS_DSI0_PHY_BASE,
						 SM8550_MDSS_DSI1_PHY_BASE,
						 SM8550_MDSS_DSI0_BASE,
						 SM8550_MDSS_DSI1_BASE);
		ret = sheng_mdss_dispcc_dsi_clks_init(SM8550_DISPCC_BASE);
		env_set_hex("sheng_mdss_replay", (unsigned long)ret);
		if (ret)
			return ret;
		/* Phase 1: DSI host writes, now that byte/pclk/esc are live. */
		sheng_mdss_replay_bringup_phase(1,
						 SM8550_MDSS_DSI0_PHY_BASE,
						 SM8550_MDSS_DSI1_PHY_BASE,
						 SM8550_MDSS_DSI0_BASE,
						 SM8550_MDSS_DSI1_BASE);
		goto bringup_done;
	}

	sheng_mdss_dsi_reset_both_phys(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);
	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI0_PHY_BASE, true);
	BBS("phy0_init_ret", ret);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI0_PHY, ret);
	env_set_hex("sheng_mdss_dsi0_phy", (unsigned long)ret);
	if (ret)
		return ret;

	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI1_PHY_BASE, false);
	BBS("phy1_init_ret", ret);
	sheng_mdss_phy144_mark(3, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI1_PHY, ret);
	env_set_hex("sheng_mdss_dsi1_phy", (unsigned long)ret);
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
	env_set_hex("sheng_mdss_phy_start", (unsigned long)ret);
	BBS("phy_start_dual_ret", ret);
	BBR("PHY0 STATUS", SM8550_MDSS_DSI0_PHY_BASE, 0x140);
	BBR("PHY1 STATUS", SM8550_MDSS_DSI1_PHY_BASE, 0x140);
	sheng_mdss_phy144_mark(4, SM8550_MDSS_DSI0_PHY_BASE);
	if (ret)
		return ret;

	/* THE REAL MISSING PIECE (SPEC.md task #5 log): live clk_summary
	 * from a working Linux boot showed disp_cc_mdss_{byte,pclk,esc}
	 * {0,1}_clk (and byte{0,1}_intf_clk) all genuinely enabled and
	 * feeding the DSI hosts -- clocks this driver never touched at
	 * all. pclk0/1 is almost certainly what actually drives
	 * INTF_FRAME_COUNT/LINE_COUNT, not MDP_CLK -- explaining why every
	 * MDP_CLK/MMCX/BCM experiment left frame counters frozen at 0
	 * regardless of clock rate or voltage. Must run after both DSI PHY
	 * PLLs are locked (just above), since these mux from the DSI PHY's
	 * own PLL output, not DISPCC's internal PLL0. */
	ret = sheng_mdss_dispcc_dsi_clks_init(SM8550_DISPCC_BASE);
	sheng_mdss_phy144_mark(5, SM8550_MDSS_DSI0_PHY_BASE);
	env_set_hex("sheng_mdss_dsi_clks", (unsigned long)ret);
	if (ret)
		return ret;

	/* Replay path rejoins HERE, past the link-clock init -- it already ran
	 * it between its two phases. Calling it twice re-runs
	 * rcg2ConfigureHidOnly()'s update-poll on RCGs that are already
	 * running, which times out and aborted probe on b49. */
bringup_done:

	/* BISECTION: reset-toggle + GDSC + DISPCC + both DSI PHYs confirmed
	 * reaching Linux. Next: add DSI panel init back and stop right
	 * after it -- this re-creates the last known-good stopping point
	 * from before this session's reset-toggle work, just with the new
	 * reset call now running first.
	 */
	/* Closing the real gap: avdd/avee bias + reset-gpio pulse, matching
	 * nt36532e_prepare()'s exact sequence, BEFORE any DCS command --
	 * see sheng_mdss_panel_power_and_reset()'s comment. Without this
	 * the panel is very likely still sitting in hardware reset and/or
	 * unpowered, and every "successful" DCS write below has been going
	 * nowhere. */
	/* ORDERING, measured from the working kernel (SPEC.md task #5 log):
	 * bring the DSI hosts up and switch them to VIDEO mode FIRST, then
	 * power and reset the panel, then run the DCS init sequence. The
	 * kernel's ktime trace shows host_enable_video at 743.050ms,
	 * panel_prepare at 743.058ms and panel_reset at 743.484ms -- the
	 * panel is reset onto an already-streaming link.
	 *
	 * This driver used to power+reset the panel and run its entire init
	 * over a command-mode link, switching to video only afterwards. A
	 * first attempt at the reorder moved just the video-mode switch and
	 * left the reset ahead of it, which regressed the DSC encoder; the
	 * reset has to FOLLOW the switch. */
	/* MEASURED RESULT (SPEC.md task #5 log): replicating the kernel's
	 * order exactly -- video mode on, THEN power+reset, THEN the DCS
	 * sequence -- broke command transmission. Commands succeed for a
	 * while and then time out mid-sequence (panel = -10026, i.e.
	 * command #26; the single-host read's first command also failed).
	 * The DSI video engine is streaming with no DPU data behind it for
	 * the ~200ms the init takes, and eventually wedges the command DMA.
	 * Linux has the identical window (host_enable_video 743.050ms,
	 * init_seq exit 952.569ms, INTF timing engine started only after)
	 * and its commands survive it -- so something about our video
	 * engine's behaviour with no data differs, which is worth chasing,
	 * but not at the cost of a working command path.
	 *
	 * Reverted to: power+reset, DCS init over a command-mode link, then
	 * the video-mode switch in dpu_start(). End state is identical
	 * either way (sheng.verify / sheng.dsiaudit both read 0). */
	/* KERNEL-ORDER REPLICATION, second attempt (SPEC.md task #5 log).
	 *
	 * The traced kernel timeline is now unambiguous:
	 *   751.075ms host_enable_video   (video mode ON)
	 *   751.582ms panel_reset
	 *   786.676ms init_seq enter
	 *   960.492ms init_seq exit
	 *   962.660ms intf_timing_engine enable=1   (2.2ms LATER)
	 *
	 * So Linux runs the whole DCS sequence on a link that is in video
	 * mode but carrying no active pixels -- the INTF timing engine is
	 * started only afterwards. Commands interleave into what is
	 * effectively 100% blanking.
	 *
	 * We reproduced exactly that and the command DMA still wedged at
	 * command #26. This run is to capture WHY: sheng.timeout_diag holds
	 * FIFO_STATUS and DLN0_PHY_ERR sampled at the failing command, which
	 * was never read on the previous attempt. Healthy reference values
	 * from live silicon: FIFO_STATUS 0x00001210, DLN0_PHY_ERR 0x00088888.
	 */
	sheng_mdss_dsi_host_video_prepare(SM8550_MDSS_DSI0_BASE,
					  SM8550_MDSS_DSI1_BASE);

	if (SHENG_GRACEFUL_RESTART) {
		/* ABL's panel is still powered and configured at this point.
		 * Shut it down the same way our own teardown shuts it down for
		 * Linux -- Display Off, then Sleep In -- before removing power.
		 * See the comment at the cold-start block above. */
		sheng_mdss_smmu_setup();
		sheng_mdss_dsi_panel_sleep(SM8550_MDSS_DSI0_BASE,
					    SM8550_MDSS_DSI1_BASE,
					    SHENG_MDSS_DSI_DMA_SCRATCH);

		/* Now the power-cycle, in the teardown's order: reset asserted
		 * first, then avee, then avdd. Held off long enough for the
		 * panel rails to genuinely discharge rather than glitch. */
		sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 0);
		sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 0);
		/* The GPIOs alone do not remove panel power -- LCD_BIAS_EN is
		 * latched over I2C too. Clear it so the rails genuinely collapse. */
		BBS("bias OFF over i2c", sheng_ktz8866_set_bias(0));

		/* THE UNMEASURED STEP (b104).
		 *
		 * sheng.rstpulse proved the RESET writes physically land (pad
		 * reads 0x0 while driven low). The bias rails never got the
		 * same treatment: sheng_mdss_biasgpio samples them only AFTER
		 * they are switched back on, so "avdd/avee actually go low"
		 * has never once been observed.
		 *
		 * It now matters more than anything else. Measured this
		 * session from Linux:
		 *   power-cycle + reset  -> panel answers 0x08
		 *   reset only, rails up -> panel answers nothing (-61)
		 * and b103 -- Linux skipping BOTH reset and init, so the DDIC
		 * is exactly as U-Boot left it -- read -61. U-Boot's result
		 * matches the rails-never-dropped case exactly.
		 *
		 * IN_OUT bit0 = value driven, bit1 = actual pad level. Both
		 * must read 0x0 here. Anything with bit1 set means the rail is
		 * still being held up (very plausibly by the KTZ8866, which
		 * also gates these rails over I2C), the DDIC never loses power,
		 * and no amount of correct DCS traffic can bring it up.
		 *
		 * Packed: [31:16] avdd IN_OUT, [15:0] avee IN_OUT. Expect 0. */
		{
			volatile u32 *p_io = (volatile u32 *)(uintptr_t)
				(SM8550_TLMM_BASE + 0x4 +
				 TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVDD_GPIO);
			volatile u32 *n_io = (volatile u32 *)(uintptr_t)
				(SM8550_TLMM_BASE + 0x4 +
				 TLMM_GPIO_REG_SIZE * TLMM_PANEL_AVEE_GPIO);

			mdelay(20);
			BBV("rails DURING off (expect 0, avdd<<16|avee)",
			    (((unsigned long long)(*p_io & 0xffff)) << 16) |
			    ((unsigned long long)(*n_io & 0xffff)));
			mdelay(60);
			BBV("rails LATE in off window",
			    (((unsigned long long)(*p_io & 0xffff)) << 16) |
			    ((unsigned long long)(*n_io & 0xffff)));
			/* b2xx: was mdelay(40), giving a 120ms total off window.
			 * The true control (no commands, no video) proved the panel
			 * is already unresponsive after U-Boot's power+reset alone,
			 * while Linux's blank/unblank -- which holds the rails down
			 * for ~1-2s -- leaves it answering 0x08. The GPIOs do go low
			 * (measured 0x0 across the window), so if 120ms simply is not
			 * long enough for the KTZ8866 rails to discharge, the DDIC
			 * never truly loses power and never resets its state. */
			mdelay(1000);
		}
	}
	/* NB: this used to be a braceless `if` with the two diagnostic calls
	 * below dangling outside it -- harmless while the flag was 0, but a
	 * silent lie the moment it isn't. Braced. */
	if (!SHENG_SKIP_PANEL_TOUCH) {
		sheng_mdss_panel_power_and_reset();
		BBM("panel powered + reset pulsed");
	} else {
		/* INHERIT PATH: ABL handed us a live, already-initialised DDIC
		 * (sheng.abl measured reset deasserted + both bias rails high).
		 * Touch none of it -- no power cycle, no reset pulse, no DCS --
		 * and stream video at a panel a working bootloader configured.
		 * This is the only way to exercise our video path WITHOUT its
		 * result depending on our own unverifiable DCS init. */
		BBM("panel UNTOUCHED (inheriting ABL init)");
	}
	sheng_mdss_phy144_mark(6, SM8550_MDSS_DSI0_PHY_BASE);

	/* EARLIEST-POSSIBLE BTA, minimal configuration -- see
	 * MINIMAL_CMD_MODE_BTA_TEST's comment in sheng_mdss_hw.zig. Issued on
	 * DSI0 alone, on a freshly-reset panel, before a single init command,
	 * with the host still in command mode and the DPU untouched. Same
	 * self-diagnosing encoding as sheng.rd1: [31:16] carries DSI_CTRL as
	 * it stood during the read, so a zero result cannot be confused with
	 * a malformed request. */
	/* PRE-INIT READ, RESTORED (b100) -- and this time it has a KNOWN
	 * EXPECTED VALUE, which is what it always lacked before.
	 *
	 * It was removed on the reasoning that the kernel never issues DCS
	 * reads on this panel, so neither should we. That reasoning was
	 * sound but the premise was incomplete: measured from Linux this
	 * session, a freshly power-cycled + reset DDIC answers
	 * get_power_mode with 0x08 (booster=0 sleep_out=0 normal=1
	 * display_on=0) BEFORE any init command is sent. The panel is
	 * demonstrably responsive at exactly this point in the sequence.
	 *
	 * That makes this the cleanest transport test available. Everything
	 * else is now excluded: U-Boot's full 94-command table (87 static +
	 * 0x90 0x03 + PPS + 0x9d 0x01 + 0xb2/0xb3 + sleep-out + display-on)
	 * was replayed from Linux onto a freshly reset panel and drove it
	 * 0x08 -> 0x9c, i.e. IDENTICAL to what the kernel's own init
	 * achieves. So the commands are right, the reset pulse is right
	 * (0x0303, physically verified), the rails are right, and the
	 * ordering is right.
	 *
	 *   reads 0x08 here -> the DSI transport works end to end, and the
	 *     fault is something about how we SEQUENCE the init.
	 *   reads nothing   -> the transport does not reach the panel at
	 *     all, despite every register matching live silicon and despite
	 *     the DMA clocking bytes out at a measured LP escape rate. That
	 *     would mean the PHY is not driving the pads, which no register
	 *     comparison we can make would reveal.
	 *
	 * Unlike every previous read attempt, a null result here cannot be
	 * blamed on an unconfigured panel -- we know this exact panel state
	 * answers, because we measured it answering. */
	/* DISABLED (b106). The read itself is now the problem.
	 *
	 * b105's SMMU stage-1 passthrough fix made the DSI transport work for
	 * the first time: this read returned 0x01f70008 -- low byte 0x08, the
	 * exact value a freshly power-cycled panel gives -- and the BTA probe
	 * logged rdbk=0x21080037 with BTA_DONE=1. Both directions genuinely
	 * work now.
	 *
	 * But the link ends the boot WEDGED: LANE_STATUS 0x00011f1e (DLN0 held
	 * out of stopstate), DLN0_PHY_ERR 0x00088988 (was a clean 0x00088888),
	 * TIMEOUT_STATUS 0x10, FIFO starved, and sheng.lanact = 0 -- no HS
	 * traffic at all, so the DPU streams into a dead link and the panel
	 * stays black. That is the signature of a bus turnaround leaving the
	 * lane contended, and it is byte-identical to a wedge reproduced
	 * independently from Linux.
	 *
	 * These reads were only ever instrumentation and they have answered
	 * their question. The kernel issues no DCS reads on this panel at all.
	 * Take them out and let the init run on a link that stays in LP-11. */
	if (0) {
		/* CONFOUND FIX (b102): panel_init() calls this as its FIRST
		 * statement, and the read below sits BEFORE panel_init -- so
		 * b100/b101 issued their command DMA while the MDSS stream was
		 * still on whatever SMMU config ABL left. A DMA fetch that
		 * faults there produces exactly the silence we measured, for a
		 * reason that has nothing to do with the transport. Set the
		 * translation up first so the read tests what it claims to. */
		sheng_mdss_smmu_setup();

		unsigned long pre = (unsigned long)
			sheng_mdss_dsi_read_power_mode_single(
				SM8550_MDSS_DSI0_BASE,
				SHENG_MDSS_DSI_DMA_SCRATCH);

		/* Snapshot the transport AT THE MOMENT IT FAILS. Every block
		 * we have ever compared -- DSI, PHY CMN/LANE/PLL, DPU,
		 * DISPCC -- was sampled at the END of probe and matches live
		 * silicon exactly. But the read fails HERE, early, and the
		 * PHY could be misconfigured in this window and correct by
		 * the time the final dump runs. Reference for the diff:
		 * linux_preinit.txt, captured from a rendering Linux forced
		 * into this same freshly-reset, pre-init state, where the
		 * identical read provably returns 0x08. */
		BBB("PREINIT_DSI0", SM8550_MDSS_DSI0_BASE, 0x000, 192);
		BBB("PREINIT_PHY0_CMN", SM8550_MDSS_DSI0_PHY_BASE, 0x000, 128);
		BBV("PRE-INIT read (expect 0x08 in low byte)", pre);
		/* Proves the packet bytes really are in physical DRAM where the
		 * DSI engine will fetch them. Read back after the cache flush,
		 * so it misses the invalidated line and pulls from DRAM.
		 * Expected for the read request, little-endian in the low
		 * bytes. Computed on every boot since it was added and never
		 * once looked at. */
		BBS("dmabuf readback @scratch", sheng_mdss_dmabuf_diag());
		env_set_hex("sheng_mdss_preread", pre);
	}

	/* Backlight now confirmed working in U-Boot itself (order flip +
	 * GPIO fault-clear cycle + brightness soft-start in board.c, run
	 * AFTER this probe() returns). Now that a real backlight exists to
	 * actually SEE pixels with, swap the DSI-bypass command-mode patch
	 * for the real DPU video path -- the panel is video-mode
	 * (MIPI_DSI_MODE_VIDEO in the real driver) and structurally can't
	 * show anything from a one-shot command-mode write.
	 *
	 * DSC ISOLATION TEST (SPEC.md task #5 log): real video is now
	 * confirmed streaming (INTF_FRAME_COUNT/LINE_COUNT genuinely
	 * incrementing) but nothing is visible -- most likely a mismatch
	 * between the DPU-side DSC encoder config and the panel-side PPS
	 * we send it, which are two independently-transcribed sets of
	 * parameters never cross-verified against each other. Disabling
	 * DSC entirely on BOTH sides isolated it -- PPS bytes cross-checked
	 * against the DPU-side DSC encoder config (pic_height=2032,
	 * pic_width=1524, slice_height=16, slice_width=762, chunk_size=762,
	 * initial_xmit_delay=512, initial_dec_delay=637 -- every field
	 * matches exactly), and disabling DSC entirely produced the exact
	 * same "frames streaming, nothing visible" symptom as DSC-on. DSC
	 * was never the blocker. Real gap found instead: DSI_VID_CFG0 (see
	 * dsiHostSwitchToVideoMode()'s comment) was never written at all.
	 * Back to enable_dsc=true, the real/correct configuration (normal
	 * path -- NOT used by this diagnostic build, see below). */

	/* DIAGNOSTIC BUILD ONLY (SPEC.md task #5 log): sanity check that
	 * SOMETHING real is being pushed to the panel, using the simplest
	 * possible path -- sheng_mdss_dsi_test_patch(), a DPU-bypass
	 * proof-of-concept built earlier in the project but never retested
	 * with the SW_RESET pulse / correct regulators / correct stride /
	 * correct framerate branch fixes now in place. Pushes a small 16x16
	 * solid-color patch directly over the already-proven command-mode
	 * DSI DMA engine -- entirely bypassing SSPP/LM/CTL/INTF/DSC. If
	 * this shows ANYTHING, the physical DSI link + panel are proven
	 * alive and the bug is DPU-video-pipeline-specific. If nothing
	 * shows here either, the problem is more fundamental than the DPU
	 * path we've been exhaustively auditing.
	 *
	 * DSI 6G REGISTER SHIFT FIX (SPEC.md task #5 log): SM8550_MDSS_DSI0/
	 * 1_BASE now include the +4 byte DSI_6G_REG_SHIFT (see their
	 * definition's comment) -- every DSI host register access in this
	 * entire driver was landing 4 bytes before where it should have
	 * been, on offset 0x000 specifically hitting the real, read-only
	 * 6G_HW_VERSION register instead of CTRL. Diagnostic early-return
	 * and DSC-incompatible test_patch call removed now that the real
	 * root cause is fixed -- proceeding into the real enable_dsc=true
	 * video path below for a genuine end-to-end test. */
	/* PRE-COMMAND AUDIT (SPEC.md task #5 log).
	 *
	 * Every audit in this driver runs at the END of probe, after
	 * dpu_start(). But the DCS init is sent BEFORE that, so the register
	 * state at the moment commands actually go out has never been checked
	 * -- only the state long afterwards.
	 *
	 * That matters now. The handoff test proved our init does not
	 * configure the DDIC, while the command bytes, packet framing,
	 * ordering, DRAM contents, DMA completion, panel power and the reset
	 * pulse are all verified correct, and the transmitted stream is
	 * byte-identical to the kernel's (including the 132-byte PPS). If the
	 * commands are well-formed and physically sent, the remaining variable
	 * is the host/PHY state they are sent INTO.
	 *
	 * Reference, from tracing every dsi_write() the kernel makes, is its
	 * state at its own first command: CTRL 0x1f3, VID_CFG0 0x02009230,
	 * VID_CFG1 0, ACTIVE_H 0x022c0030, ACTIVE_V 0x087c008c, TOTAL
	 * 0x08950272, CMD_DMA_CTRL 0x14000000, TRIG_CTRL 0x80001004,
	 * CLK_CTRL 0x0000023f, COMPRESSION 0x05f40b01 -- which is what
	 * dsi_audit_table already encodes. */
	/* CLK_STATUS (0x11c) -- the ONE register in the entire display path
	 * that differs from working silicon (SPEC.md task #5 log).
	 *
	 * Exhaustive sweeps now cover every configurable register: 124/124 CMN,
	 * 412 lane+PLL (only 3 dynamic PLL calibration regs differ, and those
	 * differ between two reads of the same rendering Linux), and 176/176
	 * DSI host -- of which this is the single mismatch, and it is READ-ONLY
	 * status rather than configuration.
	 *
	 * That makes it informative rather than dismissible: it reports which
	 * clocks are physically ACTIVE. Live, while rendering: 0x00804343 =
	 * bits 0,1 AHBM_HCLK | 6 AON_BYTECLK | 8 AON_ESCCLK | 9 AON_PCLK |
	 * 14 VID_PCLK, with bit16 PLL_UNLOCKED clear.
	 *
	 * bit8 AON_ESCCLK_ACTIVE is the one that matters here. DCS commands go
	 * out in LP escape mode (CMD_DMA_CTRL.LOW_POWER is set, matching the
	 * kernel), and LP transmission is clocked by the escape clock. If that
	 * clock is not running, the DMA engine still shifts its buffer out and
	 * reports completion, no FIFO or PHY error is raised, and nothing
	 * reaches the panel -- which is exactly what we have measured for the
	 * entire investigation.
	 *
	 * Sampled twice: immediately before the first DCS command, and again
	 * at the end of probe, so a clock that starts late is distinguishable
	 * from one that never runs.
	 * high32 = pre-command, low32 = end of probe. */
	env_set_hex("sheng_mdss_clkstat_pre",
		    (unsigned long)*(volatile u32 *)(uintptr_t)(SM8550_MDSS_DSI0_BASE + 0x11c));

	env_set_hex("sheng_mdss_preaud",
		    (unsigned long)sheng_mdss_dsi_audit(SM8550_MDSS_DSI0_BASE));
	env_set_hex("sheng_mdss_preaud1",
		    (unsigned long)sheng_mdss_dsi1_audit(SM8550_MDSS_DSI1_BASE));

	if (SHENG_SKIP_PANEL_TOUCH || SHENG_PANEL_AFTER_DPU) {
		/* panel_init() normally does this first; still required for the
		 * DPU's own SSPP fetch -- and when SHENG_PANEL_AFTER_DPU moves
		 * panel_init() past dpu_start(), this standalone call is what
		 * keeps the SSPP's translation set up in time. */
		sheng_mdss_smmu_setup();
		ret = 0;
	} else {
		ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
						 SHENG_MDSS_DSI_DMA_SCRATCH, true);
		BBS("panel_init_ret", ret);
		BBR("DSI0 CTRL", SM8550_MDSS_DSI0_BASE, 0x000);
		BBR("DSI0 STATUS0", SM8550_MDSS_DSI0_BASE, 0x004);
		BBR("DSI0 FIFO", SM8550_MDSS_DSI0_BASE, 0x008);
		BBR("DSI0 LANE_STATUS", SM8550_MDSS_DSI0_BASE, 0x0a4);
		BBR("DSI0 ACK_ERR", SM8550_MDSS_DSI0_BASE, 0x068);
		BBR("DSI0 TIMEOUT", SM8550_MDSS_DSI0_BASE, 0x0bc);
	}
	sheng_mdss_phy144_mark(7, SM8550_MDSS_DSI0_PHY_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI_PANEL, ret);
	env_set_hex("sheng_mdss_panel", (unsigned long)ret);
	/* Single-host DCS read: the one test that would positively prove
	 * two-way communication with the panel. See its comment. */
	/* DISABLED (b106) for the same reason as the pre-init read above: the
	 * BTA now succeeds, and succeeding is what wedges DLN0. This one runs
	 * AFTER the whole init sequence, so it is the one that leaves the link
	 * dead just before dpu_start -- exactly where sheng.lanact went from
	 * 242/256 to 0. It proved two-way communication; that job is done. */
	BBM("DCS read attempt SKIPPED (b106: BTA wedges DLN0)");
	BBR("DSI0 RDBK_DATA0", SM8550_MDSS_DSI0_BASE, 0x068);
	BBR("DSI0 RDBK_DATA_CTRL", SM8550_MDSS_DSI0_BASE, 0x1d0);
	env_set_hex("sheng_mdss_trigprobe",
		    (unsigned long)sheng_mdss_dsi_trigger_probe());
	env_set_hex("sheng_mdss_retries",
		    (unsigned long)sheng_mdss_dsi_retry_count());
	env_set_hex("sheng_mdss_status0_pre",
		    (unsigned long)sheng_mdss_dsi_status0_before_first_cmd());
	env_set_hex("sheng_mdss_timeout_diag", (unsigned long)sheng_mdss_dsi_timeout_diag());
	env_set_hex("sheng_mdss_snap1", (unsigned long)sheng_mdss_dsi_snapshot_1());
	env_set_hex("sheng_mdss_snap2", (unsigned long)sheng_mdss_dsi_snapshot_2());
	env_set_hex("sheng_mdss_snap3", (unsigned long)sheng_mdss_dsi_snapshot_3());
	env_set_hex("sheng_mdss_snap4", (unsigned long)sheng_mdss_dsi_snapshot_4());
	env_set_hex("sheng_mdss_smmu_diag1", (unsigned long)sheng_mdss_smmu_diag1());
	env_set_hex("sheng_mdss_smmu_diag2", (unsigned long)sheng_mdss_smmu_diag2());
	env_set_hex("sheng_mdss_smmu_diag3", (unsigned long)sheng_mdss_smmu_diag3());
	env_set_hex("sheng_mdss_iova_diag1", (unsigned long)sheng_mdss_iova_diag1());
	env_set_hex("sheng_mdss_iova_diag2", (unsigned long)sheng_mdss_iova_diag2());
	env_set_hex("sheng_mdss_dmabuf", (unsigned long)sheng_mdss_dmabuf_diag());
	/* Does U-Boot's own MMU even map the HIGH DRAM bank the scratch
	 * buffer was moved into this session? build_mem_map() maps only
	 * what the previous bootloader handed over in gd->dram[]; a bank
	 * that isn't there is simply not mapped, and every CPU store into
	 * it goes nowhere. Report which bank (if any) contains the scratch
	 * address, plus that bank's start/size, rather than assuming. */
	{
		unsigned long found = ~0UL, fstart = 0, fsize = 0;
		int b;
		for (b = 0; b < CONFIG_NR_DRAM_BANKS; b++) {
			if (!gd->dram[b].size)
				continue;
			if (SHENG_MDSS_DSI_DMA_SCRATCH >= gd->dram[b].start &&
			    SHENG_MDSS_DSI_DMA_SCRATCH < gd->dram[b].start +
							 gd->dram[b].size) {
				found = b;
				fstart = gd->dram[b].start;
				fsize = gd->dram[b].size;
				break;
			}
		}
		env_set_hex("sheng_mdss_scratch_bank", found);
		/* Same check for the FRAMEBUFFER, which was never verified --
		 * only the DSI scratch buffer was. SSPP_SRC0_ADDR is a 32-bit
		 * register and we hand it raw physical 0xa3200000; if that
		 * address is not in a bank U-Boot owns, the CPU fill goes
		 * nowhere real and/or the DPU's fetch reads a region it is not
		 * permitted to read, which looks exactly like the current
		 * symptom: entire pipeline verified bit-identical to working
		 * silicon (sheng.verify=0), no FIFO errors, and no pixels. */
		{
			unsigned long fb_found = ~0UL, fb_start = 0, fb_size = 0;
			int fb_b;
			for (fb_b = 0; fb_b < CONFIG_NR_DRAM_BANKS; fb_b++) {
				if (!gd->dram[fb_b].size)
					continue;
				if (SHENG_MDSS_FB_ADDR >= gd->dram[fb_b].start &&
				    SHENG_MDSS_FB_ADDR < gd->dram[fb_b].start +
							 gd->dram[fb_b].size) {
					fb_found = fb_b;
					fb_start = gd->dram[fb_b].start;
					fb_size = gd->dram[fb_b].size;
					break;
				}
			}
			env_set_hex("sheng_mdss_fb_bank", fb_found);
			env_set_hex("sheng_mdss_fb_bank_start", fb_start);
			env_set_hex("sheng_mdss_fb_bank_size", fb_size);
		}
		env_set_hex("sheng_mdss_scratch_bank_start", fstart);
		env_set_hex("sheng_mdss_scratch_bank_size", fsize);
	}
	if (ret)
		return ret;

	/* Ground-truth test: every DCS command sent by this driver up to
	 * now (including the panel init sequence just above) has been a
	 * plain write with no BTA/ACK -- the host reporting DMA success
	 * only proves ITS OWN buffer was shifted out, never that the panel
	 * actually received or is responding to anything. This is the
	 * first real DCS READ (Get Power Mode, 0x0A) with genuine BTA in
	 * this driver's history -- a byte 0-255 here means the panel is
	 * genuinely alive and responding at the physical layer; a timeout
	 * (large/negative value) means nothing is getting through even at
	 * the most basic command level, regardless of DPU/video pipeline
	 * state. See sheng_mdss_dsi_read_power_mode()'s comment. */
	/* DISABLED (b107). THIS is the read that wedges the link.
	 *
	 * b106 disabled read_power_mode_single but missed this one -- the DUAL
	 * variant, which sends a set-max-packet-size plus the read on BOTH
	 * hosts. The b106 trace shows the whole init finishing clean
	 * (panel_init_ret=0, LANE_STATUS=0x1f1f, TIMEOUT=0), then this read
	 * timing out at 66ms and being retried until the link is dead:
	 * STATUS0=0x13 (CMD_MODE_DMA_BUSY never clears), LANE_STATUS=0x00011f1e
	 * (DLN0 held out of stopstate), DLN0_PHY_ERR=0x00088988, and
	 * sheng.lanact=0 -- so dpu_start then streams into a dead link.
	 * sheng.pm read 0xff92 == -110 == ETIMEDOUT, which said exactly this
	 * all along.
	 *
	 * Now that the SMMU fix (b105) makes BTA actually work, a read is no
	 * longer harmless instrumentation: completing a turnaround leaves the
	 * lane contended. The kernel issues no DCS reads on this panel at all.
	 * Stop reading. */
	if (0) {
		long long power_mode = sheng_mdss_dsi_read_power_mode(SM8550_MDSS_DSI0_BASE,
									SM8550_MDSS_DSI1_BASE,
									SHENG_MDSS_DSI_DMA_SCRATCH);
		long long err_status = sheng_mdss_dsi_read_error_status(SM8550_MDSS_DSI0_BASE);
		long long ctrl_state = sheng_mdss_dsi_read_ctrl_state(SM8550_MDSS_DSI0_BASE);
		env_set_hex("sheng_mdss_power_mode", (unsigned long)power_mode);
		env_set_hex("sheng_mdss_err_status", (unsigned long)err_status);
		env_set_hex("sheng_mdss_ctrl_state", (unsigned long)ctrl_state);
		env_set_hex("sheng_mdss_ctrl_selfcheck",
			    (unsigned long)sheng_mdss_dsi_ctrl_writeback_selfcheck(SM8550_MDSS_DSI0_BASE));
		env_set_hex("sheng_mdss_block_selfcheck",
			    (unsigned long)sheng_mdss_dsi_block_writeback_selfcheck(SM8550_MDSS_DSI0_BASE));
		env_set_hex("sheng_mdss_earliest_selfcheck",
			    (unsigned long)sheng_mdss_dsi_earliest_ctrl_selfcheck());
	}

	/* Panel init is done; the DPU is about to start streaming frames,
	 * so TRIG_CTRL's BLOCK_DMA_WITHIN_FRAME / TE interlock now has a
	 * live MDP to synchronise against. Put Linux's exact live value
	 * back. See TRIG_CTRL_CMD_INIT_VALUE in sheng_mdss_hw.zig for why
	 * panel init itself must NOT run with those bits set. */
	sheng_mdss_dsi_trig_ctrl_restore(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);

	/* ALL_PIXELS_ON diagnostic REMOVED from the boot path: it answered
	 * its question (screen stayed black) and it is a state-changing
	 * DCS write that must not stay in a normal boot. The helper is
	 * kept in sheng_mdss_hw.zig for future use. Note the result was
	 * NOT conclusive -- 0x22/0x23 behaviour is implementation-defined
	 * on a RAM-less video-mode panel like this one. */

	/* Real panel timings (sheng_tianma_modes[], panel-novatek-
	 * nt36532e.c): 3048x2032, hfp=142 hsync=4 hbp=92, vfp=26 vsync=2
	 * vbp=138. */
	{
		/* sheng_mdss_dpu_start() now programs SSPP_SRC_YSTRIDE0 with
		 * the 32-pixel-aligned pitch (align_pitch() in msm_drv.h:
		 * ALIGN(3048,32)=3072, *4 bytes = 12288 -- matches a live-
		 * verified working mmap test on this exact panel, 2032*12288
		 * = 24,969,216 bytes, see SPEC.md task #5), not the naive
		 * tightly-packed 3048*4=12192. Fill the SAME aligned region
		 * here so every byte SSPP will actually fetch (including the
		 * 24 padding pixels/96 bytes per row past column 3048) is
		 * real, initialized memory -- filling only the tight 3048-
		 * wide region would leave the last ~187KB of what SSPP reads
		 * (rows shifted by the stride mismatch) as uninitialized
		 * memory. */
		volatile u32 *fb = (volatile u32 *)(uintptr_t)SHENG_MDSS_FB_ADDR;
		size_t aligned_hactive = 3072; /* (3048+31)&~31 */
		size_t fb_words = aligned_hactive * 2032;
		size_t px;

		/* KNOWN TEST PATTERN, drawn with the exact geometry measured
		 * on live Linux via /dev/fb0: stride 12288 bytes (3072 px, NOT
		 * 3048), 24969216 bytes total, ARGB8888 stored little-endian as
		 * 0xAABBGGRR -- so red is 0xFF0000FF and blue is 0xFFFF0000.
		 *
		 * A solid fill cannot diagnose anything: it looks identical at
		 * any stride and any channel order. These bands can. Read the
		 * screen top to bottom -- red, green, blue, white -- with a
		 * 64px white frame around the whole visible area:
		 *   bands crisp, correct colours, frame flush to all 4 edges
		 *      -> framebuffer geometry and format are exactly right and
		 *         any remaining mess is the console's own drawing
		 *   bands sheared diagonally  -> stride still wrong
		 *   colours permuted          -> channel order wrong
		 *   frame clipped or wrapped  -> width/height wrong */
		{
			size_t x, y;
			const u32 bandcol[4] = {
				0xffff0000u, /* red   */
				0xff00ff00u, /* green */
				0xff0000ffu, /* blue  */
				0xffffffffu, /* white */
			};

			for (y = 0; y < 2032; y++) {
				u32 c = bandcol[(y * 4) / 2032];

				for (x = 0; x < aligned_hactive; x++) {
					bool frame = (y < 64 || y >= 2032 - 64 ||
						      x < 64 || x >= 3048 - 64);
					bool pad = (x >= 3048);

					fb[y * aligned_hactive + x] =
						pad ? 0xff000000u :
						frame ? 0xffffffffu : c;
				}
			}
		}
		(void)px;
		flush_dcache_range(SHENG_MDSS_FB_ADDR,
				    SHENG_MDSS_FB_ADDR + fb_words * 4);
		dsb();
		/* DELIBERATELY NOT READ BACK HERE (SPEC.md task #5 log): an
		 * earlier build read fb[0] and fb[fb_words-1] at this point
		 * and HUNG THE BOARD outright -- no Linux boot at all. A read
		 * that hangs the CPU is a synchronous external abort, i.e.
		 * this address range is not readable memory. The fill loop
		 * above never exposed it because writes are posted and get
		 * silently swallowed, whereas a read must return data.
		 *
		 * That is itself the finding: the framebuffer is (at least
		 * partly) outside DRAM U-Boot owns. sheng.fbbank below reports
		 * the bank lookup, which is safe (it only inspects gd->dram)
		 * and must be consulted BEFORE anything dereferences this
		 * address again. Do not re-add a readback here until the
		 * framebuffer has been relocated into a verified bank.
		 *
		 * RESOLVED: sheng.fbbank came back 1 (bank 0x811d0000 +
		 * 0x56e30000, i.e. up to 0xd8000000), so this address IS
		 * inside DRAM U-Boot owns and the earlier hang was NOT an
		 * abort here at all -- it was `setenv bootargs` exceeding
		 * CONFIG_SYS_MAXARGS (64) once the diagnostic variables piled
		 * up, leaving bootargs unset and Linux with no root=. The
		 * readback is safe and is restored below, because whether the
		 * fill actually lands in memory has still never been proven. */
		env_set_hex("sheng_mdss_fb_readback",
			    (((unsigned long)fb[0]) << 32) |
			    (unsigned long)fb[fb_words - 1]);
	}

	/* SHENG_SKIP_DPU_START (b108) -- isolate the init from the video stream.
	 *
	 * b107: transport verified working (first-ever DCS reply 0x08 and
	 * BTA_DONE=1 after the b105 SMMU fix), init clean (panel_init_ret=0,
	 * no timeouts, PPS out at the correct LP rate), link byte-identical to
	 * a rendering Linux (CTRL=0x1f3 STATUS0=0x08 FIFO=0x1210 LANE=0x1f00
	 * PHY_ERR=0x88888), lanes active (lanact=f2/f5). Still black, and Linux
	 * still reads the handed-over panel as -61.
	 *
	 * The same 94 bytes replayed from Linux configure this panel to 0x9c, so
	 * the content is right. What U-Boot does that the replay does not is
	 * immediately stream DSC-compressed video at it. A malformed stream can
	 * put the DDIC decoder into an error state where it stops answering --
	 * indistinguishable from "the init never took".
	 *
	 *   Linux reads 0x9c -> our init WORKS; fault is the video stream (DSC,
	 *     SSPP fetch or framebuffer content) and the command path is done.
	 *   Linux reads -61  -> the init does not take even on a healthy link,
	 *     and the video stream is irrelevant. */
	if (SHENG_SKIP_DPU_START) {
		BBM("dpu_start SKIPPED (b108: isolating init from video)");
		env_set_hex("sheng_mdss_dpu_start", 0);
		goto dpu_started;
	}

	ret = sheng_mdss_dpu_start(SM8550_MDSS_DPU_BASE,
				    SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_FB_ADDR,
				    3048, 2032,
				    142, 92, 4,
				    26, 138, 2,
				    true); /* DSC ruled out as the blocker -- see comment above */
	env_set_hex("sheng_mdss_dpu_start", (unsigned long)ret);
	BBM("dpu_start done");
dpu_started:
	BBR("DSI0 STATUS0 post-dpu", SM8550_MDSS_DSI0_BASE, 0x004);
	BBR("DSI0 LANE_STATUS post-dpu", SM8550_MDSS_DSI0_BASE, 0x0a4);
	/* THE instrument for the b95 PLL0 rate fix. This is the register that
	 * has been quietly reporting the bug all along: live rendering Linux
	 * reads 0x00001210 (lanes FED); every build of ours until now read
	 * 0x11111210, i.e. all four DLN*_HS_FIFO_EMPTY bits set -- the link
	 * starving because mdp_clk ran at 85.7MHz instead of 514MHz. If the
	 * PLL fix works, the four top nibbles collapse to zero. */
	BBR("DSI0 FIFO_STATUS post-dpu", SM8550_MDSS_DSI0_BASE, 0x008);
	BBR("DSI1 FIFO_STATUS post-dpu", SM8550_MDSS_DSI1_BASE, 0x008);
	/* PLL0 rate readback -- expect L_VAL 0x44440050 / ALPHA 0x00005000,
	 * matching live Linux. Anything else means the write did not stick
	 * (PLL locked/latched) and the rate change needs a proper
	 * disable-reconfigure-relock sequence rather than a bare write. */
	BBR("DISPCC PLL0 L_VAL", SM8550_DISPCC_BASE, 0x010);
	BBR("DISPCC PLL0 ALPHA", SM8550_DISPCC_BASE, 0x014);
	BBR("INTF1 FRAME_COUNT", SM8550_MDSS_DPU_BASE + 0x35000, 0x0ac);
	if (ret)
		return ret;

	/* SEND THE PANEL INIT ONTO AN ALREADY-STREAMING LINK (SPEC.md task #5).
	 *
	 * This driver has always run panel_init() BEFORE dpu_start(), i.e.
	 * with the DSI host in video mode but no video actually flowing. The
	 * real kernel does the opposite, and this file's own captured
	 * timeline says so explicitly: "panel_prepare at 743.058ms and
	 * panel_reset at 743.484ms -- the panel is reset onto an
	 * ALREADY-STREAMING link". The panel driver is prepare_prev_first for
	 * exactly this reason.
	 *
	 * Why the ordering is not cosmetic: in video mode the DSI host does
	 * not transmit a command whenever it feels like it, it injects it
	 * into a blanking interval of the outgoing video stream. With the DPU
	 * stopped there is no stream and therefore no blanking interval, so
	 * the command engine can accept the DMA, mark itself busy, drain the
	 * FIFO and go idle without ever putting a packet on the wire.
	 *
	 * That is an exact match for every symptom we measured and could not
	 * explain: DMA completes with zero retries, FIFO_STATUS healthy, no
	 * error latch anywhere, lanes driving at the same 94% duty cycle as
	 * Linux -- and a DDIC that receives nothing, answers no BTA, and
	 * stays unconfigured while perfectly good video is sent to it.
	 *
	 * Flip SHENG_PANEL_AFTER_DPU back to 0 to restore the old ordering. */
	if (SHENG_PANEL_AFTER_DPU && !SHENG_SKIP_PANEL_TOUCH) {
		ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE,
						 SM8550_MDSS_DSI1_BASE,
						 SHENG_MDSS_DSI_DMA_SCRATCH, true);
		sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI_PANEL, ret);
		env_set_hex("sheng_mdss_panel", (unsigned long)ret);
		env_set_hex("sheng_mdss_rdsingle",
			    (unsigned long)sheng_mdss_dsi_read_power_mode_single(
				    SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH));
	}

	/* Frame/line counters (dpu_hw_intf.c: INTF_FRAME_COUNT=0xAC,
	 * INTF_LINE_COUNT=0xB0, relative to each intf_N_base) increment
	 * purely from real active video timing -- independent of whether
	 * backlight/panel actually show anything visibly. Read twice with
	 * a delay: if they're incrementing, video is genuinely streaming. */
	{
		volatile u32 *intf1_frame = (volatile u32 *)(uintptr_t)
			(SM8550_MDSS_DPU_BASE + 0x35000 + 0xac);
		volatile u32 *intf1_line = (volatile u32 *)(uintptr_t)
			(SM8550_MDSS_DPU_BASE + 0x35000 + 0xb0);

		u32 frame_a = *intf1_frame;

		env_set_hex("sheng_intf1_frame_a", (unsigned long)frame_a);
		env_set_hex("sheng_intf1_line_a", (unsigned long)*intf1_line);
		mdelay(500);
		env_set_hex("sheng_intf1_frame_b", (unsigned long)*intf1_frame);
		env_set_hex("sheng_intf1_line_b", (unsigned long)*intf1_line);

		/* PLL VCO-BAND CHECK (SPEC.md task #5 log). Research suggested
		 * the PHY PLL could assert "locked" while having converged on
		 * the wrong VCO band -- every static register would still match
		 * Linux, but the emitted clock would be off-frequency and the
		 * DDIC would silently discard the whole stream. The three
		 * lane/PLL registers that differ in our sweep (0x6c0/0x6c4 and
		 * one neighbour) cannot settle it: they read different values on
		 * two consecutive reads of the same RENDERING Linux, so they are
		 * dynamic status, not a comparable configuration.
		 *
		 * The output frequency itself is directly measurable, though.
		 * INTF_FRAME_COUNT advances once per real active-video frame, so
		 * frames observed across a known 500ms window IS the refresh
		 * rate. Expect ~72 for this panel's 144Hz mode. A value near 72
		 * means the pixel clock -- and therefore the PLL band, the
		 * dividers and the whole clock tree -- is correct and this
		 * hypothesis is dead. A wildly different count (half, double,
		 * near zero) would be the first hard evidence of a clock fault.
		 * Exported as a delta so a nonzero starting count cannot fake
		 * a correct answer, which reading frame_b alone would allow. */
		/* Sampled with the DPU streaming, matching the state Linux is
		 * in when read via devmem -- see sheng_mdss_dsi_txpath_state(). */
		sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 2);
		env_set_hex("sheng_mdss_gdscp",
			    (unsigned long)sheng_mdss_gdsc_probe_result());
	env_set_hex("sheng_mdss_txpath",
			    (unsigned long)sheng_mdss_dsi_txpath_state(SM8550_MDSS_DSI0_BASE));
		env_set_hex("sheng_mdss_lanact",
			    (unsigned long)sheng_mdss_dsi_lane_activity(SM8550_MDSS_DSI0_BASE));
		env_set_hex("sheng_mdss_txpath1",
			    (unsigned long)sheng_mdss_dsi_txpath_state(SM8550_MDSS_DSI1_BASE));
		env_set_hex("sheng_mdss_framedelta",
			    (unsigned long)(*intf1_frame - frame_a));
	}

	/* Sampled AFTER the DPU has been streaming for 500ms, so any SSPP
	 * pixel-fetch translation fault has had ~28 frames' worth of
	 * chances to latch. See sheng_mdss_smmu_fault_diag()'s comment for
	 * the bit decode -- this is what distinguishes "SSPP is starving
	 * on an unmapped framebuffer" from "translation is fine, the black
	 * screen is downstream in SSPP/LM/DSC/CTL config". */
	env_set_hex("sheng_mdss_smmu_fault",
		    (unsigned long)sheng_mdss_smmu_fault_diag());
	env_set_hex("sheng_mdss_smmu_far",
		    (unsigned long)sheng_mdss_smmu_fault_addr());
	/* These two have been computed on every single boot since they were
	 * added and then THROWN AWAY -- neither is on the bootcmd's sheng.*
	 * list, and the cmdline is CBSIZE-capped so they cannot all fit.
	 * The blackbox has no such cap. This is the direct test for "SSPP is
	 * starving on an unmapped framebuffer": fault = [63:32] context-bank
	 * FSR, [31:0] global GFSR; far = the faulting address. Both zero
	 * after 500ms of streaming means translation is fine and the black
	 * screen is downstream of the fetch. */
	BBS("smmu_fault(FSR<<32|GFSR)", sheng_mdss_smmu_fault_diag());
	BBS("smmu_far", sheng_mdss_smmu_fault_addr());
	BBS("smmu_cbx|s2cr_before", sheng_mdss_smmu_diag2());
	BBV("smmu_sctlr (b105: M bit must be 0)", sheng_mdss_smmu_sctlr());
	BBV("smmu_s2cr_after", sheng_mdss_smmu_diag3());

	/* Datapath readback, same 500ms-later moment -- see
	 * sheng_mdss_dpu_readback1()'s comment for the decode. */
	/* DECISIVE BISECT -- see sheng_mdss_dsi_tpg_enable()'s comment. The
	 * DSI host generates video internally, bypassing the entire DPU.
	 * Any visible change means the link reaches the panel; pure black
	 * means nothing we transmit does. Remove once answered. */
	sheng_mdss_dsi_tpg_enable(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);

	/* Whole-pipeline check against the live-hardware reference table --
	 * see sheng_mdss_verify_pipeline()'s comment. 0 == every programmed
	 * register matches working silicon. */
	/* Whole-state capture, REDUCED range set after the full list
	 * reproducibly killed the boot -- see capture_ranges' comment.
	 * Scratch moved to 0x82000000 (clear of the pre-console buffer at
	 * 0x81200000+0x4000 and below kernel_addr_r 0x83000000). */
	/* DISABLED: writing the capture to DRAM reproducibly kills the boot
	 * before backlight, even with the range list cut to blocks we read
	 * every boot and the scratch moved clear of everything known. The
	 * call site is late in probe and cannot precede backlight init, so
	 * the mechanism is not understood -- replaced by the checksum-based
	 * block audit below, which needs no DRAM writes at all. */
	env_set_hex("sheng_mdss_wrap",
		    (unsigned long)sheng_mdss_wrapper_audit(SM8550_MDSS_BASE));
	env_set_hex("sheng_mdss_dsi1_audit",
		    (unsigned long)sheng_mdss_dsi1_audit(SM8550_MDSS_DSI1_BASE));
	env_set_hex("sheng_mdss_dsi_audit",
		    (unsigned long)sheng_mdss_dsi_audit(SM8550_MDSS_DSI0_BASE));
	/* PHY audit, both PHYs -- see sheng_mdss_phy_audit()'s comment. The
	 * PHY had no automated verification at all until now. */
	env_set_hex("sheng_mdss_dispcc_audit",
		    (unsigned long)sheng_mdss_dispcc_audit(SM8550_DISPCC_BASE));
	env_set_hex("sheng_mdss_vbif",
		    (unsigned long)sheng_mdss_vbif_audit(0x0aeb0000));
	env_set_hex("sheng_mdss_phystat",
		    (unsigned long)sheng_mdss_phy_state(SM8550_MDSS_DSI0_PHY_BASE,
							SM8550_MDSS_DSI1_PHY_BASE));
	env_set_hex("sheng_mdss_clkstat_post",
		    (((unsigned long)*(volatile u32 *)(uintptr_t)(SM8550_MDSS_DSI0_BASE + 0x11c)) << 32) |
		    (unsigned long)*(volatile u32 *)(uintptr_t)(SM8550_MDSS_DSI1_BASE + 0x11c));
	BBM("diag: dsi sweep");
	env_set_hex("sheng_mdss_dsisweep",
		    (unsigned long)sheng_mdss_dsi_sweep(SM8550_MDSS_DSI0_BASE));
	BBM("diag: phy lanepll sweep");
	env_set_hex("sheng_mdss_lpsweep",
		    (unsigned long)sheng_mdss_phy_lanepll_sweep(SM8550_MDSS_DSI0_PHY_BASE));
	BBM("diag: phy cmn sweep");
	env_set_hex("sheng_mdss_cmnsweep",
		    (unsigned long)sheng_mdss_phy_cmn_sweep(SM8550_MDSS_DSI0_PHY_BASE));
	/* First sweep of the SLAVE PHY in this driver's history -- see
	 * sheng_mdss_phy1_cmn_sweep()'s comment. */
	BBM("diag: phy1 cmn sweep");
	env_set_hex("sheng_mdss_phy1_sweep",
		    (unsigned long)sheng_mdss_phy1_cmn_sweep(SM8550_MDSS_DSI1_PHY_BASE));
	BBM("diag: phy1 lane sweep");
	env_set_hex("sheng_mdss_phy1_lane",
		    (unsigned long)sheng_mdss_phy1_lane_sweep(SM8550_MDSS_DSI1_PHY_BASE));
	env_set_hex("sheng_mdss_phystatraw",
		    (unsigned long)sheng_mdss_phy_status_raw(SM8550_MDSS_DSI0_PHY_BASE,
							      SM8550_MDSS_DSI1_PHY_BASE));
	env_set_hex("sheng_mdss_p144", (unsigned long)sheng_mdss_phy144_marks());
	env_set_hex("sheng_mdss_phy0_audit",
		    (unsigned long)sheng_mdss_phy_audit(SM8550_MDSS_DSI0_PHY_BASE, true));
	env_set_hex("sheng_mdss_phy1_audit",
		    (unsigned long)sheng_mdss_phy_audit(SM8550_MDSS_DSI1_PHY_BASE, false));
	BBM("diag: verify");
	env_set_hex("sheng_mdss_verify",
		    (unsigned long)sheng_mdss_verify_pipeline(SM8550_MDSS_DPU_BASE,
							     SM8550_MDSS_DSI0_BASE));
	/* Settle before sampling the DSC encoder status (SPEC.md task #5
	 * log). These are running counters: an early sample catches the
	 * encoder mid-startup and reads like a stalled one. A previous
	 * diagnostic happened to insert a 50ms delay here, and removing it
	 * made a healthy encoder look broken -- so the delay is now
	 * explicit and fixed, to keep readings comparable across builds. */
	mdelay(50);
	env_set_hex("sheng_mdss_dsc_st1",
		    (unsigned long)sheng_mdss_dsc_status1(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dsc_st2",
		    (unsigned long)sheng_mdss_dsc_status2(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dpu_rb1",
		    (unsigned long)sheng_mdss_dpu_readback1(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dpu_rb2",
		    (unsigned long)sheng_mdss_dpu_readback2(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dpu_rb3",
		    (unsigned long)sheng_mdss_dpu_readback3(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dpu_rb4",
		    (unsigned long)sheng_mdss_dpu_readback4(SM8550_MDSS_DPU_BASE));
	env_set_hex("sheng_mdss_dsi_vrb1",
		    (unsigned long)sheng_mdss_dsi_video_readback1(SM8550_MDSS_DSI0_BASE));
	/* Physical lane state + PHY errors, sampled while streaming -- see
	 * sheng_mdss_lane_status()'s comment. Live: DSI0 0x00001F00 (lanes
	 * driven), DSI1 0x00001F1F; PHY_ERR 0x00088888 on both. */
	env_set_hex("sheng_mdss_lanes",
		    (unsigned long)sheng_mdss_lane_status(SM8550_MDSS_DSI0_BASE,
							  SM8550_MDSS_DSI1_BASE));
	BBM("diag: phy err");
	env_set_hex("sheng_mdss_phyerr",
		    (unsigned long)sheng_mdss_phy_err_both(SM8550_MDSS_DSI0_BASE,
							   SM8550_MDSS_DSI1_BASE));
	env_set_hex("sheng_mdss_dsi_vrb2",
		    (unsigned long)sheng_mdss_dsi_video_readback2(SM8550_MDSS_DSI0_BASE,
								 SM8550_MDSS_DSI1_BASE));

	/* No large hold here anymore -- board.c calls backlight init
	 * AFTER this probe() returns, with its own 5s hold at the end.
	 * Holding here would delay backlight turning on at all (exactly
	 * what made it "come on very late" before this was found). */

	/* THIS is probe's real exit -- everything below it is unreachable
	 * (the second sheng_mdss_dpu_start() and its diagnostics included).
	 * b74 attached the final dump down there and it silently never ran,
	 * which is why that log ended abruptly after "dpu_start done". */
	BBM("probe exit (real return 0)");
	/* END-OF-PROBE READ. Is the panel still alive when we hand it to Linux?
	 *
	 * b105 proved the DDIC answers 0x08 right after our power+reset. Yet
	 * Linux, booted noinit=1 noreset=1 so it neither resets nor initialises,
	 * reads -61 -- even in the true control where U-Boot sends NO commands
	 * and starts NO video. So the panel dies somewhere between those two
	 * points, and the whole SHENG_PM chain assumed that point was ours.
	 *
	 * If this read succeeds, the panel is alive at handoff and it is LINUX's
	 * own DSI/PHY bring-up that wedges it -- which would make SHENG_PM an
	 * invalid judge of U-Boot's init, and invalidate a long line of
	 * conclusions drawn from it, including "our init does not take".
	 * If it fails, the panel died inside our own probe after power+reset.
	 *
	 * Safe to do here even though a BTA can wedge the link: this runs after
	 * everything, and in the control build there is no video to disturb. */
	/* WRITE PROBE: one command, effect visible in the read below.
	 * 0x08 -> 0x18 means writes land. Still 0x08 means no write ever
	 * reaches the DDIC, even though it answers our reads. */
	if (SHENG_WRITE_PROBE) {
		int wr = sheng_mdss_dsi_exit_sleep_only(SM8550_MDSS_DSI0_BASE,
							SM8550_MDSS_DSI1_BASE,
							SHENG_MDSS_DSI_DMA_SCRATCH);
		BBS("write probe: 0x11 exit_sleep ret", wr);
		mdelay(150);
	}
	/* Instrument check: three different DCS registers. If all three come
	 * back with the same payload, the read path is fabricating it. */
	/* WRITE-DELIVERY TEST: same register, two different max-packet sizes.
	 * If 0x37 (an ordinary short write) lands, the response shape MUST
	 * change between these two. If both come back identical, no write
	 * this driver sends ever reaches the panel. */
	BBS("id maxsz=1", sheng_mdss_dsi_read_dcs_reg_max(
		SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH, 0x04, 1));
	BBS("id maxsz=3", sheng_mdss_dsi_read_dcs_reg_max(
		SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH, 0x04, 3));
	BBS("read 0x0a power_mode", sheng_mdss_dsi_read_dcs_reg(
		SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH, 0x0a));
	BBS("read 0x0c pixel_format", sheng_mdss_dsi_read_dcs_reg(
		SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH, 0x0c));
	BBS("read 0x04 display_id", sheng_mdss_dsi_read_dcs_reg(
		SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH, 0x04));
	BBS("END-OF-PROBE read (expect 0x18 if write landed)",
	    sheng_mdss_dsi_read_power_mode_single(SM8550_MDSS_DSI0_BASE,
						  SHENG_MDSS_DSI_DMA_SCRATCH));
	sheng_mdss_final_dump();
	return 0;

	/* BREAKTHROUGH (see SPEC.md task #5 log): every hang all session was
	 * caused by rsc_send_active_write() (the hand-rolled RSC/TCS
	 * transaction backing sheng_mdss_mmcx_power_on()/sheng_mdss_bcm_vote())
	 * breaking subsequent AHB access to the whole mdss/DPU address
	 * range -- not power/clock/VBIF gating. Proven via bisection:
	 * boot-wrapper-read-no-rsc.img and boot-dpu-read-no-rsc.img both
	 * reached Linux, reading real register values from the wrapper
	 * (0x90000001, a structured HW_VERSION) and the DPU
	 * (SSPP_SRC_SIZE = 0, a plausible unconfigured default) with RSC
	 * never touched at all. MMCX and BCM MM0 were never actually
	 * required -- ABL/firmware already leaves whatever's necessary
	 * active. sheng_mdss_mmcx_power_on()/sheng_mdss_bcm_vote() are
	 * intentionally NOT called below.
	 *
	 * ISOLATION TEST: boot-safe-post-rsc.img (this exact path, stopping
	 * right after DSI panel init with GCC_DISP_HF_AXI_CLK enabled) HUNG
	 * even after a genuine full power cycle -- ruling out accumulated
	 * hardware state from prior hangs. Tracing back: sheng_mdss_gcc_
	 * disp_hf_axi_clk_enable() (`*cbcr |= 1u`, a WRITE) was never
	 * actually called in either of the two builds that DID boot
	 * successfully this session (boot-wrapper-read-no-rsc.img,
	 * boot-dpu-read-no-rsc.img both stopped before reaching it, at the
	 * time dead code). Given this session's core finding -- DPU writes
	 * hang, DPU reads don't -- it's plausible the same asymmetry
	 * applies to this GCC clock-controller write too. RESULT: booted
	 * fine -- this write is NOT the issue. Ruled out.
	 *
	 * RESOLVED (SPEC.md task #5 log): the sheng_mdss_gcc_disp_hf_axi_
	 * clk_enable() call that used to sit here has MOVED UP to the MDSS
	 * clock bulk beside sheng_mdss_dispcc_init(), where Linux's
	 * msm_mdss_enable() puts it. Enabling the AXI data-path clock at
	 * this point in probe -- i.e. AFTER sheng_mdss_dsi_panel_init() --
	 * was the root cause of this driver's long-standing DSI command
	 * DMA hang: the engine's packet fetch is an AXI read, and with the
	 * bus unclocked it never returned. See the call's new site for the
	 * full FIFO_STATUS forensics. Do not move it back down here.
	 */

	/* CONFIRMED (see SPEC.md task #5 log): sheng_mdss_bind() itself was
	 * the cause of every "post-RSC" hang, not the DPU/GCC/RSC/framebuffer
	 * math investigated above -- it runs during a pre-relocation DM
	 * bind pass that's independently fragile on this board (see the
	 * "RESOLVED: CONFIG_VIDEO early-boot hang" entry further down this
	 * file for the earlier, related pre-relocation fragility). Removed
	 * .bind entirely. Instead, self-allocate the framebuffer here in
	 * probe() (stable, post-relocation context) by setting plat->base
	 * directly -- alloc_fb() in video-uclass.c explicitly supports this
	 * ("Allow drivers to allocate the frame buffer themselves": if
	 * (plat->base) return 0;), completely bypassing the fragile
	 * bind-time reservation path. SHENG_MDSS_FB_ADDR is manually chosen
	 * DRAM, clear of SHENG_MDSS_DSI_DMA_SCRATCH (0xa0100000) and well
	 * below where kernel/dtb get lmb_alloc'd later in boot -- see
	 * SPEC.md's memory-map notes.
	 */
	/* NEW TEST: never tried a WRITE to the MDSS wrapper (0xae00000)
	 * before -- only reads (proven safe, real HW_VERSION value) and
	 * DPU writes (proven to hang unconditionally). This is a genuinely
	 * untested boundary: does the firewall/gate sit exactly at
	 * 0xae01000 (DPU core), or does it already cover part of the
	 * wrapper's own register window? Target offset 0x0 (HW_VERSION,
	 * nominally read-only) specifically so even if the write has no
	 * software effect, the bus still has to ack the transaction --
	 * that's the actual thing being tested, not the register's value.
	 * See SPEC.md's task #5 log.
	 */
	sheng_mdss_log_reset();
	{
		volatile u32 *wrapper_hwver = (volatile u32 *)(uintptr_t)(SM8550_MDSS_WRAPPER_BASE + 0x0);
		u32 val = *wrapper_hwver;

		*wrapper_hwver = val;
		sheng_mdss_log(SHENG_LOG_WRAPPER_WRITE_RET, 1); /* survived the write */
		sheng_mdss_log(SHENG_LOG_WRAPPER_WRITE_READBACK, *wrapper_hwver);
	}

	plat->base = SHENG_MDSS_FB_ADDR;

	uc_priv->xsize = 3048;
	uc_priv->ysize = 2032;
	uc_priv->bpix = VIDEO_BPP32;
	/* CHANNEL ORDER, measured on the live panel via Linux /dev/fb0:
	 * writing u32 0xFF0000FF renders BLUE, so the low byte is blue and
	 * memory order is B,G,R,A -- i.e. u32 0xAARRGGBB, which is U-Boot's
	 * VIDEO_X8R8G8B8. The driver never set .format at all, leaving it
	 * VIDEO_UNKNOWN, so the uclass's colour conversion was wrong: that
	 * is why video_clear() painted the screen WHITE instead of black. */
	uc_priv->format = VIDEO_X8R8G8B8;
	uc_priv->rot = 0;

	/* STRIDE MUST MATCH THE DPU, NOT THE NAIVE WIDTH.
	 *
	 * sheng_mdss_dpu_start() programs SSPP_SRC_YSTRIDE0 as
	 * ALIGN(3048,32) * 4 = 3072 * 4 = 12288, matching live silicon. The
	 * video uclass would otherwise compute xsize * bpp = 3048 * 4 =
	 * 12192, so every console line would land 96 bytes short of where
	 * the DPU fetches it -- text skews progressively down the screen
	 * while a solid fill still looks perfect, which is exactly what we
	 * saw (green fine, console "super glitchy").
	 *
	 * video_post_probe() only computes line_length when the driver has
	 * not set one (`if (!priv->line_length)`), so presetting it here
	 * wins. plat->size has to use the same stride or the last rows fall
	 * outside the mapped framebuffer. */
	uc_priv->line_length = SHENG_MDSS_FB_STRIDE;
	plat->size = (u32)SHENG_MDSS_FB_STRIDE * uc_priv->ysize;

	sheng_mdss_log(SHENG_LOG_PLAT_BASE, (u32)plat->base);

	/* Let video_post_probe() run this time -- that's the actual test:
	 * does video_clear() survive with a manually-chosen, definitely-
	 * real DRAM plat->base instead of relying on the fragile bind-time
	 * mechanism? sheng_mdss_dpu_start() stays unreachable regardless
	 * (separate, already-confirmed problem: DPU writes hang).
	 */
	return 0;

	ret = sheng_mdss_dpu_start(SM8550_MDSS_DPU_BASE,
				    SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    plat->base,
				    uc_priv->xsize, uc_priv->ysize,
				    SHENG_PANEL_HFRONT_PORCH, SHENG_PANEL_HBACK_PORCH,
				    SHENG_PANEL_HSYNC_WIDTH,
				    SHENG_PANEL_VFRONT_PORCH, SHENG_PANEL_VBACK_PORCH,
				    SHENG_PANEL_VSYNC_WIDTH,
				    true);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DPU, ret);
	BBS("dpu_start_ret", ret);
	if (ret) {
		BBM("ABORT: dpu_start failed");
		sheng_mdss_final_dump();
		return ret;
	}

	sheng_mdss_final_dump();

	video_set_flush_dcache(dev, true);
	return 0;
}

/* Everything worth having, dumped once at the end of probe.
 *
 * This is the payload the 512-byte cmdline could never carry. Each sweep
 * so far reported only "(first mismatching offset << 32) | count" -- so
 * when PHY1 came back with a single mismatch at 0x144 we could not see
 * what the value actually WAS without spending another build on it, and
 * when the DSI host swept clean we never saw the values it swept against.
 * Dump the real contents of every block instead, once, and diff offline
 * against the same registers read from a rendering Linux via devmem. */
static void sheng_mdss_final_dump(void)
{
	BBM("=== FINAL STATE DUMP ===");

	/* DSI hosts: full 0x000-0x2fc, the same span dsi_sweep_table covers. */
	BBB("DSI0", SM8550_MDSS_DSI0_BASE, 0x000, 192);
	BBB("DSI1", SM8550_MDSS_DSI1_BASE, 0x000, 192);

	/* Both PHYs: CMN (0x000-0x1fc) and the lane block (0x200-0x47c).
	 * PHY1's lane block was only ever checked as a pass/fail count. */
	BBB("PHY0_CMN", SM8550_MDSS_DSI0_PHY_BASE, 0x000, 128);
	BBB("PHY0_LANE", SM8550_MDSS_DSI0_PHY_BASE, 0x200, 160);
	BBB("PHY0_PLL", SM8550_MDSS_DSI0_PHY_BASE, 0x500, 128);
	BBB("PHY1_CMN", SM8550_MDSS_DSI1_PHY_BASE, 0x000, 128);
	BBB("PHY1_LANE", SM8550_MDSS_DSI1_PHY_BASE, 0x200, 160);
	BBB("PHY1_PLL", SM8550_MDSS_DSI1_PHY_BASE, 0x500, 128);

	/* DPU: the blocks sheng_mdss_dpu_start() programs. Offsets are from
	 * dpu_base; see the block map at the top of sheng_mdss_hw.zig. */
	BBB("DPU_TOP", SM8550_MDSS_DPU_BASE, 0x000, 64);
	BBB("DPU_CTL0", SM8550_MDSS_DPU_BASE + 0x15000, 0x000, 64);
	BBB("DPU_SSPP_DMA0", SM8550_MDSS_DPU_BASE + 0x24000, 0x000, 96);
	BBB("DPU_INTF1", SM8550_MDSS_DPU_BASE + 0x35000, 0x000, 64);
	BBB("DPU_INTF2", SM8550_MDSS_DPU_BASE + 0x36000, 0x000, 64);
	BBB("DPU_LM0", SM8550_MDSS_DPU_BASE + 0x44000, 0x000, 32);
	BBB("DPU_LM1", SM8550_MDSS_DPU_BASE + 0x45000, 0x000, 32);
	BBB("DPU_MERGE3D", SM8550_MDSS_DPU_BASE + 0x4e000, 0x000, 16);
	BBB("DPU_PP0", SM8550_MDSS_DPU_BASE + 0x69000, 0x000, 48);
	BBB("DPU_PP1", SM8550_MDSS_DPU_BASE + 0x6a000, 0x000, 48);
	BBB("DPU_DCE", SM8550_MDSS_DPU_BASE + 0x80000, 0x000, 64);

	/* Full-width versions of the blocks that were previously truncated.
	 * Catalog lengths: sspp 0x344, ctl 0x290, lm 0x400, intf 0x300. */
	BBB("SSPP_DMA0_FULL", SM8550_MDSS_DPU_BASE + 0x24000, 0x000, 209);
	BBB("CTL0_FULL", SM8550_MDSS_DPU_BASE + 0x15000, 0x000, 164);
	BBB("LM0_FULL", SM8550_MDSS_DPU_BASE + 0x44000, 0x000, 128);
	BBB("LM1_FULL", SM8550_MDSS_DPU_BASE + 0x45000, 0x000, 128);
	BBB("INTF1_FULL", SM8550_MDSS_DPU_BASE + 0x35000, 0x000, 192);
	BBB("INTF2_FULL", SM8550_MDSS_DPU_BASE + 0x36000, 0x000, 192);
	BBB("PP0_FULL", SM8550_MDSS_DPU_BASE + 0x69000, 0x000, 64);
	BBB("PP1_FULL", SM8550_MDSS_DPU_BASE + 0x6a000, 0x000, 64);

	/* MDSS wrapper + VBIF + the whole DISPCC clock controller. */
	BBB("MDSS_TOP", SM8550_MDSS_BASE, 0x000, 32);
	/* VBIF is a separate ioremap (reg-names = "mdp", "vbif"), not an
	 * offset from dpu_base -- see sheng_mdss_vbif_init(). */
	BBB("VBIF", 0x0aeb0000, 0x000, 64);
	BBB("DISPCC", SM8550_DISPCC_BASE, 0x000, 128);
	BBB("DISPCC_MDSS", SM8550_DISPCC_BASE, 0x8000, 128);

	/* DSC LAST, DELIBERATELY.
	 *
	 * Reading an unclocked MDSS sub-block wedges this hardware's AHB bus --
	 * a mis-typed address into a neighbouring DPU block rebooted the device
	 * outright while capturing the Linux-side reference. We enable DSC, so
	 * these should be live, but "should" is not "verified": if this hangs,
	 * everything above it has already been sealed to the blackbox (sealing
	 * happens after every record), so the log is still recoverable and the
	 * hang itself localises the problem to exactly these offsets.
	 */
	/* DSC -- THE BLOCK WE HAVE NEVER ACTUALLY COMPARED.
	 *
	 * dpu_9_0_sm8550.h gives dsc_0/dsc_1 base = 0x80000 and dsc_2/dsc_3
	 * base = 0x81000, but the real registers are in SUB-BLOCKS:
	 * dpu_hw_catalog.c's dsc_sblk_0 = { .enc = +0x100 len 0x9c,
	 * .ctl = +0xF00 len 0x10 } and dsc_sblk_1 = { .enc = +0x200 ... }.
	 *
	 * Every previous dump covered 0x80000-0x800fc -- the empty gap BEFORE
	 * the encoder -- which is why it read 0x101 then all zeros on BOTH
	 * U-Boot and a rendering Linux and looked like a match. The DSC
	 * encoder configuration has never been compared at all.
	 *
	 * This matters more than anything else left: the panel's DSC decoder
	 * is configured by the 128-byte PPS (now proven transmitted, byte
	 * identical to Linux), while the DPU's DSC ENCODER is configured
	 * separately by us. If those two disagree the panel receives a
	 * compressed stream it cannot decode -- and shows black while every
	 * other register in the system reads correct. */
	BBB("DSC0_ENC", SM8550_MDSS_DPU_BASE + 0x80000, 0x100, 40);
	BBB("DSC1_ENC", SM8550_MDSS_DPU_BASE + 0x80000, 0x200, 40);
	BBB("DSC0_CTL", SM8550_MDSS_DPU_BASE + 0x80000, 0xf00, 8);
	BBB("DSC2_ENC", SM8550_MDSS_DPU_BASE + 0x81000, 0x100, 40);
	BBB("DSC3_ENC", SM8550_MDSS_DPU_BASE + 0x81000, 0x200, 40);
	BBB("DSC2_CTL", SM8550_MDSS_DPU_BASE + 0x81000, 0xf00, 8);
	BBM("=== DUMP COMPLETE ===");
	sheng_bb_finish();
}

static const struct udevice_id sheng_mdss_ids[] = {
	{ .compatible = "qcom,sm8550-mdss" },
	{ }
};

/* No .bind -- see sheng_mdss_probe()'s comment on SHENG_MDSS_FB_ADDR for
 * why: a .bind hook (even one doing nothing but a single struct write)
 * reliably hung the board, confirmed via bisection this session. The
 * framebuffer is self-allocated directly in .probe instead. */
U_BOOT_DRIVER(sheng_mdss) = {
	.name		= "sheng_mdss",
	.id		= UCLASS_VIDEO,
	.of_match	= sheng_mdss_ids,
	.probe		= sheng_mdss_probe,
	.priv_auto	= sizeof(struct sheng_mdss_priv),
};
