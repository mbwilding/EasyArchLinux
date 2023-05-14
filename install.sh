#!/bin/bash

# Default Settings
DEFAULT_HOSTNAME="arch"
DEFAULT_USERNAME="user"
DEFAULT_COUNTRY="Australia"
DEFAULT_CITY="Perth"
DEFAULT_LOCALE="en_AU"
DEFAULT_KERNEL="linux-zen"

# Set up the colors
NC='\033[0m' # No Color
Prompt='\033[1;34m'
Error='\033[1;31m'
Success='\033[1;32m'
Heading='\033[1;33m'
Standard='\033[0;37m'
Default='\033[0;35m'

# Helper functions
prompt_user() {
    local prompt=$1
    local var_name=$2
    local capitalize=$3
    local default_var_name="DEFAULT_${var_name^^}"

    echo -ne "${Prompt}${prompt} (${Default}${!default_var_name}${Prompt}): ${NC}"
    read -r response
    if [ "$capitalize" = true ]; then
        response=$(capitalize_first_letter "$response")
    fi
    eval $var_name=${response:-${!default_var_name}}
}

prompt_continue() {
    echo -n "Do you want to continue? (Press Enter to continue, any other key to exit): "
    read -rsn1 CONTINUE
    if [ "$CONTINUE" != "" ]; then
      echo -e "\n${Error}Exiting${NC}"
      exit 1
    fi
    echo
}

capitalize_first_letter() {
  input_string="$1"
  if [ -z "$input_string" ]; then
    echo ""
  else
    input_string=$(echo "$input_string" | tr '[:upper:]' '[:lower:]')
    first_letter=$(echo "${input_string:0:1}" | tr '[:lower:]' '[:upper:]')
    rest_of_string="${input_string:1}"
    echo "$first_letter$rest_of_string"
  fi
}

# Check if user is root
if [ "$(id -u)" != "0" ]; then
   echo -e "${Error}This script must be run as root.${NC}" 1>&2
   exit 1
fi

# Exit if UEFI is not supported.
if [ ! -d "/sys/firmware/efi/efivars" ]; then
  echo -e "${Error}UEFI is not supported${NC}"
  exit 1
fi

# Select a disk to install to
readarray -t AVAILABLE_DISKS < <(lsblk -d -o NAME,TYPE,SIZE | grep 'disk' | awk '{print $1, $3}')
# shellcheck disable=SC2034
DEFAULT_TARGET_DISK=$(echo "${AVAILABLE_DISKS[0]}" | awk '{print $1}')

while true; do
    echo -e "${Heading}The following disks are available on your system${NC}"
    printf "%-10s %-10s\n" "Disk" "Size"
    for disk in "${AVAILABLE_DISKS[@]}"; do
        IFS=' ' read -r -a arr <<< "$disk"
        printf "%-10s %-10s\n" "${arr[0]}" "${arr[1]}"
    done

    prompt_user "Enter the target disk" TARGET_DISK
    
    # Check if the selected disk is valid
    is_valid=false
    for available_disk in "${AVAILABLE_DISKS[@]}"; do
        if [[ "$available_disk" == *"$TARGET_DISK"* ]]; then
            is_valid=true
            break
        fi
    done

    if $is_valid; then
        break
    else
        echo -e "${Error}Invalid disk${NC}"
    fi
done

# Setup username and hostname
echo -e "${Heading}Choosing a hostname and username${NC}"
prompt_user "Enter the new hostname" HOSTNAME
prompt_user "Enter the new user" USERNAME

# Setup region
echo -e "${Heading}Set your region information${NC}"
prompt_user "Enter your country" COUNTRY true
prompt_user "Enter your city" CITY true
prompt_user "Enter your locale" LOCALE

# Select your desired kernel
echo -e "${Heading}Set your kernel${NC}"
prompt_user "Enter the desired kernel" KERNEL

# Use the correct variable name for the target disk
TIMEZONE="$COUNTRY/$CITY"
DISK="/dev/$TARGET_DISK"
CRYPT_NAME='crypt_lvm' # the name of the LUKS container.
LVM_NAME='lvm_arch' # the name of the logical volume.
LUKS_KEYS='/etc/luksKeys' # Where you will store the root partition key

# Check if settings are correct
echo -e "${Heading}Confirm Settings${NC}"
echo -e "${Prompt}Country: ${Default}${COUNTRY}${NC}"
echo -e "${Prompt}City: ${Default}${CITY}${NC}"
echo -e "${Prompt}Locale: ${Default}${LOCALE}${NC}"
echo -e "${Prompt}Disk: ${Default}${TARGET_DISK}${NC}"
echo -e "${Prompt}Kernel: ${Default}${KERNEL}${NC}"
echo -e "${Prompt}User: ${Default}${USERNAME}${NC}"
echo -e "${Prompt}Host: ${Default}${HOSTNAME}${NC}"
prompt_continue

# Setting time correctly before installation
timedatectl set-ntp true

# Wipe out partitions
echo -e "${Standard}Wiping all partitions on disk '$DISK'${NC}"
sgdisk -Z "$DISK"

# Partition the disk
echo -e "${Standard}Preparing disk '$DISK' for UEFI and Encryption${NC}"
sgdisk -og "$DISK"

