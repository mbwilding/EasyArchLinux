#!/bin/bash
# shellcheck disable=SC2034

# Default Settings
DEFAULT_HOSTNAME="arch"
DEFAULT_USERNAME="user"
DEFAULT_COUNTRY="Australia"
DEFAULT_CITY="Perth"
DEFAULT_LOCALE="en_AU"
DEFAULT_KERNEL="linux-zen"
DEFAULT_VOLUME_PASSWORD="password"
DEFAULT_ROOT_PASSWORD="password"
DEFAULT_USER_PASSWORD="password"
DEFAULT_DESKTOP_ENVIRONMENT="kde"

# Set up the colors
NC='\033[0m' # No Color
Error='\033[1;31m'
Success='\033[1;32m'
Heading='\033[1;33m'
Prompt='\033[1;34m'
Default='\033[0;35m'
Title='\033[1;36m'

# Title
echo -e "${Title}Arch Linux (Install)${NC}"

# Switches
USE_DEFAULTS=0
DE_SWITCH_SET=0
DESKTOP_ENVIRONMENT=""

while (("$#")); do
  case "$1" in
  -d)
    # If -d flag is present, use default values
    USE_DEFAULTS=1
    echo -e "${Error}Using defaults${NC}"
    shift
    ;;
  -kde)
    DESKTOP_ENVIRONMENT="kde"
    DE_SWITCH_SET=1
    shift
    ;;
  -mate)
    DESKTOP_ENVIRONMENT="mate"
    DE_SWITCH_SET=1
    shift
    ;;
  -gnome)
    DESKTOP_ENVIRONMENT="gnome"
    DE_SWITCH_SET=1
    shift
    ;;
  -cinnamon)
    DESKTOP_ENVIRONMENT="cinnamon"
    DE_SWITCH_SET=1
    shift
    ;;
  -budgie)
    DESKTOP_ENVIRONMENT="budgie"
    DE_SWITCH_SET=1
    shift
    ;;
  -lxqt)
    DESKTOP_ENVIRONMENT="lxqt"
    DE_SWITCH_SET=1
    shift
    ;;
  -xfce)
    DESKTOP_ENVIRONMENT="xfce"
    DE_SWITCH_SET=1
    shift
    ;;
  -deepin)
    DESKTOP_ENVIRONMENT="deepin"
    DE_SWITCH_SET=1
    shift
    ;;
  -none)
    DESKTOP_ENVIRONMENT="none"
    DE_SWITCH_SET=1
    shift
    ;;
  *)
    shift
    ;;
  esac
done

if [[ $USE_DEFAULTS -eq 1 && $DE_SWITCH_SET -eq 0 ]]; then
  DESKTOP_ENVIRONMENT=$DEFAULT_DESKTOP_ENVIRONMENT
fi

if [ -z "$DESKTOP_ENVIRONMENT" ]; then
  DESKTOP_ENVIRONMENT=$DEFAULT_DESKTOP_ENVIRONMENT
fi

# Helper functions
prompt_user() {
  local prompt=$1
  local var_name=$2
  local capitalize=$3
  local default_var_name="DEFAULT_${var_name^^}"
  local response

  if ((USE_DEFAULTS == 1)); then
    response=${!default_var_name}
  else
    while true; do
      echo -ne "${Prompt}${prompt} (${Default}${!default_var_name}${Prompt}): ${NC}"
      read -r response
      if [[ $response = *[[:space:]]* ]]; then
        echo -e "${Error}Please do not include spaces${NC}"
      else
        break
      fi
    done
  fi

  if [ "$capitalize" = true ]; then
    response=$(capitalize_first_letter "$response")
  fi

  eval $var_name=${response:-${!default_var_name}}
}

prompt_continue() {
  if ((USE_DEFAULTS == 0)); then
    echo -ne "${Prompt}Do you want to continue? (${Default}Enter${Prompt})${NC}"
    read -rsn1 CONTINUE
    echo
    if [ "$CONTINUE" != "" ]; then
      echo -e "${Error}Aborted${NC}"
      exit 1
    fi
  fi
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

# Functions
check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${Error}This script must be run as root.${NC}" 1>&2
    exit 1
  fi
}

