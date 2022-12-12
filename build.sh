#!/bin/sh
#
# silencesuzuka
# Discord: sulogin#0921
# Email  : makeworldgentoo@gmail.com
#
# (c) 1998-2140 silencesuzuka
#
# build.sh
#
# The main script that runs the build
#

#-- fix running systemd bug --#
if [[ -f "/usr/lib/systemd" ]]; then
    unshare --pid="/usr/lib/systemd" || exit
fi

set -Eeu

# Be more Bourne compatible
DUALCASE=1; export DUALCASE # for MKS sh
if test -n "${ZSH_VERSION+set}" && (emulate sh) >/dev/null 2>&1; then :
  emulate sh
  NULLCMD=:
  # Pre-4.2 versions of Zsh do word splitting on ${1+"$@"}, which
  # is contrary to our usage.  Disable this feature.
  alias -g '${1+"$@"}'='"$@"'
  setopt NO_GLOB_SUBST
else
  case `(set -o) 2>/dev/null` in #(
  *posix*) :
    set -o posix ;; #(
  *) :
     ;;
esac
fi

# Internal config
# Do not change these values.
script_path="$( cd -P "$( dirname "$(readlink -f "${0}")" )" && pwd )"
defaultconfig="${script_path}/default.conf"
tools_dir="${script_path}/tools" component_dir="${script_path}/components"
customized_username=false customized_password=false customized_kernel=false customized_logpath=false
pkglist_args=() makepkg_script_args=() components=() norepopkg=()
legacy_mode=false rerun=false
DEFAULT_ARGUMENT="" ARGUMENT=("${@}")
archiso_version="3.1"

# Load config file
[[ ! -f "${defaultconfig}" ]] && "${tools_dir}/msg.sh" -a 'build.sh' error "${defaultconfig} was not found." && exit 1
for config in "${defaultconfig}" "${script_path}/custom.conf"; do
    [[ -f "${config}" ]] && source "${config}" && loaded_files+=("${config}")
done

umask 0022

# Message string
function _pseudoecho() { local _witches
   for _witches in "${@:-1}"
   do
   case ${?} in
       "*" | "0" ) printf "\033[1;32;40m>>> \033[1;37;40m${_witches}\033[1;\n" ;;
       "1" ) printf "\033[1;31;40m!!! \033[1;37;40m${_witches}\033[1;\n" ;;
       "2" ) printf "\033[1;33;40m*** \033[1;37;40m${_witches}\033[1;\n" ;;
   esac
   done
}

# Usage: getclm <number>
# 標準入力から値を受けとり、引数で指定された列を抽出します。
function getclm() { cut -d " " -f "${1}"; }

# Usage: echo_blank <number>
# 指定されたぶんの半角空白文字を出力します
function echo_blank() { yes " " 2> /dev/null  | head -n "${1}" | tr -d "\n"; }

