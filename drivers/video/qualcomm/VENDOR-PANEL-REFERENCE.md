# Vendor panel reference (N81A / sheng), extracted from stock firmware

Ground truth for how Xiaomi's own stack brings this panel up. Everything
below is extracted, not inferred. Sources:

- `qcom,mdss_dsi_n81a_36_02_0a_duledsi_dsc_vid` — the Android DT panel
  node, from `dtbo.img` entry 47. Saved as `vendor-n81a-panel-node.dts`
  in the project root.
- `DisplayDxe`'s own panel XML, from `uefi.elf`. Saved as
  `abl-n81a-panel.xml`.
- See the `sheng-abl-firmware-extraction` note for how to unpack these.

`N81A` is sheng. The panel is dual-DSI split-link, so DT horizontal
values are PER LINK: `panel-width = 0x5f4` = 1524 = 3048/2.

## 1. There is NO per-command pacing

The decoded `qcom,mdss-dsi-on-command` blob is 95 commands, and **every
single one has wait=0 except sleep-out (0x11), which waits 120ms**:

    95 commands, waits: {0x11: 120ms}

Qualcomm's blob format is 7 header bytes per entry
(`type,last,vc,ack,wait,dlen_hi,dlen_lo`) followed by the payload, so the
wait is explicit per command and it is zero throughout.

**This driver paced at 500us-2000us per command** on the theory that the
DDIC needs settling time across the `0xff` page switches. The vendor
sends them back-to-back. The pacing was ~52ms of boot time defending
against something that does not exist.

## 2. Command tail differs from ours

Vendor commands 88-95, after the 87 shared entries:

    90 03
    91 89 28 00 10 d2 00 02 9d 01 b1 00 ...   (16 args)
    92 10 f0
    9d 01
    b2 91
    b3 40
    11          + 120ms
    29

Two differences worth investigating before trusting our version:

- **DSC**: vendor sends `0x91` with ~16 args plus `0x92 10 f0`. This
  driver instead emits a 128-byte PPS as a type-0x0a long write. Both
  reach a working panel, but they are not the same programming.
- **`b2`/`b3`**: vendor sends `b2 91` / `b3 40`. This driver was changed
  to send `0x00`/`0x00` based on reasoning about which framerate branch
  the kernel driver would take. The vendor's table for this panel uses
  `91`/`40`. That earlier "REAL BUG FOUND" conclusion may be wrong --
  though note the vendor node here is the 120Hz timing and we run 144Hz.

## 3. Framerate is changed by VFP ONLY

    qcom,dsi-supported-dfps-list = <120 144 90 60 50 48 30>
    qcom,mdss-dsi-pan-fps-update = "dfps_immediate_porch_mode_vfp"

All those rates share one init, one bit clock and one set of HORIZONTAL
timings; only the vertical front porch changes. So per-mode H porches are
not a thing on this panel.

Vendor 120Hz timing (per link):

    HFP 196   HBP 46   HSYNC 2      VFP 26   VBP 138   VSYNC 2
    clockrate 0x46ef5510 = 1190093072
    phy-timings [00 27 0a 0a 1b 25 0a 0b 0a 02 04 00 20 0f]

This driver uses HFP 142 / HSYNC 4 / HBP 92, which matches neither the
vendor's numbers nor its "H timings are constant" model.

## 4. Reset sequence

    qcom,mdss-dsi-reset-sequence = <0 10, 1 3, 0 3, 1 15>   (level, ms)

i.e. LOW 10ms, HIGH 3ms, LOW 3ms, HIGH 15ms. This driver uses
11/4/4/16 -- harmless, but there is no reason to differ.

    qcom,mdss-dsi-lp11-init;

**The panel wants the data lanes in LP11 during init.** Worth checking
this driver actually satisfies it.

## 5. Host configuration

    traffic-mode = "burst_mode"
    bllp-power-mode              (LP during BLLP)
    rx-eot-ignore / tx-eot-append
    panel-broadcast-mode + cmd-sync-wait-broadcast   (dual DSI, we do this)
    clk-strength = 0xff, phy-voltage = 0x51

## 6. ESD / liveness check expects 0x9D, not 0x9C

    qcom,mdss-dsi-panel-status-command = <0x06010000 0x0000010a>   (DCS read 0x0A)
    qcom,mdss-dsi-panel-status-value = <0x9d>
    qcom,mdss-dsi-panel-status-read-length = <1>

This driver treats `0x9c` as the healthy Get Power Mode value. The
vendor's own ESD check expects `0x9d`. Both have been observed; do not
treat `0x9c` as the only good value.

## 7. Backlight

    bl-pmic-control-type = "bl_ctrl_external"     (the KTZ8866 pair)
    bl-max-level = 0xfff (4095), bl-min-level = 2
    brightness-init-level = 0x133 (307)
    bl-update-flag = "delay_until_first_frame"

Note the init level is 307, not the 1500 this driver writes, and the
vendor deliberately delays the backlight until the first frame.

## What has NOT been changed on the strength of this

Only the pacing (section 1) has been acted on. The DSC tail, `b2`/`b3`,
the H timings and the 0x9d/0x9c question are all recorded here but left
alone: this driver currently reaches a working panel, and each of those
would need its own tested change rather than a batch rewrite.
