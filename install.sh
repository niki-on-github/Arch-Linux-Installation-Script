#!/bin/bash

##########################################################################################################
# CONFIGURATION VAR
##########################################################################################################

LOCALE="de_DE.UTF-8"
MIRROR="Germany"
LANG="de_DE.UTF-8"
KEYMAP="de-latin1"
LOCALTIME="/usr/share/zoneinfo/Europe/Berlin"
INSTALL_PATH="/mnt/install"
PARTLABEL_BOOT="boot"
PARTLABEL_ROOT="root"
LABEL_ARCH="arch"
CRYPT_DEV_LABEL="system"
HOSTNAME="archlinux"
USERNAME="arch"
HARDENED=1
ENCRYPT_DRIVE=1
PROPRIETARY_VIDEO_DRIVER=1
SSH_SERVER=0
ADD_BLACK_ARCH_REPO=0
REFRESH_PACMAN_KEYS=0
LUKS_PBKDF_ITERATIONS=500000
LOGFILE="/install_error.log"


##########################################################################################################
# KEYSERVER
# - In August 2020 almost no keyserver was accessible via hkps. Workaround: Set keyserver without hkps.
# - When KEYSERVER var is an empty string, then we use the default keyserver.
##########################################################################################################

#KEYSERVER="pool.sks-keyservers.net"
KEYSERVER=""


##########################################################################################################
# Package
##########################################################################################################

PACKAGES=( curl vim openssh usbutils wget )


##########################################################################################################
# BTRFS SUBVOLUME PATHS
# - Set btrfs paths without the first slash
##########################################################################################################

BTRFS_SYS_SUBVOLUME="@"
BTRFS_SYS_SNAPSHOTS_SUBVOLUME="@snapshots"
BTRFS_VAR_LOG_SUBVOLUME="@log"
BTRFS_SWAP_SUBVOLUME="@swap"
BTRFS_HOME_SUBVOLUME="@home"


##########################################################################################################
# Colors
##########################################################################################################

LBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


##########################################################################################################
# Logging
# - The DEBUG trap with `set -o functrace` setup execute right before any command execution
##########################################################################################################

set -o functrace
trap 'rcode=$?; previous_command=$this_command; this_command=$BASH_COMMAND; \
    previous_line=$this_line; this_line=$LINENO; \
    echo "${previous_line}: ${previous_command} (error code $rcode)" | grep -v " 0)$" | \
    grep -v "^${previous_line}: [ ]*\[" | grep "^${previous_line}: " | \
    grep -v "^${previous_line}: [ ]*cat " | grep -v "^${previous_line}: [ ]*print_logo " \
    >> "$LOGFILE"' DEBUG


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
    return 0
}

check_efi() {
    [ ! -e /sys/firmware/efi/efivars ] && echo -e "${RED}[ERROR] Not booted via UEFI, installation is not possible! ${NC}" && exit 1
    return 0
}

print_config() {
    echo -e "\n${LBLUE} >> Config ${NC}"
    head -n 57 $0 | grep -v "^#" | grep -v "^$"
    echo -e "\n"
    return 0
}

get_uuid() {
    blkid $1 -s UUID -o value
}

select_device() {
    echo -e "\n${LBLUE} >> Select Install Device ${NC}"
    lsblk
    echo -ne "Set device name (e.g. nvme0n1) : " && read device
    [ -z "$device" ] && exit 1
    if [ ! -e /dev/$device ]; then
        echo -e "${RED}[ERROR] Device not found! ${NC}"
        exit 1
    else
        device="/dev/$device"
    fi
    _DEVICE="$device"
    return 0
}

partition_drive() {
    device="$1"; shift
    echo -e "\n${LBLUE} >> Partition Drive ${NC}"

    [ ! -e $device ] && echo "Device not found!" && exit 1
    echo -n "All data on $device will be deleted, continue? (Y/n) : " && read delete && delete=${delete:-Yes}
    [ $delete != "Yes" ] && [ $delete != "yes" ] && [ $delete != "Y" ] && [ $delete != "y" ] && exit 1

    # if installation failed we need to remove the broken setup first
    if [ -e /dev/mapper/$CRYPT_DEV_LABEL ]; then
        umount -A -v -f /dev/mapper/$CRYPT_DEV_LABEL
        cryptsetup luksClose $CRYPT_DEV_LABEL
    fi

    if [ "$(ls ${device}* | wc -l)" -gt "1" ]; then
        for s in $(ls ${device}*); do
            echo -e "umount $s" && umount -f $s
        done
    fi

    wipefs --force --quiet --all $device >/dev/null 2>&1

    parted --script $device mklabel gpt
    parted --script $device mkpart primary 1MiB 256MiB name 1 $PARTLABEL_BOOT
    parted --script $device set 1 boot on
    parted --script $device mkpart primary 256MiB 100% name 2 $PARTLABEL_ROOT
    return 0
}

