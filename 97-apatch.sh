#!/sbin/sh
#
# APatch OTA Survival Script for A-only devices
# ==============================================
#
# Description:
#   This addon.d script ensures APatch persists through LineageOS OTA updates
#   on A-only devices. It extracts the root superkey hash from the current
#   kernel during the backup phase, then uses it with the latest APatch tools
#   to repatch the new boot image during post-restore.
#
# Requirements:
#   - APatch tools placed in /system/addon.d/APatch/ with structure:
#       /system/addon.d/APatch/lib/arm64-v8a/libmagiskboot.so
#       /system/addon.d/APatch/lib/arm64-v8a/libkptools.so
#       /system/addon.d/APatch/assets/kpimg
#   - Script saved as /system/addon.d/97-apatch.sh (chmod 755)
#   - A-only device with Lineage Recovery (no automatic /data decryption)
#
# How it works:
#   backup:
#     - Copies APatch tools to /tmp/apatch_ota/tools
#     - Dumps current boot image, extracts root_superkey hash, saves to /tmp
#   post-restore:
#     - Reads saved hash, uses staged tools to patch new kernel,
#       repack boot image, and flash it back
#
# Author: Community effort (based on Magisk addon.d template)
# Version: 1.0
# License: GPL v3
#
# ADDOND_VERSION=3

. /tmp/backuptool.functions

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# Relative path to the APatch folder (within system partition)
REL_FOLDER_PATH="addon.d/APatch"

# Temporary base directory (all operations in /tmp to avoid space issues)
TMP_BASE="/tmp/apatch_ota"
TOOLSDIR="$TMP_BASE/tools"          # Staged tools
WORKDIR="$TMP_BASE/work"            # Working directory for boot image
HASH_FILE="$TMP_BASE/hash"          # Stores root_superkey hash

# Boot partition (common for A-only devices)
BOOT_PART="/dev/block/by-name/boot"

# ----------------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------------

# Locate boot partition dynamically
find_boot_part() {
    for part in /dev/block/by-name/boot /dev/block/bootdevice/by-name/boot; do
        [ -e "$part" ] && { echo "$part"; return; }
    done
    find /dev/block -name boot | head -n1
}

# Locate APatch folder using $S (provided by backuptool) or common mount points
find_folder() {
    if [ -n "$S" ] && [ -d "$S/$REL_FOLDER_PATH" ]; then
        echo "$S/$REL_FOLDER_PATH"
        return
    fi
    for base in /postinstall /mnt/system /system; do
        if [ -d "$base/$REL_FOLDER_PATH" ]; then
            echo "$base/$REL_FOLDER_PATH"
            return
        fi
    done
    echo ""
}

# ----------------------------------------------------------------------------
# list_files – tells framework which files to preserve across OTAs
# ----------------------------------------------------------------------------
list_files() {
    find $REL_FOLDER_PATH -type f 2>/dev/null
}

