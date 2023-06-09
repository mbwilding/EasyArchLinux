#!/bin/bash

# Set up the colors
NC='\033[0m' # No Color
Error='\033[1;31m'
Success='\033[1;32m'
Heading='\033[1;33m'
Prompt='\033[1;34m'
Default='\033[0;35m'
Title='\033[1;36m'

# The below values will be changed by install.sh
USE_DEFAULTS='<use_defaults>'
DISK_PREFIX='<disk_prefix>'
LVM_NAME='<lvm_name>'
USERNAME='<username>'
HOSTNAME='<hostname>'
USER_PASSWORD='<user_password>'
ROOT_PASSWORD='<root_password>'
LOCALE='<locale>'
TIMEZONE='<timezone>'
KERNEL='<kernel>'
DESKTOP_ENVIRONMENT='<desktop_environment>'
GPU='<gpu>'
PACMAN_PARA='<pacman_para>'

# Forward declarations
GRUB_GPU=""

# Title
echo -e "${Title}Arch Linux (${Default}Chroot${Title})${NC}"

# Helper functions
append_sudoers() {
  echo "$1" | tee -a /etc/sudoers >/dev/null
}

ask_and_execute() {
  local question=$1
  local callback=$2

  if [ "$USE_DEFAULTS" == "1" ]; then
    eval "${callback}"
    return
  else
    echo -ne "${Prompt}${question} (${Default}Enter${Prompt})${NC}"
    read -rsn1 CONTINUE
    if [ "$CONTINUE" != $'\n' ]; then
      eval "${callback}"
    else
      CONTINUE=""
    fi
  fi
  echo
}

# Optional install functions
setup_swap() {
  pacman -S systemd-swap --noconfirm
  sed -i 's/#swapfc_enabled=0/swapfc_enabled=1/g' /etc/systemd/swap.conf
  systemctl enable systemd-swap
}

# Parallel downloads for pacman
pacman_para() {
  echo -e "${Heading}Pacman set to download ${Default}${PACMAN_PARA}${Heading} packages concurrently${NC}"

  if [[ ! $PACMAN_PARA =~ ^(0|1)$ ]]; then
    sed -i "s/^#\(ParallelDownloads = \).*/\1$PACMAN_PARA/" /etc/pacman.conf
  fi
}

# Setup GPU
setup_gpu() {
  if [ -z "$GPU" ]; then return; fi

  echo -e "${Heading}Installing GPU drivers ${Default}${GPU^^}${NC}"

  case "$GPU" in
  "nvidia")
    setup_nvidia
    ;;
  "amd") # TODO
    echo -e "${Error}AMD: Not implemented${NC}"
    ;;
  "intel") # TODO
    echo -e "${Error}INTEL: Not implemented${NC}"
    ;;
  esac
}

# GPU specific
setup_nvidia() {
  # Blacklist Nouveau driver
  mkdir -p /etc/modprobe.d/
  echo "blacklist nouveau" >/etc/modprobe.d/nouveau_blacklist.conf

  # Install
  pacman -S --needed --noconfirm nvidia-dkms nvidia-settings nvidia-prime

  # Kernel
  echo -e "${Heading}Adding GRUB parameters"
  GRUB_GPU="nvidia_drm.modeset=1"

  # Modules
  sed -i "s|^MODULES=.*|MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)|g" /etc/mkinitcpio.conf

  # Create X11 config
  nvidia-xconfig

  # Pacman Hook
  echo -e "${Heading}Adding pacman hook ${Default}/etc/pacman.d/hooks/nvidia.hook${NC}"
  mkdir -p /etc/pacman.d/hooks/
  cat >/etc/pacman.d/hooks/nvidia.hook <<EOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-dkms
Target=$KERNEL

[Action]
Description=Update NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in $KERNEL) exit 0; esac; done; /usr/bin/mkinitcpio -p $KERNEL'
EOF
}

setup_bluetooth() {
  pacman -S bluez bluez-utils
  systemctl enable bluetooth
  usermod -a -G lp $USERNAME
}

# Desktop environments
setup_desktop_environment() {
  echo -e "${Heading}Installing Desktop Environment ${Default}${DESKTOP_ENVIRONMENT^^}${NC}"

  case "$DESKTOP_ENVIRONMENT" in
  "kde")
    pacman -S --needed --noconfirm xorg xorg-xinit plasma-meta sddm packagekit-qt5 konsole
    systemctl enable sddm
    ;;
  "mate")
    pacman -S --needed --noconfirm xorg xorg-xinit mate mate-extra lightdm mate-terminal
    systemctl enable lightdm
    ;;
  "gnome")
    pacman -S --needed --noconfirm xorg xorg-xinit gnome gdm gnome-terminal
    systemctl enable gdm
    ;;
  "cinnamon")
    pacman -S --needed --noconfirm xorg xorg-xinit cinnamon lightdm gnome-terminal
    systemctl enable lightdm
    ;;
  "budgie")
    pacman -S --needed --noconfirm xorg xorg-xinit budgie-desktop lightdm gnome-terminal
    systemctl enable lightdm
    ;;
  "lxqt")
    pacman -S --needed --noconfirm xorg xorg-xinit lxqt sddm xdg-utils oxygen-icons qterminal
    systemctl enable sddm
    # TODO The icons are blank by default, you can set them to oxygen in the appearance settings
    ;;
  "xfce")
    pacman -S --needed --noconfirm xorg xorg-xinit xfce4 xfce4-goodies lightdm xfce4-terminal
    systemctl enable lightdm
    ;;
  "deepin")
    pacman -S --needed --noconfirm xorg xorg-xinit deepin deepin-kwin deepin-extra lightdm gvfs-smb deepin-terminal
    systemctl enable lightdm
    ;;
  esac
}

