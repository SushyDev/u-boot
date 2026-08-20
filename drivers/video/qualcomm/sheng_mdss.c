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
#define SHENG_MDSS_DSI_DMA_SCRATCH	0x8bb500000

/* 24.8MB (3048*2032*4 XRGB8888), starting 1MB above
 * SHENG_MDSS_DSI_DMA_SCRATCH, ending ~0xa4b10000 -- comfortably within
 * the same free System RAM span, well clear of the next reserved
 * region (0xccd00000, rmtfs_mem). See SHENG_MDSS_DSI_DMA_SCRATCH's
 * comment for why this moved from its old 0xa0200000. */
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
void sheng_mdss_teardown(void)
{
	if (!IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS))
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

	priv->mdss_base = dev_read_addr(dev);
	if (priv->mdss_base == FDT_ADDR_T_NONE)
		return -EINVAL;

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
	sheng_mdss_raw_gpio_set(TLMM_PANEL_RESET_GPIO, 0); /* reset asserted */
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVEE_GPIO, 0);
	sheng_mdss_raw_gpio_set(TLMM_PANEL_AVDD_GPIO, 0);
	sheng_mdss_gdsc_disable(SM8550_DISPCC_BASE);
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
	env_set_hex("sheng_mdss_vreg_s3g", (unsigned long)ret);

	/* Dual-DSI split-link panel: DSI0 is master (drives its own PLL),
	 * DSI1 is slave (sources its bit clock from DSI0 over
	 * qcom,sync-dual-dsi) -- see sheng_mdss_dsi_phy_init()'s comment
	 * in sheng_mdss_hw.zig. Both must succeed. */
	sheng_mdss_dsi_reset_both_phys(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE);
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
	ret = sheng_mdss_dsi_panel_init(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE,
					 SHENG_MDSS_DSI_DMA_SCRATCH, true);
	sheng_mdss_status_set(SHENG_MDSS_STATUS_DSI_PANEL, ret);
	env_set_hex("sheng_mdss_panel", (unsigned long)ret);
	/* Single-host DCS read: the one test that would positively prove
	 * two-way communication with the panel. See its comment. */
	env_set_hex("sheng_mdss_rdsingle",
		    (unsigned long)sheng_mdss_dsi_read_power_mode_single(
			    SM8550_MDSS_DSI0_BASE, SHENG_MDSS_DSI_DMA_SCRATCH));
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
	{
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

		for (px = 0; px < fb_words; px++)
			fb[px] = 0xff00ff00u; /* XRGB8888 solid green */
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
	env_set_hex("sheng_mdss_dsi_vrb2",
		    (unsigned long)sheng_mdss_dsi_video_readback2(SM8550_MDSS_DSI0_BASE,
								 SM8550_MDSS_DSI1_BASE));

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
