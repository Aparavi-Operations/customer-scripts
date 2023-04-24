#!/bin/bash

usage () {
    cat <<EOH

$0 -n "platform" -c "client_name" [additional_options]

Required options:
    -n Node profile for deploying. Default: "default"
       mysql                             - MySQL server
       appagt                            - MySQL server + Aparavi Platform

    -c Client name. Example "Aparavi"

appagt specific options:
    -o Aparavi parent object ID. Example: "ddd-ddd-ddd-ddd"
    -a Aparavi platform bind address. Default "preview.aparavi.com"

mysql specific options:
    -m Mysql AppUser name. Default: "aparavi_app"

additional options:
    -v Verbose level (0..5). Default: "0"
    -u Aparavi app download url. Default: "https://aparavi.jfrog.io/artifactory/aparavi-installers-public/linux-installer-latest.run"
EOH
}

DOWNLOAD_URL="https://aparavi.jfrog.io/artifactory/aparavi-installers-public/linux-installer-latest.run"

while getopts ":a:c:o:p:m:v:n:u:" options; do
    case "${options}" in
        a)
            APARAVI_PLATFORM_BIND_ADDR=${OPTARG}
            ;;
        c)
            SERVICE_INSTANCE=${OPTARG}
            ;;
        o)
            APARAVI_PARENT_OBJECT_ID=${OPTARG}
            ;;
        m)
            MYSQL_APPUSER_NAME=${OPTARG}
            ;;
        v)
            VERBOSE_LEVEL=${OPTARG}
            ;;
        n)
            NODE_PROFILE=${OPTARG}
            ;;
        u)
            DOWNLOAD_URL=${OPTARG}
            ;;
        :)  # If expected argument omitted:
            echo "Error: -${OPTARG} requires an argument."
            usage
            exit 1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

###### required switches checking ######
function check_c_switch {
if [[ -z "$SERVICE_INSTANCE" ]]; then
    echo "Error: Option '-c' is required."
    usage
    exit 1
fi
}

function check_o_switch {
if [[ -z "$NODE_PROFILE" ]]; then
    echo "Error: Option '-n' is required."
    usage
    exit 1
fi
}

function check_a_switch {
if [[ -z "$APARAVI_PLATFORM_BIND_ADDR" ]]; then
    echo "Error: Option '-a' is required."
    usage
    exit 1
fi
}

###### end of required switches checking ######
###### Node profile dictionary ######
case "${NODE_PROFILE:=default}" in
    appagt)
        check_a_switch
        APP_TYPE="appagt"
        NODE_ANSIBLE_TAGS="-t mysql,appagt"
        ;;
    mysql)
        APP_TYPE="mysql"
        NODE_ANSIBLE_TAGS="-t mysql"
        ;;
    *)
    echo "Error: please provide node profile (\"-n\" switch) from the list: mysql, appagt"
        usage
        exit 1
        ;;
esac
###### end of node profile dictionary ######

# Exit immediately if an any command exits with a non-zero status
set -e
cd "$(dirname "$0")"

shift "$((OPTIND-1))"
if [[ $# -ge 1 ]]; then
    echo "Error: '$@' - non-option arguments. Don't use them"
    usage
    exit 1
fi

###### install OS prereqs ######
. ./support/install_prerequisites.sh

###### run ansible ######
ANSIBLE_VERBOSITY=${VERBOSE_LEVEL:-0} \
pipenv run ansible-playbook --connection=local playbooks/app/main.yml \
    -i 127.0.0.1, \
    $NODE_ANSIBLE_TAGS \
    --extra-vars    "mysql_appuser_name=${MYSQL_APPUSER_NAME:-aparavi_app} \
                    app_type=${APP_TYPE} \
                    app_platform_bind_addr=${APARAVI_PLATFORM_BIND_ADDR:-preview.aparavi.com} \
                    app_package_url=${DOWNLOAD_URL} \
                    app_parent_object=${APARAVI_PARENT_OBJECT_ID:-non_needed_dummy}"
