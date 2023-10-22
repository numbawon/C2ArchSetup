#!/bin/bash

# Update the system clock
timedatectl set-ntp true

# Enable color and parallel downloads in pacman.conf
sed -i "s/^#Color/Color/" /etc/pacman.conf
sed -i "s/^#ParallelDownloads = 5/ParallelDownloads = 10/" /etc/pacman.conf

# Install reflector and configure it to find the fastest mirrors regardless of location
pacman -Sy --noconfirm reflector
reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Install essential packages
pacstrap /mnt base linux linux-firmware git base-devel nano --needed

# Generate an fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
arch-chroot /mnt

# Automatically determine the timezone based on IP address
timezone=$(curl -s http://ip-api.com/line?fields=timezone)
echo "The detected timezone is $timezone. Is this correct? (yes/no)"
read timezone_answer
if [ "$timezone_answer" != "yes" ]; then 
    echo "Please enter your region (e.g., America):"
    read region
    echo "Please enter your city (e.g., Los_Angeles):"
    read city
    timezone="$region/$city"
fi
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

# Install and configure reflector to find the fastest mirrors regardless of location
pacman -S --noconfirm reflector
reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Create a systemd timer to re-check mirrors every 10 days
echo "[Unit]
Description=Update mirror list using Reflector

[Timer]
OnBootSec=15min
OnUnitActiveSec=10d

[Install]
WantedBy=timers.target" > /etc/systemd/system/reflector.timer

echo "[Unit]
Description=Update mirror list using Reflector

[Service]
ExecStart=/usr/bin/reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist" > /etc/systemd/system/reflector.service

systemctl enable reflector.timer

# Run hwclock to generate /etc/adjtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Network configuration
echo "Please enter your desired hostname:"
read hostname
echo $hostname >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts

# Initramfs
mkinitcpio -P

# Set root password
echo "Please enter your desired root password:"
passwd

# Create a new user account
echo "Please enter your desired username:"
read username
useradd -m $username
echo "Please enter a password for this user:"
passwd $username

# Give the new user sudo access if desired and install yay as the new user
echo "Does this user need sudo access? (yes/no)"
read sudo_access
if [ "$sudo_access" = "yes" ]; then
    pacman -S sudo --noconfirm
    echo "$username ALL=(ALL) ALL" >> /etc/sudoers.d/$username
    
    # Switch to the new user and install yay, then return to the root user.
    su - $username -c 'git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm'
fi

# Update all packages to their latest versions.
pacman -Syu --noconfirm

# Enable multilib, color and parallel downloads in pacman.conf of the chrooted system.
sed -i "/\[multilib\]/,/Include/"'s/^#//' /mnt/etc/pacman.conf
sed -i "s/^#Color/Color/" /mnt/etc/pacman.conf
sed -i "s/^#ParallelDownloads = 5/ParallelDownloads = 10/" /mnt/etc/pacman.conf

# Install bootloader (systemd-boot)
bootctl --path=/boot install

# Determine the device path of the root file system dynamically.
root_device_path=$(df | grep '/$' | awk '{print $1}')

# Create loader entries for systemd-boot.
echo "default arch" > /boot/loader/loader.conf
echo "title Arch Linux" > /boot/loader/entries/arch.conf
echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value $root_device_path) rw" >> /boot/loader/entries/arch.conf

# Check for any *_dm_setup.sh scripts in the current directory and prompt the user to run one if any are found.
setup_scripts=(*_dm_setup.sh)
if [ ${#setup_scripts[@]} -ne 0 ]; then
    echo "The following desktop manager setup scripts were found:"
    for i in "${!setup_scripts[@]}"; do 
        echo "$((i+1)). ${setup_scripts[$i]}"
    done
    
    echo "Would you like to run one of these scripts? (yes/no)"
    read run_script_answer
    
    if [ "$run_script_answer" = "yes" ]; then 
        echo "Please enter the number of the script you would like to run:"
        read script_number
        
        if [ $script_number -ge 1 ] && [ $script_number -le ${#setup_scripts[@]} ]; then 
            ./${setup_scripts[$((script_number-1))]}
        else 
            echo "Invalid selection."
        fi 
    fi 
fi 

# Exit the chroot environment and reboot.
exit 
reboot 
