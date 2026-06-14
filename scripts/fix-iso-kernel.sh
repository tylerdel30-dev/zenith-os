#!/usr/bin/env bash
#
# fix-iso-kernel.sh
#
# Repairs a Zenith OS live ISO that boots with "boot=casper" but ships a plain
# local-boot initrd (no casper live-boot scripts). Such an ISO contains a valid
# kernel (/casper/vmlinuz) yet kernel-panics on boot:
#
#   /init: .: line N: can't open '/scripts/casper': No such file or directory
#   Kernel panic - not syncing: Attempted to kill init!
#
# The fix:
#   1. Extract the squashfs root filesystem.
#   2. Install the `casper` package into it (provides the live-boot initramfs
#      scripts) and regenerate the initrd so it actually contains /scripts/casper.
#   3. Repack the squashfs.
#   4. For BIOS/isolinux ISOs, fix isolinux.cfg (the original is missing the
#      `initrd=` line and references a non-existent menu module) and add the
#      required ldlinux.c32.
#   5. Add a matching md5sum.txt so casper-md5check passes.
#   6. Rebuild the ISO, preserving the original El Torito / hybrid boot record.
#
# Usage:
#   scripts/fix-iso-kernel.sh <input.iso> <output.iso>
#
# Requires (Debian/Ubuntu): xorriso squashfs-tools isolinux syslinux-common cpio
#
set -euo pipefail

IN_ISO="${1:?usage: fix-iso-kernel.sh <input.iso> <output.iso>}"
OUT_ISO="${2:?usage: fix-iso-kernel.sh <input.iso> <output.iso>}"

WORK="$(mktemp -d)"
trap 'sudo umount -R "$WORK/root"/{dev/pts,dev,proc,sys} 2>/dev/null || true; sudo rm -rf "$WORK"' EXIT

echo ">> Extracting squashfs from $IN_ISO"
xorriso -osirrox on -indev "$IN_ISO" -extract /casper/filesystem.squashfs "$WORK/filesystem.squashfs"
sudo unsquashfs -d "$WORK/root" "$WORK/filesystem.squashfs"

echo ">> Installing casper + regenerating the live initrd inside the rootfs"
sudo mount --bind /dev      "$WORK/root/dev"
sudo mount --bind /dev/pts  "$WORK/root/dev/pts"
sudo mount -t proc  proc    "$WORK/root/proc"
sudo mount -t sysfs sys     "$WORK/root/sys"
sudo cp -f /etc/resolv.conf "$WORK/root/etc/resolv.conf"

sudo chroot "$WORK/root" /bin/bash -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y casper
update-initramfs -u -k all
apt-get clean
CHROOT

# Pull the freshly generated casper initrd out for the ISO.
KVER="$(sudo chroot "$WORK/root" bash -c 'ls /boot/vmlinuz-* | sed s,.*/vmlinuz-,, | head -1')"
sudo cp "$WORK/root/boot/initrd.img-$KVER" "$WORK/initrd.img"
sudo chown "$(id -u):$(id -g)" "$WORK/initrd.img"

sudo umount -R "$WORK/root"/{dev/pts,dev,proc,sys}
sudo truncate -s 0 "$WORK/root/run/systemd/resolve/stub-resolv.conf" 2>/dev/null || true

echo ">> Repacking squashfs (xz, 1M blocks)"
sudo mksquashfs "$WORK/root" "$WORK/new.squashfs" -comp xz -b 1M -noappend
sudo chown "$(id -u):$(id -g)" "$WORK/new.squashfs"

# Assemble the list of file replacements for xorriso.
UPDATES=(-update "$WORK/new.squashfs" /casper/filesystem.squashfs
         -update "$WORK/initrd.img"   /casper/initrd.img)

# If this ISO uses isolinux (BIOS), repair its config and ship ldlinux.c32.
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
