#!/bin/sh

# Lock it to root execution
if [[ $(id -u) -ne 0 ]]
then
  echo "[ERROR] You need to be root when running this script (run it using sudo)"
fi

# Localisation
read -p "Do you want to set up localisation and timezone? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  selected_city=""

  echo "==> Collecting localisation information"

  while [[ $selected_city == "" ]]; do
    read -p "  -> Your city of timezone (just the city): " city
    for i in $(find /usr/share/zoneinfo/ -iname "$city"); do
        if [[ $i != "/usr/share/zoneinfo/posix/"* ]] && [[ $i != "/usr/share/zoneinfo/right/"* ]]; then
          found=$(basename $i)
          if [[ ${city,,} == ${found,,} ]]; then
            selected_city=$i
          else
            echo "  -> Failed to find matching city name"
            break
          fi
        fi
    done
  done

  echo "  -> Selected city: $(basename $(dirname "$selected_city"))/$(basename "$selected_city")"

  read -p "  -> Do you want to set custom locale (using text editor) or just the default en_US.UTF-8? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    selection=0
    while ! [[ $selection =~ ^[1-3]$ ]]
    do
      read -p "  -> Select your text editor of choice (1: nano, 2: vim, 3: vi): " -n 1 -r
      echo
      selection=$REPLY
    done

    editor_name=""
    if [[ $selection == 1 ]]; then
      editor_name="nano"
    fi

    if [[ $selection == 2 ]]; then
      editor_name="vim"
    fi

    if [[ $selection == 3 ]]; then
      editor_name="vi"
    fi

    pacman -Qs $editor_name > /dev/null
    if [[ $? == "0" ]]; then
      echo "  -> Text editor is installed, there's nothing to do"
    else
      echo "  -> Installing $editor_name"
      pacman -S --noconfirm $editor_name
    fi

    $editor_name /etc/locale.gen
  else
    sed -i "/en_US.UTF-8 UTF-8/s/^#//g" /etc/locale.gen
  fi


  echo "==> Setting timezone"
  ln -sf "$selected_city" /etc/localtime

  echo "==> Setting hardware clock"
  hwclock --systohc

  echo "==> Generating locales"
  locale-gen

  echo "==> Localisation configuration files"
  read -p "  -> Do you want to set LANG variable in locale.conf? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    read -p "  -> Enter your language (like en_US.UTF-8): " lang_var
    echo "LANG=$lang_var" >> /etc/locale.conf
  fi

  read -p "  -> Do you want to set KEYMAP variable in vconsole.conf (for default keymap in tty)? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    read -p "  -> Enter your keymap (like us, hu, etc.): " keymap_var
    echo "KEYMAP=$keymap_var" >> /etc/vconsole.conf
  fi
fi

# Boot setup
read -p "Do you want to set up grub for UEFI boot? (no support for MBR yet) [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  echo "==> Mounting EFI system partition"
  mkdir -p /boot/efi

  read -p "  -> Enter EFI system partition (needs to be FAT32 and at least 300MiB): " esp
  mount esp /boot/efi

  echo "==> Checking for updates"
  pacman -Syu --noconfirm

  echo "==> Installing needed network_packages"
  pacman -S efibootmgr grub

  echo "==> Installing grub"

  removable=""
  read -p "  -> Is it a removable device? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    removable"--removable "
  fi

  bootloader_id=""
  read -p "  -> Do you want to set the bootloader id? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    read -p "    -> Enter bootloader ID (without spaces): " boot_id
    bootloader_id="--bootloader-id=$boot_id "
  fi

  grub-install --target=x86_64-efi "$bootloader_id""$removable" --recheck

  echo "==> Generating grub configuration"
  grub-mkconfig -o /boot/grub/grub.cfg
fi

read -p "Do you want to add a user and setup sudo? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  read -p "==> Enter new username: " username

  echo "==> Creating user $username"
  useradd -m "$username"

  read -p "==> Do you want to create a password for this user (strongly recommended, can't be used otherwise)? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    echo "==> Creating password"
    passwd "$username"
  fi

  read -p "==> Do you want to setup sudo? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    echo "  -> Checking for updates"
    pacman -Syu --noconfirm

    echo "  -> Installing sudo"
    pacman -S --noconfirm sudo

    echo "  -> Enabling sudo for wheel group (need to edit sudoers)"

    selection=0
    while ! [[ $selection =~ ^[1-3]$ ]]
    do
      read -p "  -> Select your text editor of choice (1: nano, 2: vim, 3: vi): " -n 1 -r
      echo
      selection=$REPLY
    done

    editor_name=""
    if [[ $selection == 1 ]]; then
      editor_name="nano"
    fi

    if [[ $selection == 2 ]]; then
      editor_name="vim"
    fi

    if [[ $selection == 3 ]]; then
      editor_name="vi"
    fi

    pacman -Qs $editor_name > /dev/null
    if [[ $? == "0" ]]; then
      echo "  -> Text editor is installed, there's nothing to do"
    else
      echo "  -> Installing $editor_name"
      pacman -S --noconfirm $editor_name
    fi

    EDITOR=$editor_name visudo

    echo "  -> Adding newly created user to the wheel group"
    usermod -aG wheel "$username"
  fi
fi

