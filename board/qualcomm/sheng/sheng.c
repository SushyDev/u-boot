// SPDX-License-Identifier: GPL-2.0+
/*
 * Xiaomi Pad 6S Pro ("sheng"), SM8550.
 *
 * Board glue that used to sit in arch/arm/mach-snapdragon/board.c and
 * ran on every Qualcomm board built from it. Selected by
 * CONFIG_SYS_BOARD="sheng".
 *
 * Two jobs: bring up the KTZ8866 pair, and relay the display driver's
 * side channels into /chosen. See drivers/video/qualcomm/ARCHITECTURE.md.
 */

#include <dm.h>
#include <env.h>
#include <fdt_support.h>
#include <i2c.h>
#include <log.h>
#include <video.h>
#include <asm/global_data.h>
#include <asm/io.h>
#include <cpu_func.h>
#include <dm/device.h>
#include <dm/uclass.h>
#include <linux/delay.h>
#include <linux/kconfig.h>
#include <linux/sizes.h>

DECLARE_GLOBAL_DATA_PTR;

extern void sheng_mdss_teardown(void);

#define SHENG_KTZ8866_BRIGHTNESS		1500u
#define SHENG_KTZ8866_STATUS_ADDR	(CONFIG_PRE_CON_BUF_ADDR + 0x3400)
#define SHENG_KTZ8866_STATUS_NOT_REACHED	0x7fffffff

/* GPIO 128 is EN on both KTZ8866s. On this chip EN gates the I2C
 * interface itself, not just the LED current sinks, so writes issued
 * before it is high either NAK or land on a chip still in reset.
 *
 * Duplicated from the driver's own TLMM poke rather than shared: this
 * must run even when CONFIG_VIDEO_SHENG_MDSS is off. */
#define SHENG_TLMM_BASE			0x00f100000
#define SHENG_TLMM_GPIO_REG_SIZE	0x1000
#define SHENG_BACKLIGHT_GPIO		128
#define SHENG_TLMM_MUX_FUNC_MASK	(0x7u << 2)
#define SHENG_TLMM_OE_BIT		(1u << 9)
#define SHENG_TLMM_OUT_BIT		(1u << 1)

