#!/bin/sh

# Lock it to root execution
if [[ $(id -u) -ne 0 ]]
then
  echo "[ERROR] You need to be root when running this script (run it using sudo)"
fi

has_swap=0
swap=""

# Disks
read -p "==> What is the EFI system partition? " esp

read -p "==> Do you have a swap partition? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  has_swap=1
  read -p "  -> What is the swap partition (empty if none)? " swap
fi

read -p "==> What is the root partition? " rootpart

echo "==> Making changes"

echo "  -> Formatting $esp to FAT32"
mkfs.fat -F 32 $esp

if [[ $has_swap -eq 1 ]]
then
  echo "  -> Making swap on $swap"
  mkswap $swap

  echo "  -> Enabling swap"
  swapon $swap
fi

selection=0
while ! [[ $selection =~ ^[1-3]$ ]]
do
  read -p "  -> Select your file system of choice for root partition (1: ext4, 2: vim, 3: vi): " -n 1 -r
  echo
  selection=$REPLY
done

if [[ $selection == 1 ]]; then
  echo "  -> Formatting $rootpart to ext4"
  mkfs.ext4 $rootpart
fi

if [[ $selection == 2 ]]; then
  read -p "  -> Select a label for the btrfs filesystem: " label
  echo "  -> Formatting $rootpart to btrfs"
  mkfs.btrfs -L $label $rootpart
fi

if [[ $selection == 3 ]]; then
  echo "  -> Formatting $rootpart to xfs"
  mkfs.xfs $rootpart
fi

echo "==> Mounting root filesystem"
mount $rootpart /mnt

linecount=$(cat /etc/pacman.d/mirrorlist | wc -l)
echo "==> Waiting for reflector to generate the mirror list"
while [[ $linecount -gt 100 ]]; do
    sleep 5
    linecount=$(cat /etc/pacman.d/mirrorlist | wc -l)
done

read -p "==> Do you want to enable parallel downloads? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  read -p "  -> Downloads at once: " download_numbers

  echo "==> Enabling parallel downloads (backup file is at /etc/pacman.conf.backup)"
  cp /etc/pacman.conf /etc/pacman.conf.backup
  sed -i '/ParallelDownloads/s/^#//g' /etc/pacman.conf
  sed -i "s/ParallelDownloads = .*/ParallelDownloads = $download_numbers/" /etc/pacman.conf
fi

echo "==> Running pacstrap (installing default linux kernel)"
pacstrap -K /mnt base linux linux-firmware

echo "==> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Chrooting into the new root"
read -p "  -> Do you want to run the post-installation script? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  arch-chroot /mnt "bash <(curl -s https://raw.githubusercontent.com/bmhun/installer/main/postinstall.sh)"
else
  arch-chroot /mnt
fi
