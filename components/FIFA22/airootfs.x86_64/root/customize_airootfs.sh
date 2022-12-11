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

## Make it compatible with previous code
unset OPTIND OPTARG arg

_nsudo ldconfig

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

    _nsudo usermod -s "${usershell}" root
    _nsudo useradd -m -s "${usershell}" "${username}"
    _nsudo usermod -aG users,lp,wheel,storage,power,video,audio,input,network "${username}"

# Allow supervisor group to run as root with any command
for _cfg_visor in "admin" "root" "wheel"
do
    _groupadd "${_cfg_visor}"
    _nsudo sed -i 's/^#\s*\(%"${_cfg_visor}"\s\+ALL=(ALL)\s\+ALL\)/\1/' "/etc/sudoers.d/g_${_cfg_visor}" || true
done

run_additional_command "xdg-user-dirs-update" "LC_ALL=C LANG=C xdg-user-dirs-update"

# Set up auto login
if [[ -f "/etc/systemd/system/getty.target.wants/getty@tty1.service" ]]; then
    _nsudo sed -ri "s|%USERNAME%|${username}|g" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
fi

# Replace shortcut list config
if [[ "${language}" = "ja" ]]; then
    _nsudo echo 'LANG=ja_JP.UTF-8' > /etc/locale.conf
fi

# Uncomment the mirror list.
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

# Enable graphical.
_nsudo systemctl enable graphical.target
_nsudo systemctl set-default graphical.target

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

while true
do
    yes | pacman -Syyu --noconfirm --overwrite="*" "${pacman_args[@]}" gawk cmake python-pip opencl-headers && break || true
done

# python
## broken code: pyDes overpy sklearn chainer pyforest csvkit qrcode wikipedia tkinter pyrosm \
##    publicsuffix2 pyperclip 
## outdated: hmac hashlib secrets
## will outdated: bitcoin futures
## oversized: torch
## metadata? staticmap osmread osmapi openstreetmap OSMPythonTools osmnx

for _cfg_pythontools in wheel defusedxml xmlschema Brotli zstandard \
pyinstaller pytest pytest-asyncio pytest-cov pytest-timeout pytest-xdist pdoc \
asgiref requests tox certifi cryptography wsproto click hypothesis parver \
flask h11 h2 hyperframe kaitaistruct ldap3 mitmproxy_wireguard msgpack passlib \
ruamel.yaml sortedcontainers tornado urwid typing-extensions \
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