/* Returns the io_reg readback: bit0 the actual pin state, bit1 the
 * driven value. A write to a TZ/XPU-protected TLMM register is dropped
 * silently, not faulted, so the readback is the only way to tell a real
 * electrical change from a no-op. */
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

	/* BL_EN is 0x1f then 0x5f, NEVER 0x7f. Only 5 of 6 current sinks
	 * are wired (`current-num-sinks = <5>`), and many LED drivers
	 * fault-protect on an open sink -- some disable output entirely.
	 * Live reference reads 0x5f.
	 *
	 * Soft start, mirroring the real driver's init/update_status
	 * split: sinks on without the master-enable bit, config and bias
	 * written with brightness still 0 so no current flows, then the
	 * master-enable bit as brightness ramps up. Slamming max
	 * brightness the instant the chip enables is peak inrush on a rail
	 * that may already be marginal. */
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
	/* OUTP_CFG/OUTN_CFG as found, before the writes below. 0x1e/0x1c
	 * means ABL's bias config survived and the writes are a no-op;
	 * anything else means something reset the chip. Packed
	 * (OUTP << 8) | OUTN. */
	{
		u8 pre_outp = 0xff, pre_outn = 0xff;
		dm_i2c_read(chip, 0x0d, &pre_outp, 1);
		dm_i2c_read(chip, 0x0e, &pre_outn, 1);
		*(volatile u32 *)(uintptr_t)(SHENG_KTZ8866_STATUS_ADDR + 0x10) =
			((u32)pre_outp << 8) | (u32)pre_outn;
	}

	/* Bias configuration, written explicitly rather than inherited.
	 *
	 * Linux writes only BL_EN, BL_CFG2, BL_DIMMING and LCD_BIAS_CFG1 and
	 * inherits the rest from ABL. These are the live values, so on a
	 * normal boot they are a no-op -- but they cost nothing and make the
	 * configuration explicit instead of dependent on what ABL left.
	 *
	 * OUTP_CFG/OUTN_CFG set the +/-5.8V rails feeding the panel's
	 * avdd/avee. Written BEFORE LCD_BIAS_CFG1 enables the bias, so the
	 * rails come up already configured rather than being enabled without
	 * a voltage. */
	val = 0xfa; /* BL_CFG1 */
	ret = dm_i2c_write(chip, 0x02, &val, 1);
	if (ret)
		return ret;
	val = 0x11; /* LCD_BIAS_CFG2 */
	ret = dm_i2c_write(chip, 0x0a, &val, 1);
	if (ret)
		return ret;
	val = 0x28; /* LCD_BOOST_CFG */
	ret = dm_i2c_write(chip, 0x0c, &val, 1);
	if (ret)
		return ret;
	val = 0x1e; /* OUTP_CFG: +5.8V rail (panel avdd) */
	ret = dm_i2c_write(chip, 0x0d, &val, 1);
	if (ret)
		return ret;
	val = 0x1c; /* OUTN_CFG: -5.8V rail (panel avee) */
	ret = dm_i2c_write(chip, 0x0e, &val, 1);
	if (ret)
		return ret;
	val = 0x80; /* BL_OPTION1 */
	ret = dm_i2c_write(chip, 0x10, &val, 1);
	if (ret)
		return ret;
	val = 0x77; /* BL_OPTION2 */
	ret = dm_i2c_write(chip, 0x11, &val, 1);
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

	/* One write pair, no ramp, same value Linux uses.
	 * ktz8866_backlight_update_status() writes BL_BRT_LSB =
	 * brightness & 0x7 and BL_BRT_MSB = (brightness >> 3) & 0xff, and
	 * nothing else. Live reads 0x04/0xbb, i.e. 1500.
	 *
	 * Do not ramp. This chip's output feeds the panel bias, so a ramp
	 * is a real behavioural difference, not cosmetic. */
	val = SHENG_KTZ8866_BRIGHTNESS & 0x07;
	ret = dm_i2c_write(chip, 0x04, &val, 1);
	if (ret)
		return ret;
	val = (SHENG_KTZ8866_BRIGHTNESS >> 3) & 0xff;
	ret = dm_i2c_write(chip, 0x05, &val, 1);
	if (ret)
		return ret;

	return 0;
}

extern void sheng_mdss_teardown(void);


/* Bias IC state after the video probe has cycled the avdd/avee enable
 * pins.
 *
 *   0x09 LCD_BIAS_CFG1 -- did LCD_BIAS_EN stick, and survive the cycle?
 *   0x0F FLAG          -- the chip's own fault register. A latched
 *                         OVP/OCP/UVLO on OUTP/OUTN turns the +/-5.8V
 *                         panel rails OFF regardless of the enable pins
 *                         and the 0x09 enable bit.
 *
 * An unpowered panel is deaf on LP and HS alike, answers no BTA, and
 * shows black while every SoC-side register reads correct.
 *
 * Live under a working display, both chips: 0x09 = 0x9f, 0x0F = 0x00.
 *
 * Packed: [63:56] A 0x09, [55:48] A 0x0F, [31:24] B 0x09, [23:16] B 0x0F.
 */
static int sheng_ktz8866_read_chip(const char *path, u8 *cfg1, u8 *flag)
{
	struct udevice *bus, *chip;
	ofnode i2c_node;
	int ret;

	*cfg1 = 0xff;
	*flag = 0xff;

	i2c_node = ofnode_path(path);
	if (!ofnode_valid(i2c_node))
		return -ENOENT;
	ret = uclass_get_device_by_ofnode(UCLASS_I2C, i2c_node, &bus);
	if (ret)
		return ret;
	ret = dm_i2c_probe(bus, 0x11, 0, &chip);
	if (ret)
		return ret;

	ret = dm_i2c_read(chip, 0x09, cfg1, 1);
	if (ret)
		return ret;
	return dm_i2c_read(chip, 0x0f, flag, 1);
}

