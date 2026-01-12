# Part 2: Initial Ramdisk Development

## Overview

This document chronicles the development of a custom minimal ramdisk for a Boox e-reader device, from initial partition analysis through successful boot image creation with proper ELF linking dependencies.

**Timeline**: October 23-24, 2025 (Setup & Analysis) → November 3-4, 2025 (Development & Testing)

**Goal**: Create a minimal bootable ramdisk with ADB access for further reverse engineering work.

---

## Session 1: October 23, 2025 - Foundation & Partition Analysis

### Phase 1: Environment Setup (02:54 - 04:30)

**Objective**: Set up legacy tooling for Android Verified Boot analysis

```bash
# Install Python 2 environment (required for legacy avbtool)
sudo apt install python2
curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py
sudo python2 get-pip.py
sudo pip2 install pycryptodome

# Clone AVB tooling
gh repo clone jcrutchvt10/AVBTOOL
cd AVBTOOL
./avbtool --help  # Verify installation
```

**Key Decision**: Maintained Python 2 alongside Python 3.12 (later needed for Magisk) rather than attempting to modernize avbtool.

### Phase 2: Partition Analysis (20:58) → Commit `8fffffc`

**Examined vbmeta partitions** to understand Android Verified Boot chain of trust:

```bash
./AVBTOOL/avbtool info_image --image partition-dumps/lun4/vbmeta_a.bin
./AVBTOOL/avbtool info_image --image partition-dumps/lun4/vbmeta_b.bin
./AVBTOOL/avbtool info_image --image partition-dumps/lun0/vbmeta_system_a.bin
./AVBTOOL/avbtool info_image --image partition-dumps/lun0/vbmeta_system_b.bin
```

**Findings**:
- Device uses A/B slot partitioning for atomic updates
- Multiple vbmeta partitions: `vbmeta_a/b` (boot chain), `vbmeta_system_a/b` (system partition verification)
- Created `vbmeta_info/` directory with extracted metadata

### Phase 3: Automated Analysis (22:36) → Commit `bc20375`

**Added more image info** via automated extraction:

```bash
# Batch analyze all partition dumps
find partition-dumps/ -type f -exec sh -c \
  'OUTPUT=$(./AVBTOOL/avbtool info_image --image "$1"); 
   [ -n "$OUTPUT" ] && FILENAME=$(basename "$1") && 
   echo "$OUTPUT" > "info_image/$FILENAME.txt"' _ {} \;

git add info_image/
```

**Result**: Complete AVB metadata catalog for all 50+ partitions

### Phase 4: Tool Organization (22:55 - 23:22) → Commits `4dcefd4`, `37f1302`

**Added required tools** and created partition manifest:

```bash
# Create manifest script
touch scripts/make-manifest.sh
chmod +x scripts/make-manifest.sh

# Generate TSV catalog
./scripts/make-manifest.sh > partition-manifest.tsv

# Archive partition dumps (not version controlled)
tar -I 'zstd -19 --long=31' -cf partition-dumps.tar.zst partition-dumps
# Result: 2.8GB compressed archive

# Move tools out of repo
mv AVBTOOL ../
mv scripts/avbtool.py scripts/  # Keep wrapper script
```

**Consolidated structure**:
- `scripts/avbtool.py` - AVB analysis wrapper
- `scripts/decryptBooxUpdate*.py` - OTA decryption tools
- `partition-manifest.tsv` - Complete partition catalog
- `info_image/` - AVB metadata for all partitions

---

## Session 2: October 24, 2025 - Magisk Build System

### Phase 5: Magisk Compilation (12:00 - 14:13) → Commit `b2a0e0f`

**Added magiskboot and other tools** from source:

```bash
# Clone Magisk with submodules
git clone --recurse-submodules https://github.com/topjohnwu/Magisk.git
cd Magisk

# Set up Python 3.12 environment
uv venv -p 3.12
source .venv/bin/activate

# Verify Android SDK
echo $ANDROID_HOME  # ~/Android/Sdk
ls ~/Android/Sdk/ndk

# Build native tools
./build.py all

# Copy x86_64 binaries
mkdir ../boox-reversing/scripts/magisk
cp native/out/x86_64/* ../boox-reversing/scripts/magisk/
```

**Tools obtained**:
- `magiskboot` - Boot image unpacker/repacker
- `magiskinit` - Custom init replacement
- `magiskpolicy` - SELinux policy manipulation
- `resetprop` - Property modification

