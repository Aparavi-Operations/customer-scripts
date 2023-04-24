#!/bin/bash

set -e

cd "$(dirname "$0")"

### for servers without sshd service
[[ -f "/etc/ssh/ssh_host_ecdsa_key" ]] || ssh-keygen -A
[[ -d "/run/sshd" ]] || mkdir -p /run/sshd

if command -v dnf >/dev/null; then
    dnf install git sshpass python38 rsyslog -y
    update-alternatives --set python "/usr/bin/python3.8"
    pip3 install --upgrade pip pipenv
else
    sed -i 's/deb cdrom/#deb cdrom/' /etc/apt/sources.list
    apt update
    apt install git sshpass vim python3-mysqldb gnupg2 pipenv python3-cryptography -y
fi

if ! command -v pipenv >/dev/null; then
  # Tweak PATH for root user - helps in some situations
  export PATH=$PATH:/usr/local/bin
fi

###### Install Pipenv ######
pipenv install --skip-lock

###### Install public collection ######
pipenv run ansible-galaxy collection install -r requirements.yml
