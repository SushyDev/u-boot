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
	/* MECHANISM CHECK (SPEC.md task #5 log): read OUTP_CFG/OUTN_CFG
	 * BEFORE writing them. The theory below is that our EN-pin
	 * fault-clear cycle resets the chip and wipes ABL's bias config --
	 * asserted but never measured. Reading them here settles it:
	 *   0x1e/0x1c already  -> the EN cycle does NOT reset the chip,
	 *     ABL's config survives, and the restore writes are a no-op
	 *     (which would match the observed lack of any change).
	 *   anything else      -> the chip really is being reset and the
	 *     restore is doing real work.
	 * Packed as (OUTP << 8) | OUTN into the per-chip status slot's
	 * neighbour so it survives into Linux via sheng.bl_pre. */
	{
		u8 pre_outp = 0xff, pre_outn = 0xff;
		dm_i2c_read(chip, 0x0d, &pre_outp, 1);
		dm_i2c_read(chip, 0x0e, &pre_outn, 1);
		*(volatile u32 *)(uintptr_t)(SHENG_KTZ8866_STATUS_ADDR + 0x10) =
			((u32)pre_outp << 8) | (u32)pre_outn;
	}

	/* THEORY DISPROVEN, writes KEPT as defensive (SPEC.md task #5 log).
	 *
	 * The reasoning below was that our EN-pin fault-clear cycle resets
	 * the chip and wipes ABL's bias config. The mechanism check above
	 * measured sheng.blpre = 0x1e1c, i.e. OUTP_CFG/OUTN_CFG ALREADY
	 * hold their live values before we write anything: the EN cycle
	 * does NOT reset the chip, ABL's configuration survives, and these
	 * writes are a no-op. The panel's +/-5.8V analog supply path is
	 * exonerated.
	 *
	 * Kept anyway because they write exactly the live values and cost
	 * nothing, so the configuration is explicit rather than inherited.
	 * Original reasoning retained below for the record.
	 *
	 * sheng_backlight_gpio_fault_clear_cycle() drives the KTZ8866's EN
	 * pin LOW then HIGH, which power-cycles the chip and resets every
	 * register to its default. Linux never does this: its ktz8866
	 * driver probes the chip as ABL left it and writes only BL_EN,
	 * BL_CFG2, BL_DIMMING and LCD_BIAS_CFG1 (see ktz8866_init()) --
	 * exactly the subset this function used to write. Everything else
	 * on a live system is ABL's configuration, inherited untouched.
	 *
	 * Because we reset the chip first, that inherited state is gone and
	 * nothing restores it. Critically that includes OUTP_CFG/OUTN_CFG,
	 * which set the +/-5.8V rails feeding the panel's avdd/avee
	 * (sm8550-xiaomi-sheng.dts: avdd-supply = <&bl_vddpos_5p8>,
	 * avee-supply = <&bl_vddneg_5p8>). We were enabling the LCD bias
	 * without ever telling the chip what voltage to produce.
	 *
	 * Same failure shape as mdssCoreBcrReset() wiping the MDSS UBWC
	 * block: our reset destroys inherited state the reference driver
	 * never has to restore, so a register-by-register comparison
	 * against Linux's *driver* finds nothing wrong.
	 *
	 * Values are chip A's live registers, read over /dev/i2c-0 with
	 * I2C_SLAVE_FORCE while Linux was driving the panel. Written BEFORE
	 * LCD_BIAS_CFG1's enable so the rails come up already configured.
	 */
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

	/* Brightness set EXACTLY as Linux does (SPEC.md task #5 log): one
	 * write pair, no ramp, to the same value its driver uses.
	 *
	 * ktz8866_backlight_update_status() writes
	 *   BL_BRT_LSB = brightness & 0x7
	 *   BL_BRT_MSB = (brightness >> 3) & 0xFF
	 * and nothing else. Live registers read 0x04/0xbb, i.e.
	 * (0xbb << 3) | 0x04 = 1500 -- matching
	 * /sys/class/backlight/ktz8866-backlight/brightness exactly.
	 *
	 * This driver previously ramped 0 -> 2047 in 16 steps over ~200ms.
	 * That is a visible behavioural difference from the reference on a
	 * chip whose output feeds the panel's bias, and the ramp is
	 * plainly visible on-device, so it is not a no-op. Matching Linux
	 * removes it as a variable -- and 2047 vs 1500 was also a
	 * difference nobody had accounted for. */
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


