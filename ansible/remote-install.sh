#!/bin/bash

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    cat <<EOF
Description:

    '`basename $0`' is a script to remote install arch linux via ansible

Dependecies:

    - ansible


Precodndition:

    ```bash
    systemctl start sshd
    passwd
    ip a
    ```

Usage:

    `basename $0` [IP]
EOF
    exit $1
}

error() {
    echo -e "${RED}ERROR: $1${NC}\n"
    usage -1
}

IP="$1"
[ -z "$IP" ] && error "Invalid arguments"
[ "$IP" = "-h" ] && usage 0
[ "$IP" = "--help" ] && usage 0
[ "$IP" = "help" ] && usage 0
[ -z "$(echo "$IP" | awk '/^([0-9]{1,3}[.]){3}([0-9]{1,3})$/{print $1}')" ] && error "Invalid IP"

tmp_dir=$(mktemp -d)

close() {
    rm -rf $tmp_dir
}
trap close SIGHUP SIGINT SIGTERM EXIT

echo "Remote IP: $IP"
echo "Temp Directory: $tmp_dir"

ansible-galaxy install -r requirements.yml

ssh-keygen -a 100 -t ed25519 -f ${tmp_dir}/ansible -N "" -C ""
ssh-copy-id -i ${tmp_dir}/ansible.pub root@${IP}

cat >${tmp_dir}/inventory <<EOL
[archlinux]
archlinux-01 ansible_host=${IP} ansible_user=root ansible_connection=ssh ansible_ssh_private_key_file=${tmp_dir}/ansible
EOL

echo "Installation configuration:"
cat ./playbooks/group_vars/*

while true; do
    echo -en "\nEnter user password: " && read -s user_passphrase
    echo -en "\nVerify password: " && read -s user_passphrase_verify

    if [ "$user_passphrase" == "$user_passphrase_verify" ] && [ -n "$user_passphrase" ]; then
        break
    else
        echo -e "${RED}\nERROR: password does not match${NC}"
    fi
done

ssh root@$IP -i "${tmp_dir}/ansible" 'lsblk'

ansible-playbook \
    -i ${tmp_dir}/inventory \
    ./playbooks/install-setup.yml

[ $? -ne 0 ] && error "Installation failed"

ansible-playbook \
    -i ${tmp_dir}/inventory \
    -e '{ "ansible_python_interpreter": "/tmp/chroot_wrapper", "user_password": "'$user_passphrase'"}' \
    ./playbooks/install-chroot.yml

[ $? -ne 0 ] && error "Installation failed"

echo -e "${GREEN}OK: Installation completed${NC}"
