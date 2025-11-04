# Minimal Ramdisk Procedure

This folder holds a stripped-down ramdisk carved out of the stock `workspace/stock_boot_a.img`.  
Follow the steps below to regenerate it from scratch.

## Prerequisites
- The Magisk tooling already checked in at `scripts/magisk/magiskboot`.
- `workspace/stock_boot_a.img` copied from the device (see `recent.log` notes on using `magiskboot unpack`).
- Standard POSIX utilities (`mkdir`, `cpio`, `find`, `cp`) available in your shell.

## 1. Unpack the stock boot image
The `magiskboot unpack` invocation in `recent.log` is what produces `ramdisk.cpio`, `kernel`, and `dtb`.

```sh
mkdir -p workspace/unpack
(cd workspace/unpack && ../../scripts/magisk/magiskboot unpack ../stock_boot_a.img)
```

That command leaves the decompressed ramdisk archive at `workspace/unpack/ramdisk.cpio`.

## 2. Expand the stock ramdisk tree
Populate `workspace/stock_ramdisk` so you can copy the handful of files the tiny ramdisk needs.

```sh
mkdir -p workspace/stock_ramdisk
(cd workspace/stock_ramdisk && cpio -id < ../unpack/ramdisk.cpio)
```

After this step, `workspace/stock_ramdisk/init` is the original init binary from the OEM image.

## 3. Assemble the minimal ramdisk
Create the skeletal directory layout and copy over only the required artifacts.

```sh
mkdir -p workspace/tiny_ramdisk/{dev,proc,sys,sbin}
cp workspace/stock_ramdisk/init workspace/tiny_ramdisk/init
: > workspace/tiny_ramdisk/init.rc
```

- `init` is the unmodified binary from the stock ramdisk (`cmp` shows it matches bit-for-bit).  
- `init.rc` is intentionally blank; any additional services or mounts can be layered in later.  
- Empty `dev`, `proc`, `sys`, and `sbin` directories placate the init binary’s early boot expectations.

## 4. (Optional) Repack for flashing
If you need a cpio archive to repack or flash:

```sh
(cd workspace/tiny_ramdisk && find . -print0 | sort -z | cpio --null -o -H newc --owner=0:0) > workspace/tiny_ramdisk.cpio
```

You can then drop `workspace/tiny_ramdisk.cpio` back into `magiskboot repack` alongside the preserved `kernel`/`dtb` if you want to build a boot image that uses this minimal ramdisk.

