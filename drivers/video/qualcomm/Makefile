# SPDX-License-Identifier: GPL-2.0+

obj-$(CONFIG_VIDEO_SHENG_MDSS) += sheng_mdss.o sheng_mdss_hw.o

ZIG ?= zig
ZIG_TARGET := aarch64-freestanding-none
ZIG_CPU := generic

quiet_cmd_zig_obj = ZIG     $@
      cmd_zig_obj = $(ZIG) build-obj -target $(ZIG_TARGET) -mcpu $(ZIG_CPU) \
			-OReleaseSmall -fno-emit-bin -femit-bin=$@ $<

$(obj)/sheng_mdss_hw.o: $(src)/sheng_mdss_hw.zig FORCE
	$(call if_changed,zig_obj)