/* Drive LCD_BIAS_CFG1 (0x09) on both KTZ8866s. 0x9F sets LCD_BIAS_EN,
 * 0x1F clears it.
 *
 * LOAD-BEARING. The panel power cycle toggles GPIO 30/31, but those are
 * only the chip's enable pins -- LCD_BIAS_EN is latched over I2C as
 * well. Leave it set and the chip holds the +/-5.8V rails up, the DDIC
 * never loses power, a reset pulse cannot clear its state, and it will
 * not accept a fresh init.
 *
 * The failure is cumulative and does not look like this: the panel
 * renders for several boots on inherited state before it latches, then
 * stays black across reboots until someone holds POWER to force the
 * device off. Linux hits the same wall when it inherits our rails, and
 * recovers only after a blank/unblank, which clears the bias over I2C.
 */
int sheng_ktz8866_set_bias(int enable)
{
	static const char * const paths[] = {
		"/soc@0/geniqup@ac0000/i2c@a84000",
		"/soc@0/geniqup@9c0000/i2c@988000",
	};
	u8 val = enable ? 0x9f : 0x1f;
	int i, rc = 0;

	for (i = 0; i < 2; i++) {
		struct udevice *bus, *chip;
		ofnode node = ofnode_path(paths[i]);

		if (!ofnode_valid(node) ||
		    uclass_get_device_by_ofnode(UCLASS_I2C, node, &bus) ||
		    dm_i2c_probe(bus, 0x11, 0, &chip) ||
		    dm_i2c_write(chip, 0x09, &val, 1))
			rc = -1;
	}
	return rc;
}

static void sheng_ktz8866_bias_readback(void)
{
	u8 a_cfg1, a_flag, b_cfg1, b_flag;

	sheng_ktz8866_read_chip("/soc@0/geniqup@ac0000/i2c@a84000", &a_cfg1, &a_flag);
	sheng_ktz8866_read_chip("/soc@0/geniqup@9c0000/i2c@988000", &b_cfg1, &b_flag);

	env_set_hex("sheng_bl_post",
		    (((unsigned long)a_cfg1) << 56) | (((unsigned long)a_flag) << 48) |
		    (((unsigned long)b_cfg1) << 24) | (((unsigned long)b_flag) << 16));
}

static void sheng_ktz8866_backlight_init(void)
{
	int ret;

	sheng_ktz8866_status_set(0, SHENG_KTZ8866_STATUS_NOT_REACHED);
	sheng_ktz8866_status_set(1, SHENG_KTZ8866_STATUS_NOT_REACHED);

	/* EN must be high before either chip will ACK on I2C. 2ms is
	 * generous for EN-to-I2C-ready; the DT's
	 * kinetic,led-enable-ramp-delay-ms bounds the LED current ramp, not
	 * I2C readiness.
	 *
	 * ENABLE-ONLY, DELIBERATELY. Never drive EN low here. This is
	 * INITCALL 758; the video probe ran at 729 and the panel is already
	 * scanning out, so dropping EN removes its AVDD/AVEE and kills the
	 * DDIC. Everything drawn afterwards, the startup log included, goes
	 * to a dead panel. */
	sheng_backlight_gpio_enable();
	u32 io_readback = sheng_backlight_gpio_set(1);
	mdelay(2);

	u32 bl_en_rb_a = 0xffffffff, bl_en_rb_b = 0xffffffff;

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@ac0000/i2c@a84000", &bl_en_rb_a); /* "A" */
	sheng_ktz8866_status_set(0, ret);
	int ret_a = ret;

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@9c0000/i2c@988000", &bl_en_rb_b); /* "B" */
	sheng_ktz8866_status_set(1, ret);

	/* Report through the environment, not the status relay: that lives
	 * in a no-map reserved region, and /dev/mem cannot read one at all
	 * (xlate_dev_mem_ptr() has no linear-map pointer for it, so read()
	 * returns EFAULT). These land in bootargs, so /proc/cmdline is the
	 * readout.
	 *
	 * io_readback bit 1 is the driven GPIO 128 value, bit 0 the actual
	 * pin. Both writes returning 0 while bl_en_rb_a/b do not read back
	 * 0x5f means the I2C driver reported success without a real ACK, or
	 * the chip never powered up. */
	env_set_hex("sheng_bl_ret_a", (unsigned long)ret_a);
	env_set_hex("sheng_bl_ret_b", (unsigned long)ret);
	env_set_hex("sheng_bl_gpio_io", (unsigned long)io_readback);
	env_set_hex("sheng_bl_pre",
		    (unsigned long)*(volatile u32 *)(uintptr_t)(SHENG_KTZ8866_STATUS_ADDR + 0x10));
	env_set_hex("sheng_bl_en_rb_a", (unsigned long)bl_en_rb_a);
	env_set_hex("sheng_bl_en_rb_b", (unsigned long)bl_en_rb_b);

}

