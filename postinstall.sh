#!/bin/sh

# Constants
number_regex='^[0-9]+$'
sudoers_options=("%wheel ALL=(ALL:ALL) ALL" "%wheel ALL=(ALL:ALL) NOPASSWD: ALL")
preset_dns_servers=("8.8.8.8 8.8.4.4" "1.1.1.1" "9.9.9.9")
graphics_driver_options=(
  "nvidia" "Base package for NVIDIA graphics driver" ""
  "nvidia-lts" "Install instead of nvidia if you have LTS kernel" ""
  "lib32-nvidia-utils" "32-bit support with nvidia drivers" ""
  "nvidia-settings" "Display and GPU settings manager" ""
  "xf86-video-nouveau" "Open source NVIDIA driver (not good performance)" ""
  "xf86-video-intel" "2D acceleration (DDX) for Intel GPUs" ""
  "xf86-video-amdgpu" "2D acceleration (DDX) for AMD Radeon GPUs" ""
  "mesa" "AMD Radeon and Intel 3D (DRI) support" ""
  "lib32-mesa" "32-bit AMD Radeon and Intel 3D (DRI) support" ""
  "vulkan-intel" "Vulkan support for Intel GPUs" ""
  "vulkan-radeon" "Vulkan support for AMD Radeon GPUs" ""
  "lib32-vulkan-radeon" "32-bit Vulkan support for AMD Radeon GPUs" ""
)
pulseaudio_options=(
  "pulseaudio-alsa" "Support for ALSA" ""
  "pulseaudio-bluetooth" "Support for Bluetooth" ""
  "pulseaudio-jack" "Support for JACK" ""
)
pipewire_options=(
  "lib32-pipewire" "32-bit support" ""
  "pipewire-alsa" "Support for ALSA" ""
  "pipewire-jack" "Support for JACK" ""
  "lib32-pipewire-jack" "32-bit support for JACK" ""
  "pipewire-pulse" "PulseAudio replacement" ""
)
display_manager_options=(
  "1" "LightDM - Lightweight display manager (uses GTK greeter)"
  "2" "GDM - Gnome's display manager, simple and user friendly"
  "3" "SDDM - KDE Plasma's Qt based, lightweight display manager"
)
desktop_options=(
  "budgie" "A minimalistic and elegant desktop environment" ""
  "deepin" "An eyecandy desktop environment, with fancy stuff" ""
  "deepin-extra" "Additional apps for the Deepin desktop environment" ""
  "gnome" "Simple, user friendly desktop environment (good accessibility)" ""
  "gnome-extra" "Useful applications for the GNOME desktop environment" ""
  "kde-accessibility" "Apps for KDE Plasma - accessibility" ""
  "kde-applications" "All apps for KDE Plasma (overwrites the sub-categories)" ""
  "kde-education" "Apps for KDE Plasma - education" ""
  "kde-games" "Apps for KDE Plasma - games" ""
  "kde-graphics" "Apps for KDE Plasma - graphics" ""
  "kde-multimedia" "Apps for KDE Plasma - multimedia" ""
  "kde-network" "Apps for KDE Plasma - network" ""
  "kde-pim" "Apps for KDE Plasma - PIM" ""
  "kde-system" "Apps for KDE Plasma - Basic system applications" ""
  "kde-utilities" "Apps for KDE Plasma - Essential utilities" ""
  "mate" "A fork of the old GNOME 2" ""
  "mate-extra" "Apps for the Mate desktop environment" ""
  "plasma" "A Qt based, Windows like desktop environment" ""
  "xfce4" "A lightweight, functional desktop environment" ""
  "xfce4-goodies" "Additional apps for the xfce4 desktop environment" ""
)
packages=()

# Localisation variables
localisation_city_path=""
localisation_selected_locales=()
localisation_set_lang=0
localisation_lang=""
localisation_set_keymap=0
localisation_keymap=""

# Bootloader variables
packages+=("grub" "efibootmgr")
boot_part_esp=""
boot_removable=0
boot_set_id=0
boot_loader_id=""

# User variables
user_name=""
user_set_password=0
user_password=""
user_set_sudo=0
user_sudo_mode=1

# Networking variables
packages+=("networkmanager" "dhcpcd")
networking_hostname=""
networking_iwd=0
networking_set_dns=0
networking_dns=""

# Audio
audio_enable_wireplumber=0
audio_add_group=0

# Desktop
desktop_enable_display_manager=0
desktop_display_manager_service=""

# Other
packages_enable_parallel=0
packages_parallel_downloads=""

# Check if libnewt is installed (the windowing library)
check_environment() {
  pacman -Qs libnewt > /dev/null
  if ! [[ $? == "0" ]]; then
    echo "libnewt wasn't found, installing it"
    pacman -S --noconfirm libnewt
  fi
}

