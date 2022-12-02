#!/bin/bash

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


lsblk
echo "loading ..."
nix-shell -p ansible --run "ansible-playbook -i ./inventory/localhost ./playbooks/install-nixos.yml"
if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Installation failed${NC}"
    exit 1
fi

echo -e "${GREEN} OK: Installation complete${NC}"
