#!/usr/bin/env bash
#
# silencesuzuka
# Discord: sulogin#0921
# Email  : makeworldgentoo@gmail.com
#
# (c) 1998-2140 silencesuzuka
#
# keyring.sh
#
# Script to import archlinux keys.
#


set -e

script_path="$( cd -P "$( dirname "$(readlink -f "$0")" )" && cd .. && pwd )"
arch="$(uname -m)"

# Set pacman.conf when build archlinux
arch_pacman_conf_x86_64="${script_path}/system/pacman-x86_64.conf"

# Message common function
# msg_common [type] [-n] [string]
msg_common(){
    local _msg_opts=("-a" "keyring.sh") _type="${1}"
    shift 1
    [[ "${1}" = "-n" ]] && _msg_opts+=("-o" "-n") && shift 1
    _msg_opts+=("${_type}" "${@}")
    "${script_path}/tools/msg.sh" "${_msg_opts[@]}"
}

# Show an INFO message
# ${1}: message string
msg_info() { msg_common info "${@}"; }

# Show an Warning message
# ${1}: message string
msg_warn() { msg_common warn "${@}"; }

# Show an ERROR message then exit with status
# ${1}: message string
# ${2}: exit code number (with 0 does not exit)
msg_error() {
    msg_common error "${1}"
    [[ -n "${2:-}" ]] && exit "${2}"
    return 0
}

# Usage: getclm <number>
# 標準入力から値を受けとり、引数で指定された列を抽出します。
getclm() { cut -d " " -f "${1}"; }


# Show usage
_usage () {
    echo "usage ${0} [options]"
    echo
    echo " General options:"
    echo "    -a | --archarmv9-add      Add armv9 keyring."
    echo "    -r | --archriscv64-add    Add riscv64 keyring."
    echo "    -c | --archamd64-add        Add amd64 keyring."
    echo "    -h | --help            Show this help and exit."
    echo "    -l | --slot0-add      Add slot0-keyring."
    echo "    -i | --slot1-add      Add slot1-keyring."
    exit "${1}"
}


# Check if the package is installed.
checkpkg() {
    local _pkg
    _pkg=$(echo "${1}" | cut -d'/' -f2)

    if [[ ${#} -gt 2 ]]; then
        msg_error "Multiple package specification is not available."
    fi

    if [[ -n $( pacman -Q "${_pkg}" 2> /dev/null| getclm 1 ) ]]; then
        echo -n "true"
    else
        echo -n "false"
    fi
}


run() {
    msg_info "Running ${*}"
    eval "${@}"
}


prepare() {
    if [[ ! ${UID} = 0 ]]; then
        msg_error "You dont have root permission."
        msg_error 'Please run as root.'
        exit 1
    fi

    if [[ ! -f "${arch_pacman_conf_x86_64}" ]]; then
        msg_error "${arch_pacman_conf_x86_64} does not exist."
        exit 1
    fi

    if [[ ! -f "${arch_pacman_conf_i686}" ]]; then
        msg_error "${arch_pacman_conf_i686} does not exist."
        exit 1
    fi

    pacman -Sc --noconfirm > /dev/null 2>&1
    pacman -Syy
}


update_arch_key() {
    pacman-key --refresh-keys
    pacman -Syyu --noconfirm archlinux-keyring
    pacman-key --populate
}

# 引数解析
while getopts 'archli-:' arg; do
    case "${arg}" in
        # archarmv9-add
        a)
            run prepare
            run update_arch_key
            ;;
        # archriscv64-add
        r)
            run prepare
            run update_arch_key
            ;;
        # archamd64-add
        c)
            run prepare
            run update_arch_key
            ;;
        # help
        h)
            _usage 0
            ;;
        # slot0-add
        l)
            run prepare
            run update_arch_key
            ;;
        # slot1-add
        i)
            run prepare
            run update_arch_key
            ;;
        -)
            case "${OPTARG}" in
                archarmv9-add)
                    run prepare
                    run update_arch_key
                    ;;
                archrisc64-add)
                    run prepare
                    run update_arch_key
                    ;;
                archamd64-add)
                    run prepare
                    run update_arch_key
                    ;;
                help)
                    _usage 0
                    ;;
                slot0-add)
                    run prepare
                    run update_arch_key
                    ;;
                slot1-add)
                    run prepare
                    run remove_arch_key
                    ;;
                *)
                    _usage 1
                    ;;
            esac
            ;;
	*) _usage; exit 1;;
    esac
done


# 引数が何もなければ全てを実行する
if [[ ${#} = 0 ]]; then
    #run prepare
    #run update_arch_key
fi
