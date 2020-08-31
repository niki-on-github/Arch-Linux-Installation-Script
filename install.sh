#!/bin/bash

##########################################################################################################
# SYSTEM GLOBAL CONFIGURATION
##########################################################################################################

LOCALE="de_DE.UTF-8"
MIRROR="Germany"
LANG="de_DE.UTF-8"
KEYMAP="de-latin1"
LOCALTIME="/usr/share/zoneinfo/Europe/Berlin"
INSTALL_PATH="/mnt/install"
PARTLABEL_BOOT="boot"
PARTLABEL_ROOT="root"
CRYPT_DEV_LABEL="system"
HOSTNAME="archlinux"
US_KEYBOARD_FOR_ENCRYPTION=0
CREATE_INSTALL_LOG=0
SSH_SERVER=0


##########################################################################################################
# BTRFS SUBVOLUME PATHS
##########################################################################################################

# NOTE: set paths without the first slash!
BTRFS_SYS_SUBVOLUME="@root"
BTRFS_SYS_SNAPSHOTS_SUBVOLUME="@snapshots"
BTRFS_VAR_LOG_SUBVOLUME="@log"
BTRFS_SWAP_SUBVOLUME="@swap"
BTRFS_HOME_SUBVOLUME="@home"


##########################################################################################################
# Color
##########################################################################################################

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'  # No Color


##########################################################################################################
# Package
##########################################################################################################

packages=( curl git vim openssh wget )


##########################################################################################################
# Init-Functions
##########################################################################################################

print_logo() {
   clear
   echo -e '\e[H\e[2J'
   echo -e '          \e[0;36m.'
   echo -e '         \e[0;36m/ \'
   echo -e '        \e[0;36m/   \      \e[1;37m               #     \e[1;36m| *'
   echo -e '       \e[0;36m/^.   \     \e[1;37m a##e #%" a#"e 6##%  \e[1;36m| | |-^-. |   | \ /'
   echo -e '      \e[0;36m/  .-.  \    \e[1;37m.oOo# #   #    #  #  \e[1;36m| | |   | |   |  X'
   echo -e '     \e[0;36m/  (   ) _\   \e[1;37m%OoO# #   %#e" #  #  \e[1;36m| | |   | ^._.| / \ \e[0;37mTM'
   echo -e '    \e[1;36m/ _.~   ~._^\'
   echo -e '   \e[1;36m/.^         ^.\ \e[0;37mTM'
   echo -e " "
}

get_uuid() {
    blkid -o export "$1" | grep "UUID" | grep -v "PARTUUID" | grep -v "UUID_SUB" | awk -F= '{print $2}'
}

partition_drive() {
   local device="$1"; shift
   echo -e "\n${LBLUE} >> Partition Drive ${NC}"

   echo -n "All data on $device will be deleted, continue? (Y/n) : " && read delete && delete=${delete:-Yes}
   [ $delete != "Yes" ] && [ $delete != "yes" ] && [ $delete != "Y" ] && [ $delete != "y" ] && exit 1

   for s in $(ls ${device}*); do
      echo -e "umount $s" && umount $s
   done

   wipefs --force --quiet --all $device >/dev/null 2>&1

   parted --script $device mklabel gpt
   parted --script $device mkpart primary 1MiB 512MiB name 1 $PARTLABEL_BOOT
   parted --script $device set 1 boot on
   parted --script $device mkpart primary 512MiB 100% name 2 $PARTLABEL_ROOT
}

