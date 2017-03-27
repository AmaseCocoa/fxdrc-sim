#!/usr/bin/env bash
# drc-sim(-backend): Wii U gamepad emulator.
#
# drc-sim-backend install script
# https://github.com/rolandoislas/drc-sim

REPO_DRC_SIM="https://github.com/rolandoislas/drc-sim.git"
REPO_WPA_SUPPLICANT_DRC="https://github.com/rolandoislas/drc-hostap.git"
INSTALL_DIR="/opt/drc_sim/"
dependencies=()
branch_drc_sim=""

# Checks to see if OS has apt-get and sets dependencies
# Exits otherwise
check_os() {
    if command -v apt-get &> /dev/null; then
        echo "Command apt-get found."
        # Backend dependencies
        dependencies=("python2.7" "python2.7-dev" "python-pip" "libffi-dev" "zlib1g-dev" "libjpeg-dev"
        "net-tools" "wireless-tools" "sysvinit-utils" "psmisc" "libavcodec-dev" "libswscale-dev" "rfkill"
        "isc-dhcp-client" "ifmetric" "python-tk" "gksu")
        # Wpa supplicant compile dependencies
        dependencies+=("git" "libssl-dev" "libnl-genl-3-dev" "gcc" "make")
    else
        echo "The command apt-get was not found. This OS is not supported."
        exit 1
    fi
}

# Check to see if the script is running as root
# Exits if not root
check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "Install script must be executed with root privileges."
        exit 1
    fi
}

# Checks and installs pre-defined decencies array
# Exits on failed dependency
install_dependencies() {
    echo "Installing dependencies."
    for dependency in "${dependencies[@]}"
    do
        installed="$(dpkg -s ${dependency} 2>&1)"
        if [[ ${installed} =~ "Status: install ok installed" ]]; then
            echo "${dependency} [INSTALLED]"
        else
            echo "${dependency} [INSTALLING]"
            if command apt-get -y install ${dependency} &> /dev/null; then
                echo "${dependency} [INSTALLED]"
            else
                echo "${dependency} [FAILED]"
                exit 1
            fi
        fi
    done
}

# Update git directory while stashing changed return 1
# Returns 1 on failure
update_git() {
    cur_dir="${PWD}"
    cd "${1}" &> /dev/null || return 1
    if [[ -d "${1}" ]]; then
        echo "Found existing git directory ${1}"
        if command git stash --include-untracked &> /dev/null; then
            echo "Stashed git changes"
            echo "Updating git repo"
            if command git pull &> /dev/null; then
                echo "Updated git repo"
            else
                return 1
            fi
        else
            return 1
        fi
    fi
    cd "${cur_dir}" &> /dev/null || return 1
    return 0
}

# Clones a git repo to the install path
# If the directory exists it is removed
# Param $1: git repo url
get_git() {
    git_dir="${INSTALL_DIR}${2}"
    if update_git ${git_dir}; then
        return 0
    else
        # Remove directory for a clean clone
        if [[ -d "${git_dir}" ]]; then
            rm -rf "${git_dir}"
        fi
    fi
    # Clone
    echo "Cloning ${1} into ${git_dir}"
    if command git clone ${1} ${git_dir} &> /dev/null; then
        echo "Cloned ${1}"
    else
        echo "Failed to clone ${1}"
        exit 1
    fi
}

# Compiles wpa_supplicant after fetching it from git
compile_wpa() {
    if command -v wpa_supplicant_drc &> /dev/null && command -v wpa_cli_drc &> /dev/null; then
        echo "Skipping wpa_supplicant compile"
        return 0
    fi
    get_git ${REPO_WPA_SUPPLICANT_DRC} "wpa"
    echo "drc-hostap"
    echo "Compiling wpa_supplicant_drc"
    wpa_dir="${INSTALL_DIR}wpa/wpa_supplicant/"
    cur_dir="${PWD}"
    cd "${wpa_dir}" &> /dev/null || return 1
    cp ../conf/wpa_supplicant.config ./.config &> /dev/null || return 1
    compile_log="${wpa_dir}make.log"
    echo "Compile log at ${compile_log}"
    make &> ${compile_log} || return 1
    echo "Installing wpa_supplicant_drc and wpa_cli_drc to /usr/local/bin"
    cp wpa_supplicant /usr/local/bin/wpa_supplicant_drc &> /dev/null || return 1
    cp wpa_cli /usr/local/bin/wpa_cli_drc &> /dev/null || return 1
    cd "${cur_dir}" &> /dev/null || return 1
    return 0
}

