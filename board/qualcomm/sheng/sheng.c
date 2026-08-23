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
#include <time.h>
#include <video.h>
#include <asm/global_data.h>
#include <asm/io.h>
#include <cpu_func.h>
#include <dm/device.h>
#include <dm/uclass.h>
#include <linux/delay.h>
#include <linux/kconfig.h>
#include <linux/sizes.h>
#include <power/pmic.h>
#include <linux/psci.h>
#include <sheng_mdss_abi.h>

DECLARE_GLOBAL_DATA_PTR;

/* The DPU base, for the gentle stop in board_preboot_os(). Duplicated
 * rather than including sheng_mdss_regs.h, for the same reason as the
 * GPIO numbers below: this file must still build with
 * CONFIG_VIDEO_SHENG_MDSS off. */
#define SHENG_DPU_BASE			0x0ae01000


/* Time the backlight actually came on, microseconds since power-on.
 * Recorded in qcom_late_init() and relayed in ft_board_setup(), which
 * runs later still (at booti time). */
static unsigned long sheng_backlight_us;

#define SHENG_KTZ8866_BRIGHTNESS		1500u

/* Read-only handover sampling only -- driving these goes through the
 * named helpers in <sheng_mdss_abi.h>. GPIO 128 is EN on both KTZ8866s;
 * on this chip EN gates the I2C interface itself, not just the LED sinks,
 * so writes issued before it is high either NAK or land on a chip still
 * in reset. */
#define SHENG_BACKLIGHT_GPIO		128
#define SHENG_PANEL_AVDD_GPIO		30
#define SHENG_PANEL_AVEE_GPIO		31
#define SHENG_PANEL_RESET_GPIO		133

/* EN-to-I2C-ready. Generous: the DT's kinetic,led-enable-ramp-delay-ms
 * bounds the LED current ramp, not I2C readiness. */
#define SHENG_KTZ8866_EN_TO_I2C_MS	2

/* Display state as ABL left it, sampled at board_init() before anything
 * of ours touches it. bit0 is the pin level, bit1 the driven value.
 *
 * TLMM is always clocked, so these reads are safe this early. MDSS
 * registers are not.
 *
 * GPIO numbers are duplicated rather than including sheng_mdss_regs.h:
 * this file must still build with CONFIG_VIDEO_SHENG_MDSS off.
 */
static u32 sheng_handover_bl, sheng_handover_avdd;
static u32 sheng_handover_avee, sheng_handover_rst;

/* KTZ8866 state as ABL left it, read before anything of ours writes to
 * the chip. Diagnostic only: LCD_BIAS_CFG1 reflects whoever programmed
 * the chip last, which on a warm reboot is Linux, not ABL.
 *
 * Packed: BL_EN << 24 | BRT_MSB << 16 | BRT_LSB << 8 | LCD_BIAS_CFG1.
 */
static u32 sheng_handover_blregs = 0xffffffff;
static int sheng_handover_blret;

/* Set in qcom_board_init() from the I2C read above; consumed by
 * sheng_mdss_probe() to decide inherit vs cold bring-up. */
int sheng_abl_splash_live;

static int sheng_ktz8866_read_handover(const char *path)
{
	struct udevice *bus, *chip;
	ofnode i2c_node;
	u8 en = 0xff, lsb = 0xff, msb = 0xff, bias = 0xff;
	int ret;

	i2c_node = ofnode_path(path);
	if (!ofnode_valid(i2c_node))
		return -ENOENT;
	ret = uclass_get_device_by_ofnode(UCLASS_I2C, i2c_node, &bus);
	if (ret)
		return ret;
	ret = dm_i2c_probe(bus, 0x11, 0, &chip);
	if (ret)
		return ret;

	/* Read-only. Writing anything here would destroy the very state we
	 * are trying to observe.
	 *
	 * Every read is checked. sheng_ktz8866_backlight_init()'s fast path
	 * decides from these bits whether to skip the twelve-register init,
	 * so a partial read must not be mistaken for a live chip: one failed
	 * transfer here used to leave its 0xff default in place and still
	 * report success. Fail the whole sample instead -- the caller's
	 * 0xffffffff sentinel then forces the full path.
	 */
	if (dm_i2c_read(chip, 0x08, &en, 1) ||		/* BL_EN */
	    dm_i2c_read(chip, 0x05, &msb, 1) ||		/* BL_BRT_MSB */
	    dm_i2c_read(chip, 0x04, &lsb, 1) ||		/* BL_BRT_LSB */
	    dm_i2c_read(chip, 0x09, &bias, 1))		/* LCD_BIAS_CFG1 */
		return -EIO;

	sheng_handover_blregs = ((u32)en << 24) | ((u32)msb << 16) |
				((u32)lsb << 8) | (u32)bias;
	return 0;
}

