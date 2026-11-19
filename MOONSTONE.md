# moonstone (POCO X5 5G, Snapdragon 695 / SM6375) bring-up notes

Derived from ios-sweet (SM7150) with the packaging approach of ios-topaz.
**Status: nothing here has been built or booted yet.** The values come from the
phone's own live device tree (`moonstone.dts`). Expect to iterate.

## What was changed relative to ios-sweet

| File | Change |
|---|---|
| `shim/loader.c` | topaz's loader: finds the XNU payload appended to the shim's own kernel Image (falls back to the ramdisk). |
| `shim/build.sh` | Builds a **boot image v3** (the phone's stock layout) with the payload appended to the Image. No `--dtb`, no offsets: the DTB comes from `vendor_boot`. Output is meant to be **flashed to `boot_b`**, there is no `fastboot boot` on this bootloader. |
| `shim/console.h`, `shim/mmu.h` | Framebuffer `0x85200000` (cont_splash_region, 0xc00000), 1080x2400. |
| `shim/shim.c` | GICD `0xf200000`, GICR `0xf240000`; PSHOLD `0x440b000`; imem restart_reason `0xc12565c`. |
| `shim/ufs.c` | UFS host `0x4804000`. |
| `tools/mkadt.py` | RAM = upper bank `0x100000000` size `0xf0000000`; GIC / FB / UFS as above; CPU names and clocks. `qcom,kryo470` is kept first in the CPU `compatible` list because patch 0018 binds on it. |

The XNU kernel patches are **unchanged**. Framebuffer console, GIC, timer and the
UFS root are all described by the ADT, so the stock sweet kernel build is
the right kernel for the first milestones.

## Hardware that still needs real work (not done)

* **Touch**: moonstone has a FocalTech controller (`focaltech,fts`, I2C 0x38 on
  GENI I2C `0x4c88000`, reset GPIO 21, irq GPIO 22, avdd GPIO 49). sweet's patches
  0060/0062/0063 drive a Goodix. ios-topaz has a FocalTech FT5452 driver (its
  patches 0083/0087) that is the likely starting point.
* **Buttons**: SPMI `0x1c40000`; volume-up is GPIO 1 of the PMIC at SID 4;
  power / volume-down via the PON block. Addresses differ from sweet's.
* **USB** (patches 0072+): sweet's USB base `0x0a600000` is wrong for this SoC
  (moonstone's DWC3 is at `0x4e00000`). It MUST stay disabled (`sweetusb=0`).

## First-boot boot-args

These keep every sweet-specific hardware driver off so only the generic parts run:

```
debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress
rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin
ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30
sweetusb=0 sweettouch=0 sweetkeys=0
```

(`sweetfb_noconsole=1` is left out on purpose so the kernel log stays on screen.)

## Build (WSL2 Ubuntu or any Linux; paths shown for WSL)

```
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3 cpio gzip \
     android-tools-mkbootimg gcc
cd /mnt/d/m/ios-sweet

# 1. kernel: run the repo's CI on your own GitHub fork (needs macOS runners), download
#    the artifact to xnu/out/  -> xnu/out/kernel.development.sweet

# 2. device tree + payload (the /product node of the iPhone X tree is optional
#    for the first milestone; mkadt only warns if research/ipsw-x/d22ap.adt is missing)
python3 tools/mkadt.py shim/out/moonstone.adt
python3 tools/mkpayload.py xnu/out/kernel.development.sweet shim/out/moonstone.adt shim/out/payload.bin \
  --cmdline 'debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 sweetusb=0 sweettouch=0 sweetkeys=0'

# 3. shim boot image (v3)
cd shim && ./build.sh ../shim/out/payload.bin      # -> shim/out/shim-boot.img
```

## Flash to slot B only, never slot A

```
fastboot getvar current-slot                       # should say a
fastboot flash vendor_boot_b D:\m\backup\vendor_boot_a.img
fastboot flash dtbo_b        D:\m\backup\dtbo_a.img
fastboot flash vbmeta_b      D:\m\backup\vbmeta_a.img --disable-verity --disable-verification
fastboot flash boot_b        ios-sweet\shim\out\shim-boot.img
fastboot set_active b
fastboot reboot
```

## Back to Android (slot A is untouched)

Hold Volume Down + Power to reach fastboot, then:

```
fastboot set_active a
fastboot reboot
```

If slot A itself ever needs restoring: `fastboot flash boot_a D:\m\backup\boot_a.img`
(and `vendor_boot_a`, `dtbo_a`, `vbmeta_a`). Do not flash any other partition.

## What a good first result looks like

1. Coloured shim text lines on the splash framebuffer (EMBED, PHYS, SEGS, JUMP...).
2. Then the XNU kernel log. It will panic or stall at the root device (no iOS root
   in `userdata` yet); that is expected at this stage. Photograph the last screen.
