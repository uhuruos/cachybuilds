#!/bin/sh
#
# silencesuzuka
# Discord: sulogin#0921
# Email  : makeworldgentoo@gmail.com
#
# (c) 1998-2140 silencesuzuka
#
#shellcheck disable=SC2001

failed_pkg=()
remove_list=()
pacman_debug=false

trap 'false' 1 2 3 15

function _help() {
    echo "usage ${0} [option] [aur helper args] ..."
    echo
    echo "Install aur packages with ${aur_helper_command}"
    echo
    echo " General options:"
    echo "    -a [command]             Set the command of aur helper"
    echo "    -c                       Enable pacman debug message"
    echo "    -e [pkg]                 Set the package name of aur helper"
    echo "    -d [pkg1,pkg2...]        Set the package of the depends of aur helper"
    echo "    -p [pkg1,pkg2...]        Set the AUR package to install"
    echo "    -u [user]                Set the user name to build packages"
    echo "    -x                       Enable bash debug message"
    echo "    -h                       This help message"
}

while getopts "a:c:d:e:p:u:x:h" arg; do
    case "${arg}" in
        a) aur_helper_command="${OPTARG}" ;;
        c) pacman_debug=true ;;
        e) aur_helper_package="${OPTARG}" ;;
        p) readarray -t pkglist < <(sed "s/,$//g" <<< "${OPTARG}" | tr "," "\n") ;;
        d) readarray -t aur_helper_depends < <(sed "s/,$//g" <<< "${OPTARG}" | tr "," "\n") ;;
        u) username="${OPTARG}" ;;
        x) set -xv ;;
        h)
            _help
            exit 0
            ;;
        *)
            _help
            false
            ;;
    esac
done

shift "$((OPTIND - 1))"
aur_helper_args+=("${@}")
eval set -- "${pkglist[@]}"

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
function remove() { local _file
    for _file in "${@}"; do echo "Removing ${_file}" >&2; rm -rf "${_file}"; done
}

# Force on User Privilege
function run_user() {
    sudo -u "${username}" -g "$(whoami)" "${@}"
    #sudo -u#65534 -g#65534 "${@}"
}

# hard-tuning Makefile + (simply arrange
#10.8.3 myHack method; original sed+perl(binary)->rebuild kernelcache->rebuild kextcache->permission heal)
function _cflags_hack() {
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|gcc-ar|llvm-ar|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|ld.bfd|/ld.gold|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|fuse-ld=bfd|fuse-ld=gold|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|fuse-ld=gold|fuse-ld=gold|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|-flto |-flto=thin |g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|-fschedule-insns2 ||g" || true
    find . -type f | grep CMakeLists.txt | xargs -n1 sed -ri "s|fuse-ld=bfd|fuse-ld=gold|g" || true
    find . -type f | grep CMakeLists.txt | xargs -n1 sed -ri "s|fuse-ld=gold|fuse-ld=gold|g" || true
    find . -type f | grep CMakeLists.txt | xargs -n1 sed -ri "s|fuse-ld=mold|fuse-ld=gold|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|optimize(\"O[0-z]\")|optimize(\"O2\")\npragma\ \GCC\ \optimize(\"unroll-loops\")|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|--optimize=[0-z]|--optimize=2|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|pythonoptimize=[0-z]|pythonoptimize=2|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|-gccgoflags\ \"O[0-z]\"|-gccgoflags\ \"O2\"|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|opt-level=[0-z]|opt-level=3|g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|--optimize=[0-z]|--optimize=2|g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|pythonoptimize=[0-z]|pythonoptimize=2|g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|-gccgoflags\ \"O[0-z]\"|-gccgoflags\ \"O2\"|g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|opt-level=[0-z]|opt-level=2|g" || true
    find . -type f | grep '\.\(*c\|cc\|cs\|css\|cpp\|cxx\|d\|go\|h\|hh\|hpp\|hxx\|js\|m\|mak\|nim\|o\|py\|pyc\|rs\|s\|S\|*sh\|swig\|swigcxx\|syso\|v\|vbs\|vbscript\)' | xargs -n1 sed -ri "s|-O[0-z]|-O2|g" || true
    find . -type f | grep Makefile | xargs -n1 sed -ri "s|C++98|C++11|g" || true
    find . -type f | grep Makefile | xargs -n1 sed -ri "s|C++89|C++98|g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|options=\(|options\=('\!strip\' |g" || true
    find . -type f | grep PKGBUILD | xargs -n1 sed -ri "s|'\!lto\'|\lto\'|g" || true
    find . -type f | grep Makefile | xargs -n1 sed -ri "s|LTO=[0-z] |LTO=thin |g" || true
    find . -type f | grep Makefile | xargs -n1 sed -ri "s|-O[0-z]|-O2|g" || true
    find . -type d | xargs -n1 chmod 755 || true
    find . -type f | xargs -n1 chmod 644 || true
    chown "${username}:$(whoami)" -R . || true
    #chown 65534:65534 -R .. || true
}