enrypt_drive() {
    crypt_dev="$1"; shift
    echo -e "\n${LBLUE} >> Encrypt Drive ${NC}"

    loadkeys us
    while true; do
        echo -en "\nEnter passphrase for drive: " && read -s drive_passphrase
        echo -en "\nVerify passphrase for drive: " && read -s drive_passphrase_verify

        if [ "$drive_passphrase" == "$drive_passphrase_verify" ] && [ -n "$drive_passphrase" ]; then
            echo -e "\n${GREEN}OK ${NC}" && break
        else
            echo -e "${RED}\n[ERROR] passphrase does not match! ${NC}"
        fi
    done
    _DRIVE_PASSPHRASE="$drive_passphrase"
    loadkeys $KEYMAP

    # NOTE: The iteration count parameter are determined via benchmark upon key slot creation or update via `--iter-time`
    # parameter (default 2000 milliseconds). Unlocking from GRUB under tighter memory constraints doesn’t take advantage
    # of all crypto-related CPU instructions. That means unlocking a LUKS device from GRUB might take a lot longer than
    # doing it from the normal system. Since GRUB’s LUKS implementation isn’t able to benchmark, you’ll need to determine
    # the iteration count parameter manually via `luksChangeKey --pbkdf-force-iterations`. Wenn you change it you have to
    # make sure that the key stores in keyslot 0 to get the speed advantage. Halving the iteration count would speed up
    # unlocking by a factor of two but making low entropy passphrases twice as easy to brute-force!
    if [ "$LUKS_PBKDF_ITERATIONS" -le "100000" ]; then
        echo "[LUKS] manual pbkdf iteration is disabled, determine automatically"
        echo -en "$drive_passphrase" | cryptsetup luksFormat --type luks1 -s 512 -h sha512 ${crypt_dev}
    else
        echo "[LUKS] use $LUKS_PBKDF_ITERATIONS pbkdf iterations"
        echo -en "$drive_passphrase" | cryptsetup luksFormat --type luks1 --pbkdf-force-iterations $LUKS_PBKDF_ITERATIONS -s 512 -h sha512 ${crypt_dev}
    fi
    echo -en "$drive_passphrase" | cryptsetup open --type luks1 ${crypt_dev} $CRYPT_DEV_LABEL
    return 0
}

create_btrfs_subvolume_recursive() {
    # Installer btrfs helper function
    btrfs_path="$1"; shift

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
    boot_dev="$1"; shift
    root_dev="$1"; shift
    echo -e "\n${LBLUE} >> Setup Filesystem ${NC}"

    mkfs.vfat -F32 $boot_dev
    mkfs.btrfs -f -L $LABEL_ARCH $root_dev

    mkdir -p /mnt/btrfs-root
    mount -t btrfs -o defaults,ssd,noatime,compress=lzo $root_dev /mnt/btrfs-root

    # NOTE: subvolumes inside subvolumes are excluded from snapshots
    create_btrfs_subvolume_recursive "$BTRFS_SYS_SUBVOLUME"
    create_btrfs_subvolume_recursive "$BTRFS_SYS_SNAPSHOTS_SUBVOLUME"
    create_btrfs_subvolume_recursive "$BTRFS_VAR_LOG_SUBVOLUME"
    create_btrfs_subvolume_recursive "$BTRFS_SWAP_SUBVOLUME"
    create_btrfs_subvolume_recursive "$BTRFS_HOME_SUBVOLUME"

    # NOTE: It is not possible to mount some subvolumes with 'nodatacow' and others with 'datacow'.
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

    # Create fstab
    mkdir -p ${INSTALL_PATH}/etc
    echo -e "# <uuid>  <path>   <fs>    <options>  <0>  <order>" > ${INSTALL_PATH}/etc/fstab

    btrfs_dev_uuid=$(get_uuid "$root_dev")
    echo -e "UUID=${btrfs_dev_uuid} / btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SUBVOLUME} 0 0" >> ${INSTALL_PATH}/etc/fstab
    echo -e "UUID=${btrfs_dev_uuid} /var/log btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_VAR_LOG_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
    echo -e "UUID=${btrfs_dev_uuid} /home btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_HOME_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
    echo -e "UUID=${btrfs_dev_uuid} /.snapshots btrfs defaults,ssd,noatime,compress=lzo,subvol=${BTRFS_SYS_SNAPSHOTS_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab
    echo -e "UUID=${btrfs_dev_uuid} /swap btrfs defaults,ssd,noatime,subvol=${BTRFS_SWAP_SUBVOLUME} 0 2" >> ${INSTALL_PATH}/etc/fstab

    boot_dev_uuid=$(get_uuid "$boot_dev")
    echo -e "UUID=${boot_dev_uuid} /boot/efi vfat defaults 0 2" >> ${INSTALL_PATH}/etc/fstab
    return 0
}

