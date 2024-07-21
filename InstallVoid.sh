#!/bin/bash

# Check if the drive argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

DRIVE=$1

# Check if the provided drive exists
if [ ! -b "$DRIVE" ]; then
    echo "Error: $DRIVE is not a valid block device."
    exit 1
fi

# Arch Linux Installation Script

# Set the time
timedatectl set-ntp true

# Partition the disk
echo "Partitioning the disk..."
parted $DRIVE mklabel gpt
parted $DRIVE mkpart primary ext4 1MiB 100%
mkfs.ext4 ${DRIVE}1
mount ${DRIVE}1 /mnt

# Install base packages
echo "Installing base packages..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering chroot environment..."
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "voidspace" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 voidspace.localdomain voidspace" >> /etc/hosts

# Set root password
echo "Setting root password..."
echo "Please enter root password:"
passwd

# Create user
echo "Creating a new user..."
read -p "Enter username: " username
useradd -m -G wheel \$username
echo "Please enter password for \$username:"
passwd \$username
echo "\$username ALL=(ALL) ALL" >> /etc/sudoers

# Install and configure limine bootloader
echo "Installing limine bootloader..."
pacman -S --noconfirm limine
cp /usr/share/limine/limine.sys /boot/
cp /usr/share/limine/limine-cd.bin /boot/
cp /usr/share/limine/limine-eltorito-efi.bin /boot/
cp /usr/share/limine/limine-efi.bin /boot/

# Configure limine
cat <<LIMINECFG > /boot/limine.cfg
TIMEOUT=5
INTERFACE=text
GRAPHICS=yes

:Arch Linux
    COMMENT=Boot into Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=/vmlinuz-linux
    MODULE_PATH=/initramfs-linux.img
    CMDLINE=root=$(blkid -s UUID -o value ${DRIVE}1) rw
LIMINECFG

limine-install ${DRIVE}

# Install essential packages
echo "Installing essential packages..."
pacman -S --noconfirm base-devel networkmanager vim sudo git xorg-server xorg-xinit picom

# Enable NetworkManager
systemctl enable NetworkManager

# Install init system
pacman -S --noconfirm openrc openrc-arch-services

# Change the init system
ln -sf /etc/init.d/NetworkManager /etc/runlevels/default/NetworkManager
rc-update add NetworkManager default

# Check for NVIDIA GPU and install drivers if present
if lspci | grep -E "NVIDIA|GeForce"; then
    echo "NVIDIA GPU detected, installing drivers..."
    pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
fi

# Exit chroot
EOF

# Prompt for WiFi setup after chroot and init system change
read -p "Do you want to set up WiFi? (Y/n): " setup_wifi
setup_wifi=${setup_wifi:-Y}

if [[ $setup_wifi == [Yy] ]]; then
    arch-chroot /mnt /bin/bash <<EOF
    echo "Running nmtui for WiFi setup..."
    nmtui
EOF
fi

# Setup yay, rofi, dwm, and picom
arch-chroot /mnt /bin/bash <<EOF
# Install yay and rofi for the user
su - \$username <<EOUSER
cd /home/\$username
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
yay -S --noconfirm rofi

# Clone and build dwm
git clone https://github.com/Codespace0x25/dwm.git
cd dwm
make clean install

# Set up .xinitrc for dwm
echo "exec dwm" > /home/\$username/.xinitrc

# Exit user
EOUSER

# Exit chroot
EOF

# Unmount and reboot
umount -R /mnt
echo "Installation complete. Rebooting..."
reboot
