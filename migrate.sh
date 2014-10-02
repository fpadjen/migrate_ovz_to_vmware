#!/bin/bash

VZCTL=$(which vzctl)
VZLIST=$(which vzlist)
KVMIMG=$(which kvm-img)
WORKINGDIR=$1
MACHINE_ID=$2

if [ -z "$WORKINGDIR" ] ; then
  echo "Script to create VMware containers from OpenVZ containers."
  echo "Needs to run on the OpenVZ host. Container must be up and running."
  echo "Start with $0 /path/to/image/outputdir numeric_machine_id"
  echo "Example: $0 /tmp 1234"
  exit 0
fi


if [ -z "$VZCTL" ] || [ -z "$VZLIST" ] || [ -z "$KVMIMG" ]; then
  echo "kvm-img, vzctl or vzlist not found. Exiting."
  exit 1
fi

echo "Checking Container ID and associated disk space..."
ID=`$VZLIST -a | grep -vi stopped | awk '{print $1}' | grep -v CTID | grep $MACHINE_ID`

if [ -z "$ID" ] ; then
  echo "Container ID $MACHINE_ID not found. Exiting."
  exit 1
fi

NEEDED_SPACE=`$VZCTL exec $ID df -m | grep /$ | awk '{print $2}'`
DISKSPACE_WORKINGDIR=`df -m $WORKINGDIR | grep -v Used | awk '{print $4}'`

if [ "$((NEEDED_SPACE*2))" -gt "$DISKSPACE_WORKINGDIR" ] ; then
  echo "Not enough free space for images in $WORKINGDIR. Need at least $((NEEDED_SPACE*2))MB. Exiting."
  exit 1
fi

echo "Starting conversion."
echo "Creating empty image file $WORKINGDIR/$ID.img"
dd if=/dev/zero of=$WORKINGDIR/$ID.img bs=1M count=$NEEDED_SPACE
echo "Creating ext4 filesystem on $WORKINGDIR/$ID.img"
mkfs.ext4 -F $WORKINGDIR/$ID.img
echo "Mounting image through loopback device"
mkdir $WORKINGDIR/$ID
mount -o loop $WORKINGDIR/$ID.img $WORKINGDIR/$ID
LOOPDEV=`mount | grep $WORKINGDIR/$ID | awk '{print $3}'`

"Copying system files and modifying values for non-vz use"
rsync --numeric-ids -avP /var/lib/vz/private/$ID/* $WORKINGDIR/$ID/
sed -i -e s/127.0.0.1/127.1.1.1/g $WORKINGDIR/$ID/etc/network/interfaces
sed -i -e s/venet0:0/eth0/g $WORKINGDIR/$ID/etc/network/interfaces
echo `blkid $WORKINGDIR/$ID.img | awk '{print $2}'` / ext4 errors=remount-ro 0 1 >> $WORKINGDIR/$ID/etc/fstab
cat << EOF >> /etc/inittab
1:2345:respawn:/sbin/getty 38400 tty1
2:23:respawn:/sbin/getty 38400 tty2
3:23:respawn:/sbin/getty 38400 tty3
4:23:respawn:/sbin/getty 38400 tty4
5:23:respawn:/sbin/getty 38400 tty5
6:23:respawn:/sbin/getty 38400 tty6
EOF


echo "Installing grub and kernel"
for i in dev sys proc ; do mount --bind /$i $WORKINGDIR/$ID/$i ; done
grub-install --force --root-directory $WORKINGDIR/$ID/ $LOOPDEV
chroot $WORKINGDIR/$ID apt-get -qy install linux-image-amd64 grub-pc util-linux
chroot $WORKINGDIR/$ID update-grub

echo "Cleaning up..."
for i in dev sys proc ; do umount $WORKINGDIR/$ID/$i ; done
umount $WORKINGDIR/$ID
echo "Converting image from OpenVZ to VMware..."
kvm-img convert -f raw $WORKINGDIR/$ID.img -O vmdk $WORKINGDIR/$ID.vmdk

echo "Cleaning up..."
rm $WORKINGDIR/$ID.img
rmdir $WORKINGDIR/$ID

echo "VMware image created in $WORKINGDIR/$ID.vmdk"
echo "You can now create a new Virtualbox/VMware host and use the created image as hard disk."
