#!/bin/bash

# Default Settings
DEFAULT_COUNTRY="Australia"
DEFAULT_CITY="Perth"
DEFAULT_LOCALE="en_AU"
DEFAULT_USERNAME="user"
DEFAULT_HOSTNAME="arch"
DEFAULT_KERNEL="linux-zen"

# Set up the colors
NC='\033[0m'
Blue='\033[1;34m'

# Helper functions
capitalize_first_letter() {
  input_string="$1"
  if [ -z "$input_string" ]; then
    echo ""
  else
    first_letter=$(echo "${input_string:0:1}" | tr '[:lower:]' '[:upper:]')
    rest_of_string="${input_string:1}"
    echo "$first_letter$rest_of_string"
  fi
}

# Check if user is root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

# Take action if UEFI is supported.
if [ ! -d "/sys/firmware/efi/efivars" ]; then
  echo -e "${Blue}UEFI is not supported.${NC}"
  exit 1
else
   echo -e "${Blue}\n UEFI is supported, proceeding...\n${NC}"
fi

# Get user input for locale settings
echo -e "${Blue}Pressing enter will use the default specified in the parentheses.\n${NC}"

# Select a disk to install to
readarray -t AVAILABLE_DISKS < <(lsblk -d -o NAME,TYPE | grep 'disk' | awk '{print $1}')
FIRST_DISK=${AVAILABLE_DISKS[0]}
echo -e "${Blue}The following disks are available on your system:${NC}"
echo "${AVAILABLE_DISKS[@]}"
read -rp "Select the target disk ($FIRST_DISK): " TARGET_DISK
TARGET_DISK=${TARGET_DISK:-$FIRST_DISK}

# Validate user input
valid_disk_selection=false
for disk in "${AVAILABLE_DISKS[@]}"; do
  if [[ $disk == "$TARGET_DISK" ]]; then
    valid_disk_selection=true
    break
  fi
done

if ! $valid_disk_selection; then
  echo "Invalid disk selection: $TARGET_DISK"
  echo "Please select one of the available disks."
  exit 1
fi

read -rp "Enter your country (${DEFAULT_COUNTRY}): " COUNTRY
COUNTRY=$(capitalize_first_letter "${COUNTRY:-${DEFAULT_COUNTRY}}")

read -rp "Enter your city (${DEFAULT_CITY}): " CITY
CITY=$(capitalize_first_letter "${CITY:-${DEFAULT_CITY}}")

read -rp "Enter your locale (${DEFAULT_LOCALE}): " LOCALE
LOCALE=${LOCALE:-${DEFAULT_LOCALE}}

# Select your desired kernel
read -rp "Enter the desired kernel (${DEFAULT_KERNEL}): " KERNEL
KERNEL=${KERNEL:-${DEFAULT_KERNEL}}
echo -e "\n"

# Setup username and host
echo -e "${Blue}Choosing a username and a hostname:${NC}"

read -rp "Enter the new user (${DEFAULT_USERNAME}): " USERNAME
USERNAME=${USERNAME:-${DEFAULT_USERNAME}}

read -rp "Enter the new hostname (${DEFAULT_HOSTNAME}): " HOSTNAME
HOSTNAME=${HOSTNAME:-${DEFAULT_HOSTNAME}}
echo -e "\n"

# Use the correct variable name for the target disk
TIMEZONE="$COUNTRY/$CITY"
DISK="/dev/$TARGET_DISK"
CRYPT_NAME='crypt_lvm' # the name of the LUKS container.
LVM_NAME='lvm_arch' # the name of the logical volume.
LUKS_KEYS='/etc/luksKeys' # Where you will store the root partition key

# Check if settings are correct
echo -e "${Blue}Confirm Settings:${NC}"
echo "Country: ${COUNTRY}"
echo "City: ${CITY}"
echo "Locale: ${LOCALE}"
echo "Disk: ${TARGET_DISK}"
echo "Kernel: ${KERNEL}"
echo "User: ${USERNAME}"
echo "Host: ${HOSTNAME}"

read -rp "Do you want to continue? (Press Enter): " CONTINUE
if [[ -n "$CONTINUE" ]]; then
  echo "Exiting..."
  exit 1
fi

# Setting time correctly before installation
timedatectl set-ntp true

# Wipe out partitions
echo -e "${Blue}Wiping all partitions on disk $DISK...${NC}"
sgdisk -Z "$DISK"

# Partition the disk
echo -e "${Blue}Preparing disk $DISK for UEFI and Encryption...${NC}"
sgdisk -og "$DISK"

# Create a 1MiB BIOS boot partition
echo -e "${Blue}Creating a 1MiB BIOS boot partition...${NC}"
sgdisk -n 1:2048:4095 -t 1:ef02 -c 1:"BIOS boot Partition" "$DISK"

# Create a UEFI partition
echo -e "${Blue}Creating a UEFI partition...${NC}"
sgdisk -n 2:4096:1130495 -t 2:ef00 -c 2:"EFI" "$DISK"

# Create a LUKS partition
echo -e "${Blue}Creating a LUKS partition...${NC}"
sgdisk -n 3:1130496:"$(sgdisk -E "$DISK")" -t 3:8309 -c 3:"Linux LUKS" "$DISK"

# Create the LUKS container
echo -e "${Blue}Creating the LUKS container...${NC}"

