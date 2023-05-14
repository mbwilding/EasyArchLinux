## Arch Linux FDE UEFI Install

### Installation
First download the [Arch ISO](https://archlinux.org/download/)<br>
Boot the ISO via burning to a disc or creating a bootable USB.<br>

Then run;

    for file in install chroot
    do curl -O https://raw.githubusercontent.com/mbwilding/ArchLinux/main/${file}.sh
    done

    chmod +x *.sh
    ./install.sh

### Editing defaults
You can edit the defaults at the top of the file before running

    nano install.sh

### Switches
Running ```./install.sh -d``` will install with defaults<br>
If there are multiple disks detected, it will still prompt<br>
