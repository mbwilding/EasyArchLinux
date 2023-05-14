#!/bin/bash

# Set up the colors
NC='\033[0m'
Blue='\033[1;34m'

# Helper functions
append_sudoers() {
  echo "$1" | tee -a /etc/sudoers > /dev/null
}

ask_and_execute() {
  local question=$1
  local callback=$2
  local skip_message=$3
  read -rp "${question} (Press Enter to continue, type 'n' to skip): " RESPONSE
  if [[ -z "${RESPONSE,,}" ]]; then
    eval "${callback}"
  else
    echo "Skipping: ${skip_message}"
  fi
}

# Optional install functions
setup_swap() {
  pacman -S systemd-swap --noconfirm
  echo 'swapfc_enabled=1' >> /etc/systemd/swap.conf
  systemctl enable systemd-swap
  echo "Dynamic swap setup complete."
}

setup_pamac() {
  # Update Arch
  pacman -Syu --noconfirm
  
  # Get dependencies
  pacman -S --needed git base-devel --noconfirm
  
  # Clone YAY
  cd /tmp && git clone https://aur.archlinux.org/yay.git
  
  # Run install as non-root
  sudo chown -R $USERNAME:$USERNAME /tmp/yay
  sudo -u $USERNAME bash -c 'cd /tmp/yay && makepkg -si --noconfirm && yay -S pamac-aur --noconfirm'
  
  # Enable AUR support in Pamac
  sudo sed -i 's/#EnableAUR/EnableAUR/' /etc/pamac.conf
  sudo sed -i 's/#CheckAURUpdates/CheckAURUpdates/' /etc/pamac.conf
  
  echo "Pamac setup complete."
}

setup_kde() {
  # Install and configure KDE with only the basics
  pacman -S xorg xorg-xinit plasma sddm dolphin konsole --noconfirm
  systemctl enable sddm

  echo "KDE Plasma setup complete."
}

# The below values will be changed by ArchInstall.sh
DISK_PREFIX='<your_target_disk>'
LVM_NAME='lvm_arch'
USERNAME='<user_name_goes_here>'
HOSTNAME='<hostname_goes_here>'
LOCALE='<locale_goes_here>'
TIMEZONE='<timezone_goes_here>'
KERNEL='<kernel_goes_here>'

LUKS_KEYS='/etc/luksKeys/boot.key' # Where you will store the root partition key
UUID=$(cryptsetup luksDump "$DISK_PREFIX"3 | grep UUID | awk '{print $2}')
CPU_VENDOR_ID=$(lscpu | grep Vendor | awk '{print $3}')

pacman-key --init
pacman-key --populate archlinux

# Set the timezone
echo -e "${Blue}Setting the timezone...${NC}"
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc --utc

# Set up locale
echo -e "${Blue}Setting up locale...${NC}"
sed -i "/#${LOCALE}.UTF-8/s/^#//g" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}.UTF-8" > /etc/locale.conf
export LANG=${LOCALE}.UTF-8

# Set hostname
echo -e "${Blue}Setting hostname...${NC}"
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost localhost.localdomain $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

echo "sshd : ALL : ALLOW" > /etc/hosts.allow
echo "ALL: LOCAL, 127.0.0.1" >> /etc/hosts.allow
echo "ALL: ALL" > /etc/hosts.deny

# Enable and configure necessary services
echo -e "${Blue}Enabling NetworkManager...${NC}"
systemctl enable NetworkManager

echo -e "${Blue}Enabling OpenSSH...${NC}"
systemctl enable sshd

# Create a group for sudo
groupadd sudo
append_sudoers "%sudo ALL=(ALL) ALL"

# add a user
echo -e "${Blue}Adding the user $USERNAME...${NC}"
groupadd $USERNAME
useradd -g $USERNAME -G sudo,wheel,audio,video,optical -s /bin/bash -m $USERNAME
passwd $USERNAME

echo -e "${Blue}Setting up /home and .ssh/ of the user $USERNAME...${NC}"
mkdir /home/$USERNAME/.ssh
touch /home/$USERNAME/.ssh/authorized_keys
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME

