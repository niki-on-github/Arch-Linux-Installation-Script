# Arch Linux - SSD (NVME), UEFI, LUKS, BTRFS

**This is not a universal installation script**. It is my arch linux installation script. I make it public available because other public repositories helped me a lot when I switched to Arch Linux. I hope this repository helps you too. If you want to install an Arch Linux reproducibly on a system I recommend to create a personal installation script like this one.

The script is for a UEFI installation with fully encrypted NVME disk (LUKS) including `boot`. `boot` is on the same btrfs subvolume to allow a very easy rollback. I have experimented a lot with this in the past. This solution seems to be the best solution available. The only drawback is that no remote unlock (SSH) on boot is possible for the encrypted system. (In such a case boot would have to be unencrypted on a seperate partition, which destroys the advantage of the simple rollback)

## Easy Backup and Restore by BTRFS

### Create RW System Snapshots (Optional)

```bash
sudo btrfs subvolume snapshot / /.snapshots/$(date +%Y-%m-%d)
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

RW snapshots are directly bootable in [grub-btrfs](https://github.com/Antynea/grub-btrfs). A first RW snapshot is created in the installer which serves as a universal recovery system. I use [snapper](https://wiki.archlinux.org/index.php/Snapper) with [pacman hook](https://github.com/wesbarnett/snap-pac) which automatically creates a pre and post read only system snapshot before and after pacman transactions. To rollback such a snapshot you have to create an RW snapshot from the read only snapshot (see Restore System from Snapshot).

### Restore System from Snapshot

Additional step which is necessary if system and snapshots are not bootable. Open crypt device (e.g use Arch Linux ISO from PXE Server):

```bash
lsblk
cryptsetup open --type luks1 /dev/disk/by-partlabel/root system
```

Restore system:

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

**NOTE:** replace `$SNAPSHOT` with your snapshot directory name <br>
**NOTE:** The installer create the script /usr/bin/btrfs-system-recover to perform a system restore <br>

Reset user (Optional) - only intended for non-productive systems:

```bash
su $username
sudo rm -rf /home/$username/{*,.*}
cp -rT /etc/skel/ /home/$username/
```