enrypt_drive() {
   local crypt_dev="$1"; shift
   echo -e "\n${LBLUE} >> Encrypt Drive ${NC}"

   if [ "$KEYMAP" != "us" ]; then
      if [ "$US_KEYBOARD_FOR_ENCRYPTION" != "0" ]; then
         echo -e "[INFO] keyboard layout for password changed to us"
         echo -e "[INFO] do not use # key on german keyboard"
         loadkeys us
      else
         echo -e "Important note: In boot menu the keyboard layout could be us"
      fi
   fi

   while true; do
      echo -en "\nEnter passphrase for drive: " && read -s drive_passphrase
      echo -en "\nVerify passphrase for drive: " && read -s drive_passphrase_verify

      if [ "$drive_passphrase" == "$drive_passphrase_verify" ] && [ -n "$drive_passphrase" ]; then
         echo -e "\n${GREEN}OK ${NC}" && break
      else
         echo -e "${RED}\n[ERROR] passphrase does not match! ${NC}"
      fi
   done
   loadkeys $KEYMAP  # switch back

   # NOTE: The iteration count parameter are determined via benchmark upon key slot creation or update via `--iter-time`
   # parameter (default 2000 milliseconds). Unlocking from GRUB under tighter memory constraints doesn’t take advantage
   # of all crypto-related CPU instructions. That means unlocking a LUKS device from GRUB might take a lot longer than
   # doing it from the normal system. Since GRUB’s LUKS implementation isn’t able to benchmark, you’ll need to determine
   # the iteration count parameter manually via `luksChangeKey --pbkdf-force-iterations`. Wenn you change it you have to
   # make sure that the key stores in keyslot 0 to get the speed advantage. In most cases the key has to be changed 2
   # times to update keyslot 0.
   # NOTE: Halving the iteration count would speed up unlocking by a factor of two but making low entropy passphrases
   # twice as easy to brute-force!
   # EXAMPLE:
   # ```
   # # 1. change key (add new tmp key to next free key slot and remove keyslot 0)
   # cryptsetup luksChangeKey --pbkdf-force-iterations 500000 /dev/nvme0n1p2
   # # 2. show used key slots
   # cryptsetup luksDump /dev/nvme0n1p2
   # # 3. change key (add new key to now free keyslot 0 and remove tmp key from key slot n)
   # cryptsetup luksChangeKey --pbkdf-force-iterations 500000 /dev/nvme0n1p2
   # ```
   # SEE: https://cryptsetup-team.pages.debian.net/cryptsetup/encrypted-boot.html
   echo -en "$drive_passphrase" | cryptsetup luksFormat --type luks1 --pbkdf-force-iterations 500000 -s 512 -h sha512 ${crypt_dev}
   echo -en "$drive_passphrase" | cryptsetup open --type luks1 ${crypt_dev} $CRYPT_DEV_LABEL
}

# NOTE: internal btrfs helper function
create_btrfs_subvolume_recursive() {
   local btrfs_path="$1"; shift

   IFS='/'
   read -a str_arr <<< "$btrfs_path"
   subvol_path=""
   for subvol in "${str_arr[@]}"; do
      [ "$subvol" == "" ] && continue
      subvol_path="${subvol_path}/${subvol}"
      if [ ! -e "/mnt/btrfs-root$subvol_path" ]; then
         btrfs subvolume create "/mnt/btrfs-root${subvol_path}"
      fi
   done
   unset IFS
}