function installpkg() {
    run_user "${aur_helper_command}" -S \
            --cachedir "/var/cache/pacman/pkg/" \
            "${pacman_args[@]}" \
            "${aur_helper_args[@]}" \
            "${@}" || true
}

#-- main funtions --#
function prepare_env() {
    _nsudo ldconfig

    # Prevent systemd-oom/d bugs.
    if [[ -f /usr/bin/systemd ]] ; then
        _nsudo rfkill unblock all
        _nsudo systemctl disable systemd-rfkill
        _nsudo systemctl mask systemd-rfkill
        _nsudo systemctl unmask systemd-rfkill
        _nsudo systemctl disable systemd-oom
        _nsudo systemctl disable systemd-oomd
        _nsudo systemctl mask systemd-oom
        _nsudo systemctl mask systemd-oomd
        _nsudo systemctl unmask systemd-oom
        _nsudo systemctl unmask systemd-oomd
    fi

    # (relinking) Correcting /etc/alternatives
    if [[ ! -f "/etc/alternatives" ]]; then
        _nsudo mkdir -m 755 -p /etc/alternatives
    fi

    if [[ -f "/etc/alternatives" ]]; then
        _nsudo ln -snf /etc/alternatives/awk /usr/bin/gawk
        _nsudo ln -snf /etc/alternatives/nawk /usr/bin/gawk
    fi

    # remove duplicated database entry
    if [[ -f "/etc/alternatives" ]]; then
        _nsudo ls /var/lib/pacman/local/ | sort -V | awk -v re='(.*)-[^-]*-[^-]*$' 'match($0, re, a) { if (!(a[1] in p)){p[a[1]]} else {print} }' | xargs -n1 sudo -u#0 -g#0 fakeroot rm -rf
    fi

    # link for gcc-build if gentoo toolchain will alive
    if [[ -d "/usr/x86_64-pc-linux-gnu/gcc-bin" ]]; then
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-c++ -executable)" /usr/lib/c++
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-cpp -executable)" /usr/lib/cpp
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-g++ -executable)" /usr/lib/g++
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-gcc -executable)" /usr/lib/gcc
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-gcov -executable)" /usr/lib/gcov
        _nsudo ln -snf "$(find /usr/x86_64-pc-linux-gnu/gcc-bin/ -name x86_64-pc-linux-gnu-gfortran -executable)" /usr/lib/gfortran
    fi

    _nsudo usermod -s "${usershell}" root
    _nsudo useradd -m -s "${usershell}" "${username}"
    _nsudo usermod -aG users,lp,wheel,storage,power,video,audio,input,network "${username}"

    # Uncomment the mirror list.
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        _nsudo sed -ri "s/#Server/Server/g" "/etc/pacman.d/mirrorlist"
    fi
}

function doinstall_AdaCoreGNAT() { local __sha1sums_GNAT __ver_GNAT __rand
    #'gnat-gpl' supports riscv64-elf-linux64, x86_64-linux , arm-elf-linux64 mainly. 
    __sha1sums_GNAT='f3a99d283'
    __ver_GNAT='gnat-2021-20210519-x86_64-linux-bin'
    __rand=$( echo -n "$(od -vAn -N2 < /dev/random)$(date "+%s")" | tr -d " " )
    _nsudo wget -O "${HOME}/prebuilt_GNAT.tar" "https://community.download.adacore.com/v1/${__sha1sums_GNAT}?filename=${__ver_GNAT}&rand=${__rand}" || false

    _nsudo mkdir -m 755 -p "${HOME}/tmp_AdaCore"
    _nsudo bsdtar xvpf "${HOME}/prebuilt_GNAT.tar" -C "${HOME}/tmp_AdaCore"
    _nsudo "${HOME}/tmp_AdaCore/doconfig" 
    _nsudo "${HOME}/tmp_AdaCore/doinstall"

    _nsudo rm -rf "${HOME}/tmp_AdaCore"
    _nsudo rm -rf "${HOME}/prebuilt_GNAT.tar"
}

function fetch_keyring() {
    # Setup keyring
    if [[ -f /usr/bin/systemd-resolve ]]; then
        _nsudo systemd-resolve --flush-caches &&
        _nsudo systemd-resolve --statistics &&
        sleep 7
    fi &&
    _nsudo hwclock --verbose --directisa --systohc --utc &&
    _nsudo ntpd -qg &&
    _nsudo hwclock -w &&
    while true
    do
        _nsudo pacman -Syu --noconfirm --overwrite="*" "${pacman_args[@]}" && break || true
    done
    _nsudo pacman-key --init

    local _gpgkey _cfg_gpgtools_srv cfg_gpgtools_srv 
    for _gpgkey in $(find /usr/share/pacman/keyrings | grep '\.gpg$' | xargs -n1 basename | sed 's|\.[^*]\+$||')
    do
        _nsudo pacman-key --populate "${_gpgkey}"
    done

    for _cfg_gpgtools_srv in hkps://keys.gentoo.org:443
    do
        while true
        do
            _nsudo pacman-key --refresh-keys --keyserver "${_cfg_gpgtools_srv}" && break || true
        done
    done
}