# Set partition variable, handles nvme partitioning case
if [[ $DISK == /dev/nvme* ]]; then
    DISK_PREFIX="${DISK}p"
else
    DISK_PREFIX="${DISK}"
fi

# Encrypts with the best key size. (Will prompt for a password)
cryptsetup -q --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 3000 --use-random  luksFormat --type luks1 "$DISK_PREFIX"3

# Opening LUKS container to test
echo -e "${Blue}Opening the LUKS container to test password...${NC}"
cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME
cryptsetup -v luksClose $CRYPT_NAME

# create a LUKS key of size 2048 and save it as boot.key
echo -e "${Blue}Creating the LUKS key for $CRYPT_NAME...${NC}"
dd if=/dev/urandom of=./boot.key bs=2048 count=1
cryptsetup -v luksAddKey -i 1 "$DISK_PREFIX"3 ./boot.key

# unlock LUKS container with the boot.key file
echo -e "${Blue}Testing the LUKS keys for $CRYPT_NAME...${NC}"
cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME --key-file ./boot.key
echo -e "\n"

# Create the LVM physical volume, volume group and logical volume
echo -e "${Blue}Creating LVM logical volumes on $LVM_NAME...${NC}"
pvcreate --verbose /dev/mapper/$CRYPT_NAME
vgcreate --verbose $LVM_NAME /dev/mapper/$CRYPT_NAME
lvcreate --verbose -l 100%FREE $LVM_NAME -n root

# Format the partitions 
echo -e "${Blue}Formatting filesystems...${NC}"
mkfs.ext4 /dev/mapper/$LVM_NAME-root

# Mount filesystem
echo -e "${Blue}Mounting filesystems...${NC}"
mount --verbose /dev/mapper/$LVM_NAME-root /mnt
mkdir --verbose /mnt/home
mkdir --verbose -p /mnt/tmp

# Mount efi
echo -e "${Blue}Preparing the EFI partition...${NC}"
mkfs.vfat -F32 "$DISK_PREFIX"2
mkdir --verbose /mnt/efi
mount --verbose "$DISK_PREFIX"2 /mnt/efi

# Update the keyring for the packages
echo -e "${Blue}Updating Arch key-rings...${NC}" 
pacman -Sy archlinux-keyring --noconfirm

# Install Arch Linux base system. Add or remove packages as you wish.
echo -e "${Blue}Installing Arch Linux base system...${NC}" 
echo -ne "\n\n\n" | pacstrap -i /mnt base base-devel archlinux-keyring "$KERNEL" "$KERNEL"-headers \
                    linux-firmware lvm2 grub efibootmgr dosfstools os-prober mtools \
                    networkmanager wget curl git nano openssh unzip unrar p7zip neofetch zsh \
                    zip unarj arj cabextract xz pbzip2 pixz lrzip cpio gdisk go rsync sudo

# Generate fstab file
echo -e "${Blue}Generating fstab file...${NC}" 
genfstab -pU /mnt >> /mnt/etc/fstab

echo -e "${Blue}Copying the $CRYPT_NAME key to $LUKS_KEYS ...${NC}" 
mkdir --verbose /mnt$LUKS_KEYS
cp ./boot.key /mnt$LUKS_KEYS/boot.key
rm ./boot.key

# Add an entry to fstab so the new mountpoint will be mounted on boot
echo -e "${Blue}Adding tmpfs to fstab...${NC}" 
echo "tmpfs /tmp tmpfs rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >> /mnt/etc/fstab
echo -e "${Blue}Adding proc to fstab and hardening it...${NC}" 
echo "proc /proc proc nosuid,nodev,noexec,hidepid=2,gid=proc 0 0" >> /etc/fstab
touch /etc/systemd/system/systemd-logind.service.d/hidepid.conf
echo "[Service]" >> /etc/systemd/system/systemd-logind.service.d/hidepid.conf
echo "SupplementaryGroups=proc" >> /etc/systemd/system/systemd-logind.service.d/hidepid.conf

# Preparing the chroot script to be executed
echo -e "${Blue}Preparing the chroot script to be executed...${NC}"
cp ./chroot.sh /mnt
CHROOT="/mnt/chroot.sh"
sed -i "s|^DISK_PREFIX=.*|DISK_PREFIX='${DISK_PREFIX}'|g" $CHROOT
sed -i "s|^LVM_NAME=.*|LVM_NAME='${LVM_NAME}'|g" $CHROOT
sed -i "s|^USERNAME=.*|USERNAME='${USERNAME}'|g" $CHROOT
sed -i "s|^HOSTNAME=.*|HOSTNAME='${HOSTNAME}'|g" $CHROOT
sed -i "s|^LOCALE=.*|LOCALE='${LOCALE}'|g" $CHROOT
sed -i "s|^TIMEZONE=.*|TIMEZONE='${TIMEZONE}'|g" $CHROOT
sed -i "s|^KERNEL=.*|KERNEL='${KERNEL}'|g" $CHROOT
chmod +x $CHROOT

# Chroot into new system and configure it 
echo -e "${Blue}CH-ROOTing into new system and configuring it...${NC}"
arch-chroot /mnt /bin/bash ./chroot.sh

# Finished
read -rp "Do you want to reboot now? (Press Enter to continue, type 'n' to skip): " REBOOT
if [[ -z "${REBOOT,,}" ]]; then
    echo "Rebooting now."
    reboot
else
    echo "Skipping reboot. Remember to manually reboot when ready."
fi
