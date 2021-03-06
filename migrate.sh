#!/bin/bash

if [ "$#" -ne 2 ] ; then
  echo "Script to create VMware containers from OpenVZ containers."
  echo "Needs to run on the OpenVZ host. Container must be up and running."
  echo "Start with $0 /path/to/image/outputdir numeric_machine_id"
  echo "Example: $0 /tmp 1234"
  exit 0
fi

VZCTL=$(which vzctl)
VZLIST=$(which vzlist)
KVMIMG=$(which kvm-img)
WORKINGDIR=$1
MACHINE_ID=$2
IMAGE_NAME=`$VZLIST -a | grep -w $MACHINE_ID | awk '{print $5}'`


if [ -z "$VZCTL" ] || [ -z "$VZLIST" ] || [ -z "$KVMIMG" ]; then
  echo "kvm-img, vzctl or vzlist not found. Exiting."
  exit 1
fi

echo "Checking Container ID and associated disk space..."
ID=`$VZLIST -a | grep -vi stopped | awk '{print $1}' | grep -v CTID | grep -w $MACHINE_ID`

if [ -z "$ID" ] ; then
  echo "Container ID $MACHINE_ID not found. Exiting."
  exit 1
fi

NEEDED_SPACE=`$VZCTL exec $ID df -Pm | grep /$ | awk '{print $2}'`
DISKSPACE_WORKINGDIR=`df -Pm $WORKINGDIR | grep -v Used | awk '{print $4}'`

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
echo `blkid $WORKINGDIR/$ID.img | awk '{print $2}'` / ext4 errors=remount-ro 0 1 >> $WORKINGDIR/$ID/etc/fstab
cat << EOF > $WORKINGDIR/$ID/etc/inittab
id:2:initdefault:
si::sysinit:/etc/init.d/rcS
~~:S:wait:/sbin/sulogin
l0:0:wait:/etc/init.d/rc 0
l1:1:wait:/etc/init.d/rc 1
l2:2:wait:/etc/init.d/rc 2
l3:3:wait:/etc/init.d/rc 3
l4:4:wait:/etc/init.d/rc 4
l5:5:wait:/etc/init.d/rc 5
l6:6:wait:/etc/init.d/rc 6
z6:6:respawn:/sbin/sulogin
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
pf::powerwait:/etc/init.d/powerfail start
pn::powerfailnow:/etc/init.d/powerfail now
po::powerokwait:/etc/init.d/powerfail stop
1:2345:respawn:/sbin/getty 38400 tty1
2:23:respawn:/sbin/getty 38400 tty2
3:23:respawn:/sbin/getty 38400 tty3
4:23:respawn:/sbin/getty 38400 tty4
5:23:respawn:/sbin/getty 38400 tty5
6:23:respawn:/sbin/getty 38400 tty6
EOF


echo "Installing grub and kernel"
for i in dev sys proc ; do mount --bind /$i $WORKINGDIR/$ID/$i ; done
chroot $WORKINGDIR/$ID apt-get update
grub-install --force --root-directory $WORKINGDIR/$ID/ $LOOPDEV
chroot $WORKINGDIR/$ID apt-get -qy install linux-image-amd64 grub-pc util-linux mingetty
chroot $WORKINGDIR/$ID update-grub
echo "Please enter new rootpw:"
chroot $WORKINGDIR/$ID passwd

echo "Cleaning up..."
for i in dev sys proc ; do umount $WORKINGDIR/$ID/$i ; done
umount $WORKINGDIR/$ID
echo "Converting image from OpenVZ to VMware..."
if [ -z "$IMAGE_NAME" ] ; then
  IMAGE_NAME=$ID
fi
kvm-img convert -f raw $WORKINGDIR/$ID.img -O vmdk $WORKINGDIR/$IMAGE_NAME.vmdk

echo "Cleaning up..."
rm $WORKINGDIR/$ID.img
rmdir $WORKINGDIR/$ID

echo "VMware image created in $WORKINGDIR/$IMAGE_NAME.vmdk"
echo "You can now create a new Virtualbox/VMware host and use the created image as hard disk."
