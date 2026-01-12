# Bootloop Root Cause Analysis: Tiny Ramdisk

## Executive Summary

Device is experiencing bootloop after flashing custom `tiny_boot_a.img` / `tiny_boot_b.img`. Following systematic debugging methodology to identify root causes.

---

## Phase 1: Root Cause Investigation

### Current Ramdisk Structure

```
workspace/tiny_ramdisk/
├── dev/                    (empty directory)
├── init                    (1059624 bytes, from recovery)
├── init.rc                 (632 bytes, custom minimal config)
├── proc/                   (empty directory)
├── sbin/
│   ├── adbd               (755, 2236288 bytes)
│   ├── minadbd            (755, 245632 bytes)
│   ├── toybox             (755, 489632 bytes)
│   └── ueventd            (755, 1059624 bytes)
├── sys/                    (empty directory)
├── system/
│   ├── bin/
│   │   └── linker64       (1458280 bytes)
│   └── lib64/             (74 shared libraries from recovery)
└── ueventd.rc             (27977 bytes, from vendor)
```

### Key Evidence Gathered

1. **Init binary**: Recovery's init (1059624 bytes), requires `/system/bin/linker64`
2. **Shared libraries**: Complete lib64 tree copied from recovery (74 .so files)
3. **Init configuration**: Custom minimal init.rc (632 bytes)
4. **Missing from stock boot**:
   - `fstab.default` / `fstab.emmc` (stock boot has these)
   - Additional init scripts
   - SELinux policy files
   - Hardware-specific configuration

---

## Phase 2: Failure Hypotheses

### HYPOTHESIS 1: Missing fstab Files (CRITICAL OMISSION)
**Category**: Setup omission  
**Severity**: HIGH

**Evidence**:
- Stock boot ramdisk contains:
  - `fstab.default` (5302 bytes)
  - `fstab.emmc` (5178 bytes)
- Tiny ramdisk: **NO fstab files**

**Why This Causes Bootloop**:
```
fstab files define how Android mounts critical partitions:
- /system (read-only system partition)
- /vendor (vendor partition)
- /data (user data partition)
- /metadata (metadata partition)

Without fstab, init cannot:
1. Mount /system (contains Android framework)
2. Mount /vendor (contains hardware drivers)
3. Mount /data (user apps and data)
4. Set up encryption for userdata
```

**From stock fstab.default** (workspace/stock_boot_ramdisk_expanded/fstab.default):
```
system     /system      ext4    ro,barrier=1,discard    wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
vendor     /vendor      ext4    ro,barrier=1,discard    wait,slotselect,avb,logical,first_stage_mount
/dev/block/bootdevice/by-name/userdata  /data  f2fs  [encryption flags]  latemount,wait,check
```

**Expected Behavior**: Init reads fstab during `early-init` or `fs` stage to mount critical partitions.

**Actual Behavior**: Init cannot find fstab → partition mount fails → bootloop

---

### HYPOTHESIS 2: Missing SELinux Policy (CRITICAL OMISSION)
**Category**: Setup omission  
**Severity**: HIGH

**Evidence**:
- Stock recovery has SELinux contexts in system/
- Tiny ramdisk: No `/sepolicy` or `/system/etc/selinux/`
- init.rc sets `seclabel u:r:adbd:s0` for adbd service

**Why This Causes Bootloop**:
```
Android 11 enforces SELinux in enforcing mode by default.

Without sepolicy files:
1. Kernel enforces SELinux but has no policy loaded
2. All process creation denied (including init's children)
3. Init cannot start any services
4. System hangs/crashes
```

**SELinux Files Needed** (from recovery analysis):
- `/sepolicy` or `/system/etc/selinux/plat_sepolicy.cil`
- Compiled SELinux policy binary

**Current init.rc Issue**:
```rc
service adbd /sbin/adbd
    oneshot
    seclabel u:r:adbd:s0    # References SELinux context that doesn't exist!
```

**Expected Behavior**: SELinux policy loaded, contexts enforced  
**Actual Behavior**: SELinux denials → service start failures → bootloop

---

### HYPOTHESIS 3: Missing Toybox Symlinks (SETUP OMISSION)
**Category**: Setup omission  
**Severity**: MEDIUM-HIGH

