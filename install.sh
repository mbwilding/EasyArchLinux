#!/bin/bash
# shellcheck disable=SC2034

# Default Settings
source defaults.sh

# Set up the colors
NC='\033[0m' # No Color
Error='\033[1;31m'
Success='\033[1;32m'
Heading='\033[1;33m'
Prompt='\033[1;34m'
Default='\033[0;35m'
Title='\033[1;36m'

# Title
echo -e "${Title}Arch Linux (${Default}Install${Title})${NC}"

# Backing fields
USE_DEFAULTS=0
DISK_SWITCH_SET=0
DE_SWITCH_SET=0
GPU_SWITCH_SET=0

# Switches
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  -d | --defaults)
    USE_DEFAULTS=1
    echo -e "${Error}Using defaults${NC}"
    ;;
  -disk)
    shift
    if [[ -n "$1" ]]; then
      DEFAULT_DISK="$1"
      DISK_SWITCH_SET=1
    else
      echo -e "${Error}Missing disk argument${NC}"
      exit 1
    fi
    ;;
  -de)
    shift
    if [[ -n "$1" ]]; then
      DEFAULT_DESKTOP_ENVIRONMENT="$1"
      DE_SWITCH_SET=1
    else
      echo -e "${Error}Missing desktop environment argument${NC}"
      exit 1
    fi
    ;;
  -gpu)
    shift
    if [[ -n "$1" ]]; then
      DEFAULT_GPU="$1"
      GPU_SWITCH_SET=1
    else
      echo -e "${Error}Missing GPU argument${NC}"
      exit 1
    fi
    ;;
  *)
    echo -e "${Error}Unrecognized switch: $1${NC}"
    exit 1
    ;;
  esac
  shift
done

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

      if [[ "$var_name" == *"PASSWORD"* ]]; then
        read -rs response
        echo
      else
        read -r response
      fi

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

