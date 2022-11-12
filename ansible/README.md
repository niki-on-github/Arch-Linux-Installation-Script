# Ansible Arch Install

Ansible playbook for deploying a new Arch Linux System with encrypted disk and btrfs filesystem suitable for a server and desktop base installation.

## Usage

First adjust the variables in `./playbooks/group_vars`. Then call the install script. You have 2 options. Install arch from booted install medium or use an remote pc to install arch linux.

### Installation from booted arch install medium

```bash
loadkeys de-latin1  # set keyboard language
sudo pacman -Sy git
git -c http.sslVerify=false clone [URL]
cd [REPO_DIR]
bash install-archlinux-local.sh
```

### Remote Installation

On booted arch install medium run:

```bash
systemctl start sshd
passwd
ip a
```

On remote computer use `bash install-archlinux-remote.sh [IP]` to deploy the Arch Linux System.
