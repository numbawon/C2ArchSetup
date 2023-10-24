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
read -r timezone_answer
if [ "$timezone_answer" != "yes" ]; then 
    echo "Please enter your region (e.g., America):"
    read -r region
    echo "Please enter your city (e.g., Los_Angeles):"
    read -r city
    timezone="$region/$city"
else
    region=$(echo "$timezone" | cut -d'/' -f1)
fi
ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime

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
read -r hostname
echo "$hostname" >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts

# Initramfs
mkinitcpio -P

# Set root password
echo "Please enter your desired root password:"
passwd

# Create a new user account
echo "Please enter your desired username:"
read -r username
useradd -m "$username"
echo "Please enter a password for this user:"
passwd "$username"

# Give the new user sudo access if desired and install yay as the new user
echo "Does this user need sudo access? (yes/no)"
read -r sudo_access
if [ "$sudo_access" = "yes" ]; then
    pacman -S sudo --noconfirm
    echo "$username ALL=(ALL) ALL" >> "/etc/sudoers.d/$username"
    
    # Switch to the new user and install yay, then return to the root user.
    su - "$username" -c 'git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm'
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
read -r kernel_choice
pacman -S --noconfirm "$kernel_choice"

# Check if Secure Boot is enabled and prepare for self-signed kernel if it is.
if [ "$(mokutil --sb-state)" == "SecureBoot enabled" ]; then 
    echo "Secure Boot is enabled on this system."
    echo "Do you want to prepare this device for a self-signed kernel? (yes/no)"
    read -r secure_boot_answer
    
    if [ "$secure_boot_answer" = "yes" ]; then 
        # Install required packages for signing and MOK maintenance.
        pacman -S sbsigntools efitools openssl mokutil
        
        # Generate and self-sign the kernel.
        openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=My Secure Boot Signing Key/"
        openssl x509 -in MOK.der -inform DER -outform PEM -out MOK.pem
        sbsign --key MOK.priv --cert MOK.pem "/boot/vmlinuz-$kernel_choice" --output "/boot/vmlinuz-$kernel_choice.signed"

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
Exec = /usr/bin/sbsign --key /path/to/MOK.priv --cert "/path/to/MOK.pem /boot/vmlinuz-$kernel_choice" --output "/boot/vmlinuz-$kernel_choice.signed"
Depends = sbsigntools" > "/etc/pacman.d/hooks/100-sign-$kernel_choice.hook"
    fi 
fi 

# Install necessary packages
pacman -S --noconfirm grub efibootmgr btrfs-progs grub-btrfs

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

# Check for the location of the swap
swap_info=$(swapon --show=NAME,TYPE --noheadings)
read -r swap_name swap_type <<< "$swap_info"

if [ "$swap_type" == "partition" ]; then
    # If it's a separate swap partition, use its UUID
    swap_uuid=$(findmnt -no UUID -T "$swap_name")
elif [ "$swap_type" == "file" ]; then
    # If it's a swap file, use the UUID of the partition containing it and find the resume_offset
    swap_uuid=$(findmnt -no UUID -T "$swap_name")
    resume_offset=$(filefrag -v "$swap_name" | awk '{if($1=="0:"){print $4}}')
fi

# Add resume UUID and resume_offset (if exists) to GRUB command line
if [ -z "$resume_offset" ]; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$swap_uuid\"" >> /etc/default/grub
else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$swap_uuid resume_offset=$resume_offset\"" >> /etc/default/grub
fi

# Generate GRUB configuration file
grub-mkconfig -o /boot/grub/grub.cfg

# Check if the root filesystem is Btrfs
if [ "$(df -T / | tail -n 1 | awk '{print $2}')" == "btrfs" ]; then

    echo "The root filesystem is Btrfs."

    # Prompt the user to install and configure Snapper
    read -rp "Do you want to install and configure Snapper? (y/n) " answer
    if [ "$answer" == "y" ]; then
        # Install snapper
        pacman -S --noconfirm snapper

        # Get a list of all Btrfs subvolumes
        subvolumes=$(btrfs subvolume list / | awk '{print $9}')

        # Prompt the user to select subvolumes to create configurations for
        echo "Please select the subvolumes you want to create configurations for:"
        select subvolume in $subvolumes; do
            echo "$REPLY) $subvolume"
        done

        read -rp "Enter your selection (e.g., 1,2,4 or 1-5 or all): " selection

        # Parse the selection and create Snapper configurations
        if [ "$selection" == "all" ]; then
            for subvolume in $subvolumes; do
                snapper -c "$subvolume" create-config "/$subvolume"
            done
        else
            IFS=',-' read -ra ranges <<< "$selection"
            for range in "${ranges[@]}"; do
                if [[ $range =~ ^[0-9]+$ ]]; then
                    snapper -c "${subvolumes[$range-1]}" create-config "/${subvolumes[$range-1]}"
                else
                    IFS='-' read -r start end <<< "$range"
                    for ((i=start; i<=end; i++)); do
                        snapper -c "${subvolumes[$i-1]}" create-config "/${subvolumes[$i-1]}"
                    done
                fi
            done
        fi

        # Enable and start the Snapper services
        systemctl enable snapper-timeline.timer
        systemctl start snapper-timeline.timer

        echo "Snapper has been configured successfully."
    else
        echo "Snapper will not be installed or configured."
    fi

else
    echo "The root filesystem is not Btrfs."
fi
# Check for any *_dm_setup.sh scripts in the current directory and prompt the user to run one if any are found.
setup_scripts=(*_dm_setup.sh)
if [ ${#setup_scripts[@]} -ne 0 ]; then
    echo "The following desktop manager setup scripts were found:"
    for i in "${!setup_scripts[@]}"; do 
        echo "$((i+1)). ${setup_scripts[$i]}"
    done
    
    echo "Would you like to run one of these scripts? (yes/no)"
    read -r run_script_answer
    
    if [ "$run_script_answer" = "yes" ]; then 
        echo "Please enter the number of the script you would like to run:"
        read -r script_number
        
        if [ "$script_number" -ge 1 ] && [ "$script_number" -le ${#setup_scripts[@]} ]; then 
            ./"${setup_scripts[$((script_number-1))]}"
        else 
            echo "Invalid selection."
        fi 
    fi 
fi 

# Prompt the user if they are read -ry to reboot
echo "Are you read -ry to reboot? (yes/no)"
read -r reboot_answer
if [ "$reboot_answer" = "yes" ]; then 
    # Exit the chroot environment and reboot.
    exit 
    reboot
else 
    echo "Please type 'reboot' when you are read -ry to reboot the system."
fi