# Functions
setup_ucode() {
  echo -e "${Heading}Installing CPU µcode${NC}"
  # Use grep to check if the string 'Intel' is present in the CPU info
  if [[ $CPU_VENDOR_ID =~ "GenuineIntel" ]]; then
    pacman -S intel-ucode --noconfirm
  elif
    # If the string 'Intel' is not present, check if the string 'AMD' is present
    [[ $CPU_VENDOR_ID =~ "AuthenticAMD" ]]
  then
    pacman -S amd-ucode --noconfirm
  else
    # If neither 'Intel' nor 'AMD' is present, then it is an unknown CPU
    echo -e "${Error}This is an unknown CPU${NC}"
  fi
}

sudo_harden() {
  # Configure sudo
  echo -e "${Heading}Hardening sudo${NC}"

  # Sudoers entries
  sudoers_entries=(
    "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
    "Defaults !rootpw"
    "Defaults umask=077"
    "Defaults editor=/usr/bin/nano"
    "Defaults env_reset"
    "Defaults env_reset,env_keep=\"COLORS DISPLAY HOSTNAME HISTSIZE INPUTRC KDEDIR LS_COLORS\""
    "Defaults env_keep += \"MAIL PS1 PS2 QTDIR USERNAME LANG LC_ADDRESS LC_CTYPE\""
    "Defaults env_keep += \"LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES\""
    "Defaults env_keep += \"LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE\""
    "Defaults env_keep += \"LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY\""
    "Defaults timestamp_timeout=30"
    "Defaults !visiblepw"
    "Defaults always_set_home"
    "Defaults match_group_by_gid"
    "Defaults always_query_group_plugin"
    "Defaults passwd_timeout=10"
    "Defaults passwd_tries=3"
    "Defaults loglinelen=0"
    "Defaults insults"
    "Defaults lecture=once"
    "Defaults requiretty"
    "Defaults logfile=/var/log/sudo.log"
    "Defaults log_input, log_output"
    "@includedir /etc/sudoers.d"
  )

  # Append each entry to sudoers file
  for entry in "${sudoers_entries[@]}"; do
    append_sudoers "$entry"
  done

  # Set permissions for /etc/sudoers
  echo -e "${Heading}Setting permissions for ${Default}/etc/sudoers${NC}"
  chmod 440 /etc/sudoers
  chown root:root /etc/sudoers
}

grub_harden() {
  # GRUB hardening setup and encryption
  echo -e "${Heading}Adjusting ${Default}/etc/mkinitcpio.conf${Heading} for encryption${NC}"
  sed -i "s|^HOOKS=.*|HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)|g" /etc/mkinitcpio.conf
  sed -i "s|^FILES=.*|FILES=(${LUKS_KEYS})|g" /etc/mkinitcpio.conf
  mkinitcpio -p "$KERNEL"

  echo -e "${Heading}Adjusting ${Default}/etc/default/grub${Heading} for encryption${NC}"
  sed -i '/GRUB_ENABLE_CRYPTODISK/s/^#//g' /etc/default/grub

  echo -e "${Heading}Hardening GRUB and Kernel boot options${NC}"

  # TODO Using GPU dkms causes boot failure when hardened, disabled if using GPU dkms. Will revise hardening.
  if [ "$GPU" = "none" ]; then
    GRUBSEC=""
    # GRUBSEC="slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on randomize_kstack_offset=on vsyscall=none lockdown=confidentiality"
  else
    GRUBSEC=""
  fi

  GRUBCMD="cryptdevice=UUID=$UUID:$LVM_NAME root=/dev/mapper/$LVM_NAME-root cryptkey=rootfs:$LUKS_KEYS"
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUBSEC quiet loglevel=3\"|g" /etc/default/grub
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$GRUBCMD $GRUB_GPU\"|g" /etc/default/grub

  echo -e "${Heading}Setting up GRUB${NC}"
  grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  chmod 600 "$LUKS_KEYS"

  echo -e "${Heading}Setting permission on config files${NC}"
  # Define arrays for different file paths based on the operations required
  files_0700=(/boot)                                   # 0700: Owner has read, write, and execute permissions; group and others have no permissions
  files_644=(/etc/passwd /etc/group /etc/issue)        # 644: Owner has read and write permissions; group and others have read permissions
  files_600=(/etc/shadow /etc/gshadow /etc/login.defs) # 600: Owner has read and write permissions; group and others have no permissions
  files_750=(/etc/sudoers.d)                           # 750: Owner has read, write, and execute permissions; group has read and execute permissions; others have no permissions
  files_440=(/etc/sudoers)                             # 440: Owner has read permissions; group has read permissions; others have no permissions
  files_og_rwx=(/boot/grub/grub.cfg)                   # og-rwx: Remove read, write, and execute permissions for group and others

  # Changing ownership to root:root
  chown_files=(/etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/ssh/sshd_config /etc/fstab /etc/issue /boot/grub/grub.cfg /etc/sudoers.d /etc/sudoers)

  # Change permissions for different groups of files
  for file in "${files_0700[@]}"; do chmod 0700 $file; done
  for file in "${files_644[@]}"; do chmod 644 $file; done
  for file in "${files_600[@]}"; do chmod 600 $file; done
  for file in "${files_750[@]}"; do chmod 750 $file; done
  for file in "${files_440[@]}"; do chmod 0440 $file; done
  for file in "${files_og_rwx[@]}"; do chmod og-rwx $file; done

  # Change ownership
  for file in "${chown_files[@]}"; do chown root:root $file; done
}

