#!/bin/sh
# Philipp Wuensche
# This script is considered beer ware (http://en.wikipedia.org/wiki/Beerware)
#
# DISCLAIMER: Use at your own risk! Always make backups, don't blame me if this renders your system unusable or you lose any data! 
# 
# This only works with FreeBSD 8.0 (tested with 8.0-RC1), you have been warned!
#
# Startup the FreeBSD livefs CD. Go into the Fixit console. Create /var/db if you want to use DHCP. Configure
# your network settings. Fetch http://anonsvn.h3q.com/projects/freebsd-patches/browser/manageBE/create-zfsboot-gpt_livecd.sh?format=txt
# Execute the script with the following parameter:
#
# -p sets the geom provider to use
# -s sets the swapsize to create, you can use m/M for megabyte or g/G for gigabyte
# -n sets the name of the zpool to create
# -f sets the ftp-server used for getting the freebsd packages, default is ftp.freebsd.org
#
# You can use more than one device, creating a mirror. To specify more than one device, use multiple -p options. 
# eg. create-zfsboot-gpt_livecd.sh -p ad0 -p ad1 -s 512m -n tank

ftphost='ftp.freebsd.org'

usage="Usage: create-zfsboot-gpt_livecd.sh -p <geom_provider> -s <swapsize> -n <zpoolname> -f <ftphost>"

exerr () { echo -e "$*" >&2 ; exit 1; }

while getopts p:s:n:f: arg
do case ${arg} in
  p) provider="$provider ${OPTARG}";;
  s) swapsize=${OPTARG};;
  n) pool=${OPTARG};;
  f) ftphost=${OPTARG};;
  ?) exerr ${usage};;
esac; done; shift $(( ${OPTIND} - 1 ))

if [ -z "$pool" ] || [ -z "$provider" ] ; then
  exerr ${usage}
  exit
fi

for disk in $provider; do
  dd if=/dev/zero of=/dev/$disk bs=512 count=79
  gpart create -s gpt $disk
done

devcount=`echo ${provider} |wc -w`

smallest_disk_size='0'
for disk in $provider; do
    disk_size=`gpart show $disk | grep '\- free \-' | awk '{print $2}'`
    echo "Checking: $disk has size $disk_size"
    if [ "$smallest_disk_size" -gt "$disk_size" ] || [ "$smallest_disk_size" -eq "0" ]; then
        smallest_disk_size=$disk_size
        ref_disk=$disk
    fi
done

echo "Using $ref_disk (smallest or only disk) as reference disk for calculation offsets"
sleep 3

for disk in $provider; do
  gpart add -b 34 -s 128 -t freebsd-boot $disk
done

sleep 3

if [ "$swapsize" ]; then
  swapsize=`echo "${swapsize}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`
  swapsize=`echo "${swapsize}/512" |bc`
  offset=`gpart show $ref_disk | grep '\- free \-' | awk '{print $1}'`
  for disk in $provider; do
    gpart add -b $offset -s $swapsize -t freebsd-swap -l swap-${disk} ${disk}
  done
fi

sleep 3

offset=`gpart show $ref_disk | grep '\- free \-' | awk '{print $1}'`
size=`gpart show $ref_disk | grep '\- free \-' | awk '{print $2}'`
for disk in $provider; do
  gpart add -b $offset -s $size -t freebsd-zfs -l system-${disk} ${disk}
  labellist="${labellist} gpt/system-${disk}"
done

sleep 3

# Make first partition active so the BIOS boots from it
for disk in $provider; do
  echo 'a 1' | fdisk -f - $disk
done

sleep 3

kldload /mnt2/boot/kernel/opensolaris.ko
kldload /mnt2/boot/kernel/zfs.ko

# we need to create /boot/zfs so zpool.cache can be written.
mkdir /boot/zfs

# Create the pool and the rootfs
if [ "$devcount" -gt 1 ]; then
  zpool create -f $pool mirror ${labellist}
else
  zpool create -f $pool ${labellist}
fi

sleep 3

zfs create -o compression=lzjb -p $pool/ROOT/$pool

# Now we create some stuff we also would like to have in seperate filesystems
for filesystem in var usr-src usr-obj usr-local tmp; do
   echo "Creating $pool/$filesystem"
   zfs create $pool/$filesystem
   if [ "$filesystem" = "tmp" ]; then
     chmod 1777 /$pool/tmp
   fi
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
for disk in $provider; do
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
  for disk in $provider; do
    echo "/dev/gpt/swap-${disk} none swap sw 0 0" >> /$pool/ROOT/$pool/etc/fstab
  done
fi

# Copy the zpool.cache to the new filesystem
cp /boot/zfs/zpool.cache /$pool/ROOT/$pool/boot/zfs/zpool.cache

sleep 5

echo "Please reboot the system from the harddisk(s), remove the FreeBSD CD from you cdrom!"
