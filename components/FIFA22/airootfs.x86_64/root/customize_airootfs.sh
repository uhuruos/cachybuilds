#!/usr/bin/env bash
#
# silencesuzuka
# Discord: sulogin#0921
# Email  : makeworldgentoo@gmail.com
#
# (c) 1998-2140 silencesuzuka
#

# Parse arguments
while getopts 'p:k:xu:o:i:s:da:g:z:l:' arg; do
    case "${arg}" in
        p) password="${OPTARG}" ;;
        k) IFS=" " read -r -a kernel_config_line <<< "${OPTARG}" ;;
        u) username="${OPTARG}" ;;
        o) os_name="${OPTARG}" ;;
        i) install_dir="${OPTARG}" ;;
        s) usershell="${OPTARG}" ;;
        d) debug=true ;;
        x) debug=true; set -xv ;;
        a) arch="${OPTARG}" ;;
        g) localegen="${OPTARG/./\\.}\\" ;;
        z) timezone="${OPTARG}" ;;
        l) language="${OPTARG}" ;;
        *) : ;;
    esac
done

# Check whether true or false is assigned to the variable.
function check_bool() {
    local
    case $(eval echo '$'"${1}") in
        true | false) : ;;
                   *) _nsudo echo "The value ${1} set is invalid" >&2 ;;
    esac
}

