# Ansible Arch & NixOS Install Playbooks

Ansible and NixOS playbook for deploying a new `Arch Linux` / `NixOS` System with encrypted disk and btrfs filesystem suitable for a server and desktop base installation.

## Arch Linux

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

## NixOS

First adjust the variables in `./playbooks/group_vars`. Then call the install script. You have 2 options. Install NixOS from booted install medium or use an remote pc to install NixOS.

### Installation from booted NixOS install medium

1. Get git on install medium with: `nix-shell -p git`
2. Clone repo with `git -c http.sslVerify=false clone [URL]`
3. Run install script with `bash install-nixos-local.sh`

### Remote Installation

On booted NixOS install medium run:

```bash
passwd
ip a
```

On remote computer use `bash install-nixos-remote.sh [IP]` to deploy the NixOS System.

### Next Steps

The playbook is mainly used to set up the partition layout and the encrypted luks containers. Everything else is managed by the nix files. To get a bootable system, a minimal configuration in `/etc/nixos` is created.

The next step would be to load his nixos flakes configuration from a git repository, adjust the hardware config and build the nixos system.