**Evidence**:
- Stock recovery: `/system/bin/` has **200+ symlinks** to toybox (ls, cat, mount, mkdir, etc.)
- Tiny ramdisk: Only 4 binaries in `/sbin/`, **NO symlinks**
- init.rc has: `symlink /sbin/toybox /sbin/sh` (only creates `sh`)

**Why This Causes Bootloop**:
```
Init scripts and ueventd.rc may call utilities by name:
- mount (to mount filesystems)
- mkdir (to create directories)
- chmod (to set permissions)
- chown (to set ownership)

Without symlinks:
1. Commands fail with "command not found"
2. Init cannot execute basic filesystem operations
3. Boot sequence aborts
```

**From stock recovery** (workspace/stock_recovery_cpio_unpacked/system/bin/):
```
lrwxrwxrwx cat -> toybox
lrwxrwxrwx mount -> toybox
lrwxrwxrwx mkdir -> toybox
lrwxrwxrwx chmod -> toybox
lrwxrwxrwx chown -> toybox
... (200+ more)
```

**Current tiny ramdisk**:
```
Only: /sbin/sh -> /sbin/toybox
```

**Expected Behavior**: Commands resolved via symlinks to toybox  
**Actual Behavior**: "command not found" → script failures → bootloop

---

### HYPOTHESIS 4: Init Binary Expects Second-Stage Init (RECENT WORK ISSUE)
**Category**: Recent implementation issue  
**Severity**: HIGH

**Evidence**:
- Used **recovery's init** binary (1059624 bytes)
- Stock boot has **different init** (206672 bytes in Magisk-modified boot)
- Recovery init expects recovery environment, not boot environment

**From init strings analysis**:
```
Strings in stock boot init:
- "skip_initramfs"
- "/system/etc/init/hw"
- "/proc/cmdline"
- "/.backup/init"
- "/sbin/init-ld.xz"
```

**Why This Causes Bootloop**:
```
Recovery init is designed for recovery mode:
1. Expects /cache, /sdcard mount points
2. May try to start recovery-specific services
3. Different init stages (no first-stage mount in recovery)

Boot init is designed for normal boot:
1. Implements first-stage mount (mounts system before executing from /system)
2. Expects to chain to /system/bin/init for second-stage
3. Reads kernel cmdline for androidboot.* parameters
```

**Critical Difference**:
- Boot: **First-stage init in ramdisk** → **Second-stage init from /system**
- Recovery: **Single-stage init** (everything in ramdisk)

**Expected Behavior**: Init performs first-stage mount, execs /system/bin/init  
**Actual Behavior**: Recovery init doesn't understand first-stage mount → fails → bootloop

---

### HYPOTHESIS 5: Missing Kernel Cmdline Parameters (SETUP OMISSION)
**Category**: Boot image metadata issue  
**Severity**: MEDIUM

**Evidence**:
- Boot images have embedded kernel cmdline parameters
- Used `magiskboot repack` which may not preserve all cmdline args
- Stock boot AVB headers show: `com.android.build.boot.fingerprint`, `os_version`, `security_patch`

**Why This Causes Bootloop**:
```
Kernel cmdline parameters control critical boot behavior:
- androidboot.selinux=permissive (SELinux mode)
- androidboot.verifiedbootstate=orange (boot verification)
- androidboot.hardware=qcom (hardware platform)
- androidboot.bootdevice=<ufs-address> (storage device)

Missing parameters:
1. Init doesn't know hardware platform → can't load drivers
2. Init doesn't know boot device → can't mount partitions
3. SELinux mode unclear → enforcement failures
```

**Magiskboot Repack Concern**:
```bash
# Command used:
magiskboot repack ../stock_boot_a.img

# This preserves: kernel, dtb
# Uncertain: Does it preserve full cmdline from original?
```

**Expected Behavior**: Kernel cmdline properly passed to init  
**Actual Behavior**: Missing cmdline params → init configuration errors → bootloop

---

### HYPOTHESIS 6: Init.rc Missing Critical Mount Sequence (RECENT WORK ISSUE)
**Category**: Recent implementation issue  
**Severity**: HIGH

**Evidence**:
- Custom init.rc is **632 bytes** (minimal)
- Stock recovery init.recovery.qcom.rc has additional stages:
  - `on fs` (filesystem mounting)
  - `on property:ro.boot.usbcontroller=*` (USB setup)

