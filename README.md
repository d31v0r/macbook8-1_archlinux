# Arch Linux on the MacBook Pro 8,1 (Early 2011, 13", A1278)

Configuration and notes for running current Arch Linux on the Early 2011 13" MacBook Pro (`MacBookPro8,1`).
This is a 2026 rewrite of the original 2015 guide by [gammy](https://github.com/gammy/macbook8-1_archlinux);
the old text and hardware dumps are kept in [`docs/legacy-2015/`](docs/legacy-2015/README.md).

> **Status:** written from the original repo, its hardware dumps, the ArchWiki
> ([MacBookPro8,x](https://wiki.archlinux.org/title/MacBookPro8,x), [Intel graphics](https://wiki.archlinux.org/title/Intel_graphics), [TLP](https://wiki.archlinux.org/title/TLP)),
> the [rEFInd SIP page](https://www.rodsbooks.com/refind/sip.html), the [b43 docs](https://wireless.docs.kernel.org/en/latest/en/users/drivers/b43.html) and current package listings (checked Sep 2026).
> **Not yet run on real hardware with a 2026 kernel.** Items marked **(verify)** are the likeliest to need adjusting. PRs with results welcome.

## Hardware (from the legacy `lspci`/`lsusb` dumps)

| Part | Device | Linux driver |
|---|---|---|
| GPU | Intel HD Graphics 3000 (no discrete GPU on the 13"); no Vulkan on this generation | `i915`, Mesa `crocus` (OpenGL) |
| Wi-Fi | Broadcom BCM4331 (`14e4:4331`) | `wl` (proprietary) or `b43` |
| Ethernet | Broadcom BCM57765 | `tg3` |
| SD card reader | Broadcom BCM57765/57785 SDXC | `sdhci-pci` (untested) |
| Bluetooth | Broadcom BCM2070 (USB `05ac:821a`) | `btusb` |
| Camera | FaceTime HD (USB `05ac:8509`) | `uvcvideo` |
| Keyboard/trackpad | Apple internal, ISO (USB `05ac:0253`) | `hid_apple`, `bcm5974` |
| IR receiver | Apple (USB `05ac:8242`) | `usbhid` |
| Extras | FireWire (LSI FW643), Thunderbolt 1 | untested |

## What changed since 2015

| 2015 guide | Now |
|---|---|
| `xf86-input-mtrack` (AUR) / synaptics | **libinput**, in-kernel `bcm5974`; see [`30-touchpad.conf`](cfg/root/etc/X11/xorg.conf.d/30-touchpad.conf) |
| `xf86-video-intel` | Xorg **modesetting** driver (default, recommended by the ArchWiki). `xf86-video-intel` is legacy and "generally not recommended"; if 3D is unstable on this old GPU the wiki also offers `mesa-amber` (legacy classic driver, unmaintained) |
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
cfg/root/        config installed by scripts/post-install.sh (or copy by hand: sudo cp -rv cfg/root/* /)
cfg/optional/    pick ONE Wi-Fi setup (wifi-wl or wifi-b43), same copy method
cfg/examples/    example ~/.xinitrc, ~/.xbindkeysrc, and an X11 keyboard-layout file (edit before use)
cfg/legacy/      the original pekwm/lightdm/powertop/.Xdefaults files, unchanged
scripts/         post-install.sh (the automated setup), check.sh (health check), collect-hwinfo.sh (regenerates the old dumps)
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

- **Reuse the existing ESP** (`/dev/sda1`, FAT32, small: about 200 MB on stock Macs, check with `lsblk`) and mount it at `/boot` or `/efi`. Don't create a second one. If you mount it at `/boot`, kernel + initramfs + fallback initramfs can fill 200 MB; consider `/efi` for the ESP and keeping `/boot` on the root filesystem (rEFInd then needs its filesystem driver, e.g. btrfs).
- Add your Linux partitions in the free space (`gdisk`/`cfdisk`). The 2015 layout (swap + btrfs root + btrfs home) is still a fine example.
- The BCM4331 Wi-Fi may not come up on the installer ISO (the ArchWiki suggests switching from `b43`/`bcma` to `wl`, which needs the DKMS package, so not possible from the ISO alone). Use the built-in **Gigabit Ethernet** port (BCM57765, `tg3`, works out of the box) or USB tethering from a phone.
- Include `linux linux-firmware linux-headers dkms broadcom-wl-dkms networkmanager` in `pacstrap` if you want Wi-Fi to work on first boot (see [Wi-Fi](#wi-fi)).
- Don't bother with GRUB here; rEFInd is simpler on a Mac (next step).

### 3. Boot manager: rEFInd

Install [rEFInd](https://www.rodsbooks.com/refind/installing.html#osx) from **macOS** onto the existing ESP, as in the original guide (manual `bless --setBoot` or the `refind-install` script). From macOS 10.11 on, System Integrity Protection blocks `bless`, so the installer has to be run from **Recovery mode** (Cmd+R, then Terminal), with SIP disabled, or from another OS. rEFInd's author recommends trying Recovery mode first. See [rEFInd: SIP](https://www.rodsbooks.com/refind/sip.html).

rEFInd auto-detects `vmlinuz-linux` + `initramfs-linux.img`. If `/boot` is on a btrfs/ext4 root (not on the ESP), enable the matching rEFInd filesystem driver. To set the kernel command line, put it in `/boot/refind_linux.conf`:

```
"Boot with defaults" "root=UUID=<your-root-uuid> rw acpi_backlight=native"
```

`acpi_backlight=native`: per the ArchWiki, since kernel 6.1 this model needs it for working display brightness. Check `ls /sys/class/backlight/` first; you want `intel_backlight`. **(verify)**

If the initramfs can't find the root filesystem, add `ahci` to `MODULES=()` in `/etc/mkinitcpio.conf` and run `mkinitcpio -P` (an old ArchWiki tip for this model, probably unnecessary now).

### 4. Post-install (automated)

After the first boot into the installed system (network via Ethernet), as your normal user with `sudo`:

```sh
sudo pacman -S --needed git
git clone <this repo> && cd macbook8-1_archlinux
sudo ./scripts/post-install.sh --dry-run     # read what it will do first
sudo ./scripts/post-install.sh --x11 --layouts us,ru
sudo reboot
./scripts/check.sh                           # after the reboot
```

Options: `--wifi wl|b43|none` (default `wl`), `--x11`/`--no-x11`, `--no-extras`, `--layouts`, `--sleep-hook`, `--user`, `--yes`, `--force`, `--dry-run`. `--help` lists them.
What it does, step by step, is in [`docs/REPORT.md`](docs/REPORT.md). It is idempotent, keeps `.bak` copies of any file it overwrites, refuses to run on anything but a `MacBookPro8,1` (unless `--force`), and never touches partitions or boot-loader binaries.

`scripts/check.sh` is a read-only health check (Wi-Fi driver bound, backlights, applesmc/coretemp, TLP, PipeWire, ...).

<details><summary>Doing it by hand instead</summary>

```sh
sudo pacman -Syu --needed base-devel git dkms brightnessctl tlp lm_sensors bluez bluez-utils networkmanager \
    pipewire pipewire-pulse pipewire-alsa wireplumber mesa libva-intel-driver intel-ucode \
    xorg-server xorg-xinit xorg-apps xf86-input-libinput xbindkeys        # X11 only
sudo systemctl enable NetworkManager tlp bluetooth
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket           # required by TLP's docs
sudo cp -rv cfg/root/* /
sudo usermod -aG video "$USER"
sudo mkinitcpio -P
```

then Wi-Fi as below, `mbpfan` from the AUR, and `acpi_backlight=native` only if `/sys/class/backlight/intel_backlight` is missing.
</details>

## Wi-Fi

The BCM4331 is the awkward part of this machine, as in 2015. Pick **one**:

**A) `wl`, the proprietary driver (the ArchWiki's suggestion for this chip; full 5 GHz and 802.11n)**

```sh
# stock `linux` kernel: prebuilt module
sudo pacman -S broadcom-wl
# any other kernel (linux-lts, ...): DKMS
#   sudo pacman -S dkms linux-lts-headers broadcom-wl-dkms
sudo cp -rv cfg/optional/wifi-wl/etc/* /etc/       # extra blacklist, see note
sudo mkinitcpio -P && sudo reboot
```

Both packages are in the official `extra` repo (the DKMS one was last rebuilt in June 2026, with a newer build in `extra-testing` in August 2026). The DKMS package already ships its own blacklist in `/usr/lib/modprobe.d/`, so `cfg/optional/wifi-wl/etc/modprobe.d/broadcom-wl.conf` is a belt-and-braces duplicate. It is still a closed-source, frozen (6.30.223.271) out-of-tree driver, so a new kernel can break it. Keep `linux-lts` around as a fallback. A Manjaro thread reports freezes on kernel 6.6.5 with `wl` while 6.5.13 was fine. **(verify)**

If the machine hangs on resume while Wi-Fi reconnects (this was the 2015 problem), also install the systemd sleep hook:

```sh
sudo install -m755 cfg/optional/wifi-wl/usr/lib/systemd/system-sleep/wl-reload /usr/lib/systemd/system-sleep/
```

**B) `b43` (in-kernel, needs firmware from the AUR)**

```sh
sudo pacman -Rns broadcom-wl-dkms                  # (or broadcom-wl) if installed
sudo rm -f /etc/modprobe.d/broadcom-wl.conf        # do NOT blacklist bcma/b43 here: b43 needs bcma for the BCM4331
paru -S b43-firmware
sudo cp -rv cfg/optional/wifi-b43/etc/* /etc/
sudo reboot
```

The BCM4331 is supported by `b43` (kernel 3.2+), but the kernel's own b43 page lists limits for this HT-PHY chip: **no 5 GHz and no 802.11n features** (no HT, aggregation, 40 MHz). Expect 2.4 GHz at roughly 802.11g speeds. That is why `wl` is the usual choice.

The 2015 author gave up on both and bought a USB adapter (D-Link DWA-171, Realtek 8812AU). That's still the boring option. Use any adapter with an in-kernel driver, or the AUR `rtl8812au` DKMS packages if that's what you have.

## Keyboard and trackpad

- **F-keys:** [`hid_apple.conf`](cfg/root/etc/modprobe.d/hid_apple.conf) sets `fnmode=2` (F1-F12 by default, Fn for media keys). Change it to taste. The ISO layout's swapped `` ` ``/`<` is fixed with `iso_layout=0` (commented example in the same file).
- **Layouts:** [`cfg/examples/xorg-keyboard.conf`](cfg/examples/xorg-keyboard.conf) is an *example* (`us,ru`, Alt+Shift), not installed by the copy step. Copy it to `/etc/X11/xorg.conf.d/00-keyboard.conf` after editing, or just use `localectl set-x11-keymap`.
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

The keys emit the standard `XF86*` symbols. Nothing acts on them unless your desktop or WM does. Desktop environments handle them for you. For a bare X11 WM, `post-install.sh --x11` installs [`cfg/examples/xbindkeysrc`](cfg/examples/xbindkeysrc) as `~/.xbindkeysrc` (start `xbindkeys &`). For Wayland or a WM with its own keybindings, bind:

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

This resolves the "Work in progress" item from 2015: keyboard-backlight keys don't produce ACPI events, but they do produce input events, so the WM binding + the [udev rule](cfg/root/etc/udev/rules.d/91-kbd-backlight.rules) (write access for group `video`) is all that's needed.

## Power and thermals

- Use **TLP**, or `power-profiles-daemon`, not both. TLP's defaults already apply Powertop's recommendations (ArchWiki), so a separate `powertop --auto-tune` service is redundant, and aggressive USB autosuspend can make input devices or Bluetooth flaky (TLP has `USB_DENYLIST` for that). The 2015 service is kept at [`cfg/legacy/powertop.service`](cfg/legacy/powertop.service) for reference.
- Sensors and fans: `sudo sensors-detect`, then `sensors` (`applesmc` and `coretemp` show up). For custom fan curves there's `mbpfan` in the AUR (its README lists a 13" MBP 8,1 as tested, on kernel 3.2). This machine is 15 years old, so if it runs hot after a decade, fresh thermal paste does more than any daemon.
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
