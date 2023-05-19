# Easy Arch Linux

## Introduction

🚀 Introducing EasyArchLinux - your ultimate companion for a hassle-free Arch Linux installation experience!

This toolkit is designed to make installing Arch Linux with UEFI and Full Disk Encryption (LUKS) a breeze. We've taken care of all the complex steps - you're in full control of confirming all settings and changes. 🛡️

One of the standout features of EasyArchLinux is its broad support for major desktop environments. Whether you're a fan of KDE, Gnome, XFCE, Cinnamon, Mate, Budgie, LXQT, Deepin, or just prefer a minimal setup, this tool caters to your unique preference, letting you create the perfect Linux environment for your needs. 🎛️

Beyond the installation, EasyArchLinux takes care of essential post-install steps, ensuring you have access to key resources like Pamac and the AUR. 📚

Jumpstart your Arch Linux journey with EasyArchLinux today!

Don't forget to leave a ⭐ if you love my work!

## Information

**Warning**: This process will wipe the entire selected disk. If only one disk is available, it will be chosen by
default. You will be asked to confirm all settings and changes before they are made, unless the default switch is
provided.

## Installation

1. Download the [Arch ISO](https://archlinux.org/download/).
2. Create a [Bootable USB](https://wiki.archlinux.org/title/USB_flash_installation_medium) and boot the ISO.
3. If you're on wireless, follow this [Wireless Setup guide](https://wiki.archlinux.org/title/Iwd#iwctl).
   ```bash
   iwctl station wlan0 connect "Wifi Name"
   ```

#### Install (Without GIT)

```bash
curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

#### Install (With GIT)

```bash
pacman -S git
git clone https://github.com/mbwilding/EasyArchLinux.git
cd EasyArchLinux
chmod +x *.sh
./install.sh
```

## Post-Install

Once you are booted and logged in, open up the terminal and run this.

This will install Pamac, which grants you access to the [AUR](https://aur.archlinux.org/)

```bash
curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/extras/essentials.sh
chmod +x essentials.sh
./essentials.sh
rm essentials.sh
```

## Editing Defaults

You can edit the `defaults.sh` file to change the default settings.

## Switches

The following switches can be used on `install.sh` or `bootstrap.sh`.

Running `-d` or `--defaults` will install with default settings. If the default disk is not found, you will still be
prompted unless there is only one disk.

Default settings can be overridden with the following switches, even when combined with the default switch:

- `-disk`: Provide a value from `lsblk -d`.
- `-de`: Choose a desktop environment:
    - `none`
    - `kde`
    - `mate`
    - `gnome`
    - `cinnamon`
    - `budgie`
    - `lxqt`
    - `xfce`
    - `deepin`
- `-gpu`: Choose a GPU type (AMD and Intel soon to come):
    - `none`
    - `nvidia`