install() {
  LUKS_KEYS='/etc/luksKeys/boot.key' # Where you will store the root partition key
  UUID=$(cryptsetup luksDump "$DISK_PREFIX"3 | grep UUID | awk '{print $2}')
  CPU_VENDOR_ID=$(lscpu | grep Vendor | awk '{print $3}')

  # Enable multilib
  sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//g}' /etc/pacman.conf

  pacman_para
  pacman-key --init
  pacman-key --populate archlinux

  # Set the timezone
  echo -e "${Heading}Setting the timezone${NC}"
  ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  hwclock --systohc --utc

  # Set up locale
  echo -e "${Heading}Setting the locale${NC}"
  sed -i "/#${LOCALE}.UTF-8/s/^#//g" /etc/locale.gen
  locale-gen
  echo "LANG=${LOCALE}.UTF-8" >/etc/locale.conf
  export LANG=${LOCALE}.UTF-8

  # Set host name
  echo -e "${Heading}Setting hostname and host files${NC}"
  echo "$HOSTNAME" >/etc/hostname

  # Set host file
  echo -e "127.0.0.1\tlocalhost" >/etc/hosts
  echo -e "::1\tlocalhost" >/etc/hosts
  echo -e "127.0.1.1\t$HOSTNAME.localdomain\t$HOSTNAME" >/etc/hosts

  # Set host permissions
  echo "sshd : ALL : ALLOW" >/etc/hosts.allow
  echo "ALL: LOCAL, 127.0.0.1, 127.0.1.1, ::1" >>/etc/hosts.allow
  echo "ALL: ALL" >/etc/hosts.deny

  # Enable and configure necessary services
  echo -e "${Heading}Enabling NetworkManager${NC}"
  systemctl enable NetworkManager

  echo -e "${Heading}Enabling OpenSSH${NC}"
  systemctl enable sshd

  # Create a group for sudo
  groupadd sudo
  append_sudoers "%sudo ALL=(ALL) ALL"

  # add a user
  echo -e "${Heading}Adding the user ${Default}${USERNAME}${NC}"
  groupadd $USERNAME
  useradd -g $USERNAME -G sudo,wheel,audio,video,optical -s /bin/bash -m $USERNAME

  # Set user password
  echo -e "${Heading}Setting user password${NC}"
  echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

  # Set root password
  echo -e "${Heading}Setting root password${NC}"
  echo "root:${ROOT_PASSWORD}" | chpasswd

  echo -e "${Heading}Setting up ${Default}/home${Heading} and ${Default}.ssh/${Heading} of the user ${Default}$USERNAME${NC}"
  mkdir /home/$USERNAME/.ssh
  touch /home/$USERNAME/.ssh/authorized_keys
  chmod 700 /home/$USERNAME/.ssh
  chmod 600 /home/$USERNAME/.ssh/authorized_keys
  chown -R $USERNAME:$USERNAME /home/$USERNAME

  # Set default ACLs on home directory
  echo -e "${Heading}Setting default ACLs on home directory${NC}"
  setfacl -d -m u::rwx,g::---,o::--- ~

  # Update Arch
  pacman -Syu --noconfirm

  #ucode
  setup_ucode

  #gpu
  setup_gpu

  # Bluetooth
  setup_bluetooth

  # Harden
  sudo_harden
  grub_harden

  # Desktop Environment
  setup_desktop_environment

  # Setup extras
  setup_swap
  # ask_and_execute "Install dynamic swap using systemd-swap?" setup_swap
}

finish() {
  echo -e "${Success}Chroot script completed${NC}"
  exit
}

# Execution order
install
finish
