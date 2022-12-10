#!/bin/bash
sudo pacman -Syyuu --overwrite="*" winetricks
sudo -u "${LOGNAME}" winecfg
for i in corefonts fakejapanese cjkfonts dotnet48 vcrun2019
do
    sudo -u "${LOGNAME}" winetricks "${i}"
done
