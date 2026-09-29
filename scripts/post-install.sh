#!/usr/bin/env bash
# post-install.sh: make Arch Linux work on a MacBookPro8,1 (Early 2011, 13").
# Run as root on the INSTALLED system (first boot, network needed):   sudo ./scripts/post-install.sh
# Idempotent: safe to run again. Nothing here touches partitions or the boot loader binaries.
#
# Options:
#   --wifi wl|b43|none   Wi-Fi driver for the BCM4331 (default: wl)
#   --x11 | --no-x11     install X11 packages+config / skip X11 files (default: X11 files only if xorg-server is installed)
#   --no-extras          skip convenience packages (pavucontrol, playerctl, udiskie, gammastep, fonts)
#   --layouts us,ru      set X11 keyboard layouts (Alt+Shift toggles)
#   --sleep-hook         install the (unverified) wl unload/reload hook for suspend
#   --user NAME          user for group membership, AUR builds and ~/.xbindkeysrc (default: $SUDO_USER)
#   --yes                don't pause to review AUR PKGBUILDs
#   --force              run even if DMI says this is not a MacBookPro8,1
#   --dry-run            print what would be done, change nothing
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${ROOT:-}                      # test hook: prefix for every file path we edit
DRY=0 YES=0 FORCE=0 EXTRAS=1 SLEEP_HOOK=0
WIFI=wl X11=auto LAYOUTS=""
USER_NAME=${SUDO_USER:-}
BACKLIGHT_PARAM="acpi_backlight=native"
CHANGED_INITRAMFS=0
declare -a NOTES=()

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; NOTES+=("$*"); }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }
run()  { if ((DRY)); then printf '    [dry-run] %s\n' "$*" >&2; else "$@"; fi; }

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

parse_args() {
    while (($#)); do
        case $1 in
            --wifi)       WIFI=${2:?}; shift ;;
            --x11)        X11=yes ;;
            --no-x11)     X11=no ;;
            --no-extras)  EXTRAS=0 ;;
            --layouts)    LAYOUTS=${2:?}; shift ;;
            --sleep-hook) SLEEP_HOOK=1 ;;
            --user)       USER_NAME=${2:?}; shift ;;
            --yes)        YES=1 ;;
            --force)      FORCE=1 ;;
            --dry-run)    DRY=1 ;;
            -h|--help)    usage; exit 0 ;;
            *)            die "unknown option: $1 (see --help)" ;;
        esac
        shift
    done
    case $WIFI in wl|b43|none) ;; *) die "--wifi must be wl, b43 or none" ;; esac
}

pkg_has() { pacman -Q "$1" >/dev/null 2>&1; }

pacman_install() { run pacman -Syu --needed --noconfirm "$@"; }

# ---------------------------------------------------------------- preflight
preflight() {
    [[ -z $ROOT ]] || return 0
    [[ -f /etc/arch-release ]] || die "this is not Arch Linux"
    ((DRY)) || [[ $EUID -eq 0 ]] || die "run as root (sudo)"
    local model
    model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
    if [[ $model != MacBookPro8,1 ]] && ! ((FORCE)); then
        die "product is '$model', not MacBookPro8,1. The 15\"/17\" 8,2/8,3 have an AMD GPU and need different handling. Use --force to override."
    fi
    if [[ -n $USER_NAME ]] && ! id "$USER_NAME" >/dev/null 2>&1; then
        die "user '$USER_NAME' does not exist"
    fi
    [[ -n $USER_NAME ]] || warn "no --user / SUDO_USER: skipping video-group membership, AUR builds and ~/.xbindkeysrc"
}

user_home() { getent passwd "$USER_NAME" | cut -d: -f6; }