setup_filesystem() {
   local boot_dev="$1"; shift
   local root_dev="$1"; shift
   echo -e "\n${LBLUE} >> Setup Filesystem ${NC}"

   mkfs.vfat -F32 $boot_dev
   mkfs.btrfs -f -L "Arch Linux" $root_dev

   mkdir -p /mnt/btrfs-root
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo $root_dev /mnt/btrfs-root

   #NOTE: subvolumes inside subvolumes are excluded from snapshots
   create_btrfs_subvolume_recursive "$BTRFS_SYS_SUBVOLUME"
   create_btrfs_subvolume_recursive "$BTRFS_SYS_SNAPSHOTS_SUBVOLUME"
   create_btrfs_subvolume_recursive "$BTRFS_VAR_LOG_SUBVOLUME"
   create_btrfs_subvolume_recursive "$BTRFS_SWAP_SUBVOLUME"
   create_btrfs_subvolume_recursive "$BTRFS_HOME_SUBVOLUME"

   #NOTE: It is not possible to mount some subvolumes with 'nodatacow' and others with 'datacow'.
   # The mount option of the first mounted subvolume applies to any other subvolumes.
   # To disable copy-on-write for EMPTY directories do 'chattr +C /path'
   mkdir -p ${INSTALL_PATH}
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SUBVOLUME} $root_dev ${INSTALL_PATH}

   mkdir -p ${INSTALL_PATH}/.snapshots
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SNAPSHOTS_SUBVOLUME} $root_dev ${INSTALL_PATH}/.snapshots

   mkdir -p ${INSTALL_PATH}/var/log
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_VAR_LOG_SUBVOLUME} $root_dev ${INSTALL_PATH}/var/log

   mkdir -p ${INSTALL_PATH}/swap
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SWAP_SUBVOLUME} $root_dev ${INSTALL_PATH}/swap

   mkdir -p ${INSTALL_PATH}/home
   mount -t btrfs -o defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_HOME_SUBVOLUME} $root_dev ${INSTALL_PATH}/home

   mkdir -p ${INSTALL_PATH}/boot/efi
   mount -t vfat $boot_dev ${INSTALL_PATH}/boot/efi

   # create fstab
   mkdir -p ${INSTALL_PATH}/etc
   echo -e "# <uuid>  <path>  <fs>  <options>  <0>  <order>" > ${INSTALL_PATH}/etc/fstab

   local btrfs_dev_uuid=$(get_uuid "$root_dev")
   echo -e "UUID=${btrfs_dev_uuid} / btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SUBVOLUME} 0 0" >> ${INSTALL_PATH}/etc/fstab
   echo -e "UUID=${btrfs_dev_uuid} /var/log btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_VAR_LOG_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
   echo -e "UUID=${btrfs_dev_uuid} /home btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_HOME_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
   echo -e "UUID=${btrfs_dev_uuid} /.snapshots btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SNAPSHOTS_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
   echo -e "UUID=${btrfs_dev_uuid} /swap btrfs defaults,ssd,noatime,subvol=${BTRFS_SWAP_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab

   local boot_dev_uuid=$(get_uuid "$boot_dev")
   echo -e "UUID=${boot_dev_uuid} /boot/efi vfat defaults 0 2" >> ${INSTALL_PATH}/etc/fstab
}

update_mirrorlist() {
   echo -e "\n${LBLUE} >> Update Mirrorlist ${NC}"
   pacman --noconfirm -Sy reflector
   reflector --country "$MIRROR" -l 30 --sort rate --save /etc/pacman.d/mirrorlist
}

install_system() {
   echo -e "\n${LBLUE} >> Install System ${NC}"
   timedatectl set-ntp true

   base_packages=( base base-devel linux linux-firmware linux-headers btrfs-progs reflector nano sudo xdg-user-dirs nvme-cli )
   if lscpu -J | grep -q "Intel" >/dev/null; then
      echo -e "Intel CPU was detected -> install intel-ucode"
	  base_packages+=( intel-ucode )
   elif lscpu -J | grep -q "AMD" >/dev/null; then
      echo -e "AMD CPU was detected -> install amd-ucode"
	  base_packages+=( amd-ucode )
   fi

   pacman-key --populate
   pacman --noconfirm -Syy archlinux-keyring
   pacman-key --refresh-keys

   pacstrap ${INSTALL_PATH} ${base_packages[@]}
   sed -i 's/block filesystems keyboard/block keyboard keymap encrypt btrfs filesystems/g' ${INSTALL_PATH}/etc/mkinitcpio.conf
}

run_chroot_script() {
   local crypt_dev="$1"; shift
   local log="$1"; shift
   echo -e "\n${LBLUE} >> Run Chroot Script ${NC}"

   local crypt_dev_uuid=$(get_uuid "${crypt_dev}")

   cp $0 ${INSTALL_PATH}/setup.sh
   chmod +x ${INSTALL_PATH}/setup.sh

   if [ "$log" != "0" ]; then
      arch-chroot ${INSTALL_PATH} ./setup.sh chroot "$crypt_dev_uuid" 2>&1 | tee install.log
	  echo -ne "\n${GREEN}Press Enter to view install log ${NC} " && read any && unset any && nano --view install.log
   else
      arch-chroot ${INSTALL_PATH} ./setup.sh chroot "$crypt_dev_uuid"
   fi

   [ -f ${INSTALL_PATH}/setup.sh ] && echo -e "${RED}[ERROR] installation failed! ${NC}" && exit 1
}


##########################################################################################################
# chroot-Functions
##########################################################################################################

setting_timezone() {
   echo -e "\n${LBLUE} >> Setting Timezone ${NC}"
   rm -f /etc/localtime
   ln -sf $LOCALTIME /etc/localtime
   timedatectl set-ntp true
   hwclock --systohc --utc
}