user_password() {
    echo -e "\n${LBLUE} >> User ${NC}"
    echo "Set password for $USERNAME and root"
    while true; do
        echo -en "\nEnter user password: " && read -s user_passphrase
        echo -en "\nVerify password: " && read -s user_passphrase_verify

        if [ "$user_passphrase" == "$user_passphrase_verify" ] && [ -n "$user_passphrase" ]; then
            echo -e "\n${GREEN}OK ${NC}" && break
        else
            echo -e "${RED}\n[ERROR] password does not match! ${NC}"
        fi
    done
    _USER_PASSWORD="$user_passphrase"
    return 0
}

update_mirrorlist() {
    echo -e "\n${LBLUE} >> Update Mirrorlist ${NC}"
    pacman --noconfirm --needed -Sy reflector
    reflector --country "$MIRROR" --age 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    return 0
}

install_system() {
    echo -e "\n${LBLUE} >> Install System ${NC}"
    timedatectl set-ntp true

    base_packages=( base base-devel linux-firmware btrfs-progs reflector sudo xdg-user-dirs nvme-cli rsync )

    if [ $HARDENED != 0 ]; then
        echo -e "Install hardened Linux Kernel"
        base_packages+=( linux-hardened linux-hardened-headers )
    else
        base_packages+=( linux linux-headers )
    fi

    if lscpu -J | grep -q "Intel" >/dev/null 2>&1; then
        echo -e "Intel CPU was detected -> install intel-ucode"
        base_packages+=( intel-ucode )
    elif lscpu -J | grep -q "AMD" >/dev/null 2>&1; then
        echo -e "AMD CPU was detected -> install amd-ucode"
        base_packages+=( amd-ucode )
    fi

    pacman-key --populate archlinux
    pacman --noconfirm -Syy archlinux-keyring

    pacstrap ${INSTALL_PATH} ${base_packages[@]}
    sed -i 's/block filesystems keyboard/block keyboard keymap encrypt btrfs filesystems/g' ${INSTALL_PATH}/etc/mkinitcpio.conf
    return 0
}

run_chroot_script() {
    crypt_dev="$1"; shift
    drive_passphrase="$1"; shift
    user_password="$1"; shift
    echo -e "\n${LBLUE} >> Run Chroot Script ${NC}"

    crypt_dev_uuid=$(get_uuid "${crypt_dev}")

    cp $0 ${INSTALL_PATH}/setup.sh
    chmod +x ${INSTALL_PATH}/setup.sh

    echo "run setup.sh in arch-chroot"
    arch-chroot ${INSTALL_PATH} ./setup.sh chroot "$crypt_dev_uuid" "$drive_passphrase" "$user_password"

    [ -f ${INSTALL_PATH}${LOGFILE} ] && cat ${INSTALL_PATH}${LOGFILE} >> ${LOGFILE} && rm ${INSTALL_PATH}${LOGFILE}
    [ -f ${INSTALL_PATH}/setup.sh ] && echo -e "${RED}[ERROR] Installation failed! ${NC}" && exit 1
    return 0
}

view_install_log() {
    [ ! -f $LOGFILE ] && return
    echo -ne "\n${GREEN}Press Enter to view install log ${NC} " && read any && unset any && nano --view $LOGFILE
    return 0
}


##########################################################################################################
# chroot-Functions
##########################################################################################################

setting_timezone() {
    echo -e "\n${LBLUE} >> Setting Timezone (chroot) ${NC}"
    rm -f /etc/localtime
    ln -sf $LOCALTIME /etc/localtime
    systemctl enable systemd-timesyncd.service
    timedatectl set-ntp true
    hwclock --systohc --utc
    echo "done"
    return 0
}

setting_up_locale() {
    echo -e "\n${LBLUE} >> Setting up Locale (chroot) ${NC}"
    sed -i 's/#'"$LOCALE"' UTF-8/'"$LOCALE"' UTF-8/g' /etc/locale.gen
    locale-gen
    echo "LANG=$LANG" > /etc/locale.conf
    export LANG=$LANG
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "done"
    return 0
}

