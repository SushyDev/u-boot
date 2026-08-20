// SPDX-License-Identifier: GPL-2.0+
/*
 * Common initialisation for Qualcomm Snapdragon boards.
 *
 * Copyright (c) 2024 Linaro Ltd.
 * Author: Casey Connolly <casey.connolly@linaro.org>
 */

#define LOG_CATEGORY LOGC_BOARD
#define pr_fmt(fmt) "QCOM: " fmt

#include <asm/armv8/mmu.h>
#include <asm/barriers.h>
#include <asm/gpio.h>
#include <asm/io.h>
#include <asm/psci.h>
#include <asm/system.h>
#include <cpu_func.h>
#include <dm/device.h>
#include <dm/pinctrl.h>
#include <dm/uclass-internal.h>
#include <dm/uclass.h>
#include <dm/read.h>
#include <video.h>
#include <power/regulator.h>
#include <env.h>
#include <fdt_support.h>
#include <i2c.h>
#include <init.h>
#include <linux/arm-smccc.h>
#include <linux/bug.h>
#include <linux/delay.h>
#include <linux/psci.h>
#include <linux/sizes.h>
#include <lmb.h>
#include <malloc.h>
#include <fdt_support.h>
#include <usb.h>
#include <sort.h>
#include <time.h>

#include "qcom-priv.h"

DECLARE_GLOBAL_DATA_PTR;

enum qcom_boot_source qcom_boot_source __section(".data") = 0;

static struct mm_region rbx_mem_map[CONFIG_NR_DRAM_BANKS + 2] = { { 0 } };

struct mm_region *mem_map = rbx_mem_map;

static struct {
	phys_addr_t start;
	phys_size_t size;
} prevbl_ddr_banks[CONFIG_NR_DRAM_BANKS] __section(".data") = { 0 };

int dram_init(void)
{
	/*
	 * gd->ram_base / ram_size have been setup already
	 * in qcom_parse_memory().
	 */
	return 0;
}

static int ddr_bank_cmp(const void *v1, const void *v2)
{
	const struct {
		phys_addr_t start;
		phys_size_t size;
	} *res1 = v1, *res2 = v2;

	if (!res1->size)
		return 1;
	if (!res2->size)
		return -1;

	return (res1->start >> 24) - (res2->start >> 24);
}

/* This has to be done post-relocation since gd->bd isn't preserved */
static void qcom_configure_dram(void)
{
	int i;

	for (i = 0; i < CONFIG_NR_DRAM_BANKS; i++) {
		gd->dram[i].start = prevbl_ddr_banks[i].start;
		gd->dram[i].size = prevbl_ddr_banks[i].size;
	}
}

int dram_init_banksize(void)
{
	qcom_configure_dram();

	return 0;
}

/**
 * The generic memory parsing code in U-Boot lacks a few things that we
 * need on Qualcomm:
 *
 * 1. It sets gd->ram_size and gd->ram_base to represent a single memory block
 * 2. setup_dest_addr() later relocates U-Boot to ram_base + ram_size, the end
 *    of that first memory block.
 *
 * This results in all memory beyond U-Boot being unusable in Linux when booting
 * with EFI.
 *
 * Since the ranges in the memory node may be out of order, the only way for us
 * to correctly determine the relocation address for U-Boot is to parse all
 * memory regions and find the highest valid address.
 *
 * We can't use fdtdec_setup_memory_banksize() since it stores the result in
 * gd->bd, which is not yet allocated.
 *
 * @fdt: FDT blob to parse /memory node from
 *
 * Return: 0 on success or -ENODATA if /memory node is missing or incomplete
 */
static int qcom_parse_memory(const void *fdt)
{
	int offset;
	const fdt64_t *memory;
	int memsize;
	phys_addr_t ram_end = 0;
	int i, j, banks;

	offset = fdt_path_offset(fdt, "/memory");
	if (offset < 0)
		return -ENODATA;

	memory = fdt_getprop(fdt, offset, "reg", &memsize);
	if (!memory)
		return -ENODATA;

	banks = min(memsize / (2 * sizeof(u64)), (ulong)CONFIG_NR_DRAM_BANKS);

	if (memsize / sizeof(u64) > CONFIG_NR_DRAM_BANKS * 2)
		log_err("Provided more than the max of %d memory banks\n", CONFIG_NR_DRAM_BANKS);

	if (banks > CONFIG_NR_DRAM_BANKS)
		log_err("Provided more memory banks than we can handle\n");

	for (i = 0, j = 0; i < banks * 2; i += 2, j++) {
		prevbl_ddr_banks[j].start = get_unaligned_be64(&memory[i]);
		prevbl_ddr_banks[j].size = get_unaligned_be64(&memory[i + 1]);
		if (!prevbl_ddr_banks[j].size) {
			j--;
			continue;
		}
		ram_end = max(ram_end, prevbl_ddr_banks[j].start + prevbl_ddr_banks[j].size);
	}

	if (!banks || !prevbl_ddr_banks[0].size)
		return -ENODATA;

	/* Sort our RAM banks -_- */
	qsort(prevbl_ddr_banks, banks, sizeof(prevbl_ddr_banks[0]), ddr_bank_cmp);

	gd->ram_base = prevbl_ddr_banks[0].start;
	gd->ram_size = ram_end - gd->ram_base;

	return 0;
}

static void show_psci_version(void)
{
	struct arm_smccc_res res;

	arm_smccc_smc(ARM_PSCI_0_2_FN_PSCI_VERSION, 0, 0, 0, 0, 0, 0, 0, &res);

	/* Some older SoCs like MSM8916 don't always support PSCI */
	if ((int)res.a0 == PSCI_RET_NOT_SUPPORTED)
		return;

	debug("PSCI:  v%ld.%ld\n",
	      PSCI_VERSION_MAJOR(res.a0),
	      PSCI_VERSION_MINOR(res.a0));
}