setting_up_locale() {
   echo -e "\n${LBLUE} >> Setting up Locale ${NC}"
   sed -i 's/#'"$LOCALE"' UTF-8/'"$LOCALE"' UTF-8/g' /etc/locale.gen
   locale-gen
   echo "LANG=$LANG" > /etc/locale.conf
   export LANG=$LANG
   echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
}

create_user() {
   local username="$1"; shift

   while true; do
      echo -en "\nEnter user password: " && read -s user_passphrase
      echo -en "\nVerify password: " && read -s user_passphrase_verify

      if [ "$user_passphrase" == "$user_passphrase_verify" ] && [ -n "$user_passphrase" ]; then
         echo -e "\n${GREEN}OK ${NC}" && break
      else
         echo -e "${RED}\n[ERROR] password does not match! ${NC}"
      fi
   done

   useradd -g users -G wheel,audio,video -m -s /bin/bash $username
   sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers
   echo -e "${username}:${user_passphrase}" | chpasswd
   echo -e "root:${user_passphrase}" | chpasswd
}

# Allow user to run sudo without password (required for AUR programs that must be installed in a fakeroot environment)
addTmpSudoInstallPermission() {
   grep "^%wheel ALL=(ALL) NOPASSWD: ALL" /etc/sudoers >/dev/null 2>&1 && return
   grep "^%wheel ALL=(ALL) ALL" /etc/sudoers >/dev/null 2>&1 && sed -i 's/^%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers && return
   echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

removeTmpSudoInstallPermission() {
   sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers
}

update_system() {
   echo -e "\n${LBLUE} >> Update System ${NC}"
   sed -i "s/^#Color/Color/" /etc/pacman.conf
   pacman-key --populate
   pacman --noconfirm -Syy archlinux-keyring
   pacman-key --refresh-keys
   reflector --country "$MIRROR" -l 30 --sort rate --save /etc/pacman.d/mirrorlist
   pacman --noconfirm -Syyu
}

network_settings() {
   echo -e "\n${LBLUE} >> Setting up Network ${NC}"
   echo "$HOSTNAME" > /etc/hostname
   pacman --noconfirm --needed -S networkmanager net-tools
   systemctl enable NetworkManager.service
}

install_common_packages() {
   local username="$1"; shift
   echo -e "\n${LBLUE} >> Install common packages ${NC}"
   pacman --noconfirm --needed -S ${packages[@]}
   pacman --noconfirm --needed -S haveged
   systemctl enable haveged
}

install_aur_tools() {
   local username="$1"; shift
   echo -e "\n${LBLUE} >> Install AUR tools ${NC}"
   pacman --noconfirm --needed -S cmake git go
   local working_directory=$pwd
   cd /tmp #NOTE: for /opt the user has no authorization
   sudo -u $username git clone https://aur.archlinux.org/yay.git yay
   cd yay
   sudo -u $username makepkg --noconfirm -si
   cd $working_directory
   sudo -u $username yay -Syu
}

install_graphic_card_driver() {
   echo -e "\n${LBLUE} >> Graphic card detection ${NC}"

   if lspci -v | grep "VGA" -A 12 | grep -q "Intel" >/dev/null 2>&1; then
      echo -e "Install open-source Intel driver."
      pacman --noconfirm --needed -S mesa xf86-video-intel
   fi

   if lspci -v | grep "VGA" -A 12 | grep -q "NVIDIA" >/dev/null 2>&1; then
      echo -e "A NVIDIA GeForce card was detected."
      echo -n "Would you like to install the proprietary driver ? (y/N) : " && read nvidia_driver && nvidia_driver=${nvidia_driver:-No}
      if [ $nvidia_driver == "Y" ] || [ $nvidia_driver == "y" ] || [ $nvidia_driver == "Yes" ] || [ $nvidia_driver == "yes" ]; then
         echo -e "Install proprietary NVIDIA driver."
         pacman --noconfirm --needed -S nvidia nvidia-utils
      else
      	 echo -e "Install open-source NVIDIA driver."
         pacman --noconfirm --needed -S xf86-video-nouveau
      fi
      unset nvidia_driver
   fi

   if lspci -v | grep "VGA" -A 12 | grep -q -E "(Radeon|AMD)" >/dev/null 2>&1; then
      echo -e "Install open-source amdgpu driver"
      pacman --noconfirm --needed -S mesa xf86-video-amdgpu opencl-mesa opencl-headers libclc
   fi
}

setup_btrfs_swapfile() {
   echo -e "\n${LBLUE} >> BTRFS Swapfile ${NC}"

   chattr +C /swap
   truncate -s 0 /swap/swapfile
   chattr +C /swap/swapfile
   btrfs property set /swap/swapfile compression none
   fallocate -l 2G /swap/swapfile
   chmod 0600 /swap/swapfile
   mkswap /swap/swapfile
   swapon /swap/swapfile
   free -h
   echo "/swap/swapfile none swap defaults 0 3" >> /etc/fstab
}

setup_ssh_server() {
   local username="$1"; shift
   echo -e "\n${LBLUE} >> Setup SSH Server ${NC}"
   pacman --noconfirm --needed -S openssh
   groupadd sshusers
   usermod -a -G sshusers $username
   sudo -u $username mkdir -p /home/${username}/.ssh
   echo "DenyUsers root" >> /etc/ssh/sshd_config
   echo "DenyGroups root" >> /etc/ssh/sshd_config
   echo "AllowGroups sshusers" >> /etc/ssh/sshd_config
   systemctl enable sshd.service
}


# NOTE: Grub disk decryption is only configured with us keyboard layout
install_bootloader_grub() {
   local device_uuid="$1"; shift
   echo -e "\n${LBLUE} >> Install Bootloader Grub ${NC}"

   echo -e "create a keyfile for the LUKS Partition so that you only have to unlock the root partition once"
   dd bs=512 count=8 if=/dev/urandom of=/crypto_keyfile.bin
   echo -e "Add keyfile to luks encrypted partition"

   if [ "$KEYMAP" != "us" ]; then
      if [ "$US_KEYBOARD_FOR_ENCRYPTION" != "0" ]; then
         echo -e "[INFO] keyboard layout changed to us for drive passphrase input"
         loadkeys us
      fi
   fi

   cryptsetup luksAddKey /dev/disk/by-uuid/${device_uuid} /crypto_keyfile.bin
   loadkeys $KEYMAP  # switch back

   chmod 000 /crypto_keyfile.bin
   sed -i 's/^MODULES=(/MODULES=( crc32c /g' /etc/mkinitcpio.conf
   sed -i 's/^FILES=(/FILES=( \/crypto_keyfile.bin /g' /etc/mkinitcpio.conf

   pacman --noconfirm --needed -S grub-btrfs efibootmgr mkinitcpio
   sed -i 's/#GRUB_ENABLE_CRYPTODISK=.*$/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
   sed -i 's/GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="cryptdevice=UUID='$device_uuid':'${CRYPT_DEV_LABEL}' rootflags=subvol='${BTRFS_SYS_SUBVOLUME}'"/' /etc/default/grub
   sed -i 's/loglevel=3 quiet/loglevel=3/g' /etc/default/grub

   if lscpu -J | grep -q "Intel" >/dev/null 2>&1; then
      echo -e "Intel CPU was detected -> add intel_iommu=on"
      sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on /g' /etc/default/grub
   elif lscpu -J | grep -q "AMD" >/dev/null 2>&1; then
      echo -e "AMD CPU was detected -> add amd_iommu=on"
      sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on /g' /etc/default/grub
   fi

   systemctl enable grub-btrfs.path
   mkinitcpio -P
   grub-install --efi-directory=/boot/efi --bootloader-id=arch
   grub-mkconfig -o /boot/grub/grub.cfg

   # grub de language fix:
   if [ "$LOCALE" = "de_DE.UTF-8" ]; then
      if [ -f /usr/share/locale/de/LC_MESSAGES/grub.mo ]; then
         echo -e "Copy /usr/share/locale/de/LC_MESSAGES/grub.mo /boot/grub/locale/de.gmo"
         mkdir -p /boot/grub/locale
         cp /usr/share/locale/de/LC_MESSAGES/grub.mo /boot/grub/locale/de.gmo
      fi
   fi
}

virtualbox_fix() {
   local username="$1"; shift
   echo -e "\n${LBLUE} >> VirtualBox Fix${NC}"

   # fix host: vm freeze caused by btrfs
   sudo -u $username mkdir -p "/home/$username/VirtualBox VMs"
   sudo -u $username chattr +C "/home/$username/VirtualBox VMs"
   sudo -u $username btrfs property set "/home/$username/VirtualBox VMs" compression none

   # fix guest: grub
   [ -f /boot/efi/EFI/arch/grubx64.efi ] && \
      echo "\EFI\arch\grubx64.efi" > /boot/efi/startup.nsh
}

setup_snapper() {
   [ -d /.snapshots ] || return # continue only if we have a common btrfs structure
   [ -f /etc/snapper/configs/root ] && return
   echo -e "\n${LBLUE} >> Setup Snapper${NC}"
   pacman --noconfirm --needed -S snapper snap-pac

   #NOTE: snapper required a not existing /.snapshots directory for setup!
   umount /.snapshots
   rm -r /.snapshots

   # Disable dbus in chroot
   snapper --no-dbus -c root create-config /
   btrfs quota enable /

   # config path: /etc/snapper/configs/root
   snapper --no-dbus -c root set-config "TIMELINE_CREATE=no"
   snapper --no-dbus -c root set-config "NUMBER_CLEANUP=yes"
   snapper --no-dbus -c root set-config "NUMBER_MIN_AGE=0"
   snapper --no-dbus -c root set-config "NUMBER_LIMIT=30"
   snapper --no-dbus -c root set-config "NUMBER_LIMIT_IMPORTANT=10"

   systemctl enable snapper-cleanup.timer

   #NOTE: we delete the snapshots directory from snapper and use our own btrfs subvolume
   btrfs sub delete /.snapshots
   mkdir /.snapshots
   mount -a # mount .snapshots from fstab
}

create_btrfs_snapshot() {
   echo -e "\n${LBLUE} >> Create btrfs snapshot ${NC}"
   local snapshot_name=$(date +%Y-%m-%d)
   btrfs subvolume snapshot / /.snapshots/$snapshot_name # we create a rw snapshot (use -r for read-only)

   # update gub file if we use grub as bootloader
   [ -f /boot/grub/grub.cfg ] && \
      grub-mkconfig -o /boot/grub/grub.cfg
}


##########################################################################################################
# MAIN
##########################################################################################################

init() {
   print_logo

   lsblk
   echo -ne "Set device name : " && read device
   [ -z "$device" ] && exit 1
   if [ ! -e /dev/$device ]; then
      echo -e "${RED}[ERROR] Device not found! ${NC}"
      exit 1
   else
      device="/dev/$device"
   fi

   partition_drive "$device"

   local crypt_dev="/dev/disk/by-partlabel/$PARTLABEL_ROOT"

   enrypt_drive "$crypt_dev"

   local boot_dev="/dev/disk/by-partlabel/$PARTLABEL_BOOT"
   local root_dev="/dev/mapper/$CRYPT_DEV_LABEL"

   setup_filesystem "$boot_dev" "$root_dev"
   update_mirrorlist
   install_system
   run_chroot_script "$crypt_dev" "$CREATE_INSTALL_LOG"

   echo -ne "\n${GREEN}Press Enter to reboot ${NC} " && read any && unset any
   reboot

   exit 0
}

chroot() {
   local crypt_dev_uuid="$1"; shift
   local root_dev="/dev/mapper/$CRYPT_DEV_LABEL"

   print_logo

   setting_timezone
   setting_up_locale

   echo -e "\n${LBLUE} >> User Settings ${NC}"
   echo -ne "Add new user : " && read username && username=${username:-arch}

   create_user "$username"
   addTmpSudoInstallPermission

   update_system
   network_settings

   install_common_packages "$username"
   install_aur_tools "$username"
   install_graphic_card_driver

   if [ "$SSH_SERVER" != "0" ]; then
      setup_ssh_server "$username"
   fi

   setup_btrfs_swapfile
   install_bootloader_grub "$crypt_dev_uuid"
   virtualbox_fix "$username"

   removeTmpSudoInstallPermission
   setup_snapper
   create_btrfs_snapshot
   rm /setup.sh
   exit 0
}

# main
if [ "$1" == "chroot" ]; then
   chroot "$2"
else
   init
fi

