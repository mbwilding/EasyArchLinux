#!/bin/bash

# shellcheck disable=SC2164
cd /tmp

# Dependencies
sudo pacman -S base-devel git --noconfirm

setup_pamac() {
  # Clone and install yay
  git clone https://aur.archlinux.org/yay.git
  (cd yay && makepkg -si --noconfirm)

  # Install Pamac
  yay -S --noconfirm pamac

  # Enable AUR support in Pamac
  sudo sed -i 's/#EnableAUR/EnableAUR/' /etc/pamac.conf

  # Enable updates in Pamac
  sudo sed -i 's/#CheckAURUpdates/CheckAURUpdates/' /etc/pamac.conf
}

# Execution order
setup_pamac
