# Ansible Arch Install (WIP)

An attempt to use ansible for the installation of Arch Linux.

## Usage

### Install ansible

```bash
sudo pacman -Sy ansible python-pip
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
