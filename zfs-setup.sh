#!/usr/bin/env bash

# A NixOS partition scheme with UEFI boot, root on tmpfs, everything else 
# on encrypted ZFS datasets, and no swap.
# This script wipes and formats the selected disk, and creates the following:
# 1. 1GB FAT32 UEFI boot partition (each Nix generation consumes about 20MB on 
#    /boot, so size this based on how many generations you want to store)
# 2. Encrypted ZFS pool comprising all remaining disk space - rpool
# 3. Tmpfs root - /
# 4. ZFS datasets - rpool/local/nix, rpool/safe/[home,persist], rpool/reserved
# 5. mounts all of the above (except rpool/reserved which should never be mounted)
# 6. generates hardware-configuration.nix customized to this machine and tmpfs
# 7. generates a generic default configuration.nix replace-able with a custom one
#
# https://www.reddit.com/r/NixOS/comments/o1er2p/tmpfs_as_root_but_without_hardcoding_your/
# https://www.reddit.com/r/NixOS/comments/g9wks6/root_on_tmpfs/
# https://grahamc.com/blog/nixos-on-zfs
# https://grahamc.com/blog/erase-your-darlings
# https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/
# https://elis.nu/blog/2020/06/nixos-tmpfs-as-home/
# 
# Disk Partitions:
# sda
# ├─sda1            /boot EFI BOOT
# └─sda2            rpool ZFS POOL
#
# Mount Layout:
# /		    tmpfs
# ├─/boot           /dev/sda1
# ├─/nix	    rpool/local/nix
# ├─/home	    rpool/safe/home
# └─/persist	    rpool/safe/persist

#useful commands
# mount -l | grep sda
# findmnt | grep zfs
# lsblk
# ncdu -x /
# zpool list
# zfs list -o name,mounted,mountpoint
# zfs mount (only usable with non-legacy datasets)
# zfs unmount -a (unmount everything, only usable with non-legacy datasets)
# umount -R /mnt (unmount everything in /mnt recursively, required for legacy zfs datasets)
# zpool export $POOL (disconnects the pool)
# zpool remove $POOL sda1 (removes the disk from your zpool)
# zpool destroy $POOL (this destroys the pool and it's gone and rather difficult to retrieve)

# Some ZFS properties cannot be changed after the pool and/or datasets are created.  Some discussion on this:
# https://www.reddit.com/r/zfs/comments/nsc235/what_are_all_the_properties_that_cant_be_modified/
# `ashift` is one of these properties, but is easy to determine.  Use the following commands:
# disk logical blocksize:  `$ sudo blockdev --getbsz /dev/sdX` (ashift)
# disk physical blocksize: `$ sudo blockdev --getpbsz /dev/sdX` (not ashift but interesting)

#set -euo pipefail
set -e

pprint () {
    local cyan="\e[96m"
    local default="\e[39m"
    # ISO8601 timestamp + ms
    local timestamp
    timestamp=$(date +%FT%T.%3NZ)
    echo -e "${cyan}${timestamp} $1${default}" 1>&2
}

# Select DISK to format and install to
echo # move to a new line
pprint "> Select installation disk: "
select ENTRY in $(ls /dev/disk/by-id/);
do
    DISK="/dev/disk/by-id/$ENTRY"
    echo "Installing system on $ENTRY."
    break
done

# Set ZFS pool name
read -p "> Name your ZFS pool: " POOL
read -p "> You entered '$POOL'.  Is this correct?  (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

# Confirm wipe hdd
read -p "> Do you want to wipe all data on $ENTRY ?" -n 1 -r
echo # move to a new line
if [[ "$REPLY" =~ ^[Yy]$ ]]
then
    # Clear disk (sometimes need to run wipefs twice when deleting ZFS pools)
    # May also need to `umount -R /mnt`
    pprint "Wiping $DISK. If errors occur, make sure all $DISK partitions are umounted and ZFS Pools are exported and/or destroyed."
    pprint "To do so, run 'findmnt' to see all current mounts, umount /dev/sdX to unmount, and zpool export <poolname>." 
    wipefs -af "$DISK"
    sleep 1
    wipefs -af "$DISK"
    sgdisk -Zo "$DISK"
fi

# if you're new to sgdisk, see these guides by its developer:
# https://www.rodsbooks.com/gdisk/
# https://www.rodsbooks.com/gdisk/walkthrough.html
pprint "Creating boot (EFI) partition ..."
sgdisk -n 0:0:+954M -t 0:EF00 -c 0:efiboot $DISK
BOOT="$DISK-part1"

pprint "Creating ZFS partition ..."
sgdisk -n 0:0:0 -t 0:BF01 -c 0:zfspool $DISK
ZFS="$DISK-part2"

# Inform kernel
partprobe "$DISK"
sleep 1

pprint "Formatting BOOT partition $BOOT as FAT32 ... "
mkfs.vfat -F 32 "$BOOT"

# Inform kernel
partprobe "$DISK"
sleep 1

