# Arch Linux install script

My bash install script to setup a Arch Linux System with encrypted disk and btrfs filesystem suitable for a server and desktop base installation.

### WARNING: The bash install script will not longer be maintained. I am using now the ansible playbook in this repository for my setups!

## Installation

1. Boot from Arch Linux UEFI Installationsmedium.
2. Start SSH server: `systemctl start sshd`.
3. Set SSH password for root user: `passwd`.
4. Get IP Address: `ìp a`.
5. From remote PC run `ssh root@IP` with password from step `3`
6. Install git: `pacman -Sy git`.
7. Clone Repository with git: `git clone https://github.com/niki-on-github/Arch-Linux-Installation-Script.git`.
8. Use vim to edit the configuration of the install script: `vim install.sh`.
9. Run the installer: `bash install.sh`.

### Troubleshoot

#### git installation fail

Sometimes i was not able to install git on the booted Arch Linux live environment. The following commands were required to get `git` installed:

```bash
killall gpg-agent
rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux
pacman -Syy git
```

## Restore System from Read-Only Snapshot

The installer create the script `/usr/bin/btrfs-system-recover` to perform a easy system restore from [snapper](https://wiki.archlinux.org/index.php/Snapper) system snapshots.

Manual instructions to restore system without my recover script:

```bash
mkdir -p /tmp/btrfs-recover
mount -t btrfs -o subvolid=0 /dev/mapper/system /tmp/btrfs-recover
rm -rf /tmp/btrfs-recover/@/{*,.*}
btrfs subvolume set-default /tmp/btrfs-recover
btrfs subvolume delete /tmp/btrfs-recover/@
btrfs subvolume snapshot /tmp/btrfs-recover/@snapshots/$SNAPSHOT/snapshot /tmp/btrfs-recover/@
rm -f /tmp/btrfs-recover/@/var/lib/pacman/db.lck
umount /tmp/btrfs-recover && rm -d /tmp/btrfs-recover
reboot
```

**NOTE:** Replace `$SNAPSHOT` with your snapshot directory name
