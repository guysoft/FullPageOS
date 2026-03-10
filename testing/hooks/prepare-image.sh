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

# Disable services that timeout waiting for Pi-specific hardware in QEMU:
# - zram (no /dev/zram0 in virt)
# - rpi-eeprom-update (no Pi EEPROM)
# - copy-network-manager config for wlan0 (no wifi)
# - DRI device dependencies (virtio-gpu may not create card0/renderD128 in time)
-rm /etc/systemd/system/multi-user.target.wants/dphys-swapfile.service
-rm /etc/systemd/system/swap.target.wants/mkswap.service
-rm /etc/systemd/system/swap.target.wants/sys-subsystem-net-devices-wlan0.device
-rm /lib/systemd/system/rpi-eeprom-update.service
-rm /etc/systemd/system/multi-user.target.wants/rpi-eeprom-update.service

# Mask services that block boot waiting for Pi hardware
ln-sf /dev/null /etc/systemd/system/systemd-zram-setup@.service
ln-sf /dev/null /etc/systemd/system/copy-network-manager-conf@.service

# Mask DRI device wait units -- virtio-gpu may not create /dev/dri/* in QEMU virt
ln-sf /dev/null /etc/systemd/system/dev-dri-card0.device
ln-sf /dev/null /etc/systemd/system/dev-dri-renderD128.device

# Pre-create /etc/gpu_enabled so enable_gpu script skips its reboot
touch /etc/gpu_enabled

# Disable the enable_gpu_first_boot service entirely in QEMU
ln-sf /dev/null /etc/systemd/system/enable_gpu_first_boot.service

# Xvfb will be installed and configured via post-boot.sh hook (needs apt-get).
# Pre-create the lightdm conf directory so the hook can write to it.
mkdir-p /etc/lightdm/lightdm.conf.d

umount /
GFEOF

echo 'FullPageOS patches applied'
