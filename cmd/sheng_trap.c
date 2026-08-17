// SPDX-License-Identifier: GPL-2.0+
/*
 * sheng shell-handoff bring-up: a bootcmd-callable checkpoint. Reaching
 * this command and issuing the PSCI reset is the only observable signal
 * available on this build (no display, no USB, no confirmed UART) -- if
 * the device reboots, everything in bootcmd before this point completed;
 * if it just hangs instead, the failure is upstream of wherever `trap`
 * was placed in bootcmd. Move it forward once the current position is
 * confirmed reached, same as the earlier LED/fastboot traps on this
 * board. Remove once the real hang site is found.
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
