# What `scripts/post-install.sh` sets up

Status: the script is shellcheck-clean and was tested against fixture files (boot-loader editing, idempotency),
a fake root directory and `--dry-run`. It has **not** been run on a real MacBookPro8,1 with real `pacman`.
Sources: ArchWiki (MacBookPro8,x, Intel graphics, Backlight, TLP, Broadcom wireless, Hardware video acceleration),
rEFInd docs, brightnessctl README, package listings (29 Sep 2026: `linux` 7.2.7, `linux-lts` 6.18.54, `broadcom-wl-dkms` 6.30.223.271-50).

## Done automatically

| Area | What the script does | Source / reason |
|---|---|---|
| Safety | Refuses to run unless DMI product is `MacBookPro8,1` (`--force` overrides). Backs up overwritten files as `*.bak`. Re-running changes nothing that is already in place. | 15"/17" 8,2/8,3 have an AMD GPU |
| Packages | `pacman -Syu --needed`: base-devel git dkms brightnessctl tlp lm_sensors bluez bluez-utils networkmanager pipewire pipewire-pulse pipewire-alsa wireplumber mesa libva-intel-driver intel-ucode; with `--x11`: xorg-server xorg-xinit xorg-apps xf86-input-libinput xbindkeys; extras: pavucontrol playerctl udiskie gammastep ttf-dejavu libva-utils | full upgrade, never a partial one |
| Graphics | Xorg modesetting driver (no `xf86-video-intel`), Mesa `crocus`, VA-API via `libva-intel-driver` (Wiki: GMA 4500 up to Coffee Lake) | ArchWiki: Intel graphics, Hardware video acceleration |
| Wi-Fi (default `wl`) | `linux-lts` + `linux-lts-headers` + `broadcom-wl-dkms`. Headers for other installed kernels only when that kernel is older than 7.2 (`strncpy` was removed; wl 6.30.223.271 does not build). Blacklist of competing modules, plus `keep-tg3.conf` so BCM57765 Ethernet stays up. rEFInd `default_selection vmlinuz-linux-lts` when `refind.conf` is found | Linux 7.2 strncpy removal; ArchWiki: MacBookPro8,x; FS#70476 |
| Wi-Fi (`--wifi b43`) | `b43-fwcutter`, AUR `b43-firmware`, `btcoex=0`, removes the `wl` package, its blacklist and `keep-tg3.conf`. In-kernel, so Linux 7.2 is fine | ArchWiki + kernel b43 docs; no 5 GHz, no 802.11n on this chip |
| Network | Enables NetworkManager, unless another manager (systemd-networkd, iwd, dhcpcd, connman, wicd) is already enabled, then it warns and leaves it alone | avoids two managers fighting |
| Bluetooth | `bluez`, `bluetooth.service` enabled; TLP `USB_EXCLUDE_BTUSB=1`; `options btusb enable_autosuspend=0` because the driver turns autosuspend back on | TLP 1.10 |
| Sound | PipeWire + WirePlumber + pulse/alsa shims; user units enabled globally | |
| Keyboard | `/etc/modprobe.d/hid_apple.conf`: `fnmode=2` (F1-F12 by default, Fn for media keys). `--layouts us,ru` runs `localectl set-x11-keymap` with Alt+Shift toggle | ArchWiki: MacBookPro8,x |
| Trackpad (X11) | `/etc/X11/xorg.conf.d/30-touchpad.conf`: libinput, tap, two-finger tap = middle, three-finger tap = right, clickfinger, natural scroll, disable-while-typing | replaces mtrack/synaptics |
| Display brightness | `brightnessctl` (its udev rules cover the `video` group); `acpi_backlight=native` is added to the boot loader **only if** `intel_backlight` is missing | ArchWiki: MacBookPro8,x, Backlight |
| Keyboard backlight | udev rule `91-kbd-backlight.rules` (group `video`, runs after brightnessctl's own rule); your user is added to `video` | Backlight wiki: chgrp/chmod via RUN |
| Hotkeys (X11) | `~/.xbindkeysrc` for brightness, keyboard backlight, volume, mute, media, eject (only if the file doesn't exist) | needed on bare WMs; DEs handle these keys |
| Power | TLP enabled; `systemd-rfkill` service and socket masked; `power-profiles-daemon` masked if present | ArchWiki: TLP |
| Sensors / fans | `applesmc` and `coretemp` loaded at boot; AUR `mbpfan` built as your user and enabled | mbpfan README (lists 13" MBP 8,1) |
| SSD | `fstrim.timer` enabled only if a rotational=0 disk is found | |
| Suspend | Lid-close suspend is `systemd-logind`'s default: nothing to set. Optional `--sleep-hook` installs a `wl` unload/reload hook | hook is unverified |
| Boot loader | Adds the backlight parameter (only if needed) to `/boot/refind_linux.conf` (each entry), `/etc/default/grub` (+ `grub-mkconfig`) or systemd-boot entries. GRUB is regenerated so `intel-ucode` is picked up | tested on fixtures |
| Finish | `mkinitcpio -P` when a module config changed, reload udev, print notes | |

## Not automated, on purpose

- Shrinking macOS, partitioning, the Arch base install, user creation, locale and timezone (use `archinstall` or the installation guide; see the README).
- **rEFInd installation.** It must be done from macOS Recovery (SIP blocks `bless`). The Wiki warns that `efibootmgr` can upset Mac firmware, so the script never runs `refind-install` or `efibootmgr`.
- **Microcode for rEFInd / systemd-boot:** `intel-ucode` is installed, but you have to add its `initrd=` line yourself. Only GRUB does this automatically.
- Choosing a desktop or window manager. Wayland compositors need their own touchpad/keyboard config (sway example in the README).
- Hibernate, Thunderbolt, FireWire, SPDIF: untested on this machine.
- If `refind_linux.conf` doesn't exist, the script can't safely invent one (the `initrd=` path depends on your layout). It tells you what to add.

## Known risks

- **BCM4331 + `wl`:** the driver does not build on Linux 7.2+ (`strncpy` was removed). The script installs `linux-lts` (6.18.x as of 29 Sep 2026) and boots that. It also has no WPA3 and no 802.11w. When `linux-lts` itself reaches 7.2, this breaks again until Arch patches the package.
- **AUR packages** (`mbpfan`, `b43-firmware`) are unreviewed. The script pauses so you can read the PKGBUILD (`--yes` skips this). If AUR is unreachable, the rest still gets installed and you get a warning.
- `pacman -Syu` upgrades the whole system, so a reboot may switch you to a new kernel.
- Everything marked unverified above needs a real run. `scripts/check.sh` reports what came up. Please open an issue with its output.