create_user() {
    user_passphrase="$1"; shift
    echo -e "\n${LBLUE} >> Create User (chroot) ${NC}"
    groupadd -r audit # for apparmor notifications
    useradd -g users -G wheel,audio,video,uucp,audit -m -s /bin/bash $USERNAME
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
    echo -e "${USERNAME}:${user_passphrase}" | chpasswd
    echo -e "root:${user_passphrase}" | chpasswd
    echo "done"
    return 0
}

addInstallPermission() {
    # Allow user to run sudo without password (required for AUR programs that must be installed in a fakeroot environment)
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    return 0
}

removeInstallPermission() {
    sed -i '$ d' /etc/sudoers # remove last entry
    return 0
}

update_system() {
    echo -e "\n${LBLUE} >> Update System (chroot) ${NC}"
    sed -i "s/^#Color/Color/" /etc/pacman.conf
    sed -i "s/^#ParallelDownloads.*$/ParallelDownloads = 4/g" /etc/pacman.conf
    pacman-key --populate archlinux
    pacman --noconfirm -Syy archlinux-keyring

    if [ -n "$KEYSERVER" ]; then
        if grep -q "^keyserver " /etc/pacman.d/gnupg/gpg.conf ; then
            sed -i 's/^keyserver .*$/keyserver '$(echo "$KEYSERVER" | sed 's/\//\\\//g')'/g' /etc/pacman.d/gnupg/gpg.conf
        else
            mkdir -p /etc/pacman.d/gnupg
            echo "keyserver $KEYSERVER" >> /etc/pacman.d/gnupg/gpg.conf
        fi
    fi

    if [ $REFRESH_PACMAN_KEYS != 0 ]; then
        pacman-key --refresh-keys # Warning: time consuming
    fi

    reflector --country "$MIRROR" --age 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    pacman --noconfirm -Syu
    return 0
}

add_black_arch_repo() {
    pushd /tmp
    pacman --noconfirm --needed -S curl
    curl -O https://blackarch.org/strap.sh
    chmod +x strap.sh
    ./strap.sh
    popd
}

network_settings() {
    echo -e "\n${LBLUE} >> Setting up Network (chroot) ${NC}"
    echo "$HOSTNAME" > /etc/hostname
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1 localhost" >> /etc/hosts
    echo "127.0.0.1 $HOSTNAME.local $HOSTNAME" >> /etc/hosts
    pacman --noconfirm --needed -S networkmanager net-tools
    systemctl enable NetworkManager.service
    systemctl enable systemd-resolved.service
    return 0
}

install_common_packages() {
    echo -e "\n${LBLUE} >> Install common packages (chroot) ${NC}"
    pacman --noconfirm --needed -S ${PACKAGES[@]}
    pacman --noconfirm --needed -S haveged cmake git git-lfs xdg-user-dirs
    sudo -u $USERNAME xdg-user-dirs-update --force
    sudo -u $USERNAME git lfs install >/dev/null 2>&1 || echo "initialize git lfs"
    # pacman --noconfirm --needed -S iptables-nft
    # systemctl enable nftables
    systemctl enable haveged
    return 0
}

install_yay() {
    echo -e "\n${LBLUE} >> Install AUR helper yay (chroot) ${NC}"

    sudo -u $USERNAME mkdir -p /home/$USERNAME/.config # avoid config directory created by root

    if [ -n "$KEYSERVER" ]; then
        [ -d /home/$USERNAME/.gnupg ] || sudo -u $USERNAME mkdir -p /home/$USERNAME/.gnupg
        sudo -u $USERNAME chmod 700 /home/$USERNAME/.gnupg
        if grep -q "^keyserver " /home/$USERNAME/.gnupg ; then
            sudo -u $USERNAME sed -i 's/^keyserver .*$/keyserver '$(echo "$KEYSERVER" | sed 's/\//\\\//g')'/g' /home/$USERNAME/.gnupg/gpg.conf
        else
            echo "keyserver $KEYSERVER" | sudo -u $USERNAME tee -a /home/$USERNAME/.gnupg/gpg.conf
        fi
        sudo -u $USERNAME chmod 600 /home/$USERNAME/.gnupg/gpg.conf
    fi

    if [ $ADD_BLACK_ARCH_REPO != 0 ]; then
        pacman --noconfirm --needed -S yay
    else
        pacman --noconfirm --needed -S go
        sudo -u $USERNAME git clone https://aur.archlinux.org/yay.git /tmp/yay
        pushd /tmp/yay
        sudo -u $USERNAME makepkg --noconfirm -si
        popd
    fi
    sudo -u $USERNAME yay --noconfirm -Syu
    sed -i 's/^#MAKEFLAGS=.*$/MAKEFLAGS="-j$(expr $(nproc) \+ 1)"/g' /etc/makepkg.conf
    return 0
}