# Network setup
read -p "Do you want to set up networking? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  read -p "==> Enter new hostname: " hostname

  echo "==> Setting hostname"
  echo "$hostname" >> /etc/hostname

  echo "==> Setting hosts"
  echo "127.0.0.1        localhost
  ::1              localhost
  127.0.1.1        $hostname" >> /etc/hosts

  wireless=0

  read -p "==> Do you want to have support for wireless connections (with iwd)? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    wireless=1
  fi

  network_packages="networkmanager dhcpcd"

  if [[ $wireless -eq 1 ]]
  then
    network_packages="$network_packages iwd"
  fi

  echo "==> Checking for updates"
  pacman -Syu --noconfirm

  echo "==> Installing audio_packages"
  pacman -S --noconfirm "$network_packages"

  echo "==> Enabling services"

  echo "  -> Network Manager"
  systemctl enable NetworkManager

  echo "  -> dhcpcd"
  systemctl enable dhcpcd

  if [[ $wireless -eq 1 ]]
  then
    echo "  -> iwd"
    systemctl enable iwd
  fi

  echo "==> Configuring DHCP"

  read -p "  -> Do you want to set custom domain name servers (DNS)? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    servers=""
    read -p "  -> Do you want to use Google's servers? (recommended) [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      servers="8.8.8.8 8.8.4.4"
    else
      read -p "    -> Enter your domain name servers (separated with spaces): " dns_servers
      servers=$dns_servers
    fi
    echo "static domain_name_servers=$servers" >> /etc/dhcpcd.conf
  fi
fi

# Graphics
read -p "Do you want to install video drivers? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  graphics_packages=""
  need_multilib=0

  read -p "==> Do you want to download proprietary NVIDIA drivers [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
  then
    graphics_packages="$graphics_packages nvidia nvidia-utils"

    read -p "  -> Do you want 32-bit support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      need_multilib=1
      graphics_packages="$graphics_packages lib32-nvidia-utils"
    fi

    read -p "  -> Do you want to install nvidia settings for managing your GPU and screens? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      graphics_packages="$graphics_packages nvidia-settings"
    fi
  fi

  read -p "==> Do you want to install open source nvidia drivers (not recommended) [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    graphics_packages="$graphics_packages xf86-video-nouveau"
  fi

  read -p "==> Do you want to install AMD open source drivers (Vulkan, DRI and DDX drivers)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    graphics_packages="$graphics_packages mesa vulkan-radeon xf86-video-amdgpu"

    read -p "  -> Do you want 32-bit support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      need_multilib=1
      graphics_packages="$graphics_packages lib32-mesa lib32-vulkan-radeon"
    fi
  fi

  read -p "==> Do you want to install Intel drivers (Vulkan, DRI and DDX drivers)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    graphics_packages="$graphics_packages mesa vulkan-intel xf86-video-intel"

    read -p "  -> Do you want 32-bit support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      need_multilib=1
      graphics_packages="$graphics_packages lib32-mesa"
    fi
  fi

  if [[ $need_multilib -eq 1 ]]
  then
    if [[ $(grep "\\[multilib\\]" /etc/pacman.conf) == "#"* ]]
    then
      configfile="/etc/pacman.conf"
      backupfile="$configfile.backup"

      echo "==> Enabling multilib repository, in case something goes wrong a backup file is located at $backupfile"

      cp $configfile $backupfile
      mline=$(grep -n "\\[multilib\\]" $configfile | cut -d: -f1)
      rline=$(($mline + 1))
      sed -i ''$mline's|#\[multilib\]|\[multilib\]|g' $configfile
      sed -i ''$rline's|#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|g' $configfile
    else
      echo "==> Multilib repository is enabled, there's nothing to do"
    fi
  fi

  echo "==> Checking for updates"
  pacman -Syu --noconfirm

  echo "==> Installing audio_packages"
  pacman -S --noconfirm "$network_packages"
fi

read -p "Do you want to setup audio (pipewire) [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
then
  multilib=0
  alsa=0
  jack=0
  pulse=0

  echo "==> Collecting information about the pipewire installation"

  read -p "  -> Do you want to customize the installation of pipewire? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    read -p "  -> Do you want 32-bit support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      multilib=1
    fi

    read -p "  -> Do you want alsa support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      alsa=1
    fi

    read -p "  -> Do you want JACK support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      jack=1
    fi

    read -p "  -> Do you want pulseaudio support? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" ]]
    then
      pulse=1
    fi
  else
    multilib=1
    alsa=1
    jack=1
    pulse=1
  fi

  echo "  -> Default is wireplumber session manager"

  audio_packages="pipewire wireplumber"

  if [[ $multilib -eq 1 ]]
  then
    audio_packages="$audio_packages lib32-pipewire"

    if [[ $jack -eq 1 ]]
    then
      audio_packages="$audio_packages lib32-pipewire-jack"
    fi

    if [[ $(grep "\\[multilib\\]" /etc/pacman.conf) == "#"* ]]
    then
      configfile="/etc/pacman.conf"
      backupfile="$configfile.backup"

      echo "==> Enabling multilib repository, in case something goes wrong a backup file is located at $backupfile"

      cp $configfile $backupfile
      mline=$(grep -n "\\[multilib\\]" $configfile | cut -d: -f1)
      rline=$(($mline + 1))
      sed -i ''$mline's|#\[multilib\]|\[multilib\]|g' $configfile
      sed -i ''$rline's|#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|g' $configfile
    else
      echo "==> Multilib repository is enabled, there's nothing to do"
    fi
  fi

  if [[ $alsa -eq 1 ]]
  then
    audio_packages="$audio_packages pipewire-alsa"
  fi

  if [[ $jack -eq 1 ]]
  then
    audio_packages="$audio_packages pipewire-jack"
  fi

  if [[ $pulse -eq 1 ]]
  then
    audio_packages="$audio_packages pipewire-pulse"
  fi

  echo "==> Checking for updates"
  pacman -Syu --noconfirm

  echo "==> Installing packages"
  pacman -S --noconfirm "$audio_packages"

  echo "==> Enabling session manager (wireplumber, this might give an error but it's normal)"
  systemctl --user --now enable wireplumber
fi

echo "Installation is done! Install your own desktop environment or desktop manager (e.g.: pacman -S xorg gnome firefox)"
