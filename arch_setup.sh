#!/bin/bash

# Update the system clock
timedatectl set-ntp true

# Install essential packages
pacstrap /mnt base linux linux-firmware git base-devel --needed

# Generate an fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
arch-chroot /mnt

# Prompt for and set the time zone
echo "Please enter your region (e.g., America):"
read region
echo "Please enter your city (e.g., Los_Angeles):"
read city
ln -sf /usr/share/zoneinfo/$region/$city /etc/localtime

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

# Give the new user sudo access if desired
echo "Does this user need sudo access? (yes/no)"
read sudo_access
if [ "$sudo_access" = "yes" ]; then
    pacman -S sudo --noconfirm
    echo "$username ALL=(ALL) ALL" >> /etc/sudoers.d/$username
    
    # Switch to the new user and install yay
    su - $username -c 'git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm'
fi

# Install bootloader (systemd-boot)
bootctl --path=/boot install

# Determine the device path of the root file system dynamically
root_device_path=$(df | grep '/$' | awk '{print $1}')

# Create loader entries for systemd-boot
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