# ---------------------------------------------------------------- files
# copy one file from the repo to its place, keeping a numbered backup of anything we overwrite
PUT_CHANGED=0
put() {   # put <path-below-tree> <tree> [mode]; sets PUT_CHANGED=1 when it actually wrote something
    local rel=$1 tree=$2 src dst
    PUT_CHANGED=0
    src="$REPO_DIR/cfg/$tree/$rel"
    dst="$ROOT/$rel"
    [[ -f $src ]] || die "missing $src"
    if [[ -f $dst ]] && cmp -s "$src" "$dst"; then return 0; fi
    log "install /$rel"
    PUT_CHANGED=1
    run install -Dm"${3:-644}" -b --suffix=.bak "$src" "$dst"
}

put_initrd() { put "$@"; if ((PUT_CHANGED)); then CHANGED_INITRAMFS=1; fi; }

install_configs() {
    put_initrd etc/modprobe.d/hid_apple.conf     root
    put etc/udev/rules.d/91-kbd-backlight.rules  root
    put etc/modules-load.d/macbook81.conf        root
    put etc/tlp.d/10-macbook81.conf              root
    if [[ $X11 == yes ]]; then
        put etc/X11/xorg.conf.d/30-touchpad.conf root
    fi
    case $WIFI in
        wl)
            put_initrd etc/modprobe.d/broadcom-wl.conf optional/wifi-wl
            if ((SLEEP_HOOK)); then
                put usr/lib/systemd/system-sleep/wl-reload optional/wifi-wl 755
            fi ;;
        b43)
            run rm -f "$ROOT/etc/modprobe.d/broadcom-wl.conf"
            run rm -f "$ROOT/usr/lib/systemd/system-sleep/wl-reload"
            put_initrd etc/modprobe.d/b43.conf optional/wifi-b43
            CHANGED_INITRAMFS=1 ;;
    esac
}

# ---------------------------------------------------------------- packages
kernel_headers() {
    local k
    for k in linux linux-lts linux-zen linux-hardened; do
        pkg_has "$k" && printf '%s-headers\n' "$k"
    done
}

