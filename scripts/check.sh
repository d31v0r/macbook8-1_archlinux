#!/usr/bin/env bash
# check.sh: read-only health check for the MacBookPro8,1 setup. Run as your normal user AFTER rebooting.
pass=0 warn=0 fail=0
ok()   { printf ' \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf ' \033[33mWARN\033[0m %s\n' "$*"; warn=$((warn+1)); }
nope() { printf ' \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
have() { command -v "$1" >/dev/null 2>&1; }
active() { systemctl is-active --quiet "$1" 2>/dev/null; }
enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

echo "== machine"
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
[[ $model == MacBookPro8,1 ]] && ok "MacBookPro8,1" || bad "product is '$model'"
echo "kernel: $(uname -r)"; echo "cmdline: $(cat /proc/cmdline)"

echo "== display / graphics"
[[ -e /sys/class/backlight/intel_backlight ]] && ok "intel_backlight present" || nope "no intel_backlight (add acpi_backlight=native to the kernel command line)"
lspci -k -s 00:02.0 2>/dev/null | grep -q 'in use: i915' && ok "i915 bound to the Intel GPU" || nope "i915 not bound"
if have vainfo; then vainfo >/dev/null 2>&1 && ok "VA-API works (libva-intel-driver)" || bad "vainfo failed"; fi

echo "== keyboard / input"
kb=/sys/class/leds/smc::kbd_backlight/brightness
if [[ -e $kb ]]; then [[ -w $kb ]] && ok "keyboard backlight writable by $USER" || bad "keyboard backlight not writable: are you in group 'video'? (re-login needed after usermod)"; else nope "no smc::kbd_backlight (applesmc not loaded?)"; fi
fn=$(cat /sys/module/hid_apple/parameters/fnmode 2>/dev/null)
[[ $fn == 2 ]] && ok "hid_apple fnmode=2 (F1-F12 by default)" || bad "hid_apple fnmode='$fn'"
compgen -G '/dev/input/by-path/*' >/dev/null && ok "input devices present"

echo "== Wi-Fi / Bluetooth"
drv=$(lspci -nnk -d 14e4:4331 2>/dev/null | sed -n 's/.*Kernel driver in use: //p')
[[ -n $drv ]] && ok "BCM4331 driver in use: $drv" || nope "BCM4331 has no driver bound"
ip -br link 2>/dev/null | grep -q '^wl' && ok "wireless interface exists" || nope "no wlan interface"
active NetworkManager && ok "NetworkManager active" || bad "NetworkManager not active (other network manager in use?)"
active bluetooth && ok "bluetooth.service active" || bad "bluetooth.service not active"
have rfkill && rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: no' && ok "bluetooth not blocked"

echo "== sound"
if have pactl; then pactl info 2>/dev/null | grep -qi pipewire && ok "PipeWire is the sound server" || bad "PipeWire not the sound server (log in to a user session first)"; fi

echo "== power / thermals"
enabled tlp && ok "tlp enabled" || bad "tlp not enabled"
[[ $(systemctl is-enabled systemd-rfkill.service 2>/dev/null) == masked ]] && ok "systemd-rfkill masked (needed by TLP)" || bad "systemd-rfkill not masked"
lsmod | grep -qw applesmc && ok "applesmc loaded" || nope "applesmc not loaded"
lsmod | grep -qw coretemp && ok "coretemp loaded" || bad "coretemp not loaded"
active mbpfan && ok "mbpfan running" || bad "mbpfan not running (AUR build skipped?)"
have sensors && sensors 2>/dev/null | grep -qi 'fan\|Core' && ok "sensors report data"

echo "== misc"
[[ -e /dev/video0 ]] && ok "webcam /dev/video0" || bad "no /dev/video0"

printf '\n%d passed, %d warnings, %d failed\n' "$pass" "$warn" "$fail"
echo "Manual: suspend (close the lid), resume, Wi-Fi after resume, brightness keys."
((fail == 0))