**Current init.rc**:
```rc
on early-init
    mount proc proc /proc
    mount sysfs sysfs /sys
    mount tmpfs tmpfs /dev mode=0755
    mkdir /dev/pts 0755
    mount devpts devpts /dev/pts
    chmod 0755 /sbin
    symlink /sbin/toybox /sbin/sh
    write /proc/sys/kernel/printk "7 4 1 7"

on init
    setprop ro.secure 0
    setprop ro.adb.secure 0
    setprop sys.usb.config adb
    setprop service.adb.tcp.port 5555

on property:sys.usb.config=adb
    start adbd

service adbd /sbin/adbd
    oneshot
    seclabel u:r:adbd:s0
```

**What's Missing**:
1. **No `on fs` trigger** → Filesystem mounting never happens
2. **No symlink creation for /dev/block/bootdevice** → Cannot find storage
3. **No USB controller setup** → ADB over USB may fail
4. **No property service initialization** → Properties may not work

**From stock recovery init.recovery.qcom.rc**:
```rc
on fs
    wait /dev/block/platform/soc/${ro.boot.bootdevice}
    symlink /dev/block/platform/soc/${ro.boot.bootdevice} /dev/block/bootdevice
```

**Expected Behavior**: Init executes `on fs` stage, creates device symlinks  
**Actual Behavior**: No `on fs` stage → device nodes not created → mount failures → bootloop

---

### HYPOTHESIS 7: ueventd Not Started (RECENT WORK ISSUE)
**Category**: Recent implementation issue  
**Severity**: MEDIUM-HIGH

**Evidence**:
- `ueventd` binary present in /sbin (1059624 bytes)
- `ueventd.rc` present (27977 bytes, from vendor)
- **NO service definition for ueventd in init.rc**

**Why This Causes Bootloop**:
```
ueventd is responsible for:
1. Creating device nodes in /dev based on kernel uevents
2. Setting permissions on device nodes (from ueventd.rc)
3. Loading firmware files when kernel requests them

Without ueventd:
1. /dev remains empty (only tmpfs root)
2. No /dev/block/* devices created
3. No /dev/console, /dev/kmsg, /dev/null
4. Init cannot access devices → all operations fail
```

**How ueventd is normally started**:
```
Option 1: ueventd is a symlink to init (stock does this)
         - init sees argv[0] == "ueventd" and runs as ueventd
         
Option 2: init.rc starts ueventd as a service:
         service ueventd /sbin/ueventd
             critical
             seclabel u:r:ueventd:s0
```

**Current situation**:
- ueventd binary exists but is **separate binary**
- Stock recovery: `ueventd -> init` (symlink)
- Tiny ramdisk: `ueventd` (standalone binary, never started)

**Expected Behavior**: ueventd runs, populates /dev with device nodes  
**Actual Behavior**: ueventd never starts → /dev empty → bootloop

---

### HYPOTHESIS 8: Wrong Init Binary for Boot Mode (RECENT WORK ISSUE)
**Category**: Binary mismatch  
**Severity**: CRITICAL

**Evidence**:
- Currently using: **Recovery init** (workspace/stock_recovery_cpio_unpacked/system/bin/init)
- Should consider: **Boot init** (workspace/stock_boot_ramdisk_expanded/init)

**Size comparison**:
```
Recovery init: 1,059,624 bytes (from recovery ramdisk)
Boot init:       206,672 bytes (from stock boot, Magisk-modified)
```

**Why This Matters**:
```
Boot init and Recovery init have fundamentally different purposes:

BOOT INIT:
- Performs two-stage boot (ramdisk → /system)
- Implements first-stage mount for dynamic partitions
- Expects to exec /system/bin/init after mounting /system
- Parses androidboot.* cmdline parameters
- Sets up normal Android runtime

RECOVERY INIT:
- Single-stage boot (everything in ramdisk)
- Mounts /cache, /sdcard for recovery operations
- Starts recovery UI
- Does NOT expect /system to exist
- Different service set
```