int ft_board_setup(void *blob, struct bd_info *bd)
{
	/* Relay the driver's side channels into /chosen, readable from
	 * Linux under /proc/device-tree/chosen/. There is no console during
	 * probe, so this is the only way the results get out.
	 *
	 * mdss-status is 9 stages x 4 bytes, in SHENG_MDSS_STATUS_* order.
	 * The count MUST track SHENG_MDSS_STATUS_COUNT. Each slot is
	 * 0x7fffffff for a stage never reached, 0 on success, or -errno.
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
			/* Log ring: a u32 entry count then up to 64 (tag,
			 * value) pairs, 516 bytes. Relay the whole fixed
			 * region; the count says how much is valid. */
			fdt_setprop(blob, nodeoff, "sheng,mdss-log",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3100),
				    4 + 64 * 8);
			/* Per-chip KTZ8866 status, [chip_a, chip_b], same
			 * convention as mdss-status. Sits clear of the log
			 * ring, which ends at 0x3304. */
			fdt_setprop(blob, nodeoff, "sheng,ktz8866-status",
				    (void *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3400),
				    8);
		}
	}

	return 0;
}

/*
 * Runs from board_late_init() via the generic hook.
 *
 * ORDER: this is INITCALL slot 758. stdio_add_devices() probes every
 * UCLASS_VIDEO device at slot 729 and console_init_r() prints the
 * banner at 734, so the panel is already initialised and scanning out
 * by the time we get here. Nothing below may disturb its power -- in
 * particular the KTZ8866 EN line, which gates AVDD/AVEE. Dropping it
 * kills the DDIC and it does not recover.
 */
void qcom_late_init(void)
{
	sheng_ktz8866_backlight_init();

	/* CONFIG_VIDEO only BINDS video devices during early boot. Nothing
	 * in this board's flow probes one -- no splash, and CONSOLE_MUX /
	 * SYS_CONSOLE_IS_IN_ENV are both off. Force the probe so
	 * sheng_mdss_probe() actually runs. */
	if (IS_ENABLED(CONFIG_VIDEO)) {
		struct udevice *vdev = NULL;
		int vret;

		vret = uclass_get_device(UCLASS_VIDEO, 0, &vdev);
		/* Separate slot from the driver's own stage array, so it is
		 * populated even when probe() is never entered: tells "no
		 * video device bound" (-ENODEV) from "bound, probe failed". */
		if (IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
			*(volatile int *)(uintptr_t)(CONFIG_PRE_CON_BUF_ADDR + 0x3020) = vret;
		env_set_hex("sheng_mdss_vret", (unsigned long)vret);
	}

	sheng_ktz8866_bias_readback();
}

/*
 * Tear the display down immediately before jumping into the OS.
 *
 * MUST be here and not in board_late_init(): that finishes before
 * main_loop(), so a teardown there kills the panel before the console
 * banner, bootcmd or the boot menu ever draw, and every later write
 * lands in a dead framebuffer.
 *
 * Guarded on CONFIG_VIDEO_SHENG_MDSS because sheng_mdss.c is not
 * compiled at all when that is off, so an unconditional call would not
 * link.
 */
void board_preboot_os(void)
{
	if (IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS))
		sheng_mdss_teardown();
}
