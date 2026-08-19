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
	major = (rsc_id >> 16) & 0xff;
	regs = (major == 3) ? &rsc_regs_v3_0 : &rsc_regs_v2_7;

	for (i = 0; i < APPS_RSC_ACTIVE_TCS_COUNT; i++) {
		int id = APPS_RSC_ACTIVE_TCS_FIRST + i;

		if (readl(rsc_tcs_reg(tcs_base, regs, regs->status, id))) {
			tcs_id = id;
			break;
		}
	}
	sheng_mdss_log(SHENG_LOG_MMCX_TCS_ID, (u32)tcs_id);
	if (tcs_id < 0)
		return -EBUSY;

	cmd_msgid = CMD_MSGID_BASE | CMD_MSGID_RESP_REQ | CMD_MSGID_WRITE;
	writel(cmd_msgid, rsc_cmd_reg(tcs_base, regs, regs->cmd_msgid, tcs_id));
	writel(resource_addr, rsc_cmd_reg(tcs_base, regs, regs->cmd_addr, tcs_id));
	writel(data, rsc_cmd_reg(tcs_base, regs, regs->cmd_data, tcs_id));

	writel(readl(rsc_tcs_reg(tcs_base, regs, regs->cmd_enable, tcs_id)) | 1u,
	       rsc_tcs_reg(tcs_base, regs, regs->cmd_enable, tcs_id));
	writel(1u, rsc_tcs_reg(tcs_base, regs, regs->cmd_wait_for_cmpl, tcs_id));

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

static int sheng_mdss_mmcx_power_on(void)
{
	u32 addr;
	const u16 *levels;
	size_t len, count, i;
	u32 corner;

	addr = cmd_db_read_addr("mmcx.lvl");
	sheng_mdss_log(SHENG_LOG_CMDDB_MMCX_ADDR, addr);
	if (!addr)
		return -ENODEV;

	levels = cmd_db_read_aux_data("mmcx.lvl", &len);
	if (IS_ERR(levels))
		return PTR_ERR(levels);

	count = len >> 1;

	/* Mirror rpmhpd_set_performance_state() (drivers/pmdomain/qcom/
	 * rpmhpd.c): pick the smallest corner whose level is >= the
	 * required performance level, clamping to the max corner if none
	 * qualifies (its own "if the level requested is more than that
	 * supported by the max corner, just set it to max anyway"). */
	corner = count ? (u32)(count - 1) : 0;
	for (i = 0; i < count; i++) {
		if (levels[i] >= RPMH_REGULATOR_LEVEL_NOM) {
			corner = i;
			break;
		}
	}
	sheng_mdss_log(SHENG_LOG_MMCX_CORNER, corner);
	sheng_mdss_log(SHENG_LOG_MMCX_LEVEL_PICKED, corner < count ? levels[corner] : 0);

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

static void sheng_mdss_backlight_gpio_enable(void)
{
	volatile u32 *ctl = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * TLMM_BACKLIGHT_GPIO);
	volatile u32 *io = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * TLMM_BACKLIGHT_GPIO);
	u32 v;

	v = *ctl;
	v &= ~TLMM_MUX_FUNC_MASK; /* native GPIO function (msm_mux_gpio = 0) */
	v |= TLMM_OE_BIT;
	*ctl = v;

	v = *io;
	v |= TLMM_OUT_BIT;
	*io = v;
}

static int sheng_mdss_bcm_vote(const char *bcm_name)
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
				 u32 vfront_porch, u32 vback_porch, u32 vsync_width);

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

	ret = sheng_mdss_dispcc_init(SM8550_DISPCC_BASE);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DISPCC, ret);
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

	/* BISECTION: reset-toggle + GDSC + DISPCC confirmed reaching Linux.
	 * Next: add both DSI PHYs back and stop before DSI panel init.
	 */

	/* Dual-DSI split-link panel: DSI0 is master (drives its own PLL),
	 * DSI1 is slave (sources its bit clock from DSI0 over
	 * qcom,sync-dual-dsi) -- see sheng_mdss_dsi_phy_init()'s comment
	 * in sheng_mdss_hw.zig. Both must succeed. */
	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI0_PHY_BASE, true);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI0_PHY, ret);
	if (ret)
		return ret;

	ret = sheng_mdss_dsi_phy_init(SM8550_MDSS_DSI1_PHY_BASE, false);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI1_PHY, ret);
	if (ret)
		return ret;

	/* BISECTION: reset-toggle + GDSC + DISPCC + both DSI PHYs confirmed
	 * reaching Linux. Next: add DSI panel init back and stop right
	 * after it -- this re-creates the last known-good stopping point
	 * from before this session's reset-toggle work, just with the new
	 * reset call now running first.
	 */
	/* DPU-bypass proof-of-concept (SPEC.md task #5): enable_dsc=false
	 * here -- the real pipeline needs DSC, but this experiment pushes
	 * raw uncompressed pixels directly over DSI command mode and must
	 * NOT have DSC enabled on the panel side, or it'll try to decode
	 * garbage. Revert to true before ever resuming real dpu_start()
	 * work (which is unreachable below regardless, for now). */
	ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
					 SHENG_MDSS_DSI_DMA_SCRATCH, false);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI_PANEL, ret);
	if (ret)
		return ret;

	/* Backlight enable (GPIO 128) -- see its own comment above. Cheap,
	 * independent peripheral, unrelated to DSI/DPU; done here so it's
	 * on by the time the test patch below lands, for a chance at an
	 * actual visible result this time. */
	sheng_mdss_backlight_gpio_enable();

	/* Push a small solid-red 16x16 RGB888 patch directly to the panel
	 * over the DSI command-mode DMA engine, entirely bypassing the DPU
	 * (0xae01000+) -- see sheng_mdss_dsi_test_patch()'s comment in
	 * sheng_mdss_hw.zig. If this survives and a red square appears now
	 * that backlight is on too, we have a genuinely confirmed
	 * pixel-output path independent of the still-unsolved DPU write
	 * hang.
	 */
	ret = sheng_mdss_dsi_test_patch(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
					 SHENG_MDSS_DSI_DMA_SCRATCH);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DPU, ret); /* reusing the DPU slot for this experiment */
	if (ret)
		return ret;

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
				    SHENG_PANEL_VSYNC_WIDTH);
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
