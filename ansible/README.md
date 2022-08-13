# Ansible Arch Install (WIP)

An attempt to use ansible for the installation of Arch Linux. **WIP!!**

## Usage

### Install ansible and git

```bash
loadkeys de-latin1
mount -o remount,size=2G /run/archiso/cowspace
sudo pacman -Sy git ansible python-pip
```

### Clone this repository

```bash
git -c http.sslVerify=false clone [URL]
```

### Install Ansible dependencies

```bash
ansible-galaxy install -r requirements.yml
```

### Provisioning

```bash
ansible-playbook -i ./inventory/localhost ./playbooks/install-setup.yml
ansible-playbook -i ./inventory/localhost -e '{ "ansible_python_interpreter": "/tmp/chroot_wrapper"}' ./playbooks/install-chroot.yml
```
