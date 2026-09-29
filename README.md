# Arch Linux on the MacBook Pro 8,1 (Early 2011, 13", A1278)

Configuration and notes for running current Arch Linux on the Early 2011 13" MacBook Pro (`MacBookPro8,1`).
This is a 2026 rewrite of the original 2015 guide by [gammy](https://github.com/gammy/macbook8-1_archlinux);
the old text and hardware dumps are kept in [`docs/legacy-2015/`](docs/legacy-2015/README.md).

> **Status:** rewritten from the original repo, the hardware dumps in it, and the current ArchWiki
> ([MacBookPro8,x](https://wiki.archlinux.org/title/MacBookPro8,x)). Not yet re-verified on real hardware with a 2026 kernel.
> Items marked **(verify)** are the ones most likely to need adjusting. PRs with results welcome.

## Hardware (from the legacy `lspci`/`lsusb` dumps)

| Part | Device | Linux driver |
|---|---|---|
| GPU | Intel HD Graphics 3000 (no discrete GPU on the 13") | `i915`, Mesa `crocus` |
| Wi-Fi | Broadcom BCM4331 (`14e4:4331`) | `wl` (proprietary) or `b43` |
| Ethernet / SD reader | Broadcom BCM57765 | `tg3` |
| Bluetooth | Broadcom BCM2070 (USB `05ac:821a`) | `btusb` |
| Camera | FaceTime HD (USB `05ac:8509`) | `uvcvideo` |
| Keyboard/trackpad | Apple internal, ISO (USB `05ac:0253`) | `hid_apple`, `bcm5974` |
| IR receiver | Apple (USB `05ac:8242`) | `usbhid` |
| Extras | FireWire (LSI FW643), Thunderbolt 1 | untested |

## What changed since 2015

| 2015 guide | Now |
|---|---|
| `xf86-input-mtrack` (AUR) / synaptics | **libinput**, in-kernel `bcm5974`; see [`30-touchpad.conf`](cfg/root/etc/X11/xorg.conf.d/30-touchpad.conf) |
| `xf86-video-intel` | Xorg **modesetting** driver (default). Keep `xf86-video-intel` only as a fallback if you see tearing/glitches |
| `xorg-server-utils` | Gone; use `xorg-apps` |
| `yaourt` | `paru` or `yay` (or build from the AUR by hand) |
| `wicd` | **NetworkManager** or **iwd** |
| `pm-utils`, `uswsusp` | `systemd-logind` suspend (lid close works out of the box); systemd sleep hooks if needed |
| LightDM + `wicd-gtk` + `devmon` | Your choice of greeter (greetd, SDDM, GDM, ly, ...) or just `startx`; `udiskie` for automount |
| `pulseaudio` started from the WM script | **PipeWire** + WirePlumber, started by systemd user units |
| `powertop --auto-tune` service | **TLP** (or `power-profiles-daemon`); don't run more than one |
| `redshift` | `gammastep` (works on X11 and Wayland) |
| Kernel params `i915.i915_enable_rc6=1 i915.lvds_downclock=1 ...` | Not needed by default. `i915.enable_fbc=1` is optional; ArchWiki warns it can cause stutter/freezes with some apps |
| Keyboard backlight only via `root` + `/sys` | udev rule + `brightnessctl`, no root needed |

## Repository layout

```
cfg/root/        safe defaults, copy onto / after reading them:   sudo cp -rv cfg/root/* /
cfg/optional/    pick ONE Wi-Fi setup (wifi-wl or wifi-b43), same copy method
cfg/examples/    example ~/.xinitrc (bare X11 WM)
cfg/legacy/      the original pekwm/lightdm/powertop/.Xdefaults files, unchanged
scripts/         collect-hwinfo.sh: regenerates the dumps in docs/legacy-2015/output/
docs/legacy-2015 the original README and lspci/lsusb/dmesg output (kernel 3.18, 2015)
```

## Installation

### 1. Prepare macOS

- The last macOS this model officially supports is **High Sierra 10.13**. Keep it if you want dual boot.
- In Disk Utility, shrink the macOS volume to make room. Leave the EFI system partition and the macOS partitions alone.
- Write the Arch ISO to a USB stick (`dd`, balenaEtcher, ...), power on holding **Option (Alt)**, choose the stick (shown as "EFI Boot").

### 2. Install Arch

Use `archinstall` or the [manual installation guide](https://wiki.archlinux.org/title/Installation_guide).
Mac-specific points:

- **Reuse the existing ESP** (`/dev/sda1`, ~200 MB, FAT32) and mount it at `/boot` or `/efi`. Don't create a second one.
- Add your Linux partitions in the free space (`gdisk`/`cfdisk`). The 2015 layout (swap + btrfs root + btrfs home) is still a fine example.
- The installer ISO can't drive the BCM4331 Wi-Fi out of the box (wiki: switch from `b43`/`bcma` to `wl`). Use the built-in **Gigabit Ethernet** port (BCM57765, `tg3`, works out of the box) or USB tethering from a phone.
- Include `linux linux-firmware linux-headers dkms broadcom-wl-dkms networkmanager` in `pacstrap` if you want Wi-Fi to work on first boot (see [Wi-Fi](#wi-fi)).
- Don't bother with GRUB here; rEFInd is simpler on a Mac (next step). If you prefer GRUB, install it to the ESP with `--removable`.

### 3. Boot manager: rEFInd

Install [rEFInd](https://www.rodsbooks.com/refind/installing.html#osx) from **macOS** onto the existing ESP, as in the original guide (manual `bless --setBoot` or the `refind-install` script). On macOS 10.11 and newer, System Integrity Protection can block `bless`; the rEFInd page describes running the installer from Recovery. **(verify on your macOS version)**

rEFInd normally auto-detects `vmlinuz-linux` + `initramfs-linux.img` in the same directory. Mounting the ESP at `/boot` is the simplest layout. If your `/boot` lives on the btrfs/ext4 root instead, enable the matching rEFInd filesystem driver. To set the kernel command line, put it in `/boot/refind_linux.conf`:

```
"Boot with defaults" "root=UUID=<your-root-uuid> rw acpi_backlight=native"
```

`acpi_backlight=native`: per the ArchWiki, since kernel 6.1 this model needs it for working display brightness. Check `ls /sys/class/backlight/` first; you want `intel_backlight`. **(verify)**

If the initramfs can't find the root filesystem, add `ahci` to `MODULES=()` in `/etc/mkinitcpio.conf` and run `mkinitcpio -P` (an old ArchWiki tip for this model, probably unnecessary now).

### 4. Post-install

```sh
# base desktop bits (X11 path; for Wayland skip xorg-* and see below)
sudo pacman -S mesa xorg-server xorg-xinit xorg-apps xf86-input-libinput ttf-dejavu

# sound
sudo pacman -S pipewire pipewire-pulse wireplumber pavucontrol

# network (NetworkManager; iwd alone also works, but needs EnableNetworkConfiguration=true in /etc/iwd/main.conf)
sudo pacman -S networkmanager
sudo systemctl enable --now NetworkManager

# power, sensors, misc
sudo pacman -S tlp lm_sensors brightnessctl udiskie gammastep bluez bluez-utils
sudo systemctl enable --now tlp bluetooth
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket   # required by TLP's docs

# my configs (read them first!)
git clone https://github.com/gammy/macbook8-1_archlinux && cd macbook8-1_archlinux   # or your fork
sudo cp -rv cfg/root/* /
sudo usermod -aG video "$USER"
sudo mkinitcpio -P
sudo udevadm control --reload && sudo udevadm trigger
```

Then reboot.

## Wi-Fi

The BCM4331 is the awkward part of this machine, as in 2015. Pick **one**:

**A) `wl`, the proprietary driver (recommended by the ArchWiki for this chip)**

```sh
sudo pacman -S dkms linux-headers broadcom-wl-dkms
sudo cp -rv cfg/optional/wifi-wl/etc/* /etc/       # blacklists the competing in-kernel modules
sudo mkinitcpio -P && sudo reboot
```

`broadcom-wl-dkms` is in the official repos, but it's an out-of-tree, frozen driver. New kernels occasionally break the build or the runtime. Keep `linux-lts` + `linux-lts-headers` installed as a fallback. Forum reports exist of freezes on a specific kernel while a neighbouring one worked (Manjaro, kernel 6.6.5 vs 6.5.13). **(verify)**

If the machine hangs on resume while Wi-Fi reconnects (this was the 2015 problem), also install the systemd sleep hook:

```sh
sudo install -m755 cfg/optional/wifi-wl/usr/lib/systemd/system-sleep/wl-reload /usr/lib/systemd/system-sleep/
```

**B) `b43` (in-kernel, needs firmware from the AUR)**

```sh
sudo pacman -Rns broadcom-wl-dkms                  # if installed; also remove the wifi-wl blacklist file
paru -S b43-firmware
sudo cp -rv cfg/optional/wifi-b43/etc/* /etc/
sudo reboot
```

Reports about BCM4331 on `b43` are mixed; the 2015 author gave up on both drivers and bought a USB adapter (D-Link DWA-171, Realtek 8812AU). That's still the boring, reliable option: `paru -S rtl8812au-dkms-git` or any adapter with an in-kernel driver.

## Keyboard and trackpad

- **F-keys:** [`hid_apple.conf`](cfg/root/etc/modprobe.d/hid_apple.conf) sets `fnmode=2` (F1-F12 by default, Fn for media keys). Change it to taste. The ISO layout's swapped `` ` ``/`<` is fixed with `iso_layout=0` (commented example in the same file).
- **Layouts:** [`00-keyboard.conf`](cfg/root/etc/X11/xorg.conf.d/00-keyboard.conf) is an *example* (`us,ru`, Alt+Shift). Edit it or use `localectl set-x11-keymap`.
- **Trackpad:** libinput handles palm rejection, thumbs and gestures itself. The provided config gives: tap = left, two-finger tap = middle, three-finger tap = right; physical click with one/two/three fingers = left/right/middle. That mirrors the old `mtrack` layout. "Cmd+click to move window" was a WM binding, not a driver feature: bind your WM's modifier to Super/Cmd (`hid_apple swap_opt_cmd=1` if you want).
- **Wayland (sway example):**

  ```
  input type:touchpad {
      tap enabled
      tap_button_map lmr
      click_method clickfinger
      natural_scroll enabled
      dwt enabled
  }
  input type:keyboard {
      xkb_layout us,ru
      xkb_options grp:alt_shift_toggle
  }
  ```

## Backlights and media keys

The keys emit the standard `XF86*` symbols. Nothing acts on them unless your desktop or WM does. Desktop environments handle them for you. For a bare WM, bind them:

```
XF86MonBrightnessUp    -> brightnessctl set 5%+
XF86MonBrightnessDown  -> brightnessctl set 5%-
XF86KbdBrightnessUp    -> brightnessctl -d 'smc::kbd_backlight' set 10%+
XF86KbdBrightnessDown  -> brightnessctl -d 'smc::kbd_backlight' set 10%-
XF86AudioRaiseVolume   -> wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
XF86AudioLowerVolume   -> wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
XF86AudioMute          -> wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
XF86AudioPlay/Prev/Next-> playerctl play-pause / previous / next
XF86Eject              -> eject
```

This resolves the "Work in progress" item from 2015: keyboard-backlight keys don't produce ACPI events, but they do produce input events, so the WM binding + the [udev rule](cfg/root/etc/udev/rules.d/90-kbd-backlight.rules) (write access for group `video`) is all that's needed.

## Power and thermals

- Use **TLP**, or `power-profiles-daemon`, not both, and not `powertop --auto-tune` on top. Auto-tune puts USB input devices into autosuspend, which can make an external mouse/keyboard laggy. The 2015 service is kept at [`cfg/legacy/powertop.service`](cfg/legacy/powertop.service) for reference.
- Sensors and fans: `sudo sensors-detect`, then `sensors` (`applesmc` and `coretemp` show up). For custom fan curves there's `mbpfan` in the AUR. This machine is 15 years old, so if it runs hot after a decade, fresh thermal paste does more than any daemon.
- Suspend: lid-close suspend is handled by `systemd-logind`. Test suspend/resume with both AC and battery.

## Status of hardware

**Worked in 2015, no known blockers now:** video, audio (speakers + jack), webcam, Ethernet, optical drive, multitouch, brightness, suspend, most IR remote buttons.

**Needs care:** Wi-Fi (see above), keyboard backlight/brightness keys (need bindings), HDMI audio (2015 dmesg has `HDMI: invalid ELD data byte 0` spam, harmless but noisy).

**Untested:** Bluetooth (ArchWiki reports pairing trouble with `b43`, see Troubleshooting), SD reader, Thunderbolt, FireWire, SPDIF (red LED lights up when the optical jack is in use), hibernate.

## Troubleshooting

- **No `intel_backlight`:** add `acpi_backlight=native` (see above).
- **Black screen / no display under EFI boot:** that's the 15"/17" models' problem (AMD + Intel). The 13" 8,1 has only the Intel GPU. Don't copy `radeon.modeset=0` / `i915.modeset=0` advice from other 8,x pages.
- **Wi-Fi interface missing (`ip link`):** `lspci -k -s 03:00.0` shows which driver is bound. Make sure only one of `wl` / `b43` is loaded and that competing modules are blacklisted.
- **Bluetooth pairing fails with `b43`:** `options b43 btcoex=0` (already in `cfg/optional/wifi-b43`).
- **HFS+ macOS partition mounts read-only:** turn journaling off in macOS, or just leave it alone.

## Resources

- [ArchWiki: MacBookPro8,x](https://wiki.archlinux.org/title/MacBookPro8,x)
- [ArchWiki: Broadcom wireless](https://wiki.archlinux.org/title/Broadcom_wireless)
- [ArchWiki: Backlight](https://wiki.archlinux.org/title/Backlight), [libinput](https://wiki.archlinux.org/title/Libinput), [TLP](https://wiki.archlinux.org/title/TLP), [rEFInd](https://wiki.archlinux.org/title/REFInd)
- [rEFInd install docs](https://www.rodsbooks.com/refind/installing.html)
- Original repo: [gammy/macbook8-1_archlinux](https://github.com/gammy/macbook8-1_archlinux)

## License / credits

The original repository does not declare a license. Original content and hardware dumps are by gammy and kept under `docs/legacy-2015/` and `cfg/legacy/`. If you publish this rewrite, keep the attribution, and ideally ask the author for permission or open a PR against the original.