# Create a 1MiB BIOS boot partition
echo -e "${Standard}Creating a 1MiB BIOS boot partition${NC}"
sgdisk -n 1:2048:4095 -t 1:ef02 -c 1:"BIOS boot Partition" "$DISK"

# Create a UEFI partition
echo -e "${Standard}Creating a UEFI partition${NC}"
sgdisk -n 2:4096:1130495 -t 2:ef00 -c 2:"EFI" "$DISK"

# Create a LUKS partition
echo -e "${Standard}Creating a LUKS partition${NC}"
sgdisk -n 3:1130496:"$(sgdisk -E "$DISK")" -t 3:8309 -c 3:"Linux LUKS" "$DISK"

# Create the LUKS container
echo -e "${Standard}Creating the LUKS container${NC}"

# Set partition variable, handles nvme partitioning case
if [[ $DISK == /dev/nvme* ]]; then
    DISK_PREFIX="${DISK}p"
else
    DISK_PREFIX="${DISK}"
fi

# Encrypts with the best key size. (Will prompt for a password)
cryptsetup -q --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 3000 --use-random  luksFormat --type luks1 "$DISK_PREFIX"3

# Opening LUKS container to test
echo -e "${Standard}Opening the LUKS container to test password${NC}"
cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME
cryptsetup -v luksClose $CRYPT_NAME

# create a LUKS key of size 2048 and save it as boot.key
echo -e "${Standard}Creating the LUKS key for '$CRYPT_NAME'${NC}"
dd if=/dev/urandom of=./boot.key bs=2048 count=1
cryptsetup -v luksAddKey -i 1 "$DISK_PREFIX"3 ./boot.key

# unlock LUKS container with the boot.key file
echo -e "${Standard}Testing the LUKS keys for '$CRYPT_NAME'${NC}"
cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME --key-file ./boot.key
echo -e "\n"

# Create the LVM physical volume, volume group and logical volume
echo -e "${Standard}Creating LVM logical volumes on '$LVM_NAME'${NC}"
pvcreate --verbose /dev/mapper/$CRYPT_NAME
vgcreate --verbose $LVM_NAME /dev/mapper/$CRYPT_NAME
lvcreate --verbose -l 100%FREE $LVM_NAME -n root

# Format the partitions 
echo -e "${Standard}Formatting filesystems${NC}"
mkfs.ext4 /dev/mapper/$LVM_NAME-root

# Mount filesystem
echo -e "${Standard}Mounting filesystems${NC}"
mount --verbose /dev/mapper/$LVM_NAME-root /mnt
mkdir --verbose /mnt/home
mkdir --verbose -p /mnt/tmp

# Mount efi
echo -e "${Standard}Preparing the EFI partition${NC}"
mkfs.vfat -F32 "$DISK_PREFIX"2
mkdir --verbose /mnt/efi
mount --verbose "$DISK_PREFIX"2 /mnt/efi

# Update the keyring for the packages
echo -e "${Standard}Updating Arch key-rings${NC}" 
pacman -Sy archlinux-keyring --noconfirm

# Install Arch Linux base system. Add or remove packages as you wish.
echo -e "${Standard}Installing Arch Linux base system${NC}" 
pacstrap -i /mnt base base-devel archlinux-keyring "$KERNEL" "$KERNEL"-headers \
                 linux-firmware lvm2 grub efibootmgr dosfstools os-prober mtools \
                 networkmanager wget curl git nano openssh unzip unrar p7zip neofetch zsh \
                 zip unarj arj cabextract xz pbzip2 pixz lrzip cpio gdisk go rsync sudo

# Generate fstab file
echo -e "${Standard}Generating fstab file${NC}" 
genfstab -pU /mnt >> /mnt/etc/fstab

echo -e "${Standard}Copying the '$CRYPT_NAME' key to '$LUKS_KEYS'${NC}" 
mkdir --verbose /mnt$LUKS_KEYS
cp ./boot.key /mnt$LUKS_KEYS/boot.key
rm ./boot.key

# Add an entry to fstab so the new mountpoint will be mounted on boot
echo -e "${Standard}Adding tmpfs to fstab${NC}" 
echo "tmpfs /tmp tmpfs rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >> /mnt/etc/fstab
echo -e "${Standard}Adding proc to fstab and hardening it${NC}" 
echo "proc /proc proc nosuid,nodev,noexec,hidepid=2,gid=proc 0 0" >> /etc/fstab
touch /etc/systemd/system/systemd-logind.service.d/hidepid.conf
echo "[Service]" >> /etc/systemd/system/systemd-logind.service.d/hidepid.conf
echo "SupplementaryGroups=proc" >> /etc/systemd/system/systemd-logind.service.d/hidepid.conf

# Preparing the chroot script to be executed
echo -e "${Standard}Preparing the chroot script to be executed${NC}"
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
echo -e "${Standard}Chrooting into new system and configuring it${NC}"
arch-chroot /mnt /bin/bash ./chroot.sh
rm /mnt/chroot.sh

# Finished
read -rp "${Prompt}Do you want to reboot now? (Press Enter to continue, type 'n' to skip): ${NC}" REBOOT
if [[ -z "${REBOOT,,}" ]]; then
    echo -e "${Success}Rebooting now${NC}"
    reboot
else
    echo -e "${Success}Skipping reboot${NC}"
fi