pprint "Creating ZFS pool on $ZFS ..."
# -f force
# -m none (mountpoint), canmount=off.  ZFS datasets on this pool unmountable 
# unless explicitly specified otherwise in 'zfs create'.
# Use blockdev --getbsz /dev/sdX to find correct ashift for your disk.
# acltype=posix, xattr=sa required
# atime=off and relatime=on for performance
# recordsize depends on usage, 16k for database server or similar, 1M for home media server with large files
# normalization=formD for max compatility
# secondarycache=none to disable L2ARC which is not needed
# more info on pool properties:
# https://nixos.wiki/wiki/NixOS_on_ZFS#Dataset_Properties
# https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
zpool create -f	-m none	-R /mnt	\
	-o ashift=12				\
	-o listsnapshots=on			\
	-O acltype=posix			\
	-O compression=lz4			\
	-O encryption=on			\
	-O keylocation=prompt		\
	-O keyformat=passphrase 	\
	-O canmount=off				\
	-O atime=off				\
	-O relatime=on 				\
	-O recordsize=1M			\
	-O dnodesize=auto			\
	-O xattr=sa					\
	-O normalization=formD		\
	$POOL $ZFS

pprint "Creating ZFS datasets nix, opt, home, persist, reserved ..."
zfs create -p -v -o secondarycache=none -o mountpoint=legacy ${POOL}/local/nix
zfs create -p -v -o secondarycache=none -o mountpoint=legacy ${POOL}/safe/home
zfs create -p -v -o secondarycache=none -o mountpoint=legacy ${POOL}/safe/persist
# create an unused, unmounted 2GB dataset.  In case the rest of the pool runs out 
# of space required for ZFS operations (even deletions require disk space in a 
# copy-on-write filesystem), shrink or delete this pool to free enough
# space to continue ZFS operations.
# https://nixos.wiki/wiki/NixOS_on_ZFS#Reservations
zfs create -o refreservation=2G -o primarycache=none -o secondarycache=none -o mountpoint=none ${POOL}/reserved

pprint "Enabling auto-snapshotting for ${POOL}/safe/[home,persist] datasets ..."
zfs set com.sun:auto-snapshot=true ${POOL}/safe

pprint "Mounting Tmpfs and ZFS datasets ..."
mkdir -p /mnt
mount -t tmpfs tmpfs /mnt
mkdir -p /mnt/nix
mount -t zfs ${POOL}/local/nix /mnt/nix
mkdir -p /mnt/home
mount -t zfs ${POOL}/safe/home /mnt/home
mkdir -p /mnt/persist
mount -t zfs ${POOL}/safe/persist /mnt/persist
mkdir -p /mnt/boot
mount -t vfat "$BOOT" /mnt/boot

pprint "Making /mnt/persist/ subdirectories for persisted artifacts ..."
mkdir -p /mnt/persist/etc/ssh
mkdir -p /mnt/persist/etc/users
mkdir -p /mnt/persist/etc/nixos
mkdir -p /mnt/persist/etc/wireguard/
mkdir -p /mnt/persist/etc/NetworkManager/system-connections
mkdir -p /mnt/persist/var/lib/bluetooth
mkdir -p /mnt/persist/var/lib/acme

pprint "Generating NixOS configuration ..."
nixos-generate-config --force --root /mnt

# Specify machine-specific properties for hardware-configuration.nix
HOSTID=$(head -c8 /etc/machine-id)

HARDWARE_CONFIG=$(mktemp)
cat <<CONFIG > "$HARDWARE_CONFIG"
  networking.hostId = "$HOSTID";
  boot.zfs.devNodes = "$ZFS";
CONFIG

# Add extra Tmpfs config options to the / mount section in hardware-configuration.nix
# mode=755: required for some software like openssh, or will complain about permissions
# size=2G: Tmpfs size. A fresh NixOS + Gnome4 install can use 30MB - 230MB on tmpfs.
# size=512M is sufficient, or larger if you have enough RAM and want more headroom.
# backing up original to /mnt/etc/nixos/hardware-configuration.nix.original.
# https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/#step-4-1-configure-disks
pprint "Adding Tmpfs options to hardware-configuration.nix ..."
sed --in-place=.original '/fsType = "tmpfs";/a\      options = [ "defaults" "size=2G" "mode=755" ];' /mnt/etc/nixos/hardware-configuration.nix

pprint "Appending machine-specific properties to hardware-configuration.nix ..."
sed -i "\$e cat $HARDWARE_CONFIG" /mnt/etc/nixos/hardware-configuration.nix

# Password
read -p "> Set password for lfron user?" -n 1 -r
echo # move to a new line
if [[ "$REPLY" =~ ^[Yy]$ ]]
then
    mkpasswd -m sha-512 > /mnt/persist/etc/users/lfron
fi

cp "$PWD"/configuration.nix /mnt/etc/nixos/configuration.nix
cp "$PWD"/configuration.nix /mnt/persist/etc/nixos/configuration.nix
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/persist/etc/nixos/hardware-configuration.nix


pprint "Configuration complete.  To install, run 'nixos-install --no-root-passwd'."
#if install fails, try the install script below:

# ---- install script ---- 
# #!/usr/bin/env bash
# install NixOS with no root password
#set -e
# If nixos-install fails, may need to prepend this nixos-build line to install script:
# https://github.com/NixOS/nixpkgs/issues/126141#issuecomment-861720372
#nix-build -v '<nixpkgs/nixos>' -A config.system.build.toplevel -I nixos-config=/mnt/etc/nixos/configuration.nix
# install NixOS with no root password.  Must use `passwd` on first use to set user password.
#nixos-install -v --show-trace --no-root-passwd
# ---- /install script ----
