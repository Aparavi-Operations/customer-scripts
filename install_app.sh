#!/bin/bash

usage () {
    cat <<EOH

$0 -n "platform" -c "client_name" [additional_options]

Required options:
    -n Node profile for deploying. Default: "default"
       mysql                             - MySQL server
       appagtbundle                      - MySQL server + Aparavi AppAgent
       appagt                            - Aparavi AppAgent

    -c Client name. Example "Aparavi"

appagt specific options:
    -o Aparavi parent object ID. Example: "ddd-ddd-ddd-ddd"
    -a Aparavi platform bind address. Default "preview.aparavi.com"

mysql specific options:
    -m Mysql AppUser name. Default: "aparavi_app"
    -h Mysql host. Default: localhost with bundle install
    -p Mysql password. Default: random generated.

additional options:
    -v Verbose level (0..5). Default: "0"
    -u Aparavi app download url. Default: 2.6.0-7315 version now.
    -d Aparavi app download package checksum digest. Default: sha256:4c9074f3c7c9af80a95c00616dacdff87194655da2c224de28bd9ba5cf302ddc
EOH
}

DOWNLOAD_URL="https://updates.aparavi.com/updates-dia-aparavi/production/install-aparavi-data-ia-2.6.0-7315.run"
DOWNLOAD_DIGEST="sha256:4c9074f3c7c9af80a95c00616dacdff87194655da2c224de28bd9ba5cf302ddc"
MYSQL_OPTIONS=""

while getopts ":a:c:o:p:m:h:v:n:u:d:" options; do
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
        p)
            MYSQL_OPTIONS="mysql_appuser_password='${OPTARG}'"
            ;;
        m)
            MYSQL_OPTIONS="${MYSQL_OPTIONS} mysql_appuser_name='${OPTARG}'"
            ;;
        h)
            MYSQL_OPTIONS="${MYSQL_OPTIONS} app_db_host='${OPTARG}'"
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
        d)
            DOWNLOAD_DIGEST=${OPTARG}
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
if [[ -z "$APARAVI_PARENT_OBJECT_ID" ]]; then
    echo "Error: Option '-o' is required."
    usage
    exit 1
fi
}

###### end of required switches checking ######
###### Node profile dictionary ######
case "${NODE_PROFILE:=default}" in
    appagtbundle)
        check_o_switch
        APP_TYPE="appagt"
        NODE_ANSIBLE_TAGS="-t mysql,appagt"
        ;;
    appagt)
        check_o_switch
        APP_TYPE="appagt"
        NODE_ANSIBLE_TAGS="-t appagt"
        ;;
    mysql)
        APP_TYPE="mysql"
        NODE_ANSIBLE_TAGS="-t mysql"
        ;;
    *)
    echo "Error: please provide node profile (\"-n\" switch) from the list: mysql, appagt, appagtbundle"
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
# default mysql user is set in group_vars
ANSIBLE_VERBOSITY=${VERBOSE_LEVEL:-0} \
pipenv run ansible-playbook --connection=local ansible-playbooks/app/main.yml \
    -i 127.0.0.1, \
    $NODE_ANSIBLE_TAGS \
    --extra-vars    "app_type=${APP_TYPE} \
                    app_platform_bind_addr=${APARAVI_PLATFORM_BIND_ADDR:-preview.aparavi.com} \
                    app_package_url=${DOWNLOAD_URL} \
                    app_package_checksum=${DOWNLOAD_DIGEST} \
                    app_parent_object=${APARAVI_PARENT_OBJECT_ID:-non_needed_dummy} \
                    ${MYSQL_OPTIONS}"