/**
 * Most MSM8916 devices in the wild shipped without PSCI support, but the
 * upstream DTs pretend that PSCI exists. If that situation is detected here,
 * the /psci node is deleted. This is done very early to ensure the PSCI
 * firmware driver doesn't bind (which then binds a sysreset driver that won't
 * work).
 */
static void qcom_psci_fixup(void *fdt)
{
	int offset, ret;
	struct arm_smccc_res res;

	arm_smccc_smc(ARM_PSCI_0_2_FN_PSCI_VERSION, 0, 0, 0, 0, 0, 0, 0, &res);

	if ((int)res.a0 != PSCI_RET_NOT_SUPPORTED)
		return;

	offset = fdt_path_offset(fdt, "/psci");
	if (offset < 0)
		return;

	debug("Found /psci DT node on device with no PSCI. Deleting.\n");
	ret = fdt_del_node(fdt, offset);
	if (ret)
		log_err("Failed to delete /psci node: %d\n", ret);
}

/* We support booting U-Boot with an internal DT when running as a first-stage bootloader
 * or for supporting quirky devices where it's easier to leave the downstream DT in place
 * to improve ABL compatibility. Otherwise, we use the DT provided by ABL.
 */
/*
 * get_prev_bl_fdt_addr() returns raw x0 as saved at boot entry with no
 * validation. sheng's internal DT is always valid, so gate the external
 * pointer behind a sanity check instead of dereferencing it unconditionally
 * this early in boot (no exception vectors installed yet).
 */
static bool qcom_debug_addr_plausible(phys_addr_t addr)
{
	return addr && !(addr & 0x7) &&
	       addr >= 0x80000000ULL && addr < 0x400000000ULL;
}

int board_fdt_blob_setup(void **fdtp)
{
	struct fdt_header *external_fdt, *internal_fdt;
	bool internal_valid, external_valid;
	phys_addr_t prev_bl_fdt;
	int ret = -ENODATA;

	internal_fdt = (struct fdt_header *)*fdtp;
	prev_bl_fdt = get_prev_bl_fdt_addr();
	external_fdt = (struct fdt_header *)prev_bl_fdt;
	external_valid = qcom_debug_addr_plausible(prev_bl_fdt) &&
			  !fdt_check_header(external_fdt);
	internal_valid = !fdt_check_header(internal_fdt);

	/*
	 * There is no point returning an error here, U-Boot can't do anything useful in this situation.
	 * Bail out while we can still print a useful error message.
	 */
	if (!internal_valid && !external_valid)
		panic("Internal FDT is invalid and no external FDT was provided! (fdt=%#llx)\n",
		      (phys_addr_t)external_fdt);

	/* Prefer memory information from internal DT if it's present */
	if (internal_valid)
		ret = qcom_parse_memory(internal_fdt);

	if (ret < 0 && external_valid) {
		/* No internal FDT or it lacks a proper /memory node.
		 * The previous bootloader handed us something, let's try that.
		 */
		if (internal_valid)
			debug("No memory info in internal FDT, falling back to external\n");

		ret = qcom_parse_memory(external_fdt);
	}

	if (ret < 0)
		panic("No valid memory ranges found!\n");

	/* If we have an external FDT, it can only have come from the Android bootloader. */
	if (external_valid)
		qcom_boot_source = QCOM_BOOT_SOURCE_ANDROID;
	else
		qcom_boot_source = QCOM_BOOT_SOURCE_XBL;

	debug("ram_base = %#011lx, ram_size = %#011llx\n",
	      gd->ram_base, gd->ram_size);

	if (internal_valid) {
		debug("Using built in FDT\n");
		ret = -EEXIST;
	} else {
		debug("Using external FDT\n");
		*fdtp = external_fdt;
		ret = 0;
	}

	qcom_psci_fixup(*fdtp);

	return ret;
}

/*
 * Some Qualcomm boards require GPIO configuration when switching USB modes.
 * Support setting this configuration via pinctrl state.
 */
int board_usb_init(int index, enum usb_init_type init)
{
	struct udevice *usb;
	int ret = 0;

	/* USB device */
	ret = uclass_find_device_by_seq(UCLASS_USB, index, &usb);
	if (ret) {
		printf("Cannot find USB device\n");
		return ret;
	}

	ret = dev_read_stringlist_search(usb, "pinctrl-names",
					 "device");
	/* No "device" pinctrl state, so just bail */
	if (ret < 0)
		return 0;

	/* Select "default" or "device" pinctrl */
	switch (init) {
	case USB_INIT_HOST:
		pinctrl_select_state(usb, "default");
		break;
	case USB_INIT_DEVICE:
		pinctrl_select_state(usb, "device");
		break;
	default:
		debug("Unknown usb_init_type %d\n", init);
		break;
	}

	return 0;
}

/*
 * Some boards still need board specific init code, they can implement that by
 * overriding this function.
 *
 * FIXME: get rid of board specific init code
 */
void __weak qcom_board_init(void)
{
}

int board_init(void)
{
	show_psci_version();
	qcom_board_init();
	return 0;
}