void qcom_board_init(void)
{
	sheng_handover_bl = sheng_gpio_read(SHENG_BACKLIGHT_GPIO);
	sheng_handover_avdd = sheng_gpio_read(SHENG_PANEL_AVDD_GPIO);
	sheng_handover_avee = sheng_gpio_read(SHENG_PANEL_AVEE_GPIO);
	sheng_handover_rst = sheng_gpio_read(SHENG_PANEL_RESET_GPIO);
	sheng_handover_blret =
		sheng_ktz8866_read_handover("/soc@0/geniqup@ac0000/i2c@a84000");

	/* Does ABL hand over a live display? Decided from our own DTB, never
	 * by reading an MDSS register.
	 *
	 * Asking the DPU or DSI host whether it is streaming is a trap: those
	 * blocks need clocks that only run WHILE ABL IS STREAMING, so the read
	 * answers correctly when live and WEDGES THE AHB BUS in exactly the
	 * case it exists to detect. Recovery is fastboot.
	 *
	 * The KTZ8866 is on I2C and always readable, but LCD_BIAS_CFG1
	 * reflects whoever programmed the chip last, which on a warm reboot is
	 * Linux, not ABL. It is recorded in the diag, not used as a test.
	 *
	 * Whether ABL keeps the panel alive is decided by whether we advertise
	 * /reserved-memory/splash_region. We control both sides of that, and
	 * reading our own device tree cannot wedge a bus.
	 *
	 * If ABL ever ignores the node we inherit a dead pipeline and U-Boot
	 * shows a dark panel. Linux still boots.
	 */
	sheng_abl_splash_live =
		ofnode_valid(ofnode_path("/reserved-memory/splash_region"));

	/* Measured 2026-08-22: WITHOUT /reserved-memory/splash_region, a 3s
	 * hold here shows an already-black panel with backlight EN and both
	 * rails still high -- ABL does not cut power, it blanks and hands
	 * over dark. WITH the node present it does not blank at all and
	 * hands over a live pipeline, which sheng_mdss_probe() inherits.
	 * Either way the answer was in the DTB, not in this file. */
}

/* THE ONLY WAY TO WRITE A BREADCRUMB FROM THIS FILE.
 *
 * D-cache is on for this board, so a plain volatile store can sit dirty
 * in a cache line indefinitely -- and the whole point of a breadcrumb is
 * to survive a hang on the very next instruction. Every write must be
 * followed by flush + dsb, so no caller open-codes the store.
 *
 * Two sites used to do it by hand and both forgot the flush: the
 * OUTP/OUTN handover sample in sheng_ktz8866_write_chip(), and the
 * uclass_get_device() result in qcom_late_init(). Neither value was
 * reliably reaching DRAM, which made them useless exactly when a boot
 * hung -- the case they exist for.
 */
void sheng_breadcrumb_u32(unsigned long addr, u32 value)
{
	if (!IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER))
		return;

	*(volatile u32 *)(uintptr_t)addr = value;
	flush_dcache_range(addr, addr + sizeof(value));
	dsb();
}

static void sheng_ktz8866_status_set(unsigned int slot, int ret)
{
	volatile struct sheng_blackbox *bb = SHENG_BLACKBOX;

	sheng_breadcrumb_u32((unsigned long)(uintptr_t)&bb->ktz8866[slot],
			     (u32)ret);
}

