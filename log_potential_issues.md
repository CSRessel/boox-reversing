# Initramfs Bootloop Issues - Comprehensive List

## All Identified Issues

1. **Init Binary Not Executable**
   - **File**: `workspace/tiny_ramdisk/init`
   - **Current**: 664 (rw-rw-r--)
   - **Required**: 755 (rwxr-xr-x)
   - **Impact**: Kernel cannot execute init, immediate boot failure
   - **Fix**: `chmod 755 workspace/tiny_ramdisk/init`

2. **Wrong Init Binary - Recovery Instead of Boot**
   - **Current**: Using recovery init (1,059,624 bytes from `stock_recovery_cpio_unpacked/system/bin/init`)
   - **Required**: Boot init (206,672 bytes from `stock_boot_ramdisk_expanded/init`)
   - **Impact**: Recovery init expects single-stage boot for recovery environment, not two-stage boot flow. Won't perform first-stage mount of dynamic partitions, won't chain to `/system/bin/init`, tries to start recovery-specific services that don't exist
   - **Fix**: `cp workspace/stock_boot_ramdisk_expanded/init workspace/tiny_ramdisk/init && chmod 755 workspace/tiny_ramdisk/init`

3. **Missing fstab.default**
   - **File**: `fstab.default`
   - **Current**: Does not exist in ramdisk
   - **Required**: Copy from `workspace/stock_boot_ramdisk_expanded/fstab.default` (5,302 bytes)
   - **Impact**: Init cannot mount /system, /vendor, /product partitions. Defines critical mount points with AVB verification, slot selection, and first-stage mount flags. Without it, partition mounting fails completely
   - **Fix**: `cp workspace/stock_boot_ramdisk_expanded/fstab.default workspace/tiny_ramdisk/`

4. **Missing fstab.emmc**
   - **File**: `fstab.emmc`
   - **Current**: Does not exist in ramdisk
   - **Required**: Copy from `workspace/stock_boot_ramdisk_expanded/fstab.emmc` (5,178 bytes)
   - **Impact**: Alternative fstab for eMMC storage devices (vs UFS). System cannot determine storage device type or mount partitions on eMMC hardware
   - **Fix**: `cp workspace/stock_boot_ramdisk_expanded/fstab.emmc workspace/tiny_ramdisk/`

5. **Missing SELinux Policy Files**
   - **Files**: `/sepolicy`, `/system/etc/selinux/plat_sepolicy.cil`, or compiled policy binaries
   - **Current**: No SELinux policy present anywhere in ramdisk
   - **Impact**: Android 11 enforces SELinux by default. Without policy loaded, all process creation denied. Init.rc sets `seclabel u:r:adbd:s0` but context doesn't exist. Services cannot start, system hangs or crashes
   - **Fix**: Either extract sepolicy from stock boot/recovery, or add kernel cmdline parameter `androidboot.selinux=permissive` (requires boot image rebuild)

6. **Missing "on fs" Stage in init.rc**
   - **File**: `workspace/tiny_ramdisk/init.rc`
   - **Current**: Has `on early-init` and `on init` but no `on fs`
   - **Required**: Add filesystem mounting trigger stage
   - **Impact**: Device symlinks never created (`/dev/block/bootdevice` → actual storage device), storage devices inaccessible, filesystem mounting doesn't trigger
   - **Fix**: Add to init.rc:
     ```rc
     on fs
         wait /dev/block/platform/soc/${ro.boot.bootdevice}
         symlink /dev/block/platform/soc/${ro.boot.bootdevice} /dev/block/bootdevice
     ```

