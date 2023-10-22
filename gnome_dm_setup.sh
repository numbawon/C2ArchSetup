#!/bin/bash

echo "Updating system..."
pacman -Syu --noconfirm

echo "Installing GNOME..."
pacman -S gnome --noconfirm

echo "The gnome-extra group includes the following packages:"
pacman -Sg gnome-extra | awk '{print $2}'

read -p "Do you want to install GNOME extras? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo "Installing GNOME extras..."
    pacman -S gnome-extra --noconfirm
fi

echo "Listing all users..."
users=($(awk -F':' '{ print $1}' /etc/passwd))
for i in "${!users[@]}"; do 
  echo "$((i+1)). ${users[$i]}"
done

read -p "Do you want to add all users as administrators? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    for user in "${users[@]}"; do
        usermod -aG wheel $user
        echo "$user is now an administrator."
    done
else
    read -p "Enter the number of the user you want to add as an administrator: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#users[@]} ]; then
        user=${users[$((num-1))]}
        usermod -aG wheel $user
        echo "$user is now an administrator."
    else
        echo "Invalid input. No changes made."
    fi
fi

read -p "Do you want to remain in the chrooted system? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo "You are still in the chrooted system. You can exit and reboot when you are ready."
else
    echo "Exiting chroot and rebooting..."
    exit
    reboot
fi