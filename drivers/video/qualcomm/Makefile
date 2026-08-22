# SPDX-License-Identifier: GPL-2.0+

obj-$(CONFIG_VIDEO_SHENG_MDSS) += sheng_mdss.o sheng_mdss_hw.o
obj-$(CONFIG_VIDEO_SHENG_MDSS_DEBUG) += sheng_mdss_debug.o sheng_mdss_diag.o

include $(srctree)/scripts/Makefile.zig

$(obj)/sheng_mdss_hw.o: $(src)/sheng_mdss_hw.zig FORCE
	$(call if_changed,zig_obj)

$(obj)/sheng_mdss_diag.o: $(src)/sheng_mdss_diag.zig FORCE
	$(call if_changed,zig_obj)
