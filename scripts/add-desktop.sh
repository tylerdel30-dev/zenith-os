#!/usr/bin/env bash
#
# add-desktop.sh
#
# Installs a GNOME desktop (GDM3 + GNOME Shell, with casper live autologin) and
# the Brave browser into a Zenith OS live ISO's squashfs root, then rebuilds the
# ISO. Use this together with / after fix-iso-kernel.sh: the stock 1.0 rootfs has
# no desktop installed, so the live session would otherwise boot to a text
# console instead of the GNOME desktop described in the README.
#
# This regenerates the (casper) initrd as part of installing the desktop, so the
# resulting ISO is both bootable and graphical.
#
# Usage:
#   scripts/add-desktop.sh <input.iso> <output.iso>
#
# Requires (Debian/Ubuntu host): xorriso squashfs-tools isolinux syslinux-common cpio curl
#
set -euo pipefail

IN_ISO="${1:?usage: add-desktop.sh <input.iso> <output.iso>}"
OUT_ISO="${2:?usage: add-desktop.sh <input.iso> <output.iso>}"

WORK="$(mktemp -d)"
trap 'sudo umount -R "$WORK/root"/{dev/pts,dev,proc,sys} 2>/dev/null || true; sudo rm -rf "$WORK"' EXIT

echo ">> Extracting squashfs from $IN_ISO"
xorriso -osirrox on -indev "$IN_ISO" -extract /casper/filesystem.squashfs "$WORK/filesystem.squashfs"
sudo unsquashfs -d "$WORK/root" "$WORK/filesystem.squashfs"

echo ">> Installing GNOME desktop + Brave inside the rootfs"
sudo mount --bind /dev      "$WORK/root/dev"
sudo mount --bind /dev/pts  "$WORK/root/dev/pts"
sudo mount -t proc  proc    "$WORK/root/proc"
sudo mount -t sysfs sys     "$WORK/root/sys"
sudo cp -f /etc/resolv.conf "$WORK/root/etc/resolv.conf"

sudo chroot "$WORK/root" /bin/bash -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
apt-get update

# casper provides the live-boot initramfs scripts + live autologin setup.
apt-get install -y casper

# GNOME desktop (no-recommends keeps it lean and avoids pulling snap packages,
# which cannot be seeded reliably inside a chroot).
apt-get install -y --no-install-recommends \
    ubuntu-desktop-minimal gdm3 gnome-shell gnome-session gnome-control-center \
    gnome-terminal nautilus gnome-text-editor network-manager-gnome \
    xserver-xorg xserver-xorg-video-all gnome-backgrounds plymouth-theme-spinner

# Brave browser (README lists it as the default browser).
apt-get install -y curl
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update
apt-get install -y brave-browser

systemctl set-default graphical.target
update-initramfs -u -k all
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT

KVER="$(sudo chroot "$WORK/root" bash -c 'ls /boot/vmlinuz-* | sed s,.*/vmlinuz-,, | head -1')"
sudo cp "$WORK/root/boot/initrd.img-$KVER" "$WORK/initrd.img"
sudo chown "$(id -u):$(id -g)" "$WORK/initrd.img"

sudo umount -R "$WORK/root"/{dev/pts,dev,proc,sys}
sudo truncate -s 0 "$WORK/root/run/systemd/resolve/stub-resolv.conf" 2>/dev/null || true

echo ">> Repacking squashfs (xz, 1M blocks)"
sudo mksquashfs "$WORK/root" "$WORK/new.squashfs" -comp xz -b 1M -noappend
sudo chown "$(id -u):$(id -g)" "$WORK/new.squashfs"

UPDATES=(-update "$WORK/new.squashfs" /casper/filesystem.squashfs
         -update "$WORK/initrd.img"   /casper/initrd.img)

if xorriso -indev "$IN_ISO" -find /isolinux/isolinux.bin 2>/dev/null | grep -q isolinux.bin; then
  echo ">> Repairing BIOS/isolinux boot configuration"
  cat > "$WORK/isolinux.cfg" <<'CFG'
DEFAULT live
PROMPT 0
TIMEOUT 50

LABEL live
  MENU LABEL Start Zenith OS
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd.img boot=casper quiet splash ---

LABEL try
  MENU LABEL Try Zenith OS without installing
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd.img boot=casper quiet splash ---
CFG
  cp /usr/lib/ISOLINUX/isolinux.bin "$WORK/isolinux.bin"
  cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$WORK/ldlinux.c32"
  UPDATES+=(-update "$WORK/isolinux.cfg" /isolinux/isolinux.cfg
            -update "$WORK/isolinux.bin" /isolinux/isolinux.bin
            -update "$WORK/ldlinux.c32"  /isolinux/ldlinux.c32)
fi

echo ">> Rebuilding ISO (boot record preserved)"
rm -f "$OUT_ISO"
xorriso -indev "$IN_ISO" -outdev "$OUT_ISO" -boot_image any replay "${UPDATES[@]}" -commit

echo ">> Generating and embedding md5sum.txt"
TREE="$WORK/tree"; mkdir -p "$TREE"
xorriso -osirrox on -indev "$OUT_ISO" -extract / "$TREE"
( cd "$TREE" && find . -type f ! -name md5sum.txt ! -path './boot.catalog' \
    ! -path './isolinux/boot.cat' -print0 | xargs -0 md5sum | sort -k2 ) > "$WORK/md5sum.txt"
xorriso -indev "$OUT_ISO" -outdev "$OUT_ISO.tmp" -boot_image any replay \
    -update "$WORK/md5sum.txt" /md5sum.txt -commit
mv "$OUT_ISO.tmp" "$OUT_ISO"

echo ">> Done: $OUT_ISO"