# Installs drc-sim in a virtualenv
install_drc_sim() {
    # Get repo
    get_git ${REPO_DRC_SIM} "drc"
    # Paths
    drc_dir="${INSTALL_DIR}drc/"
    cur_dir="${PWD}"
    venv_dir="${INSTALL_DIR}venv_drc/"
    # Install virtualenv
    echo "Installing virtualenv"
    python -m pip install virtualenv &> /dev/null || return 1
    # Create venv
    echo "Creating virtualenv"
    python -m virtualenv "${venv_dir}" &> /dev/null || return 1
    # Activate venv
    echo "Activating virtualenv"
    source "${venv_dir}bin/activate" || return 1
    # Remove an existing install of drc-sim
    #echo "Attempting to remove previous installations"
    #pip uninstall drc-sim &> /dev/null || return 1
    # Set the directory
    cd "${drc_dir}" &> /dev/null || return 1
    # Branch to checkout
    echo "Using branch \"${branch_drc_sim}\" for drc-sim install"
    git checkout ${branch_drc_sim} &> /dev/null || return 1
    # Install
    echo "Installing drc-sim"
    echo "Downloading Python packages. This may take a while."
    python setup.py install &> /dev/null || return 1
    cd "${cur_dir}" &> /dev/null || return 1
}

# Install the shell script that activates the venv and launches drc-sim with gksu
install_launch_script() {
    echo "Installing launch script"
    launch_script="${INSTALL_DIR}drc/resources/bin/drc-sim-backend.sh"
    echo "Copying launch script from ${launch_script}"
    cp ${launch_script} /usr/local/bin/drc-sim-backend &> /dev/null || return 1
    echo "Setting launch script executable"
    chmod +x /usr/local/bin/drc-sim-backend &> /dev/null || return 1
}

# Install the desktop launcher
install_desktop_launcher() {
    echo "Installing desktop launcher"
    launcher="${INSTALL_DIR}drc/resources/bin/drc-sim-backend.desktop"
    cp ${launcher} /usr/share/applications/ &> /dev/null || return 1
    chmod +x /usr/share/applications/drc-sim-backend.desktop &> /dev/null || return 1
    echo "Installing icon"
    icon="${INSTALL_DIR}drc/resources/image/icon.png"
    cp ${icon} /usr/share/icons/hicolor/512x512/apps/drcsimbackend.png &> /dev/null || echo "Failed to install icon"
    update-icon-caches /usr/share/icons/* &> /dev/null || echo "Failed to update icon cache."
}

# Checks if the first parameter is help or -h and displays help
# exits if help is displayed
check_help() {
    if [[ "${1}" == "help" ]] || [[ "${1}" == "-h" ]]; then
        echo "Usage: <install.sh> [options] [branch]"
        echo "  Options:"
        echo "    -h, help : help menu"
        echo "  Arguments:"
        echo "    branch : branch to use for drc-sim (master or develop) master is used by default"
        exit 1
    fi
}

# Echos the general info
print_info() {
    echo "Drc-sim installer"
    echo "  https://github.com/rolandoislas/drc-sim"
}

# Parses args
check_args() {
    branch_drc_sim=${1:-master}
    if [[ "${branch_drc_sim}" != "develop" ]] && [[ "${branch_drc_sim}" != "master" ]]; then
        echo "Invalid branch \"${branch_drc_sim}\""
        check_help "help"
    fi
}

# Check if command return value is non-zero and exit with message.
# If the command exited with a zero exit value the success message will be echoed
pass_fail() {
    if $1; then
        echo $2
    else
        echo $3
        exit 1
    fi
}

# Echo post install message and exit
post_install() {
    echo "Install finished"
    echo "\"DRC SIM Server\" is now available in a GUI desktop applications menu if installed."
    echo "It can also be launched via \"drc-sim-backend\"."
    exit 0
}

main() {
    # TODO create uninstall parameter
    print_info
    check_help "$@"
    check_args "$@"
    check_root
    check_os
    install_dependencies
    pass_fail compile_wpa "Compiled wpa_supplicant" "Failed to compile wpa_supplicant"
    pass_fail install_drc_sim "Created virtualenv for drc-sim" "Failed to create virtualenv for drc-sim"
    pass_fail install_launch_script "Launch script installed." "Failed to install launch script"
    pass_fail install_desktop_launcher "Installed application launcher" "Failed to install desktop application launcher"
    post_install
}


main "$@"
