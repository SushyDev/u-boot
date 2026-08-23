// SPDX-License-Identifier: GPL-2.0+
/*
 * Debug side channels for the sheng MDSS driver. Built only when
 * CONFIG_VIDEO_SHENG_MDSS_DEBUG=y; see sheng_mdss_debug.h for the API.
 *
 * Everything here writes DRAM at fixed physical addresses inside the
 * region CONFIG_PRE_CON_BUF_ADDR already reserves. board.c's
 * ft_board_setup() relays the results into /chosen.
 */

#include <env.h>
#include <lmb.h>
#include <log.h>
#include <vsprintf.h>
#include <asm/global_data.h>
#include <asm/io.h>
#include <asm/barriers.h>
#include <cpu_func.h>
#include <linux/delay.h>
#include <linux/kconfig.h>
#include <linux/types.h>
#include <stdbool.h>

DECLARE_GLOBAL_DATA_PTR;

#include "sheng_mdss_debug.h"
#include "sheng_mdss_regs.h"

/* Must match BB_BASE / BB_HDR + BB_CAP in sheng_mdss_hw.zig. */
#define SHENG_BB_BASE			0xa5000000
#define SHENG_BB_SIZE			(16 + 512 * 1024)

/* D-cache is on. A breadcrumb left dirty in a cache line never reaches
 * DRAM if the next instruction hangs the CPU -- which is the case this
 * whole channel exists to survive. Push every record to the point of
 * coherency before returning. */
static void breadcrumb_flush(uintptr_t addr, size_t len)
{
	flush_dcache_range(addr, addr + len);
	dsb();
}

void sheng_mdss_debug_log(unsigned int tag, unsigned int value)
{
	volatile struct sheng_blackbox *bb = SHENG_BLACKBOX;
	u32 n;

	if (!IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
		return;

	n = bb->log.count;
	if (n >= SHENG_MDSS_LOG_MAX)
		return;

	bb->log.entry[n].tag = tag;
	bb->log.entry[n].value = value;
	bb->log.count = n + 1;
	breadcrumb_flush((uintptr_t)&bb->log,
			 sizeof(bb->log.count) + (n + 1) * sizeof(bb->log.entry[0]));
}

/* CFG in the high half, IN_OUT in the low half. In IN_OUT, bit 0 is the
 * value driven and bit 1 is what the pad actually reads: a pin driven
 * low must read 0. Anything else means something is holding the line. */
void sheng_mdss_debug_pin(const char *name, unsigned int gpio)
{
	volatile u32 *ctl = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + TLMM_GPIO_REG_SIZE * gpio);
	volatile u32 *io = (volatile u32 *)(uintptr_t)
		(SM8550_TLMM_BASE + 0x4 + TLMM_GPIO_REG_SIZE * gpio);

	sheng_bb_val(name, (((unsigned long long)*ctl) << 32) | *io);
}

void sheng_mdss_debug_env(const char *name, unsigned long long v)
{
	env_set_hex(name, (unsigned long)v);
}

void sheng_mdss_debug_start(void)
{
	volatile struct sheng_blackbox *bb = SHENG_BLACKBOX;

	if (IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
		bb->log.count = 0;
		breadcrumb_flush((uintptr_t)&bb->log.count,
				 sizeof(bb->log.count));
	}

	/* Reserve the blackbox for the same reason the driver reserves its
	 * framebuffer: it is a fixed address that U-Boot's allocator knows
	 * nothing about, and board_late_init() allocates after this runs. */
	{
		phys_addr_t bb = SHENG_BB_BASE;

		if (lmb_alloc_mem(LMB_MEM_ALLOC_ADDR, 0, &bb, SHENG_BB_SIZE, LMB_NONE))
			log_warning("sheng_mdss: blackbox not reserved\n");
	}

	sheng_bb_init();
}

void sheng_mdss_debug_finish(void)
{
	sheng_bb_finish();
}