# ----------------------------------------------------------------------------
# Main Case (addon.d stages)
# ----------------------------------------------------------------------------
case "$1" in
    backup)
        # --------------------------------------------------------------------
        # BACKUP STAGE – runs before OTA wipes /system
        # --------------------------------------------------------------------
        echo "I: APatch backup: staging tools and extracting root_superkey hash" >> /tmp/recovery.log

        # Locate boot partition
        BOOT_PART=$(find_boot_part)
        if [ -z "$BOOT_PART" ]; then
            echo "E: Cannot find boot partition – aborting backup" >> /tmp/recovery.log
            exit 0
        fi
        echo "I: Boot partition: $BOOT_PART" >> /tmp/recovery.log

        # Locate APatch folder
        FOLDER=$(find_folder)
        if [ -z "$FOLDER" ]; then
            echo "E: APatch folder not found – aborting backup" >> /tmp/recovery.log
            exit 0
        fi
        echo "I: APatch folder found at: $FOLDER" >> /tmp/recovery.log

        # Clean and recreate tools directory
        rm -rf "$TOOLSDIR"
        mkdir -p "$TOOLSDIR"

        # Copy binaries and kpimg from APatch folder
        echo "I: Copying binaries from $FOLDER/lib/arm64-v8a/* to $TOOLSDIR" >> /tmp/recovery.log
        cp "$FOLDER/lib/arm64-v8a/"* "$TOOLSDIR"/ 2>/dev/null
        echo "I: Copying kpimg from $FOLDER/assets/kpimg" >> /tmp/recovery.log
        cp "$FOLDER/assets/kpimg" "$TOOLSDIR"/ 2>/dev/null

        # Set permissions
        chmod 755 "$TOOLSDIR"/lib*.so 2>/dev/null
        chmod 644 "$TOOLSDIR"/kpimg 2>/dev/null

        # Verify essential tools are present
        if [ ! -x "$TOOLSDIR/libmagiskboot.so" ] || [ ! -x "$TOOLSDIR/libkptools.so" ] || [ ! -f "$TOOLSDIR/kpimg" ]; then
            echo "E: Essential APatch tools missing – aborting backup" >> /tmp/recovery.log
            exit 0
        fi

        # Create working directory and dump boot image
        rm -rf "$WORKDIR"
        mkdir -p "$WORKDIR"
        cd "$WORKDIR" || exit 0

        echo "I: Dumping current boot image to $WORKDIR/boot.img" >> /tmp/recovery.log
        dd if="$BOOT_PART" of=boot.img bs=1M 2>&1 | tee -a /tmp/recovery.log
        if [ $? -ne 0 ]; then
            echo "E: Failed to dump boot image" >> /tmp/recovery.log
            exit 0
        fi

        # Unpack boot image
        echo "I: Unpacking boot.img" >> /tmp/recovery.log
        "$TOOLSDIR/libmagiskboot.so" unpack boot.img >> /tmp/recovery.log 2>&1

        # Check for kernel
        if [ ! -f kernel ]; then
            echo "E: Kernel not found after unpack – aborting backup" >> /tmp/recovery.log
            exit 0
        fi

        # Extract root_superkey hash from kernel
        echo "I: Extracting root_superkey hash from kernel" >> /tmp/recovery.log
        KP_OUTPUT=$("$TOOLSDIR/libkptools.so" -i kernel -l 2>&1)
        ROOT_HASH=$(echo "$KP_OUTPUT" | grep 'root_superkey=' | cut -d= -f2)

        if [ -n "$ROOT_HASH" ]; then
            echo -n "$ROOT_HASH" > "$HASH_FILE"
            echo "I: root_superkey hash saved: $ROOT_HASH" >> /tmp/recovery.log
        else
            echo "W: Could not extract root_superkey hash – patching may fail" >> /tmp/recovery.log
        fi

        # Clean up work directory (keep tools and hash)
        rm -rf "$WORKDIR"
        echo "I: Backup stage completed" >> /tmp/recovery.log
        ;;

    post-restore)
        # --------------------------------------------------------------------
        # POST-RESTORE STAGE – runs after new ROM is flashed
        # --------------------------------------------------------------------
        echo "I: APatch post-restore: re-patching boot image" >> /tmp/recovery.log

        # Verify tools and hash are present
        if [ ! -d "$TOOLSDIR" ] || [ ! -x "$TOOLSDIR/libmagiskboot.so" ] || [ ! -x "$TOOLSDIR/libkptools.so" ] || [ ! -f "$TOOLSDIR/kpimg" ]; then
            echo "E: APatch tools not found in $TOOLSDIR – aborting" >> /tmp/recovery.log
            exit 0
        fi
        if [ ! -f "$HASH_FILE" ]; then
            echo "E: root_superkey hash file missing – cannot repatch" >> /tmp/recovery.log
            exit 0
        fi
        ROOT_HASH=$(cat "$HASH_FILE")
        echo "I: Using root hash: $ROOT_HASH" >> /tmp/recovery.log

        # Locate boot partition again (may have changed if slots are used)
        BOOT_PART=$(find_boot_part)
        if [ -z "$BOOT_PART" ]; then
            echo "E: Cannot find boot partition – aborting" >> /tmp/recovery.log
            exit 0
        fi

        # Create working directory
        rm -rf "$WORKDIR"
        mkdir -p "$WORKDIR"
        cd "$WORKDIR" || exit 0

        # Dump new boot image
        echo "I: Dumping new boot image" >> /tmp/recovery.log
        dd if="$BOOT_PART" of=boot.img bs=1M 2>&1 | tee -a /tmp/recovery.log
        if [ $? -ne 0 ]; then
            echo "E: Failed to dump boot image" >> /tmp/recovery.log
            exit 0
        fi

        # Unpack boot image
        "$TOOLSDIR/libmagiskboot.so" unpack boot.img >> /tmp/recovery.log 2>&1
        if [ ! -f kernel ]; then
            echo "E: Failed to unpack kernel" >> /tmp/recovery.log
            exit 0
        fi

        # Verify kernel has required symbols
        if ! "$TOOLSDIR/libkptools.so" -i kernel -f 2>/dev/null | grep -q "CONFIG_KALLSYMS=y"; then
            echo "E: Kernel lacks CONFIG_KALLSYMS – cannot patch" >> /tmp/recovery.log
            exit 0
        fi

        # Backup original kernel and patch with root hash
        mv kernel kernel.ori
        echo "I: Patching kernel with root hash" >> /tmp/recovery.log
        "$TOOLSDIR/libkptools.so" -p --image kernel.ori --root-skey "$ROOT_HASH" --kpimg "$TOOLSDIR/kpimg" --out kernel 2>&1 | tee -a /tmp/recovery.log

        # Repack boot image
        "$TOOLSDIR/libmagiskboot.so" repack boot.img >> /tmp/recovery.log 2>&1
        if [ ! -f new-boot.img ]; then
            echo "E: Repack failed – new-boot.img not created" >> /tmp/recovery.log
            exit 0
        fi

        # Flash new boot image
        echo "I: Flashing patched boot image" >> /tmp/recovery.log
        dd if=new-boot.img of="$BOOT_PART" bs=1M 2>&1 | tee -a /tmp/recovery.log
        echo "I: Boot image flashed successfully" >> /tmp/recovery.log

        # Clean up
        rm -f "$HASH_FILE"
        rm -rf "$WORKDIR"
        echo "I: Post-restore stage completed" >> /tmp/recovery.log
        ;;

    # Unused stages (must be present for compatibility)
    pre-backup) ;;
    post-backup) ;;
    pre-restore) ;;
    restore) ;;
esac