# Show message when file is removed
# remove <file> <file> ...
function remove() {
    local _file
    for _file in "${@}"; do echo "Removing ${_file}"; rm -rf "${_file}"; done
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

# user_check <name>
function user_check() {
    if [[ ! -v 1 ]]; then return 2; fi
    getent passwd "${1}" > /dev/null
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

# Create a user.
# create_user <username> <password>
function create_user() {
    local _username="${1-""}" _usershell="${2-""}" _password="${3-""}"

    if [[ -z "${_username}" ]]; then
        echo "User name is not specified." >&2
        return 1
    fi
    if [[ -z "${_usershell}" ]]; then
        echo "No usershell has been specified." >&2
        return 1
    fi
    if [[ -z "${_password}" ]]; then
        echo "No password has been specified." >&2
        return 1
    fi

    if ! user_check "${_username}"; then
        _nsudo useradd -m -s "${_usershell}" "${_username}"
        #_nsudo usermod -U -g "${_username}" "${_username}"
        _nsudo usermod -aG users,lp,wheel,storage,power,video,audio,input,network "${_username}"
        #_nsudo mkdir -m 755 -p "/home/${_username}"
        #cp -raT "/etc/skel/" "/home/${_username}/"
        [[ -f /etc/.zshrc ]] && \cp -raT /etc/.zshrc /home/${_username}/.zshrc
        _nsudo chmod 755 -R "/home/${_username}"
        _nsudo chown "${_username}:${_username}" -R "/home/${_username}"
        _nsudo echo -e "${_password}\n${_password}" | passwd "${_username}"
    fi
}

## Make it compatible with previous code
unset OPTIND OPTARG arg

_nsudo ldconfig

# session
session='startxfce4'

# login session
_nsudo sed -ri "s|%SESSION%|${session}|g" "/etc/skel/.xinitrc"

# Enable and generate languages.
_nsudo sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
if [[ ! "${localegen}" = "en_US\\.UTF-8\\" ]]; then
    _nsudo sed -i "s/#\(${localegen})/\1/" /etc/locale.gen
fi
locale-gen

# Setting the time zone.
_nsudo ln -snf "/usr/share/zoneinfo/${timezone}" /etc/localtime

# (relinking) Correcting /etc/alternatives
if [[ ! -f "/etc/alternatives" ]]; then
    _nsudo mkdir -m 755 -p /etc/alternatives
    _nsudo ln -snf /etc/alternatives/awk /usr/bin/gawk
    _nsudo ln -snf /etc/alternatives/nawk /usr/bin/gawk
fi

# Allow supervisor group to run as root with any command
for _cfg_visor in "admin" "root" "wheel"
do
    _groupadd "${_cfg_visor}"
    _nsudo sed -i 's/^#\s*\(%"${_cfg_visor}"\s\+ALL=(ALL)\s\+ALL\)/\1/' "/etc/sudoers.d/g_${_cfg_visor}" || true
done

_nsudo usermod -s "${usershell}" root
#cp -aT /etc/skel/ /root/
run_additional_command "xdg-user-dirs-update" "LC_ALL=C LANG=C xdg-user-dirs-update"
_nsudo echo -e "${password}\n${password}" | passwd root

# Create user
create_user "${username}" "${usershell}" "${password}"

# Set up auto login
if [[ -f "/etc/systemd/system/getty.target.wants/getty@tty1.service" ]]; then
    _nsudo sed -ri "s|%USERNAME%|${username}|g" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
fi

# Set to execute sudo without password as alter user.
cat >> /etc/sudoers << "EOF"
Defaults pwfeedback
EOF
_nsudo echo "${username} ALL=NOPASSWD: ALL" > /etc/sudoers.d/archiso

# Replace shortcut list config
if [[ "${language}" = "ja" ]]; then
    _nsudo echo 'LANG=ja_JP.UTF-8' > /etc/locale.conf
fi
#remove config file about live only
#remove /etc/skel/Desktop
#remove /root/Desktop
#remove "/etc/skel/.config/conky/conky-live.conf"
#remove "/etc/skel/.config/conky/conky-live-jp.conf"
#remove "/home/${username}/.config/conky/conky-jp.conf"

# Change aurorun files permission
_nsudo chmod 755 -R "/home/${username}/.config/autostart/"* "/etc/skel/.config/autostart/"* || true

# Set permission for script
_nsudo chmod 755 -R /etc/skel/ 
_nsudo chmod 755 -R /home/${username}/

#if [[ -f /usr/bin/eselect-arc ]]; then
#    _nsudo chmod 755 "/usr/bin/eselect-arc"
#fi

if [[ "${arch}" = "i686" ]]; then
    _nsudo ln -snf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist32
fi

# TUI Installer configs
_nsudo echo "${kernel_filename}" > /root/kernel_filename

# Set os name
_nsudo sed -ri "s|%OS_NAME%|${os_name}|g" "/usr/lib/os-release"

# Enable root login with SSH.
if [[ -f "/etc/ssh/sshd_config" ]]; then
    _nsudo sed -i 's|#\(PermitRootLogin \).\+|\1yes|' "/etc/ssh/sshd_config"
fi

# Un comment the mirror list.
if [[ -f "/etc/pacman.d/mirrorlist" ]]; then
    _nsudo sed -ri "s/#Server/Server/g" "/etc/pacman.d/mirrorlist"
fi

# Set the os name to grub
grub_os_name="${os_name%' Linux'}"
#_nsudo sed -ri "s|^s*GRUB_DISTRIBUTOR=.+|\1\"${grub_os_name}"/|" "/etc/default/grub"
_nsudo sed -ri "s|^s*GRUB_DISTRIBUTOR=.+|GRUB_DISTRIBUTOR=${grub_os_name}|" "/etc/default/grub"

_nsudo mkfontscale /usr/share/fonts/TTF || true
_nsudo mkfontdir /usr/share/fonts/TTF || true
_nsudo fc-cache -s || true
_nsudo glib-compile-schemas /usr/share/glib-2.0/schemas || true

# Create new icon cache
# This is because alter icon was added by airootfs.
if [[ -e "/usr/bin/gtk-update-icon-cache" ]]; then
    for _cfg_gtkicache in $(find /usr/share/icons/ -mindepth 1 -maxdepth 1 -type d)
    do
        _nsudo gtk-update-icon-cache -ftq "${_cfg_gtkicache}" || true
    done
fi

if [[ -e "/root/.automated_script.sh" ]]; then
    _nsudo chmod 755 "/root/.automated_script.sh"
fi

# Enable graphical.
_nsudo systemctl enable graphical.target
_nsudo systemctl set-default graphical.target

# kmscon
if [[ -f /usr/bin/kmscon ]]; then
    # Copy config file for getty@.service to kmsconvt@.service
    if [[ -f "/etc/systemd/system/getty@.service.d/autologin.conf" ]]; then
        _nsudo mkdir -p "/etc/systemd/system/kmsconvt@.service.d/"
        cp "/etc/systemd/system/getty@.service.d/autologin.conf" "/etc/systemd/system/kmsconvt@.service.d/autologin.conf"
    fi

    # Disable default tty
    _nsudo systemctl disable "getty@tty1" "getty@" "getty"
    _nsudo systemctl enable "kmsconvt@tty1"
    _nsudo systemctl enable "kmsconvt@tty2"

    # Do not run setterm
    remove /etc/profile.d/disable-beep.sh

    # Run KMSCON for all tty
    _nsudo ln -snf "/usr/lib/systemd/system/kmsconvt@" "/etc/systemd/system/autovt@"
fi

# Prevent OOMKiller, rc compatible bugs.
#_nsudo systemctl mask systemd-binfmt
_nsudo systemctl mask systemd-oom
_nsudo systemctl mask systemd-oomd
_nsudo systemctl mask systemd-resolved
#_nsudo systemctl disable systemd-binfmt
_nsudo systemctl disable systemd-oom
_nsudo systemctl disable systemd-oomd
_nsudo systemctl disable systemd-resolved
#_nsudo systemctl unmask systemd-binfmt
_nsudo systemctl unmask systemd-oom
_nsudo systemctl unmask systemd-oomd
_nsudo systemctl unmask systemd-resolved

# registring rc services
#-- init
###_nsudo systemctl enable modprobe || false
_nsudo systemctl enable ldconfig || false
#-- DBus
###_nsudo systemctl enable dbus || false
###_nsudo systemctl enable dbus-broker || false
#-- polkit, udev
_nsudo systemctl enable polkit || false
#_nsudo systemctl enable packagekit || false
###_nsudo systemctl enable udev || false
###_nsudo systemctl enable systemd-udevd || false
###_nsudo systemctl enable wacom-inputattach || false
_nsudo systemctl enable usbmuxd || false
#_nsudo systemctl enable usbguard || false
#_nsudo systemctl enable usbguard-dbus || false
#-- distcc, preload, udisk2
##_nsudo systemctl enable preload || false
##_nsudo systemctl enable udisk2 || false
#-- system support printer
##_nsudo systemctl enable hplip || false
##_nsudo systemctl enable hplip-printer || false
_nsudo systemctl enable cups || false
_nsudo systemctl enable cups-browsed || false
#-- iptables
_nsudo systemctl enable iptables || false
##_nsudo systemctl enable nftables || false
#-- DNS resolver
#_nsudo systemctl enable avahi-daemon || false
_nsudo systemctl enable dnsmasq || false
#_nsudo systemctl enable systemd-resolved || false
_nsudo systemctl enable macspoof || false
#-- Network Manager and SSH
#_nsudo systemctl enable netctl || false
##_nsudo systemctl enable iwd || false
_nsudo systemctl enable NetworkManager || false
_nsudo rfkill unblock all
_nsudo systemctl disable systemd-rfkill
_nsudo systemctl mask systemd-rfkill
_nsudo systemctl unmask systemd-rfkill
_nsudo systemctl enable bluetooth || false
_nsudo systemctl enable ModemManager || false
##_nsudo systemctl enable sshd || false
_nsudo systemctl enable sshguard || false
#-- System Clock, RPCbind NTP client
_nsudo systemctl enable xl2tpd || false
##_nsudo systemctl enable rpcbind || false
#_nsudo systemctl enable ntpd || false
#_nsudo systemctl enable ntpdate || false
##_nsudo systemctl enable time-sync || false
_nsudo systemctl disable systemd-timedated
_nsudo systemctl mask systemd-timedated
_nsudo systemctl unmask systemd-timedated
##_nsudo systemctl enable systemd-timedated || false
_nsudo systemctl disable systemd-timesyncd
_nsudo systemctl mask systemd-timesyncd
_nsudo systemctl unmask systemd-timesyncd
#_nsudo systemctl enable systemd-timesyncd || false

#-- Firewall and Cron
_nsudo systemctl enable snmpd || false
#_nsudo systemctl enable smb || false
#_nsudo systemctl enable samba || false
#_nsudo systemctl enable winbind || false
_nsudo systemctl enable ufw || false
##_nsudo systemctl enable timers || false

_nsudo systemctl mask tor || false

# Enable zeronet
if [[ -d /usr/lib/start-zeronet ]]; then
    _safe_systemctl enable zeronet.service
    chmod +x /usr/lib/start-zeronet
    usermod -aG tor zeronet
fi

if [[ -d /usr/lib/obscurix ]]; then
    chmod +x /usr/lib/obscurix/secure-time-sync || false
    _nsudo systemctl enable secure-time-sync || false
    chmod +x /usr/lib/obscurix/spoof-mac-address || false
    _nsudo systemctl enable spoof-mac-address || false
fi

if [[ -f "/usr/bin/kloak" ]]; then
    _nsudo systemctl enable kloak || false
fi

if [[ -f "/usr/lib/onion-greeter" ]]; then
    chmod +x /usr/lib/onion-greeter || false
fi

#-- Tweaks
##_nsudo systemctl enable lm_sensors || false
##_nsudo systemctl enable tlp || false
#_nsudo systemctl enable irqbalance || false
#_nsudo systemctl enable macfanctld || false
#_nsudo systemctl enable intel-undervolt-loop || false
#_nsudo systemctl enable auto-cpufreq || false
##_nsudo systemctl enable fstrim.timer || false
##_nsudo systemctl enable git-daemon || false
##_nsudo systemctl enable vmtoolsd || false
#_nsudo systemctl enable adb || false
##_nsudo systemctl enable lxd || false
#_nsudo systemctl enable containerd || false
#_nsudo systemctl enable docker || false
#_nsudo systemctl enable warp-svc || false
##_nsudo systemctl enable vpnc || false
#_nsudo systemctl enable darkstat || false
#_nsudo systemctl enable darkhttpd || false
#_nsudo systemctl enable mysql || false
#_nsudo systemctl enable mariadb || false
#_nsudo systemctl enable bettercap || false
#_nsudo systemctl enable geoipupdate || false
#_nsudo systemctl enable clamav-daemon || false
#_nsudo systemctl enable adguardhome || false

# ??registring for XDMCP
#_nsudo systemctl enable xdm || false

# Snap
#_safe_systemctl enable snapd.apparmor || false
#_safe_systemctl enable apparmor || false
#_safe_systemctl enable snapd.socket || false
#_safe_systemctl enable snapd || false

# disable light-locker on live
for _cfg_lightlocker in $(find "/home/${username}/.config" -type f | grep config | xargs -n1 realpath)
do
    _nsudo sed -ri "/light/s/^/# /g" "${_cfg_lightlocker}"
done

# disable auto screen lock
remove /etc/xdg/autostart/light-locker.desktop || true

# Update system datebase
if type -p dconf 1>/dev/null 2>/dev/null; then
    _nsudo dconf update
fi

# gdm
if [[ -f /usr/bin/gdm ]]; then
    #_nsudo systemctl enable add gdm

    # Replace auto login user
    _nsudo sed -i 's|#\(WaylandEnable\)|\1|' "/etc/gdm/custom.conf"
    _nsudo sed -ri "s|%USERNAME%|${username}|g" "/etc/gdm/custom.conf"

    # Remove file for japanese input (states will moved another chance)
    if [[ ! "${language}" = "ja" ]]; then

        for _cfg_environment in "/etc/environment" "/etc/skel/.xprofile" "/home/${username}/.xprofile"
        do
            _nsudo sed -ri "s|^s*export GTK_IM_MODULE=.+|#export GTK_IM_MODULE=fcitx|g" "${_cfg_environment}"
            _nsudo sed -ri "s|^s*export QT_IM_MODULE=.+|#export QT_IM_MODULE=fcitx|g" "${_cfg_environment}"
            _nsudo sed -ri "s|^s*export XMODIFIERS=.+|#export XMODIFIERS=@im=fcitx|g" "${_cfg_environment}"
            _nsudo sed -ri "s|^s*export GLFW_IM_MODULE=.+|#export GLFW_IM_MODULE=@im=fcitx|g" "${_cfg_environment}"
        done
    fi
fi

# lightdm
if [[ -f /usr/bin/lightdm ]]; then
    _nsudo echo -e "\nremove /etc/lightdm/lightdm.conf.d/02-autologin.conf" >> "/usr/share/calamares/final-process"
    
    # Enable lightdm to auto login in live session
    _nsudo systemctl enable lightdm || false

    #if [[ -d /etc/lightdm/lightdm.conf.d/ ]]; then
        #_nsudo sed -ri "s|%USERNAME%|${username}|g" "/etc/lightdm/lightdm.conf.d/02-autologin.conf"

        # Session list
        #if [[ -f "/etc/lightdm/lightdm.conf.d/02-autologin-session.conf" ]] && cat "/etc/lightdm/lightdm.conf.d/02-autologin-session.conf" | grep "%SESSION%" 1> /dev/null 2>&1; then
        #session_list=()
            #while read -r session; do
            #    session_list+=("${session}")
            #done < <(find "/usr/share/xsessions" -type f | grep .desktop | xargs -n1 sudo -u#0 -g#0 fakeroot sed 's/.desktop//g')
            #if (( "${#session_list[@]}" == 1)); then
            #    session="${session_list[*]}"
                #_nsudo sed -ri "s|%SESSION%|${session}|g" "/etc/lightdm/lightdm.conf.d/02-autologin-session.conf"
            #elif (( "${#session_list[@]}" == 0)); then
            #    _nsudo echo "Warining: Auto login session was not found"
            #else
            #    _nsudo echo "Failed to set the session.Multiple sessions were found." >&2
            #    _nsudo echo "Please set the session of automatic login in /etc/lightdm/lightdm.conf.d/02-autologin-session.conf"
            #    _nsudo echo "Found session: $(printf "%s " "${session_list[@]}")"
            #    sleep 0.5
            #    exit 1
            #fi
        #fi
    #fi
fi

# sddm
if [[ -f /usr/bin/sddm ]]; then
    if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
        _nsudo sed -ri "s|%USERNAME%|${username}|g" "/etc/sddm.conf.d/autologin.conf"
    fi
fi

# qtongtk
if [[ -f /usr/bin/qt5ct ]]; then
    #_cfg_qt5ct_cmdline="export QT_QPA_PLATFORMTHEME="
    _cfg_qt5ct_files=(
        "/etc/zsh/zshenv"
        "/etc/bash.bashrc"
        "/etc/skel/.profile"
        "/home/${username}/.profile"
    )

    for cfg_qt5ct_file in "${_cfg_qt5ct_files[@]}"; do
        _nsudo mkdir -p "$(dirname "${cfg_qt5ct_file}")"
        #touch "${cfg_qt5ct_file}"
        #_nsudo echo "${_cfg_qt5ct_cmdline}" >> "${cfg_qt5ct_file}"
    done
fi

#if [[ -f /usr/bin/calamares ]]; then
#    # Create Calamares Entry
#    if [[ -f "/etc/skel/Desktop/calamares.desktop" ]]; then
#        cp -raT "/etc/skel/Desktop/calamares.desktop" "/usr/share/applications/calamares.desktop"
#    fi
#
#    # Delete the configuration file for prevent bad plymouth conflicts.
#    remove "/usr/share/calamares/modules/services-plymouth.conf"
#    cp -raT "/usr/share/calamares/modules/services.conf" "/usr/share/calamares/modules/services-plymouth.conf"
#
#    # Calamares configs
#
#    # Replace the configuration file.
#    # initcpio
#    _nsudo sed -ri "s|%MKINITCPIO_PROFILE%|${kernel_mkinitcpio_profile}|g" /usr/share/calamares/modules/initcpio.conf
#    # unpackfs
#    ## {squashfs,erofs,tar.gz}
#    _nsudo sed -ri "s|%KERNEL_FILENAME%|${kernel_filename}|g" /usr/share/calamares/modules/unpackfs.conf
#
#    # Remove configuration files for other kernels.
#    #remove "/usr/share/calamares/modules/initcpio"
#    #remove "/usr/share/calamares/modules/unpackfs"
#
#    # Set up calamares removeuser
#    _nsudo sed -ri "s|%USERNAME%|${username}|g" "/usr/share/calamares/modules/removeuser.conf"
#    # Set user shell
#    _nsudo sed -ri "s|%USERSHELL%|${usershell}|g" "/usr/share/calamares/modules/users.conf"
#    # Set INSTALL_DIR
#    _nsudo sed -ri "s|%INSTALL_DIR%|${install_dir}|g" "/usr/share/calamares/modules/unpackfs.conf"
#    # Set ARCH
#    _nsudo sed -ri "s|%ARCH%|${arch}|g" "/usr/share/calamares/modules/unpackfs.conf"
#
#    # Add disabling of sudo setting
#    _nsudo echo -e "\nremove \"remove /etc/polkit-1/rules.d/01-nopasswork.rules\"" >> "/usr/share/calamares/final-process"
#fi

# Added autologin group to auto login
_groupadd autologin
_nsudo usermod -aG autologin "${username}"

while true
do
    yes | pacman -Syyu --noconfirm --overwrite="*" "${pacman_args[@]}" gawk cmake python-pip opencl-headers && break || true
done

# python
## broken code: pyDes overpy sklearn chainer pyforest csvkit qrcode wikipedia tkinter pyrosm
## outdated: hmac hashlib secrets
## will outdated: bitcoin futures
## oversized: torch
## metadata? staticmap osmread osmapi openstreetmap OSMPythonTools osmnx

for _cfg_pythontools in wheel defusedxml xmlschema Brotli zstandard \
pyinstaller pytest pytest-asyncio pytest-cov pytest-timeout pytest-xdist pdoc \
asgiref requests tox certifi cryptography wsproto click hypothesis parver \
flask h11 h2 hyperframe kaitaistruct ldap3 mitmproxy_wireguard msgpack passlib publicsuffix2 \
pyperclip ruamel.yaml sortedcontainers tornado urwid typing-extensions \
pyOpenSSL h5py scipy ipython cython joblib numpy pandas \
pytz backtrader base58 pycryptodome ecdsa datetime xlwt xlrd \
seaborn Pillow jupyter matplotlib scikit-learn sympy nose \
pytz backtrader xlsxwriter folium
do
    while true
    do
        _nsudo mkdir -m 755 -p "/home/${username}/.local"
        _nsudo chown ${username}:${username} -R "/home/${username}/.local" || true
        sudo -u "${username}" -g "${username}" pip install "${_cfg_pythontools}" && break || true
    done
done

# Whonix gateway download & install
#VERSION_WHO='16.0.9.0'
#URL="https://download.whonix.org/ova/${VERSION_WHO}/Whonix-XFCE-${VERSION_WHO}.ova" 
#su $username -c "wget -O /home/${username}/tmp.ova $URL"
#su $username -c "vboxmanage import /home/${username}/tmp.ova --vsys 0 --eula accept --vsys 1 --eula accept"
#su $username -c "rm /home/${username}/tmp.ova"

# WPScan Update
if [[ -f /usr/bin/wpscan ]]; then
    wpscan --update
fi

#for _cfg_gpgtools_srv in hkps://keys.gentoo.org:443
#do
#    while true
#    do
#        pacman-key --refresh-keys --keyserver "${_cfg_gpgtools_srv}" && break || true
#    done
#done