int ft_board_setup(void *blob, struct bd_info *bd)
{
	/* Relay sheng_mdss's per-stage status codes (see
	 * drivers/video/qualcomm/sheng_mdss.c) into /chosen so they're
	 * readable from Linux at /proc/device-tree/chosen/sheng,mdss-status
	 * -- this board has no working UART/console during U-Boot's own
	 * boot stage to see log_debug() output directly. 9 stages x 4
	 * bytes = 36 bytes (mdss_reset, bcm_mm0, mmcx, gdsc, dispcc,
	 * dsi0_phy, dsi1_phy, dsi_panel, dpu, in that order -- must track
	 * SHENG_MDSS_STATUS_COUNT in sheng_mdss.c); each is 0x7fffffff if
	 * that stage was never reached, 0 on success, or a negative errno.
	 */
	if (IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS) && IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
		int nodeoff = fdt_path_offset(blob, "/chosen");

		if (nodeoff >= 0) {
			fdt_setprop(blob, nodeoff, "sheng,mdss-status",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3000),
				    36);
			fdt_setprop(blob, nodeoff, "sheng,uclass-get-device-ret",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3020),
				    4);
			/* Log buffer (see sheng_mdss_log() in sheng_mdss.c):
			 * 4-byte entry count followed by up to 64 (tag,
			 * value) u32 pairs = 4 + 64*8 = 516 bytes. Always
			 * relay the full fixed-size region; the leading
			 * count says how many entries are actually valid. */
			fdt_setprop(blob, nodeoff, "sheng,mdss-log",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3100),
				    4 + 64 * 8);
			/* sheng_ktz8866_backlight_init()'s per-chip status
			 * (see its own comment): [chip_a_ret, chip_b_ret],
			 * 2 x 4 bytes. Same convention as mdss-status (0 =
			 * success, negative = errno, 0x7fffffff = not
			 * reached). Placed well clear of the mdss-log region
			 * above (ends at 0x3100+516=0x3304). */
			fdt_setprop(blob, nodeoff, "sheng,ktz8866-status",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3400),
				    8);
		}
	}

	return 0;
}

/**
 * out_len includes the trailing null space
 */
static int get_cmdline_option(const char *cmdline, const char *key, char *out, int out_len)
{
	const char *p, *p_end;
	int len;

	p = strstr(cmdline, key);
	if (!p)
		return -ENOENT;

	p += strlen(key);
	p_end = strstr(p, " ");
	if (!p_end)
		return -ENOENT;

	len = p_end - p;
	if (len > out_len)
		len = out_len;

	strncpy(out, p, len);
	out[len] = '\0';

	return 0;
}

/* The bootargs are populated by the previous stage bootloader */
static const char *get_cmdline(void)
{
	ofnode node;
	static const char *cmdline = NULL;

	if (cmdline)
		return cmdline;

	node = ofnode_path("/chosen");
	if (!ofnode_valid(node))
		return NULL;

	cmdline = ofnode_read_string(node, "bootargs");

	return cmdline;
}

void qcom_set_serialno(void)
{
	const char *cmdline = get_cmdline();
	char serial[32];

	if (!cmdline) {
		log_debug("Failed to get bootargs\n");
		return;
	}

	get_cmdline_option(cmdline, "androidboot.serialno=", serial, sizeof(serial));
	if (serial[0] != '\0')
		env_set("serial#", serial);
}

/* Sets up the "board", and "soc" environment variables as well as constructing the devicetree
 * path, with a few quirks to handle non-standard dtb filenames. This is not meant to be a
 * comprehensive solution to automatically picking the DTB, but aims to be correct for the
 * majority case. For most devices it should be possible to make this algorithm work by
 * adjusting the root compatible property in the U-Boot DTS. Handling devices with multiple
 * variants that are all supported by a single U-Boot image will require implementing device-
 * specific detection.
 */
static void __maybe_unused configure_env(void)
{
	const char *first_compat, *last_compat;
	char *tmp;
	char buf[32] = { 0 };
	/*
	 * Most DTB filenames follow the scheme: qcom/<soc>-[vendor]-<board>.dtb
	 * The vendor is skipped when it's a Qualcomm reference board, or the
	 * db845c.
	 */
	char dt_path[64] = { 0 };
	int compat_count, ret;
	ofnode root;

	root = ofnode_root();
	/* This is almost always 2, but be explicit that we want the first and last compatibles
	 * not the first and second.
	 */
	compat_count = ofnode_read_string_count(root, "compatible");
	if (compat_count < 2) {
		log_warning("%s: only one root compatible bailing!\n", __func__);
		return;
	}

	/* The most specific device compatible (e.g. "thundercomm,db845c") */
	ret = ofnode_read_string_index(root, "compatible", 0, &first_compat);
	if (ret < 0) {
		log_warning("Can't read first compatible\n");
		return;
	}

	strlcpy(buf, first_compat, sizeof(buf) - 1);
	tmp = buf;

	/* The Qualcomm reference boards (RBx, HDK, etc)  */
	if (!strncmp("qcom", buf, strlen("qcom"))) {
		char *soc;

		/*
		 * They all have the first compatible as "qcom,<soc>-<board>"
		 * (e.g. "qcom,qrb5165-rb5"). We extract just the part after
		 * the dash.
		 */
		if (!strsep(&tmp, ",")) {
			log_warning("compatible '%s' has no ','\n", buf);
			return;
		}
		soc = strsep(&tmp, "-");
		if (!soc) {
			log_warning("compatible '%s' has no '-'\n", buf);
			return;
		}

		env_set("soc", soc);
		env_set("board", tmp);
	} else {
		if (!strsep(&tmp, ",")) {
			log_warning("compatible '%s' has no ','\n", buf);
			return;
		}
		/*
		 * For thundercomm we just want the bit after the comma
		 * (e.g. "db845c"), for all other boards we replace the comma
		 * with a '-' and take both (e.g. "oneplus-enchilada")
		 */
		if (!strncmp("thundercomm", buf, strlen("thundercomm"))) {
			env_set("board", tmp);
		} else {
			*(tmp - 1) = '-';
			env_set("board", buf);
		}

		/* The last compatible is always the SoC compatible */
		ret = ofnode_read_string_index(root, "compatible",
					       compat_count - 1, &last_compat);
		if (ret < 0) {
			log_warning("Can't read second compatible\n");
			return;
		}

		/* Copy the last compat (e.g. "qcom,sdm845") into buf */
		memset(buf, 0, sizeof(buf));
		strlcpy(buf, last_compat, sizeof(buf) - 1);
		tmp = buf;

		/* strsep() is destructive, it replaces the comma with a \0 */
		if (!strsep(&tmp, ",")) {
			log_warning("second compatible '%s' has no ','\n", buf);
			return;
		}

		/* tmp now points to just the "sdm845" part of the string */
		env_set("soc", tmp);
	}

	/* Now build the full path name */
	snprintf(dt_path, sizeof(dt_path), "qcom/%s-%s.dtb",
		 env_get("soc"), env_get("board"));
	env_set("fdtfile", dt_path);

	qcom_set_serialno();
}

