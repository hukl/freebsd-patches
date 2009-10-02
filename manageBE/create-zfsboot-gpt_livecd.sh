#!/bin/sh

pool=$1
geom=$2
swapsize=$3
sec_geom=$4

if [ "$pool" = "" ] || [ "$geom" = "" ]; then
        echo 'Usage <pool> <geom> (swapsize) (second-geom)'
        exit
fi

for disk in $geom $sec_geom; do
  dd if=/dev/zero of=/dev/$disk bs=512 count=79
  gpart create -s gpt $disk
done

if [ "$sec_geom" ]; then
   geom_size=`gpart show $geom | grep '\- free \-' | awk '{print $2}'`
   sec_geom_size=`gpart show $sec_geom | grep '\- free \-' | awk '{print $2}'`
   if [ "$geom_size" -ne "$sec_geom_size" ]; then
      echo "WARNING: $geom and $sec_geom are not the same size. Will use smaller geom as reference!"
      sleep 5
      if [ "$geom_size" -gt "$sec_geom_size" ]; then
         tmp_geom="$geom"
         geom="$sec_geom"
         sec_geom="$tmp_geom"
      fi
   fi
fi

for disk in $geom $sec_geom; do
  gpart add -b 34 -s 128 -t freebsd-boot $disk
done

if [ "$swapsize" ]; then
  swapsize=`echo "${swapsize}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`
  swapsize=`echo "${swapsize}/512" |bc`
  offset=`gpart show $geom | grep '\- free \-' | awk '{print $1}'`
  gpart add -b $offset -s $swapsize -t freebsd-swap -l swap0 $geom
fi
if [ "$sec_geom" ]; then
  gpart add -b $offset -s $swapsize -t freebsd-swap -l swap1 $sec_geom
fi

offset=`gpart show $geom | grep '\- free \-' | awk '{print $1}'`
size=`gpart show $geom | grep '\- free \-' | awk '{print $2}'`
gpart add -b $offset -s $size -t freebsd-zfs -l system-disk0 $geom
if [ "$sec_geom" ]; then
  gpart add -b $offset -s $size -t freebsd-zfs -l system-disk1 $sec_geom
fi

# Make first partition active so the BIOS boots from it
for disk in $geom $sec_geom; do
  echo 'a 1' | fdisk -f - $disk
done

kldload /mnt2/boot/kernel/opensolaris.ko
kldload /mnt2/boot/kernel/zfs.ko

# we need to create /boot/zfs so zpool.cache can be written.
mkdir /boot/zfs

# Create the pool and the rootfs
if [ "$sec_geom" ]; then 
  zpool create -f $pool mirror gpt/system-disk0 gpt/system-disk1
else
  zpool create -f $pool gpt/system-disk0
fi
zfs create -o compression=lzjb -p $pool/ROOT/$pool

# Now we create some stuff we also would like to have in seperate filesystems
for filesystem in var usr-src usr-obj usr-local tmp; do
   echo "Creating $pool/$filesystem"
   zfs create $pool/$filesystem
   zfs umount $pool/$filesystem
   _filesystem=`echo $filesystem | sed s:-:\/:g`
   zfs set mountpoint=/${_filesystem} $pool/${filesystem}
done

mkdir /$pool/ROOT/$pool/usr

zfs set mountpoint=/$pool/ROOT/$pool/usr/src $pool/usr-src
zfs mount $pool/usr-src

zfs set mountpoint=/$pool/ROOT/$pool/usr/obj $pool/usr-obj
zfs mount $pool/usr-obj

zfs set mountpoint=/$pool/ROOT/$pool/var $pool/var
zfs mount $pool/var

echo ####################################
echo 'Now install world, kernel etc'
zfs create $pool/installdata
cd /$pool/installdata

ftphost='192.168.23.1'
sleep 5
arch=`uname -p`
release=`uname -r`
for pkg in base kernels; do
    mkdir /$pool/installdata/${pkg}
    cd /$pool/installdata/${pkg}
    ftp "$ftphost:pub/FreeBSD/releases/${arch}/${release}/${pkg}/*"
done
mkdir /$pool/installdata/src
cd /$pool/installdata/src/
ftp "$ftphost:pub/FreeBSD/releases/${arch}/${release}/src/ssys*"
ftp "$ftphost:pub/FreeBSD/releases/${arch}/${release}/src/slib*"
ftp "$ftphost:pub/FreeBSD/releases/${arch}/${release}/src/install.sh"

export DESTDIR=/$pool/ROOT/$pool/

cd /$pool/installdata/base ;   yes | sh ./install.sh
cd /$pool/installdata/src ;     sh ./install.sh sys lib
echo "Extracting kernel into $DESTDIR/boot"
cd /$pool/installdata/kernels ; sh ./install.sh generic

cd /$pool/ROOT/$pool/boot ; cp -rp GENERIC/* /$pool/ROOT/$pool/boot/kernel/

echo 'LOADER_ZFS_SUPPORT=YES' >> /$pool/ROOT/$pool/etc/make.conf

echo "Build ZFS aware boot-loader"
echo '#!/bin/sh 
mount -t devfs devfs /dev 
export DESTDIR="" 
cd /usr/src/sys/boot/ 
make obj 
make depend 
make 
cd /usr/src/sys/boot/i386/loader; make install 
cd /usr/src/sys/boot/i386/zfsboot; make install 
cd /usr/src/sys/boot/i386/gptzfsboot; make install 
cd /usr/src/sys/boot/i386/pmbr; make install 
umount /dev 
exit' > /$pool/ROOT/$pool/tmp/chroot-command.sh
chmod +x /$pool/ROOT/$pool/tmp/chroot-command.sh
chroot /$pool/ROOT/$pool/ /tmp/chroot-command.sh
rm /$pool/ROOT/$pool/tmp/chroot-command.sh
zfs destroy $pool/installdata

echo "Install new bootcode"
for disk in $geom $sec_geom; do
  gpart bootcode -b /$pool/ROOT/$pool/boot/pmbr -p /$pool/ROOT/$pool/boot/gptzfsboot -i 1 $disk
done

# We need to fix /var so it is mounted correct when booting from ZFS
zfs umount $pool/var
zfs set mountpoint=/var $pool/var

# We need to fix /usr/src so it is mounted correct when booting from ZFS
zfs umount $pool/usr-src
zfs set mountpoint=/usr/src $pool/usr-src

# We need to fix /usr/obj so it is mounted correct when booting from ZFS
zfs umount $pool/usr-obj
zfs set mountpoint=/usr/obj $pool/usr-obj

# Enable the new filesystem as zpool bootfs
zpool set bootfs=$pool/ROOT/$pool $pool

# We still need to tell the kernel from where to mount its root-filesystem
echo 'zfs_load="YES"' >> /$pool/ROOT/$pool/boot/loader.conf
echo "vfs.root.mountfrom=\"zfs:$pool/ROOT/$pool\"" >> /$pool/ROOT/$pool/boot/loader.conf
echo 'zfs_enable="YES"' >> /$pool/ROOT/$pool/etc/rc.conf
touch /$pool/ROOT/$pool/etc/fstab

if [ "$swapsize" ]; then
  echo "/dev/gpt/swap0 none swap sw 0 0" > /$pool/ROOT/$pool/etc/fstab
fi

# Copy the zpool.cache to the new filesystem
cp /boot/zfs/zpool.cache /$pool/ROOT/$pool/boot/zfs/zpool.cache

sleep 5

echo "Please reboot the system from the harddisk(s), remove the FreeBSD from you cdrom!"