/*
 * Every block the driver programs, dumped once. Diff offline against the
 * same registers read from a rendering Linux via devmem.
 *
 * DSC LAST, DELIBERATELY. Reading an unclocked MDSS sub-block wedges the
 * AHB bus, and recovery is fastboot. Records are sealed as they are
 * written, so a hang here still leaves everything above it readable and
 * localises the fault to these offsets.
 */
void sheng_mdss_debug_final_dump(void)
{
	BBM("=== FINAL STATE DUMP ===");

	BBB("DSI0", SM8550_MDSS_DSI0_BASE, 0x000, 192);
	BBB("DSI1", SM8550_MDSS_DSI1_BASE, 0x000, 192);

	BBB("PHY0_CMN", SM8550_MDSS_DSI0_PHY_BASE, 0x000, 128);
	BBB("PHY0_LANE", SM8550_MDSS_DSI0_PHY_BASE, 0x200, 160);
	BBB("PHY0_PLL", SM8550_MDSS_DSI0_PHY_BASE, 0x500, 128);
	BBB("PHY1_CMN", SM8550_MDSS_DSI1_PHY_BASE, 0x000, 128);
	BBB("PHY1_LANE", SM8550_MDSS_DSI1_PHY_BASE, 0x200, 160);
	BBB("PHY1_PLL", SM8550_MDSS_DSI1_PHY_BASE, 0x500, 128);

	BBB("DPU_TOP", SM8550_MDSS_DPU_BASE, 0x000, 64);
	BBB("DPU_CTL0", SM8550_MDSS_DPU_BASE + DPU_CTL0_OFF, 0x000, 164);
	BBB("DPU_SSPP_DMA0", SM8550_MDSS_DPU_BASE + DPU_SSPP_DMA0_OFF, 0x000, 209);
	BBB("DPU_INTF1", SM8550_MDSS_DPU_BASE + DPU_INTF1_OFF, 0x000, 192);
	BBB("DPU_INTF2", SM8550_MDSS_DPU_BASE + DPU_INTF2_OFF, 0x000, 192);
	BBB("DPU_LM0", SM8550_MDSS_DPU_BASE + DPU_LM0_OFF, 0x000, 128);
	BBB("DPU_LM1", SM8550_MDSS_DPU_BASE + DPU_LM1_OFF, 0x000, 128);
	BBB("DPU_MERGE3D", SM8550_MDSS_DPU_BASE + DPU_MERGE3D_OFF, 0x000, 16);
	BBB("DPU_PP0", SM8550_MDSS_DPU_BASE + DPU_PP0_OFF, 0x000, 64);
	BBB("DPU_PP1", SM8550_MDSS_DPU_BASE + DPU_PP1_OFF, 0x000, 64);

	BBB("MDSS_TOP", SM8550_MDSS_BASE, 0x000, 32);
	BBB("VBIF", SM8550_MDSS_VBIF_BASE, 0x000, 64);
	BBB("DISPCC", SM8550_DISPCC_BASE, 0x000, 128);
	BBB("DISPCC_MDSS", SM8550_DISPCC_BASE, 0x8000, 128);

	/* The DSC registers live in sub-blocks, not at the block base:
	 * enc at +0x100/+0x200, ctl at +0xf00. A dump of the base reads
	 * the empty gap before the encoder and matches anything. */
	BBB("DSC0_ENC", SM8550_MDSS_DPU_BASE + DPU_DCE0_OFF, 0x100, 40);
	BBB("DSC1_ENC", SM8550_MDSS_DPU_BASE + DPU_DCE0_OFF, 0x200, 40);
	BBB("DSC0_CTL", SM8550_MDSS_DPU_BASE + DPU_DCE0_OFF, 0xf00, 8);
	BBB("DSC2_ENC", SM8550_MDSS_DPU_BASE + DPU_DCE1_OFF, 0x100, 40);
	BBB("DSC3_ENC", SM8550_MDSS_DPU_BASE + DPU_DCE1_OFF, 0x200, 40);
	BBB("DSC2_CTL", SM8550_MDSS_DPU_BASE + DPU_DCE1_OFF, 0xf00, 8);

	BBM("=== DUMP COMPLETE ===");
	sheng_bb_finish();
}