void qcom_show_boot_source(void)
{
	const char *name = "UNKNOWN";

	switch (qcom_boot_source) {
	case QCOM_BOOT_SOURCE_ANDROID:
		name = "ABL";
		break;
	case QCOM_BOOT_SOURCE_XBL:
		name = "XBL";
		break;
	}

	log_info("U-Boot loaded from %s\n", name);
	env_set("boot_source", name);
}

void __weak qcom_late_init(void)
{
}

#define KERNEL_COMP_SIZE	SZ_64M
#ifdef CONFIG_FASTBOOT_BUF_SIZE
#define FASTBOOT_BUF_SIZE CONFIG_FASTBOOT_BUF_SIZE
#else
#define FASTBOOT_BUF_SIZE 0
#endif

#define lmb_alloc(size, addr) lmb_alloc_mem(LMB_MEM_ALLOC_ANY, SZ_2M, addr, size, LMB_NONE)

/*
 * KTZ8866 backlight IC bring-up (SPEC.md task #5 log has the full
 * investigation trail). GPIO 128 (backlight enable line) is handled
 * separately in sheng_mdss.c via raw TLMM MMIO; this handles the I2C
 * side (brightness/current-sink config), which the GPIO enable line
 * alone doesn't provide -- the KTZ886x family needs these register
 * writes to actually drive LED current, confirmed against the real
 * kernel driver (drivers/video/backlight/ktz8866.c in the mainline
 * checkout).
 *
 * This is a PAIRED pair of chips, not one: the real driver's own
 * ktz8866_ids[] table has "ktz8866a"/"ktz8866b" variants that mirror
 * writes to each other (ktz8866_write()/update_bits() write to both
 * ktz->regmap and the paired ktz_b->regmap). Confirmed live under the
 * booted Linux kernel:
 *   - "A": /soc@0/geniqup@ac0000/i2c@a84000 (i2c1, already enabled
 *     above), address 0x11.
 *   - "B": /soc@0/geniqup@9c0000/i2c@988000 (i2c_hub_2, a SEPARATE
 *     "qcom,geni-se-i2c-master-hub"-type wrapper, also enabled above),
 *     address 0x11.
 * Our first pass at this only wrote chip A -- if the panel's two DSI
 * halves are each driven by their own chip, that alone could explain
 * total darkness despite every register on A reading back correct.
 *
 * Also added LCD_BIAS_CFG1 (register 0x09 = 0x9F, LCD_BIAS_EN): the
 * real driver's ktz8866_init() writes this too (gated on the
 * `kinetic,enable-lcd-bias` boolean property, present on this board's
 * real kernel-side devicetree node) via a plain, non-mirrored
 * regmap_write() straight to ktz->regmap -- confirmed live: chip A's
 * register 0x09 already reads 0x9F (Linux's own driver set it) while
 * chip B's reads 0x98 (never mirrored there by the real driver either).
 * Written to both here since we don't know for certain it's A-only by
 * hardware design rather than a real driver oversight, and it's a
 * cheap, low-risk extra register write either way.
 *
 * Both i2c bus nodes are already `status = "okay"` in this board's
 * devicetree, meaning U-Boot's automatic GENI SE firmware loader +
 * geni_i2c driver bind/probe already run on every boot via the
 * standard, declarative DT-node-enables-driver mechanism -- this
 * function is the first thing to actually attempt a real transaction
 * over either. dm_i2c_probe() dynamically creates the chip device at
 * runtime; no static devicetree child node for the ktz8866 itself is
 * needed for a plain register write.
 */
#define SHENG_KTZ8866_STATUS_ADDR	(CONFIG_PRE_CON_BUF_ADDR + 0x3400)
#define SHENG_KTZ8866_STATUS_NOT_REACHED	0x7fffffff

/* Real board devicetree (sm8550-mainline's arch/arm64/boot/dts/qcom/
 * sm8550-xiaomi-sheng.dts) declares `enable-gpios = <&tlmm 128
 * GPIO_ACTIVE_HIGH>` on BOTH ktz8866 backlight@11 nodes. On this chip
 * the EN pin doesn't just gate the LED current sinks -- it gates the
 * I2C interface itself, so writes issued before EN is driven high
 * either NAK or land on a chip that's still in reset. This function
 * previously lived only in sheng_mdss.c's sheng_mdss_backlight_gpio_
 * enable(), which doesn't run until sheng_mdss_probe() -- triggered
 * by the CONFIG_VIDEO uclass_get_device() call *after*
 * sheng_ktz8866_backlight_init() in misc_init_r() below. So the I2C
 * writes were always racing a chip that hadn't been enabled yet.
 * Same raw TLMM MMIO poke, duplicated here (rather than shared)
 * because board.c can't/shouldn't depend on a driver-internal static
 * in drivers/video/qualcomm/sheng_mdss.c, and this needs to run even
 * when CONFIG_VIDEO_SHENG_MDSS is disabled. */
#define SHENG_TLMM_BASE			0x00f100000
#define SHENG_TLMM_GPIO_REG_SIZE	0x1000
#define SHENG_BACKLIGHT_GPIO		128
#define SHENG_TLMM_MUX_FUNC_MASK	(0x7u << 2)
#define SHENG_TLMM_OE_BIT		(1u << 9)
#define SHENG_TLMM_OUT_BIT		(1u << 1)

/* Returns the post-write io_reg readback (bit0 = actual input pin state,
 * bit1 = driven output value) so the caller can tell a real electrical
 * change from a write that silently no-op'd (e.g. TZ/XPU pin-ownership
 * protection on this GPIO, which would make this a no-op even though
 * nothing reports an error -- direct writes to protected TLMM registers
 * are typically just dropped, not faulted). */
