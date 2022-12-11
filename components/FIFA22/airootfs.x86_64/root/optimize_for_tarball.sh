#!/usr/bin/env bash

set -e -u
TERM='vt220'

# Check whether true or false is assigned to the variable.
function check_bool() {
    local
    case $(eval echo '$'"${1}") in
        true | false) : ;;
                   *) echo "The value ${boot_splash} set is invalid" >&2 ;;
    esac
}

# isolated i/o sudo
function _nsudo() { fakeroot sudo -S "${@}" ; }
# isolated sudo
function _isudo() { sudo -u#0 -g#0 fakeroot "${@}" ; }
# isolated sudo for build.sh runs
function _esudo() { sudo -u#0 -g#0 "${@}" ; }

# wrapper of command 'cp' for executable binaries
function _BNcp() { _nsudo rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --chown=0:0 --chmod=D755,F750 ${@} ; }
# wrapper of command 'cp' for executable binaries (noclobber)
function _BNcpNC() { _nsudo rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --ignore-existing --chown=0:0 --chmod=D755,F750 ${@} ; }

# wrapper of command 'cp' for old maintenance (but NOT certain, still some wrong)
function _cp() { _nsudo cp -af --no-preserve=ownership,mode -- "${@}"; }
# wrapper of command 'cp' for old maintenance (but NOT certain, still some wrong)
function _cpNC() { _nsudo cp -af --no-preserve=ownership,mode --no-clobber -- "${@}"; }

# wrapper of command 'cp' for strict safety
function _dicp() { _nsudo rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --chown=0:0 --chmod=D755,F644 ${@} ; }
# wrapper of command 'cp' for strict safety (noclobber)
function _dicpNC() { _nsudo rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --ignore-existing --chown=0:0 --chmod=D755,F644 ${@} ; }

# Show message when file is removed
# remove <file> <file> ...
function remove() {
    local _file
    for _file in "${@}"; do echo "Removing ${_file}"; rm -rf "${_file}"; done
}

# Execute only if the command exists
# run_additional_command [command name] [command to actually execute]
function run_additional_command() {
    if [[ -f "$(type -p "${1}" 2> /dev/null)" ]]; then
        shift 1
        eval "${@}"
    fi
}

function installedpkg() {
    if pacman -Qq "${1}" 1>/dev/null 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Add group if it does not exist
function _groupadd() {
    cut -d ":" -f 1 < "/etc/group" | grep -qx "${1}" && return 0 || groupadd "${1}"
}

_nsudo ldconfig

    _nsudo usermod -s "${usershell}" root
    _nsudo useradd -m -s "${usershell}" "${username}"
    _nsudo usermod -aG users,lp,wheel,storage,power,video,audio,input,network "${username}"

remove /etc/mkinitcpio-archiso.conf

# Disabled auto login
if [[ -f "/etc/gdm/custom.conf" ]]; then
    sed -i "s/Automatic*/#Automatic/g" "/etc/gdm/custom.conf"
fi
if [[ -f "/etc/lightdm/lightdm.conf" ]]; then
    sed -i "s/^autologin/#autologin/g" "/etc/lightdm/lightdm.conf"
fi

# Remove dconf for live environment
#remove "/etc/dconf/db/local.d/02-live-"*

# Update system datebase
_nsudo dconf update

# 追加のスクリプトを実行
if [[ -d "${script_path}/${script_name}.d/" ]]; then
    for extra_script in "${script_path}/${script_name}.d/"*; do
        _nsudo bash -c "${extra_script} ${user}"
    done
fi
