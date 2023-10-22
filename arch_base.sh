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
else
    region=$(echo $timezone | cut -d'/' -f1)
fi
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

# Install and configure reflector to find the fastest mirrors regardless of location
pacman -S --noconfirm reflector
reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

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

# Install NetworkManager and PipeWire, enable NetworkManager to start at boot.
pacman -S --noconfirm networkmanager pipewire pipewire-alsa pipewire-pulse pipewire-jack 
systemctl enable NetworkManager 

# Prompt the user for their choice of kernel and install it.
echo "Please enter your choice of kernel (e.g., linux, linux-lts, linux-hardened, linux-zen):"
read kernel_choice
pacman -S --noconfirm $kernel_choice

# Check if Secure Boot is enabled and prepare for self-signed kernel if it is.
if [ "$(mokutil --sb-state)" == "SecureBoot enabled" ]; then 
    echo "Secure Boot is enabled on this system."
    echo "Do you want to prepare this device for a self-signed kernel? (yes/no)"
    read secure_boot_answer
    
    if [ "$secure_boot_answer" = "yes" ]; then 
        # Install required packages for signing and MOK maintenance.
        pacman -S sbsigntools efitools openssl mokutil
        
        # Generate and self-sign the kernel.
        openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=My Secure Boot Signing Key/"
        openssl x509 -in MOK.der -inform DER -outform PEM -out MOK.pem
        sbsign --key MOK.priv --cert MOK.pem /boot/vmlinuz-$kernel_choice --output /boot/vmlinuz-$kernel_choice.signed

        # Enroll the key.
        mokutil --import MOK.der

        # Create a pacman hook for the chosen kernel.
        echo "[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = $kernel_choice

[Action]
Description = Sign the kernel for secure boot...
When = PostTransaction
Exec = /usr/bin/sbsign --key /path/to/MOK.priv --cert /path/to/MOK.pem /boot/vmlinuz-$kernel_choice --output /boot/vmlinuz-$kernel_choice.signed
Depends = sbsigntools" > /etc/pacman.d/hooks/100-sign-$kernel_choice.hook
    fi 
fi 

# Install bootloader (systemd-boot)
bootctl --path=/boot install

# Determine the device path of the root file system dynamically.
root_device_path=$(df | grep '/$' | awk '{print $1}')

# Create loader entries for systemd-boot.
echo "default arch" > /boot/loader/loader.conf
echo "title Arch Linux" > /boot/loader/entries/arch.conf
echo "linux /vmlinuz-$kernel_choice.signed" >> /boot/loader/entries/arch.conf
echo "initrd  /initramfs-$kernel_choice.img" >> /boot/loader/entries/arch.conf
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value $root_device_path) rw resume=/@swap/swapfile" >> /boot/loader/entries/arch.conf

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

# Prompt the user if they are ready to reboot
echo "Are you ready to reboot? (yes/no)"
read reboot_answer
if [ "$reboot_answer" = "yes" ]; then 
    # Exit the chroot environment and reboot.
    exit 
    reboot 
else 
    echo "Please type 'reboot' when you are ready to reboot the system."
fi