# City of timezone, locales, keymaps, languages
collect_localisation() {
  # City
  cities=()
  for i in $(find /usr/share/zoneinfo/*/* -type f); do
    if [[ $i != "/usr/share/zoneinfo/posix/"* ]] && [[ $i != "/usr/share/zoneinfo/right/"* ]]; then
      cities+=("$(realpath --relative-to=/usr/share/zoneinfo/ "$i")")
      cities+=("")
    fi
  done
  selected_city=$(whiptail --nocancel --title "Localisation" --menu "Select the city of your timezone" 20 60 12 "${cities[@]}" 3>&1 1>&2 2>&3)
  localisation_city_path="/usr/share/zoneinfo/$selected_city"


  # Locales
  locales=()
  while read -r line; do
    locale_substring="$line"
    if [[ $line == "#"* ]]; then locale_substring=${line:1}; fi

    locales+=("$locale_substring")
    locales+=("")
    locales+=("")
  done < <(cat /etc/locale.gen | tail -n +18)

  selected_locales=$(whiptail --nocancel --title "Localisation" --checklist "Select the locales that you want to generate" 20 60 12 "${locales[@]}" 3>&1 1>&2 2>&3)
  while read -r line; do
    localisation_selected_locales+=("$(echo "$line" | tr -d '"')")
  done < <(echo "$selected_locales" | awk 'BEGIN{FPAT = "([^[:space:]]+)|(\"[^\"]+\")"}{for(i=1;i<=NF;i++) print $i}')


  # Language variable
  whiptail --nocancel --title "Localisation" --yesno "Do you want to set the language (LANG variable in locale.conf)?" 10 60
  if [[ $? -eq 0 ]]; then
    localisation_set_lang=1
    lang_options=()
    for i in "${localisation_selected_locales[@]}"; do
      locale_parts=($i)
      lang_options+=("${locale_parts[0]}")
      lang_options+=("")
    done
    localisation_lang=$(whiptail --nocancel --title "Localisation" --menu "Select the language" 20 60 12 "${lang_options[@]}" 3>&1 1>&2 2>&3)
  fi


  # Keymap variable
  whiptail --nocancel --title "Localisation" --yesno "Do you want to set the keymap (KEYMAP variable in vconsole.conf)?" 10 60
  if [[ $? -eq 0 ]]; then
    localisation_set_keymap=1
    localisation_keymap=$(whiptail --nocancel --title "Localisation" --inputbox "Choose a your keymap (that you used with loadkeys)" 10 60 3>&1 1>&2 2>&3)
  fi
}

collect_bootloader() {
  # Get an array of all partitions
  partitions=()
  for i in $(lsblk | grep part | awk '{print $1};')
  do
    partitions+=("$(echo "$i" | tr -dc "[:alnum:]")")
    partitions+=("$(lsblk | grep "$i" | awk '{print $4};')")
  done

  # Get EFI partition
  boot_part_esp="/dev/$(whiptail --nocancel --title "Bootloader" --menu "Select your EFI system partition" 20 60 10 "${partitions[@]}" 3>&1 1>&2 2>&3)"

  # Whether its removable
  whiptail --nocancel --title "Bootloader" --yesno "Is that partition on a removable device?" 10 60
  if [[ $? -eq 0 ]]; then
    boot_removable=1
  fi

  # Set the ID if user needs it
  whiptail --nocancel --title "Bootloader" --yesno "Do you want to set the ID of the bootloader?" 10 60
  if [[ $? -eq 0 ]]; then
    boot_set_id=1
    boot_loader_id=$(whiptail --nocancel --title "Bootloader" --inputbox "Set the ID for the bootloader (no spaces)" 10 60 3>&1 1>&2 2>&3)
    if [[ $boot_loader_id == "" ]]; then
      boot_loader_id="grub"
    fi
  fi
}

# Setup user
collect_user() {
  # Name is needed
  user_name=$(whiptail --nocancel --title "User" --inputbox "Select the name for the new user (possibly no spaces)" 10 60 3>&1 1>&2 2>&3)

  # Set password if user wants it
  whiptail --nocancel --title "User" --yesno "Do you want to set a password for the new user?" 10 60
  if [[ $? -eq 0 ]]; then
    user_set_password=1
    entered_password=0

    password_first=""
    password_second=""
    while [[ $entered_password -eq 0 ]] || ! [[ "$password_first" == "$password_second" ]]; do
      password_first=$(whiptail --nocancel --title "User" --passwordbox "Enter the new password" 10 60 3>&1 1>&2 2>&3)
      password_second=$(whiptail --nocancel --title "User" --passwordbox "Enter the new password again" 10 60 3>&1 1>&2 2>&3)
      entered_password=1
    done

    user_password=$password_first
  fi

  # Setup sudo if user wants it
  whiptail --nocancel --title "User" --yesno "Do you want to set up sudo (for running programs as root)?" 10 60
  if [[ $? -eq 0 ]]; then
    user_set_sudo=1
    user_sudo_mode=$(whiptail --nocancel --title "User" --menu "What sudo mode do you want to use" 10 60 2 "1" "Require user password" "2" "Don't require a password (not recommended)" 3>&1 1>&2 2>&3)
    packages+=("sudo")
  fi
}

# Networking settings
collect_networking() {
  # Hostname
  networking_hostname=$(whiptail --nocancel --title "Networking" --inputbox "Select your hostname (without spaces)" 10 60 3>&1 1>&2 2>&3)

  # Get iwd if user wants it
  whiptail --nocancel --title "Networking" --yesno "Do you want support for wireless connections?" 10 60
  if [[ $? -eq 0 ]]; then
    networking_iwd=1
    packages+=("iwd")
  fi

  # DNS
  whiptail --nocancel --title "Networking" --yesno "Do you want to set custom DNS servers?" 10 60
  if [[ $? -eq 0 ]]; then
    networking_set_dns=1
    selected_dns=$(whiptail --nocancel --title "Networking" --menu "Which DNS server do you want to use?" 20 60 10 "1" "Google (8.8.8.8 and 8.8.4.4)" "2" "Cloudflare (1.1.1.1)" "3" "Quad9 (9.9.9.9)" "4" "Custom" 3>&1 1>&2 2>&3)
    if [[ $selected_dns -eq 4 ]]; then
      networking_dns=$(whiptail --nocancel --title "Networking" --inputbox "Set your custom DNS servers (separated with spaces)" 10 60 3>&1 1>&2 2>&3)
    else
      networking_dns="${preset_dns_servers[$((selected_dns - 1))]}"
    fi
  fi
}

# Graphics driver downloads
collect_graphics() {
  packages+=($(whiptail --nocancel --title "Graphics" --checklist "Select which graphics drivers should be installed" 20 80 12 "${graphics_driver_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"'))
}

# Audio settings
collect_audio() {
  selected_server_type=$(whiptail --nocancel --title "Audio" --menu "Which audio server do you want?" 15 60 3 "1" "None" "2" "PulseAudio" "3" "PipeWire (with wireplumber)" 3>&1 1>&2 2>&3)
  if [[ $selected_server_type -eq 2 ]]; then
    packages+=("pulseaudio" $(whiptail --nocancel --title "Audio" --checklist "Customize your PulseAudio install" 15 60 3 "${pulseaudio_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"'))
    audio_add_group=1
  elif [[ $selected_server_type -eq 3 ]]; then
    packages+=("pipewire" "wireplumber" $(whiptail --nocancel --title "Audio" --checklist "Customize your PipeWire install" 15 60 5 "${pipewire_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"'))
    audio_enable_wireplumber=1
  fi
}

# Get display managers
collect_desktop() {
  whiptail --nocancel --title "Desktop" --yesno "Do you want to install desktop components (only X11)?" 10 60
  if [[ $? -eq 0 ]]; then
    # Install xorg
    packages+=("xorg")

    # Display Manager
    selected_display_managers="$(whiptail --nocancel --title "Desktop" --menu "Which display manager do you want to use" 15 70 3 "${display_manager_options[@]}" 3>&1 1>&2 2>&3)"
    if [[ $selected_display_managers -eq 1 ]]; then
      packages+=("lightdm" "lightdm-gtk-greeter")
      desktop_display_manager_service="lightdm"
    elif [[ $selected_display_managers -eq 2 ]]; then
      packages+=("gdm")
      desktop_display_manager_service="gdm"
    elif [[ $selected_display_managers -eq 3 ]]; then
      packages+=("sddm")
      desktop_display_manager_service="sddm"
    fi
    desktop_enable_display_manager=1

    # Desktop
    packages+=($(whiptail --nocancel --title "Desktop" --checklist "Select which desktop components should be installed" 28 90 20 "${desktop_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"'))
  fi
}

# Ask the user if they want to enable parallel downloads
collect_packages() {
  whiptail --nocancel --title "Downloads" --yesno "Do you want to enable parallel downloads?" 10 60
  if [[ $? -eq 0 ]]; then
    packages_enable_parallel=1
    while ! [[ $packages_parallel_downloads =~ $number_regex ]]; do
      packages_parallel_downloads=$(whiptail --nocancel --title "Downloads" --inputbox "How many download do you want at once?" 10 60 3>&1 1>&2 2>&3)
    done
  fi
}

# Installing packages
setup_packages() {
  all_packages="${packages[@]}"

  if [[ $packages_enable_parallel -eq 1 ]]; then
    echo "Enabling parallel downloads"
    sed -i '/ParallelDownloads/s/^#//g' /etc/pacman.conf
    sed -i "s/ParallelDownloads = .*/ParallelDownloads = $packages_parallel_downloads/" /etc/pacman.conf
  fi

  if [[ $all_packages == *"lib32"* ]]; then
    if [[ $(grep "\\[multilib\\]" /etc/pacman.conf) == "#"* ]]; then
      configfile="/etc/pacman.conf"
      backupfile="$configfile.backup"

      echo "Enabling multilib repository, in case something goes wrong a backup file is located at $backupfile"

      cp $configfile $backupfile
      mline=$(grep -n "\\[multilib\\]" $configfile | cut -d: -f1)
      rline=$(($mline + 1))
      sed -i ''$mline's|#\[multilib\]|\[multilib\]|g' $configfile
      sed -i ''$rline's|#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|g' $configfile
    else
      echo "Multilib repository is enabled, there's nothing to do"
    fi
  fi

  echo "Checking for updates"
  pacman -Syu --noconfirm

  echo "Installing packages"
  pacman -S --noconfirm $all_packages
}

# Changes: localisation
setup_localisation() {
  echo "Setting timezone"
  ln -sf "$localisation_city_path" /etc/localtime

  echo "Enabling hardware clock"
  hwclock --systohc

  echo "Setting selectable locales"
  for i in "${localisation_selected_locales[@]}"; do
    sed -i "/$i/s/^#//g" /etc/locale.gen
  done

  echo "Generating locales"
  locale-gen

  if [[ $localisation_set_lang -eq 1 ]]; then
    echo "Setting language"
    echo "LANG=$localisation_lang" >> /etc/locale.conf
  fi

  if [[ $localisation_set_keymap -eq 1 ]]; then
    echo "Setting keymap"
    echo "LANG=$localisation_keymap" >> /etc/vconsole.conf
  fi
}

# Changes: bootloader
setup_bootloader() {
  echo "Mounting EFI system partition"
  mount --mkdir "$boot_part_esp" /boot/efi

  # Preparing arguments
  id_option=""
  removable_option=""
  if [[ $boot_set_id -eq 1 ]]; then id_option="--bootloader-id=$boot_loader_id "; fi
  if [[ $boot_removable -eq 1 ]]; then removable_option="--removable"; fi

  echo "Installing grub"
  grub-install --target=x86_64-efi ${id_option}${removable_option} --recheck

  echo "Generating grub configuration"
  grub-mkconfig -o /boot/grub/grub.cfg
}

# Changes: user
setup_user() {
  echo "Adding user"
  useradd -m "$user_name"

  if [[ $user_set_password -eq 1 ]]; then
    echo "Changing password"
    echo "${user_name}:${user_password}" | chpasswd
  fi

  if [[ $user_set_sudo -eq 1 ]]; then
    echo "Setting up sudo"
    echo "${sudoers_options[$((user_sudo_mode - 1))]}" | EDITOR='tee -a' visudo

    echo "Adding user to wheel group"
    usermod -aG wheel "$user_name"
  fi
}

# Changes: network
setup_networking() {
  echo "Setting hostname"
  echo "$networking_hostname" >> /etc/hostname

  echo "Setting hosts"
  echo "127.0.0.1        localhost
  ::1              localhost
  127.0.1.1        $networking_hostname" >> /etc/hosts

  echo "Enabling services"
  systemctl enable NetworkManager
  systemctl enable dhcpcd
  if [[ $networking_iwd -eq 1 ]]; then systemctl enable iwd; fi

  if [[ $networking_set_dns -eq 1 ]]; then
    echo "Setting DNS servers"
    echo "static domain_name_servers=$networking_dns" >> /etc/dhcpcd.conf
  fi
}

# Changes: audio
setup_audio() {
  if [[ $audio_add_group -eq 1 ]]; then
    echo "Adding user to the audio group"
    usermod -aG audio "$user_name"
  fi

  if [[ $audio_enable_wireplumber -eq 1 ]]; then
    echo "Enabling wireplumber (pipewire session manager)"
    systemctl --user --now enable wireplumber
  fi
}

# Changes: desktop
setup_desktop() {
  if [[ $desktop_enable_display_manager -eq 1 ]]; then
    echo "Enabling display manager"
    systemctl enable $desktop_display_manager_service
  fi
}

# Before running
check_environment

# Collecting information
collect_localisation
collect_bootloader
collect_user
collect_networking
collect_graphics
collect_audio
collect_desktop
collect_packages

# Making changes
setup_packages
setup_localisation
setup_bootloader
setup_user
setup_networking
setup_audio
setup_desktop

# End
whiptail --nocancel --title "Arch Linux installer" --msgbox "The installation is done!\n\nYou can keep making changes to the new installation using chroot" 10 100
