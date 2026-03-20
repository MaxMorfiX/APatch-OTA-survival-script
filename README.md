# APatch OTA Survival for A-only devices

This addon.d script ensures APatch survives LineageOS OTA updates on A-only devices. It extracts the root superkey from the current kernel and re-patches the new boot image after the update.

# Requirements
- A-only device with LineageOS (or any ROM supporting addon.d)
- APatch already installed
- extracted APatch apk/zip placed in `/system/addon.d/APatch/` (explained later in the guide)

# Installation

## 1. Copy the `97-apatch.sh` to the `/system/addon.d` folder on your device (root required)
either via adb:
```
adb root
adb remount /
adb push 97-apatch.sh /system/addon.d
```
or with termux:
```
su
remount /
cp 97-apatch.sh /system/addon.d
```
## 2. Unzip the APatch.apk file (from the official [APatch github](https://github.com/bmax121/APatch)) and place it in `/system/addon.d/APatch`

from termux:
```
unzip APatch.apk /APatch #replace with the actual filename
su
remount /
cp 97-apatch.sh /system/addon.d
```
or you can just run the update-apatch-ota.sh script which should extract the neccessary files from your already installed APatch installation and move them in the right folder automatically

# Update to a newer APatch

You can either manually replace the APatch folder in addon.d with the new version of APatch, or do it automatically if you run `update-apatch-ota.sh` from termux. You can even add it as a shortcut to your homescreen if you put the script in `/.termux/widget/dynamic_shortcuts` and then add it as a wiget to your homescreen with [Termux Widget](https://github.com/termux/termux-widget).
