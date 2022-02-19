# Arch Linux - SSD (NVME), UEFI, LUKS, BTRFS

**This is not a universal installation script**. It is my Arch Linux installation script for a system suitable for everyday use. I make it public available because other public repositories helped me a lot when I switched to Arch Linux. I hope this repository helps you too. If you want to install an Arch Linux reproducibly on a system I recommend to create a personal installation script like this one.

The script is for a UEFI installation with fully encrypted NVME disk (LUKS) including `boot`. `boot` is on the same btrfs subvolume to allow a very easy rollback. I have experimented a lot with this in the past. This solution seems to be the best solution available. The only drawback is that no remote unlock (SSH) on boot is possible for the encrypted system. (In such a case boot would have to be unencrypted on a separate partition, which destroys the advantage of the simple rollback)

## Easy Backup and Restore by BTRFS

### Create RW System Snapshots:

```bash
sudo btrfs subvolume snapshot / /.snapshots/$(date +%Y-%m-%d)
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Read-Write (RW) and Read-Only snapshots are directly bootable in [grub-btrfs](https://github.com/Antynea/grub-btrfs). A first RW snapshot is created in the installer which serves as a universal recovery system. I use [snapper](https://wiki.archlinux.org/index.php/Snapper) with [pacman hook](https://github.com/wesbarnett/snap-pac) which automatically creates a pre and post **read only** system snapshot before and after pacman transactions. To rollback such a snapshot you have to create an RW snapshot from the read only snapshot.

### Restore System from Read-Only Snapshot

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

## Maintenance

To keep your btrfs volume clean and ensure data integrity you should execute scrubbing and balancing once per year.

### Scrubbing

This checks all checksums and corrects possible errors by using redundant copy from an btrfs RAID1 configuration. If no RAID1 configuration exists an error is printed. This is the main mechanism against bitrot. This process needs a long time and is really I/O heavy!

Scrubbing control commands:

```bash
sudo btrfs scrub start /path/to/an/mounted/btrfs-volume
sudo btrfs scrub status /path/to/an/mounted/btrfs-volume
sudo btrfs scrub cancel /path/to/an/mounted/btrfs-volume
sudo btrfs scrub resume /path/to/an/mounted/btrfs-volume
```

### Balancing

Commands to rebalance blocks (data/metadata) with less then 80% usage:

```bash
sudo btrfs balance start -dusage=80 /path/to/an/mounted/btrfs-volume
sudo btrfs balance start -musage=80 /path/to/an/mounted/btrfs-volume

```

## Replace failed disk

See: [Using Btrfs with Multiple Devices](https://btrfs.wiki.kernel.org/index.php/Using_Btrfs_with_Multiple_Devices#Replacing_failed_devices)
