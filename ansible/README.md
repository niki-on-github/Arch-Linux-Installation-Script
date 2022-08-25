# Ansible Arch Install

An attempt to use ansible for the installation of Arch Linux.

## Usage

```bash
loadkeys de-latin1
sudo pacman -Sy git
git -c http.sslVerify=false clone [URL]
cd [REPO]
bash local-install.sh
```