static int sheng_ktz8866_write_chip(const char *path)
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

		if (dm_i2c_read(chip, 0x0d, &pre_outp, 1))
			pre_outp = 0xff;
		if (dm_i2c_read(chip, 0x0e, &pre_outn, 1))
			pre_outn = 0xff;
		sheng_breadcrumb_u32((unsigned long)(uintptr_t)
				     &SHENG_BLACKBOX->ktz8866_outcfg,
				     ((u32)pre_outp << 8) | (u32)pre_outn);
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

/* Brightness only -- two writes, for when the chip is already configured
 * and enabled. See the fast path in sheng_ktz8866_backlight_init(). */
static int sheng_ktz8866_set_brightness(const char *path)
{
	struct udevice *bus, *chip;
	ofnode i2c_node;
	u8 val;
	int ret;

	i2c_node = ofnode_path(path);
	if (!ofnode_valid(i2c_node))
		return -ENOENT;
	ret = uclass_get_device_by_ofnode(UCLASS_I2C, i2c_node, &bus);
	if (ret)
		return ret;
	ret = dm_i2c_probe(bus, 0x11, 0, &chip);
	if (ret)
		return ret;

	val = SHENG_KTZ8866_BRIGHTNESS & 0x7;
	ret = dm_i2c_write(chip, 0x04, &val, 1);
	if (ret)
		return ret;
	val = (SHENG_KTZ8866_BRIGHTNESS >> 3) & 0xff;
	return dm_i2c_write(chip, 0x05, &val, 1);
}

static void sheng_ktz8866_backlight_init(void)
{
	int ret;

	/* FAST PATH: ABL already configured and enabled this chip.
	 *
	 * Measured (b367): ABL hands over BL_EN=0x7f, brightness 1390, LCD
	 * bias on -- i.e. the backlight is LIT the whole time. The screen is
	 * dark because the DDIC is asleep behind it, not because the
	 * backlight is off. Re-running the full twelve-register init to
	 * reach a state the chip is already in costs ~110ms, and every one
	 * of those milliseconds is inside the black gap.
	 *
	 * Requires the master-enable bit (0x40 in BL_EN) and LCD_BIAS_EN
	 * (0x80 in LCD_BIAS_CFG1) to both be set in what we actually read at
	 * board_init(). Anything else -- including a failed read, which
	 * leaves blregs at 0xffffffff -- takes the full path.
	 */
	if (sheng_handover_blret == 0 &&
	    sheng_handover_blregs != 0xffffffff &&
	    ((sheng_handover_blregs >> 24) & 0x40) &&
	    (sheng_handover_blregs & 0x80)) {
		sheng_backlight_enable();
		ret = sheng_ktz8866_set_brightness("/soc@0/geniqup@ac0000/i2c@a84000");
		sheng_ktz8866_status_set(0, ret);
		ret = sheng_ktz8866_set_brightness("/soc@0/geniqup@9c0000/i2c@988000");
		sheng_ktz8866_status_set(1, ret);
		return;
	}
	sheng_ktz8866_status_set(0, SHENG_MDSS_STATUS_NOT_REACHED);
	sheng_ktz8866_status_set(1, SHENG_MDSS_STATUS_NOT_REACHED);

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
	sheng_backlight_enable();
	mdelay(SHENG_KTZ8866_EN_TO_I2C_MS);

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@ac0000/i2c@a84000");
	sheng_ktz8866_status_set(0, ret);

	ret = sheng_ktz8866_write_chip("/soc@0/geniqup@9c0000/i2c@988000");
	sheng_ktz8866_status_set(1, ret);
}

/* XBL/ABL's own log, scraped from the region it writes into.
 *
 * xbl-dt-log-region@81a00000 is no-map, so Linux cannot read it --
 * /dev/mem returns EFAULT. U-Boot has plain access, so relaying it
 * through /chosen is the only way to see what ABL said.
 *
 * Scans for the first printable ASCII run of at least MINRUN characters,
 * so a region of binary or zeros yields an empty property rather than
 * garbage.
 */
#define SHENG_XBL_LOG_ADDR	0x81a00000
#define SHENG_XBL_LOG_SIZE	0x40000
#define SHENG_XBL_LOG_COPY	768

/* Keywords worth finding. Dumping from the start of the region just
 * shows PBL/XBL boot banners (verified b367) -- anything ABL says about
 * the display is much further in, past 256KB of earlier logging. */
