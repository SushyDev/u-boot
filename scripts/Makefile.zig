# SPDX-License-Identifier: GPL-2.0+
#
# Shared rule for building Zig sources into U-Boot objects.
#
# Include this from any drivers/ Makefile that has .zig sources, then add
# a per-file rule:
#
#	$(obj)/foo.o: $(src)/foo.zig $(obj)/sheng_mdss_config.zig FORCE
#		$(call if_changed,zig_obj)
#
# Freestanding, no libc, no runtime: the objects link into U-Boot like
# any other. -OReleaseSmall keeps them out of the image size budget,
# which is tight on this board.
#
# Kconfig reaches Zig through a generated module rather than a -D flag,
# which `zig build-obj` has no equivalent of. The module is imported as
# `config`, so a source can say
#
#	const debug_enabled = @import("config").debug;
#
# and get a comptime-known bool. That is what lets the instrumentation be
# eliminated outright when CONFIG_VIDEO_SHENG_MDSS_DEBUG=n, instead of
# being skipped at runtime by a flag that is always false -- which is what
# the C side of this driver has always done via its macros.

ZIG ?= zig
ZIG_TARGET := aarch64-freestanding-none
ZIG_CPU := generic

quiet_cmd_zig_cfg = ZIGCFG $@
      cmd_zig_cfg = { \
	echo '// Generated from Kconfig by scripts/Makefile.zig. Do not edit.'; \
	echo 'pub const debug: bool = $(if $(CONFIG_VIDEO_SHENG_MDSS_DEBUG),true,false);'; \
	echo 'pub const pre_con_buf_addr: usize = $(CONFIG_PRE_CON_BUF_ADDR);'; \
	} > $@

$(obj)/sheng_mdss_config.zig: FORCE
	$(call if_changed,zig_cfg)

quiet_cmd_zig_obj = ZIG     $@
      cmd_zig_obj = $(ZIG) build-obj -target $(ZIG_TARGET) -mcpu $(ZIG_CPU) \
			-OReleaseSmall -femit-bin=$@ \
			--dep config \
			-Mroot=$< -Mconfig=$(obj)/sheng_mdss_config.zig
