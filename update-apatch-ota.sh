#!/data/data/com.termux/files/usr/bin/bash
# APatch Tools Updater – one-tap refresh from Termux widget

# Colors for terminal output (optional)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}📱 APatch Tools Updater${NC}"
echo "================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ This script must run as root!${NC}"
    echo "Please grant root permissions when prompted."
    exec su -c "$0"
    exit 1
fi

echo -e "${GREEN}✓ Running as root${NC}"

# Source paths
APATCH_APP_DATA="/data/data/me.bmax.apatch"
DEST_DIR="/system/addon.d/APatch/lib/arm64-v8a/"
DEST_ASSETS="/system/addon.d/APatch/assets/"

# Verify source files exist
if [ ! -f "$APATCH_APP_DATA/patch/kptools" ] || [ ! -f "$APATCH_APP_DATA/patch/kpimg" ] || [ ! -f "$APATCH_APP_DATA/patch/magiskboot" ]; then
    echo -e "${RED}❌ APatch tools not found in app data!${NC}"
    echo "Make sure APatch is installed and has been run at least once."
    exit 1
fi

echo -e "${GREEN}✓ Found APatch tools in app data${NC}"

# Remount system as read-write
echo "📂 Remounting system as read-write..."
mount -o rw,remount /system
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to remount system!${NC}"
    exit 1
fi

# Create destination directories if needed
mkdir -p "$DEST_DIR" "$DEST_ASSETS"

# Copy files
echo "📋 Copying kptools..."
cp "$APATCH_APP_DATA/patch/kptools" "$DEST_DIR/libkptools.so"

echo "📋 Copying magiskboot..."
cp "$APATCH_APP_DATA/patch/magiskboot" "$DEST_DIR/libmagiskboot.so"

echo "📋 Copying kpimg..."
cp "$APATCH_APP_DATA/patch/kpimg" "$DEST_ASSETS/kpimg"

# Set permissions
chmod 755 "$DEST_DIR/libkptools.so" "$DEST_DIR/libmagiskboot.so"
chmod 644 "$DEST_ASSETS/kpimg"

# Remount system as read-only
mount -o ro,remount /system

echo -e "${GREEN}✅ APatch tools updated successfully!${NC}"
echo "================================"

# Optional: Show a notification
if command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "APatch Tools" --content "Update completed successfully"
fi