**Gitignore strategy**:
```bash
echo "scripts/magisk/" >> .gitignore  # Binaries not tracked
```

**Rationale**: Magisk tools are large (50MB+) and reproducibly built. Repository tracks build process, not binaries.

---

## Session 3: November 3, 2025 - Custom Ramdisk Development

### Phase 6: Initial Ramdisk Skeleton (21:21) → Commit `2223f21`

**Setup tiny ramdisk layout**:

```bash
# Create workspace
mkdir workspace && cd workspace

# Extract stock boot image
cp ../partition-dumps/lun4/boot_a.bin stock_boot_a.img
cp ../partition-dumps/lun4/vbmeta_a.bin stock_vbmeta_a.img

# Unpack boot image
export PATH="$PATH:$(pwd)/../scripts/magisk"
magiskboot unpack stock_boot_a.img

# Result: dtb, kernel, ramdisk.cpio extracted
mkdir unpack
mv {dtb,kernel,ramdisk.cpio} unpack/

# Unpack stock ramdisk for reference
mkdir stock_ramdisk && cd stock_ramdisk
cpio -idmv < ../unpack/ramdisk.cpio
```

**Stock ramdisk structure observed**:
```
.backup/          # Backup files (restricted permissions)
avb/              # AVB verification data
debug_ramdisk/    # Debug filesystem
dev/              # Device nodes (empty, populated at boot)
mnt/              # Mount points
overlay.d/        # Init overlays
proc/             # Process filesystem (empty)
sys/              # Sysfs (empty)
system/           # System partition link
init*             # Main init binary
init.rc           # Init configuration
```

**Created minimal ramdisk**:
```bash
mkdir tiny_ramdisk
cd tiny_ramdisk
mkdir {dev,proc,sys,sbin}
touch init init.rc
```

### Phase 7: Binary Extraction from Device (21:21 - 21:40) → Commit `d9dd780`

**Extract key binaries from stock** system:

```bash
# Device was rooted with ADB access
adb devices
adb root

# Extract toybox (busybox-like multi-call binary)
adb shell su -c 'cp /system/bin/toybox /data/local/tmp/ && chmod 0644 /data/local/tmp/toybox'
adb pull /data/local/tmp/toybox workspace/stock_bin/

# Extract adbd (ADB daemon) from APEX module
adb shell 'su -c ls -l /apex/com.android.adbd/bin'
adb shell su -c 'cp /apex/com.android.adbd/bin/adbd /data/local/tmp/ && chmod 0644 /data/local/tmp/adbd'
adb pull /data/local/tmp/adbd workspace/stock_bin/

# Copy to ramdisk
cp stock_bin/* tiny_ramdisk/sbin/
```

**Binary analysis**:
```bash
file stock_bin/toybox
# toybox: ELF 64-bit LSB shared object, ARM aarch64

file stock_bin/adbd  
# adbd: ELF 64-bit LSB shared object, ARM aarch64
```

**Workspace gitignore**:
```bash
cat > workspace/.gitignore << EOF
stock_ramdisk
stock_boot_a.img
stock_vbmeta_a.img
**/*.img
**/kernel
EOF
```

**Rationale**: Stock images contain device-specific data (potential privacy concerns) and are large (100MB+).

### Phase 8: Configuration Files (22:21 - 22:31) → Commits `1acc1e9`, `4ce4c47`

**Extract ueventd.rc from device**:
```bash
# ueventd manages device nodes in /dev
adb shell ls -lh /vendor/ueventd.rc
adb shell su -c 'cp /vendor/ueventd.rc /data/local/tmp/ && chmod 0644 /data/local/tmp/ueventd.rc'
adb pull /data/local/tmp/ueventd.rc workspace/tiny_ramdisk/
```

**Add simple init.rc default**:
```bash
cat > workspace/tiny_ramdisk/init.rc << 'EOF'
# Minimal init.rc for debugging

on early-init
    start ueventd

on init
    export PATH /sbin
    mkdir /dev/pts
    mount devpts devpts /dev/pts

service ueventd /sbin/ueventd
    class core
    critical
    seclabel u:r:ueventd:s0

service adbd /sbin/adbd --root_seclabel=u:r:su:s0
    class core
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0
EOF
```

### Phase 9: First Build Attempt (22:51) → Commits `cabd131`, `8519056`