install_paru() {
    echo -e "\n${LBLUE} >> Install AUR helper paru (chroot) ${NC}"
    sudo -u $USERNAME mkdir -p /home/$USERNAME/.config # avoid config directory created by root

    if [ -n "$KEYSERVER" ]; then
        [ -d /home/$USERNAME/.gnupg ] || sudo -u $USERNAME mkdir -p /home/$USERNAME/.gnupg
        sudo -u $USERNAME chmod 700 /home/$USERNAME/.gnupg
        if grep -q "^keyserver " /home/$USERNAME/.gnupg ; then
            sudo -u $USERNAME sed -i 's/^keyserver .*$/keyserver '$(echo "$KEYSERVER" | sed 's/\//\\\//g')'/g' /home/$USERNAME/.gnupg/gpg.conf
        else
            echo "keyserver $KEYSERVER" | sudo -u $USERNAME tee -a /home/$USERNAME/.gnupg/gpg.conf
        fi
        sudo -u $USERNAME chmod 600 /home/$USERNAME/.gnupg/gpg.conf
    fi

    if [ $ADD_BLACK_ARCH_REPO != 0 ]; then
        pacman --noconfirm --needed -S paru
    else
        pacman --noconfirm --needed -S rustup
        sudo -u $USERNAME git lfs install >/dev/null 2>&1 || echo "initialize git lfs"
        sudo -u $USERNAME rustup install stable
        sudo -u $USERNAME rustup default stable
        sudo -u $USERNAME git clone https://aur.archlinux.org/paru.git /tmp/paru
        pushd /tmp/paru
        sudo -u $USERNAME makepkg --noconfirm -si
        popd
    fi
    sudo -u $USERNAME paru --noconfirm -Syu
    sed -i 's/^#MAKEFLAGS=.*$/MAKEFLAGS="-j$(expr $(nproc) \+ 1)"/g' /etc/makepkg.conf
    return 0
}

install_video_driver() {
    echo -e "\n${LBLUE} >> Graphic card detection (chroot) ${NC}"

    if lspci 2>&1 | grep "VGA" -A 2 | grep -q "Intel"; then
        echo -e "Install open-source Intel driver"
        pacman --noconfirm --needed -S mesa xf86-video-intel
    fi

    if lspci 2>&1 | grep "VGA" -A 2 | grep -q "NVIDIA"; then
        echo -e "A NVIDIA card was detected."
        if [ $PROPRIETARY_VIDEO_DRIVER != 0 ]; then
            echo -e "Install proprietary NVIDIA driver"
            pacman --noconfirm --needed -S nvidia nvidia-utils
        else
            echo -e "Install open-source NVIDIA driver"
            pacman --noconfirm --needed -S xf86-video-nouveau
        fi
    fi

    if lspci 2>&1 | grep "VGA" -A 2 | grep -q -E "(Radeon|AMD)"; then
        echo -e "Install open-source amdgpu driver"
        pacman --noconfirm --needed -S mesa opencl-mesa opencl-headers libclc
    fi
    return 0
}

setup_btrfs_swapfile() {
    echo -e "\n${LBLUE} >> BTRFS Swapfile (chroot) ${NC}"
    chattr +C /swap
    truncate -s 0 /swap/swapfile
    chattr +C /swap/swapfile
    btrfs property set /swap/swapfile compression none
    fallocate -l 2G /swap/swapfile
    chmod 0600 /swap/swapfile
    mkswap /swap/swapfile
    swapon /swap/swapfile
    echo "/swap/swapfile none swap defaults 0 3" >> /etc/fstab
    return 0
}

systemd_settings() {
    echo -e "\n${LBLUE} >> systemd settings ${NC}"

    echo "Set shutdown timeout"
    sed -i 's/.*DefaultTimeoutStopSec=.*$/DefaultTimeoutStopSec=20s/g' /etc/systemd/system.conf

    echo "Forwarding the journal to /dev/tty12"
    mkdir -p /etc/systemd/journald.conf.d
    echo "[Journal]" > /etc/systemd/journald.conf.d/fw-tty12.conf
    echo "ForwardToConsole=yes" >> /etc/systemd/journald.conf.d/fw-tty12.conf
    echo "TTYPath=/dev/tty12" >> /etc/systemd/journald.conf.d/fw-tty12.conf
    echo "MaxLevelConsole=info" >> /etc/systemd/journald.conf.d/fw-tty12.conf

    return 0
}

