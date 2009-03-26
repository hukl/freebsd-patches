#!/bin/sh

pool=$1
geom=$2
swapsize=$3

if [ "$pool" = "" ] || [ "$geom" = "" ]; then
        echo 'Usage <pool> <geom> (swapsize)'
        exit
fi

swapsize=`echo "${swapsize}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`
swapsize=`echo "${swapsize}/512" |bc`

gpart create -s gpt $geom
gpart add -b 34 -s 128 -t freebsd-boot $geom
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $geom

if [ "$swapsize" ]; then
  offset=`gpart show $geom | grep '\- free \-' | awk '{print $1}'`
  gpart add -b $offset -s $swapsize -t freebsd-swap $geom
  partnum=`gpart show $geom | grep 'freebsd\-swap' |awk '{print $3}'`
  glabel create swap /dev/${geom}p${partnum}
fi

offset=`gpart show $geom | grep '\- free \-' | awk '{print $1}'`
size=`gpart show $geom | grep '\- free \-' | awk '{print $2}'`
gpart add -b $offset -s $size -t freebsd-zfs $geom
partnum=`gpart show $geom | grep 'freebsd\-zfs' |awk '{print $3}'`

# Make first partition active so the BIOS boots from it
echo 'a 1' | fdisk -f - $geom

# Create the pool and the rootfs
zpool create $pool ${geom}p${partnum}
zfs create -o compression=lzjb -p $pool/ROOT/$pool

# Now we create some stuff we also would like to have in seperate filesystems
for filesystem in var usr-local tmp; do
   echo "Creating $pool/$filesystem"
   zfs create $pool/$filesystem
   zfs umount $pool/$filesystem
   _filesystem=`echo $filesystem | sed s:-:\/:g`
   zfs set mountpoint=/${_filesystem} $pool/${filesystem}
done

zfs set mountpoint=/$pool/ROOT/$pool/var $pool/var
zfs mount $pool/var

echo ####################################
echo 'Now install world, kernel etc'
cd /usr/src
make -s installkernel DESTDIR=/$pool/ROOT/$pool/
make -s installworld DESTDIR=/$pool/ROOT/$pool/
mergemaster -i -D /$pool/ROOT/$pool/

# We need to fix /var so it is mounted correct when booting from ZFS
zfs umount $pool/var
zfs set mountpoint=/var $pool/var

# Enable the new filesystem as zpool bootfs
zpool set bootfs=$pool/ROOT/$pool $pool

# We still need to tell the kernel from where to mount its root-filesystem
echo 'zfs_load="YES"' >> /$pool/ROOT/$pool/boot/loader.conf
echo "vfs.root.mountfrom=\"zfs:$pool/ROOT/$pool\"" >> /$pool/ROOT/$pool/boot/loader.conf
echo 'zfs_enable="YES"' >> /$pool/ROOT/$pool/etc/rc.conf

if [ "$swapsize" ]; then
  echo 'geom_label_load="YES"' >> /$pool/ROOT/$pool/boot/loader.conf
  echo "/dev/label/swap none swap sw 0 0" > /$pool/ROOT/$pool/etc/fstab
fi

# Copy the zpool.cache to the new filesystem
cp /boot/zfs/zpool.cache /$pool/ROOT/$pool/boot/zfs/zpool.cache

zpool export $pool
