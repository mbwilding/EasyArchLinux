#!/bin/bash

# shellcheck disable=SC2164
cd /tmp

setup_pamac() {
  # Clone and install
  git clone https://aur.archlinux.org/libpamac-aur.git && (cd libpamac-aur && makepkg -si --noconfirm)
  git clone https://aur.archlinux.org/pamac-aur.git && (cd pamac-aur && makepkg -si --noconfirm)
  
  # Enable AUR support in Pamac
  sudo sed -i 's/#EnableAUR/EnableAUR/' /etc/pamac.conf
  
  # Enable updates in Pamac
  sudo sed -i 's/#CheckAURUpdates/CheckAURUpdates/' /etc/pamac.conf
}

# Execution order
setup_pamac
