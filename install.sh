#!/bin/bash
# https://wiki.archlinux.org/index.php/Archiso#Installation_without_Internet_access
# create VirtualBox with EFI enabled in the system settings and boot Arch ISO
# choose the first boot option "Arch Linux archiso x86_64 UEFI USB"
# tested with archlinux-2017.01.01-dual.iso and VirtualBox 5.1.12 r112440 on 1-15-2017

set -e
set -x

SCRIPT_PATH="$0"
SCRIPT_NAME=$(basename "$SCRIPT_PATH")

function install()
{
  # enable NTP to synchronize clock
  timedatectl set-ntp true

  # parition disk with a GUID partition table:
  # 1. 512MB EFI system partition (FAT32 format)
  # 2. remainder for the root filesystem (ext4 format)
  parted --script /dev/sda mklabel gpt
  parted --script --align optimal /dev/sda mkpart primary fat32 0% 512MB
  parted --script /dev/sda set 1 boot on
  parted --script --align optimal /dev/sda mkpart primary ext4 512MB 100%

  # format disk partitions
  mkfs.vfat -F32 /dev/sda1
  mkfs.ext4 -F /dev/sda2

  # mount disk partitions
  mount /dev/sda2 /mnt
  mkdir /mnt/boot
  mount /dev/sda1 /mnt/boot

  # copy root filesystem from ISO to disk
  time cp -ax / /mnt

  # copy kernel from ISO to disk
  cp -vaT /run/archiso/bootmnt/arch/boot/$(uname -m)/vmlinuz /mnt/boot/vmlinuz-linux

  # create fstab file to enable automatic mounting of partitions
  genfstab -U /mnt >> /mnt/etc/fstab

  # chroot to filesystem on disk and complete installation
  cp "$SCRIPT_PATH" /mnt/root/install-chroot.sh
  chmod +x /mnt/root/install-chroot.sh
  arch-chroot /mnt /root/install-chroot.sh
  rm /mnt/root/install-chroot.sh
  rm /mnt/root/"$SCRIPT_NAME"
  rm /mnt/root/install.txt
  umount -R /mnt

  echo "Remove installation media and restart to complete installation"
}

function install_chroot()
{
  # remove live environment
  sed -i 's/Storage=volatile/#Storage=auto/' /etc/systemd/journald.conf
  rm /etc/udev/rules.d/81-dhcpcd.rules
  systemctl disable pacman-init.service choose-mirror.service
  rm -r /etc/systemd/system/choose-mirror.service
  rm -r /etc/systemd/system/pacman-init.service
  rm -r /etc/systemd/system/etc-pacman.d-gnupg.mount
  rm -r /etc/systemd/system/getty@tty1.service.d
  rm /etc/systemd/scripts/choose-mirror
  rm /root/.automated_script.sh
  rm /root/.zlogin
  rm /etc/mkinitcpio-archiso.conf
  rm -r /etc/initcpio

  # enable networking
  echo -e "[Match]\nName=en*\n\n[Network]\nDHCP=yes" > /etc/systemd/network/wired.network
  systemctl enable systemd-networkd.service
  systemctl enable systemd-resolved.service

  # import archlinux keys for package manager
  pacman-key --init
  pacman-key --populate archlinux

  # set time zone
  ln -sfn /usr/share/zoneinfo/US/Pacific /etc/localtime

  # setup clock
  hwclock --systohc

  # generate locales
  locale-gen

  # set default hostname
  echo "arch" > /etc/hostname

  # create inital ramdisk
  mkinitcpio -p linux

  # install GRUB bootloader for EFI booting
  grub-install /dev/sda --target=x86_64-efi --efi-directory=/boot
  grub-mkconfig -o /boot/grub/grub.cfg

  echo '\EFI\arch\grubx64.efi' > /boot/startup.nsh

  exit
}

if [ "$SCRIPT_NAME" == "install-chroot.sh" ]; then
  install_chroot
else
  install
fi
