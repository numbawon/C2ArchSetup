#!/bin/bash

# Get a list of drives
DRIVES=$(lsblk -dpno NAME,SIZE | grep -v "boot\|rpmb\|loop\|sr0" | awk '{print $1}')

# Convert the list into an array
DRIVES=("$DRIVES")

# Print the list to the user
echo "Available drives:"
for i in "${!DRIVES[@]}"; do 
  echo "$((i+1))) ${DRIVES[$i]}"
done

# Prompt user for drive to use
read -rp "Enter the number of the drive you want to use: " DRIVE_NUM

# Get the selected drive
DRIVE=${DRIVES[$((DRIVE_NUM-1))]}

# Unmount the device if it's already mounted
umount "${DRIVE}"*

# Create partitions
echo -e "o\nn\np\n1\n\n+500M\nt\nc\nn\np\n2\n\n\nw" | fdisk "${DRIVE}"

# Format the boot partition with FAT32
mkfs.fat -F32 "${DRIVE}"1

# Format the main partition with BTRFS
mkfs.btrfs "${DRIVE}"2

# Mount the main partition
mount "${DRIVE}"2 /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@opt
btrfs subvolume create /mnt/@usr_local

# Unmount the main partition
umount /mnt

# Remount the subvolumes
mount -o noatime,compress=lzo,space_cache,subvol=@ "${DRIVE}"2 /
mount -o noatime,compress=lzo,space_cache,subvol=@home "${DRIVE}"2 /home
mount -o noatime,compress=lzo,space_cache,subvol=@snapshots "${DRIVE}"2 /.snapshots
mount -o noatime,compress=lzo,space_cache,subvol=@var "${DRIVE}"2 /var
mount -o noatime,compress=lzo,space_cache,subvol=@tmp "${DRIVE}"2 /tmp
mount -o noatime,compress=lzo,space_cache,subvol=@srv "${DRIVE}"2 /srv
mount -o noatime,compress=lzo,space_cache,subvol=@opt "${DRIVE}"2 /opt
mount -o noatime,compress=lzo,space_cache,subvol=@usr_local "${DRIVE}"2 /usr/local

# Mount the boot partition to /boot/efi (required for UEFI)
mkdir -p /boot/
mount "${DRIVE}"1 /boot/

# Create a swapfile
btrfs subvolume create /mnt/@swap
truncate -s 0 /mnt/@swap/swapfile
chattr +C /mnt/@swap/swapfile
btrfs property set /mnt/@swap/swapfile compression none
dd if=/dev/zero of=/mnt/@swap/swapfile bs=1M count=4096 status=progress
chmod 600 /mnt/@swap/swapfile
mkswap /mnt/@swap/swapfile
swapon /mnt/@swap/swapfile

# Check if arch_base.sh script exists
if [ -f "$(dirname "$0")/arch_base.sh" ]; then
  read -rp "The arch_base script was found in the same directory. Do you want to run it now? (y/n): " RUN_ARCH_BASE
  if [[ ${RUN_ARCH_BASE,,} == "y" ]]; then
    bash "$(dirname "$0")/arch_base.sh"
  else
    echo "Exiting the script. You can run arch_base.sh manually later."
    exit 1
  fi
else
  echo "The arch_base.sh script was not found in the same directory. Exiting the script."
  exit 1
fi
end