static u32 sheng_backlight_gpio_set(int high)
{
	volatile u32 *ctl = (volatile u32 *)(uintptr_t)
		(SHENG_TLMM_BASE + SHENG_TLMM_GPIO_REG_SIZE * SHENG_BACKLIGHT_GPIO);
	volatile u32 *io = (volatile u32 *)(uintptr_t)
		(SHENG_TLMM_BASE + 0x4 + SHENG_TLMM_GPIO_REG_SIZE * SHENG_BACKLIGHT_GPIO);
	u32 v;

	v = *ctl;
	v &= ~SHENG_TLMM_MUX_FUNC_MASK;
	v |= SHENG_TLMM_OE_BIT;
	*ctl = v;

	v = *io;
	if (high)
		v |= SHENG_TLMM_OUT_BIT;
	else
		v &= ~SHENG_TLMM_OUT_BIT;
	*io = v;

	return *io;
}

static u32 sheng_backlight_gpio_enable(void)
{
	return sheng_backlight_gpio_set(1);
}

/* Hail-Mary attempt at clearing a possible latched UVLO/fault condition
 * inside the KTZ8866's boost converter: if the MDP_CLK_CBCR transient
 * (proven via ftrace to leave I2C/GPIO digitally identical either way --
 * see board_late_init()'s comment) trips the chip's own protection
 * circuit, re-sending I2C bytes to an already-latched-off chip won't
 * un-latch it; only a real EN-pin power cycle will. Drive it low long
 * enough for internal caps to actually discharge, then high again,
 * before ever touching I2C. */
static void sheng_backlight_gpio_fault_clear_cycle(void)
{
	sheng_backlight_gpio_set(0);
	mdelay(10);
	sheng_backlight_gpio_set(1);
	mdelay(2);
}

/* Raw MMIO breadcrumb, same pattern (and same reason) as sheng_mdss.c's
 * sheng_mdss_breadcrumb_flush(): D-cache is on for this board, so a
 * plain volatile store here can sit dirty in a cache line indefinitely
 * -- must flush + dsb after every write for it to survive to a
 * subsequent boot/warm-reset reliably. */
