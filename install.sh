#!/bin/bash

# Constants
modtools=("fdisk" "cfdisk")
rootfs_types=("ext4" "btrfs" "xfs")
kernel_types=("linux" "linux-lts" "linux-zen")
number_regex='^[0-9]+$'

# Partition variables
part_esp=""
part_boot_exists=0
part_boot=""
part_swap_exists=0
part_swap=""
part_root=""
part_root_fstype=1
part_root_set_btrfs_label=0
part_root_btrfs_label=""
part_confirmtext=""
part_setup_encryption=0
part_encryption_passwd=""

# Kernel variable
kernel_type=1
kernel_confirmtext=""

# Pacman/pacstrap
pacman_enable_parallel=0
pacman_parallel_number=""
pacman_confirmtext=""

# Mirrorlist
mirrorlist_wait=0

# Introduction
whiptail --nocancel --title "Arch Linux installer" --msgbox "Welcome to this whiptail based, user-friendly Arch Linux installer!\n\nThis will walk you through all steps of a basic installation" 10 100

# Modify disk if user needs it
disk_modify() {
  diskmod=0
  while [[ $diskmod -ne 1 ]]; do
    diskmod=$(whiptail --nocancel --title "Disks" --menu "Do you want to start any disk modification tool to manage your partitions?" 15 60 3 \
    "1" "No, continue with the installation" "2" "Use fdisk" "3" "Use cfdisk" 3>&1 1>&2 2>&3)
    if [[ $diskmod -eq 2 ]] || [[ $diskmod -eq 3 ]]; then
      options=()

      for i in $(lsblk | grep disk | awk '{print $1};'); do
        options+=("$(echo "$i" | tr -dc "[:alnum:]")")
        options+=("$(lsblk | grep "$i" | awk '{print $4};')")
      done

      DISK=$(whiptail --nocancel --menu "Choose which disk do you want to modify" 20 60 10 \
       "${options[@]}" 3>&1 1>&2 2>&3)

      clear
      ${modtools[$((diskmod - 2))]} "/dev/$DISK"
    fi
  done
}

# Collect info about partitions
disk_selection() {
  # Get an array of all partitions
  options=()
  for i in $(lsblk | grep part | awk '{print $1};')
  do
    options+=("$(echo "$i" | tr -dc "[:alnum:]")")
    options+=("$(lsblk | grep "$i" | awk '{print $4};')")
  done

  # Currently only UEFI is supported
  part_esp="/dev/$(whiptail --nocancel --title "Disks" --menu "Select your EFI system partition" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)"

  # Boot mount (required for encryption)
  whiptail --nocancel --title "Disks" --yesno "Do you have a boot partition (mount for /boot; required when encryption is used; at least 500MiB)?" 10 60
  if [[ $? -eq 0 ]]; then
    part_boot_exists=1
    part_boot="/dev/$(whiptail --nocancel --title "Disks" --menu "Select your boot partition (at least 500MiB)" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)"
  fi

  # If there is, ask for swap
  whiptail --nocancel --title "Disks" --yesno "Do you have a swap partition?" 10 60
  if [[ $? -eq 0 ]]; then
    part_swap_exists=1
    part_swap="/dev/$(whiptail --nocancel --title "Disks" --menu "Select your swap partition" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)"
  fi

  # Ask for root
  part_root="/dev/$(whiptail --nocancel --title "Disks" --menu "Select your root partition" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)"

  # Ask for root filesystem type
  part_root_fstype=$(whiptail --nocancel --title "Disks" --menu "What filesystem should be the root partition formatted to?" 20 60 3 "1" "ext4" "2" "btrfs" "3" "xfs" 3>&1 1>&2 2>&3)
  if [[ $part_root_fstype -eq 2 ]]; then
    whiptail --nocancel --title "Disks" --yesno "Do you want to set a label for the btrfs partition?" 10 60
    if [[ $? -eq 0 ]]; then
      part_root_btrfs_label=$(whiptail --nocancel --title "Disks" --inputbox "Choose a label for the btrfs root partition" 10 60 3>&1 1>&2 2>&3)
      part_root_set_btrfs_label=1
    fi
  fi

  # If possible, ask for encryption
  if [[ $part_boot_exists -eq 1 ]]; then
    whiptail --nocancel --title "Disks" --yesno "Do you want to set up encryption for your root disk?" 10 60
    if [[ $? -eq 0 ]]; then
      part_setup_encryption=1

      entered_password=0
      password_first=""
      password_second=""
      while [[ $entered_password -eq 0 ]] || ! [[ "$password_first" == "$password_second" ]]; do
        password_first=$(whiptail --nocancel --title "Disks" --passwordbox "Enter the password" 10 60 3>&1 1>&2 2>&3)
        password_second=$(whiptail --nocancel --title "Disks" --passwordbox "Enter the password again" 10 60 3>&1 1>&2 2>&3)
        entered_password=1
      done
      part_encryption_passwd="$password_first"
    fi
  fi

  # Confirm output
  confirm_text=""

  confirm_text="$confirm_text EFI system partition: $part_esp\n"
  if [[ $part_boot_exists -eq 1 ]]; then confirm_text="$confirm_text Boot partition: $part_boot\n"; fi
  if [[ $part_swap_exists -eq 1 ]]; then confirm_text="$confirm_text Swap partition: $part_swap\n"; fi
  confirm_text="$confirm_text Root partition: $part_root\n"
  confirm_text="$confirm_text Root partition filesystem type: ${rootfs_types[$((part_root_fstype - 1))]}\n"
  if [[ $part_root_fstype -eq 2 ]]; then confirm_text="$confirm_text Btrfs label: $part_root_btrfs_label\n"; fi
  confirm_text="$confirm_text \n"
  confirm_text="$confirm_text $part_esp will be formatted to FAT32\n"
  if [[ $part_swap_exists -eq 1 ]]; then confirm_text="$confirm_text $part_swap will be formatted to swap\n"; fi
  confirm_text="$confirm_text $part_root will be formatted to ${rootfs_types[$((part_root_fstype - 1))]}\n\n"

  whiptail --nocancel --title "Disks" --yesno "Are you okay with these?\n\n$confirm_text" 20 60
  if ! [[ $? -eq 0 ]]; then
    part_esp=""
    part_swap_exists=0
    part_swap=""
    part_boot_exists=0
    part_boot=""
    part_root=""
    part_root_fstype=1
    part_root_set_btrfs_label=0
    part_root_btrfs_label=""
    part_confirmtext=""
    part_encryption_passwd=""
    disk_selection
  else
    part_confirmtext=$confirm_text
  fi
}