/* Declared here rather than in a header: nothing outside this file may
 * call them. Reading an MDSS block once the display is down wedges the
 * AHB bus, and recovery is fastboot. */
unsigned int sheng_mdss_wrapper_audit(unsigned long mdss_base);
long long sheng_mdss_verify_pipeline(unsigned long dpu_base, unsigned long dsi0_base);
long long sheng_mdss_dsi_audit(unsigned long dsi0_base);
long long sheng_mdss_dsi1_audit(unsigned long dsi1_base);
long long sheng_mdss_dispcc_audit(unsigned long dispcc_base);
long long sheng_mdss_vbif_audit(unsigned long vbif_base);
long long sheng_mdss_phy_audit(unsigned long phy_base, bool is_master);
long long sheng_mdss_phy_state(unsigned long phy0_base, unsigned long phy1_base);
long long sheng_mdss_phy_status_raw(unsigned long phy0_base, unsigned long phy1_base);
long long sheng_mdss_phy_cmn_sweep(unsigned long phy_base);
long long sheng_mdss_phy1_cmn_sweep(unsigned long phy_base);
long long sheng_mdss_phy1_lane_sweep(unsigned long phy_base);
long long sheng_mdss_phy_lanepll_sweep(unsigned long phy_base);
long long sheng_mdss_phy144_marks(void);
long long sheng_mdss_dsi_sweep(unsigned long dsi_base);
long long sheng_mdss_dsi_txpath_state(unsigned long dsi0_base);
long long sheng_mdss_dsi_lane_activity(unsigned long dsi_base);
long long sheng_mdss_dsi_video_readback1(unsigned long dsi0_base);
long long sheng_mdss_dsi_video_readback2(unsigned long dsi0_base, unsigned long dsi1_base);
long long sheng_mdss_lane_status(unsigned long dsi0_base, unsigned long dsi1_base);
long long sheng_mdss_phy_err_both(unsigned long dsi0_base, unsigned long dsi1_base);
long long sheng_mdss_dsc_status1(unsigned long dpu_base);
long long sheng_mdss_dsc_status2(unsigned long dpu_base);
long long sheng_mdss_dpu_readback1(unsigned long dpu_base);
long long sheng_mdss_dpu_readback2(unsigned long dpu_base);
long long sheng_mdss_dpu_readback3(unsigned long dpu_base);
long long sheng_mdss_dpu_readback4(unsigned long dpu_base);
long long sheng_mdss_smmu_fault_diag(void);
long long sheng_mdss_smmu_fault_addr(void);
long long sheng_mdss_smmu_diag2(void);
unsigned int sheng_mdss_smmu_diag3(void);
unsigned int sheng_mdss_smmu_sctlr(void);
void sheng_mdss_gdsc_probe(unsigned long dispcc_base, unsigned int slot);
long long sheng_mdss_gdsc_probe_result(void);

/*
 * Sampled after dpu_start, with the pipeline streaming. The 500ms window
 * is the instrument, not padding: INTF_FRAME_COUNT advances once per
 * active-video frame, so frames-per-500ms is the real refresh rate and
 * therefore a direct measurement of the whole clock tree. Expect ~72 at
 * 144Hz. It also gives any SSPP translation fault ~28 frames to latch.
 */