static void sheng_ktz8866_status_set(unsigned int slot, int ret)
{
	volatile int *slots = (volatile int *)(uintptr_t)SHENG_KTZ8866_STATUS_ADDR;

	if (!IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
		return;

	slots[slot] = ret;
	flush_dcache_range(SHENG_KTZ8866_STATUS_ADDR + slot * sizeof(*slots),
			    SHENG_KTZ8866_STATUS_ADDR + (slot + 1) * sizeof(*slots));
	dsb();
}

static int sheng_ktz8866_write_chip(const char *path, u32 *bl_en_readback_out)
{
	struct udevice *bus, *chip;
	ofnode i2c_node;
	u8 val;
	int ret;

	i2c_node = ofnode_path(path);
	if (!ofnode_valid(i2c_node)) {
		log_warning("sheng: ktz8866 ofnode not found: %s\n", path);
		return -ENOENT;
	}

	ret = uclass_get_device_by_ofnode(UCLASS_I2C, i2c_node, &bus);
	if (ret) {
		log_warning("sheng: ktz8866 bus probe failed (%s): %d\n", path, ret);
		return ret;
	}

	ret = dm_i2c_probe(bus, 0x11, 0, &chip);
	if (ret) {
		log_warning("sheng: ktz8866 chip probe failed (%s): %d\n", path, ret);
		return ret;
	}

	/* BL_EN: this board's real devicetree (sm8550-mainline checkout,
	 * arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts) declares
	 * `current-num-sinks = <5>` on BOTH chips -- only 5 of 6 current
	 * sinks are physically wired. Our first pass wrote 0x7f (all 6
	 * sinks + master enable), which the real driver's own
	 * ktz8866_init() would never do: `ktz8866_write(ktz, BL_EN,
	 * BIT(val) - 1)` with val=5 gives 0x1f, later OR'd with
	 * BL_EN_BIT (0x40) once brightness > 0 -> 0x5f. Enabling a sink
	 * channel that isn't physically connected is a real bug, not
	 * just a harmless extra bit -- many LED driver ICs fault-protect
	 * (and can disable output entirely) on an open/disconnected sink
	 * channel. Confirmed live: Linux's own driver's register 0x08
	 * reads 0x5f, never 0x7f, on this hardware. */
	/* Soft-start attempt (see SPEC.md task #5 log): mirrors the real
	 * ktz8866_init()/ktz8866_backlight_update_status() split exactly --
	 * enable current sinks WITHOUT the master-enable bit first (0x1f,
	 * matching Linux's own first BL_EN write), set config/bias with
	 * brightness still at 0 (no LED current flowing yet), THEN add the
	 * master-enable bit (0x5f) only once brightness is about to ramp
	 * up from zero -- rather than slamming max brightness (2047) the
	 * instant the chip is enabled, which is maximum inrush current on
	 * a rail that may already be marginal right after the MDP_CLK_CBCR
	 * transient. */
	val = 0x1f; /* BL_EN: 5 current sinks, no master enable yet */
	ret = dm_i2c_write(chip, 0x08, &val, 1);
	if (ret)
		return ret;
	val = 0x00; /* BL_BRT_LSB: brightness 0 */
	ret = dm_i2c_write(chip, 0x04, &val, 1);
	if (ret)
		return ret;
	val = 0x00; /* BL_BRT_MSB: brightness 0 */
	ret = dm_i2c_write(chip, 0x05, &val, 1);
	if (ret)
		return ret;
	val = 0x9f; /* LCD_BIAS_CFG1: LCD_BIAS_EN, matches real driver's ktz8866_init() */
	ret = dm_i2c_write(chip, 0x09, &val, 1);
	if (ret)
		return ret;
	/* BL_CFG2: kinetic,current-ramp-delay-ms=256 in the real DT ->
	 * BIT(7) | ((5 + 256/64) << 3) | PWM_HYST(0x5) = 0xcd, per
	 * ktz8866_init()'s >128ms branch. Confirmed against live register
	 * dump (0x03 already reads 0xcd from Linux's own driver). */
	val = 0xcd;
	ret = dm_i2c_write(chip, 0x03, &val, 1);
	if (ret)
		return ret;
	/* BL_DIMMING: kinetic,led-enable-ramp-delay-ms=8 in the real DT ->
	 * ramp_off_time=ilog2(8)+1=4, ramp_on_time=4<<4=0x40, OR'd =
	 * 0x44. Confirmed against live register dump (0x14 already reads
	 * 0x44 from Linux's own driver). */
	val = 0x44;
	ret = dm_i2c_write(chip, 0x14, &val, 1);
	if (ret)
		return ret;

	/* Add the master-enable bit now, at zero brightness -- minimal
	 * inrush, matching ktz8866_backlight_update_status()'s own
	 * update_bits(BL_EN, BL_EN_BIT, BL_EN_BIT) call. */
	val = 0x5f;
	ret = dm_i2c_write(chip, 0x08, &val, 1);
	if (ret)
		return ret;
	/* Read BL_EN straight back: if the write really landed in real
	 * hardware this reads 0x5f. If GENI reported write success without
	 * a real ACK (or the chip never actually powered up because its
	 * enable-gpio write was a silent no-op), this reads back stale/0/
	 * garbage instead -- a much stronger signal than the write's own
	 * return code. */
	if (bl_en_readback_out) {
		u8 rb = 0;
		int rb_ret = dm_i2c_read(chip, 0x08, &rb, 1);
		*bl_en_readback_out = rb_ret ? (0xdead0000u | (rb_ret & 0xff)) : rb;
	}

	/* Ramp brightness up from 0 to max (2047) over ~200ms in 16 steps,
	 * instead of one instantaneous jump -- softens the actual LED
	 * current inrush, not just the master-enable transition. */
	for (int step = 1; step <= 16; step++) {
		unsigned int brightness = (2047u * (unsigned int)step) / 16;

		val = brightness & 0x07;
		dm_i2c_write(chip, 0x04, &val, 1);
		val = (brightness >> 3) & 0xff;
		dm_i2c_write(chip, 0x05, &val, 1);
		mdelay(12);
	}

	return 0;
}

static void sheng_ktz8866_backlight_init(void)
{
	int ret;

	sheng_ktz8866_status_set(0, SHENG_KTZ8866_STATUS_NOT_REACHED);
	sheng_ktz8866_status_set(1, SHENG_KTZ8866_STATUS_NOT_REACHED);

	/* Must be high before either chip will ACK on I2C -- see the
	 * comment on sheng_backlight_gpio_enable()'s definition. A couple
	 * ms is generous for the EN-to-I2C-ready time on this class of
	 * chip; the real driver's own kinetic,led-enable-ramp-delay-ms=8
	 * property only bounds the LED current ramp, not I2C readiness.
	 * Fault-clear cycle (LOW then HIGH) instead of a plain enable now
	 * -- see its own comment -- in case the MDP_CLK_CBCR transient
	 * (which now runs before this, per board_late_init()'s reordering)
	 * latched a UVLO/protection fault inside the chip. */
	sheng_backlight_gpio_fault_clear_cycle();
	u32 io_readback = sheng_backlight_gpio_set(1);
	mdelay(2);

	u32 bl_en_rb_a = 0xffffffff, bl_en_rb_b = 0xffffffff;

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@ac0000/i2c@a84000", &bl_en_rb_a); /* "A" */
	sheng_ktz8866_status_set(0, ret);
	int ret_a = ret;

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@9c0000/i2c@988000", &bl_en_rb_b); /* "B" */
	sheng_ktz8866_status_set(1, ret);

	/* The CONFIG_PRE_CON_BUF_ADDR status relay lives in a no-map
	 * reserved-memory region -- turns out that's NOT readable via
	 * /dev/mem post-boot after all (STRICT_DEVMEM's RAM check isn't
	 * the blocker; xlate_dev_mem_ptr() can't get a linear-map pointer
	 * for a no-map range at all, "Bad address"/EFAULT on read()).
	 * Stash diagnostics in env vars and fold them into bootargs below
	 * so `cat /proc/cmdline` on the booted kernel is a trivial,
	 * always-available readout instead. io_readback's bit1 is the
	 * driven GPIO128 output value, bit0 the actual pin input state --
	 * if both writes report success (ret_a/ret_b == 0) but bl_en_rb_a/b
	 * don't read back 0x5f, the I2C driver is reporting false success
	 * without a real ACK, or the chip never powered up at all. */
	env_set_hex("sheng_bl_ret_a", (unsigned long)ret_a);
	env_set_hex("sheng_bl_ret_b", (unsigned long)ret);
	env_set_hex("sheng_bl_gpio_io", (unsigned long)io_readback);
	env_set_hex("sheng_bl_en_rb_a", (unsigned long)bl_en_rb_a);
	env_set_hex("sheng_bl_en_rb_b", (unsigned long)bl_en_rb_b);

	/* Give the chips/panel time to actually respond before boot
	 * continues -- requested to make sure a slow-to-light backlight
	 * gets a real chance, not just a race against whatever runs next. */
	mdelay(5000);
}

/* Stolen from arch/arm/mach-apple/board.c */
int board_late_init(void)
{
	u32 status = 0, fdt_status = 0;
	phys_addr_t addr;
	struct fdt_header *fdt_blob = (struct fdt_header *)gd->fdt_blob;

	/* We need to be fairly conservative here as we support boards with just 1G of TOTAL RAM */
	status |= !lmb_alloc(SZ_128M, &addr) ?
		env_set_hex("loadaddr", addr) : 1;
	status |= env_set_hex("kernel_addr_r", addr);
	status |= !lmb_alloc(SZ_128M, &addr) ?
		env_set_hex("ramdisk_addr_r", addr) : 1;
	status |= !lmb_alloc(KERNEL_COMP_SIZE, &addr) ?
		env_set_hex("kernel_comp_addr_r", addr) : 1;
	status |= env_set_hex("kernel_comp_size", KERNEL_COMP_SIZE);
	status |= !lmb_alloc(SZ_4M, &addr) ?
		env_set_hex("scriptaddr", addr) : 1;
	status |= !lmb_alloc(SZ_4M, &addr) ?
		env_set_hex("pxefile_addr_r", addr) : 1;

	if (IS_ENABLED(CONFIG_FASTBOOT)) {
		status |= !lmb_alloc(FASTBOOT_BUF_SIZE, &addr) ?
			env_set_hex("fastboot_addr_r", addr) : 1;
		/*
		 * Override loadaddr for memory rich soc since ${loadaddr} and
		 * ${kernel_addr_r} need to be different for the Android boot image
		 * flow. It's typically safe for ${loadaddr} to be the same address
		 * as the fastboot buffer.
		 */
		status |= env_set_hex("loadaddr", addr);
	}

	fdt_status |= !lmb_alloc(SZ_2M, &addr) ?
		env_set_hex("fdt_addr_r", addr) : 1;

	if (IS_ENABLED(CONFIG_OF_LIBFDT_OVERLAY)) {
		status |= !lmb_alloc(SZ_1M, &addr) ?
			env_set_hex("fdtoverlay_addr_r", addr) : 1;
	}

	if (status || fdt_status)
		log_warning("%s: Failed to set run time variables\n", __func__);

	/* By default copy U-Boots FDT, it will be used as a fallback */
	if (fdt_status)
		log_warning("%s: Failed to reserve memory for copying FDT\n",
			    __func__);
	else
		memcpy((void *)addr, (void *)gd->fdt_blob,
		       fdt32_to_cpu(fdt_blob->totalsize));

	configure_env();
	qcom_late_init();

	qcom_show_boot_source();
	/* Configure the dfu_string for capsule updates */
	qcom_configure_capsule_updates();

	/*
	 * Order flip (see SPEC.md task #5 log): sheng_mdss_probe()'s
	 * MDP_CLK_CBCR branch enable is a proven electrical disruptor --
	 * an I2C/GPIO ftrace comparison showed the KTZ8866 backlight
	 * chips' I2C sequence and GPIO128's TLMM state are BYTE-FOR-BYTE
	 * IDENTICAL whether backlight is working or not, ruling out any
	 * software/protocol difference. That points at a real analog
	 * effect (inrush/UVLO trip inside the KTZ8866's own boost
	 * converter, or a brief supply-rail sag) during the clock
	 * transition. Previously backlight was brought up FIRST, then the
	 * disruptive clock hit it. Flipping the order: let the disruptive
	 * transient happen first (video probe, unconditionally including
	 * the MDP clock branch now -- see sheng_mdss_dispcc_init()), give
	 * the rail real time to resettle, THEN bring up backlight from a
	 * clean state with a GPIO128 fault-clear cycle and a soft-start
	 * brightness ramp (see sheng_ktz8866_backlight_init()) instead of
	 * slamming max brightness immediately.
	 *
	 * CONFIG_VIDEO=y only *binds* video devices during early boot
	 * (video_reserve()'s uclass walk); nothing in this board's flow
	 * otherwise *probes* one (no splash screen, no CONSOLE_MUX/
	 * SYS_CONSOLE_IS_IN_ENV console selection -- both explicitly
	 * disabled elsewhere, see configs/sm8550_defconfig, to work
	 * around an unrelated early-boot hang). Force a probe attempt
	 * here so sheng_mdss's probe() actually runs.
	 */
	if (IS_ENABLED(CONFIG_VIDEO)) {
		struct udevice *vdev = NULL;
		int vret;

		vret = uclass_get_device(UCLASS_VIDEO, 0, &vdev);
		if (IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
			/* Diagnostic: raw uclass_get_device() return code,
			 * to tell "no video device bound at all" (-ENODEV)
			 * apart from "bound but probe() itself failed"
			 * (whatever sheng_mdss_probe() returned) apart from
			 * "found and probed fine" (0). Separate slot from
			 * sheng_mdss's own 5-stage status array so it's
			 * populated even if probe() is never entered at all.
			 * Relayed via ft_board_setup below.
			 */
			*(volatile int *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3020) = vret;
		}
		env_set_hex("sheng_mdss_vret", (unsigned long)vret);
	}

	/* Let the rail resettle after whatever electrical transient the
	 * video probe above caused, before bringing up backlight fresh. */
	mdelay(50);
	sheng_ktz8866_backlight_init();

	return 0;
}

static void build_mem_map(void)
{
	int i, j;

	/*
	 * Ensure the peripheral block is sized to correctly cover the address range
	 * up to the first memory bank.
	 * Don't map the first page to ensure that we actually trigger an abort on a
	 * null pointer access rather than just hanging.
	 * FIXME: we should probably split this into more precise regions
	 */
	mem_map[0].phys = 0x1000;
	mem_map[0].virt = mem_map[0].phys;
	mem_map[0].size = gd->dram[0].start - mem_map[0].phys;
	mem_map[0].attrs = PTE_BLOCK_MEMTYPE(MT_DEVICE_NGNRNE) |
			 PTE_BLOCK_NON_SHARE |
			 PTE_BLOCK_PXN | PTE_BLOCK_UXN;

	for (i = 1, j = 0; i < ARRAY_SIZE(rbx_mem_map) - 1 && gd->dram[j].size; i++, j++) {
		mem_map[i].phys = gd->dram[j].start;
		mem_map[i].virt = mem_map[i].phys;
		mem_map[i].size = gd->dram[j].size;
		mem_map[i].attrs = PTE_BLOCK_MEMTYPE(MT_NORMAL) | \
				   PTE_BLOCK_INNER_SHARE;
	}

	mem_map[i].phys = UINT64_MAX;
	mem_map[i].size = 0;

#ifdef DEBUG
	debug("Configured memory map:\n");
	for (i = 0; mem_map[i].size; i++)
		debug("  0x%016llx - 0x%016llx: entry %d\n",
		      mem_map[i].phys, mem_map[i].phys + mem_map[i].size, i);
#endif
}

u64 __maybe_unused get_page_table_size(void)
{
	return SZ_1M;
}

static int fdt_cmp_res(const void *v1, const void *v2)
{
	const struct fdt_resource *res1 = v1, *res2 = v2;

	return res1->start - res2->start;
}

/*
 * sm8550-xiaomi-sheng.dtb has 34 no-map subnodes under /reserved-memory,
 * over the original 32 -- carve_out_reserved_memory() silently drops
 * anything past this count, leaving unmapped regions as ordinary
 * cacheable RAM instead of PTE_TYPE_FAULT. Bumped with headroom.
 */
#define N_RESERVED_REGIONS 48

/* Mark all no-map regions as PTE_TYPE_FAULT to prevent speculative access.
 * On some platforms this is enough to trigger a security violation and trap
 * to EL3.
 */
static void carve_out_reserved_memory(void)
{
	static struct fdt_resource res[N_RESERVED_REGIONS] = { 0 };
	int parent, rmem, count, i = 0;
	phys_addr_t start;
	size_t size;

	/* Some reserved nodes must be carved out, as the cache-prefetcher may otherwise
	 * attempt to access them, causing a security exception.
	 */
	parent = fdt_path_offset(gd->fdt_blob, "/reserved-memory");
	if (parent <= 0) {
		log_err("No reserved memory regions found\n");
		return;
	}

	/* Collect the reserved memory regions */
	fdt_for_each_subnode(rmem, gd->fdt_blob, parent) {
		const fdt32_t *ptr;
		int len;
		if (!fdt_getprop(gd->fdt_blob, rmem, "no-map", NULL))
			continue;

		if (i == N_RESERVED_REGIONS) {
			log_err("Too many reserved regions!\n");
			break;
		}

		/* Read the address and size out from the reg property. Doing this "properly" with
		 * fdt_get_resource() takes ~70ms on SDM845, but open-coding the happy path here
		 * takes <1ms... Oh the woes of no dcache.
		 */
		ptr = fdt_getprop(gd->fdt_blob, rmem, "reg", &len);
		if (ptr) {
			/* Qualcomm devices use #address/size-cells = <2> but all reserved regions are within
			 * the 32-bit address space. So we can cheat here for speed.
			 */
			res[i].start = fdt32_to_cpu(ptr[1]);
			res[i].end = res[i].start + fdt32_to_cpu(ptr[3]);
			i++;
		}
	}

	/* Sort the reserved memory regions by address */
	count = i;
	qsort(res, count, sizeof(struct fdt_resource), fdt_cmp_res);

	/* Now set the right attributes for them. Often a lot of the regions are tightly packed together
	 * so we can optimise the number of calls to mmu_change_region_attr() by combining adjacent
	 * regions.
	 */
	start = ALIGN_DOWN(res[0].start, SZ_2M);
	size = ALIGN(res[0].end - start, SZ_2M);
	for (i = 1; i <= count; i++) {
		/* We ideally want to 2M align everything for more efficient pagetables, but we must avoid
		 * overwriting reserved memory regions which shouldn't be mapped as FAULT (like those with
		 * compatible properties).
		 * If within 2M of the previous region, bump the size to include this region. Otherwise
		 * start a new region.
		 */
		if (i == count || start + size < res[i].start - SZ_2M) {
			debug("  0x%016llx - 0x%016llx: reserved\n",
			      start, start + size);
			mmu_change_region_attr(start, size, PTE_TYPE_FAULT);
			/* If this is the final region then quit here before we index
			 * out of bounds...
			 */
			if (i == count)
				break;
			start = ALIGN_DOWN(res[i].start, SZ_2M);
			size = ALIGN(res[i].end - start, SZ_2M);
		} else {
			/* Bump size if this region is immediately after the previous one */
			size = ALIGN(res[i].end - start, SZ_2M);
		}
	}
}

/* This function open-codes setup_all_pgtables() so that we can
 * insert additional mappings *before* turning on the MMU.
 */
void __maybe_unused enable_caches(void)
{
	u64 tlb_addr = gd->arch.tlb_addr;
	u64 tlb_size = gd->arch.tlb_size;
	u64 pt_size;
	ulong carveout_start;

	gd->arch.tlb_fillptr = tlb_addr;

	build_mem_map();

	icache_enable();

	/* Create normal system page tables */
	setup_pgtables();

	pt_size = (uintptr_t)gd->arch.tlb_fillptr -
		  (uintptr_t)gd->arch.tlb_addr;
	debug("Primary pagetable size: %lluKiB\n", pt_size / 1024);

	/* Create emergency page tables */
	gd->arch.tlb_size -= pt_size;
	gd->arch.tlb_addr = gd->arch.tlb_fillptr;
	setup_pgtables();
	gd->arch.tlb_emerg = gd->arch.tlb_addr;
	gd->arch.tlb_addr = tlb_addr;
	gd->arch.tlb_size = tlb_size;

	/* We do the carveouts only for QCS404, for now. */
	if (fdt_node_check_compatible(gd->fdt_blob, 0, "qcom,qcs404") == 0) {
		carveout_start = get_timer(0);
		/* Takes ~20-50ms on SDM845 */
		carve_out_reserved_memory();
		debug("carveout time: %lums\n", get_timer(carveout_start));
	}
	dcache_enable();
}