7. **ueventd Service Not Started**
   - **Binary**: `/sbin/ueventd` (1,059,624 bytes, present but never executed)
   - **Config**: `ueventd.rc` (27,977 bytes, present but unused)
   - **Current**: No service definition for ueventd in init.rc
   - **Impact**: ueventd creates device nodes in /dev based on kernel uevents, sets device permissions, loads firmware. Without it: /dev remains mostly empty, no /dev/block/* devices, no /dev/console, /dev/null, init cannot access devices
   - **Fix Option A**: Add to init.rc:
     ```rc
     service ueventd /sbin/ueventd
         critical
         seclabel u:r:ueventd:s0
     ```
   - **Fix Option B**: Replace ueventd binary with symlink to init: `ln -sf init workspace/tiny_ramdisk/sbin/ueventd` (stock approach)

8. **Missing Toybox Command Symlinks**
   - **Location**: Should be in `/sbin/` or `/system/bin/`
   - **Current**: Only `/sbin/sh -> toybox` symlink exists (created by init.rc)
   - **Stock Recovery Has**: 200+ symlinks (ls, cat, mount, mkdir, chmod, chown, rm, cp, mv, ps, kill, grep, find, etc.)
   - **Impact**: Commands called by init scripts or ueventd fail with "command not found". Basic filesystem operations fail. Shell scripts cannot execute
   - **Fix**: Create essential symlinks:
     ```bash
     cd workspace/tiny_ramdisk/sbin
     for cmd in ls cat mount mkdir chmod chown rm cp mv ln ps kill grep find; do
         ln -s toybox $cmd
     done
     ```

9. **Missing Initial Critical Device Nodes**
   - **Devices**: `/dev/null`, `/dev/console`, `/dev/kmsg`
   - **Current**: /dev is empty tmpfs after mount
   - **Impact**: Init I/O operations fail (cannot redirect to /dev/null), kernel console output fails, logging broken, services cannot start due to missing stdio devices
   - **Fix**: Add to init.rc `on early-init` section (before other operations):
     ```rc
     mknod /dev/null c 1 3 0666
     mknod /dev/console c 5 1
     mknod /dev/kmsg c 1 11 0600
     ```

10. **Missing USB Controller Property Trigger**
    - **File**: `workspace/tiny_ramdisk/init.rc`
    - **Current**: Sets `sys.usb.config=adb` statically
    - **Required**: Property-based USB controller initialization from kernel cmdline
    - **Impact**: USB ADB may not initialize correctly, USB peripheral mode may not activate, ro.boot.usbcontroller property not propagated
    - **Fix**: Add to init.rc:
      ```rc
      on property:ro.boot.usbcontroller=*
          setprop sys.usb.controller ${ro.boot.usbcontroller}
          write /sys/class/udc/${ro.boot.usbcontroller}/device/../mode peripheral
      ```

11. **Potential Kernel Cmdline Parameter Loss**
    - **Concern**: `magiskboot repack` may not preserve all androidboot.* kernel cmdline parameters
    - **Critical Parameters**: `androidboot.selinux`, `androidboot.hardware=qcom`, `androidboot.bootdevice=<ufs-address>`, `androidboot.verifiedbootstate`
    - **Impact**: Init doesn't know hardware platform or boot device path, cannot find storage controller, SELinux mode unclear
    - **Verification Needed**: Extract and compare cmdline from stock vs repacked boot images
    - **Fix**: Ensure magiskboot preserves cmdline, or manually specify in repack

12. **Missing /sbin Directory Creation**
    - **File**: `workspace/tiny_ramdisk/init.rc`
    - **Current**: `chmod 0755 /sbin` without ensuring directory exists first
    - **Impact**: If /sbin doesn't exist when chmod runs, command fails silently or errors
    - **Fix**: Add before `chmod 0755 /sbin`:
      ```rc
      mkdir /sbin 0755
      ```
    - **Note**: Directory likely already exists in ramdisk cpio, but init.rc should be defensive

13. **Incomplete Toybox Symlink in init.rc**
    - **File**: `workspace/tiny_ramdisk/init.rc`
    - **Current**: Only creates `/sbin/sh -> /sbin/toybox`
    - **Impact**: Shell works but no other commands available via PATH. Scripts using absolute paths to /bin/* or /usr/bin/* fail
    - **Fix**: While symlink is correct, need additional symlinks (see issue #8). Consider adding mkdir commands for standard directories:
      ```rc
      mkdir /bin 0755
      symlink /sbin/toybox /bin/sh
      ```

14. **Missing Standard Directory Structure**
    - **Directories**: `/bin`, `/tmp`, `/mnt`, `/cache`
    - **Current**: Only `/dev`, `/proc`, `/sys`, `/sbin`, `/system` exist
    - **Impact**: Scripts or binaries expecting standard FHS paths fail. Temporary file operations fail. Mount points for debugging missing
    - **Fix**: Add to init.rc `on early-init`:
      ```rc
      mkdir /tmp 01777
      mkdir /mnt 0755
      mkdir /bin 0755
      ```

15. **No Console or Logging Output Configured**
    - **Current**: `write /proc/sys/kernel/printk "7 4 1 7"` sets kernel log level but no console device
    - **Impact**: Cannot see boot messages, cannot debug boot failures, no visibility into what's failing
    - **Fix**: After creating /dev/console (issue #9), add to init.rc:
      ```rc
      write /sys/class/tty/console/active ttyMSM0
      ```
    - **Alternative**: Add kernel cmdline parameter `console=ttyMSM0,115200n8` for serial console

16. **Missing Init Second-Stage Transition**
    - **Context**: Boot init typically performs two-stage boot
    - **Current**: Using recovery init (single-stage) or boot init without proper transition setup
    - **Impact**: First-stage mount completes but doesn't exec `/system/bin/init` for second-stage. Boot hangs after ramdisk init completes
    - **Fix**: If using proper boot init, ensure init.rc doesn't block second-stage transition. May need to verify stock boot's init behavior (Magisk modification complicates this)

17. **SELinux Context Mismatch in Service Definition**
    - **File**: `workspace/tiny_ramdisk/init.rc`
    - **Current**: `service adbd /sbin/adbd` with `seclabel u:r:adbd:s0`
    - **Impact**: Without SELinux policy defining u:r:adbd:s0 context, service fails to start with SELinux denial
    - **Fix**: Either load proper SELinux policy (issue #5) or remove seclabel line and run in kernel domain (insecure but works for debugging)

18. **adbd Service Set to "oneshot" Mode**
    - **File**: `workspace/tiny_ramdisk/init.rc`
    - **Current**: `service adbd /sbin/adbd` with `oneshot` flag
    - **Impact**: adbd runs once and exits. If it crashes or exits, won't restart. For debugging/recovery, should be persistent
    - **Fix**: Change to:
      ```rc
      service adbd /sbin/adbd
          disabled
          seclabel u:r:adbd:s0
      ```
      Then start with property trigger (already present: `on property:sys.usb.config=adb`)

19. **No Property Service Trigger for Init**
    - **Context**: Property service must be running for `on property:` triggers to work
    - **Current**: init.rc uses property triggers but doesn't explicitly start property service
    - **Impact**: Property triggers may not fire, services may not start, `setprop` commands may fail silently
    - **Fix**: Property service is typically built into init binary (verify with strings). If not, cannot use property-based triggers. Modern Android init always includes property service

20. **Missing Kernel Module Loading Support**
    - **Files**: No `/lib/modules/` directory or module loading in init.rc
    - **Current**: No kernel module support configured
    - **Impact**: If device requires kernel modules for storage, USB, or other hardware, they won't load. Device may not be accessible
    - **Fix**: If needed, add to init.rc:
      ```rc
      on boot
          insmod /lib/modules/module_name.ko
      ```
    - **Note**: May not be needed if all drivers built into kernel

21. **Stock Boot May Use Different Init Mechanism**
    - **Evidence**: Stock boot has `overlay.d/sbin/` with Magisk files (init-ld.xz, magisk.xz, stub.xz)
    - **Current**: Magisk modifies init process with overlay mechanism, unclear what stock unmodified boot does
    - **Impact**: May be replicating Magisk-modified boot instead of clean stock boot. Init behavior unclear
    - **Investigation Needed**: Obtain truly stock (unmodified) boot image to compare, or understand Magisk's init replacement mechanism

22. **Recovery Binary Size Suggests Different Compilation**
    - **Evidence**: Recovery init is 1,059,624 bytes (same as ueventd binary size)
    - **Current**: Both init and ueventd are identical size, suggesting they may be the same binary (multi-call binary)
    - **Impact**: If ueventd is actually a symlink or hardlink to init in stock recovery, running separate ueventd binary may fail or behave unexpectedly
    - **Fix**: Verify with: `cmp workspace/tiny_ramdisk/init workspace/tiny_ramdisk/sbin/ueventd` - if identical, make ueventd a symlink to init

23. **No /system Partition Pre-mount for Shared Libraries**
    - **Context**: Binaries require `/system/lib64/*.so` via dynamic linker
    - **Current**: Shared libraries copied to ramdisk `/system/lib64/`, but /system partition not mounted
    - **Impact**: If init or early services try to access /system partition before it's mounted, they fail. If shared libraries aren't in ramdisk but referenced from partition, missing dependencies
    - **Fix**: Libraries already in ramdisk (issue mitigated), but verify no references to /system partition paths exist in binaries

24. **Missing /system/bin Symlinks for Standard Commands**
    - **Location**: `/system/bin/` only contains linker64
    - **Stock Recovery**: Has 200+ binaries and symlinks in `/system/bin/`
    - **Impact**: Services or scripts calling `/system/bin/command` fail. Standard Android paths not available
    - **Fix**: Add symlinks in /system/bin:
      ```bash
      cd workspace/tiny_ramdisk/system/bin
      for cmd in sh ls cat mount; do
          ln -s ../../sbin/toybox $cmd
      done
      ```

---

## Priority Matrix

**CRITICAL (Boot Impossible)**:
- Issue #1: Init not executable
- Issue #2: Wrong init binary (recovery vs boot)
- Issue #3: Missing fstab.default
- Issue #4: Missing fstab.emmc
- Issue #5: Missing SELinux policy

**HIGH (Boot Fails Early)**:
- Issue #6: Missing "on fs" stage
- Issue #7: ueventd not started
- Issue #8: Missing toybox symlinks
- Issue #9: Missing /dev/null, /dev/console

**MEDIUM (Boot May Progress Further)**:
- Issue #10: USB controller trigger
- Issue #11: Kernel cmdline parameters
- Issue #17: SELinux context mismatch
- Issue #22: Init/ueventd binary relationship

**LOW (Functionality Issues)**:
- Issue #12: /sbin directory creation
- Issue #13: Incomplete symlinks
- Issue #14: Missing directories
- Issue #15: Console logging
- Issue #18: adbd oneshot mode
- Issue #24: /system/bin symlinks

**INVESTIGATION NEEDED**:
- Issue #16: Second-stage transition
- Issue #19: Property service
- Issue #20: Kernel modules
- Issue #21: Stock vs Magisk init
- Issue #23: /system partition dependencies

---

## Recommended Fix Order

1. Fix init permissions (1s): `chmod 755 workspace/tiny_ramdisk/init`
2. Create critical device nodes (30s): Add mknod commands to init.rc
3. Replace init binary (1m): Copy boot init instead of recovery init
4. Add fstab files (1m): Copy both fstab files to ramdisk
5. Add "on fs" stage (2m): Add filesystem mount trigger to init.rc
6. Start ueventd (2m): Add service definition or create symlink
7. Create toybox symlinks (3m): Essential command symlinks
8. Fix SELinux (varies): Add policy or use permissive mode
9. Test boot, gather logs, iterate

**Estimated time to first successful boot**: 15-30 minutes

---

*Analysis Date: 2026-01-11*  
*Ramdisk Version: tiny_ramdisk (commit 25eb416)*  
*Total Issues Identified: 24*
