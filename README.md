## Easy Arch Linux

### Information
These scripts are to facilitate installing Arch Linux with UEFI and Full Disk Encryption (LUKS)

### Installation
First download the [Arch ISO](https://archlinux.org/download/).<br>
Boot the ISO via burning to a disc or creating a bootable USB.<br>

Then run;

    for file in install chroot
    do curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/${file}.sh
    done

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