static const char * const sheng_xbl_keys[] = {
	"Display", "display", "DISPLAY", "MDP", "Splash", "splash", "Panel",
};

static bool sheng_mem_match(const volatile u8 *p, unsigned int off,
			    unsigned int limit, const char *s)
{
	unsigned int k;

	for (k = 0; s[k]; k++) {
		if (off + k >= limit || p[off + k] != (u8)s[k])
			return false;
	}
	return true;
}

/* Same tail-dump, over an arbitrary region.
 *
 * WHY A SECOND REGION: xbl-dt-log-region@81a00000 ends at "SBL1, End"
 * (1.479s). ABL runs from there until it hands over at ~5.57s -- FOUR
 * SECONDS, 62% of the whole boot, and where the panel goes dark -- and
 * it keeps its own log somewhere else.
 *
 * xbl-ramdump-region@81200000 is 0x280000 (2.5MB). U-Boot's pre-console
 * buffer sits at its START and is only CONFIG_PRE_CON_BUF_SZ (16KB), so
 * anything ABL left beyond that is intact. Skip our own 16KB and scan
 * the rest rather than relocating PRE_CON_BUF_ADDR, which would have
 * been the risky way to answer the same question.
 */
static int sheng_log_tail(const volatile u8 *p, unsigned int size,
			  char *out, int outlen)
{
	unsigned int i, j, last_text = 0;
	int n = 0;

	for (i = 0; i < size; i++) {
		if (sheng_mem_match(p, i, size, "B - ") ||
		    sheng_mem_match(p, i, size, "S - ") ||
		    sheng_mem_match(p, i, size, "D - "))
			last_text = i;
	}
	if (!last_text)
		return 0;

	{
		unsigned int start = last_text > SHENG_XBL_LOG_COPY ?
					last_text - SHENG_XBL_LOG_COPY : 0;

		while (start < size && p[start] != '\n')
			start++;

		for (j = start; j < size && n < outlen - 2 &&
				j < last_text + 200; j++) {
			u8 c = p[j];

			out[n++] = ((c >= 0x20 && c < 0x7f) || c == '\n')
					? (char)c : '.';
		}
	}
	out[n] = '\0';
	return n + 1;
}

#define SHENG_ABL_LOG_ADDR	(CONFIG_PRE_CON_BUF_ADDR + CONFIG_PRE_CON_BUF_SZ)
#define SHENG_ABL_LOG_SIZE	(0x280000 - CONFIG_PRE_CON_BUF_SZ)