# Kernel type selection
kernel_selection() {
  kernel_type=$(whiptail --nocancel --title "Kernel" --menu "What type of kernel do you want to install?" 20 60 3 "1" "linux (bleeding-edge)" "2" "linux-lts (more stable)" "3" "linux-zen (gaming optimised)" 3>&1 1>&2 2>&3)
  kernel_confirmtext="Kernel type: ${kernel_types[$((kernel_type - 1))]}\n"
}

# Enable parallel downloads
parallel_download_selection() {
  whiptail --nocancel --title "Downloads" --yesno "Do you want to enable parallel downloads?" 10 60
  if [[ $? -eq 0 ]]; then
    pacman_enable_parallel=1
    while ! [[ $pacman_parallel_number =~ $number_regex ]]; do
      pacman_parallel_number=$(whiptail --nocancel --title "Downloads" --inputbox "How many download do you want at once?" 10 60 3>&1 1>&2 2>&3)
    done
    pacman_confirmtext="Pacman parallel downloads: on\n Downloads at once: $pacman_parallel_number\n"
  else
    pacman_confirmtext="Pacman parallel downloads: off\n"
  fi
}

# Final point to ask
installation_ready() {
  whiptail --nocancel --title "Arch Linux installer" --yesno "Ready to install! Press return if you want to begin the installation process!\n\nCheck if everything is okay:\n$part_confirmtext $kernel_confirmtext $pacman_confirmtext" 20 100
  if [[ $? -eq 1 ]]; then
    exit 1
  fi
}

# Check mirrorlist
mirror_selection() {
  # Check if reflector has selected mirrors
  mirrorlist_linecount=$(cat /etc/pacman.d/mirrorlist | wc -l)
  if [[ $mirrorlist_linecount -gt 100 ]]; then
    whiptail --nocancel --title "Mirrors" --yesno "Mirrors haven't been selected yet, do you want to generate a list now? (or just wait for it)" 10 60
    if [[ $? -eq 0 ]]; then
      whiptail --nocancel --title "Mirrors" --yesno "Do you want the mirrors to be sorted by speed? (takes more time)" 10 60
      if [[ $? -eq 0 ]]; then
        reflector --save /etc/pacman.d/mirrorlist --latest 20 --protocol https --sort rate
      else
        reflector --save /etc/pacman.d/mirrorlist --latest 20 --protocol https
      fi
    else
      mirrorlist_wait=1
    fi
  fi
}

# Wait for mirrorlist to be generated
mirror_wait() {
  if [[ $mirrorlist_wait -eq 1 ]]; then
    clear
    echo "Waiting for reflector to generate the pacman mirror list"

    mirrorlist_linecount=$(cat /etc/pacman.d/mirrorlist | wc -l)
    while [[ $mirrorlist_linecount -gt 100 ]]; do
        sleep 5
        mirrorlist_linecount=$(cat /etc/pacman.d/mirrorlist | wc -l)
    done
  fi
}

