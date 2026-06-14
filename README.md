# zenith-os

Zenith OS - Complete Description
Overview
Zenith OS is a custom Linux-based operating system built on Ubuntu, designed to provide a seamless hybrid experience combining the best of macOS and Windows 11 aesthetics with powerful Linux functionality. It features a modern, polished user interface with pre-installed productivity tools, gaming support, and system utilities.

Key Features
Desktop Environment
GNOME Desktop Environment with custom hybrid macOS/Windows 11 theme
Windows 11-style taskbar with integrated system tray
Custom boot logo and splash screen featuring the Zenith OS branding
Mountain and galaxy backgrounds for a premium visual experience
Application Support
Windows Application Support: Pre-configured Wine and Proton for running Windows applications
Brave Browser: Pre-installed for secure, fast web browsing
Gaming Support: Includes Salad GPU miner for cryptocurrency mining
System Apps and Utilities: Comprehensive suite of productivity and system management tools
System Features
Software Update Checker: Built-in tool to keep the system updated
System Tweaks: Optimized sysctl settings for performance and usability
Custom System Sounds: Floaty ambient pad sounds for startup, shutdown, notifications, errors, success, warnings, and questions
Hybrid Boot Support: GPT and MBR hybrid support for maximum compatibility
Technical Specifications
Base Distribution: Ubuntu Linux
Kernel: Latest stable kernel with custom configurations
Package Management: APT with custom repositories
ISO Format: Hybrid ISO supporting both BIOS and UEFI boot
File System: SquashFS compressed filesystem for live environment
Custom Components
Zenith OS Branding: Custom logo, icons, and visual identity throughout the system
Custom Applications: Zenith-specific applications and utilities
Sound Theme: Unique floaty ambient pad sounds with +5 dB gain for clear audio feedback
Theme System: Custom GNOME theme blending macOS elegance with Windows 11 functionality
Installation & Deployment
Live ISO: Bootable live environment for testing and installation
USB Creation: Compatible with dd, Rufus, Etcher, and other USB creation tools
Virtualization: Tested and compatible with QEMU and other virtualization platforms

## Repairing live ISOs that kernel-panic on boot

The 1.0 release ISOs booted with `boot=casper` but shipped a plain local-boot
initrd that did not contain the casper live-boot scripts. The kernel is present
(`/casper/vmlinuz`), but boot panics early:

```
/init: .: can't open '/scripts/casper': No such file or directory
Kernel panic - not syncing: Attempted to kill init!
```

`scripts/fix-iso-kernel.sh` repairs an affected ISO in place by installing the
`casper` package into the squashfs root, regenerating a proper live initrd,
fixing the BIOS `isolinux.cfg` (it was missing the `initrd=` line) plus shipping
the required `ldlinux.c32`, and adding a matching `md5sum.txt`. The original
hybrid boot record is preserved.

```bash
# deps: xorriso squashfs-tools isolinux syslinux-common cpio
scripts/fix-iso-kernel.sh Zenith.OS-1.0-GPT.iso Zenith.OS-1.0-GPT-fixed.iso
scripts/fix-iso-kernel.sh Zenith.OS-1.0-MBR.iso Zenith.OS-1.0-MBR-fixed.iso
```

## Adding the GNOME desktop

The stock 1.0 root filesystem has no desktop environment installed, so even a
boot-fixed ISO lands on a text console. `scripts/add-desktop.sh` installs a
GNOME desktop (GDM3 with casper live autologin) and the Brave browser into the
squashfs root, regenerates the live initrd, and rebuilds the ISO (boot record
preserved). It supersedes `fix-iso-kernel.sh` (it also applies the boot fix).

```bash
# deps: xorriso squashfs-tools isolinux syslinux-common cpio curl
scripts/add-desktop.sh Zenith.OS-1.0-GPT.iso Zenith.OS-1.0-GPT-desktop.iso
scripts/add-desktop.sh Zenith.OS-1.0-MBR.iso Zenith.OS-1.0-MBR-desktop.iso
```

Custom Zenith branding (wallpapers, themes, taskbar) is not yet in this repo, so
the result is a stock GNOME desktop. The crypto miner mentioned in the feature
list is intentionally not bundled.
