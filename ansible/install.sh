#!/bin/bash

if command -v pacman; then
    pacman -Sy ansible python-pip
fi

ansible-galaxy install -r requirements.yml

ansible-playbook -i ./inventory/localhost ./playbooks/install-setup.yml
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

ansible-playbook -i ./inventory/localhost -e '{ "ansible_python_interpreter": "/tmp/chroot_wrapper"}' ./playbooks/install-chroot.yml
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

echo "Installation complete"
