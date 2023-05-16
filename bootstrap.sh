#!/bin/bash

for file in install chroot; do
  curl -O https://raw.githubusercontent.com/mbwilding/EasyArchLinux/main/${file}.sh
  chmod +x ${file}.sh
done

./install.sh "$@"