setup_ssh_server() {
    echo -e "\n${LBLUE} >> Setup SSH Server (chroot) ${NC}"
    pacman --noconfirm --needed -S openssh
    groupadd sshusers
    usermod -a -G sshusers $USERNAME
    sudo -u $USERNAME mkdir -p /home/${USERNAME}/.ssh
    echo "DenyUsers root" >> /etc/ssh/sshd_config
    echo "DenyGroups root" >> /etc/ssh/sshd_config
    echo "AllowGroups sshusers" >> /etc/ssh/sshd_config
    systemctl enable sshd.service
    return 0
}

system_hardening() {
    echo -e "\n${LBLUE} >> Hardening System (chroot) ${NC}"

    #NOTE: may lead to problems with git lfs
    # echo "set default file access permissions"
    #sed -i 's/^umask .*$/umask 077/g' /etc/profile

    echo "setup fail2ban"
    pacman --noconfirm --needed -S fail2ban
    if [ $SSH_SERVER != 0 ]; then echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local; fi
    systemctl enable fail2ban

    echo "done"
    return 0
}

install_bootloader_grub_with_crypt_dev() {
    # NOTE: My Grub disk decryption is only configured with us keyboard layout
    # NOTE: To protect against offline tampering threats, see mkinitcpio-chkcryptoboot hook (AUR)
    device_uuid="$1"; shift
    drive_passphrase="$1"; shift
    echo -e "\n${LBLUE} >> Install Bootloader Grub for encrypted device (chroot) ${NC}"
    pacman --noconfirm --needed -S grub-btrfs efibootmgr mkinitcpio

    if [ ! -e /dev/disk/by-uuid/${device_uuid} ]; then
        echo -e "${RED}WARNING: /dev/disk/by-uuid/${device_uuid} does not exists. Workaround we create the link now ${NC}"
        ln -s /dev/mapper/${CRYPT_DEV_LABEL} /dev/disk/by-uuid/${device_uuid}
    fi

    echo -e "create a keyfile for the LUKS Partition so that you only have to unlock the root partition once"
    dd bs=512 count=8 if=/dev/random of=/disk.key iflag=fullblock
    echo -e "Add keyfile to luks encrypted partition"
    echo -en "$drive_passphrase" | cryptsetup luksAddKey /dev/disk/by-uuid/${device_uuid} /disk.key

    chmod 000 /disk.key
    sed -i 's/^MODULES=(/MODULES=( crc32c /g' /etc/mkinitcpio.conf
    sed -i 's/^FILES=(/FILES=( \/disk.key /g' /etc/mkinitcpio.conf
    sed -i 's/#GRUB_ENABLE_CRYPTODISK=.*$/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="cryptdevice=UUID='$device_uuid':'${CRYPT_DEV_LABEL}' rootflags=subvol='${BTRFS_SYS_SUBVOLUME}' cryptkey=rootfs:\/disk.key"/' /etc/default/grub
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
    chmod 600 /boot/initramfs-linux*

    # Initramfs permissions are set to 644 by default, all users will be able to dump the keyfile!
    # Workaround: use systemd service to set new initramfs to 600
    cat > /usr/lib/systemd/system/initramfs-keyfile.path <<EOF
[Unit]
Description=Monitors for new initramfs

[Path]
PathModified=/boot
TriggerLimitIntervalSec=60s

[Install]
WantedBy=multi-user.target
EOF

    cat > /usr/lib/systemd/system/initramfs-keyfile.service <<EOF
[Unit]
Description=Make sure the permissions for initramfs are still 600 after kernel update

[Service]
Type=oneshot
ExecStart=bash -c 'chmod 600 /boot/initramfs-linux*'
EOF

    systemctl enable initramfs-keyfile.path

    grub-install --efi-directory=/boot/efi --bootloader-id=arch
    grub-mkconfig -o /boot/grub/grub.cfg

    if [ ! -f /boot/grub/grub.cfg ]; then
        echo "${RED}ERROR: /boot/grub/grub.cfg missing${NC}"
    fi

    # grub de language fix:
    if [ "$LOCALE" = "de_DE.UTF-8" ]; then
        if [ -f /usr/share/locale/de/LC_MESSAGES/grub.mo ]; then
            mkdir -p /boot/grub/locale
            cp -v /usr/share/locale/de/LC_MESSAGES/grub.mo /boot/grub/locale/de.gmo
        fi
    fi
    return 0
}

install_bootloader_grub() {
    echo -e "\n${LBLUE} >> Install Bootloader Grub (chroot) ${NC}"
    pacman --noconfirm --needed -S grub-btrfs efibootmgr mkinitcpio

    sed -i 's/GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="rootflags=subvol='${BTRFS_SYS_SUBVOLUME}'"/' /etc/default/grub
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
            mkdir -p /boot/grub/locale
            cp -v /usr/share/locale/de/LC_MESSAGES/grub.mo /boot/grub/locale/de.gmo
        fi
    fi

    return 0
}

