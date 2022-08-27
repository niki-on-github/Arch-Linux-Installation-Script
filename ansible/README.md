# Ansible Arch Install

Ansible playbook for deploying a new Arch Linux System with encrypted disk and btrfs filesystem suitable for a server and desktop base installation.

## Usage

### Installation from booted arch install medium

```bash
loadkeys de-latin1  # set keyboard language
sudo pacman -Sy git
git -c http.sslVerify=false clone [URL]
cd [REPO_DIR]
bash install-local.sh
```

### Remote Installation

On booted arch install medium run:

```bash
systemctl start ssh
passwd
ip a
```

On remote computer use `bash install-remote.sh [IP]` to deploy the Arch Linux System.