# isolated i/o sudo
function _nsudo() { fakeroot ionice -c 1 -n 1 sudo -S LANGUAGE=C LC_ALL=C unshare --fork --pid nice -n -20 "${@}" ; }
# isolated sudo
function _isudo() { sudo -u#0 -g#0 fakeroot nice -n -20 "${@}" ; }
# isolated sudo for build.sh runs
function _esudo() { sudo -u#0 -g#0 nice -n -20 "${@}" ; }

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

function _usage() {
    cat "${script_path}/docs/build.sh/help.1"
    local blank="29" _arch _dirname _type _output _first
    for _type in "locale" "kernel"; do
        echo " ${_type} for each architecture:"
        for _arch in $(find "${script_path}/system/" -maxdepth 1 -mindepth 1 -name "${_type}-*" -print0 | xargs -I{} -0 basename {} | sed "s|${_type}-||g"); do
            echo "    ${_arch}$(echo_blank "$(( "${blank}" - "${#_arch}" ))")$("${tools_dir}/${_type}.sh" -a "${_arch}" show)"
        done
        echo
    done

    echo " Channel:"
    for _dirname in $(sh "${tools_dir}/channel.sh" --version "${archiso_version}" -d -b -n --line show | sed "s|.add$||g"); do
        readarray -t _output < <("${tools_dir}/channel.sh" --version "${archiso_version}" --nocheck desc "${_dirname}")
        _first=true
        echo -n "    ${_dirname}"
        for _out in "${_output[@]}"; do
            "${_first}" && echo -e "    $(echo_blank "$(( "${blank}" - 4 - "${#_dirname}" ))")${_out}" || echo -e "    $(echo_blank "$(( "${blank}" + 5 - "${#_dirname}" ))")${_out}"
            _first=false
        done
    done
    cat "${script_path}/docs/build.sh/help.2"
    [[ -n "${1:-}" ]] && exit "${1}"
}

# Unmount helper Usage: _umount <target>
function _umount() { umount -vdl "${@}" || true ; }

# Mount helper Usage: mount <source> <target>
function mount_airootfs() {
    if [[ -f "${airootfs_dir}.img" ]] && [[ -d "${airootfs_dir}" ]] ; then
        mount "${airootfs_dir}.img" "${airootfs_dir}"
        mount --mkdir -t devtmpfs none "${airootfs_dir}/dev"
        mount --mkdir -t sysfs none "${airootfs_dir}/sys"
        mount --mkdir -t proc none "${airootfs_dir}/proc"
        mount --mkdir "${tmpfs_dir}.img" "${airootfs_dir}/tmp"
    fi
}


# [WHAT DREAMCOLLAPSE WTF] {dev,proc,sys,efivars,tmp,run,mnt,media,lost+found,*}
# Unmount helper for special devices
function umount_specials() {
   for special in dev sys efivars proc dev pts shm run tmp
   do
       for count in $(seq 2)
       do
           umount -vdl "${airootfs_dir}/${special}" || true
       done
   done
}

# Helper function to run make_*() only one time.
function run_once() {
    if [[ ! -e "${lockfile_dir}/build.${1}" ]]; then
        _pseudoecho "Running ${1} ..."
        mkdir -m 755 -p "${airootfs_dir}"
        eval "${@}"
        mkdir -m 755 -p "${lockfile_dir}"; touch "${lockfile_dir}/build.${1}"
    else
        _pseudoecho "Skipped because ${1} has already been executed."
    fi
}

# Show message when file is removed
# remove <file> <file> ...
function remove() { local _file
    for _file in "${@}"; do _pseudoecho "Removing ${_file}"; rm -rf "${_file}"; done
}

# 強制終了時にアンマウント
function umount_trap() { local _status="${?}"

    # Separationg Specials
    umount_specials

    # Separating airootfs
    umount -vdl "${airootfs_dir}.img"

    _pseudoecho "It was killed by the user.\nThe process may not have completed successfully."
    exit "${_status}"
}

# 設定ファイルを読み込む
# load_config [file1] [file2] ...
function load_config() { local _file
    for _file in "${@}"; do [[ -f "${_file}" ]] && source "${_file}" && _pseudoecho "The settings have been overwritten by the ${_file}"; done
    return 0
}

# Display channel list
function show_channel_list() { local _args=("-v" "${archiso_version}" show)
    [[ "${nochkver}" = true ]] && _args+=("-n")
    sh "${tools_dir}/channel.sh" "${_args[@]}"
}

# Execute command for each component. It will be executed with {} replaced with the component name.
# for_component <command>
function for_component() { local component
    for component in "${components[@]}"; do eval "${@//"{}"/${component}}"; done; }

# Unpack Void
function _xbedrock_Void() { local __verVoid='20221001'

    wget -O "${cache_dir}/void.tar.xz" "https://mirrors.dotsrc.org/voidlinux/live/current/void-x86_64-ROOTFS-${__verVoid}.tar.xz" || false

    bsdtar xvpf "${cache_dir}/void.tar.xz" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{etc,bin,sbin,dev,sys,proc}/* \
               --exclude=^./usr/lib/* \
               --exclude=^./etc/polkit-1/* \
               --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/lib/sysctl.d/* \
               --exclude=^./usr/lib/sysusers.d/* --exclude=^./usr/lib/tmpfiles.d/* \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk --exclude=^./usr/lib/ld-* --exclude=^./usr/bin/* \
               --exclude=^./usr/share/* --exclude=/usr/local/share/man/* --exclude=^./var/service/* || true
}

# Unpack gentoo for clang
function _xbedrock_Gentoo_CLANG() { local __ver_Gentoo_CLANG=$( wget -O - "https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/latest-stage3-amd64-musl-clang.txt" | grep -vE '^\s*(#|$)' | awk '{print $1}' )

    wget -O "${cache_dir}/gentoo.clang" "https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/${__ver_Gentoo_CLANG}" || false

    bsdtar xvpf "${cache_dir}/gentoo.clang" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{etc,dev,sys,proc}/* \
               --exclude=^./usr/lib/* --exclude=^./usr/include/* \
               --exclude=^./etc/polkit-1/* --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/lib/sysctl.d/* \
               --exclude=^./usr/lib/sysusers.d/* --exclude=^./usr/lib/tmpfiles.d/* \
               --exclude=^./var/spool/* --exclude=^./bin/* --exclude=^./usr/bin/* \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk --exclude=^./usr/bin/augenrules --exclude=^./bin/awk --exclude=^./bin/arping \
               --exclude=^./usr/bin/go --exclude=^./usr/bin/gofmt --exclude=^./bin/passwd \
               --exclude=^./bin/ping --exclude=^./bin/ping4 --exclude=^./bin/ping6 --exclude=^./bin/ping \
               --exclude=^./bin/umount --exclude=^./usr/bin/augenrules \
               --exclude=^./usr/x86_64-gentoo-linux-musl/bin/* --exclude=^./usr/x86_64-gentoo-linux-musl/lib/* \
               --exclude=^./usr/lib/clang/* --exclude=^./var/tmp/* --exclude=^./var/cache/edb/* --exclude=^./var/db/pkg/* || true

    _nsudo find "${airootfs_dir}" -type f -name ".keep" | xargs -I{} rm -rf {} || true

    if [[ ! -d "${airootfs_dir}/var/db/repos" ]]; then
        echo -e "    [x] Merging Gentoo (clang) was failed. \n" && false
    fi

    _nsudo rm -rf "${airootfs_dir}/bin"
    _nsudo rm -rf "${airootfs_dir}/sbin"
    _nsudo rm -rf "${airootfs_dir}/lib"
    _nsudo rm -rf "${airootfs_dir}/lib64"
    _nsudo rm -rf "${airootfs_dir}/usr/bin"
    _nsudo rm -rf "${airootfs_dir}/usr/sbin"
    _nsudo rm -rf "${airootfs_dir}/usr/lib64"
}

# Unpack stage3nomultilibsystemd+portagerepos
function _xbedrock_Gentoo_GCC() { local __ver_Gentoo_GCC=$( wget -O - "https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/latest-stage3-amd64-nomultilib-systemd.txt" | grep -vE '^\s*(#|$)' | awk '{print $1}' )

    wget -O "${cache_dir}/gentoo.gcc" "https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/${__ver_Gentoo_GCC}" || false

    bsdtar xvpf "${cache_dir}/gentoo.gcc" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{etc,dev,sys,proc}/* \
               --exclude=^./etc/polkit-1/* --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/lib/sysctl.d/* \
               --exclude=^./usr/lib/sysusers.d/* --exclude=^./usr/lib/tmpfiles.d/* \
               --exclude=^./var/spool/* --exclude=^./bin/* --exclude=^./usr/bin/* \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk --exclude=^./usr/bin/augenrules --exclude=^./bin/awk --exclude=^./bin/arping \
               --exclude=^./usr/bin/go --exclude=^./usr/bin/gofmt --exclude=^./bin/passwd \
               --exclude=^./bin/ping --exclude=^./bin/ping4 --exclude=^./bin/ping6 --exclude=^./bin/ping \
               --exclude=^./bin/umount --exclude=^./usr/bin/augenrules \
               --exclude=^./usr/x86_64-pc-linux-gnu/bin/* --exclude=^./usr/x86_64-pc-linux-gnu/lib/* \
               --exclude=^./usr/lib/gcc/* --exclude=^./var/tmp/* --exclude=^./var/cache/edb/* --exclude=^./var/db/pkg/* || true

    _nsudo find "${airootfs_dir}" -type f -name ".keep" | xargs -I{} rm -rf {} || true

    if [[ ! -d "${airootfs_dir}/var/db/repos" ]]; then
        echo -e "    [x] Merging Gentoo Stage3 (gcc) was failed. \n" && false
    fi

    _nsudo rm -rf "${airootfs_dir}/bin"
    _nsudo rm -rf "${airootfs_dir}/sbin"
    _nsudo rm -rf "${airootfs_dir}/lib"
    _nsudo rm -rf "${airootfs_dir}/lib64"
    _nsudo rm -rf "${airootfs_dir}/usr/bin"
    _nsudo rm -rf "${airootfs_dir}/usr/sbin"
    _nsudo rm -rf "${airootfs_dir}/usr/lib64"
}

# Unpack Arch for alternative
function _xbedrock_Arch_STUB() { local __arch_mirrorurl
    if [[ -d "${airootfs_dir}/usr/local/share/man" ]]; then
        _nsudo rm -rf "${airootfs_dir}/usr/local/share/man"
    fi

    wget -O "${cache_dir}/arch-org.pacstrap" "https://mirror.sg.gs/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.gz" || false

    bsdtar xvpf "${cache_dir}/arch-org.pacstrap" --strip-components 1 -C "${airootfs_dir}"

    _nsudo rm -rf "${airootfs_dir}/etc/.pwd.lock"
}

# (CANNOT && DONOT) Unpack Alpine
function _xbedrock_Alpine() { local __verAlpine='3.16'

    wget -O "${cache_dir}/alpine.tar.gz" "https://ftp.udx.icscoe.jp/Linux/alpine/v${__verAlpine}/releases/x86_64/alpine-minirootfs-${__verAlpine}.0-x86_64.tar.gz"

    bsdtar xvpf "${cache_dir}/alpine.tar.gz" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{dev,sys,proc}/* \
               --exclude=^./etc/polkit-1/* \
               --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/lib/sysctl.d/* \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk \
               --exclude=^./var/run/* --exclude=^./var/spool/* || false

    _nsudo rm -rf "${airootfs_dir}/bin"
    _nsudo rm -rf "${airootfs_dir}/sbin"
    _nsudo rm -rf "${airootfs_dir}/lib"
    _nsudo rm -rf "${airootfs_dir}/lib64"
    _nsudo rm -rf "${airootfs_dir}/usr/sbin"
    _nsudo rm -rf "${airootfs_dir}/usr/lib64"
}

# (!BUT DO NOT FOREVER) Unpack Salix (false allocate shared memory area or wrong lock)
function _xbedrock_SalixOS() { local __verSalix='core'

    wget -O "${cache_dir}/salixos.tar.xz" "https://people.salixos.org/gapan/docker-rootfs/salix64-${__verSalix}-rootfs.tar.xz" || false

    bsdtar xvpf "${cache_dir}/salixos.tar.xz" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{dev,sys,proc}/* \
               --exclude=^./etc/polkit-1/* \
               --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk --exclude=^./var/run/* --exclude=^./var/spool/* || true

    _nsudo rm -rf "${airootfs_dir}/bin"
    _nsudo rm -rf "${airootfs_dir}/sbin"
    _nsudo rm -rf "${airootfs_dir}/lib"
    _nsudo rm -rf "${airootfs_dir}/lib64"
    _nsudo rm -rf "${airootfs_dir}/usr/sbin"
    _nsudo rm -rf "${airootfs_dir}/usr/lib64"
}

# Unpack Ubuntu
function _xbedrock_Ubuntu() { local __verUbuntu='kinetic'

    wget -O "${cache_dir}/ubuntu.tar.gz" "https://cdimage.ubuntu.com/ubuntu-base/daily/current/${__verUbuntu}-base-amd64.tar.gz" || false

    bsdtar xvpf "${cache_dir}/ubuntu.tar.gz" -C "${airootfs_dir}" --keep-newer-files \
               --exclude=^./{dev,sys,proc,sbin}/* \
               --exclude=^./etc/polkit-1/* \
               --exclude=^./etc/security/* --exclude=^./etc/group --exclude=^./etc/gshadow --exclude=^./etc/passwd \
               --exclude=^./usr/lib/sysctl.d/* \
               --exclude=^./usr/lib/sysusers.d/* --exclude=^./usr/lib/tmpfiles.d/* \
               --exclude=^./usr/bin/awk --exclude=^./usr/bin/gawk --exclude=^./usr/bin/nawk --exclude=^./usr/bin/pager \
               --exclude=^./var/lock/* --exclude=^./var/spool/* --exclude=^./usr/local/man || false

    _nsudo rm -rf "${airootfs_dir}/etc/alternatives"
    _nsudo rm -rf "${airootfs_dir}/lib64"
    _nsudo rm -rf "${airootfs_dir}/usr/sbin"
    _nsudo rm -rf "${airootfs_dir}/usr/lib/terminfo"
    _nsudo rm -rf "${airootfs_dir}/usr/lib64"
    _nsudo rm -rf "${airootfs_dir}/lib/x86_64-linux-gnu"
    _nsudo rm -rf "${airootfs_dir}/usr/lib/systemd"
}

# Unpack Nix -> After merging 'pacman -S nix'
function _xbedrock_NixOS() { local __verNixOS='2.9.2'

    wget -O "${cache_dir}/nixos.tar.xz" "https://releases.nixos.org/nix/nix-${__verNixOS}/nix-${__verNixOS}-x86_64-linux.tar.xz" || false
    tar xvJpf "${cache_dir}/nixos.tar.xz" --strip-components 3 -C "${airootfs_dir}" --keep-newer-files
}


# (!!! DO NOT CHANGE THESE ORDER)
function _xbedrock_all() {
    _xbedrock_NixOS
    _xbedrock_Void
    _xbedrock_Gentoo_CLANG
    _xbedrock_Gentoo_GCC
    _xbedrock_Arch_STUB
    _xbedrock_Alpine
    _xbedrock_SalixOS
    ##_xbedrock_SUSE
    ##_xbedrock_Debian
    _xbedrock_Ubuntu
    ##_xbedrock_Rocky

    if [[ -f "${airootfs_dir}/arch-org.pacstrap" ]]; then
        bsdtar xvpf "${cache_dir}/arch-org.pacstrap" -C "${airootfs_dir}" --keep-newer-files
    fi

    # Cleaner
    _nsudo rm -rf "${airootfs_dir}/usr/local/share/man"
    _nsudo rm -rf "${airootfs_dir}/etc/.pwd.lock"
    _nsudo rm -rf "${airootfs_dir}/var/lock"
    _nsudo rm -rf "${airootfs_dir}/var/empty"
    _nsudo rm -rf "${airootfs_dir}/var/mail"

    # Correlation
    if [[ -d "${airootfs_dir}/usr/bin" ]]; then
        _nsudo chmod 755 "${airootfs_dir}/usr/bin" || true
        _nsudo rm -rf "${airootfs_dir}/usr/bin/awk"
        _nsudo rm -rf "${airootfs_dir}/usr/bin/passwd"
        _nsudo rm -rf "${airootfs_dir}/usr/bin/git"
        _nsudo rm -rf "${airootfs_dir}/usr/bin/pip"
        _nsudo rm -rf "${airootfs_dir}/usr/bin/gawk*"
        _nsudo ln -snf "/usr/bin/gawk" "${airootfs_dir}/usr/bin/awk"
    fi
    if [[ -d "${airootfs_dir}/usr/lib" ]]; then
        _nsudo rm -rf "${airootfs_dir}/usr/lib/ld-linux-x86-64.so.2"
        _nsudo rm -rf "${airootfs_dir}/usr/lib/sysctl.d"
        _nsudo rm -rf "${airootfs_dir}/usr/lib/sysusers.d"
        _nsudo rm -rf "${airootfs_dir}/usr/lib/tmpfiles.d"
    fi

    if [[ -d "${airootfs_dir}/etc" ]]; then
        # passwd, user authorities
        _nsudo rm -rf "${airootfs_dir}/etc/polkit-1"
        _nsudo rm -rf "${airootfs_dir}/etc/security"
        _nsudo rm -rf "${airootfs_dir}/etc/group"
        _nsudo rm -rf "${airootfs_dir}/etc/gshadow"
        _nsudo rm -rf "${airootfs_dir}/etc/passwd"
        _nsudo rm -rf "${airootfs_dir}/etc/subgid"
        _nsudo rm -rf "${airootfs_dir}/etc/subuid"

        # shadow, selinux
        _nsudo rm -rf "${airootfs_dir}/etc/pam.d"
        _nsudo rm -rf "${airootfs_dir}/etc/sudoers.d"
        _nsudo rm -rf "${airootfs_dir}/etc/sudoers"
        _nsudo rm -rf "${airootfs_dir}/etc/securetty"
        _nsudo rm -rf "${airootfs_dir}/etc/selinux"
        _nsudo rm -rf "${airootfs_dir}/etc/selinux"
        _nsudo rm -rf "${airootfs_dir}/etc/shadow"

        # bloat
        _nsudo rm -rf "${airootfs_dir}/etc/rmt"
        _nsudo rm -rf "${airootfs_dir}/etc/ld.so.conf.d"
        _nsudo rm -rf "${airootfs_dir}/etc/inittab"
        _nsudo rm -rf "${airootfs_dir}/etc/init.d"
        _nsudo rm -rf "${airootfs_dir}/etc/kernel"
        _nsudo rm -rf "${airootfs_dir}/etc/localtime"
        _nsudo rm -rf "${airootfs_dir}/etc/profile"
        _nsudo rm -rf "${airootfs_dir}/etc/runlevels"
        _nsudo rm -rf "${airootfs_dir}/etc/services"
        _nsudo rm -rf "${airootfs_dir}/etc/systemd/system"
        _nsudo rm -rf "${airootfs_dir}/etc/sv"
        _nsudo rm -rf "${airootfs_dir}/etc/runit"
        _nsudo rm -rf "${airootfs_dir}/etc/ssl"

        # regex *.defs *.env *.d *.conf

        # regenerate
        _nsudo mkdir -m 755 -p "${airootfs_dir}/usr/lib/sysusers.d"
        _nsudo mkdir -m 755 -p "${airootfs_dir}/usr/lib/tmpfiles.d"
        _nsudo mkdir -m 755 -p "${airootfs_dir}/etc/ld.so.conf.d"
    fi

    _pseudoecho "[Warning] Fixing corrupted /var fail-lock ${airootfs_dir}/..."
    _nsudo rm -rf ${airootfs_dir}/var/lock
    #_nsudo mkdir -m 755 -p ${airootfs_dir}/var/lock
    _nsudo rm -rf ${airootfs_dir}/var/local
    #_nsudo mkdir -m 755 -p ${airootfs_dir}/var/local
}

function _cofpatcher() {
    _pseudoecho "[Warning] Fix libc(libc++) libm ELF, libcap, libcap-ng kmod, libcrypt.so.1 OpenSSL"
    #if [[ -f ${airootfs_dir}/usr/lib/libc-*.so ]]; then
    #    local __libc_certainsource=$( ls ${airootfs_dir}/usr/lib/libc-*.so | sort -V -r | head -1 )
    #    _nsudo ln -snf "${__libc_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libc.so.6"
    #fi
    if [[ -f ${airootfs_dir}/usr/lib/libz-*.so ]]; then
        local __libz_certainsource=$( ls ${airootfs_dir}/usr/lib/libz-*.so | sort -V -r | head -1 )
        _nsudo ln -snf "${__libz_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libz.so.1"
    fi
    if [[ -f ${airootfs_dir}/usr/lib/libm-*.so ]]; then
        local __libm_certainsource=$( ls ${airootfs_dir}/usr/lib/libm-*.so | sort -V -r | head -1 )
        _nsudo ln -snf "${__libm_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libm.so.6"
    fi
    if [[ -f ${airootfs_dir}/usr/lib/libcap.so.*.* ]]; then
        local __libcap_certainsource=$( ls ${airootfs_dir}/usr/lib/libcap.so.*.* | sort -V -r | head -1 )
        _nsudo ln -snf "${__libcap_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libcap.so.2"
    fi
    if [[ -f ${airootfs_dir}/usr/lib/libcap-ng.so.*.* ]]; then
        local __libcap_ng_certainsource=$( ls ${airootfs_dir}/usr/lib/libcap-ng.so.*.* | sort -V -r | head -1 )
       _nsudo ln -snf "${__libcap_ng_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libcap-ng.so.0"
    fi
    if [[ -f ${airootfs_dir}/usr/lib/libcrypto-*.so ]]; then
        local __libcrypto_certainsource=$( ls ${airootfs_dir}/usr/lib/libcrypto-*.so | sort -V -r | head -1 )
        _nsudo ln -snf "${__libcrypto_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/libcrypto.so.1"
    fi

    _pseudoecho "[Warning] Fix ld-linux.so.2"
    if [[ -f ${airootfs_dir}/usr/lib/ld-*.so ]]; then
        local __ld_certainsource=$( ls ${airootfs_dir}/usr/lib/ld-*.so | sort -V -r | head -1 )
       _nsudo ln -snf "${__ld_certainsource#${airootfs_dir}}" "${airootfs_dir}/usr/lib/ld-linux.so.2"
       _nsudo mv "${airootfs_dir}/usr/lib/ld-linux-x86-64.so.2" "${airootfs_dir}/usr/lib/ld-linux-x86-64.so"
       _nsudo ln -snf "/usr/lib/ld-linux-x86-64.so.2" "${airootfs_dir}/usr/lib/ld-linux-x86-64.so"
    fi
}

# debootstrap for stabilize libc++ -> pacman -S for collecting other binaries
function _pacstrap() {
    _pseudoecho "Installing packages to ${airootfs_dir}/'..."
    ## options if you use pacstrap
    #local _args=("${@}" "-C" "${build_dir}/pacman.conf" "-M" "${airootfs_dir}" "-c" "${airootfs_dir}" "-G" "${cache_dir}" "--refresh" "--sysupgrade" "--overwrite=${airootfs_dir}/*" "--noconfirm")

    # For debugs
    if [[ "${pacman_debug}" = true ]]; then
        pacman_args+=("--debug")
    fi
    local _args=("--config=${build_dir}/pacman.conf" "--root=${airootfs_dir}" "${pacman_args[@]}" )
    mkdir -m 755 -p "${airootfs_dir}/var/lib/pacman"

    # Ignore broken keyrings all && misc (DO NOT USE 'gnu-netcat')
    while true
    do
        _nsudo pacman -Syu --overwrite="${airootfs_dir}/*" "${_args[@]}" --dbonly --noscriptlet sudo glibc libc++ libxcrypt archlinux-keyring cachyos/pacman openbsd-netcat && break || true
    done

    _nsudo mv "${airootfs_dir}/var/lib/pacman" "${airootfs_dir}/var/lib/pacman_bak"
    _xbedrock_all

    # debootstrap (backup ubuntu latest url -> revert by them)
    #_nsudo cp "${airootfs_dir}/etc/apt/sources.list" "${cache_dir}/strapped-sources.list"
    #debootstrap --foreign --no-check-gpg --extractor=ar --arch=amd64 --variant buildd --include=ca-certificates,apt,wget,sudo,debootstrap \
    #                --merged-usr kinetic "${airootfs_dir}/" "http://archive.ubuntu.com/ubuntu/" || true
    #_nsudo cp "${cache_dir}/strapped-sources.list" "${airootfs_dir}/etc/apt/sources.list"

    if [[ -d "${airootfs_dir}/var/lib/pacman_bak" ]]; then
        _nsudo rm -rf "${airootfs_dir}/var/lib/pacman"
        _nsudo mv "${airootfs_dir}/var/lib/pacman_bak" "${airootfs_dir}/var/lib/pacman"
    fi

    # remove duplicated database entry
    _nsudo ls ${airootfs_dir}/var/lib/pacman/local/ | sort -V | awk -v re='(.*)-[^-]*-[^-]*$' 'match($0, re, a) { if (!(a[1] in p)){p[a[1]]} else {print} }' | xargs -n1 sudo -u#0 -g#0 fakeroot rm -rf

    _nsudo ln -snf "/usr/lib32" "${airootfs_dir}/lib32" || true
    _nsudo ln -snf "/usr/lib" "${airootfs_dir}/lib" || true
    _nsudo ln -snf "/usr/lib" "${airootfs_dir}/lib64" || true
    _nsudo ln -snf "/usr/lib" "${airootfs_dir}/usr/lib64" || true

    _nsudo ln -snf "/usr/bin" "${airootfs_dir}/sbin" || true
    _nsudo ln -snf "/usr/bin" "${airootfs_dir}/bin" || true
    _nsudo ln -snf "/usr/bin" "${airootfs_dir}/usr/sbin" || true

    # Correlation
    _cofpatcher

    _nsudo rm -rf "${airootfs_dir}/etc/ca-certicates/extracted/cadir/"*
    _nsudo rm -rf "${airootfs_dir}/etc/ssl/certs/"*.{bin,crt,pem}
    _nsudo mkdir -m 750 -p "${airootfs_dir}/etc/ssl/certs/"
    _nsudo wget -q http://curl.haxx.se/ca/cacert.pem -O "${airootfs_dir}/etc/ssl/certs/ca-certificates.crt"

    # you might be maintain precompiled binaries which under ${script_path}/system/fixfiles/*
    _pseudoecho "[Warning] Fix some compatible binaries which you had troublesome by run under bash"
    if [[ -d "${script_path}/system/fixfiles/root.any/" ]]; then
        _BNcp "${script_path}/system/fixfiles/root.any/" "${airootfs_dir}/"
    fi
    if [[ -d "${script_path}/system/fixfiles/root.${arch}/" ]]; then
        _BNcp "${script_path}/system/fixfiles/root.${arch}/" "${airootfs_dir}/"
    fi

    # you might be maintain file to configure about root privilege which under ${script_path}/system/fixfiles/*
    _pseudoecho "[Warning] Fix some compatible binaries which you had troublesome by run under bash"
    if [[ -d "${script_path}/system/authfiles/root.any/" ]]; then
        _BNcp "${script_path}/system/fixfiles/root.any/" "${airootfs_dir}/"
    fi
    if [[ -d "${script_path}/system/authfiles/root.${arch}/" ]]; then
        _BNcp "${script_path}/system/fixfiles/root.${arch}/" "${airootfs_dir}/"
    fi

    # reset kernel installation managed by pacman for correcting
    if [[ defaultkernel='core' ]]; then
        while true
        do
            _nsudo pacman -Syu --overwrite="${airootfs_dir}/*" "${_args[@]}" "${@}" && break || true
        done
    else
        local _args+=("${@}")
        while true
        do
            _nsudo pacman -Syu --overwrite="${airootfs_dir}/*" "${_args[@]}" "${@}" && break || true
            _nsudo pacman -Rddnc "${_args[@]}" linux linux-headers && break || true
        done
    fi

    # /adm to /var/log
    _nsudo ln -snf "/var/log" "${airootfs_dir}/adm"
    # bug awk by thrice 
    _nsudo ln -snf "/usr/bin/gawk" "${airootfs_dir}/usr/bin/awk"

    _pseudoecho "[Warning] Temporary pseudolinking cc/cpp for prevent sanity-check fails"
    if [[ ! -d "${airootfs_dir}/usr/lib/cpp" ]]; then
       _nsudo ln -snf /usr/bin/gcc "${airootfs_dir}/usr/lib/cc"
       _nsudo ln -snf /usr/bin/g++ "${airootfs_dir}/usr/lib/cpp"
    fi

    _pseudoecho "Packages installed successfully!"
}

# chroot環境でpacmanコマンドを実行
# /etc/pacman.confを準備してコマンドを実行します
function _run_with_pacmanconf() {
    sed "s|^#?\\s*CacheDir.+|#CacheDir.+|g" "${build_dir}/pacman.conf" > "${airootfs_dir}/etc/pacman.conf"
    eval -- "${@}"
}

# コマンドをchrootで実行する
function _chroot_run() { local _specialCH specialCH
    if [[ -d "${airootfs_dir}" ]] ; then
        _pseudoecho "Run command in chroot\nCommand: ${*}"
        _nsudo chroot "${airootfs_dir}" "/usr/bin/bash" "${@}" || return "${?}"
    else
        _pseudoecho "CANNOT chroot by stopping fault \nCommand: ${*}"
    fi
}

function _cleanup_airootfs() {
    _pseudoecho "Cleaning up what we can on airootfs..."

    # Delete all files in /boot
    [[ -d "${airootfs_dir}/boot" ]] && _nsudo find "${airootfs_dir}/boot" -mindepth 1 -type f -name 'init*' -delete

    # Delete pacman database sync cache files (*.tar.gz)
    [[ -d "${airootfs_dir}/var/lib/pacman" ]] && _nsudo find "${airootfs_dir}/var/lib/pacman" -maxdepth 1 -type f -delete

    # Delete pacman database sync cache
    [[ -d "${airootfs_dir}/var/lib/pacman/sync" ]] && _nsudo find "${airootfs_dir}/var/lib/pacman/sync" -delete

    # Delete pacman package cache
    [[ -d "${airootfs_dir}/var/cache/pacman/pkg" ]] && _nsudo find "${airootfs_dir}/var/cache/pacman/pkg" -type f -delete

    # Delete all log files, keeps empty dirs.
    [[ -d "${airootfs_dir}/var/log" ]] && _nsudo find "${airootfs_dir}/var/log" -type f -delete

    # Delete all temporary files and dirs
    [[ -d "${airootfs_dir}/var/tmp" ]] && _nsudo find "${airootfs_dir}/var/tmp" -mindepth 1 -delete

    # Delete package pacman related files.
    _nsudo find "${build_dir}" \( -name '*.pacnew' -o -name '*.pacsave' -o -name '*.pacorig' \) -delete || true

    # Delete all cache file
    [[ -d "${airootfs_dir}/var/cache" ]] && _nsudo find "${airootfs_dir}/var/cache" -mindepth 1 -delete

    # Create an empty /etc/machine-id
    _nsudo printf '' > "${airootfs_dir}/etc/machine-id"
}

function _mkchecksum() {
    _pseudoecho "Creating md5 checksum ..."
    echo "$(md5sum "${1}" | getclm 1) $(basename "${1}")" > "${1}.md5"
    _pseudoecho "Creating sha256 checksum ..."
    echo "$(sha256sum "${1}" | getclm 1) $(basename "${1}")" > "${1}.sha256"
}

# Check the value of a variable that can only be set to true or false.
function check_bool() { local _value _variable
    for _variable in "${@}"; do
        _pseudoecho -n "Checking ${_variable}..."
        eval ": \${${_variable}:=''}"
        _value="$(eval echo "\${${_variable},,}")"
        eval "${_variable}=${_value}"
        if [[ ! -v "${1}" ]] || [[ "${_value}"  = "" ]]; then
            [[ "${debug}" = true ]] && echo ; _pseudoecho "The variable name ${_variable} is empty."
        elif [[ ! "${_value}" = "true" ]] && [[ ! "${_value}" = "false" ]]; then
            [[ "${debug}" = true ]] && echo ; _pseudoecho "The variable name ${_variable} is not of bool type (${_variable} = ${_value})"
        elif [[ "${debug}" = true ]]; then
            echo -e " ${_value}"
        fi
    done
}

function _run_cleansh() {
    # Separationg Specials
    umount_specials

    # Separating airootfs
    umount -vdl "${airootfs_dir}.img" || true

    sh "$([[ "${bash_debug}" = true ]] && echo -n "-x" || echo -n "+x")" "${tools_dir}/clean.sh" -o -w "$(realpath "${build_dir}")" "$([[ "${debug}" = true ]] && printf "%s" "-d")" "$([[ "${noconfirm}" = true ]] && printf "%s" "-n")" "$([[ "${nocolor}" = true ]] && printf "%s" "--nocolor")"

    # remove old files
    remove "${airootfs_dir}" "${airootfs_dir}.img" && sleep 4

    # remove compile cache
    if [[ -d "/tmp/.cache" ]]; then
        _nsudo rm -rf /tmp/.cache
    fi
}

# Check the build environment and create a directory.
function prepare_env() {
    _pseudoecho "Checking dependencies ..."
    local _pkg
    for _pkg in "${dependence[@]}"; do
        eval which "${_pkg}" "$( [[ "${debug}" = false ]] && echo "> /dev/null")" || false
    done

    # Load loop kernel component
    if [[ "${noloopmod}" = false ]]; then
        [[ ! -d "/usr/lib/modules/$(uname -r)" ]] && _pseudoecho "The currently running kernel component could not be found.\nProbably the system kernel has been updated.\nReboot your system to run the latest kernel."
        lsmod | getclm 1 | grep -qx "loop" || modprobe loop
    fi

    # Check work dir
    if [[ "${normwork}" = false ]]; then
        _pseudoecho "Deleting the contents of ${build_dir}..."
        _run_cleansh
    fi

    # Set gpg key
    if [[ -n "${gpg_key}" ]]; then
        gpg --batch --output "${work_dir}/pubkey.gpg" --export "${gpg_key}"
        exec {ARCHISO_GNUPG_FD}<>"${build_dir}/pubkey.gpg"
        export ARCHISO_GNUPG_FD
    fi

    # 強制終了時に作業ディレクトリを削除する
    local _trap_remove_work
    _trap_remove_work() {
        local status="${?}"
        [[ "${normwork}" = false ]] && echo && _run_cleansh
        exit "${status}"
    }
    trap '_trap_remove_work' HUP INT QUIT TERM

    return 0
}

# Error message
function error_exit_trap() { local _exit="${?}" _line="${1}" && shift 1
    _pseudoecho "An exception error occurred in the function"
    _pseudoecho "Exit Code: ${_exit}\nLine: ${_line}\nArgument: ${ARGUMENT[*]}"
    exit "${_exit}"
}

# Show settings.
function show_settings() {
    _pseudoecho "Language is ${locale_fullname}."
    _pseudoecho "Use the ${kernel} kernel."
    _pseudoecho "Live username is ${username}."
    _pseudoecho "Live user password is ${password}."
    _pseudoecho "Use the ${channel_name%.add} channel."
    _pseudoecho "Build with architecture ${arch}."
    (( "${#additional_exclude_pkg[@]}" != 0 )) && _pseudoecho "Excluded packages: ${additional_exclude_pkg[*]}"
    if [[ "${noconfirm}" = false ]]; then
        printf "\Ctrl + C if exit."
        sleep 4
    fi
    trap HUP INT QUIT TERM
    trap 'umount_trap' HUP INT QUIT TERM
    trap 'error_exit_trap $LINENO' ERR

    return 0
}


# Preparation for build
function prepare_build() {
    # Debug mode
    [[ "${bash_debug}" = true ]] && set -x -v

    # Load configs
    load_config "${channel_dir}/config.any" "${channel_dir}/config.${arch}"

    # Additional components
    components+=("${additional_components[@]}")

    # Legacy mode
    if [[ "$(sh "${tools_dir}/channel.sh" --version "${archiso_version}" ver "${channel_name}")" = "3.0" ]]; then
        _pseudoecho "The component cannot be used anymore incompatible."
        sleep 3
        exit 1
    fi

    # Load presets
    local _components=() component_check
    for_component '[[ -f "${preset_dir}/{}" ]] && readarray -t -O "${#_components[@]}" _components < <(grep -h -v ^'#' "${preset_dir}/{}") || _components+=("{}")'
    components=("${_components[@]}")
    unset _components

    # Ignore components
    local _m
    for _m in "${exclude_components[@]}"; do
        readarray -t components < <(printf "%s\n" "${components[@]}" | grep -xv "${_m}")
    done

    # Check components
    component_check() {
        _pseudoecho -n "Checking ${1} component ... "
        sh "${tools_dir}/component.sh" check "${1}" || _pseudoecho "component ${1} is not available." && _pseudoecho "Load ${component_dir}/${1}"
    }
    readarray -t components < <(printf "%s\n" "${components[@]}" | awk '!a[$0]++')
    for_component "component_check {}"

    # Load components
    for_component load_config "${component_dir}/{}/config.any" "${component_dir}/{}/config.${arch}"
    _pseudoecho "Loaded components: ${components[*]}"
    ! printf "%s\n" "${components[@]}" | grep -x "base" >/dev/null 2>&1 && _pseudoecho "The base component is not loaded."
    ! printf "%s\n" "${components[@]}" | grep -x "main" >/dev/null 2>&1 && _pseudoecho "The main component is not loaded." 1

    # Set kernel
    [[ "${customized_kernel}" = false ]] && kernel="${defaultkernel}"

    # Parse files
    eval "$(sh "${tools_dir}/locale.sh" -s -a "${arch}" get "${locale_name}")"
    eval "$(sh "${tools_dir}/kernel.sh" -s -c "${channel_name}" -a "${arch}" get "${kernel}")"

    # Set username and password
    [[ "${customized_username}" = false ]] && username="${defaultusername}"
    [[ "${customized_password}" = false ]] && password="${defaultpassword}"

    # Generate tar file name
    tar_ext=""
    case "${tar_comp}" in
        "gzip" ) tar_ext="gz"                        ;;
        "zstd" ) tar_ext="zst"                       ;;
        "xz" | "lzma" | "lzo" | "lz4" ) tar_ext="${tar_comp}" ;;
    esac

    if [[ "${build_mode}" = "erofs" ]]; then
         _pseudoecho "Archiving iso with EROfs."
    else
         _pseudoecho "Archiving iso with squashfs."
    fi

    # Generate iso file name
    local _channel_name="${channel_name%.add}-${locale_version}"
    iso_filename="${iso_name%.img}-${_channel_name}-${iso_version}-${arch}.img"
    tar_filename="${iso_filename%.img}.tar.${tar_ext}"
    [[ "${nochname}" = true ]] && iso_filename="${iso_name%.img}-${iso_version}-${arch}.img"
    _pseudoecho "Iso filename is ${iso_filename}"

    # check bool
    check_bool cleaning noconfirm nodepend customized_username customized_password noloopmod nochname tarball noiso noaur norescue_entry debug bash_debug nocolor msgdebug nosigcheck

    # Check architecture for each channel
    local _exit=0
    sh "${tools_dir}/channel.sh" --version "${archiso_version}" -a "${arch}" -n -b check "${channel_name}" || _exit="${?}"
    ( (( "${_exit}" != 0 )) && (( "${_exit}" != 1 )) ) && _pseudoecho "${channel_name} channel does not support current architecture (${arch})."

    # Run with tee
    if [[ ! "${logging}" = false ]]; then
        [[ "${customized_logpath}" = false ]] && logging="${out_dir}/${iso_filename%.iso}.log"
        mkdir -p "$(dirname "${logging}")" && touch "${logging}"
        _pseudoecho "[_isudo] Re-run 'sudo -u#0 -g#0 ${0} ${ARGUMENT[*]} --nodepend --nolog --nocolor --rerun 2>&1 | tee ${logging}'"
        if [[ -f /usr/bin/systemd ]] ; then
            _isudo systemctl disable systemd-oom.service
            _isudo systemctl disable systemd-oomd.service
            _isudo systemctl mask systemd-oom.service
            _isudo systemctl mask systemd-oomd.service
            _isudo systemctl unmask systemd-oom.service
            _isudo systemctl unmask systemd-oomd.service
        fi
        _isudo "${0}" "${ARGUMENT[@]}" --nolog --nocolor --nodepend --rerun 2>&1 | tee "${logging}"
        exit "${PIPESTATUS[0]}"
    fi

    # Set argument of pkglist.sh
    pkglist_args=("-a" "${arch}" "-k" "${kernel}" "-c" "${channel_dir}" "-l" "${locale_name}" --line)
    [[ "${debug}"                    = true ]] && pkglist_args+=("-d")
    [[ "${memtest86}"                = true ]] && pkglist_args+=("-m")
    [[ "${nocolor}"                  = true ]] && pkglist_args+=("--nocolor")
    (( "${#additional_exclude_pkg[@]}" >= 1 )) && pkglist_args+=("-e" "${additional_exclude_pkg[*]}")
    pkglist_args+=("${components[@]}")

    # For debugs
    # Set argument of builduser.sh (cf. aur.sh and pkgbuild.sh)
    if [[ "${bash_debug}"   = true ]]; then
        makepkg_script_args+=("-x")
    fi
    if [[ "${pacman_debug}" = true ]]; then
        pacman_args+=("--debug")
        makepkg_script_args+=("-c")
    fi

    return 0
}


# Setup custom pacman.conf with current cache directories.
function make_pacman_conf() {
    # Pacman configuration file used only when building
    # If there is pacman.conf for each channel, use that for building
    local _pacman_conf _pacman_conf_list=("${script_path}/pacman-${arch}.conf" "${channel_dir}/pacman-${arch}.conf" "${script_path}/system/pacman-${arch}.conf")
    for _pacman_conf in "${_pacman_conf_list[@]}"; do
        if [[ -f "${_pacman_conf}" ]]; then
            build_pacman_conf="${_pacman_conf}"
            break
        fi
    done

    _pseudoecho "Use ${build_pacman_conf}"
    sed "s|^#?\\s*CacheDir.+|CacheDir     = ${cache_dir}|g" "${build_pacman_conf}" > "${build_dir}/pacman.conf"

    [[ "${nosigcheck}" = true ]] && sed -ri "s|^s*SigLevel.+|SigLevel = Never|g" "${build_pacman_conf}"

    [[ -n "$(find "${cache_dir}" -mindepth 1 -maxdepth 1 -name '*.pkg.tar.*' 2> /dev/null)" ]] && _pseudoecho "Use cached package files in ${cache_dir}"

    # Share any architecture packages
    #while read -r _pkg; do
    #    if [[ ! -f "${cache_dir}/$(basename "${_pkg}")" ]]; then
    #        ln -s "${_pkg}" "${cache_dir}"
    #    fi
    #done < <(find "${cache_dir}/../" -type d -name "$(basename "${cache_dir}")" -prune -o -type f -name "*-any.pkg.tar.*" -printf "%p\n")

    return 0
}

# Base installation (airootfs)
function make_basefs() {
    _pseudoecho "Creating filesystem..."

    ## There were not support in old;
    ## -O '^large_file,^dir_index,^filetype,^uninit_bg

    dd if=/dev/zero of="${airootfs_dir}.img" bs=1073741824 count=0 seek=13
    mkfs.ext4 -T news -O '^resize_inode,^sparse_super' -E 'lazy_itable_init=1,root_owner=0:0' -m 0 -F -U clear "${airootfs_dir}.img"
    tune2fs -c 0 -i 0 "${airootfs_dir}.img"

    dd if=/dev/zero of="${tmpfs_dir}.img" bs=1073741824 count=0 seek=12
    mkfs.ext4 -T news -O '^resize_inode,^sparse_super' -E 'lazy_itable_init=1,root_owner=0:0' -m 0 -F -U clear "${tmpfs_dir}.img"
    tune2fs -c 0 -i 0 "${tmpfs_dir}.img"

    _pseudoecho "Done!"

    _pseudoecho "Mounting ${airootfs_dir}.img on ${airootfs_dir}"
    mount_airootfs

    _pseudoecho "Done!"

    return 0
}

# Additional packages (airootfs)
function make_packages_repo() {
    _pseudoecho "pkglist.sh ${pkglist_args[*]}"
    readarray -t _pkglist_install < <("${tools_dir}/pkglist.sh" "${pkglist_args[@]}")

    # Package check
    if [[ "${legacy_mode}" = true ]]; then
        readarray -t _pkglist < <("${tools_dir}/pkglist.sh" "${pkglist_args[@]}")
        readarray -t repopkgs < <(pacman-conf -c "${build_pacman_conf}" -l | xargs -I{} pacman -Sql --config "${build_pacman_conf}" --color=never {} && pacman -Sg)
        local _pkg
        for _pkg in "${_pkglist[@]}"; do
            _pseudoecho "Checking ${_pkg}..."
            if printf "%s\n" "${repopkgs[@]}" | grep -qx "${_pkg}"; then
                _pkglist_install+=("${_pkg}")
            else
                _pseudoecho "${_pkg} was not found. Install it from AUR"
                norepopkg+=("${_pkg}")
            fi
        done
    fi

    # Create a list of packages to be finally installed as packages.list directly under the working directory.
    echo -e "# The list of packages that is installed in live cd.\n#\n" > "${build_dir}/packages.list"
    printf "%s\n" "${_pkglist_install[@]}" >> "${build_dir}/packages.list"

    # Install packages on airootfs
    _pacstrap "${_pkglist_install[@]}"

    if [[ "${gpg_key}" ]]; then
      gpg --export "${gpg_key}" >"${build_dir}/gpgkey"
      exec 17<>"${build_dir}/gpgkey"
    fi

    return 0
}

function make_packages_special() {
    # Overwrite (first) for optimise pacman and their GPG (Compability of arch-chroot)
    local _xairootfs _xairootfs_list=()

    for_component '_xairootfs_list+=("${component_dir}/{}/airootfs.any" "${component_dir}/{}/airootfs.${arch}")'
    _xairootfs_list+=("${channel_dir}/airootfs.any" "${channel_dir}/airootfs.${arch}")

    for _xairootfs in "${_xairootfs_list[@]}";do
        if [[ -d "${_xairootfs}" ]]; then
            _pseudoecho "Copying airootfs ${_xairootfs} ..."
            _dicp "${_xairootfs}/*" "${airootfs_dir}"
        fi
    done

    if [[ "${noaur}" = false ]]; then
        readarray -t _pkglist_aur < <("${tools_dir}/pkglist.sh" --aur "${pkglist_args[@]}")
        _pkglist_aur=("${_pkglist_aur[@]}" "${norepopkg[@]}")
        builduser_script_args=("-a" "${aur_helper_command}" \
            "-e" "${aur_helper_package}" \
            "-d" "$(printf "%s\n" "${aur_helper_depends[@]}" | tr "\n" ",")" \
            "-p" "$(printf "%s\n" "${_pkglist_aur[@]}" | tr "\n" ",")" \
            "-u" "${username}" \
            "${makepkg_script_args[@]}" -- "${aur_helper_args[@]}")

        # Create a list of packages to be finally installed as packages.list directly under the working directory.
        echo -e "\n# AUR packages.\n#\n" >> "${build_dir}/packages.list"
        printf "%s\n" "${_pkglist_aur[@]}" >> "${build_dir}/packages.list"

        # prepare for aur helper
        _dicp "${script_path}/system/builduser.sh" "${airootfs_dir}/root/builduser.sh"

        if [[ "${nopkgbuild}" = false ]]; then
            # Get PKGBUILD List
            local _pkgbuild_dirs=("${channel_dir}/pkgbuild.any" "${channel_dir}/pkgbuild.${arch}")
            for_component '_pkgbuild_dirs+=("${component_dir}/{}/pkgbuild.any" "${component_dir}/{}/pkgbuild.${arch}")'

            # Copy PKGBUILD to work
            mkdir -m 755 -p "${airootfs_dir}/AURHelper"
            for _dir in $(find "${_pkgbuild_dirs[@]}" -type f -name "PKGBUILD" -print0 2>/dev/null | xargs -0 -I{} realpath {} | xargs -I{} dirname {}); do
                _pseudoecho "Find $(basename "${_dir}")"
                _dicp "${_dir}" "${airootfs_dir}/AURHelper"
            done
        fi

        # Run builduser script
        _run_with_pacmanconf _chroot_run "/root/builduser.sh" "${builduser_script_args[@]}"
        # Remove script
        remove "${airootfs_dir}/root/builduser.sh"
    fi
    return 0
}

# Customize installation (airootfs)
function make_customize_airootfs() {
    # Overwrite airootfs with customize_airootfs.
    local _airootfs _airootfs_script_options _script _script_list _airootfs_list=() _main_script

    for_component '_airootfs_list+=("${component_dir}/{}/airootfs.any" "${component_dir}/{}/airootfs.${arch}")'
    _airootfs_list+=("${channel_dir}/airootfs.any" "${channel_dir}/airootfs.${arch}")

    for _airootfs in "${_airootfs_list[@]}";do
        if [[ -d "${_airootfs}" ]]; then
            _pseudoecho "Copying airootfs ${_airootfs} ..."
            _dicp "${_airootfs}/" "${airootfs_dir}"
        fi
    done

    # Replace /etc/mkinitcpio.conf
    install -m 644 -- "${script_path}/mkinitcpio/mkinitcpio.conf" "${airootfs_dir}/etc/mkinitcpio.conf"

    # /root permission
    # https://listman.redhat.com/archives/linux-audit/2012-January/msg00029.html
    # https://github.com/archlinux/archiso/commit/d39e2ba41bf556674501062742190c29ee11cd59

    #644
    find "${airootfs_dir}/etc/pam.d/" -type f || xargs -n1 sudo -u#0 -g#0 fakeroot chmod 644
    find "${airootfs_dir}/etc/ssh/" -type f || xargs -n1 sudo -u#0 -g#0 fakeroot chmod 644
    find "${airootfs_dir}/etc/sudoers.d" -type f || xargs -n1 sudo -u#0 -g#0 fakeroot chmod 644
    chmod 644 "${airootfs_dir}/etc/sudoers"    

    # customize_airootfs options
    # -d                        : Enable debug mode.
    # -g <locale_gen_name>      : Set locale-gen.
    # -k <kernel config line>   : Set kernel name.
    # -o <os name>              : Set os name.
    # -p <password>             : Set password.
    # -s <shell>                : Set user shell.
    # -u <username>             : Set live user name.
    # -x                        : Enable bash debug mode.
    # -z <locale_time>          : Set the time zone.
    # -l <locale_name>          : Set language.
    #
    # -j is obsolete cannot be used.
    # -r is obsolete due to the removal of rebuild.
    # -k from passing kernel name to passing kernel configuration.

    # Generate options of customize_airootfs.sh.
    _airootfs_script_options=(-p "${password}" -k "${kernel} ${kernel_filename} ${kernel_mkinitcpio_profile}" -u "${username}" -o "${os_name}" -s "${usershell}" -a "${arch}" -g "${locale_gen_name}" -l "${locale_name}" -z "${locale_time}")
    [[ "${debug}" = true       ]] && _airootfs_script_options+=("-d")
    [[ "${bash_debug}" = true  ]] && _airootfs_script_options+=("-x")
  
    _main_script="/root/customize_airootfs.sh"

    _script_list=(
        "${airootfs_dir}/root/customize_airootfs_${channel_name}.sh"
        "${airootfs_dir}/root/customize_airootfs_${channel_name%.add}.sh"
    )

    for_component '_script_list+=("${airootfs_dir}/root/customize_airootfs_{}.sh")'

    # Create script
    for _script in "${_script_list[@]}"; do
        if [[ -f "${_script}" ]]; then
            (echo -e "\n#--$(basename "${_script}")--#\n" && cat "${_script}")  >> "${airootfs_dir}/${_main_script}"
            remove "${_script}"
        else
            _pseudoecho "${_script} was not found."
        fi
    done

    _nsudo chmod -Rf 755 "${airootfs_dir}/${_main_script}"
    _dicp "${airootfs_dir}/${_main_script}" "${build_dir}/$(basename "${_main_script}")"
    _chroot_run "${_main_script}" "${_airootfs_script_options[@]}"
    remove "${airootfs_dir}/${_main_script}"

    return 0
}

# Copy mkinitcpio archiso hooks and build initramfs (airootfs)
function make_setup_mkinitcpio() {
    local _hook
    mkdir -m 755 -p "${airootfs_dir}/etc/initcpio/hooks" "${airootfs_dir}/etc/initcpio/install"

    for _hook in "archiso_loop_mnt" "archiso" ; do
        install -m 644 -- "${script_path}/system/initcpio/hooks/${_hook}" "${airootfs_dir}/etc/initcpio/hooks"
        install -m 644 -- "${script_path}/system/initcpio/install/${_hook}" "${airootfs_dir}/etc/initcpio/install"
    done
    install -m 644 -- "${script_path}/mkinitcpio/mkinitcpio-archiso.conf" "${airootfs_dir}/etc/mkinitcpio-archiso.conf"

    _chroot_run mkinitcpio -c "/etc/mkinitcpio-archiso.conf" -k "/boot/${kernel_filename}" -g "/boot/archiso.img"

    # Cleanup
    _cleanup_airootfs

    # correctly regenerate vmlinuz
    _chroot_run mkinitcpio -P

    return 0
}


# Compress airootfs with tar.gz
function make_compresstgz() {
    # Run script
    [[ -f "${airootfs_dir}/root/optimize_for_tarball.sh" ]] && _chroot_run "/root/optimize_for_tarball.sh" -u "${username}"
    remove "${airootfs_dir}/root/optimize_for_tarball.sh"

    # Separationg Specials
    umount_specials

    # make
    tar_comp_opt+=("--${tar_comp}")
    mkdir -m 755 -p "${out_dir}"
    _pseudoecho "Tarball filename is ${tar_filename}"
    _pseudoecho "Creating tarball..."
    cd -- "${airootfs_dir}"
    _pseudoecho "Run tar cvpf \"${out_dir}/${tar_filename}\" ${tar_comp_opt[*]} ./*"
    _nsudo tar cvpf "${out_dir}/${tar_filename}" "${tar_comp_opt[@]}" ./*
    cd -- "${OLDPWD}"

    # checksum
    _mkchecksum "${out_dir}/${tar_filename}"
    _pseudoecho "Done! | $(ls -sh "${out_dir}/${tar_filename}")"

    # Sign with gpg
    if [[ -v gpg_key ]] && (( "${#gpg_key}" != 0 )); then
        _pseudoecho "Creating signature file ($gpg_key) ..."
        cd -- "${out_dir}"
        gpg --detach-sign --default-key "${gpg_key}" "${out_dir}/${tar_filename}"
        cd -- "${OLDPWD}"
        _pseudoecho "Done!"
    fi

    _pseudoecho "The password for the live user and root is ${password}."
}

# Build airootfs filesystem image
function make_prepare() {
    if [[ -f "${airootfs_dir}/root/optimize_for_tarball.sh" ]]; then
        remove "${airootfs_dir}/root/optimize_for_tarball.sh"
    fi

    mkdir -m 755 -p "${isofs_dir}/${install_dir}"

    # Create packages list
    _pseudoecho "Creating a list of installed packages on live-enviroment..."
    _nsudo pacman "-SyQ" "--config=${build_dir}/pacman.conf" "--sysroot=${airootfs_dir}" | tee "${isofs_dir}/${install_dir}/pkglist.${arch}.txt" "${build_dir}/packages-full.list" > /dev/null
}

# Add files to the root of isofs
function make_overisofs() {
    local _over_isofs_list _isofs
    _over_isofs_list=("${channel_dir}/over_isofs.any""${channel_dir}/over_isofs.${arch}")
    for_component '_over_isofs_list+=("${component_dir}/{}/over_isofs.any" "${component_dir}/{}/over_isofs.${arch}")'
    for _isofs in "${_over_isofs_list[@]}"; do
        [[ -d "${_isofs}" ]] && [[ -n "$(find "${_isofs}" -mindepth 1 -maxdepth 2)" ]] && _Normcp "${_isofs}"/* "${isofs_dir}"
    done

    return 0
}

# Prepare /${install_dir}/boot/syslinux
function make_syslinux() {

    # copy all syslinux config to work dir
    mkdir -m 755 -p "${isofs_dir}/syslinux/"
    _dicp "${script_path}/syslinux/"* "${isofs_dir}/syslinux/"

    # Replace the SYSLINUX configuration file
    find "${isofs_dir}/syslinux/" -type f | grep '\.\(cfg\)' | xargs -n1 sed -ri "s|%ARCHISO_LABEL%|${iso_label}|g; \
             s|%OS_NAME%|${os_name}|g; \
             s|%KERNEL_FILENAME%|${kernel_filename}|g; \
             s|%ARCH%|${arch}|g; \
             s|%INSTALL_DIR%|${install_dir}|g"

    # Set syslinux wallpaper
    install -m 644 -- "${script_path}/syslinux/splash.png" "${isofs_dir}/syslinux/"
    [[ -f "${channel_dir}/splash.png" ]] && install -m 644 -- "${channel_dir}/splash.png" "${isofs_dir}/syslinux"

    # remove config
    local _remove_config
    function _remove_config() {
        remove "${isofs_dir}/syslinux/${1}"
        sed -ri "s|$(grep "${1}" "${isofs_dir}/syslinux/archiso_sys_load.cfg")||g" "${isofs_dir}/syslinux/archiso_sys_load.cfg"
    }

    [[ "${norescue_entry}" = true  ]] && _remove_config archiso_sys_rescue.cfg
    [[ "${memtest86}"      = false ]] && _remove_config memtest86.cfg

    # copy files
    install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/"*.c32 "${isofs_dir}/syslinux/"
    install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/lpxelinux.0" "${isofs_dir}/syslinux/"
    install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/memdisk" "${isofs_dir}/syslinux/"

    #install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/boot.cat" "${isofs_dir}/syslinux/"
    install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/isolinux.bin" "${isofs_dir}/syslinux/"
    install -m 644 -- "${airootfs_dir}/usr/lib/syslinux/bios/isohdpfx.bin" "${isofs_dir}/syslinux/"

    if [[ -e "${isofs_dir}/syslinux/hdt.c32" ]]; then
        install -d -m 755 -- "${isofs_dir}/syslinux/hdt"
        if [[ -e "${airootfs_dir}/usr/share/hwdata/pci.ids" ]]; then
            gzip -c -9 "${airootfs_dir}/usr/share/hwdata/pci.ids" > "${isofs_dir}/syslinux/hdt/pciids.gz"
        fi
        find "${airootfs_dir}/usr/lib/modules" -name 'modules.alias' -print -exec gzip -c -9 '{}' ';' -quit > "${isofs_dir}/syslinux/hdt/modalias.gz"
    fi

    return 0
}

# Prepare kernel/initramfs ${install_dir}/boot/
function make_boot() {
    mkdir -m 755 -p "${isofs_dir}/${install_dir}/boot/${arch}"
    install -m 644 --  "${airootfs_dir}/boot/archiso.img" "${isofs_dir}/${install_dir}/boot/${arch}/archiso.img"

    # kernel
    install -m 644 --  "${airootfs_dir}/boot/${kernel_filename}" "${isofs_dir}/${install_dir}/boot/${arch}/${kernel_filename}"

    if [[ -e "${airootfs_dir}/boot/memtest86+/memtest.bin" ]]; then
        install -m 644 -- "${airootfs_dir}/boot/memtest86+/memtest.bin" "${isofs_dir}/${install_dir}/boot/memtest"
        ##install -d -m 644 -- "${isofs_dir}/${install_dir}/boot/licenses/memtest86+/"
        ##install -m 644 -- "${airootfs_dir}/usr/share/licenses/common/GPL2/license.txt" "${isofs_dir}/${install_dir}/boot/licenses/memtest86+/"
    fi

    local _ucode_image
    _pseudoecho "Preparing microcode for the ISO 9660 file system..."

    for _ucode_image in {intel-uc.img,intel-ucode.img,amd-uc.img,amd-ucode.img,early_ucode.cpio,microcode.cpio}; do
        if [[ -e "${airootfs_dir}/boot/${_ucode_image}" ]]; then
            _pseudoecho "Installimg ${_ucode_image} ..."
            install -m 644 -- "${airootfs_dir}/boot/${_ucode_image}" "${isofs_dir}/${install_dir}/boot/"
            if [[ -e "${airootfs_dir}/usr/share/licenses/${_ucode_image%.*}/" ]]; then
                install -d -m 644 -- "${isofs_dir}/${install_dir}/boot/licenses/${_ucode_image%.*}/"
                install -m 644 -- "${airootfs_dir}/usr/share/licenses/${_ucode_image%.*}/"* "${isofs_dir}/${install_dir}/boot/licenses/${_ucode_image%.*}/"
            fi
        fi
    done
    _pseudoecho "Done!"

    return 0
}

# Prepare /EFI
function make_efi() {
    local _bootfile _efi_config_list=() _efi_config

    _bootfile="$(basename "$(ls "${airootfs_dir}/usr/lib/systemd/boot/efi/systemd-boot"*".efi" )")"

    install -d -m 755 -- "${isofs_dir}/EFI/boot"
    install -m 644 -- "${airootfs_dir}/usr/lib/systemd/boot/efi/${_bootfile}" "${isofs_dir}/EFI/boot/${_bootfile#systemd-}"

    install -d -m 755 -- "${isofs_dir}/loader/entries"
    sed -i "s|%ARCH%|${arch}|g" "${script_path}/bootleg/loader.conf" > "${isofs_dir}/loader/loader.conf"

    readarray -t _efi_config_list < <(find "${script_path}/bootleg/" -mindepth 1 -maxdepth 1 -type f -name "*-archiso-BIOS*.conf" -printf "%f\n" | grep -v "rescue")
    [[ "${norescue_entry}" = false ]] && readarray -t _efi_config_list < <(find "${script_path}/bootleg/" -mindepth 1 -maxdepth 1 -type f  -name "*-archiso-BIOS*.conf" -printf "%f\n")

    for _efi_config in "${_efi_config_list[@]}"; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g; \
            s|%OS_NAME%|${os_name}|g; \
            s|%KERNEL_FILENAME%|${kernel_filename}|g; \
            s|%ARCH%|${arch}|g; \
            s|%INSTALL_DIR%|${install_dir}|g" \
        "${script_path}/bootleg/${_efi_config}" > "${isofs_dir}/loader/entries/$(basename "${_efi_config}" | sed "s|BIOS|${arch}|g")"
    done

    # edk2-shell based UEFI shell
    local _efi_shell_arch
    if [[ -d "${airootfs_dir}/usr/share/edk2-shell" ]]; then
        for _efi_shell_arch in $(find "${airootfs_dir}/usr/share/edk2-shell" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 -I{} basename {}); do
            if [[ -f "${airootfs_dir}/usr/share/edk2-shell/${_efi_shell_arch}/Shell_Full.efi" ]]; then
                _BNcp "${airootfs_dir}/usr/share/edk2-shell/${_efi_shell_arch}/Shell_Full.efi" "${isofs_dir}/EFI/shell_${_efi_shell_arch}.efi"
            elif [[ -f "${airootfs_dir}/usr/share/edk2-shell/${_efi_shell_arch}/Shell.efi" ]]; then
                _BNcp "${airootfs_dir}/usr/share/edk2-shell/${_efi_shell_arch}/Shell.efi" "${isofs_dir}/EFI/shell_${_efi_shell_arch}.efi"
            else
                continue
            fi
            echo -e "title  UEFI Shell ${_efi_shell_arch}\nefi    /EFI/shell_${_efi_shell_arch}.efi" > "${isofs_dir}/loader/entries/uefi-shell-${_efi_shell_arch}.conf"
        done
    fi

    return 0
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
function make_efiboot() {
    dd if=/dev/zero of="${build_dir}/efiboot.img" bs=1024 count=200000
    mkfs.vfat -F 32 -S 512 -s 1 -n ARCHISO_EFI "${build_dir}/efiboot.img"

    mkdir -m 755 -p "${build_dir}/efiboot"
    mount "${build_dir}/efiboot.img" "${build_dir}/efiboot"

    mkdir -m 755 -p "${build_dir}/efiboot/EFI/boot/${arch}" "${build_dir}/efiboot/EFI/boot" "${build_dir}/efiboot/loader/entries"
    _BNcp "${isofs_dir}/${install_dir}/boot/${arch}/${kernel_filename}" "${build_dir}/efiboot/EFI/boot/${arch}/${kernel_filename}"
    _BNcp "${isofs_dir}/${install_dir}/boot/${arch}/archiso.img" "${build_dir}/efiboot/EFI/boot/${arch}/archiso.img"

    local _ucode_image _efi_config _bootfile
    for _ucode_image in "${airootfs_dir}/boot/"{intel-uc.img,intel-ucode.img,amd-uc.img,amd-ucode.img,early_ucode.cpio,microcode.cpio}; do
        [[ -e "${_ucode_image}" ]] && _BNcp "${_ucode_image}" "${build_dir}/efiboot/EFI/boot/"
    done

    _BNcp "${airootfs_dir}/usr/share/efitools/efi/HashTool.efi" "${build_dir}/efiboot/EFI/boot/"

    _bootfile="$(basename "$(ls "${airootfs_dir}/usr/lib/systemd/boot/efi/systemd-boot"*".efi" )")"
    _BNcp "${airootfs_dir}/usr/lib/systemd/boot/efi/${_bootfile}" "${build_dir}/efiboot/EFI/boot/${_bootfile#systemd-}"

    sed "s|%ARCH%|${arch}|g;" "${script_path}/bootleg/loader.conf" > "${build_dir}/efiboot/loader/loader.conf"

    find "${isofs_dir}/loader/entries/" -maxdepth 1 -mindepth 1 -name "uefi-shell*" -type f -printf "%p\0" | xargs -0 -I{} fakeroot sudo -S rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --chown=0:0 --chmod=D755,F644 {} "${build_dir}/efiboot/loader/entries/"

    readarray -t _efi_config_list < <(find "${script_path}/bootleg/" -mindepth 1 -maxdepth 1 -type f -name "*-archiso-EFI*.conf" -printf "%f\n" | grep -v "rescue")
    [[ "${norescue_entry}" = false ]] && readarray -t _efi_config_list < <(find "${script_path}/bootleg/" -mindepth 1 -maxdepth 1 -type f  -name "*-archiso-EFI*.conf" -printf "%f\n")

    for _efi_config in "${_efi_config_list[@]}"; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
            s|%OS_NAME%|${os_name}|g;
            s|%KERNEL_FILENAME%|${kernel_filename}|g;
            s|%ARCH%|${arch}|g;
            s|%INSTALL_DIR%|${install_dir}|g" \
        "${script_path}/bootleg/${_efi_config}" > "${build_dir}/efiboot/loader/entries/$(basename "${_efi_config}" | sed "s|EFI|${arch}|g")"
    done

    find "${isofs_dir}/EFI" -maxdepth 1 -mindepth 1 -name "shell*.efi" -printf "%p\0" | xargs -0 -I{} fakeroot sudo -S rsync -zvAHXal --info=progress2 --devices --specials --copy-links --no-implied-dirs --chown=0:0 --chmod=D755,F644 {} "${build_dir}/efiboot/EFI/"
    umount -vdl "${build_dir}/efiboot"

    return 0
}


# Compress tarball
function make_tarball() {
    # Separationg Specials
    umount_specials

    # Create initrd tarball
    tar_comp_opt+=("--${tar_comp}")
    mkdir -m 755 -p "${out_dir}"
    _pseudoecho "Tarball filename is ${tar_filename}"
    _pseudoecho "Creating tarball..."
    cd -- "${airootfs_dir}"
    _pseudoecho "Run tar cvpf \"${out_dir}/${tar_filename}\" ${tar_comp_opt[*]} ./*"
    _nsudo tar cvpf "${out_dir}/${tar_filename}" "${tar_comp_opt[@]}" ./*
    cd -- "${OLDPWD}"

    # checksum
    _mkchecksum "${out_dir}/${tar_filename}"
    _pseudoecho "Done! | $(ls -sh "${out_dir}/${tar_filename}")"

    # Sign with gpg
    if [[ -v gpg_key ]] && (( "${#gpg_key}" != 0 )); then
        _pseudoecho "Creating signature file ($gpg_key) ..."
        cd -- "${isofs_dir}/${install_dir}/${arch}"
        gpg --detach-sign --default-key "${gpg_key}" "${out_dir}/${tar_filename}"
        cd -- "${OLDPWD}"
        _pseudoecho "Done!"
    fi
}

function make_archiso_erofs() {
    # Separationg Specials
    umount_specials

    # Create EROfs
    mkdir -m 755 -p "${isofs_dir}/${install_dir}/${arch}/"
    _pseudoecho "Creating EROfs image, this may take some time..."
    mkfs.erofs "${build_dir}/iso/${install_dir}/${arch}/airootfs.erofs" "${airootfs_dir}/" -zlz4

    # Create checksum
    _pseudoecho "Creating checksum file for self-test..."
    echo "$(sha512sum "${isofs_dir}/${install_dir}/${arch}/airootfs.erofs" | getclm 1) airootfs.erofs" > "${isofs_dir}/${install_dir}/${arch}/airootfs.sha512"
    _pseudoecho "Done!"

    # Sign with gpg
    if [[ -v gpg_key ]] && (( "${#gpg_key}" != 0 )); then
        _pseudoecho "Creating signature file ($gpg_key) ..."
        cd -- "${isofs_dir}/${install_dir}/${arch}"
        gpg --detach-sign --default-key "${gpg_key}" "airootfs.erofs"
        cd -- "${OLDPWD}"
        _pseudoecho "Done!"
    fi
}

function make_archiso_squashfs() {
    # Separationg Specials
    umount_specials

    # Create squashfs
    # Please DO NOT change https://gihyo.jp/lifestyle/serial/01/ganshiki-soushi/0012
    mkdir -m 755 -p "${isofs_dir}/${install_dir}/${arch}/"
    _pseudoecho "Creating squashfs image, this may take some time..."
    mksquashfs "${airootfs_dir}/" "${build_dir}/iso/${install_dir}/${arch}/airootfs.sfs" -b 4096 -comp lzo -noappend

    # Create checksum
    _pseudoecho "Creating checksum file for self-test..."
    echo "$(sha512sum "${isofs_dir}/${install_dir}/${arch}/airootfs.sfs" | getclm 1) airootfs.sfs" > "${isofs_dir}/${install_dir}/${arch}/airootfs.sha512"
    _pseudoecho "Done!"

    # Sign with gpg
    if [[ -v gpg_key ]] && (( "${#gpg_key}" != 0 )); then
        _pseudoecho "Creating signature file ($gpg_key) ..."
        cd -- "${isofs_dir}/${install_dir}/${arch}"
        gpg --detach-sign --default-key "${gpg_key}" "airootfs.sfs"
        cd -- "${OLDPWD}"
        _pseudoecho "Done!"
    fi
}

# Build ISO
function make_iso() {
    #--grub2-mbr "${build_dir}/boot" --mbr-force-bootable
                 # dd if="$orig" bs=1 count=446 of="$mbr"
    #0xef
    #-append_partition 1 0FC63DAF-8483-4772-8E79-3D69D8477DE4 "${isofs_dir}/"

    mkdir -m 755 -p "${out_dir}"
    _pseudoecho "Creating ISO image..."
    _nsudo xorriso -as mkisofs \
        -iso-level 3 \
            -full-iso9660-filenames \
            -joliet \
            -joliet-long \
        -rational-rock \
            -volid "${iso_label}" \
            -appid "${iso_application}" \
            -publisher "${iso_publisher}" \
            -preparer "prepared by archiso" \
        -eltorito-platform 0xEF \
            -eltorito-boot 'syslinux/isolinux.bin' \
                -partition_cyl_align on \
                    -partition_offset 0 \
                    -partition_hd_cyl 64 \
                    -partition_sec_hd 32 \
                    -partition_offset 16 \
                -no-emul-boot -boot-load-size 4 -boot-info-table \
                -isohybrid-mbr "${build_dir}/iso/syslinux/isohdpfx.bin" \
        -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "${build_dir}/efiboot.img" \
            -appended_part_as_gpt \
            -eltorito-alt-boot --efi-boot --interval:appended_partition_2:all:: \
                -no-emul-boot -boot-load-size 744 -boot-info-table \
                -isohybrid-gpt-basdat \
        -output "${out_dir}/${iso_filename}" \
        "${build_dir}/iso/"

    _mkchecksum "${out_dir}/${iso_filename}"
    _pseudoecho "Done! | $(ls -sh -- "${out_dir}/${iso_filename}")"

    _pseudoecho "The password for the live user and root is ${password}."
    return 0
}

# Parse options
ARGUMENT=("${DEFAULT_ARGUMENT[@]}" "${@}") OPTS=("a:" "c:" "d" "e" "g:" "h" "j" "k:" "l:" "m:" "o:" "p:" "r" "t:" "u:" "w:" "x") OPTL=("arch:" "comp-type:" "debug" "cleaning" "cleanup" "gpgkey:" "help" "lang:" "japanese" "kernel:" "mode:" "out:" "password:" "comp-opts:" "user:" "work:" "bash-debug" "nocolor" "noconfirm" "nodepend" "msgdebug" "noloopmod" "tarball" "noiso" "noaur" "nochkver" "channellist" "config:" "noefi" "nodebug" "nosigcheck" "normwork" "log" "logpath:" "nolog" "nopkgbuild" "pacman-debug" "confirm" "tar-type:" "tar-opts:" "add-component:" "rerun" "depend" "loopmod")
GETOPT=(-o "$(printf "%s," "${OPTS[@]}")" -l "$(printf "%s," "${OPTL[@]}")" -- "${ARGUMENT[@]}")
getopt -Q "${GETOPT[@]}" || exit 1 # 引数エラー判定
readarray -t OPT < <(getopt "${GETOPT[@]}") # 配列に代入

eval set -- "${OPT[@]}"
_pseudoecho "Argument: ${OPT[*]}"
unset OPT OPTS OPTL DEFAULT_ARGUMENT GETOPT

while true; do
    case "${1}" in
        -j | --japanese)
            _pseudoecho "This option is obsolete in archiso 3. To use Japanese, use \"-l ja\"."
            ;;
        -k | --kernel)
            customized_kernel=true
            kernel="${2}"
            shift 2
            ;;
        -m | --mode)
            IFS=" " read -r -a build_mode <<< "${2}"
            shift 2
            ;;
        -p | --password)
            customized_password=true
            password="${2}"
            shift 2
            ;;
        -u | --user)
            customized_username=true
            username="$(echo -n "${2}" | sed 's/ //g' | tr '[:upper:]' '[:lower:]')"
            shift 2
            ;;
        --nodebug)
            debug=false msgdebug=false bash_debug=false
            shift 1
            ;;
        --logpath)
            customized_logpath=true
            logging="${2}"
            shift 2
            ;;
        --tar-type)
            case "${2}" in
                "gzip" | "lzma" | "lzo" | "lz4" | "xz" | "zstd") tar_comp="${2}" ;;
                *) _pseudoecho "Invaild compressors '${2}'" '1' ;;
            esac
            shift 2
            ;;
        --tar-opts)
            IFS=" " read -r -a tar_comp_opt <<< "${2}"
            shift 2
            ;;
        --add-component)
            readarray -t -O "${#additional_components[@]}" additional_components < <(echo "${2}" | tr "," "\n")
            _pseudoecho "Added components: ${additional_components[*]}"
            shift 2
            ;;
        -g | --gpgkey               ) gpg_key="${2}"     && shift 2 ;;
        -h | --help                 ) _usage 0           && break   ;;
        -a | --arch                 ) arch="${2}"        && shift 2 ;;
        -d | --debug                ) debug=true         && shift 1 ;;
        -e | --cleaning | --cleanup ) cleaning=true      && shift 1 ;;
        -l | --lang                 ) locale_name="${2}" && shift 2 ;;
        -m | --mode                 ) buildmode="${2}"   && shift 2 ;;
        -o | --out                  ) out_dir="${2}"     && shift 2 ;;
        -r | --tarball              ) tarball=true       && shift 1 ;;
        -w | --work                 ) work_dir="${2}"    && shift 2 ;;
        -x | --bash-debug           ) bash_debug=true    && shift 1 ;;
        --noconfirm                 ) noconfirm=true     && shift 1 ;;
        --confirm                   ) noconfirm=false    && shift 1 ;;
        --nodepend                  ) nodepend=true      && shift 1 ;;
        --nocolor                   ) nocolor=true       && shift 1 ;;
        --msgdebug                  ) msgdebug=true      && shift 1 ;;
        --noloopmod                 ) noloopmod=true     && shift 1 ;;
        --noiso                     ) noiso=true         && shift 1 ;;
        --noaur                     ) noaur=true         && shift 1 ;;
        --nochkver                  ) nochkver=true      && shift 1 ;;
        --noefi                     ) noefi=true         && shift 1 ;;
        --channellist               ) show_channel_list  && exit  0 ;;
        --config                    ) source "${2}"      && shift 2 ;;
        --pacman-debug              ) pacman_debug=true  && shift 1 ;;
        --nosigcheck                ) nosigcheck=true    && shift 1 ;;
        --normwork                  ) normwork=true      && shift 1 ;;
        --log                       ) logging=true       && shift 1 ;;
        --nolog                     ) logging=false      && shift 1 ;;
        --nopkgbuild                ) nopkgbuild=true    && shift 1 ;;
        --rerun                     ) rerun=true         && shift 1 ;;
        --depend                    ) nodepend=false     && shift 1 ;;
        --loopmod                   ) noloopmod=false    && shift 1 ;;
        --                          ) shift 1            && break   ;;
        *)
            _pseudoecho "Argument exception error '${1}'"
            _pseudoecho "Please report this error to the developer." 1
            ;;
    esac
done

# Check root.
if (( ! "${EUID}" == 0 )); then
    _pseudoecho "[_esudo] This script must be run as root." >&2
    _pseudoecho "Re-run 'sudo -u#0 -g#0 ${0} ${ARGUMENT[*]}'"
    _esudo "${0}" "${ARGUMENT[@]}" --rerun
    exit "${?}"
fi

# Show config message
_pseudoecho "Use the default configuration file (${defaultconfig})."
[[ -f "${script_path}/custom.conf" ]] && _pseudoecho "The default settings have been overridden by custom.conf"

# Debug mode
[[ "${bash_debug}" = true ]] && set -x -v

# Check for a valid channel name
if [[ -n "${1+SET}" ]]; then
    case "$(sh "${tools_dir}/channel.sh" --version "${archiso_version}" -n check "${1}"; printf "%d" "${?}")" in
        "2")
            _pseudoecho "Invalid channel ${1}"
            ;;
        "1")
            channel_dir="${1}"
            channel_name="$(basename "${1%/}")"
            ;;
        "0")
            channel_dir="${script_path}/channels/${1}"
            channel_name="${1}"
            ;;
    esac
else
    channel_dir="${script_path}/channels/${channel_name}"
fi

# Set vars
build_dir="${work_dir}/build/${arch}" cache_dir="${work_dir}/cache/${arch}" airootfs_dir="${build_dir}/airootfs" tmpfs_dir="${build_dir}/override_tmpfs" isofs_dir="${build_dir}/iso" lockfile_dir="${build_dir}/lockfile" preset_dir="${script_path}/presets"

# Create dir
for _dir in build_dir cache_dir airootfs_dir isofs_dir lockfile_dir out_dir; do
    mkdir -m 755 -p "$(eval "echo \$${_dir}")"
    _pseudoecho "${_dir} is $(realpath "$(eval "echo \$${_dir}")")"
    eval "${_dir}=\"$(realpath "$(eval "echo \$${_dir}")")\""
done

# Set for special channels
if [[ -d "${channel_dir}.add" ]]; then
    channel_name="${1}"
    channel_dir="${channel_dir}.add"
elif [[ "${channel_name}" = "clean" ]]; then
   _run_cleansh
    exit 0
fi

# Check channel version
_pseudoecho "channel path is ${channel_dir}"
if [[ ! "$(sh "${tools_dir}/channel.sh" --version "${archiso_version}" ver "${channel_name}" | cut -d "." -f 1)" = "$(echo "${archiso_version}" | cut -d "." -f 1)" ]] && [[ "${nochkver}" = false ]]; then
    _pseudoecho "Configures running this moment seems old."
else
    _pseudoecho "Please check previous configures of them."
fi

prepare_env
prepare_build
show_settings

#-- stage 3
run_once make_pacman_conf
run_once make_basefs
run_once make_packages_repo
run_once make_packages_special

#-- stage 4
run_once make_customize_airootfs

#-- genkernel
run_once make_setup_mkinitcpio

#-- catalyst
if [[ "${noiso}" = true ]]; then
    run_once make_compresstgz
fi

if [[ "${noiso}" = false ]]; then
    run_once make_prepare
    run_once make_overisofs

        run_once make_syslinux
            run_once make_boot
            run_once make_efi
            run_once make_efiboot

    if [[ "${tarball}" = true ]]; then
        run_once make_tarball
    fi

    if [[ "${build_mode}" = "erofs" ]]; then
        run_once make_archiso_erofs
    elif [[ "${build_mode}" = "squashfs" ]]; then
        run_once make_archiso_squashfs
    fi

    run_once make_iso

fi

if [[ "${cleaning}" = true ]]; then
    _run_cleansh
fi

exit 0
