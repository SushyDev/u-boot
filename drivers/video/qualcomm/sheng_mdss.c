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

static void sheng_mdss_backlight_gpio_enable(void)
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

static void sheng_mdss_panel_power_and_reset(void)
{
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 1);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 1);
	mdelay(1); /* regulator-enable-ramp-delay=233us on both, rounded up */

	/* nt36532e_reset(): reset_gpio is GPIO_ACTIVE_LOW in the real DT,
	 * requested GPIOD_OUT_HIGH (idle = logical 0 = physical HIGH, not
	 * in reset). gpiod_set_value_cansleep(gpio, 1) means *logical*
	 * assert, which the gpiod core inverts to *physical* LOW for an
	 * active-low line -- translating the real driver's exact sequence
	 * to raw physical pin levels: */
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* logical 1 = physical LOW: reset asserted */
	mdelay(11);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 1); /* logical 0 = physical HIGH: deasserted */
	mdelay(4);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* logical 1 = physical LOW: asserted again */
	mdelay(4);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 1); /* logical 0 = physical HIGH: deasserted, panel ready */
	mdelay(16);
}

static int __maybe_unused sheng_mdss_bcm_vote(const char *bcm_name)
{
	u32 addr;
	u32 data;

	addr = cmd_db_read_addr(bcm_name);
	sheng_mdss_log(SHENG_LOG_CMDDB_MM0_ADDR, addr);
	if (!addr)
		return -ENODEV;

	data = (1u << 30) /* commit */ | (1u << 29) /* valid */ |
	       ((1u & 0x3fff) << 14) /* vote_x */ | (1u & 0x3fff) /* vote_y */;

	return rsc_send_active_write(addr, data);
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
#define SM8550_MDSS_DPU_BASE		0x0ae01000
#define SM8550_MDSS_DSI0_BASE		0x0ae94000
#define SM8550_MDSS_DSI0_PHY_BASE	0x0ae95000
#define SM8550_MDSS_DSI1_PHY_BASE	0x0ae97000
#define SM8550_MDSS_DSI1_BASE		0x0ae96000
#define SM8550_DISPCC_BASE		0x0af00000

/* Fixed physical DRAM scratch address the DSI DMA engine reads
 * command packets from. Real usable DRAM starts at 0xa0000000 (see
 * SPEC.md); 1MB in is comfortably clear of anything else touched this
 * early in boot (kernel/dtb loads happen later, in board_late_init,
 * at much higher addresses via lmb_alloc). Only needs to hold the
 * largest single DCS command we send (well under 4KB). */
#define SHENG_MDSS_DSI_DMA_SCRATCH	0xa0100000

/* Fixed physical DRAM framebuffer address, self-allocated by
 * sheng_mdss_probe() (see its comment for why: alloc_fb()'s bind-time
 * automatic reservation path is unusable on this board). 2MB in, clear
 * of SHENG_MDSS_DSI_DMA_SCRATCH above (1MB in, well under 4KB used) and
 * everything else touched this early in boot; needs ~24.8MB
 * (3048*2032*4 XRGB8888), ending well below 0xd8100000 (xbl-sc-region,
 * the nearest higher reserved region per SPEC.md's memory map). */
#define SHENG_MDSS_FB_ADDR		0xa0200000

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
extern int sheng_mdss_dispcc_init(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_dsi_clks_init(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_pll0_only(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_ahb(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_mdp(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_thru_mdp_rcg_only(unsigned long dispcc_base);
extern int sheng_mdss_dispcc_init_no_mdp_branch(unsigned long dispcc_base);
extern int sheng_mdss_dsi_phy_init(unsigned long dsi_phy_base, bool is_master);
extern int sheng_mdss_dsi_panel_init(unsigned long dsi0_base, unsigned long dsi1_base,
				      unsigned long dma_scratch, bool enable_dsc);
extern int sheng_mdss_dsi_test_patch(unsigned long dsi0_base, unsigned long dsi1_base,
				      unsigned long dma_scratch);
extern int sheng_mdss_dpu_start(unsigned long dpu_base,
				 unsigned long dsi0_base, unsigned long dsi1_base,
				 unsigned long fb_addr,
				 u32 hactive, u32 vactive,
				 u32 hfront_porch, u32 hback_porch, u32 hsync_width,
				 u32 vfront_porch, u32 vback_porch, u32 vsync_width,
				 bool enable_dsc);

struct sheng_mdss_priv {
	fdt_addr_t mdss_base;
};

static int sheng_mdss_probe(struct udevice *dev)
{
	struct sheng_mdss_priv *priv = dev_get_priv(dev);
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);
	struct video_priv *uc_priv = dev_get_uclass_priv(dev);
	int ret;

	priv->mdss_base = dev_read_addr(dev);
	if (priv->mdss_base == FDT_ADDR_T_NONE)
		return -EINVAL;

	for (unsigned int i = 0; i < SHENG_MDSS_STATUS_COUNT; i++)
		sheng_mdss_status_set(i, SHENG_MDSS_STATUS_NOT_REACHED);

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
	sheng_mdss_status_set(SHENG_MDSS_STATUS_MDSS_RESET, 0);

	/* BISECTION: reset-toggle + GDSC confirmed reaching Linux. Next:
	 * add DISPCC (PLL0 + AHB/MDP clocks) back and stop right after it,
	 * before DSI PHY.
	 */
	ret = sheng_mdss_gdsc_enable(SM8550_DISPCC_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_GDSC, ret);
	if (ret) {
		log_debug("sheng_mdss: GDSC bring-up failed (%d)\n", ret);
		return ret;
	}

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
	ret = sheng_mdss_dispcc_init(SM8550_DISPCC_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DISPCC, ret);
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

	/* Dual-DSI split-link panel: DSI0 is master (drives its own PLL),
	 * DSI1 is slave (sources its bit clock from DSI0 over
	 * qcom,sync-dual-dsi) -- see sheng_mdss_dsi_phy_init()'s comment
	 * in sheng_mdss_hw.zig. Both must succeed. */
	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI0_PHY_BASE, true);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI0_PHY, ret);
	env_set_hex("sheng_mdss_dsi0_phy", (unsigned long)ret);
	if (ret)
		return ret;

	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI1_PHY_BASE, false);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI1_PHY, ret);
	env_set_hex("sheng_mdss_dsi1_phy", (unsigned long)ret);
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
	env_set_hex("sheng_mdss_dsi_clks", (unsigned long)ret);
	if (ret)
		return ret;

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
	sheng_mdss_panel_power_and_reset();

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
	 * Back to enable_dsc=true, the real/correct configuration. */
	ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
					 SHENG_MDSS_DSI_DMA_SCRATCH, true);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI_PANEL, ret);
	env_set_hex("sheng_mdss_panel", (unsigned long)ret);
	if (ret)
		return ret;

	/* Real panel timings (sheng_tianma_modes[], panel-novatek-
	 * nt36532e.c): 3048x2032, hfp=142 hsync=4 hbp=92, vfp=26 vsync=2
	 * vbp=138. */
	{
		volatile u32 *fb = (volatile u32 *)(uintptr_t)SHENG_MDSS_FB_ADDR;
		size_t fb_pixels = (size_t)3048 * 2032;
		size_t px;

		for (px = 0; px < fb_pixels; px++)
			fb[px] = 0xff00ff00u; /* XRGB8888 solid green */
		flush_dcache_range(SHENG_MDSS_FB_ADDR,
				    SHENG_MDSS_FB_ADDR + fb_pixels * 4);
		dsb();
	}

	ret = sheng_mdss_dpu_start(SM8550_MDSS_DPU_BASE,
				    SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
				    SHENG_MDSS_FB_ADDR,
				    3048, 2032,
				    142, 92, 4,
				    26, 138, 2,
				    true); /* DSC ruled out as the blocker -- see comment above */
	env_set_hex("sheng_mdss_dpu_start", (unsigned long)ret);
	if (ret)
		return ret;

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

		env_set_hex("sheng_intf1_frame_a", (unsigned long)*intf1_frame);
		env_set_hex("sheng_intf1_line_a", (unsigned long)*intf1_line);
		mdelay(500);
		env_set_hex("sheng_intf1_frame_b", (unsigned long)*intf1_frame);
		env_set_hex("sheng_intf1_line_b", (unsigned long)*intf1_line);
	}

	/* No large hold here anymore -- board.c calls backlight init
	 * AFTER this probe() returns, with its own 5s hold at the end.
	 * Holding here would delay backlight turning on at all (exactly
	 * what made it "come on very late" before this was found). */
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
	 */
	sheng_mdss_gcc_disp_hf_axi_clk_enable();

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
	uc_priv->rot = 0;

	plat->size = (u32)uc_priv->xsize * uc_priv->ysize * VNBYTES(uc_priv->bpix);

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
	if (ret)
		return ret;

	video_set_flush_dcache(dev, true);
	return 0;
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
