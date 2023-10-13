download() {
  # $1 - url
  # $2 - destination file name
  # $3 - file checksum
  wget -O $2 $1

  [ $? == 0 ] || (echo "!!! ${1} download failed !!!"; exit 1)

  if [ $# == 3 ]; then
    echo "${3} ${2}" | sha256sum --check --status
    [ $? == 0 ] || (echo "!!! ${2} checksum verification failed !!!"; exit 1)
  fi

  return 0
}

set_file_perms() {
  # $1 - file path
  # $2 - owner
  # $3 - mode
  sudo chown $2 $1
  sudo chmod $3 $1
}

mysql_debian_install() {
  # $1 root password
  # $2 data dir path
  echo -e "###### Installing MySQL ######\n"
  [ $# == 2 ] && ln -s $2 /var/lib/mysql
  export DEBIAN_FRONTEND="noninteractive";
  sudo apt-get update
  sudo -E apt-get install -y debconf-utils
  echo mysql-apt-config mysql-apt-config/select-server select mysql-8.0 | sudo -E debconf-set-selections;
  sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${1}"
  sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${1}"
  [ -d "downloads" ] || mkdir downloads
  wget -O downloads/mysql-apt-config.deb https://dev.mysql.com/get/mysql-apt-config_0.8.22-1_all.deb
  sudo -E apt-get install -y ./downloads/mysql-apt-config.deb
  sudo -E apt-get update
  sudo -E apt-get install -y mysql-server
  sudo mysql_secure_installation -p${1} --use-default
  echo -e "###### Installing MySQL COMPLETE ######\n"
}

# parameters
# 1 - filebeat version
filebeat_install() {
  [[ $# < 1 ]] && FILEBEAT_VER='7.17.9' || FILEBEAT_VER=$1
  echo -e "###### Setting up filebeat version ${FILEBEAT_VER} ######\n"
  # install requirements
  sudo apt install -y apt-transport-https gnupg2
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  [[ -f /etc/apt/sources.list.d/elastic-7.x.list ]] || (echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list)
  sudo apt-mark unhold filebeat || true
  sudo apt-get update && sudo apt-get install -y --allow-downgrades filebeat=$FILEBEAT_VER
  sudo apt-mark hold filebeat
  echo -e "###### Filebeat version ${FILEBEAT_VER} setup COMPLETE ######\n"
}

# parameters
# 1 - application type (aggregator/collector/appagent)
# 2 - application folder name (differs from type name)
# 3 - service instance name
# 4 - environment name
# 5 - logstash endpoint
filebeat_configure() {
  echo -e "###### Configuring filebeat ######\n"
  [[ $# < 3 ]] && (echo "Insufficient filebeat configuration parameters passed!"; exit 1)
  SERVICE_TYPE=$1
  SERVICE_FOLDER=$2
  SERVICE_CLIENT=$3
  ENV=$4
  LOGSTASH=$5
  sudo -E sh -c "envsubst < $(get_lib_path)/templates/filebeat.conf > /etc/filebeat/filebeat.yml"
  sudo -E cp $(get_lib_path)/templates/rsyslog-59-filters.conf /etc/rsyslog.d/59-filters.conf
  sudo -E cp $(get_lib_path)/templates/rsyslog-60-forward-to-filebeat.conf /etc/rsyslog.d/60-forward-to-filebeat.conf
  sudo systemctl enable --now filebeat
  sudo systemctl restart filebeat
  echo -e "###### Configuring filebeat COMPLETE ######\n"
}

# parameters
# 1 - prometheus node exporter version
prometheus_node_exporter_install() {
  [[ $# < 1 ]] && NODE_EXP_VER='1.6.0' || NODE_EXP_VER=$1
  echo -e "###### Setting up Node exporter version ${NODE_EXP_VER} ######\n"
  manage_user_group node-exp
  [[ -d "node_exporter" ]] || mkdir node_exporter
  [ -d "downloads" ] || mkdir downloads
  download "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXP_VER}/node_exporter-${NODE_EXP_VER}.linux-amd64.tar.gz" downloads/node_exporter.tar.gz
  tar xzf downloads/node_exporter.tar.gz --strip-components 1 -C node_exporter
  sudo mv node_exporter/node_exporter /usr/local/bin/node_exporter
  rm -rf node_exporter
  set_file_perms "/usr/local/bin/node_exporter" "root:root" "0755"
  echo -e "###### Node exporter version ${NODE_EXP_VER} setup COMPLETE ######\n"
}

prometheus_node_exporter_configure() {
  echo -e "###### Configuring Node exporter ######\n"
  sudo cp $(get_lib_path)/templates/node_exporter.service /etc/systemd/system/node_exporter.service
  set_file_perms "/etc/systemd/system/node_exporter.service" "root:root" "0644"
  sudo systemctl daemon-reload
  sudo systemctl enable --now node_exporter
  sudo systemctl restart node_exporter
  echo -e "###### Configuring Node exporter COMPLETE ######\n"
}

# parameters
# 1 - prometheus mysqld exporter version
prometheus_mysqld_exporter_install() {
  [[ $# < 1 ]] && MYSQLD_EXP_VER='0.14.0' || MYSQLD_EXP_VER=$1
  echo -e "###### Setting up Mysqld exporter version ${MYSQLD_EXP_VER} ######\n"
  manage_user_group mysqld-exp
  [ -d "mysqld_exporter" ] || mkdir mysqld_exporter
  [ -d "downloads" ] || mkdir downloads
  download "https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXP_VER}/mysqld_exporter-${MYSQLD_EXP_VER}.linux-amd64.tar.gz" downloads/mysqld_exporter.tar.gz
  tar xzf downloads/mysqld_exporter.tar.gz --strip-components 1 -C mysqld_exporter
  sudo mv mysqld_exporter/mysqld_exporter /usr/local/bin/mysqld_exporter
  rm -rf mysqld_exporter
  echo -e "###### Mysqld exporter version ${MYSQLD_EXP_VER} setup COMPLETE ######\n"
}

# parameters
# 1 - mysqld DB user
# 2 - mysqld DB password
prometheus_mysqld_exporter_configure() {
  [[ $# < 2 ]] && (echo "mysqld credentials were not provided!"; exit 1)
  export MYSQLD_USER=$1
  export MYSQLD_PASS=$2
  echo -e "###### Configuring Mysqld exporter ######\n"
  sudo cp $(get_lib_path)/templates/mysqld_exporter.service /etc/systemd/system/mysqld_exporter.service
  sudo -E sh -c "envsubst < $(get_lib_path)/templates/mysqld_exporter.env > /etc/default/mysqld_exporter"
  set_file_perms "/etc/systemd/system/mysqld_exporter.service" "root:root" "0644"
  set_file_perms "/etc/default/mysqld_exporter" "root:root" "0640"
  sudo systemctl daemon-reload
  sudo systemctl enable --now mysqld_exporter
  sudo systemctl restart mysqld_exporter
  echo -e "###### Configuring Mysqld exporter COMPLETE ######\n"
}

# creates user and group
# uses 1 parameter as user and group names
manage_user_group() {
  [[ $# < 1 ]] && (echo "No user/group name passed!"; exit 1)
  [[ $(getent group $1) ]] || sudo groupadd --system $1
  id "$1" >/dev/null 2>&1 || sudo useradd -s /sbin/nologin --system -g $1 $1
}

# parameters
# 1 - vmagent version
vmagent_install() {
  [[ $# < 1 ]] && VMAGENT_VER='1.87.5' || VMAGENT_VER=$1
  echo -e "###### Setting up VictoriaMetrics agent version ${VMAGENT_VER} ######\n"
  manage_user_group vmagent
  [ -d "downloads" ] || mkdir downloads
  download "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VMAGENT_VER}/vmutils-linux-amd64-v${VMAGENT_VER}.tar.gz" downloads/vmutils.tar.gz
  sudo tar xzf downloads/vmutils.tar.gz -C /usr/local/bin
  set_file_perms "/usr/local/bin/vm*-prod" "root:root" "0755"
  echo -e "###### VictoriaMetrics agent version ${VMAGENT_VER} setup COMPLETE ######\n"
}

get_lib_path() {
  SCRIPT=$(readlink -f "$0")
  echo "$(dirname "$SCRIPT")/lib"
}

# parameters:
# 1 - service client
# 2 - environment name
# 3 - VM endpoint
vmagent_configure() {
  SERVICE_CLIENT=$1
  ENV=$2
  VM_ENDPOINT=$3
  [[ $# < 3 ]] && (echo "Insufficient VM configuration parameters passed!"; exit 1)
  echo -e "###### Configuring VictoriaMetrics agent ######\n"
  sudo mkdir -p /etc/vm/vmagent
  set_file_perms "/etc/vm" "vmagent:vmagent -R" "0750"
  sudo -E sh -c "envsubst < $(get_lib_path)/templates/vmagent_scrape_aparavi_local.yml > /etc/vm/vmagent/scrape_aparavi_local.yml"
  sudo -E sh -c "envsubst < $(get_lib_path)/templates/vmagent.conf > /etc/vm/vmagent/vmagent.yml"
  sudo -E sh -c "envsubst < $(get_lib_path)/templates/vmagent.service > /etc/systemd/system/vmagent.service"
  set_file_perms "/etc/systemd/system/vmagent.service" "root:root" "0644"
  set_file_perms "/etc/vm/vmagent/vmagent.yml" "vmagent:vmagent" "0640"
  set_file_perms "/etc/vm/vmagent/scrape_aparavi_local.yml" "vmagent:vmagent" "0640"
  sudo systemctl daemon-reload
  sudo systemctl enable --now vmagent
  sudo systemctl restart vmagent
  echo -e "###### Configuring VictoriaMetrics agent COMPLETE ######\n"
}