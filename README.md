# Arch Linux - SSD (NVME), UEFI, LUKS, BTRFS

**This is not a universal installation script**. It is my arch linux installation script. I make it public available because other public repositories helped me a lot when I switched to Arch Linux. I hope this repository helps you too. If you want to install an Arch Linux more than once a month I recommend to create a personal installation script like this one.

The script is for a UEFI installation with fully encrypted hard disk (LUKS) including boot on a SSD (NVME). Also boot is on the same btrfs subvolume to allow a very easy rollback. I have experimented a lot with this in the past. This solution seems to be the best solution available. The only drawback is that no remote unlock (SSH) on boot is possible for the encrypted system. (In such a case boot would have to be unencrypted on a seperate partition, which destroys the advantage of the simple rollback)

## Easy Backup and Restore by BTRFS

### Create RW System Snapshot

```bash
sudo btrfs subvolume snapshot / /.snapshots/$(date +%Y-%m-%d)
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

RW snapshots are directly bootable in grub-btrfs. A first RW snapshot is created in the installer which serves as a recovery system. I use snapper with pacman hook which automatically creates read only snapshots. To rollback such a snapshot I use this first RW snapshot as recovery system.

### Restore System from Snapshot

Additional step which is necessary if the first RW recovery system snapshot is not used. Open crypt device (e.g use Arch Linux ISO from PXE Server):

```bash
lsblk
cryptsetup open --type luks1 /dev/disk/by-partlabel/root secure
```

Restore system:

```bash
mkdir -p /mnt/btrfs-root
mount -t btrfs /dev/mapper/secure /mnt/btrfs-root
rm -rf /mnt/btrfs-root/@root/*
btrfs subvolume delete /mnt/btrfs-root/@root
btrfs subvolume snapshot /mnt/btrfs-root/@snapshots/$SNAPSHOT/snapshot /mnt/btrfs-root/@root
rm -f /mnt/btrfs-root/@root/var/lib/pacman/db.lck
reboot
```