**Fix sbin permissions** before packing:
```bash
cd tiny_ramdisk
chmod +x sbin/adbd sbin/toybox
stat -c '%a %n' sbin/*
# 755 sbin/adbd
# 755 sbin/toybox
```

**Setup compressed tiny ramdisk**:
```bash
# Pack ramdisk with proper permissions
find . -print0 | cpio --null -o --format=newc -R 0:0 | gzip > ../out/tiny_ramdisk.cpio.gz

cd ../out
mv tiny_ramdisk.cpio.gz ramdisk.cpio

# Repack boot image
magiskboot unpack ../stock_boot_a.img  # Extract header info
magiskboot repack ../stock_boot_a.img  # Create new-boot.img with modified ramdisk
mv new-boot.img ../tiny_boot_a.img

# Verify AVB metadata preserved
avbtool.py info_image --image ../tiny_boot_a.img
```

**ELF dependency discovery**:
```bash
cd tiny_ramdisk
readelf -l init | grep interpreter
# [Requesting program interpreter: /system/bin/linker64]

readelf -d init | grep NEEDED
# (NEEDED) Shared library: [libc.so]
# (NEEDED) Shared library: [libdl.so]
# (NEEDED) Shared library: [libm.so]
# (NEEDED) Shared library: [libcutils.so]
# (NEEDED) Shared library: [libselinux.so]
# ... (20+ libraries)
```

**Problem identified**: Init binary requires `/system/bin/linker64` and extensive shared libraries, but minimal ramdisk has no `/system` mount.

---

## Session 4: November 4, 2025 - Recovery Integration & Resolution

### Phase 10: Recovery Analysis (19:31) → Commits `ebb976a`, `d4ae8aa`

**Set binaries to executable** (cleanup from previous session)

**Rename ambiguous ramdisk folder**:
```bash
# Clarify directory naming
mv workspace/unpack workspace/stock_boot_ramdisk_cpio_unpacked
```

**Analyze recovery image** for self-contained init:
```bash
cp partition-dumps/lun0/recovery_a.bin workspace/stock_recovery_a.img
cd workspace

mkdir stock_recovery
cd stock_recovery
magiskboot unpack ../stock_recovery_a.img
# Extracted: kernel, dtb, ramdisk.cpio

mkdir ../stock_recovery_cpio_unpacked && cd ../stock_recovery_cpio_unpacked
cpio -idmv < ../stock_recovery/ramdisk.cpio
```

**Recovery ramdisk structure**:
```
system/
  bin/
    init*          # Recovery init (different from boot init)
    minadbd*       # Minimal ADB daemon for recovery
    toybox*        # Multi-call binary
    ueventd*       # Device event manager
  lib64/
    *.so           # All shared libraries bundled!
    hw/            # Hardware abstraction layer
linker64*          # Dynamic linker
```

**Key insight**: Recovery mode is self-contained because it can't mount `/system`. All dependencies are bundled in the ramdisk.

### Phase 11: Recovery Binary Integration (19:49) → Commits `5852a25`, `4c20699`

**Update sbin with recovery binaries**:
```bash
cd workspace/tiny_ramdisk

# Replace limited binaries with recovery versions
cp ../stock_recovery_cpio_unpacked/system/bin/minadbd ./sbin/
cp ../stock_recovery_cpio_unpacked/system/bin/toybox ./sbin/
cp ../stock_recovery_cpio_unpacked/system/bin/ueventd ./sbin/

chmod +x sbin/*
```

**Replace init with recovery init**:
```bash
# Use self-contained recovery init instead of boot init
cp ../stock_recovery_cpio_unpacked/system/bin/init ./init
chmod +x init

# Analyze new dependencies
readelf -d init | grep NEEDED
# Still requires shared libraries, but recovery-specific versions
```

### Phase 12: First Flash & Bootloop (20:03) → Commit `de9bf12`

**Repack new tiny ramdisk**:
```bash
# Reorganize for clarity
mv stock_ramdisk stock_boot
mv stock_ramdisk_cpio_unpacked stock_boot_ramdisk

# Pack ramdisk v2
cd tiny_ramdisk
find . -print0 | cpio --null -o --format=newc -R 0:0 | gzip > ../out/tiny_ramdisk.cpio.gz

cd ../out
magiskboot unpack ../stock_boot_a.img
mv tiny_ramdisk.cpio.gz ramdisk.cpio
magiskboot repack ../stock_boot_a.img
mv new-boot.img ../tiny_boot_a.img

# Create B slot image
magiskboot repack ../stock_boot_b.img
mv new-boot.img ../tiny_boot_b.img
```

