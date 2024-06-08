# My Arch Linux installer

> [!IMPORTANT]  
> I switched to NixOS for all my devices. Therefore this repository is not longer used.

**This is not a universal installation script**. It is my Arch Linux and NixOS installation script for a system suitable for everyday use. I make it public available because other public repositories helped me a lot when I switched to Arch Linux. I hope this repository helps you too. If you want to install an Arch Linux reproducibly on a system I recommend to create a personal installation script like this one.

The install script is for a UEFI installation with fully encrypted NVME disk (LUKS) including `boot`. `boot` is on the same btrfs subvolume to allow a very easy rollback. I have experimented a lot with this in the past. This solution seems to be the best solution available. The only drawback is that no remote unlock (SSH) on boot is possible for the encrypted system. (In such a case boot would have to be unencrypted on a separate partition, which destroys the advantage of the simple rollback).

In NixOS a rollback feature is directly implemented into the system. The btrfs rollback implementation is not required. However, the other features of btrfs like file checksums, cow, ... are indispensable for me which is why I also put nixos on btrfs.

## Arch Linux

### Easy Backup and Restore by BTRFS

#### Create RW System Snapshots:

```bash
sudo btrfs subvolume snapshot / /.snapshots/$(date +%Y-%m-%d)
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Read-Write (RW) and Read-Only snapshots are directly bootable in [grub-btrfs](https://github.com/Antynea/grub-btrfs). A first RW snapshot is created in the installer which serves as a universal recovery system. I use [snapper](https://wiki.archlinux.org/index.php/Snapper) with [pacman hook](https://github.com/wesbarnett/snap-pac) which automatically creates a pre and post **read only** system snapshot before and after pacman transactions. To rollback such a snapshot you have to create an RW snapshot from the read only snapshot.

#### Restore System from Read-Only Snapshot

The installer create the script `/usr/bin/btrfs-system-recover` to perform a easy system restore from [snapper](https://wiki.archlinux.org/index.php/Snapper) system snapshots. You can boot any snapshot from grub and use this script to restore the system on the main partition (default grub boot entry).

### System Maintenance

To keep your btrfs volume clean and ensure data integrity you should execute scrubbing and balancing once per year.

#### Scrubbing

This checks all checksums and corrects possible errors by using redundant copy from an btrfs RAID1 configuration. If no RAID1 configuration exists an error is printed. This is the main mechanism against bitrot. This process needs a long time and is really I/O heavy!

Scrubbing control commands:

```bash
sudo btrfs scrub start /path/to/an/mounted/btrfs-volume
sudo btrfs scrub status /path/to/an/mounted/btrfs-volume
sudo btrfs scrub cancel /path/to/an/mounted/btrfs-volume
sudo btrfs scrub resume /path/to/an/mounted/btrfs-volume
```

#### Balancing

Commands to rebalance blocks (data/metadata) with less then 80% usage:

```bash
sudo btrfs balance start -dusage=80 /path/to/an/mounted/btrfs-volume
sudo btrfs balance start -musage=80 /path/to/an/mounted/btrfs-volume
```