ask_option() {
  local -n selected_option=$1
  local switch_set=$2
  local use_defaults=$3
  local options=("${!4}")
  local prompt_message=$5
  local default_option=$6
  local indexed=$7
  local multi_field=$8

  if [ -n "$default_option" ]; then
    selected_option="$default_option"
  fi

  [ "$switch_set" -eq 1 ] || [ "$use_defaults" -eq 1 ] && return

  echo -e "${Prompt}Enter a number for the desired $prompt_message (${Default}${selected_option}${NC}${Prompt}):${NC}"
  for i in "${!options[@]}"; do
    if [[ $multi_field -eq 1 ]]; then
      IFS=' ' read -r -a arr <<<"${options[$i]}"
      echo -e "${Success}$(printf "%2d. %-10s %-10s" $((i + 1)) "${arr[0]}" "${Default}${arr[1]}")${NC}"
    else
      echo -e "${Prompt}$((i))${Default}) ${Success}${options[$i]^}${NC}"
    fi
  done

  while true; do
    read -rsn1 opt
    if [[ -z $opt ]] && [[ -n $default_option ]]; then
      selected_option=$default_option
      break
    elif [[ $opt -ge 0 && $opt -lt ${#options[@]} ]] && [[ $indexed -eq 0 ]]; then
      selected_option=${options[$opt]}
      break
    elif [[ $opt -ge 1 && $opt -le ${#options[@]} ]] && [[ $indexed -eq 1 ]]; then
      IFS=' ' read -r -a arr <<<"${options[$((opt - 1))]}"
      selected_option=${arr[0]}
      break
    fi
  done
}

prompt_continue() {
  if ((USE_DEFAULTS == 0)); then
    echo -ne "${Error}The drive will be wiped\n${Prompt}Do you want to continue? (${Default}Enter${Prompt})${NC}"
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

update_chroot_variable() {
  local variable_name=$1
  sed -i "s|^${variable_name}=.*|${variable_name}='${!variable_name}'|g" /mnt/chroot.sh
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
    echo -e "${Error}If using VMWare, edit the ${Prompt}.vmx${Error} file and add ${Prompt}firmware=\"efi\"${NC}"
    exit 1
  fi
}

# Parallel downloads for pacman
pacman_para() {
  echo -e "${Heading}Pacman set to download ${Default}${PACMAN_PARA}${Heading} packages concurrently${NC}"

  if [[ ! $PACMAN_PARA =~ ^(0|1)$ ]]; then
    sed -i "s/^#\(ParallelDownloads = \).*/\1$PACMAN_PARA/" /etc/pacman.conf
  fi
}

ask_disk() {
  readarray -t AVAILABLE_DISKS < <(lsblk -d -o NAME,TYPE,SIZE | grep 'disk' | awk '{print $1, $3}')

  if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    echo -e "${Error}No disks detected${NC}"
    exit 1
  fi

  if [[ $DISK_SWITCH_SET -eq 1 && ! " ${AVAILABLE_DISKS[@]} " =~ " ${DEFAULT_DISK} " ]]; then
    echo -e "${Error}Provided disk not found (${Default}${DEFAULT_DISK}${Error})${NC}"
    echo -e "${Error}Available Disks:${NC}"
    for disk in "${AVAILABLE_DISKS[@]}"; do
      IFS=' ' read -r -a arr <<<"$disk"
      echo -e "${Success}$(printf "%-10s %-10s" "${arr[0]}" "${Default}${arr[1]}")${NC}"
    done
    exit 1
  fi

  # Set DEFAULT_TARGET_DISK as the first available disk by default
  DEFAULT_TARGET_DISK=$(echo "${AVAILABLE_DISKS[0]}" | awk '{print $1}')

  # If DEFAULT_DISK is set and exists in the available disks, set it as the default
  if [ -n "$DEFAULT_DISK" ]; then
    for disk in "${AVAILABLE_DISKS[@]}"; do
      if [[ $(echo "$disk" | awk '{print $1}') == "$DEFAULT_DISK" ]]; then
        DEFAULT_TARGET_DISK=$DEFAULT_DISK
        break
      fi
    done
  fi

  ask_option TARGET_DISK "$DISK_SWITCH_SET" "$USE_DEFAULTS" AVAILABLE_DISKS[@] "disk" $DEFAULT_TARGET_DISK 1 1
}

ask_desktop_environment() {
  options=("none" "kde" "mate" "gnome" "cinnamon" "budgie" "lxqt" "xfce" "deepin")
  ask_option DESKTOP_ENVIRONMENT "$DE_SWITCH_SET" "$USE_DEFAULTS" options[@] "desktop environment" $DEFAULT_DESKTOP_ENVIRONMENT 0 0
}

ask_gpu() {
  options=("none" "nvidia") # TODO "amd" "intel"
  ask_option GPU "$GPU_SWITCH_SET" "$USE_DEFAULTS" options[@] "GPU" $DEFAULT_GPU 0 0
}

select_settings() {
  echo -e "${Heading}Configuration${NC}"

  ask_disk
  prompt_user "Enter download concurrency" PACMAN_PARA
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
  ask_gpu

  # Setup more parameters
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
  # echo -e "${Success}User Password: ${Default}${USER_PASSWORD}${NC}"
  # echo -e "${Success}Root Password: ${Default}${ROOT_PASSWORD}${NC}"
  # echo -e "${Success}Volume Password: ${Default}${VOLUME_PASSWORD}${NC}"
  echo -e "${Success}Country: ${Default}${COUNTRY}${NC}"
  echo -e "${Success}City: ${Default}${CITY}${NC}"
  echo -e "${Success}Locale: ${Default}${LOCALE}${NC}"
  echo -e "${Success}Kernel: ${Default}${KERNEL}${NC}"
  echo -e "${Success}Desktop Environment: ${Default}${DESKTOP_ENVIRONMENT}${NC}"
  echo -e "${Success}GPU: ${Default}${GPU}${NC}"

  prompt_continue
}

install() {
  # Setting time correctly before installation
  timedatectl set-ntp true

  # Wipe out partitions
  echo -e "${Heading}Wiping all partitions on disk ${Default}${DISK}${NC}"
  sgdisk -Z "$DISK"

  # Partition the disk
  echo -e "${Heading}Preparing disk ${Default}${DISK}${Heading} for UEFI and Encryption${NC}"
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
  echo -e "${Heading}Creating the LUKS key for ${Default}${CRYPT_NAME}${NC}"
  dd if=/dev/urandom of=./boot.key bs=2048 count=1
  echo -n "${VOLUME_PASSWORD}" | cryptsetup -v luksAddKey -i 1 "$DISK_PREFIX"3 ./boot.key -

  # unlock LUKS container with the boot.key file
  echo -e "${Heading}Testing the LUKS keys for ${Default}${CRYPT_NAME}${NC}"
  cryptsetup -v luksOpen "$DISK_PREFIX"3 $CRYPT_NAME --key-file ./boot.key

  # Create the LVM physical volume, volume group and logical volume
  echo -e "${Heading}Creating LVM logical volumes on ${Default}${LVM_NAME}${NC}"
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

  echo -e "${Heading}Copying the ${Default}${CRYPT_NAME}${Heading} key to ${Default}${LUKS_KEYS}${NC}"
  mkdir --verbose /mnt$LUKS_KEYS
  cp ./boot.key /mnt$LUKS_KEYS/boot.key
  rm ./boot.key

  # Add an entry to fstab so the new mountpoint will be mounted on boot
  echo -e "${Heading}Adding tmpfs to fstab${NC}"
  echo "tmpfs /tmp tmpfs rw,nosuid,nodev,relatime,size=2G 0 0" >>/mnt/etc/fstab
  echo -e "${Heading}Adding proc to fstab and hardening it${NC}"
  echo "proc /proc proc nosuid,nodev,hidepid=2,gid=proc 0 0" >>/etc/fstab
  touch /etc/systemd/system/systemd-logind.service.d/hidepid.conf
  echo "[Service]" >>/etc/systemd/system/systemd-logind.service.d/hidepid.conf
  echo "SupplementaryGroups=proc" >>/etc/systemd/system/systemd-logind.service.d/hidepid.conf

  # Preparing the chroot script to be executed
  echo -e "${Heading}Preparing the chroot script to be executed${NC}"
  cp ./chroot.sh /mnt
  chmod +x /mnt/chroot.sh

  # Move settings into chroot script
  settings=("USE_DEFAULTS" "DISK_PREFIX" "LVM_NAME" "HOSTNAME" "USERNAME" "USER_PASSWORD" "ROOT_PASSWORD" "LOCALE" "TIMEZONE" "KERNEL" "DESKTOP_ENVIRONMENT" "PACMAN_PARA" "GPU")
  for setting in "${settings[@]}"; do
    update_chroot_variable "$setting"
  done

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
pacman_para
install
finish
