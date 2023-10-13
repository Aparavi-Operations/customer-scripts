#!/bin/bash

source ./lib/func.sh

usage () {
    cat <<EOH

$0 -n "platform" -c "client_name" [additional_options]

Required options:
    --client        Client name to distinguish installs in monitoring. REQUIRED.
    --db-pass       Database password. REQUIRED.

Other available options:
    --type          Application type to install of aggregator/appagent/collector (default: appagent)
    --platform      Parent node endpoint (platform for aggregator/appagent) (default: preview.aparavi.com)
    --env           Application environment (default: production)
    --parent        Parent ID in platform tree (default: CLIENTS)
    --db-host       Database host. If specified no MySQL will be installed
    --db-user       Required if db-host was specified, root is used for script installs
    --url           Package URL to install (default: some outdated version)
    --vm            VictoriaMetrics endpoint. If specified agents will be installed.
    --logstash      Logstash endpoint. If specified filebeat will be installed.
    --checksum      Package checksum. Will be checked if specified.
    --help          Prints help.

EOH
}

# Some internally set versions
FILEBEAT_VERSION='7.17.9'
NODE_EXP_VERSION='1.6.0'
MYSQLD_EXP_VERSION='0.14.0'
VMAGENT_VERSION='1.87.5'

# Some defaults
APP_PROFILE="appagent"
APP_ENV="production"
APP_PLATFORM_URL="preview.aparavi.com"
APP_PARENT_OBJECT_ID="CLIENTS"
APP_PACKAGE_URL="https://updates.aparavi.com/updates-dia-aparavi/production/install-aparavi-data-ia-2.8.3-7667.run"
APP_PACKAGE_CHECKSUM=""

get_args() {
    ARGUMENT_LIST=(
        "help"
        "type:"
        "env:"
        "platform:"
        "parent:"
        "client:"
        "db-host:"
        "db-user:"
        "db-pass:"
        "url:"
        "checksum:"
        "vm:"
        "logstash:"
    )

    # read arguments
    opts=$(getopt \
        --longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
        --name "$(basename "$0")" \
        --options "" \
        -- "$@"
    )
    eval set --$opts
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                export APP_PROFILE=$2; shift 2
                ;;
            --env)
                export APP_ENV=$2; shift 2
                ;;
            --platform)
                export APP_PLATFORM_URL=$2; shift 2
                ;;
            --parent)
                export APP_PARENT_OBJECT_ID=$2; shift 2
                ;;
            --client)
                export APP_CLIENT=$2; shift 2
                ;;
            --db-host)
                export APP_DB_HOST=$2; shift 2
                ;;
            --db-user)
                export APP_DB_USER=$2; shift 2
                ;;
            --db-pass)
                export APP_DB_PASS=$2; shift 2
                ;;
            --url)
                export APP_PACKAGE_URL=$2; shift 2
                ;;
            --vm)
                export APP_VM_ENDPOINT=$2; shift 2
                ;;
            --logstash)
                export APP_LOGSTASH_ENDPOINT=$2; shift 2
                ;;
            --checksum)
                export APP_PACKAGE_CHECKSUM=$2; shift 2
                ;;
            --help)
                usage
                ;;
            --)
                break
                ;;
            *)
                echo "Invalid argument $1 $2" && usage
                ;;
        esac
    done

    return 0
}

# Exit immediately if an any command exits with a non-zero status
set -e

cd "$(dirname "$0")"

# Parse command line args
get_args "$@"

[[ -z "${APP_DB_PASS}" ]] && (echo "Database password is required!"; usage; exit 1)
[[ -z "${APP_CLIENT}" ]] && (echo "Client name is required!"; usage; exit 1)

if [ -z "${APP_DB_HOST}" ]; then
    APP_DB_HOST='127.0.0.1'
    APP_DB_USER='root'
    mysql_debian_install $APP_DB_PASS
elif [ ! -z "${APP_DB_USER}" ]; then
    echo "You specified DB host, but username is also required!"
    usage
    exit 1
fi

download $APP_PACKAGE_URL aparavi-installer.run $APP_PACKAGE_CHECKSUM

case $APP_PROFILE in
    'appagent')
        APP_FOLDER="aggregator-collector"
        sh ./aparavi-installer.run -- \
            /APPTYPE=appagt /SILENT \
            --cfg.node.nodeName="$(hostname)-appagent" --cfg.node.parentObjectId="${APP_PARENT_OBJECT_ID}" \
            --cfg.node.hostName="$(hostname)" /BINDTO="${APP_PLATFORM_URL}" \
            --cfg.database.database="$(hostname)-db" /DBUSER="${APP_DB_USER}" \
            /DBPSWD=="${APP_DB_PASS}" /DBHOST="${APP_DB_HOST}"
        ;;
    'aggregator')
        APP_FOLDER="aggregator"
        sh ./aparavi-installer.run -- \
            /APPTYPE=appliance /SILENT \
            --cfg.node.nodeName="$(hostname)-aggregator" --cfg.node.parentObjectId="${APP_PARENT_OBJECT_ID}" \
            --cfg.node.hostName="$(hostname)" /BINDTO="${APP_PLATFORM_URL}" \
            --cfg.database.database="$(hostname)-db" /DBUSER="${APP_DB_USER}" \
            /DBPSWD=="${APP_DB_PASS}" /DBHOST="${APP_DB_HOST}"
        ;;
    'collector')
        APP_FOLDER="collector"
        sh ./aparavi-installer.run -- \
            /APPTYPE=agent /SILENT \
            --cfg.node.nodeName="$(hostname)-collector" --cfg.node.parentObjectId="${APP_PARENT_OBJECT_ID}" \
            --cfg.node.hostName="$(hostname)" /BINDTO="${APP_PLATFORM_URL}"
        ;;
    *)
        echo "Only aggregator/appagent/collector supported as type"; exit 1
        ;;
esac

if [ ! -z "${APP_LOGSTASH_ENDPOINT}" ]; then
    echo "#### Logstash address ${APP_LOGSTASH_ENDPOINT} was passed ####"
    echo -e "#### Installer script: filebeat setup in progress... ####\n"
    filebeat_install $FILEBEAT_VERSION
    filebeat_configure $APP_PROFILE $APP_FOLDER $APP_CLIENT $APP_ENV $APP_LOGSTASH_ENDPOINT
    echo "#### Installer script: filebeat setup DONE ####"
fi

if [ ! -z "${APP_VM_ENDPOINT}" ]; then
    echo "#### VictoriaMetrics address ${APP_VM_ENDPOINT} was passed ####"
    echo -e "#### Installer script: metrics collection setup in progress... ####\n"
    prometheus_node_exporter_install $NODE_EXP_VERSION
    prometheus_node_exporter_configure
    prometheus_mysqld_exporter_install $MYSQLD_EXP_VERSION
    prometheus_mysqld_exporter_configure $APP_DB_USER $APP_DB_PASS
    vmagent_install $VMAGENT_VERSION
    vmagent_configure $APP_CLIENT $APP_ENV $APP_VM_ENDPOINT
    echo "#### Installer script: metrics collection setup in DONE ####"
fi
