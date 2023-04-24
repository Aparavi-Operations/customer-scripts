#!/bin/bash

get_local_ip() {
    for ip in $(/usr/bin/hostname -I); do
        if [[ $ip != 172.17.* ]]; then
            echo $ip
            return
        fi
    done
}

usage () {
    cat <<EOH

$0 -e <ENVIRONMENT> -c <CLIENT_NAME> -l <LOGSTASH_ADDRESS> -u <USER> -p <PASS> -v <VM_EXT_URL> -f <PLATFORM_IP> -m <PLATFORM_MYSQL_IP>

Required arguments:
    --client Client name. Example "Aparavi"

    --logstash-address Logstash
    --logstash-user-password Logstash HTTP input user password


Optional arguments:
    --rhub   prod or nonprod. Default to "prod". Aparavi regional hub to use.
    --env    Environment name. Defaults to "prod-onprem" or "nonprod-onprem", depends on rhub.

    --platform-ip            Platform IP address. Defaults to the first IP in `hostname -I` on this instance.

    --platform-url           Platform URL for synthetic monitoring.
    --platform-user          Platform user name for synthetic monitoring.
    --platform-user-password Platform user password for synthetic monitoring.

    --platform-mysql-ip      Platform MYSQL IP address. Defaults to the first IP in `hostname -I` on this instance.
    --platform-mysql-user    Platform MYSQL User. Will be get from platform's config.json by default.
    --platform-mysql-password Platform MYSQL User's password. Will be get from platform's config.json by default.

    --appagt-ip             AppAgent IP address
    --appagt-mysql-ip       AppAgent MYSQL IP address
    --appagt-mysql-user     AppAgent MYSQL User
    --appagt-mysql-password AppAgent MYSQL User's password
EOH
    exit 1
}

print_pass() {
    if ! [ -z "$1" ]; then
        echo "${1:0:2}..."
    fi
}

get_args() {
    ARGUMENT_LIST=(
        "help"

        "env:"
        "client:"
        "rhub:"

        "logstash-user:"
        "logstash-user-password:"

        "platform-ip:"

        "platform-url:"
        "platform-user:"
        "platform-user-password:"

        "platform-mysql-ip:"
        "platform-mysql-user:"
        "platform-mysql-user-password:"

        "appagt-ip:"
        "appagt-mysql-ip:"
        "appagt-mysql-user:"
        "appagt-mysql-user-password:"
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
            --env)
                export ENVIRONMENT=$2; shift 2
                ;;
            --client)
                export SERVICE_INSTANCE=$2;shift 2
                ;;
            --rhub)
                RHUB=$2; shift 2
                ;;
            --logstash-address)
                export LOGSTASH_ADDRESS=$2; shift 2
                ;;
            --logstash-user)
                export LOGSTASH_HTTP_USER=$2; shift 2
                ;;
            --logstash-user-password)
                export LOGSTASH_HTTP_USER_PASSWORD=$2; shift 2
                ;;
            --platform-ip)
                export PLATFORM_IP=$2; shift 2
                ;;
            --platform-url)
                export PLATFORM_URL=$2; shift 2
                ;;
            --platform-user)
                export PLATFORM_USER=$2; shift 2
                ;;
            --platform-user-password)
                export PLATFORM_USER_PASSWORD=$2; shift 2
                ;;
            --platform-mysql-ip)
                export PLATFORM_MYSQL_IP=$2; shift 2
                ;;
            --platform-mysql-user)
                export PLATFORM_MYSQL_USER=$2; shift 2
                ;;
            --platform-mysql-user-password)
                export PLATFORM_MYSQL_USER_PASSWORD=$2; shift 2
                ;;
            --appagt-ip)
                export APPAGT_IP=$2; shift 2
                ;;
            --appagt-mysql-ip)
                export APPAGT_MYSQL_IP=$2; shift 2
                ;;
            --appagt-mysql-user)
                export APPAGT_MYSQL_USER=$2; shift 2
                ;;
            --appagt-mysql-user-password)
                export APPAGT_MYSQL_USER_PASSWORD=$2; shift 2
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

    [ -z "$SERVICE_INSTANCE" ] && echo "--client argument missing" && usage
    [ -z "$LOGSTASH_HTTP_USER" ] && echo "--logstash-user argument missing" && usage
    [ -z "$LOGSTASH_HTTP_USER_PASSWORD" ] && echo "--logstash-password argument missing" && usage

    if [ "$RHUB" == "prod" ]; then
        export LOGSTASH_ADDRESS="logstash-ext.prod.aparavi.com"
        export VM_EXTERNAL_URL="https://vm-ext.prod.aparavi.com"
        [ -z "$ENVIRONMENT"] && export ENVIRONMENT=prod-onprem
    elif [ "$RHUB" == "nonprod" ]; then
        export LOGSTASH_ADDRESS="logstash-ext.paas.aparavi.com"
        export VM_EXTERNAL_URL="https://vm-ext.paas.aparavi.com"
        [ -z "$ENVIRONMENT"] && export ENVIRONMENT=nonprod-onprem
    else
        echo "Invalid argument $RHUB, should be prod or nonprod" && usage
    fi

    echo "Monitoring install options:"
    echo "  ENVIRONMENT=$ENVIRONMENT"
    echo "  SERVICE_INSTANCE=$SERVICE_INSTANCE"
    echo "  VM_EXTERNAL_URL=$VM_EXTERNAL_URL"

    echo "  LOGSTASH_ADDRESS=$LOGSTASH_ADDRESS"
    echo "  LOGSTASH_HTTP_USER=$LOGSTASH_HTTP_USER"
    echo "  LOGSTASH_HTTP_USER_PASSWORD=$(print_pass $LOGSTASH_HTTP_USER_PASSWORD)"

    echo "  PLATFORM_IP=$PLATFORM_IP"

    echo "  PLATFORM_URL=$PLATFORM_URL"
    echo "  PLATFORM_USER=$PLATFORM_USER"
    echo "  PLATFORM_USER_PASSWORD=$(print_pass $PLATFORM_USER)"

    echo "  PLATFORM_MYSQL_IP=$PLATFORM_MYSQL_IP"
    echo "  PLATFORM_MYSQL_USER=$PLATFORM_MYSQL_USER"
    echo "  PLATFORM_MYSQL_USER_PASSWORD=$(print_pass $PLATFORM_MYSQL_USER_PASSWORD)"

    echo "  APPAGT_IP=$APPAGT_IP"
    echo "  APPAGT_MYSQL_IP=$APPAGT_MYSQL_IP"
    echo "  APPAGT_MYSQL_USER=$APPAGT_MYSQL_USER"
    echo "  APPAGT_MYSQL_USER_PASSWORD=$(print_pass $APPAGT_MYSQL_USER_PASSWORD)"

    return 0
}

