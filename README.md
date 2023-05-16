## Easy Arch Linux

### Information
These scripts are to facilitate installing Arch Linux with UEFI and Full Disk Encryption (LUKS)<br>
This will wipe the entire disk that is selected, if there is only one disk available, it'll be selected by default.<br>
You will be prompted for all of the settings and asked to confirm before any changes are made, unless the ```-d``` default switch is provided.

### Installation
Download the [Arch ISO](https://archlinux.org/download/).<br>
Boot the ISO via creating a [Bootable USB](https://wiki.archlinux.org/title/USB_flash_installation_medium).<br>
If you're on wireless, [Wireless Setup](https://wiki.archlinux.org/title/Iwd#iwctl).

Steps without git;

    curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/bootstrap.sh
    chmod +x bootstrap.sh
    ./bootstrap.sh

Steps with git;

    pacman -S git
    git clone https://github.com/mbwilding/EasyArchLinux.git
    cd EasyArchLinux
    chmod +x *.sh
    ./install.sh

### Editing defaults
You can edit the ```defaults.sh``` file, which is where ```install.sh``` gets its defaults from.

### Switches
These switches can be used on ```install.sh``` or ```bootstrap.sh```<br>

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
