#!/bin/bash
#
# Achilles build script
# Made with <3 https://github.com/Tracker-Friendly/Achilles
# Modified from https://github.com/asineth0/checkn1x, https://github.com/raspberryenvoie/odysseyn1x and https://github.com/palera1n/palera1x                               

# ___            .-- ----.     
#/  |\          /   /     \    
#\  | |        /   /   .   \   
# `--'   .---..\   \  / \   \ 
#      .'  .' | \___\/   \   | 
#    .---.'   ,      \   |   | 
#    |   |    |       |  |   | 
#    |   |  .'        |  |   | 
#    |   |.'     ___ /   |   | 
# ___`---       /   /\   /   | 
#/  |\         /   /  \ /    | 
#\  | |        \   \   '    /  
# `--'          \   \      /   
#                '--- ----'    
                              

# Exit if user isn't root
[ "$(id -u)" -ne 0 ] && {
    echo 'Please run as root'
    exit 1
}

cat ./logo.txt

# Ask for the architecture if variable is empty
while [ -z "$VERSION" ]; do
    VERSION=$(cat version)
done
until [ "$ARCH" = 'amd64' ] || [ "$ARCH" = 'i686' ] || [ "$ARCH" = 'aarch64' ]; do
    echo '1 amd64'
    echo '2 i686'
    echo '3 aarch64'
    printf 'Which architecture? amd64 (default), i686, or aarch64 '
    read -r input_arch
    [ "$input_arch" = 1 ] && ARCH='amd64'
    [ "$input_arch" = 2 ] && ARCH='i686'
    [ "$input_arch" = 3 ] && ARCH='aarch64'
    [ -z "$input_arch" ] && ARCH='amd64'
done

# Install dependencies to build Achilles
if [[ $(uname -r | grep arch) ]]; then
  sudo pacman -S --needed wget debootstrap mtools xorriso ca-certificates curl usbutils gcc make gzip unzip
else
  apt-get update
  apt-get install -y --no-install-recommends wget debootstrap mtools xorriso ca-certificates curl libusb-1.0-0-dev gcc make gzip xz-utils unzip libc6-dev
fi

# Get proper files for amd64 or i686
if [ "$ARCH" = 'amd64' ]; then
    ROOTFS='https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-minirootfs-3.17.3-x86_64.tar.gz'
elif [ "$ARCH" = 'i686' ]; then
    ROOTFS='https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86/alpine-minirootfs-3.17.3-x86.tar.gz'
elif [ "$ARCH" = 'aarch64' ]; then
    ROOTFS='https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/aarch64/alpine-minirootfs-3.17.3-aarch64.tar.gz'
fi

# Clean up previous attempts
umount -v work/rootfs/{dev,sys,proc} >/dev/null 2>&1
rm -rf work
mkdir -pv work/{rootfs,iso/boot/grub}
cd work

# Fetch ROOTFS
curl -sL "$ROOTFS" | tar -xzC rootfs
mount -vo bind /dev rootfs/dev
mount -vt sysfs sysfs rootfs/sys
mount -vt proc proc rootfs/proc
cp /etc/resolv.conf rootfs/etc
cp ../packages rootfs/root
cat << ! > rootfs/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/v3.12/main
http://dl-cdn.alpinelinux.org/alpine/edge/community
http://dl-cdn.alpinelinux.org/alpine/edge/testing
!

sleep 2
# ROOTFS packages & services
cat << ! | chroot rootfs /usr/bin/env PATH=/usr/bin:/usr/local/bin:/bin:/usr/sbin:/sbin /bin/sh
apk update
apk upgrade
cat /root/packages
apk add $(cat /root/packages)
apk add --no-scripts linux-lts linux-firmware-none
rc-update add bootmisc
rc-update add hwdrivers
rc-update add udev
rc-update add udev-trigger
rc-update add udev-settle
rc-update add iwd
!

# Unmount fs
umount -v rootfs/{dev,sys,proc}

# Copy files
cp -av ../inittab rootfs/etc
cp -v ../scripts/* rootfs/usr/bin
chmod -v 755 rootfs/usr/local/bin/*
ln -sv sbin/init rootfs/init
ln -sv ../../etc/terminfo rootfs/usr/share/terminfo # fix ncurses
cp -v ../scripts/setupeth rootfs/usr/bin
cp -v ../configs rootfs/
rm /root/packages

# Boot config
cp -av rootfs/boot/vmlinuz-lts iso/boot/vmlinuz
cat << ! > iso/boot/grub/grub.cfg
insmod all_video
echo 'Achilles $VERSION'
linux /boot/vmlinuz quiet loglevel=3
initrd /boot/initramfs.xz
boot
!

# initramfs
pushd rootfs
rm -rfv tmp/* boot/* var/cache/* etc/resolv.conf
find . | cpio -oH newc | xz -C crc32 --x86 -vz9eT$(nproc --all) > ../iso/boot/initramfs.xz
popd

# ISO creation
grub-mkrescue -o "Achilles-$VERSION-$ARCH.iso" iso --compress=xz