# Apply changes on the disks
install_modify_disks() {
  actual_root=""

  echo "Checking for mounted partitions"
  umount -l "$part_esp"
  if [[ $part_boot_exists -eq 1 ]]; then umount -l "$part_boot"; fi
  if [[ $part_swap_exists -eq 1 ]]; then umount -l "$part_swap"; fi
  umount -l "$part_root"


  if [[ $part_setup_encryption -eq 1 ]]; then
    echo "Setting up encryption"
    echo -e "YES\n$part_encryption_passwd\n$part_encryption_passwd" | cryptsetup luksFormat -v -s 512 -h sha512 "$part_root"

    echo "Opening encrypted container"
    echo "$part_encryption_passwd" | cryptsetup open "$part_root" root

    actual_root="/dev/mapper/root"
  else
    actual_root="$part_root"
  fi

  echo "Formatting EFI system partition"
  mkfs.fat -F 32 "$part_esp"

  if [[ $part_boot_exists -eq 1 ]]; then
    echo "Formatting boot partition to ext4"
    mkfs.ext4 -F "$part_boot"
  fi

  if [[ $part_swap_exists -eq 1 ]]; then
    echo "Making swap"
    mkswap "$part_swap"

    echo "Enabling swap"
    swapon "$part_swap"
  fi

  if [[ $part_root_fstype -eq 1 ]]; then
    echo "Formatting root partition to ext4"
    mkfs.ext4 -F "$actual_root"
  elif [[ $part_root_fstype -eq 2 ]]; then
    echo "Formatting root partition to btrfs"
    if [[ $part_root_set_btrfs_label -eq 1 ]]; then
      mkfs.btrfs -f -L "$part_root_btrfs_label" "$actual_root"
    else
      mkfs.btrfs -f "$actual_root"
    fi
  else
    echo "Formatting root partition to xfs"
    mkfs.xfs -f "$actual_root"
  fi


  # Mounting
  echo "Mounting root"
  mount "$actual_root" /mnt

  if [[ $part_boot_exists -eq 1 ]]; then
    echo "Mounting boot partition"
    mount --mkdir "$part_boot" /mnt/boot
  fi

  echo "Mounting EFI system partition"
  mount --mkdir "$part_esp" /mnt/boot/efi
}

# Enabling parallel downloads
install_enable_parallel() {
  if [[ $pacman_enable_parallel -eq 1 ]]; then
    echo "Enabling parallel downloads"
    sed -i '/ParallelDownloads/s/^#//g' /etc/pacman.conf
    sed -i "s/ParallelDownloads = .*/ParallelDownloads = $pacman_parallel_number/" /etc/pacman.conf
  fi
}

# Install linux
install_linux() {
  echo "Starting installation"
  pacstrap -K /mnt base "${kernel_types[$((kernel_type - 1))]}" linux-firmware
}

# Generate fstab
post_install_fstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
}

# Chroot and complete setup
post_install_chroot() {
  whiptail --nocancel --title "Arch Linux installer" --yesno "Do you want to go through the post-installation setup?" 10 60
  if [[ $? -eq 0 ]]; then
    curl -s https://raw.githubusercontent.com/bmhun/installer/main/postinstall.sh >> /mnt/var/post_installation.sh
    chmod +x /mnt/var/post_installation.sh
    arch-chroot /mnt /var/post_installation.sh
  fi
}

# Ask to reboot
post_install_action() {
  operation=$(whiptail --nocancel --title "Arch Linux installer" --menu "What do you want to do now?" 20 60 5 "1" "Nothing (exit chroot)" "2" "Chroot into the new environment" "3" "Reboot" "4" "Shutdown" "5" "Run the post-installation script" 3>&1 1>&2 2>&3)

  if [[ $operation -eq 1 ]]; then
    exit 0
  elif [[ $operation -eq 2 ]]; then
    arch-chroot /mnt
  elif [[ $operation -eq 3 ]]; then
    umount -l /mnt
    reboot
  elif [[ $operation -eq 4 ]]; then
    umount -l /mnt
    shutdown now
  else
    curl -s https://raw.githubusercontent.com/bmhun/installer/main/postinstall.sh >> /mnt/var/post_installation.sh
    chmod +x /mnt/var/post_installation.sh
    arch-chroot /mnt /var/post_installation.sh "$part_esp"
    post_install_action
  fi
}

# Collecting information
disk_modify
disk_selection
kernel_selection
parallel_download_selection

# Waiting for the installation to be possible
installation_ready
mirror_selection
mirror_wait


# Pre install stuff
install_modify_disks
install_enable_parallel

# The long awaited installation
install_linux

# Post installation stuff
post_install_fstab
post_install_chroot
post_install_action