# use not tmpfs(RAM) in several case PKGBUILD
function run_makepkgs() { local _pkg pkg
    # Parse SRCINFO
    _nsudo chmod 755 -R "/AURHelper"
    _nsudo chown "${username}:$(whoami)" -R "/AURHelper"
    cd "/AURHelper"
    readarray -t pkgbuild_dirs < <(find "/AURHelper" -mindepth 1 -maxdepth 1 -type d | sort -V 2> /dev/null)
    if (( "${#pkgbuild_dirs[@]}" != 0 )); then
        for _dir in "${pkgbuild_dirs[@]}"; do
            cd "${_dir}"
            _cflags_hack
            readarray -t depends < <(source "${_dir}/PKGBUILD"; printf "%s\n" "${depends[@]}")
            readarray -t makedepends < <(source "${_dir}/PKGBUILD"; printf "%s\n" "${makedepends[@]}")
            if (( ${#depends[@]} + ${#makedepends[@]} != 0 )); then
                for _pkg in "${depends[@]}" "${makedepends[@]}"; do
                    if _nsudo pacman -Ssq "${_pkg}" | grep -x "${_pkg}" 1> /dev/null; then
                        while true
                        do
                            _nsudo pacman -S --noconfirm --overwrite="*" "${pacman_args[@]}" "${_pkg}" && break || true
                        done
                    fi
                done
            fi
            run_user makepkg "${makepkg_args[@]}"
            for pkg in $(run_user makepkg -f --packagelist); do
                _nsudo pacman -U --noconfirm --overwrite="*" "${pacman_args[@]}" "${pkg}" || true
            done
            cd ..
            remove "${_dir}"
        done
    fi

    # Clean up
    _nsudo pacman -Sccc --noconfirm || true
    while true
    do
        _nsudo pacman -Syy --noconfirm && break || true
    done
}

# we ought to do procedure only about "${aur_helper_package}"
function install_aur_helper() { local _pkg
    # Install
    if ! _nsudo pacman -Qq "${aur_helper_package}" 1> /dev/null 2>&1; then

        # Install depends
        for _pkg in "${aur_helper_depends[@]}"; do
            if ! _nsudo pacman -Qq "${_pkg}" > /dev/null 2>&1 | grep -q "${_pkg}"; then
                while true
                do
                    _nsudo pacman -Syyuu --noconfirm --overwrite="*" "${pacman_args[@]}" "${aur_helper_depends[@]}" && break || true
                done
            fi
        done

        # Build
        run_user git clone "https://aur.archlinux.org/${aur_helper_package}.git" "/home/${username}/${aur_helper_package}"
        run_user git config --global --add safe.directory "/home/${username}/${aur_helper_package}" || remove "/home/${username}/${aur_helper_package}" && false ||
        cd "/home/${username}/${aur_helper_package}" &&
        _cflags_hack
        run_user makepkg "${makepkg_args[@]}" || false || remove "/home/${username}/${aur_helper_package}"

        # Install
        for _pkg in $(cd "/home/${username}/${aur_helper_package}"; run_user makepkg --packagelist)
        do
            _nsudo pacman -U --noconfirm --overwrite="*" "${pacman_args[@]}" "${_pkg}"
        done

        # Remove debris
        cd ..
        remove "/home/${username}/${aur_helper_package}"
    fi

    if ! type -p "${aur_helper_command}" > /dev/null; then
        echo "Failed to install ${aur_helper_package}"
        sleep 14
    fi
}

# specifying about selecting from yours, not considering by "${aur_helper_package}" themselves.
function install_aur_pkgs() { local _pkg
    # Build and install
    for _pkg in "${@}"; do
        installpkg "${_pkg}"
        if ! _nsudo pacman -Qq "${_pkg}" > /dev/null 2>&1; then
            echo -e "\n[aur_helper_command::builduser.sh] Failed to install ${_pkg}\n"
            failed_pkg=("${_pkg}")
        fi
    done

    # Reinstall failed package
    for _pkg in "${failedpkg[@]}"; do
        installpkg "${_pkg}"
        if ! _nsudo pacman -Qq "${_pkg}" > /dev/null 2>&1; then
            echo -e "\n[pacman::builduser.sh] Failed to install ${_pkg}\n"
            remove_list+=("${_pkg}")
        fi
    done

    # Clean up
    _nsudo pacman -Sccc --noconfirm || true
    while true
    do
        _nsudo pacman -Syy --noconfirm && break || true
    done
}

function cleanup() {
    ## Remove packages
    readarray -t -O "${#remove_list[@]}" remove_list < <(_nsudo pacman -Qtdq)
    (( "${#remove_list[@]}" != 0 )) && _nsudo pacman -Rddnc "${pacman_args[@]}" "${remove_list[@]}" || true

    remove "/AURHelper"
    remove "/var/cache/pacman/pkg/"
}

# For debugs
if [[ "${pacman_debug}" = true ]]; then
    pacman_args+=("--debug")
fi

prepare_env
#fetch_keyring
run_makepkgs
install_aur_helper
install_aur_pkgs "$@"
cleanup