# Exit immediately if an any command exits with a non-zero status
set -e

cd "$(dirname "$0")"

###### install OS prereqs ######
. ./install_prerequisites.sh

# Defaults
export MONITORING_DEST_DIR="/opt/aparavi/monitoring"
export RHUB="prod"
export PLATFORM_IP="$(get_local_ip)"
export PLATFORM_MYSQL_IP="${PLATFORM_IP}"

# Parse command line args
get_args "$@"

# Install monitoring
pipenv run ansible-playbook \
    --connection=local \
    -i 127.0.0.1, \
    -i ../../ansible/inventories/_globals \
    --skip-tags atop,filebeat \
    -e "env=${ENVIRONMENT}" \
    -e "service_instance=${SERVICE_INSTANCE}" \
    -e "logstash_address=${LOGSTASH_ADDRESS}" \
    -e "logstash_http_user=${LOGSTASH_HTTP_USER}" \
    -e "logstash_http_user_password=${LOGSTASH_HTTP_USER_PASSWORD}" \
    -e "prometheus_mysqld_exporter_tls=false" \
    -e "vector_https_proxy=${HTTPS_PROXY:-$https_proxy}" \
    -e "mysql_hostname=${PLATFORM_MYSQL_IP}" \
    -e "mysql_username=${PLATFORM_MYSQL_USER}" \
    -e "mysql_password=${PLATFORM_MYSQL_USER_PASSWORD}" \
    -e "mysql_get_creds_from_aparavi_config=$([ -z "$PLATFORM_MYSQL_USER" ] && echo "true" || echo "false")" \
    ./playbooks/monitoring/main.yml

# Install docker
pipenv run ansible-playbook \
    --connection=local \
    -i 127.0.0.1, \
    -e "docker_https_proxy=${HTTPS_PROXY:-$https_proxy}" \
    ./playbooks/monitoring/docker.yml

echo "### Copying docker-compose files..."
mkdir -p "${MONITORING_DEST_DIR}" 2>/dev/null
cp -r monitoring/. "${MONITORING_DEST_DIR}/"
chown -R root:root "${MONITORING_DEST_DIR}"
chmod -R u=rwX,g=rwX,o= "${MONITORING_DEST_DIR}/"

echo "### Templating docker-compose files..."
pipenv run find "${MONITORING_DEST_DIR}" \
    -name '*.j2' \
    -type f \
    -exec sh -c \
    'jinja -E MONITORING_DEST_DIR -E https_proxy -E HTTPS_PROXY -E ENVIRONMENT -E SERVICE_INSTANCE -X "^(PLATFORM|APPAGT|VM)_" "$1" -o "${1%.*}";rm "$1"' _ {} \;

echo "### Starting docker-compose"
docker compose -f "${MONITORING_DEST_DIR}/docker-compose.yml" up -d --remove-orphans --build
docker compose -f "${MONITORING_DEST_DIR}/docker-compose.yml" ps

echo "### Checking monitoring status..."
VMAGENT_OUTPUT=/tmp/vmagent.output
for i in {1..15}; do
    curl --noproxy '*' -s http://localhost:8429/targets -o ${VMAGENT_OUTPUT}
    grep -q "down" ${VMAGENT_OUTPUT} || break
    sleep 3
done
sed -i ''/up/s//`printf "\033[32mup\033[0m"`/''  ${VMAGENT_OUTPUT}
sed -i ''/down/s//`printf "\033[31mdown\033[0m"`/''  ${VMAGENT_OUTPUT}
cat ${VMAGENT_OUTPUT}
rm ${VMAGENT_OUTPUT} 2>/dev/null

echo "### Monitoring installed"
