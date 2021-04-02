#!/bin/bash

set -e

function getCurrentDir() {
    local current_dir="${BASH_SOURCE%/*}"
    if [[ ! -d "${current_dir}" ]]; then current_dir="$PWD"; fi
    echo "${current_dir}"
}

function includeDependencies() {
    source "${current_dir}/setupLibrary.sh"
}

current_dir=$(getCurrentDir)
includeDependencies
output_file="output.log"

function main() {
    read -rp "Enter the username of the new user account:" username
    promptForPassword
    read -s -rp "Enter new docker password:" dockerPassword

    # Run setup functions
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    addUserAccount "${username}" "${password}" true

    read -rp $'Paste in the public SSH key for the new user:\n' sshKey
    echo 'Running setup script...'
    logTimestamp "${output_file}"

    exec 3>&1 >>"${output_file}" 2>&1
    disableSudoPassword "${username}"
    addSSHKey "${username}" "${sshKey}"
    changeSSHConfig
    setupUfw

    if ! hasSwap; then
        setupSwap
    fi

    setupTimezone

    echo "Installing Network Time Protocol... " >&3
    configureNTP

    sudo service ssh restart

    echo "Done installing Network Time Protocol. " >&3

    echo "Installing Docker... " >&3
    sudo apt-get update -y
    addUserAccount docker "${dockerPassword}" true
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker docker
    rm get-docker.sh
    sudo curl -L "https://github.com/docker/compose/releases/download/1.28.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Done Installing Docker." >&3

    cleanup

    echo "Setup Done! Log file is located at ${output_file}" >&3
}

function setupSwap() {
    createSwap
    mountSwap
    tweakSwapSettings "10" "50"
    saveSwapSettings "10" "50"
}

function hasSwap() {
    [[ "$(sudo swapon -s)" == *"/swapfile"* ]]
}

function cleanup() {
    if [[ -f "/etc/sudoers.bak" ]]; then
        revertSudoers
    fi
}

function logTimestamp() {
    local filename=${1}
    {
        echo "==================="
        echo "Log generated on $(date)"
        echo "==================="
    } >>"${filename}" 2>&1
}

function setupTimezone() {
    echo -ne "Enter the timezone for the server (Default is 'Europe/Berlin'):\n" >&3
    read -r timezone
    if [ -z "${timezone}" ]; then
        timezone="Europe/Berlin"
    fi
    setTimezone "${timezone}"
    echo "Timezone is set to $(cat /etc/timezone)" >&3
}

# Keep prompting for the password and password confirmation
function promptForPassword() {
   PASSWORDS_MATCH=0
   while [ "${PASSWORDS_MATCH}" -eq "0" ]; do
       read -s -rp "Enter new UNIX password:" password
       printf "\n"
       read -s -rp "Retype new UNIX password:" password_confirmation
       printf "\n"

       if [[ "${password}" != "${password_confirmation}" ]]; then
           echo "Passwords do not match! Please try again."
       else
           PASSWORDS_MATCH=1
       fi
   done
}

main