static int sheng_xbl_log_scrape(char *out, int outlen)
{
	const volatile u8 *p = (const volatile u8 *)(uintptr_t)SHENG_XBL_LOG_ADDR;
	unsigned int i, j;
	int n = 0;

	/* Find the END of the text log first, then walk back.
	 *
	 * Dumping from the start shows PBL/XBL banners; keyword-searching
	 * forward hits the binary devcfg tables that follow the text
	 * (NAMEDNODE_Display / SIDMappings -- SID mapping data, not a log).
	 * Both were tried (b367/b368). The LATEST boot stage is at the END
	 * of the text, so that is where ABL's own lines are, including
	 * anything it says about tearing the display down.
	 */
	{
		unsigned int last_text = 0;

		for (i = 0; i < SHENG_XBL_LOG_SIZE; i++) {
			/* "B - " / "S - " / "D - " line prefixes are the
			 * log's own format; use them as the marker for
			 * genuine log text rather than any printable byte.
			 *
			 * Match the WHOLE prefix at i. The previous version
			 * tested for " - " at i AND p[i] being B/S/D, which
			 * cannot both hold -- so last_text stayed 0 and this
			 * whole block was dead, silently falling through to
			 * the keyword scan. */
			if (sheng_mem_match(p, i, SHENG_XBL_LOG_SIZE, "B - ") ||
			    sheng_mem_match(p, i, SHENG_XBL_LOG_SIZE, "S - ") ||
			    sheng_mem_match(p, i, SHENG_XBL_LOG_SIZE, "D - "))
				last_text = i;
		}

		if (last_text) {
			unsigned int start = last_text;
			unsigned int back = 0;

			/* Walk back ~SHENG_XBL_LOG_COPY bytes of lines so we
			 * get the tail in context, not just the final line. */
			while (start > 0 && back < SHENG_XBL_LOG_COPY) {
				start--;
				back++;
			}
			while (start < SHENG_XBL_LOG_SIZE && p[start] != '\n')
				start++;

			for (j = start; j < SHENG_XBL_LOG_SIZE &&
					n < outlen - 2 &&
					j < last_text + 200; j++) {
				u8 c = p[j];

				out[n++] = ((c >= 0x20 && c < 0x7f) || c == '\n')
						? (char)c : '.';
			}
			out[n] = '\0';
			return n + 1;
		}
	}

	for (i = 0; i < SHENG_XBL_LOG_SIZE && n < outlen - 2; i++) {
		bool hit = false;

		for (j = 0; j < ARRAY_SIZE(sheng_xbl_keys); j++) {
			if (sheng_mem_match(p, i, SHENG_XBL_LOG_SIZE,
					    sheng_xbl_keys[j])) {
				hit = true;
				break;
			}
		}
		if (!hit)
			continue;

		/* Back up to the start of the line so the timestamp and log
		 * type come with it -- the format is
		 * "B - <microsec> - <message>". */
		{
			unsigned int start = i;
			unsigned int back = 0;

			while (start > 0 && back < 80 && p[start - 1] != '\n') {
				start--;
				back++;
			}

			for (j = start; j < SHENG_XBL_LOG_SIZE &&
					n < outlen - 2; j++) {
				u8 c = p[j];

				if (c == '\n')
					break;
				out[n++] = (c >= 0x20 && c < 0x7f) ? (char)c : '.';
			}
			out[n++] = '\n';
			i = j; /* resume past this line */
		}
	}

	if (!n)
		return 0;
	out[n] = '\0';
	return n + 1;
}

/* Dump both PON peripherals, to tell a power-key boot from a cable
 * insert.
 *
 * pmk8550 is pmic@0. U-Boot's qcom PMIC addresses registers as
 * (PID << 8) | offset, so pon@1300's HLOS half is PID 0x13 and the PBS
 * half at 0x800 is PID 0x08.
 *
 * READ-ONLY. The reason offsets differ between PON generations and this
 * is a GEN3 part; a shutdown written against a guessed offset turns
 * "boots when you plug in" into "reboot-loops when you plug in", which
 * only fastboot escapes.
 */
static int sheng_pon_dump(char *out, int outlen)
{
	struct udevice *pmic;
	ofnode node;
	int n = 0, i, ret;

	node = ofnode_path("/soc@0/spmi@c400000/pmic@0");
	if (!ofnode_valid(node))
		node = ofnode_path("/spmi@c400000/pmic@0");
	if (!ofnode_valid(node))
		return 0;

	ret = uclass_get_device_by_ofnode(UCLASS_PMIC, node, &pmic);
	if (ret)
		return snprintf(out, outlen, "pmic_err=%d", ret) + 1;

	n += snprintf(out + n, outlen - n, "hlos@13xx:");
	for (i = 0; i < 0x20 && n < outlen - 8; i++) {
		int v = pmic_reg_read(pmic, (0x13 << 8) | i);

		n += snprintf(out + n, outlen - n, " %02x", v < 0 ? 0xff : v & 0xff);
	}
	n += snprintf(out + n, outlen - n, " pbs@08xx:");
	for (i = 0; i < 0x20 && n < outlen - 8; i++) {
		int v = pmic_reg_read(pmic, (0x08 << 8) | i);

		n += snprintf(out + n, outlen - n, " %02x", v < 0 ? 0xff : v & 0xff);
	}

	/* DO NOT SCAN THE PMIC BLIND.
	 *
	 * b404 walked both peripherals 0x20-0xff looking for
	 * PON_PS_HOLD_RESET_CTL and CRASHED THE BOARD INTO FASTBOOT. Reads
	 * are not automatically safe on SPMI: unimplemented addresses can
	 * fault the bus, and some registers are clear-on-read. Only touch
	 * offsets something documents or a driver already uses.
	 *
	 * The 0x00-0x1f window above is known-good (b402/b403) and is what
	 * carries the power-on reason bits.
	 */
	return n + 1;
}