check_uefi() {
  if [ ! -d "/sys/firmware/efi/efivars" ]; then
    echo -e "${Error}UEFI is not supported${NC}"
    exit 1
  fi
}

select_disk() {
  readarray -t AVAILABLE_DISKS < <(lsblk -d -o NAME,TYPE,SIZE | grep 'disk' | awk '{print $1, $3}')
  DEFAULT_TARGET_DISK=$(echo "${AVAILABLE_DISKS[0]}" | awk '{print $1}')

  # Check if the array is empty
  if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    echo -e "${Error}No disks detected${NC}"
    exit 1
  fi

  # Check if there's only one disk
  if [ ${#AVAILABLE_DISKS[@]} -eq 1 ]; then
    echo -e "${Prompt}Only one disk detected (${Default}${DEFAULT_TARGET_DISK}${Prompt})${NC}"
    TARGET_DISK=$DEFAULT_TARGET_DISK
    return
  fi

  while true; do
    echo -e "${Heading}The following disks are available on your system${NC}"
    # Display the list of available disks with indices
    for i in "${!AVAILABLE_DISKS[@]}"; do
      IFS=' ' read -r -a arr <<<"${AVAILABLE_DISKS[$i]}"
      echo -e "${Success}$(printf "%2d. %-10s %-10s" $((i + 1)) "${arr[0]}" "${Default}${arr[1]}")${NC}"
    done

    # Prompt the user for selection or use the default
    echo -ne "${Prompt}Select a disk number (${Default}1${Prompt}): ${NC}"
    read -r
    if [[ -z $REPLY ]]; then
      TARGET_DISK=$DEFAULT_TARGET_DISK
      break
    elif [[ $REPLY -ge 1 && $REPLY -le ${#AVAILABLE_DISKS[@]} ]]; then
      IFS=' ' read -r -a arr <<<"${AVAILABLE_DISKS[$((REPLY - 1))]}"
      TARGET_DISK=${arr[0]}
      break
    else
      echo -e "${Error}Invalid selection${NC}"
    fi
  done
}

ask_desktop_environment() {
  if [ "$DE_SWITCH_SET" -eq 1 ] || [ "$USE_DEFAULTS" -eq 1 ]; then
    return
  fi

  options=("none" "kde" "mate" "gnome" "cinnamon" "budgie" "lxqt" "xfce" "deepin")

  echo -e "${Prompt}Enter the desired desktop environment (${Default}${DESKTOP_ENVIRONMENT}${NC}${Prompt}):${NC}"
  for i in "${!options[@]}"; do
    echo -e "${Prompt}$((i))${Success}) ${Default}${options[$i]^}${NC}"
  done

  while true; do
    read -rsn1 opt
    if [ -n "$opt" ] && [ "$opt" -ge 0 ] && [ "$opt" -lt ${#options[@]} ]; then
      DESKTOP_ENVIRONMENT=${options[$opt]}
      break
    fi
  done
}

select_settings() {
  echo -e "${Heading}Configuration${NC}"

  select_disk
  prompt_user "Enter the new hostname" HOSTNAME
  prompt_user "Enter the new user" USERNAME
  prompt_user "Enter the user password" USER_PASSWORD
  prompt_user "Enter the root password" ROOT_PASSWORD
  prompt_user "Enter the volume password" VOLUME_PASSWORD
  prompt_user "Enter your country" COUNTRY true
  prompt_user "Enter your city" CITY true
  prompt_user "Enter your locale" LOCALE
  prompt_user "Enter the desired kernel" KERNEL
  ask_desktop_environment

  # Use the correct variable name for the target disk
  TIMEZONE="$COUNTRY/$CITY"
  DISK="/dev/$TARGET_DISK"
  CRYPT_NAME='crypt_lvm'    # the name of the LUKS container.
  LVM_NAME='lvm_arch'       # the name of the logical volume.
  LUKS_KEYS='/etc/luksKeys' # Where you will store the root partition key
}

confirm_settings() {
  echo -e "${Heading}Confirm${NC}"

  echo -e "${Success}Disk: ${Default}${TARGET_DISK}${NC}"
  echo -e "${Success}Host: ${Default}${HOSTNAME}${NC}"
  echo -e "${Success}User: ${Default}${USERNAME}${NC}"
  echo -e "${Success}User Password: ${Default}${USER_PASSWORD}${NC}"
  echo -e "${Success}Root Password: ${Default}${ROOT_PASSWORD}${NC}"
  echo -e "${Success}Volume Password: ${Default}${VOLUME_PASSWORD}${NC}"
  echo -e "${Success}Country: ${Default}${COUNTRY}${NC}"
  echo -e "${Success}City: ${Default}${CITY}${NC}"
  echo -e "${Success}Locale: ${Default}${LOCALE}${NC}"
  echo -e "${Success}Kernel: ${Default}${KERNEL}${NC}"
  echo -e "${Success}Desktop Environment: ${Default}${DESKTOP_ENVIRONMENT}${NC}"
  exit 1 # REMOVE ME
  prompt_continue
}

install() {
  # Setting time correctly before installation
  timedatectl set-ntp true

  # Wipe out partitions
  echo -e "${Heading}Wiping all partitions on disk '$DISK'${NC}"
  sgdisk -Z "$DISK"

  # Partition the disk
  echo -e "${Heading}Preparing disk '$DISK' for UEFI and Encryption${NC}"
  sgdisk -og "$DISK"

  # Create a 1MiB BIOS boot partition
  echo -e "${Heading}Creating a 1MiB BIOS boot partition${NC}"
  sgdisk -n 1:2048:4095 -t 1:ef02 -c 1:"BIOS boot Partition" "$DISK"

  # Create a UEFI partition
  echo -e "${Heading}Creating a UEFI partition${NC}"
  sgdisk -n 2:4096:1130495 -t 2:ef00 -c 2:"EFI" "$DISK"

  # Create a LUKS partition
  echo -e "${Heading}Creating a LUKS partition${NC}"
  sgdisk -n 3:1130496:"$(sgdisk -E "$DISK")" -t 3:8309 -c 3:"Linux LUKS" "$DISK"

  # Create the LUKS container
  echo -e "${Heading}Creating the LUKS container${NC}"

  # Set partition variable, handles nvme partitioning case
  if [[ $DISK == /dev/nvme* ]]; then
    DISK_PREFIX="${DISK}p"
  else
    DISK_PREFIX="${DISK}"
  fi

  # Encrypts with the best key size
  echo -n "${VOLUME_PASSWORD}" | cryptsetup -q --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 3000 --use-random luksFormat --type luks1 "$DISK_PREFIX"3 -

  # create a LUKS key of size 2048 and save it as boot.key
  echo -e "${Heading}Creating the LUKS key for '$CRYPT_NAME'${NC}"
  dd if=/dev/urandom of=./boot.key bs=2048 count=1
  echo -n "${VOLUME_PASSWORD}" | cryptsetup -v luksAddKey -i 1 "$DISK_PREFIX"3 ./boot.key -

  # unlock LUKS container with the boot.key file
  echo -e "${Heading}Testing the LUKS keys for '$CRYPT_NAME'${NC}"
  cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME --key-file ./boot.key
  echo -e "\n"

  # Create the LVM physical volume, volume group and logical volume
  echo -e "${Heading}Creating LVM logical volumes on '$LVM_NAME'${NC}"
  pvcreate --verbose /dev/mapper/$CRYPT_NAME
  vgcreate --verbose $LVM_NAME /dev/mapper/$CRYPT_NAME
  lvcreate --verbose -l 100%FREE $LVM_NAME -n root

  # Format the partitions
  echo -e "${Heading}Formatting filesystems${NC}"
  mkfs.ext4 /dev/mapper/$LVM_NAME-root

  # Mount filesystem
  echo -e "${Heading}Mounting filesystems${NC}"
  mount --verbose /dev/mapper/$LVM_NAME-root /mnt
  mkdir --verbose /mnt/home
  mkdir --verbose -p /mnt/tmp

  # Mount EFI
  echo -e "${Heading}Preparing the EFI partition${NC}"
  mkfs.vfat -F32 "$DISK_PREFIX"2
  mkdir --verbose /mnt/efi
  mount --verbose "$DISK_PREFIX"2 /mnt/efi

  # Update the keyring for the packages
  echo -e "${Heading}Updating Arch key-rings${NC}"
  pacman -Sy archlinux-keyring --noconfirm

  # Install Arch Linux base system. Add or remove packages as you wish.
  echo -e "${Heading}Installing Arch Linux base system${NC}"
  pacstrap /mnt base base-devel archlinux-keyring "$KERNEL" "$KERNEL"-headers \
    linux-firmware lvm2 grub efibootmgr dosfstools os-prober mtools \
    networkmanager wget curl git nano openssh unzip unrar p7zip neofetch zsh \
    zip unarj arj cabextract xz pbzip2 pixz lrzip cpio gdisk go rsync sudo

  # Generate fstab file
  echo -e "${Heading}Generating fstab file${NC}"
  genfstab -pU /mnt >>/mnt/etc/fstab

  echo -e "${Heading}Copying the '$CRYPT_NAME' key to '$LUKS_KEYS'${NC}"
  mkdir --verbose /mnt$LUKS_KEYS
  cp ./boot.key /mnt$LUKS_KEYS/boot.key
  rm ./boot.key

  # Add an entry to fstab so the new mountpoint will be mounted on boot
  echo -e "${Heading}Adding tmpfs to fstab${NC}"
  echo "tmpfs /tmp tmpfs rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >>/mnt/etc/fstab
  echo -e "${Heading}Adding proc to fstab and hardening it${NC}"
  echo "proc /proc proc nosuid,nodev,noexec,hidepid=2,gid=proc 0 0" >>/etc/fstab
  touch /etc/systemd/system/systemd-logind.service.d/hidepid.conf
  echo "[Service]" >>/etc/systemd/system/systemd-logind.service.d/hidepid.conf
  echo "SupplementaryGroups=proc" >>/etc/systemd/system/systemd-logind.service.d/hidepid.conf

  # Preparing the chroot script to be executed
  echo -e "${Heading}Preparing the chroot script to be executed${NC}"
  cp ./chroot.sh /mnt
  CHROOT="/mnt/chroot.sh"
  sed -i "s|^USE_DEFAULTS=.*|USE_DEFAULTS='${USE_DEFAULTS}'|g" $CHROOT
  sed -i "s|^DISK_PREFIX=.*|DISK_PREFIX='${DISK_PREFIX}'|g" $CHROOT
  sed -i "s|^LVM_NAME=.*|LVM_NAME='${LVM_NAME}'|g" $CHROOT
  sed -i "s|^HOSTNAME=.*|HOSTNAME='${HOSTNAME}'|g" $CHROOT
  sed -i "s|^USERNAME=.*|USERNAME='${USERNAME}'|g" $CHROOT
  sed -i "s|^USER_PASSWORD=.*|USER_PASSWORD='${USER_PASSWORD}'|g" $CHROOT
  sed -i "s|^ROOT_PASSWORD=.*|ROOT_PASSWORD='${ROOT_PASSWORD}'|g" $CHROOT
  sed -i "s|^LOCALE=.*|LOCALE='${LOCALE}'|g" $CHROOT
  sed -i "s|^TIMEZONE=.*|TIMEZONE='${TIMEZONE}'|g" $CHROOT
  sed -i "s|^KERNEL=.*|KERNEL='${KERNEL}'|g" $CHROOT
  sed -i "s|^DESKTOP_ENVIRONMENT=.*|DESKTOP_ENVIRONMENT='${DESKTOP_ENVIRONMENT}'|g" $CHROOT
  chmod +x $CHROOT

  # Chroot into new system and configure it
  echo -e "${Heading}Chrooting into new system and configuring it${NC}"
  arch-chroot /mnt /bin/bash ./chroot.sh
  rm /mnt/chroot.sh
}

finish() {
  echo -e "${Heading}Cleaning up${NC}"
  rm *.sh

  echo -e "${Success}Rebooting now${NC}"
  reboot
}

# Execution order
check_root
check_uefi
select_settings
confirm_settings
install
finish