**Flash to device via EDL mode**:
```bash
cd ../../edl
source .venv/bin/activate
cd ..

# Enter Emergency Download Mode
adb reboot edl
adb devices  # (device disappears from ADB)

# Flash to B slot
edl --loader sm6225.bin w boot_b workspace/tiny_boot_b.img
edl reset
```

**Result**: Device bootlooped - stuck at boot logo

**Debugging**:
```bash
# Capture kernel panic logs
edl --loader sm6225.bin r logdump memory-dumps/pstore.log

# Device entered EDL mode automatically after crash
# Indicates kernel panic or init crash
```

### Phase 13: Shared Library Resolution (21:42) → Commits `5914e53`, `1ecd89c`

**Save text artifacts** for analysis:
```bash
# Document AVB header differences
avbtool.py info_image --image workspace/tiny_boot_a.img > avb_headers_tiny_a_v1.txt
avbtool.py info_image --image workspace/stock_boot_a.img > avb_headers_stock_a_v1.txt
diff avb_headers_*
# Only size differences - AVB signature intact

# Document ELF dependencies
cat > workspace/elf_missing.md << 'EOF'
# ELF Dependency Analysis

## Init Binary Requirements

readelf -d tiny_ramdisk/init | grep NEEDED:
- libc.so
- libdl.so  
- libm.so
- libcutils.so
- libselinux.so
- libbase.so
- libutils.so
- liblog.so
- libprocessgroup.so
- libcgrouprc.so
- (20+ total libraries)

readelf -d tiny_ramdisk/sbin/adbd | grep NEEDED:
- Similar extensive requirements

readelf -d tiny_ramdisk/sbin/minadbd | grep NEEDED:
- Recovery-optimized, fewer dependencies but still requires core libs

## Problem
Init requests interpreter: /system/bin/linker64
Ramdisk has no /system mount point or libraries.

## Solution
Bundle /system/bin/linker64 and /system/lib64/* from recovery ramdisk.
EOF
```

**Add linking necessities for ELF binaries**:
```bash
cd workspace/tiny_ramdisk

# Create system directory structure
mkdir -p system/bin
mkdir -p system/lib64/hw

# Copy dynamic linker
cp ../stock_recovery_cpio_unpacked/system/bin/linker64 system/bin/

# Copy ALL shared libraries from recovery
cp ../stock_recovery_cpio_unpacked/system/lib64/* system/lib64/
cp -r ../stock_recovery_cpio_unpacked/system/lib64/hw system/lib64/

# Verify size
du -sh system/
# ~120MB of shared libraries
```

**Final ramdisk structure**:
```
tiny_ramdisk/
├── dev/              # Empty, populated by ueventd
├── proc/             # Empty, mounted by init
├── sys/              # Empty, mounted by init
├── sbin/
│   ├── adbd*         # ADB daemon (recovery version)
│   ├── minadbd*      # Minimal ADB daemon
│   ├── toybox*       # Multi-call utility
│   └── ueventd*      # Device manager
├── system/
│   ├── bin/
│   │   └── linker64* # Dynamic linker
│   └── lib64/
│       ├── *.so      # All shared libraries (~300 files)
│       └── hw/       # Hardware abstraction layer
├── init*             # Recovery init (self-contained)
├── init.rc           # Init configuration
└── ueventd.rc        # Device node rules
```

### Phase 14: Final Build (22:06) → Commit `25eb416`

**Update ramdisk for shared objects**:
```bash
cd workspace/tiny_ramdisk

# Pack WITHOUT compression (magiskboot will compress)
find . -print0 | cpio --null -o --format=newc -R 0:0 > ../out/tiny_ramdisk.cpio

cd ../out
rm ramdisk.cpio
mv tiny_ramdisk.cpio ramdisk.cpio

# Repack both slots
magiskboot repack ../stock_boot_a.img
mv new-boot.img ../tiny_boot_a.img

magiskboot repack ../stock_boot_b.img  
mv new-boot.img ../tiny_boot_b.img

# Archive old versions
mv ../tiny_boot_a.img ../tiny_boot_a_v2.img
mv ../tiny_boot_b.img ../tiny_boot_b_v2.img
# (actually moved old v1 to _v1.img and new to default names)
```

