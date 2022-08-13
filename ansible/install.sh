#!/bin/bash

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

while true; do
    echo -en "\nEnter user password: " && read -s user_passphrase
    echo -en "\nVerify password: " && read -s user_passphrase_verify

    if [ "$user_passphrase" == "$user_passphrase_verify" ] && [ -n "$user_passphrase" ]; then
        echo -e "\n${GREEN}OK ${NC}" && break
    else
        echo -e "${RED}\n[ERROR] password does not match! ${NC}"
    fi
done

mount -o remount,size=2G /run/archiso/cowspace
pacman -Sy --noconfirm --needed ansible python-pip
ansible-galaxy install -r requirements.yml

ansible-playbook -i ./inventory/localhost ./playbooks/install-setup.yml
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

ansible-playbook -i ./inventory/localhost -e '{ "ansible_python_interpreter": "/tmp/chroot_wrapper", "user_password": "'$user_passphrase'"}' ./playbooks/install-chroot.yml
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

echo "Installation complete"