# Set default ACLs on home directory 
echo -e "${Blue}Setting default ACLs on home directory${NC}"
setfacl -d -m u::rwx,g::---,o::--- ~

# Setup extras
ask_and_execute "Install dynamic swap using systemd-swap?" setup_swap "Dynamic swap setup."
ask_and_execute "Install Pamac from the AUR?" setup_pamac "Pamac setup."
ask_and_execute "Install KDE Plasma?" setup_kde "KDE Plasma setup."

# Configure sudo
echo -e "${Blue}Hardening sudo...${NC}"

# Set the secure path for sudo.
append_sudoers "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""

# Disable the ability to run commands with root password.
append_sudoers "Defaults !rootpw"

# Set the default umask for sudo.
append_sudoers "Defaults umask=077"

# Set the default editor for sudo.
append_sudoers "Defaults editor=/usr/bin/nano"

# Set the default environment variables for sudo.
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
echo -e "${Blue}Setting permissions for /etc/sudoers${NC}"
chmod 440 /etc/sudoers 
chown root:root /etc/sudoers

# GRUB hardening setup and encryption
echo -e "${Blue}Adjusting /etc/mkinitcpio.conf for encryption...${NC}"
sed -i "s|^HOOKS=.*|HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)|g" /etc/mkinitcpio.conf
sed -i "s|^FILES=.*|FILES=(${LUKS_KEYS})|g" /etc/mkinitcpio.conf
mkinitcpio -p "$KERNEL"

echo -e "${Blue}Adjusting etc/default/grub for encryption...${NC}"
sed -i '/GRUB_ENABLE_CRYPTODISK/s/^#//g' /etc/default/grub

echo -e "${Blue}Hardening GRUB and Kernel boot options...${NC}"

# GRUBSEC Hardening explanation:
# slab_nomerge: This disables slab merging, which significantly increases the difficulty of heap exploitation
# init_on_alloc=1 init_on_free=1: enables zeroing of memory during allocation and free time, which can help mitigate use-after-free vulnerabilities and erase sensitive information in memory.
# page_alloc.shuffle=1: randomises page allocator freelists, improving security by making page allocations less predictable. This also improves performance.
# pti=on: enables Kernel Page Table Isolation, which mitigates Meltdown and prevents some KASLR bypasses.
# randomize_kstack_offset=on:  randomises the kernel stack offset on each syscall, which makes attacks that rely on deterministic kernel stack layout significantly more difficult
# vsyscall=none: disables vsyscalls, as they are obsolete and have been replaced with vDSO. vsyscalls are also at fixed addresses in memory, making them a potential target for ROP attacks.
# lockdown=confidentiality: eliminate many methods that user space code could abuse to escalate to kernel privileges and extract sensitive information.
GRUBSEC="\"slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on randomize_kstack_offset=on vsyscall=none lockdown=confidentiality quiet loglevel=3\""
GRUBCMD="\"cryptdevice=UUID=$UUID:$LVM_NAME root=/dev/mapper/$LVM_NAME-root cryptkey=rootfs:$LUKS_KEYS\""
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=${GRUBSEC}|g" /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=${GRUBCMD}|g" /etc/default/grub

echo -e "${Blue}Setting up GRUB...${NC}"
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg
chmod 600 $LUKS_KEYS

echo -e "${Blue}Installing CPU ucode...${NC}"
# Use grep to check if the string 'Intel' is present in the CPU info
if [[ $CPU_VENDOR_ID =~ "GenuineIntel" ]]; then
    pacman -S intel-ucode --noconfirm
elif
    # If the string 'Intel' is not present, check if the string 'AMD' is present
    [[ $CPU_VENDOR_ID =~ "AuthenticAMD" ]]; then
    pacman -S amd-ucode --noconfirm
else
    # If neither 'Intel' nor 'AMD' is present, then it is an unknown CPU
    echo "This is an unknown CPU."
fi

echo -e "${Blue}Setting permission on config files...${NC}"

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

echo -e "${Blue}Setting root password...${NC}"
passwd

# Finished
echo -e "${Blue}Installation completed!${NC}"
rm /chroot.sh
exit
