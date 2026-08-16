// SPDX-License-Identifier: GPL-2.0+
/*
 * Novatek NT36532E Panel Driver (minimal stub for U-Boot)
 */

#include <common.h>
#include <dm.h>
#include <panel.h>

static int nt36532e_enable(struct udevice *dev)
{
	return 0;
}

static const struct panel_ops nt36532e_ops = {
	.enable = nt36532e_enable,
};

static const struct udevice_id nt36532e_ids[] = {
	{ .compatible = "xiaomi,sheng-nt36532e" },
	{ }
};

U_BOOT_DRIVER(nt36532e_panel) = {
	.name = "nt36532e_panel",
	.id = UCLASS_PANEL,
	.of_match = nt36532e_ids,
	.ops = &nt36532e_ops,
};
