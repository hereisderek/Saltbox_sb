#!/bin/bash
#########################################################################
# Title:         Saltbox: SB Script                                     #
# Author(s):     desimaniac, chazlarson                                 #
# URL:           https://github.com/saltyorg/sb                         #
# --                                                                    #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Privilege Escalation
################################

# Restart script in SUDO
# https://unix.stackexchange.com/a/28793

if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

################################
# Scripts
################################

source /srv/git/sb/yaml.sh
create_variables /srv/git/saltbox/accounts.yml

################################
# Variables
################################

#Ansible
ANSIBLE_PLAYBOOK_BINARY_PATH="/usr/local/bin/ansible-playbook"

# Saltbox
SALTBOX_REPO_PATH="/srv/git/saltbox"
SALTBOX_PLAYBOOK_PATH="$SALTBOX_REPO_PATH/saltbox.yml"
SALTBOX_LOGFILE_PATH="$SALTBOX_REPO_PATH/saltbox.log"

# Community
COMMUNITY_REPO_PATH="/opt/community"
COMMUNITY_PLAYBOOK_PATH="$COMMUNITY_REPO_PATH/community.yml"
COMMUNITY_LOGFILE_PATH="$COMMUNITY_REPO_PATH/community.log"

################################
# Functions
################################

git_fetch_and_reset () {

    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard @{u} >/dev/null
    git checkout --quiet master >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard @{u} >/dev/null
    git submodule update --init --recursive
    chmod 664 /srv/git/saltbox/ansible.cfg
    chown -R "${user_name}":"${user_name}" "${SALTBOX_REPO_PATH}"
}

run_playbook_sb () {

    local arguments="$@"

    echo "" > "${SALTBOX_LOGFILE_PATH}"

    cd "${SALTBOX_REPO_PATH}"

    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${SALTBOX_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null

}

run_playbook_cm () {

    local arguments="$@"

    echo "" > "${COMMUNITY_LOGFILE_PATH}"

    cd "${COMMUNITY_REPO_PATH}"
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${COMMUNITY_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    cd - >/dev/null

}

install () {

    local arg=("$@")

    # Remove space after comma
    arg_clean=$(sed -e 's/, /,/g' <<< "$arg")

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    re="^(\S+)\s+(-.*)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        tags_arg="${BASH_REMATCH[1]}"
        extra_arg="${BASH_REMATCH[2]}"
    else
        tags_arg="$arg_clean"
    fi

    # Save tags into 'tags' array
    tags_tmp=(${tags_arg//,/ })

    # Remove duplicate entries from array
    # https://stackoverflow.com/a/31736999
    readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

    # Build SB/CM tag arrays
    local tags_sb
    local tags_cm
    local skip_settings_in_sb=true
    local skip_settings_in_cm=true

    for i in "${!tags[@]}"
    do
        if [[ ${tags[i]} == cm-* ]]; then
            tags_cm="${tags_cm}${tags_cm:+,}${tags[i]##cm-}"

            if [[ "${tags[i]##cm-}" =~ "settings" ]]; then
                skip_settings_in_cm=false
            fi
        else
            tags_sb="${tags_sb}${tags_sb:+,}${tags[i]}"

            if [[ "${tags[i]}" =~ "settings" ]]; then
                skip_settings_in_sb=false
            fi
        fi
    done

    # Saltbox Ansible Playbook
    if [[ ! -z "$tags_sb" ]]; then

        # Build arguments
        local arguments_sb="--tags $tags_sb"

        if [ "$skip_settings_in_sb" = true ]; then
            arguments_sb="${arguments_sb} --skip-tags settings"
        fi

        if [[ ! -z "$extra_arg" ]]; then
            arguments_sb="${arguments_sb} ${extra_arg}"
        fi

        # Run playbook
        echo ""
        echo "Running Saltbox Tags: "${tags_sb//,/,  }
        echo ""
        run_playbook_sb $arguments_sb
        echo ""

    fi

    # Community Ansible Playbook
    if [[ ! -z "$tags_cm" ]]; then

        # Build arguments
        local arguments_cm="--tags $tags_cm"

        if [ "$skip_settings_in_cm" = true ]; then
            arguments_cm="${arguments_cm} --skip-tags settings"
        fi

        if [[ ! -z "$extra_arg" ]]; then
            arguments_cm="${arguments_cm} ${extra_arg}"
        fi

        # Run playbook
        echo "========================="
        echo ""
        echo "Running Community Tags: "${tags_cm//,/,  }
        echo ""
        run_playbook_cm $arguments_cm
        echo ""
    fi

}

update () {

    declare -A old_object_ids
    declare -A new_object_ids
    config_files=('accounts' 'settings' 'adv_settings' 'backup_config')
    config_files_are_changed=false

    echo -e "Updating Saltbox...\n"

    cd "${SALTBOX_REPO_PATH}"

    # Get Git Object IDs for config files
    for file in "${config_files[@]}"; do
        old_object_ids["$file"]=$(git hash-object defaults/"$file".yml.default)
    done

    git_fetch_and_reset

    # Get Git Object IDs for config files
    for file in "${config_files[@]}"; do
        new_object_ids["$file"]=$(git hash-object defaults/"$file".yml.default)
    done

    # Compare Git Object IDs
    for file in "${config_files[@]}"; do
        if [ ${old_object_ids[$file]} != ${new_object_ids[$file]} ]; then
            config_files_are_changed=true
            break
        fi
    done

    $config_files_are_changed && run_playbook_sb "--tags settings" && echo -e '\n'

    echo -e "Updating Complete."

}

usage () {
    echo "Usage:"
    echo "    sb [-h]                Display this help message."
    echo "    sb install <package>   Install <package>."
    echo "    sb update              Update Saltbox project folder."
}

################################
# Argument Parser
################################

# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

roles=""  # Default to empty role
target=""  # Default to empty target

# Parse options
while getopts ":h" opt; do
  case ${opt} in
    h)
        usage
        exit 0
        ;;
   \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        echo ""
        usage
        exit 1
     ;;
  esac
done
shift $((OPTIND -1))

# Parse commands
subcommand=$1; shift  # Remove 'cb' from the argument list
case "$subcommand" in

  # Parse options to the various sub commands
    update)
        update
        ;;
    install)
        roles=${@}
        install "${roles}"
        ;;
    "") echo "A command is required."
        echo ""
        usage
        exit 1
        ;;
    *)
        echo "Invalid Command: ${@}" 1>&2
        echo ""
        usage
        exit 1
        ;;
esac