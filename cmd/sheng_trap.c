// SPDX-License-Identifier: GPL-2.0+
/*
 * sheng shell-handoff bring-up checkpoint (PSCI reset as a reachability
 * signal for bisecting hangs with no display/USB/UART available).
 *
 * `trap` is not called anywhere in bootcmd on this board and looks like
 * dead code -- it isn't. Removing this file (and its cmd/Makefile hook)
 * has been confirmed on real hardware to reintroduce a boot hang, even
 * though nothing else changes and bootcmd never references it. Cause
 * not fully understood (suspected link-layout/size sensitivity on this
 * particular bring-up), but empirically: do not remove without a full
 * reboot test on real hardware first.
 */

#include <command.h>
#include <asm/system.h>

static int do_sheng_trap(struct cmd_tbl *cmdtp, int flag, int argc,
			  char *const argv[])
{
	psci_system_reset();
	return CMD_RET_FAILURE; /* unreachable if the reset actually fires */
}

U_BOOT_CMD(
	trap, 1, 1, do_sheng_trap,
	"sheng bring-up checkpoint: PSCI reset as a reachability signal",
	""
);
