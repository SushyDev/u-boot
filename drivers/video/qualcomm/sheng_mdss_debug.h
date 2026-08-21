/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Debug side channels for the sheng MDSS driver.
 *
 * The board has no reachable UART, so bring-up reports through two
 * channels instead:
 *
 *   blackbox  a DRAM ring written by sheng_mdss_hw.zig, scraped after
 *             boot. Every record is flushed to DRAM as it is written,
 *             so the log survives a hard hang.
 *   env       sheng_* environment variables, relayed into /chosen by
 *             ft_board_setup(). Capped by CBSIZE -- the blackbox is
 *             not, so prefer it for anything large.
 *   stage     one return code per bring-up stage at a fixed address,
 *             relayed the same way.
 *
 * With CONFIG_VIDEO_SHENG_MDSS_DEBUG=n every macro below expands to
 * nothing AND DISCARDS ITS ARGUMENTS, so a diagnostic that reads MDSS
 * registers costs nothing on a normal boot.
 *
 * NEVER put a call with a required side effect inside one of these --
 * it will not run in a normal boot. Assign to a local, then log the
 * local. This has already cost one latched panel.
 */

#ifndef __SHENG_MDSS_DEBUG_H
#define __SHENG_MDSS_DEBUG_H

#include <linux/kconfig.h>

/* Tags for the (tag, value) log ring. Values recorded from inside
 * load-bearing code -- cmd-db lookups, RSC ids, register readbacks. */
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

/* A stage that never ran. */
#define SHENG_MDSS_STATUS_NOT_REACHED	0x7fffffff

/* Bring-up stages, one status slot each. */
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

#if IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS_DEBUG)

/* Blackbox primitives, implemented in sheng_mdss_hw.zig. */
void sheng_bb_init(void);
void sheng_bb_mark(const char *name);
void sheng_bb_val(const char *name, unsigned long long v);
void sheng_bb_sval(const char *name, long long v);
void sheng_bb_reg(const char *name, unsigned long base, unsigned long off);
void sheng_bb_block(const char *name, unsigned long base,
		    unsigned long start, unsigned long count);
void sheng_bb_finish(void);

void sheng_mdss_debug_start(void);
void sheng_mdss_debug_stage(unsigned int stage, int ret);
void sheng_mdss_debug_env(const char *name, unsigned long long v);
void sheng_mdss_debug_log(unsigned int tag, unsigned int value);
void sheng_mdss_debug_pin(const char *name, unsigned int gpio);
void sheng_mdss_debug_finish(void);
void sheng_mdss_debug_final_dump(void);
void sheng_mdss_debug_post_dpu_report(void);
void sheng_mdss_debug_post_panel_report(void);

#define BBM(n)		sheng_bb_mark(n)
#define BBV(n, v)	sheng_bb_val((n), (unsigned long long)(v))
#define BBS(n, v)	sheng_bb_sval((n), (long long)(v))
#define BBR(n, b, o)	sheng_bb_reg((n), (unsigned long)(b), (unsigned long)(o))
#define BBB(n, b, s, c)	sheng_bb_block((n), (unsigned long)(b), \
				       (unsigned long)(s), (unsigned long)(c))

/* Named so it reads as a report, not a setter. */
#define SHENG_DBG_ENV(n, v)	sheng_mdss_debug_env((n), (unsigned long long)(v))
#define SHENG_DBG_STAGE(s, r)	sheng_mdss_debug_stage((s), (r))
#define SHENG_DBG_LOG(t, v)	sheng_mdss_debug_log((t), (unsigned int)(v))
#define SHENG_DBG_PIN(n, g)	sheng_mdss_debug_pin((n), (g))
#define SHENG_DBG_START()	sheng_mdss_debug_start()
#define SHENG_DBG_FINISH()	sheng_mdss_debug_finish()
#define SHENG_DBG_FINAL_DUMP()	sheng_mdss_debug_final_dump()
#define SHENG_DBG_POST_DPU_REPORT()	sheng_mdss_debug_post_dpu_report()
#define SHENG_DBG_POST_PANEL_REPORT()	sheng_mdss_debug_post_panel_report()

#else

/*
 * Arguments are TYPE-CHECKED BUT NOT EVALUATED. sizeof does not evaluate
 * its operand, so the MMIO reads feeding these still cost nothing --
 * but a renamed symbol breaks THIS build instead of silently vanishing.
 */
#define BBM(n)			((void)sizeof(n))
#define BBV(n, v)		((void)(sizeof(n) + sizeof(v)))
#define BBS(n, v)		((void)(sizeof(n) + sizeof(v)))
#define BBR(n, b, o)		((void)(sizeof(n) + sizeof(b) + sizeof(o)))
#define BBB(n, b, s, c)		((void)(sizeof(n) + sizeof(b) + \
					sizeof(s) + sizeof(c)))
#define SHENG_DBG_ENV(n, v)	((void)(sizeof(n) + sizeof(v)))
#define SHENG_DBG_STAGE(s, r)	((void)(sizeof(s) + sizeof(r)))
#define SHENG_DBG_LOG(t, v)	((void)(sizeof(t) + sizeof(v)))
#define SHENG_DBG_PIN(n, g)	((void)(sizeof(n) + sizeof(g)))
#define SHENG_DBG_START()	((void)0)
#define SHENG_DBG_FINISH()	((void)0)
#define SHENG_DBG_FINAL_DUMP()	((void)0)
#define SHENG_DBG_POST_DPU_REPORT()	((void)0)
#define SHENG_DBG_POST_PANEL_REPORT()	((void)0)

#endif /* CONFIG_VIDEO_SHENG_MDSS_DEBUG */

#endif /* __SHENG_MDSS_DEBUG_H */