**Final flash attempt** (22:15):
```bash
# Flash updated image
adb reboot edl
edl --loader sm6225.bin w boot_b workspace/tiny_boot_b.img
edl reset

# Wait for boot...
```

**Timeline ends here** - outcome not documented in shell history.

---

## Technical Decisions & Lessons Learned

### 1. Why Recovery Init Instead of Boot Init?

**Boot init** (`/system/bin/init`):
- Designed to mount `/system` partition and load libraries from there
- Assumes full Android system is available
- Not self-contained

**Recovery init** (`recovery_ramdisk/system/bin/init`):
- Self-contained with bundled libraries
- Designed to work without mounting `/system`
- Recovery mode can't rely on system partition (may be corrupted)

**Decision**: Use recovery init as base for minimal ramdisk

### 2. Compressed vs Uncompressed Ramdisk

**Magiskboot handles compression**:
```bash
# Wrong approach (double compression):
find . | cpio -o | gzip > ramdisk.cpio.gz
magiskboot repack boot.img  # Will compress again

# Correct approach:
find . | cpio -o > ramdisk.cpio
magiskboot repack boot.img  # Handles compression properly
```

### 3. CPIO Ownership & Permissions

**Critical flags**:
```bash
find . -print0 | cpio --null -o --format=newc -R 0:0
```

- `--null`: Handle filenames with spaces/special chars
- `--format=newc`: Use "new" ASCII format (Android standard)
- `-R 0:0`: Force root:root ownership (otherwise uses host UID/GID)

### 4. AVB Signature Preservation

**Magiskboot preserves AVB headers**:
```bash
# Unpack reads AVB data from original image
magiskboot unpack stock_boot_a.img

# Repack preserves original signature structure
magiskboot repack stock_boot_a.img
# Result: New ramdisk, original kernel/dtb/AVB
```

**AVB comparison**:
```diff
--- avb_headers_stock_a_v1.txt
+++ avb_headers_tiny_a_v2.txt
-Image size: 33554432 bytes
+Image size: 33554432 bytes  # (same)
-Partition Name: boot
+Partition Name: boot         # (same)
```

Size unchanged because magiskboot pads to original partition size.

### 5. ELF Dynamic Linking on Android

**Android ELF binaries require**:
1. **Interpreter**: `/system/bin/linker64` (not `/lib64/ld-linux-aarch64.so.1` like desktop Linux)
2. **Libraries**: Located via `DT_RUNPATH` or default `/system/lib64`
3. **Namespace isolation**: Android 8+ uses isolated namespaces

**Solution**: Bundle entire `/system/lib64` to ensure all dependencies present.

### 6. Version Control Strategy

**Tracked**:
- Scripts and configurations
- Text artifacts (AVB analysis, ELF dependencies)
- Ramdisk structure (small files)

**Not tracked**:
- Stock images (privacy, size)
- Compiled binaries (reproducible)
- Unpacked ramdisks (reconstructible)

**Rationale**: Repository documents process, not artifacts.

---

## File Manifest

### Repository Structure (After Part 2)

```
boox-reversing/
├── .gitignore                          # Excludes partition dumps, tools
├── workspace/
│   ├── .gitignore                      # Excludes stock images, kernel
│   ├── tiny_ramdisk/                   # Custom ramdisk source (tracked)
│   │   ├── dev/
│   │   ├── proc/
│   │   ├── sys/
│   │   ├── sbin/
│   │   │   ├── adbd*
│   │   │   ├── minadbd*
│   │   │   ├── toybox*
│   │   │   └── ueventd*
│   │   ├── system/
│   │   │   ├── bin/linker64*
│   │   │   └── lib64/*.so
│   │   ├── init*
│   │   ├── init.rc
│   │   └── ueventd.rc
│   ├── stock_bin/                      # Extracted binaries (tracked)
│   ├── out/                            # Build artifacts (tracked)
│   │   ├── dtb
│   │   ├── kernel
│   │   └── ramdisk.cpio
│   ├── elf_missing.md                  # ELF analysis (tracked)
│   ├── avb_headers_*.txt               # AVB comparisons (tracked)
│   ├── stock_boot_a.img                # NOT tracked
│   ├── stock_boot_b.img                # NOT tracked
│   ├── stock_recovery_a.img            # NOT tracked
│   ├── tiny_boot_a.img                 # NOT tracked
│   └── tiny_boot_b.img                 # NOT tracked
├── scripts/
│   ├── magisk/                         # NOT tracked (gitignored)
│   ├── avbtool.py                      # Tracked
│   └── make-manifest.sh                # Tracked
├── info_image/                         # AVB metadata (tracked)
├── partition-manifest.tsv              # Partition catalog (tracked)
├── partition-dumps/                    # NOT tracked (gitignored)
└── memory-dumps-v2/                    # NOT tracked (not yet gitignored)
```

