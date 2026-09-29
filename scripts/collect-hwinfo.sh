#!/bin/sh
# Regenerate the hardware dumps that live in docs/legacy-2015/output/ (from 2015, kernel 3.18).
# Usage: ./scripts/collect-hwinfo.sh [outdir]
out="${1:-hwinfo-$(uname -r)}"
mkdir -p "$out"
sudo lspci -vvv  > "$out/lspci_vvv"
lsusb -vvv 2>/dev/null > "$out/lsusb_vvv"
sudo dmesg       > "$out/dmesg"
cat /proc/cmdline > "$out/cmdline"
uname -a         > "$out/uname"
lsmod            > "$out/lsmod"
ls /sys/class/backlight /sys/class/leds > "$out/sysfs-backlight-leds" 2>&1
echo "Wrote $out/"
