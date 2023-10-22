#!/bin/bash

# Get a list of drives
DRIVES=$(lsblk -dpno NAME,SIZE | grep -v "boot\|rpmb\|loop\|sr0" | awk '{print $1}')

# Convert the list into an array
DRIVES=($DRIVES)

# Print the list to the user
echo "Available drives:"
for i in "${!DRIVES[@]}"; do 
  echo "$((i+1))) ${DRIVES[$i]}"
done

# Prompt user for drive to use
read -p "Enter the number of the drive you want to use: " DRIVE_NUM

# Get the selected drive
DRIVE=${DRIVES[$((DRIVE_NUM-1))]}

# Unmount the device if it's already mounted
umount ${DRIVE}*

# Create partition
echo -e "o\nn\np\n1\n\n\nw" | fdisk ${DRIVE}

# Format the partition with BTRFS
mkfs.btrfs ${DRIVE}1

# Mount the partition
mount ${DRIVE}1 /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@opt
btrfs subvolume create /mnt/@usr_local

# Unmount the partition
umount /mnt

# Remount the subvolumes
mount -o noatime,compress=lzo,space_cache,subvol=@ ${DRIVE}1 /
mount -o noatime,compress=lzo,space_cache,subvol=@home ${DRIVE}1 /home
mount -o noatime,compress=lzo,space_cache,subvol=@snapshots ${DRIVE}1 /.snapshots
mount -o noatime,compress=lzo,space_cache,subvol=@var ${DRIVE}1 /var
mount -o noatime,compress=lzo,space_cache,subvol=@tmp ${DRIVE}1 /tmp
mount -o noatime,compress=lzo,space_cache,subvol=@srv ${DRIVE}1 /srv
mount -o noatime,compress=lzo,space_cache,subvol=@opt ${DRIVE}1 /opt
mount -o noatime,compress=lzo,space_cache,subvol=@usr_local ${DRIVE}1 /usr/local

# Create a swapfile
btrfs subvolume create /mnt/@swap
truncate -s 0 /mnt/@swap/swapfile
chattr +C /mnt/@swap/swapfile
btrfs property set /mnt/@swap/swapfile compression none
dd if=/dev/zero of=/mnt/@swap/swapfile bs=1M count=4096 status=progress
chmod 600 /mnt/@swap/swapfile
mkswap /mnt/@swap/swapfile
swapon /mnt/@swap/swapfile

echo "${DRIVE}1  /.snapshots     btrfs   noatime,compress=lzo,space_cache,subvol=@snapshots 0 0" >> /etc/fstab
echo "${DRIVE}1  /.home           btrfs   noatime,compress=lzo,space_cache,subvol=@home 0 0" >> /etc/fstab
echo "${DRIVE}1  /.var            btrfs   noatime,compress=lzo,space_cache,subvol=@var 0 0" >> /etc/fstab
echo "${DRIVE}1  /.tmp            btrfs   noatime,compress=lzo,space_cache,subvol=@tmp 0 0" >> /etc/fstab
echo "${DRIVE}1  /.srv            btrfs   noatime,compress=lzo,space_cache,subvol=@srv 0 0" >> /etc/fstab
echo "${DRIVE}1  /.opt            btrfs   noatime,compress=lzo,space_cache,subvol=@opt 0 0" >> /etc/fstab
echo "${DRIVE}1  /.usr/local      btrfs   noatime,compress=lzo,space_cache,subvol=@usr_local 0 0" >> /etc/fstab
echo "/mnt/@swap/swapfile none swap defaults 0 0" >> /etc/fstab

# Check if arch_base script exists
if [ -f "$(dirname "$0")/arch_base.sh" ]; then
  read -p "The arch_base.sh script was found in the same directory. Do you want to run it now? (y/n): " RUN_ARCH_BASE
  if [[ ${RUN_ARCH_BASE,,} == "y" ]]; then
    bash "$(dirname "$0")/arch_base.sh"
  else
    echo "Exiting the script. You can run arch_base manually later."
    exit 1
  fi
else
  echo "The arch_base script was not found in the same directory. Exiting the script."
  exit 1
fi