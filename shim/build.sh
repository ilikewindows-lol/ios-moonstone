#!/bin/bash
# moonstone (POCO X5 5G, SM6375): build the shim and wrap it in a boot.img v3.
#
# The phone's bootloader has no `fastboot boot`, and its stock boot image is a
# v3 image (the DTB and vendor ramdisk live in vendor_boot, not in boot). So:
#   - the shim is packed as boot v3 (no DTB in the image);
#   - the XNU payload is appended to the shim's own kernel Image (loader.c
#     looks for it at the first 4K boundary after _end), because a v3 boot
#     ramdisk may be dropped or replaced by vendor_boot's;
#   - the result is FLASHED to the inactive slot (boot_b), never boot_a.
# Based on ios-sweet/shim/build.sh and ios-topaz/shim/build.sh.
set -euo pipefail
cd "$(dirname "$0")"
CC=aarch64-linux-gnu-gcc
OBJCOPY=aarch64-linux-gnu-objcopy
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
mkdir -p out
for f in start.S shim.c console.c mmu.c fdt.c loader.c ufs.c; do
	$CC $CFLAGS -c $f -o out/${f%.*}.o
done
# The image runs wherever ABL puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$(aarch64-linux-gnu-readelf -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	out/start.o out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o -o out/shim.elf
$OBJCOPY -O binary out/shim.elf out/Image
# ABL copies the file; pad to image_size so .bss/stacks exist as zeroed bytes.
size=$((16#$(aarch64-linux-gnu-nm out/shim.elf | awk '$3=="_end"{print $1}')))
truncate -s "$size" out/Image
# Ramdisk: ABL dislikes a zero-size ramdisk on some builds, so always give it
# an empty newc cpio. The real payload (tools/mkpayload.py, $1) rides in the Image.
if [ -n "${1:-}" ]; then
	# Append the payload at the first 4K boundary after _end (loader.c) and
	# grow image_size (u64 at offset 16 of the arm64 Image header).
	truncate -s $(( (size + 0xfff) & ~0xfff )) out/Image
	cat "$1" >> out/Image
	python3 -c 'import os,struct,sys; f=open(sys.argv[1],"r+b"); f.seek(16); f.write(struct.pack("<Q", os.path.getsize(sys.argv[1])))' out/Image
fi
(cd out && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
# Header v3 has no dtb, tags or offsets: the bootloader takes those from vendor_boot.
${MKBOOTIMG:-mkbootimg} --header_version 3 --kernel out/Image --ramdisk out/ramdisk.bin \
	--os_version 13.0.0 --os_patch_level 2025-01 \
	--cmdline "console=null" -o out/shim-boot.img
# Host render of the console layout.
gcc -O1 -Wall -o out/host_test console.c host_test.c && ./out/host_test
ls -l out/Image out/shim-boot.img
