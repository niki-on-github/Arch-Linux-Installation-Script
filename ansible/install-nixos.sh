#!/bin/bash

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    cat <<EOF
Description:

    '`basename $0`' is a script to remote install nixos via ansible

Dependecies:

    - ansible


Precondition:

    nix-env -iA nixos.python310
    systemctl start sshd
    passwd
    ip a

Usage:

    `basename $0` [IP]
EOF
    exit $1
}

error() {
    echo -e "${RED}ERROR: $1${NC}\n"
    usage 1
}

IP="$1"
[ -z "$IP" ] && error "Invalid arguments"
[ "$IP" = "-h" ] && usage 0
[ "$IP" = "--help" ] && usage 0
[ "$IP" = "help" ] && usage 0
[ -z "$(echo "$IP" | awk '/^([0-9]{1,3}[.]){3}([0-9]{1,3})$/{print $1}')" ] && error "Invalid IP"

echo "Ping $IP..."
ping -c 1 -W 2 $IP >/dev/null || error "Device not found!"

tmp_dir=$(mktemp -d)

close() {
    rm -rf $tmp_dir
}
trap close SIGHUP SIGINT SIGTERM EXIT

echo "Remote IP: $IP"
echo "Temp Directory: $tmp_dir"

ansible-galaxy install -r requirements.yml

ssh-keygen -a 100 -t ed25519 -f ${tmp_dir}/ansible -N "" -C ""
ssh-copy-id -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' -i ${tmp_dir}/ansible.pub nixos@${IP}

cat >${tmp_dir}/inventory <<EOL
[nixos]
nixos-01 ansible_host=${IP} ansible_user=nixos ansible_connection=ssh ansible_ssh_private_key_file=${tmp_dir}/ansible
EOL

ssh -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' nixos@$IP -i "${tmp_dir}/ansible" 'lsblk'

ansible-playbook \
    -i ${tmp_dir}/inventory \
    ./playbooks/install-nixos.yml

[ $? -ne 0 ] && error "Installation failed"

echo -e "${GREEN}OK: Installation completed${NC}"
