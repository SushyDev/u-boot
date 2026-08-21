/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * SM8550 MDSS block addresses for the sheng display driver.
 *
 * Addresses come from dts/upstream/src/arm64/qcom/sm8550.dtsi. U-Boot
 * does not instantiate the DPU/DSI sub-nodes as separate udevices, so
 * they are named here rather than walked from the device tree.
 *
 * DPU sub-block offsets are relative to SM8550_MDSS_DPU_BASE and match
 * the kernel's dpu_9_0_sm8550.h catalog.
 */

#ifndef __SHENG_MDSS_REGS_H
#define __SHENG_MDSS_REGS_H

#define SM8550_GCC_BASE			0x00100000
#define GCC_DISP_HF_AXI_CLK_CBCR_OFF	0x2700c

#define SM8550_TLMM_BASE		0x00f100000
#define TLMM_GPIO_REG_SIZE		0x1000
#define TLMM_MUX_FUNC_MASK		(0x7u << 2)
#define TLMM_OE_BIT			(1u << 9)
#define TLMM_OUT_BIT			(1u << 1)

/* GPIOs 30/31 gate the panel bias rails, they do not create them --
 * the KTZ8866 latches LCD_BIAS_CFG1 over I2C as well. */
#define TLMM_PANEL_AVDD_GPIO		30
#define TLMM_PANEL_AVEE_GPIO		31
#define TLMM_PANEL_RESET_GPIO		133
#define TLMM_BACKLIGHT_GPIO		128

#define SM8550_MDSS_BASE		0x0ae00000
#define SM8550_MDSS_DPU_BASE		0x0ae01000
/* Separate ioremap in the binding (reg-names "mdp", "vbif"), not an
 * offset from the DPU base. */
#define SM8550_MDSS_VBIF_BASE		0x0aeb0000
#define SM8550_DISPCC_BASE		0x0af00000

/* From DSI6G v3 a HW_VERSION register at offset 0 shifts every other
 * register down by 4 bytes. Fold the shift into the base. */
#define DSI_6G_REG_SHIFT		4
#define SM8550_MDSS_DSI0_BASE		(0x0ae94000 + DSI_6G_REG_SHIFT)
#define SM8550_MDSS_DSI1_BASE		(0x0ae96000 + DSI_6G_REG_SHIFT)
#define SM8550_MDSS_DSI0_PHY_BASE	0x0ae95000
#define SM8550_MDSS_DSI1_PHY_BASE	0x0ae97000

/* DPU sub-blocks, offsets from SM8550_MDSS_DPU_BASE. */
#define DPU_CTL0_OFF			0x15000
#define DPU_SSPP_DMA0_OFF		0x24000
#define DPU_INTF1_OFF			0x35000
#define DPU_INTF2_OFF			0x36000
#define DPU_LM0_OFF			0x44000
#define DPU_LM1_OFF			0x45000
#define DPU_MERGE3D_OFF			0x4e000
#define DPU_PP0_OFF			0x69000
#define DPU_PP1_OFF			0x6a000
#define DPU_DCE0_OFF			0x80000
#define DPU_DCE1_OFF			0x81000

/* MDP clock RCG, dispcc-relative. CFG holds src_sel [10:8] and
 * src_div [4:0]. */
#define MDP_CLK_SRC_CMD_RCGR		0x80d8
#define MDP_CLK_SRC_CFG_RCGR		(MDP_CLK_SRC_CMD_RCGR + 0x4)

/* INTF timing counters, offsets from an intf block base. */
#define INTF_FRAME_COUNT		0x0ac
#define INTF_LINE_COUNT			0x0b0

/* Panel geometry. */
#define SHENG_PANEL_HACTIVE		3048
#define SHENG_PANEL_VACTIVE		2032

/* Stride is ALIGN(3048,32)*4 = 12288, not 3048*4. The DPU fetches at
 * this pitch, so the video uclass must be told it before probe returns
 * or every console line lands 96 bytes short. */
#define SHENG_MDSS_FB_STRIDE		12288
#define SHENG_MDSS_FB_ADDR		0xa3200000
#define SHENG_MDSS_DSI_DMA_SCRATCH	0xa3100000

#endif /* __SHENG_MDSS_REGS_H */