/* Charger insert powers the SoC up. Stay off instead of booting Linux.
 *
 * Stock ABL routes a cable insert to offline charging, which we do not
 * implement, so every plug-in becomes a full boot.
 *
 * Detection: PBS peripheral (PID 0x08) offset 0x15. Across three boot
 * types every other byte was identical:
 *
 *     warm reboot  0x17   bit5=0 bit7=0
 *     power key    0x37   bit5=1 bit7=0
 *     charger      0xb7   bit5=1 bit7=1
 *
 * bit7 is charger-initiated, bit5 is cold boot. Require BOTH, or a warm
 * reboot is mistaken for a cable insert.
 *
 * Shutdown uses PSCI SYSTEM_OFF, not PMIC registers. Selecting SHUTDOWN
 * in PON_PS_HOLD_RST_CTL (0x5a) and dropping PS_HOLD means writing PMIC
 * state, and a wrong type makes the drop a WARM RESET -- a reboot loop.
 * U-Boot's qcom_pshold driver has that bug: it writes 0 to PS_HOLD for
 * every sysreset type, POWER_OFF included.
 *
 * The escape hatch is load-bearing. It is not known what the reason bits
 * read when POWER is pressed with a cable already connected; that boot
 * may look like a plain insert. So announce and wait: hold POWER during
 * the countdown and it boots normally. KPDPWR live state comes from
 * PON_INT_RT_STS, the same bit button-qcom-pmic uses.
 */
#define SHENG_PON_PBS_PID	0x08
#define SHENG_PON_REASON_OFF	0x15
#define SHENG_PON_REASON_CHARGER	BIT(7)
#define SHENG_PON_REASON_COLD		BIT(5)
#define SHENG_PON_HLOS_PID	0x13
#define SHENG_PON_INT_RT_STS	0x10
#define SHENG_PON_GEN3_KPDPWR	BIT(7)

static struct udevice *sheng_pon_pmic(void)
{
	struct udevice *pmic;
	ofnode node;

	node = ofnode_path("/soc@0/spmi@c400000/pmic@0");
	if (!ofnode_valid(node))
		node = ofnode_path("/spmi@c400000/pmic@0");
	if (!ofnode_valid(node))
		return NULL;

	return uclass_get_device_by_ofnode(UCLASS_PMIC, node, &pmic) ? NULL : pmic;
}

static void sheng_charger_boot_poweroff(void)
{
	struct udevice *pmic = sheng_pon_pmic();
	int reason, i;

	if (!pmic)
		return;

	reason = pmic_reg_read(pmic, (SHENG_PON_PBS_PID << 8) | SHENG_PON_REASON_OFF);
	if (reason < 0)
		return;

	if (!(reason & SHENG_PON_REASON_CHARGER) ||
	    !(reason & SHENG_PON_REASON_COLD))
		return;

	/* DO NOT POWER OFF HERE. Tried it (b406) and it is an INFINITE
	 * REBOOT LOOP: the cable is still inserted, so the PMIC powers the
	 * SoC straight back up, we detect the charger again, power off
	 * again, forever. Powering down is simply not available while a
	 * charger is connected -- which is exactly why stock shows a
	 * charging screen instead of shutting down.
	 *
	 * So do what stock does: stay here. Linux is never booted, the panel
	 * shows this message, and pressing POWER boots normally. Idling in
	 * U-Boot is not a low-power charging mode, but it does the thing
	 * that actually matters -- plugging in a charger no longer drags the
	 * whole OS up.
	 */
	log_debug("sheng: charger-insert power-on (PON reason 0x%02x)\n", reason);
	printf("sheng: charging. Press POWER to boot.\n");

	for (i = 0; ; i++) {
		int sts = pmic_reg_read(pmic,
					(SHENG_PON_HLOS_PID << 8) | SHENG_PON_INT_RT_STS);

		if (sts > 0 && (sts & SHENG_PON_GEN3_KPDPWR)) {
			/* WAIT FOR RELEASE before returning, or the same
			 * press is still down when the boot menu starts
			 * polling stdin and instantly selects entry 0.
			 * button-kbd reports the live pin state, so a held
			 * key is indistinguishable from a fresh keystroke.
			 *
			 * Bounded so a stuck or shorted key cannot strand
			 * the boot here -- after 10s give up and continue,
			 * which is the same outcome as before this loop
			 * existed. */
			for (i = 0; i < 100; i++) {
				sts = pmic_reg_read(pmic,
						    (SHENG_PON_HLOS_PID << 8) |
						    SHENG_PON_INT_RT_STS);
				if (sts >= 0 && !(sts & SHENG_PON_GEN3_KPDPWR))
					break;
				mdelay(100);
			}
			return;
		}
		mdelay(100);
	}
}