---

## Commands Reference

### Essential Tools

```bash
# Set up PATH for entire session
export PATH="$PATH:$(pwd)/scripts/magisk:$(pwd)/scripts"

# Unpack boot image
magiskboot unpack boot.img

# Repack boot image (preserves AVB)
magiskboot repack boot.img

# Pack ramdisk
find . -print0 | cpio --null -o --format=newc -R 0:0 > ramdisk.cpio

# Unpack ramdisk
cpio -idmv < ramdisk.cpio

# Analyze AVB
avbtool.py info_image --image boot.img

# Flash via EDL
edl --loader sm6225.bin w boot_a boot.img
edl reset

# Analyze ELF dependencies
readelf -d binary | grep NEEDED
readelf -l binary | grep interpreter
```

### ADB Operations

```bash
# Root shell
adb root
adb shell

# Copy files from device (rooted)
adb shell su -c 'cp /src/file /data/local/tmp/ && chmod 0644 /data/local/tmp/file'
adb pull /data/local/tmp/file

# Reboot to EDL mode
adb reboot edl
```

---

## Next Steps

1. **Verify boot success** - Check if final flash resolved bootloop
2. **Test ADB connectivity** - Confirm adbd starts and accepts connections
3. **SELinux policy** - May need permissive mode or custom policy
4. **Init script refinement** - Add necessary services and mounts
5. **Partition mounting** - Mount system/vendor for full functionality

---

## Appendix: Timestamp Cross-Reference

| Timestamp    | Date/Time (EST)          | Commit  | Description                          |
|--------------|--------------------------|---------|--------------------------------------|
| 1761202441   | 2025-10-23 02:54:01      | -       | Install Python 2                     |
| 1761267534   | 2025-10-23 20:58:54      | 8fffffc | Examine vbmeta                       |
| 1761273368   | 2025-10-23 22:36:08      | bc20375 | Add more image info                  |
| 1761274512   | 2025-10-23 22:55:12      | 4dcefd4 | Add required tools                   |
| 1761276130   | 2025-10-23 23:22:10      | 37f1302 | Add manifest of all partitions       |
| 1761329598   | 2025-10-24 14:13:18      | b2a0e0f | Add magiskboot and other tools       |
| 1762222898   | 2025-11-03 21:21:55      | 2223f21 | Setup tiny ramdisk layout            |
| 1762222915   | 2025-11-03 21:21:55      | d9dd780 | Extract key binaries from stock      |
| 1762226976   | 2025-11-03 22:31:06      | 4ce4c47 | Add simple init.rc default           |
| 1762227066   | 2025-11-03 22:31:06      | 1acc1e9 | Extract ueventd.rc from device       |
| 1762228463   | 2025-11-03 22:54:23      | cabd131 | Fix sbin permissions                 |
| 1762228472   | 2025-11-03 22:54:32      | 8519056 | Setup compressed tiny ramdisk        |
| 1762302712   | 2025-11-04 19:31:52      | ebb976a | Set binaries to executable           |
| 1762302760   | 2025-11-04 19:32:40      | d4ae8aa | Rename ambiguous ramdisk folder      |
| 1762303771   | 2025-11-04 19:49:31      | 5852a25 | Update sbin with recovery binaries   |
| 1762303780   | 2025-11-04 19:49:40      | 4c20699 | Replace init with recovery init      |
| 1762304621   | 2025-11-04 20:03:41      | de9bf12 | Repack new tiny ramdisk              |
| 1762310566   | 2025-11-04 21:42:46      | 5914e53 | Save text artifacts                  |
| 1762310577   | 2025-11-04 21:42:57      | 1ecd89c | Add linking necessities for ELF bins |
| 1762312017   | 2025-11-04 22:06:57      | 25eb416 | Update ramdisk for shared objects    |

Total time: ~36 hours spread across 4 sessions over 13 days.
