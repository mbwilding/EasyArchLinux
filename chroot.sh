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

# Title
echo -e "${Title}Arch Linux (Chroot)${NC}"

# Helper functions
append_sudoers() {
  echo "$1" | tee -a /etc/sudoers > /dev/null
}

ask_and_execute() {
  local question=$1
  local callback=$2
  
  if [ "$USE_DEFAULTS" == "1" ]; then
    eval "${callback}"
  else
    echo -ne "${Prompt}${question} (${Default}Enter${Prompt})${NC}"
    read -rsn1 CONTINUE
    if [ "$CONTINUE" != $'\n' ]; then
      eval "${callback}"
    else
      CONTINUE=""
    fi
  fi
}

# Optional install functions
setup_swap() {
  pacman -S systemd-swap --noconfirm
  echo 'swapfc_enabled=1' >> /etc/systemd/swap.conf
  systemctl enable systemd-swap
}

setup_kde() {
  # Install and configure KDE with only the basics
  pacman -S xorg xorg-xinit plasma sddm dolphin konsole --noconfirm
  systemctl enable sddm
}

install() {
  LUKS_KEYS='/etc/luksKeys/boot.key' # Where you will store the root partition key
  UUID=$(cryptsetup luksDump "$DISK_PREFIX"3 | grep UUID | awk '{print $2}')
  CPU_VENDOR_ID=$(lscpu | grep Vendor | awk '{print $3}')
  
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
  echo "LANG=${LOCALE}.UTF-8" > /etc/locale.conf
  export LANG=${LOCALE}.UTF-8
  
  # Set hostname
  echo -e "${Heading}Setting hostname${NC}"
  echo "$HOSTNAME" > /etc/hostname
  echo "127.0.0.1 localhost localhost.localdomain $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
  
  echo "sshd : ALL : ALLOW" > /etc/hosts.allow
  echo "ALL: LOCAL, 127.0.0.1" >> /etc/hosts.allow
  echo "ALL: ALL" > /etc/hosts.deny
  
  # Enable and configure necessary services
  echo -e "${Heading}Enabling NetworkManager${NC}"
  systemctl enable NetworkManager
  
  echo -e "${Heading}Enabling OpenSSH${NC}"
  systemctl enable sshd
  
  # Create a group for sudo
  groupadd sudo
  append_sudoers "%sudo ALL=(ALL) ALL"
  
  # add a user
  echo -e "${Heading}Adding the user '$USERNAME'${NC}"
  groupadd $USERNAME
  useradd -g $USERNAME -G sudo,wheel,audio,video,optical -s /bin/bash -m $USERNAME
  
  # Set user password
  echo -e "${Heading}Setting user password${NC}"
  echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
  
  # Set root password
  echo -e "${Heading}Setting root password${NC}"
  echo "root:${ROOT_PASSWORD}" | chpasswd
  
  echo -e "${Heading}Setting up /home and .ssh/ of the user '$USERNAME'${NC}"
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
  
  echo -e "${Heading}Installing CPU µcode${NC}"
  # Use grep to check if the string 'Intel' is present in the CPU info
  if [[ $CPU_VENDOR_ID =~ "GenuineIntel" ]]; then
      pacman -S intel-ucode --noconfirm
  elif
      # If the string 'Intel' is not present, check if the string 'AMD' is present
      [[ $CPU_VENDOR_ID =~ "AuthenticAMD" ]]; then
      pacman -S amd-ucode --noconfirm
  else
      # If neither 'Intel' nor 'AMD' is present, then it is an unknown CPU
      echo -e "${Error}This is an unknown CPU${NC}"
  fi
  
  # Setup extras
  ask_and_execute "Install dynamic swap using systemd-swap?" setup_swap
  ask_and_execute "Install KDE Plasma?" setup_kde
  
  # Configure sudo
  echo -e "${Heading}Hardening sudo${NC}"
  
  # Set the secure path for sudo
  append_sudoers "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
  
  # Disable the ability to run commands with root password
  append_sudoers "Defaults !rootpw"
  
  # Set the default umask for sudo
  append_sudoers "Defaults umask=077"
  
  # Set the default editor for sudo
  append_sudoers "Defaults editor=/usr/bin/nano"
  
  # Set the default environment variables for sudo
  append_sudoers "Defaults env_reset"
  append_sudoers "Defaults env_reset,env_keep=\"COLORS DISPLAY HOSTNAME HISTSIZE INPUTRC KDEDIR LS_COLORS\""
  append_sudoers "Defaults env_keep += \"MAIL PS1 PS2 QTDIR USERNAME LANG LC_ADDRESS LC_CTYPE\""
  append_sudoers "Defaults env_keep += \"LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES\""
  append_sudoers "Defaults env_keep += \"LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE\""
  append_sudoers "Defaults env_keep += \"LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY\""
  
  # Set the security tweaks for sudoers file
  append_sudoers "Defaults timestamp_timeout=30"
  append_sudoers "Defaults !visiblepw"
  append_sudoers "Defaults always_set_home"
  append_sudoers "Defaults match_group_by_gid"
  append_sudoers "Defaults always_query_group_plugin"
  append_sudoers "Defaults passwd_timeout=10" # 10 minutes before sudo times out
  append_sudoers "Defaults passwd_tries=3" # Nr of attempts to enter password
  append_sudoers "Defaults loglinelen=0"
  append_sudoers "Defaults insults" # Insults user when wrong password is entered
  append_sudoers "Defaults lecture=once"
  append_sudoers "Defaults requiretty" # Forces to use real tty and not cron or cgi-bin
  append_sudoers "Defaults logfile=/var/log/sudo.log"
  append_sudoers "Defaults log_input, log_output" # Log input and output of sudo commands
  append_sudoers "@includedir /etc/sudoers.d"
  
  # Set permissions for /etc/sudoers
  echo -e "${Heading}Setting permissions for /etc/sudoers${NC}"
  chmod 440 /etc/sudoers
  chown root:root /etc/sudoers
  
  # GRUB hardening setup and encryption
  echo -e "${Heading}Adjusting /etc/mkinitcpio.conf for encryption...${NC}"
  sed -i "s|^HOOKS=.*|HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)|g" /etc/mkinitcpio.conf
  sed -i "s|^FILES=.*|FILES=(${LUKS_KEYS})|g" /etc/mkinitcpio.conf
  mkinitcpio -p "$KERNEL"
  
  echo -e "${Heading}Adjusting etc/default/grub for encryption...${NC}"
  sed -i '/GRUB_ENABLE_CRYPTODISK/s/^#//g' /etc/default/grub
  
  echo -e "${Heading}Hardening GRUB and Kernel boot options...${NC}"
  GRUBSEC="\"slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on randomize_kstack_offset=on vsyscall=none lockdown=confidentiality quiet loglevel=3\""
  GRUBCMD="\"cryptdevice=UUID=$UUID:$LVM_NAME root=/dev/mapper/$LVM_NAME-root cryptkey=rootfs:$LUKS_KEYS\""
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=${GRUBSEC}|g" /etc/default/grub
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=${GRUBCMD}|g" /etc/default/grub
  
  echo -e "${Heading}Setting up GRUB${NC}"
  grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  chmod 600 $LUKS_KEYS
  
  echo -e "${Heading}Setting permission on config files${NC}"
  
  chmod 0700 /boot
  chmod 644 /etc/passwd
  chown root:root /etc/passwd
  chmod 644 /etc/group
  chown root:root /etc/group
  chmod 600 /etc/shadow
  chown root:root /etc/shadow
  chmod 600 /etc/gshadow
  chown root:root /etc/gshadow
  chown root:root /etc/ssh/sshd_config
  chmod 600 /etc/ssh/sshd_config
  chown root:root /etc/fstab
  chown root:root /etc/issue
  chmod 644 /etc/issue
  chown root:root /boot/grub/grub.cfg
  chmod og-rwx /boot/grub/grub.cfg
  chown root:root /etc/sudoers.d/
  chmod 750 /etc/sudoers.d
  chown -c root:root /etc/sudoers
  chmod -c 0440 /etc/sudoers
  chmod 02750 /bin/ping 
  chmod 02750 /usr/bin/w 
  chmod 02750 /usr/bin/who
  chmod 02750 /usr/bin/whereis
  chmod 0600 /etc/login.defs
}

finish() {
  echo -e "${Success}Chroot script completed${NC}"
  exit
}

# Execution order
install
finish
