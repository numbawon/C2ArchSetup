#!/bin/bash

echo "Updating system..."
pacman -Syu --noconfirm

echo "Installing GNOME..."
pacman -S gnome --noconfirm

echo "Enabling GDM..."
systemctl enable gdm.service

echo "The gnome-extra group includes the following packages:"
pacman -Sg gnome-extra | awk '{print $2}'

read -rp "Do you want to install GNOME extras? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo "Installing GNOME extras..."
    pacman -S gnome-extra --noconfirm
fi

echo "Identifying graphics card..."
gpu_info=$(lspci | grep VGA)
echo "$gpu_info"

if echo "$gpu_info" | grep -iq "nvidia"
then
    echo "NVIDIA graphics card detected."
    echo "Installing NVIDIA graphics drivers..."
    pacman -S nvidia nvidia-utils --noconfirm
elif echo "$gpu_info" | grep -iq "intel"
then
    echo "Intel graphics card detected."
    echo "Installing Intel graphics drivers..."
    pacman -S mesa xf86-video-intel --noconfirm
elif echo "$gpu_info" | grep -iq "amd"
then
    echo "AMD graphics card detected."
    echo "Installing AMD graphics drivers..."
    pacman -S mesa xf86-video-amdgpu --noconfirm
else
    echo "Graphics card not recognized. Installing generic vesa driver..."
    pacman -S xf86-video-vesa --noconfirm
fi

echo "Listing all users..."
IFS=$'\n' read -d '' -r -a users < <(awk -F':' '{ print $1}' /etc/passwd)
for i in "${!users[@]}"; do 
  echo "$((i+1)). ${users[$i]}"
done

read -rp "Do you want to add all users as administrators? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    for user in "${users[@]}"; do
        usermod -aG wheel "$user"
        echo "$user is now an administrator."
    done
else
    read -rp "Enter the number of the user you want to add as an administrator: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#users[@]} ]; then
        user=${users[$((num-1))]}
        usermod -aG wheel "$user"
        echo "$user is now an administrator."
    else
        echo "Invalid input. No changes made."
    fi
fi

read -rp "Do you want to remain in the chrooted system? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo "You are still in the chrooted system. You can exit and reboot when you are ready."
else
    echo "Exiting chroot and rebooting..."
    exit
    reboot
fi
