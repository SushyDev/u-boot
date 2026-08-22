# SPDX-License-Identifier: GPL-2.0+
#
# Shared rule for building Zig sources into U-Boot objects.
#
# Include this from any drivers/ Makefile that has .zig sources, then add
# a per-file rule:
#
#	$(obj)/foo.o: $(src)/foo.zig FORCE
#		$(call if_changed,zig_obj)
#
# Freestanding, no libc, no runtime: the objects link into U-Boot like
# any other. -OReleaseSmall keeps them out of the image size budget,
# which is tight on this board.

ZIG ?= zig
ZIG_TARGET := aarch64-freestanding-none
ZIG_CPU := generic

quiet_cmd_zig_obj = ZIG     $@
      cmd_zig_obj = $(ZIG) build-obj -target $(ZIG_TARGET) -mcpu $(ZIG_CPU) \
			-OReleaseSmall -fno-emit-bin -femit-bin=$@ $<
