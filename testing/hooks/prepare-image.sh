#!/bin/bash
set -e
IMAGE_FILE="${1:?Usage: $0 <image.qcow2>}"

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_DEBUG=0
export LIBGUESTFS_TRACE=0

echo '=== FullPageOS-specific image patches ==='

guestfish -a "$IMAGE_FILE" <<GFEOF
run
mount /dev/sda2 /

# Remove fbturbo X11 config that conflicts with virtio-gpu
-rm /usr/share/X11/xorg.conf.d/99-fbturbo.conf
-rm /usr/share/X11/xorg.conf.d/99-fbturbo.~

# Disable FullPageOS-specific services not needed in QEMU:
# - dphys-swapfile/mkswap (no swap in qcow2)
# - wlan0 device (no wifi in QEMU)
-rm /etc/systemd/system/multi-user.target.wants/dphys-swapfile.service
-rm /etc/systemd/system/swap.target.wants/mkswap.service
-rm /etc/systemd/system/swap.target.wants/sys-subsystem-net-devices-wlan0.device

# Mask DRI device wait units -- virtio-gpu may not create /dev/dri/* in QEMU virt
ln-sf /dev/null /etc/systemd/system/dev-dri-card0.device
ln-sf /dev/null /etc/systemd/system/dev-dri-renderD128.device

# Pre-create /etc/gpu_enabled so enable_gpu script skips its reboot
touch /etc/gpu_enabled

# Xvfb will be installed and configured via post-boot.sh hook (needs apt-get).
# Pre-create the lightdm conf directory so the hook can write to it.
mkdir-p /etc/lightdm/lightdm.conf.d

umount /
GFEOF

echo 'FullPageOS patches applied'