install_packages() {
    local -a pk=(base-devel git dkms brightnessctl tlp lm_sensors
                 bluez bluez-utils networkmanager
                 pipewire pipewire-pulse pipewire-alsa wireplumber
                 mesa libva-intel-driver intel-ucode)
    [[ $X11 == yes ]] && pk+=(xorg-server xorg-xinit xorg-apps xf86-input-libinput xbindkeys)
    ((EXTRAS)) && pk+=(pavucontrol playerctl udiskie gammastep ttf-dejavu libva-utils)
    case $WIFI in
        wl)  mapfile -t hdr < <(kernel_headers)
             ((${#hdr[@]})) || warn "no known kernel package found for headers (linux, linux-lts, ...): DKMS cannot build wl"
             pk+=("${hdr[@]}" broadcom-wl-dkms) ;;
        b43) pk+=(b43-fwcutter) ;;
    esac
    log "packages (full system upgrade + install): ${pk[*]}"
    pacman_install "${pk[@]}"
    if [[ $WIFI == b43 ]] && pkg_has broadcom-wl-dkms; then
        run pacman -Rns --noconfirm broadcom-wl-dkms
    fi
}

# run a command as the normal user with HOME set (runuser is part of util-linux; plain `sudo` is not in a base install)
as_user() { run runuser -u "$USER_NAME" -- env HOME="$(user_home)" "$@"; }

aur_install() {   # aur_install <pkg>: build as the normal user, install as root
    local pkg=$1 home dir
    [[ -n $USER_NAME ]] || { warn "cannot build AUR package $pkg without a user (--user)"; return 0; }
    pkg_has "$pkg" && return 0
    home=$(user_home); dir="$home/.cache/macbook81-aur/$pkg"
    log "AUR: $pkg"
    # NB: callers use `aur_install x || warn ...`, which disables errexit in here, so every step checks itself
    as_user mkdir -p "$home/.cache/macbook81-aur" || return 1
    if [[ -d $dir/.git ]]; then
        as_user git -C "$dir" pull --ff-only || return 1
    else
        as_user git clone "https://aur.archlinux.org/$pkg.git" "$dir" || return 1
    fi
    if ! ((YES)) && ! ((DRY)); then
        warn "AUR packages are unreviewed user submissions. Review $dir/PKGBUILD."
        read -rp "    Have you read the PKGBUILD and want to build it? [y/N] " a
        [[ $a == [yY]* ]] || { warn "skipped AUR package $pkg"; return 0; }
    fi
    # makepkg calls `sudo pacman` for build dependencies (sudo comes with base-devel); you may be asked for your password
    as_user bash -c "cd '$dir' && makepkg --syncdeps --noconfirm" || return 1
    if ((DRY)); then echo "    [dry-run] pacman -U <built $pkg package>" >&2; return 0; fi
    local f
    f=$(find "$dir" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*-debug-*' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-) || true
    [[ -n $f ]] || return 1
    pacman -U --noconfirm "$f"
}

# ---------------------------------------------------------------- kernel parameter
backlight_ok() { [[ -e /sys/class/backlight/intel_backlight ]]; }

# add PARAM to a boot loader's kernel command line if it is missing. Echoes the loader touched.
ensure_kernel_param() {
    local param=$1 f touched=""
    add_t() { touched+="${touched:+; }$1"; }
    f="$ROOT/boot/refind_linux.conf"
    if [[ -f $f ]] && ! grep -q -- "$param" "$f"; then
        run sed -E -i.bak "/^[[:space:]]*\"[^\"]*\"[[:space:]]+\"[^\"]*\"/ s/\"[[:space:]]*\$/ $param\"/" "$f"
        add_t "rEFInd (/boot/refind_linux.conf)"
    fi
    f="$ROOT/etc/default/grub"
    if [[ -f $f ]] && ! grep -q -- "$param" "$f"; then
        run sed -E -i.bak "s/^(GRUB_CMDLINE_LINUX_DEFAULT=[\"'][^\"']*)([\"'])/\\1 $param\\2/" "$f"
        run grub-mkconfig -o "$ROOT/boot/grub/grub.cfg" >&2
        add_t "GRUB (/etc/default/grub)"
    fi
    local d e
    for d in "$ROOT/boot/loader/entries" "$ROOT/efi/loader/entries"; do
        [[ -d $d ]] || continue
        for e in "$d"/*.conf; do
            [[ -f $e ]] && ! grep -q -- "$param" "$e" || continue
            run sed -E -i.bak "s/^(options[[:space:]].*)\$/\\1 $param/" "$e"
            add_t "systemd-boot ($d)"
        done
    done
    printf '%s' "$touched"
}

kernel_param_step() {
    if backlight_ok; then
        log "intel_backlight present, $BACKLIGHT_PARAM not needed"
        return 0
    fi
    log "no /sys/class/backlight/intel_backlight, adding $BACKLIGHT_PARAM (ArchWiki: needed since kernel 6.1)"
    local t; t=$(ensure_kernel_param "$BACKLIGHT_PARAM")
    if [[ -n $t ]]; then
        warn "added $BACKLIGHT_PARAM to $t. Reboot for it to apply."
    else
        warn "no editable boot loader config found (or already set). Add '$BACKLIGHT_PARAM' to your kernel command line by hand (rEFInd: /boot/refind_linux.conf)."
    fi
}

# ---------------------------------------------------------------- services
other_network_manager() {
    local u
    for u in systemd-networkd iwd dhcpcd connman wicd; do
        systemctl is-enabled "$u.service" >/dev/null 2>&1 && { echo "$u"; return 0; }
    done
    return 1
}

services_step() {
    log "services"
    local other
    if systemctl is-enabled NetworkManager.service >/dev/null 2>&1; then
        :
    elif other=$(other_network_manager); then
        warn "$other is already enabled: NetworkManager installed but NOT enabled. Pick one network manager."
    else
        run systemctl enable NetworkManager.service
    fi
    run systemctl enable tlp.service bluetooth.service
    # ArchWiki (TLP): systemd-rfkill conflicts with TLP's radio switching
    run systemctl mask systemd-rfkill.service systemd-rfkill.socket
    # TLP conflicts with power-profiles-daemon as a whole
    if pkg_has power-profiles-daemon; then run systemctl mask power-profiles-daemon.service; fi
    # PipeWire is socket-activated per user; make sure the presets are in effect
    run systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
        || warn "could not enable the PipeWire user units globally; run: systemctl --user enable --now pipewire pipewire-pulse wireplumber"
    # SSD only: weekly TRIM (ArchWiki: Solid state drive)
    local d rot
    for d in /sys/block/sd?; do
        [[ -r $d/queue/rotational ]] || continue
        rot=$(cat "$d/queue/rotational")
        if [[ $rot == 0 ]]; then run systemctl enable fstrim.timer; break; fi
    done
    if pkg_has mbpfan || ((DRY)); then run systemctl enable mbpfan.service; fi
    return 0
}

user_step() {
    [[ -n $USER_NAME ]] || return 0
    log "group 'video' for $USER_NAME (backlight / keyboard backlight without root)"
    run usermod -aG video "$USER_NAME"
    if [[ $X11 == yes ]]; then
        local home; home=$(user_home)
        if [[ ! -e $home/.xbindkeysrc ]]; then
            log "$HOME/.xbindkeysrc (brightness / volume / media keys)"
            run install -Dm644 -o "$USER_NAME" -g "$(id -gn "$USER_NAME")" "$REPO_DIR/cfg/examples/xbindkeysrc" "$home/.xbindkeysrc"
            NOTES+=("Start xbindkeys from your WM/.xinitrc (see cfg/examples/xinitrc). Not needed in KDE/GNOME/XFCE.")
        fi
    fi
    if [[ -n $LAYOUTS ]]; then
        log "X11 keyboard layouts: $LAYOUTS"
        run localectl set-x11-keymap "$LAYOUTS" "" "" grp:alt_shift_toggle
    fi
}

finish() {
    log "regenerate initramfs and reload udev"
    if ((CHANGED_INITRAMFS)); then run mkinitcpio -P; fi
    # GRUB only: regenerate so the freshly installed intel-ucode is picked up
    if [[ -f $ROOT/etc/default/grub ]]; then run grub-mkconfig -o "$ROOT/boot/grub/grub.cfg" >&2; fi
    run udevadm control --reload
    run udevadm trigger --subsystem-match=leds --subsystem-match=backlight
    if [[ ! -f $ROOT/etc/default/grub ]]; then
        NOTES+=("intel-ucode is installed, but only GRUB picks it up automatically. With rEFInd/systemd-boot add 'initrd=<path>/intel-ucode.img' BEFORE the initramfs initrd in your boot options.")
    fi
    if ((${#NOTES[@]})); then
        printf '\n\033[1;33mNotes\033[0m\n'
        printf '  - %s\n' "${NOTES[@]}"
    fi
    printf '\nDone. Reboot, then run: ./scripts/check.sh\n'
}

main() {
    parse_args "$@"
    preflight
    if [[ $X11 == auto ]]; then
        if pkg_has xorg-server 2>/dev/null; then X11=yes; else X11=no; fi
    fi
    install_packages
    if [[ $WIFI == b43 ]]; then
        aur_install b43-firmware || warn "b43-firmware (AUR) was NOT installed: Wi-Fi via b43 will not work until it is. Re-run this script."
    fi
    aur_install mbpfan || warn "mbpfan (AUR) was NOT installed: no custom fan control. Re-run this script, or skip it."
    install_configs
    kernel_param_step
    services_step
    user_step
    finish
}

if [[ ${MB81_SOURCE_ONLY:-0} != 1 ]]; then main "$@"; fi