void sheng_mdss_debug_post_dpu_report(void)
{
	volatile u32 *intf1_frame = (volatile u32 *)(uintptr_t)
		(SM8550_MDSS_DPU_BASE + DPU_INTF1_OFF + INTF_FRAME_COUNT);
	volatile u32 *intf1_line = (volatile u32 *)(uintptr_t)
		(SM8550_MDSS_DPU_BASE + DPU_INTF1_OFF + INTF_LINE_COUNT);
	u32 frame_a = *intf1_frame;

	SHENG_DBG_ENV("sheng_intf1_frame_a", frame_a);
	SHENG_DBG_ENV("sheng_intf1_line_a", *intf1_line);
	mdelay(500);
	SHENG_DBG_ENV("sheng_intf1_frame_b", *intf1_frame);
	SHENG_DBG_ENV("sheng_intf1_line_b", *intf1_line);

	sheng_mdss_gdsc_probe(SM8550_DISPCC_BASE, 2);
	SHENG_DBG_ENV("sheng_mdss_gdscp", sheng_mdss_gdsc_probe_result());
	SHENG_DBG_ENV("sheng_mdss_txpath",
		      sheng_mdss_dsi_txpath_state(SM8550_MDSS_DSI0_BASE));
	SHENG_DBG_ENV("sheng_mdss_lanact",
		      sheng_mdss_dsi_lane_activity(SM8550_MDSS_DSI0_BASE));
	SHENG_DBG_ENV("sheng_mdss_txpath1",
		      sheng_mdss_dsi_txpath_state(SM8550_MDSS_DSI1_BASE));
	/* Delta, so a nonzero starting count cannot fake a correct answer. */
	SHENG_DBG_ENV("sheng_mdss_framedelta", *intf1_frame - frame_a);

	/* fault = [63:32] context-bank FSR, [31:0] global GFSR; far = the
	 * faulting address. Both zero means translation is fine and a black
	 * screen is downstream of the pixel fetch. */
	SHENG_DBG_ENV("sheng_mdss_smmu_fault", sheng_mdss_smmu_fault_diag());
	SHENG_DBG_ENV("sheng_mdss_smmu_far", sheng_mdss_smmu_fault_addr());
	BBS("smmu_fault(FSR<<32|GFSR)", sheng_mdss_smmu_fault_diag());
	BBS("smmu_far", sheng_mdss_smmu_fault_addr());
	BBS("smmu_cbx|s2cr_before", sheng_mdss_smmu_diag2());
	/* SCTLR.M must read 0 -- the MDSS stream runs stage-1 passthrough. */
	BBV("smmu_sctlr", sheng_mdss_smmu_sctlr());
	BBV("smmu_s2cr_after", sheng_mdss_smmu_diag3());


	/* Audits return 0 when every programmed register matches the
	 * live-hardware reference table; otherwise
	 * (first mismatching offset << 32) | count. */
	SHENG_DBG_ENV("sheng_mdss_wrap", sheng_mdss_wrapper_audit(SM8550_MDSS_BASE));
	SHENG_DBG_ENV("sheng_mdss_dsi1_audit", sheng_mdss_dsi1_audit(SM8550_MDSS_DSI1_BASE));
	SHENG_DBG_ENV("sheng_mdss_dsi_audit", sheng_mdss_dsi_audit(SM8550_MDSS_DSI0_BASE));
	SHENG_DBG_ENV("sheng_mdss_dispcc_audit", sheng_mdss_dispcc_audit(SM8550_DISPCC_BASE));
	SHENG_DBG_ENV("sheng_mdss_vbif", sheng_mdss_vbif_audit(SM8550_MDSS_VBIF_BASE));
	SHENG_DBG_ENV("sheng_mdss_phystat",
		      sheng_mdss_phy_state(SM8550_MDSS_DSI0_PHY_BASE,
					   SM8550_MDSS_DSI1_PHY_BASE));
	SHENG_DBG_ENV("sheng_mdss_clkstat_post",
		      (((unsigned long long)*(volatile u32 *)(uintptr_t)
			(SM8550_MDSS_DSI0_BASE + 0x11c)) << 32) |
		      *(volatile u32 *)(uintptr_t)(SM8550_MDSS_DSI1_BASE + 0x11c));

	BBM("diag: dsi sweep");
	SHENG_DBG_ENV("sheng_mdss_dsisweep", sheng_mdss_dsi_sweep(SM8550_MDSS_DSI0_BASE));
	BBM("diag: phy lanepll sweep");
	SHENG_DBG_ENV("sheng_mdss_lpsweep",
		      sheng_mdss_phy_lanepll_sweep(SM8550_MDSS_DSI0_PHY_BASE));
	BBM("diag: phy cmn sweep");
	SHENG_DBG_ENV("sheng_mdss_cmnsweep",
		      sheng_mdss_phy_cmn_sweep(SM8550_MDSS_DSI0_PHY_BASE));
	BBM("diag: phy1 cmn sweep");
	SHENG_DBG_ENV("sheng_mdss_phy1_sweep",
		      sheng_mdss_phy1_cmn_sweep(SM8550_MDSS_DSI1_PHY_BASE));
	BBM("diag: phy1 lane sweep");
	SHENG_DBG_ENV("sheng_mdss_phy1_lane",
		      sheng_mdss_phy1_lane_sweep(SM8550_MDSS_DSI1_PHY_BASE));
	SHENG_DBG_ENV("sheng_mdss_phystatraw",
		      sheng_mdss_phy_status_raw(SM8550_MDSS_DSI0_PHY_BASE,
						SM8550_MDSS_DSI1_PHY_BASE));
	SHENG_DBG_ENV("sheng_mdss_p144", sheng_mdss_phy144_marks());
	SHENG_DBG_ENV("sheng_mdss_phy0_audit",
		      sheng_mdss_phy_audit(SM8550_MDSS_DSI0_PHY_BASE, true));
	SHENG_DBG_ENV("sheng_mdss_phy1_audit",
		      sheng_mdss_phy_audit(SM8550_MDSS_DSI1_PHY_BASE, false));
	BBM("diag: verify");
	SHENG_DBG_ENV("sheng_mdss_verify",
		      sheng_mdss_verify_pipeline(SM8550_MDSS_DPU_BASE,
						 SM8550_MDSS_DSI0_BASE));

	/* DSC status registers are running counters. Sample them too early
	 * and an encoder still starting up reads like a stalled one. Keep
	 * this delay fixed so readings compare across builds. */
	mdelay(50);
	SHENG_DBG_ENV("sheng_mdss_dsc_st1", sheng_mdss_dsc_status1(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dsc_st2", sheng_mdss_dsc_status2(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dpu_rb1", sheng_mdss_dpu_readback1(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dpu_rb2", sheng_mdss_dpu_readback2(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dpu_rb3", sheng_mdss_dpu_readback3(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dpu_rb4", sheng_mdss_dpu_readback4(SM8550_MDSS_DPU_BASE));
	SHENG_DBG_ENV("sheng_mdss_dsi_vrb1",
		      sheng_mdss_dsi_video_readback1(SM8550_MDSS_DSI0_BASE));
	/* Live reference: DSI0 0x1F00 (lanes driven), DSI1 0x1F1F;
	 * PHY_ERR 0x00088888 on both. */
	SHENG_DBG_ENV("sheng_mdss_lanes",
		      sheng_mdss_lane_status(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE));
	BBM("diag: phy err");
	SHENG_DBG_ENV("sheng_mdss_phyerr",
		      sheng_mdss_phy_err_both(SM8550_MDSS_DSI0_BASE, SM8550_MDSS_DSI1_BASE));
	SHENG_DBG_ENV("sheng_mdss_dsi_vrb2",
		      sheng_mdss_dsi_video_readback2(SM8550_MDSS_DSI0_BASE,
						     SM8550_MDSS_DSI1_BASE));

	BBM("probe exit");
}

long long sheng_mdss_dsi_trigger_probe(void);
unsigned int sheng_mdss_dsi_retry_count(void);
unsigned int sheng_mdss_dsi_status0_before_first_cmd(void);
long long sheng_mdss_dsi_timeout_diag(void);
long long sheng_mdss_dsi_snapshot_1(void);
long long sheng_mdss_dsi_snapshot_2(void);
long long sheng_mdss_dsi_snapshot_3(void);
long long sheng_mdss_dsi_snapshot_4(void);
unsigned int sheng_mdss_smmu_diag1(void);
long long sheng_mdss_iova_diag1(void);
long long sheng_mdss_iova_diag2(void);
long long sheng_mdss_dmabuf_diag(void);

/* Which DRAM bank, if any, holds addr. build_mem_map() maps only what
 * the previous bootloader reported in gd->dram[], so an address in a
 * bank U-Boot does not own is simply unmapped: CPU stores go nowhere
 * and the DPU fetches a region it may not read. Both look identical to
 * a correctly programmed pipeline with no pixels. */
static void report_dram_bank(const char *what, unsigned long addr)
{
	char name[48];
	int b;

	for (b = 0; b < CONFIG_NR_DRAM_BANKS; b++) {
		if (!gd->dram[b].size)
			continue;
		if (addr < gd->dram[b].start ||
		    addr >= gd->dram[b].start + gd->dram[b].size)
			continue;

		snprintf(name, sizeof(name), "sheng_mdss_%s_bank", what);
		sheng_mdss_debug_env(name, b);
		snprintf(name, sizeof(name), "sheng_mdss_%s_bank_start", what);
		sheng_mdss_debug_env(name, gd->dram[b].start);
		snprintf(name, sizeof(name), "sheng_mdss_%s_bank_size", what);
		sheng_mdss_debug_env(name, gd->dram[b].size);
		return;
	}

	snprintf(name, sizeof(name), "sheng_mdss_%s_bank", what);
	sheng_mdss_debug_env(name, ~0UL);
}

/* State right after the DCS init, before the DPU starts streaming. */
void sheng_mdss_debug_post_panel_report(void)
{
	BBR("DSI0 RDBK_DATA0", SM8550_MDSS_DSI0_BASE, 0x068);
	BBR("DSI0 RDBK_DATA_CTRL", SM8550_MDSS_DSI0_BASE, 0x1d0);

	SHENG_DBG_ENV("sheng_mdss_trigprobe", sheng_mdss_dsi_trigger_probe());
	SHENG_DBG_ENV("sheng_mdss_retries", sheng_mdss_dsi_retry_count());
	SHENG_DBG_ENV("sheng_mdss_status0_pre",
		      sheng_mdss_dsi_status0_before_first_cmd());
	SHENG_DBG_ENV("sheng_mdss_timeout_diag", sheng_mdss_dsi_timeout_diag());
	SHENG_DBG_ENV("sheng_mdss_snap1", sheng_mdss_dsi_snapshot_1());
	SHENG_DBG_ENV("sheng_mdss_snap2", sheng_mdss_dsi_snapshot_2());
	SHENG_DBG_ENV("sheng_mdss_snap3", sheng_mdss_dsi_snapshot_3());
	SHENG_DBG_ENV("sheng_mdss_snap4", sheng_mdss_dsi_snapshot_4());
	SHENG_DBG_ENV("sheng_mdss_smmu_diag1", sheng_mdss_smmu_diag1());
	SHENG_DBG_ENV("sheng_mdss_smmu_diag2", sheng_mdss_smmu_diag2());
	SHENG_DBG_ENV("sheng_mdss_smmu_diag3", sheng_mdss_smmu_diag3());
	SHENG_DBG_ENV("sheng_mdss_iova_diag1", sheng_mdss_iova_diag1());
	SHENG_DBG_ENV("sheng_mdss_iova_diag2", sheng_mdss_iova_diag2());
	SHENG_DBG_ENV("sheng_mdss_dmabuf", sheng_mdss_dmabuf_diag());

	report_dram_bank("scratch", SHENG_MDSS_DSI_DMA_SCRATCH);
	report_dram_bank("fb", SHENG_MDSS_FB_ADDR);
}