**Critical Issue**:
Using recovery init for boot means:
1. Init doesn't perform first-stage mount
2. Init doesn't chain to /system/bin/init
3. Init tries to start recovery services (which don't exist)
4. Boot sequence fundamentally broken

**Expected Behavior**: Boot init performs first-stage mount, transitions to /system  
**Actual Behavior**: Recovery init doesn't understand boot flow → bootloop

---

### HYPOTHESIS 9: Missing /dev/null and Console Devices (SETUP OMISSION)
**Category**: Setup omission  
**Severity**: MEDIUM

**Evidence**:
- `/dev` directory exists but is empty
- init.rc mounts tmpfs on /dev but **doesn't create initial nodes**
- Many init operations require /dev/null, /dev/console

**Why This Causes Bootloop**:
```
Critical device nodes needed before ueventd runs:
- /dev/null (for redirecting unwanted output)
- /dev/console (for kernel console output)
- /dev/kmsg (for kernel message logging)

Without these:
1. Init's stdio redirects fail
2. Service startup fails (cannot redirect stderr/stdout)
3. Logging broken
4. Commands fail with "No such device"
```

**Standard early boot sequence**:
```rc
on early-init
    # Create initial devices before ueventd
    mknod /dev/null c 1 3 0666
    mknod /dev/console c 5 1
    mknod /dev/kmsg c 1 11 0600
```

**Current init.rc**:
```rc
on early-init
    mount tmpfs tmpfs /dev mode=0755
    # MISSING: mknod commands for initial devices!
```

**Expected Behavior**: Critical device nodes created early  
**Actual Behavior**: Missing device nodes → I/O failures → bootloop

---

## Phase 3: Hypothesis Prioritization

### CRITICAL (Must Fix for Boot):
1. **H1: Missing fstab files** → Cannot mount /system, /vendor, /data
2. **H4: Wrong init binary (recovery vs boot)** → Fundamental boot flow mismatch
3. **H8: Wrong init binary for boot mode** → (Duplicate of H4, same issue)

### HIGH Priority:
4. **H2: Missing SELinux policy** → Process creation denied
5. **H6: Init.rc missing mount sequence** → Device setup incomplete
6. **H7: ueventd not started** → Device nodes not created

### MEDIUM Priority:
7. **H3: Missing toybox symlinks** → Command resolution failures
8. **H5: Missing kernel cmdline parameters** → Configuration issues
9. **H9: Missing /dev/null and console** → I/O failures

---

## Phase 4: Recommended Investigation Steps

### Immediate Actions (Evidence Gathering):

1. **Extract kernel logs** (if possible):
   ```bash
   # Via EDL mode after bootloop:
   edl --loader sm6225.bin r logdump pstore.log
   
   # Check for kernel panic, init crashes:
   strings pstore.log | grep -i "init\|panic\|oops"
   ```

2. **Compare init binaries**:
   ```bash
   # Strings comparison:
   strings workspace/stock_boot_ramdisk_expanded/init > boot_init_strings.txt
   strings workspace/stock_recovery_cpio_unpacked/system/bin/init > recovery_init_strings.txt
   diff boot_init_strings.txt recovery_init_strings.txt
   ```

3. **Examine stock boot's init.rc** (currently don't have this):
   ```bash
   # Stock boot may have init.rc in different location
   find workspace/stock_boot_ramdisk_expanded -name "*.rc"
   ```

4. **Check AVB/vbmeta status**:
   ```bash
   # Verify boot image integrity:
   avbtool.py info_image --image workspace/tiny_boot_a.img
   
   # Compare hashes with stock:
   diff <(avbtool.py info_image --image workspace/stock_boot_a.img) \
        <(avbtool.py info_image --image workspace/tiny_boot_a.img)
   ```

---

## Summary of Root Causes

**The bootloop is likely caused by a combination of**:

1. **PRIMARY**: Using recovery init instead of boot init (wrong binary for boot mode)
2. **CRITICAL**: Missing fstab files (cannot mount partitions)
3. **CRITICAL**: Missing SELinux policy (process creation denied)
4. **HIGH**: Incomplete init.rc (missing filesystem mounting stage)
5. **HIGH**: ueventd not started (device nodes not created)
6. **MEDIUM**: Missing toybox symlinks (command resolution failures)

**Next Steps**: Prioritize fixing H4/H8 (correct init binary), H1 (fstab), H2 (SELinux policy).

---

## Questions for Further Investigation

1. Does the stock boot ramdisk have an init.rc? (We haven't found one yet in stock_boot_ramdisk_expanded)
2. What exactly does the Magisk-modified stock boot do? (overlay.d/ structure suggests init replacement)
3. Are there kernel logs available from the bootloop? (pstore/ramoops)
4. Should we use boot's init binary instead of recovery's init?
5. Can we boot with SELinux in permissive mode to bypass policy issues?

---

**Analysis completed**: 2026-01-11  
**Next phase**: Hypothesis testing and targeted fixes