int ft_board_setup(void *blob, struct bd_info *bd)
{
	/* Relay the driver's side channels into /chosen, readable from
	 * Linux under /proc/device-tree/chosen/. There is no console during
	 * probe, so this is the only way the results get out.
	 *
	 * mdss-status is one 4-byte slot per stage, in SHENG_MDSS_STATUS_*
	 * order. Each slot is SHENG_MDSS_STATUS_NOT_REACHED for a stage
	 * never reached, 0 on success, or -errno.
	 *
	 * The last slot is the probe result. Anything but 0 there means an
	 * early return and therefore backlight with no picture; the first
	 * non-zero slot before it names the stage that failed.
	 *
	 * Every length below is a sizeof() over struct sheng_blackbox, so
	 * adding a stage or a log entry cannot leave a relay truncated. The
	 * stage count in particular used to be a literal `11 * 4` under a
	 * comment saying it must track SHENG_MDSS_STATUS_COUNT.
	 */
	if (IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS) && IS_ENABLED(CONFIG_PRE_CONSOLE_BUFFER)) {
		volatile struct sheng_blackbox *bb = SHENG_BLACKBOX;
		int nodeoff = fdt_path_offset(blob, "/chosen");

		if (nodeoff >= 0) {
			fdt_setprop(blob, nodeoff, "sheng,mdss-status",
				    (void *)(uintptr_t)bb->stage,
				    sizeof(bb->stage));
			fdt_setprop(blob, nodeoff, "sheng,uclass-get-device-ret",
				    (void *)(uintptr_t)&bb->uclass_get_device_ret,
				    sizeof(bb->uclass_get_device_ret));
			/* Log ring: a u32 count then up to SHENG_MDSS_LOG_MAX
			 * (tag, value) pairs. Only sheng_mdss_debug.c writes
			 * it, so without that build it is zeros. */
			if (IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS_DEBUG))
				fdt_setprop(blob, nodeoff, "sheng,mdss-log",
					    (void *)(uintptr_t)&bb->log,
					    sizeof(bb->log));
			/* Per-chip KTZ8866 status, [chip_a, chip_b], same
			 * convention as mdss-status. */
			fdt_setprop(blob, nodeoff, "sheng,ktz8866-status",
				    (void *)(uintptr_t)bb->ktz8866,
				    sizeof(bb->ktz8866));

			/* Boot timing, as a plain string. The same block is
			 * printed to the panel during probe, but that is
			 * the only place it goes -- serial is absent and
			 * the pre-console buffer is unreadable from Linux
			 * (no-map region, /dev/mem gives EFAULT). Here it
			 * lands in /proc/device-tree/chosen/sheng,boot-timing
			 * where a normal SSH session can cat it. */
			{
				char t[640];
				int n = sheng_mdss_timing_fmt(t, sizeof(t) - 32);

				if (n > 0) {
					n--; /* drop the NUL, append below */
					n += snprintf(t + n, sizeof(t) - n,
						      " abl=%lums relocdone=%lums"
						      " backlight=%lums"
						      " handover[bl=%x avdd=%x"
						      " avee=%x rst=%x"
						      " blregs=%08x/%d]",
						      sheng_uboot_entry_us / 1000,
						      sheng_board_init_us / 1000,
						      sheng_backlight_us / 1000,
						      sheng_handover_bl,
						      sheng_handover_avdd,
						      sheng_handover_avee,
						      sheng_handover_rst,
						      sheng_handover_blregs,
						      sheng_handover_blret);
					fdt_setprop(blob, nodeoff,
						    "sheng,boot-timing", t, n + 1);
				}

				/* Display signature, for classifying a
				 * glitched boot from data instead of by
				 * eye. Separate property so a boot that
				 * never reached the video probe still
				 * relays its timing. */
				n = sheng_mdss_diag_fmt(t, sizeof(t));
				if (n > 0)
					fdt_setprop(blob, nodeoff,
						    "sheng,display-diag", t, n);
			}

			/* XBL/ABL's log. Separate buffer: it is larger than
			 * the diag strings and unrelated to the display
			 * driver, so it must not be gated on it. */
			{
				static char xbl[SHENG_XBL_LOG_COPY + 1];
				int n = sheng_xbl_log_scrape(xbl, sizeof(xbl));

				if (n > 0)
					fdt_setprop(blob, nodeoff,
						    "sheng,xbl-log", xbl, n);

				/* PON register dump -- read-only, for the
				 * charger-boot investigation. */
				n = sheng_pon_dump(xbl, sizeof(xbl));
				if (n > 0)
					fdt_setprop(blob, nodeoff,
						    "sheng,pon", xbl, n);

				/* ABL's own log, if it lives in the ramdump
				 * region past our pre-console buffer. */
				n = sheng_log_tail(
					(const volatile u8 *)(uintptr_t)SHENG_ABL_LOG_ADDR,
					SHENG_ABL_LOG_SIZE, xbl, sizeof(xbl));
				if (n > 0)
					fdt_setprop(blob, nodeoff,
						    "sheng,abl-log", xbl, n);
			}
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
	/* Same clock as the driver's marks: microseconds since power-on,
	 * so these line up with the "sheng: probe ..." block. */
	unsigned long t_entry = timer_get_us();

	sheng_ktz8866_backlight_init();
	sheng_backlight_us = timer_get_us();
	/* Boot-timing chatter: useful while working on boot time, noise
	 * otherwise. log_debug() compiles out unless DEBUG is defined. */
	log_debug("sheng: backlight lit at %lu ms (%lu ms in late_init)\n",
	       sheng_backlight_us / 1000,
	       (sheng_backlight_us - t_entry) / 1000);

	/* CONFIG_VIDEO only BINDS video devices during early boot. Nothing
	 * in this board's flow probes one -- no splash, and CONSOLE_MUX /
	 * SYS_CONSOLE_IS_IN_ENV are both off. Force the probe so
	 * sheng_mdss_probe() actually runs. */
	if (IS_ENABLED(CONFIG_VIDEO)) {
		struct udevice *vdev = NULL;
		int vret;

		vret = uclass_get_device(UCLASS_VIDEO, 0, &vdev);
		/* Populated even when probe() is never entered, so "no video
		 * device bound" (-ENODEV) is distinguishable from "bound,
		 * probe failed". */
		sheng_breadcrumb_u32((unsigned long)(uintptr_t)
				     &SHENG_BLACKBOX->uclass_get_device_ret,
				     (u32)vret);
	}

	log_debug("sheng: late_init done at %lu ms\n", timer_get_us() / 1000);

	/* Last thing in late_init, deliberately: the display and console are
	 * up by now, so the countdown and its escape hatch are actually
	 * visible on the panel rather than announced to nobody. */
	sheng_charger_boot_poweroff();
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
	if (!IS_ENABLED(CONFIG_VIDEO_SHENG_MDSS))
		return;

	/* Two handovers, because we may not own the pipeline.
	 *
	 * Built it ourselves -> full teardown.
	 *
	 * Inherited ABL's live pipeline -> stop the INTF timing engines first,
	 * then the same full teardown. Both extremes fail on their own:
	 *   - no stop at all leaves MDSS streaming and Linux boots to a black
	 *     panel; drm/msm cannot adopt a running pipeline.
	 *   - teardown alone unclocks MDSS and then touches DPU registers,
	 *     which hangs the board mid-frame.
	 *
	 * Stopping the timing engine leaves clocks, power and configuration
	 * intact, which is what Linux's own bring-up expects to find.
	 */
	if (sheng_inherited)
		sheng_mdss_intf_stop(SHENG_DPU_BASE);

	sheng_mdss_teardown();
}
