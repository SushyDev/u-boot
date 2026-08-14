{ pkgs, lib, config, ... }:

let
  cross = pkgs.pkgsCross.aarch64-multiplatform;
in
{
  env.ARCH = "arm64";
  env.CROSS_COMPILE = cross.stdenv.cc.targetPrefix;
  env.BUILD_DIR = ".output";
  env.DEFCONFIG = "sm8550_defconfig";
  # macOS's ld64 doesn't merge tentative C definitions across translation
  # units the way GNU ld / -fno-common expects; several U-Boot host tools
  # (tools/imagetool.h's __start_image_type/__stop_image_type fallback for
  # __MACH__) rely on old-style "common" symbol merging to build on a Mac.
  env.HOSTCFLAGS = "-fcommon";

  packages = [
    cross.stdenv.cc

    pkgs.gnumake
    pkgs.bison
    pkgs.flex
    pkgs.bc
    pkgs.openssl
    pkgs.ncurses
    pkgs.dtc
    pkgs.pkg-config
    pkgs.util-linux
    pkgs.gnutls
    pkgs.python3
    pkgs.swig

    pkgs.coreutils
    pkgs.findutils
    pkgs.gnused
    pkgs.gawk
    pkgs.gnugrep

    pkgs.android-tools
    pkgs.tio
    pkgs.usbutils
  ];

  tasks = {
    "uboot:build" = {
      description = "Build U-Boot for the Xiaomi Pad 6S Pro (sheng)";
      exec = ''
        set -e
        make O=$BUILD_DIR $DEFCONFIG
        make O=$BUILD_DIR -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
        echo ""
        echo "✓ Build artifacts:"
        ls -lh $BUILD_DIR/u-boot-nodtb.bin \
          $BUILD_DIR/dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dtb 2>/dev/null \
          || echo "Expected outputs not found -- check the build log above."
      '';
    };

    "uboot:menuconfig" = {
      description = "Interactively tweak the sm8550_defconfig";
      exec = "make O=$BUILD_DIR menuconfig";
    };

    "uboot:pack" = {
      description = "gzip u-boot-nodtb.bin, append the sheng dtb, and build boot.img";
      exec = ''
        set -e
        cd $BUILD_DIR
        gzip -kf u-boot-nodtb.bin
        cat u-boot-nodtb.bin.gz dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dtb \
          > u-boot-nodtb.bin.gz-dtb
        mkbootimg --kernel u-boot-nodtb.bin.gz-dtb \
          --output boot.img --pagesize 4096 \
          --base 0x0 --kernel_offset 0x00008000 --tags_offset 0x01e00000 \
          || echo "mkbootimg not on PATH -- get it from debian-sheng/ or AOSP mkbootimg."
        echo "✓ boot.img ready in $BUILD_DIR/"
      '';
    };

    "usb:watch" = {
      description = "Watch lsusb";
      exec = "while true; do clear; lsusb; sleep 0.1; done";
    };

    "serial:watch" = {
      description = "Watch USB g serial console (U-Boot ACM gadget)";
      exec = "tio -m INLCRNL -S unix:/tmp/nerves-socket /dev/cu.usbmodem*";
    };
  };
}
