#!/bin/bash

read -p "This script will remove Aparavi components!!! Are you sure (Y/N)? "
if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo "### Stopping services"
systemctl stop mysqld vector docker.service docker.socket
systemctl disable --now node_exporter prometheus-mysqld-exporter

echo "### Uninstalling Aparavi Platform"
/opt/aparavi-data-ia/platform/app/uninstall

echo "### Removing obsolete apt packages"
if command -v dnf; then
  dnf remove redis-server mysql-server pipenv containerd.io docker-ce vector docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-ce-cli docker-compose-plugin -y
else
  apt purge redis-server mysql-server pipenv docker-ce vector docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-ce-cli docker-compose-plugin -y
  apt autoremove -y
fi

echo "### Cleaning obsolete files"
rm -rf \
  /etc/redis \
  /etc/vector \
  /etc/yum.repos.d/timber-vector.repo \
  /opt/aparavi \
  /opt/aparavi-data-ia \
  /root/.ansible \
  /root/.dia \
  /root/.docker \
  /root/.my.cnf \
  /root/.mysql_history \
  /root/.virtualenvs \
  /tmp/pipenv-* \
  /var/lib/docker \
  /var/lib/mysql* \
  /var/lib/vector \
  /var/log/aparavi-* \
  /var/log/mysql* \
  /var/run/docker \
  /var/run/docker.sock \
  2> /dev/null