install_apparmor() {
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="lsm=landlock,lockdown,yama,apparmor,bpf audit=1 /g' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    pacman --noconfirm --needed -S apparmor audit
    systemctl enable apparmor.service
    systemctl enable auditd.service
    sed -i 's/^log_group = root/log_group = audit/g' /etc/audit/auditd.conf
}

install_memtest86() {
    AUR_HELPER=""
    if command -v yay >/dev/null ; then
        AUR_HELPER="yay"
    elif command -v paru >/dev/null ; then
        AUR_HELPER="paru"
    fi
    [ -z "$AUR_HELPER" ] && return 0
    echo -e "\n${LBLUE} >> Install Memtest86 (chroot) ${NC}"
    eval "sudo -u $USERNAME $AUR_HELPER --noconfirm -S memtest86-efi"

    MEMTEST86_PATH="/usr/share/memtest86-efi"
    [ ! -d $MEMTEST86_PATH ] && echo -e "${RED}MemTest86 install failed (DirectoryNotFound: $MEMTEST86_PATH) ${NC}" && return

    mkdir -pv "/boot/efi/EFI/memtest86"
    pushd $MEMTEST86_PATH
    find . -type f -not -iname '*.efi' -exec cp '{}' '/boot/efi/EFI/memtest86/{}' ';'
    popd
    cp -v "$MEMTEST86_PATH/bootx64.efi" "/boot/efi/EFI/memtest86/memtestx64.efi"

    boot_uuid=$(get_uuid "/dev/disk/by-partlabel/$PARTLABEL_BOOT")
    cat > "/etc/grub.d/86_memtest" <<FOE
#!/bin/sh

cat <<EOF
menuentry "Memtest86" {
    search --set=root --no-floppy --fs-uuid $boot_uuid
    chainloader /EFI/memtest86/memtestx64.efi
}
EOF
FOE
    chmod 755 "/etc/grub.d/86_memtest"
    grub-mkconfig -o "/boot/grub/grub.cfg"

    if [ -f /etc/memtest86-efi/memtest86-efi.conf ]; then
        echo "Writting configuration (for updates) ..."
        sed -i "s|@PARTITION@|/dev/disk/by-partlabel/$PARTLABEL_BOOT|g" /etc/memtest86-efi/memtest86-efi.conf
        sed -i "s|@ESP@|/boot/efi|g" /etc/memtest86-efi/memtest86-efi.conf
        sed -i "s|@CHOICE@|3|g" /etc/memtest86-efi/memtest86-efi.conf
        sed -i "s|install=0|install=1|g" /etc/memtest86-efi/memtest86-efi.conf
    fi
    return 0
}

virtualbox_fix() {
    echo -e "\n${LBLUE} >> VirtualBox Fix (chroot) ${NC}"

    # fix host: vm freeze caused by btrfs
    sudo -u $USERNAME mkdir -p "/home/$USERNAME/VirtualBox VMs"
    sudo -u $USERNAME chattr +C "/home/$USERNAME/VirtualBox VMs"
    sudo -u $USERNAME btrfs property set "/home/$USERNAME/VirtualBox VMs" compression none

    # fix guest: grub
    [ -f /boot/efi/EFI/arch/grubx64.efi ] && \
        echo "\EFI\arch\grubx64.efi" > /boot/efi/startup.nsh

    echo "done"
    return 0
}

setup_snapper() {
    [ -d /.snapshots ] || return # continue only if we have a common btrfs structure
    [ -f /etc/snapper/configs/root ] && return
    echo -e "\n${LBLUE} >> Setup Snapper (chroot) ${NC}"
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
    snapper --no-dbus -c root set-config "NUMBER_LIMIT=25"
    snapper --no-dbus -c root set-config "NUMBER_LIMIT_IMPORTANT=5"

    systemctl enable snapper-cleanup.timer

    #NOTE: we delete the snapshots directory from snapper and use our own btrfs subvolume
    btrfs sub delete /.snapshots
    mkdir /.snapshots
    mount -a # mount .snapshots from fstab
    return 0
}

