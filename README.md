## Easy Arch Linux

### Information
These scripts are to facilitate installing Arch Linux with UEFI and Full Disk Encryption (LUKS)

### Installation
Download the [Arch ISO](https://archlinux.org/download/).<br>
Boot the ISO via creating a [Bootable USB](https://wiki.archlinux.org/title/USB_flash_installation_medium).<br>

Steps without git;

    for file in install chroot
    do curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/${file}.sh &&
    chmod +x ${file}.sh
    done

    ./install.sh

Steps with git;

    pacman -S git
    git clone https://github.com/mbwilding/EasyArchLinux.git
    cd EasyArchLinux
    chmod +x *.sh

    ./install.sh

### Editing defaults
You can edit the defaults at the top of the file before running.

    nano install.sh

### Switches
Running ```-d``` will install with defaults.<br>
If there are multiple disks detected, it will still prompt.<br>

Some additional switches for selecting the desktop environment.<br>
It will use the default if not supplied.

    -kde
    -mate
    -gnome
    -cinnamon
    -budgie
    -lxqt
    -xfce
    -deepin
    -none