/* POST-PANEL-POWER BIAS READBACK (SPEC.md task #5 log).
 *
 * The last unverified link in the panel-power chain. We write LCD_BIAS_CFG1
 * (0x09 = 0x9F, LCD_BIAS_EN) to both KTZ8866s in
 * sheng_ktz8866_backlight_init(), which runs BEFORE the video probe. The
 * video probe then drops GPIO 30/31 (avdd/avee enables) as part of its
 * cold-start teardown and re-raises them ~100ms later. Nothing has ever
 * checked what the bias IC looks like AFTER that cycle.
 *
 * Two things worth knowing, neither ever measured:
 *   0x09 LCD_BIAS_CFG1 -- did our LCD_BIAS_EN write actually stick, and
 *                         does it survive the enable-pin cycle?
 *   0x0F FLAG          -- the chip's own fault register. If the KTZ8866
 *                         latched an OVP/OCP/UVLO fault on OUTP/OUTN, the
 *                         +/-5.8V panel rails are OFF regardless of both
 *                         the enable pins (verified driven high at the pad
 *                         via sheng.biasgpio) and the 0x09 enable bit.
 *
 * A latched bias fault would explain every remaining observation at once:
 * an unpowered panel is deaf to LP and HS alike, never answers a BTA, never
 * drives contention onto the lanes, and shows black while every SoC-side
 * register legitimately matches working silicon -- which is exactly the
 * state we are in, now that the lanes are confirmed to be driven
 * (sheng.lanes = 0x00001F00 on both links, matching live).
 *
 * Read live under a WORKING Linux display, both chips: 0x09 = 0x9f,
 * 0x0F = 0x00 (no faults). Anything else here names the culprit.
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

/* Drive LCD_BIAS_CFG1 (0x09) on both KTZ8866s. 0x9F = LCD_BIAS_EN set,
 * 0x1F = enable cleared.
 *
 * WHY THIS EXISTS: U-Boot's panel "power cycle" only toggles GPIO 30/31.
 * Those are the chip's enable pins, but LCD_BIAS_EN is also latched over
 * I2C, and we set it to 0x9F before probe. If the chip keeps the +/-5.8V
 * rails up on the strength of that I2C bit, the DDIC never actually loses
 * power -- so a reset pulse alone cannot clear its state and it will not
 * accept a fresh init sequence.
 *
 * That matches every measurement: the panel answers DCS reads (its logic
 * rail is fine), an ordinary write lands (0x37 changes the read response),
 * but 0x11 exit_sleep and the whole 94-command init leave power_mode at
 * 0x08. Linux's own boot-time init fails identically when it inherits our
 * rails, and only succeeds after a blank/unblank -- which goes through the
 * ktz8866 regulator driver and therefore clears the bias over I2C.
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

	/* Must be high before either chip will ACK on I2C -- see the
	 * comment on sheng_backlight_gpio_enable()'s definition. A couple
	 * ms is generous for the EN-to-I2C-ready time on this class of
	 * chip; the real driver's own kinetic,led-enable-ramp-delay-ms=8
	 * property only bounds the LED current ramp, not I2C readiness.
	 * DO NOT PUT THE FAULT-CLEAR CYCLE BACK.
	 *
	 * This used to call sheng_backlight_gpio_fault_clear_cycle(), which
	 * drives the KTZ8866 EN line LOW and then HIGH. That was added on the
	 * belief that this function "runs BEFORE the video probe, per
	 * board_late_init()'s reordering", so that dropping EN could only
	 * clear a latched UVLO fault before the panel existed.
	 *
	 * That belief is false. board_late_init() is INITCALL slot 758;
	 * stdio_add_devices() probes every UCLASS_VIDEO device at slot 729 and
	 * console_init_r() prints the banner at 734. The panel is already
	 * initialised and scanning out by the time we get here, so dropping EN
	 * removed its AVDD/AVEE and destroyed the DDIC's state -- and every
	 * frame after this point, the startup log included, went to a dead
	 * panel. Measured directly: a magenta fill painted immediately before
	 * this call appears, a cyan fill painted immediately after it never
	 * does.
	 *
	 * Enable-only. The chip is already enabled by this point anyway, and
	 * the fault it was meant to clear was hypothetical; the panel
	 * rendering is not. */
	sheng_backlight_gpio_enable();
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
	env_set_hex("sheng_bl_pre",
		    (unsigned long)*(volatile u32 *)(uintptr_t)(SHENG_KTZ8866_STATUS_ADDR + 0x10));
	env_set_hex("sheng_bl_en_rb_a", (unsigned long)bl_en_rb_a);
	env_set_hex("sheng_bl_en_rb_b", (unsigned long)bl_en_rb_b);

	/* Give the chips/panel time to actually respond before boot
	 * continues -- requested to make sure a slow-to-light backlight
	 * gets a real chance, not just a race against whatever runs next. */
	/* The 5s viewing hold that used to live here has MOVED to the call
	 * site in board_late_init(): this function now runs BEFORE the video
	 * probe (see its new call site's comment), and holding here would
	 * burn the hold before any picture exists. */
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