create_btrfs_recover_script() {
    echo -e "\n${LBLUE} >> Create BTRFS Recover Script (chroot) ${NC}"
    pacman -S --needed --noconfirm fzf  # install recover script dependencies
    cat > /usr/bin/btrfs-system-recover <<EOF
#!/bin/bash
set -e
[ "\$EUID" -ne 0 ] && echo "require root" && exit 1
check() {
    [ "\$?" -eq "0" ] || echo "Error: Recovery failed"
    [ -d /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME/boot ] || echo "Warning: System is not bootable anymore"
    rm -d /tmp/btrfs-recover >/dev/null
}
trap check SIGHUP SIGINT SIGTERM EXIT
if [ ! -d /tmp/btrfs-recover ]; then
    mkdir -p /tmp/btrfs-recover
    mount -t btrfs -o subvolid=0 /dev/mapper/$CRYPT_DEV_LABEL /tmp/btrfs-recover
fi
recover=\$(find /tmp/btrfs-recover/$BTRFS_SYS_SNAPSHOTS_SUBVOLUME -maxdepth 2 -name "info.xml" | fzf --preview 'cat {}' | sed 's/\/info.xml$//g') || exit 1
[ -z "\$recover" ] && exit 1
[ ! -d \$recover/snapshot ] && echo "[ERROR] SnapshotNotFound: \$recover/snapshot" && exit 1
echo "process system recover ... (may take several seconds)"
rm -rf /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME/{*,.*} >/dev/null 2>&1 || echo "clear bad btrfs system root"  # return always true
btrfs subvolume set-default /tmp/btrfs-recover
[ ! -e /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME ] || btrfs subvolume delete /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME
btrfs subvolume snapshot \$recover/snapshot /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME
rm -f /tmp/btrfs-recover/$BTRFS_SYS_SUBVOLUME/var/lib/pacman/db.lck
echo "recovery successful (restart your system to complete the restore process)"
EOF
    chmod +x /usr/bin/btrfs-system-recover
    echo "/usr/bin/btrfs-system-recover created"
    return 0
}

create_btrfs_snapshot() {
    echo -e "\n${LBLUE} >> Create btrfs snapshot (chroot) ${NC}"
    snapshot_name="System_Recovery_$(date +%Y_%m_%d)"
    btrfs subvolume snapshot / /.snapshots/$snapshot_name # we create a rw snapshot (use -r for read-only)

    # update gub file if we use grub as bootloader
    [ -f /boot/grub/grub.cfg ] && \
        grub-mkconfig -o /boot/grub/grub.cfg
    return 0
}


##########################################################################################################
# MAIN
##########################################################################################################

if [ "$1" == "chroot" ]; then
    shift
    _CRYPT_DEV_UUID="$1"; shift
    _DRIVE_PASSPHRASE="$1"; shift
    _USER_PASSWORD="$1"; shift

    setting_timezone
    setting_up_locale
    create_user "$_USER_PASSWORD"
    addInstallPermission
    update_system
    [ $ADD_BLACK_ARCH_REPO != 0 ] && add_black_arch_repo
    network_settings
    install_common_packages
    install_paru
    install_video_driver
    setup_btrfs_swapfile
    systemd_settings
    if [ $ENCRYPT_DRIVE != 0 ]; then
        install_bootloader_grub_with_crypt_dev "$_CRYPT_DEV_UUID" "$_DRIVE_PASSPHRASE"
    else
        install_bootloader_grub
    fi
    [ $HARDENED != 0 ] && install_apparmor
    install_memtest86
    virtualbox_fix
    setup_snapper
    create_btrfs_recover_script

    [ $SSH_SERVER != 0 ] && setup_ssh_server
    [ $HARDENED != 0 ] && system_hardening

    removeInstallPermission
    create_btrfs_snapshot
    rm /setup.sh && exit 0
else # "init"
    print_logo
    check_efi
    print_config
    select_device   # Set _DEVICE
    partition_drive "$_DEVICE"

    _BOOT_DEV="/dev/disk/by-partlabel/$PARTLABEL_BOOT"
    if [ $ENCRYPT_DRIVE != 0 ]; then
        _CRYPT_DEV="/dev/disk/by-partlabel/$PARTLABEL_ROOT"
        _ROOT_DEV="/dev/mapper/$CRYPT_DEV_LABEL"
        enrypt_drive "$_CRYPT_DEV"  # Set _DRIVE_PASSPHRASE
    else
        _DRIVE_PASSPHRASE=""
        _CRYPT_DEV="/dev/disk/by-partlabel/$PARTLABEL_ROOT"
        _ROOT_DEV="$_CRYPT_DEV"
    fi

    setup_filesystem "$_BOOT_DEV" "$_ROOT_DEV"

    user_password   # Set _USER_PASSWORD

    update_mirrorlist
    install_system

    run_chroot_script "$_CRYPT_DEV" "$_DRIVE_PASSPHRASE" "$_USER_PASSWORD"
    view_install_log

    echo -ne "\n${GREEN}Press Enter to reboot ${NC} " && read any && unset any
    reboot && exit 0
fi
