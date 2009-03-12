#!/bin/sh
# Copyright Philipp Wuensche

usage='Usage: zfs-tm -f <configfile>'

while getopts :f: arg; do
 case ${arg} in
  f) zfs_tm_conf=$OPTARG;;
  *) echo $usage && exit
 esac
done

[ -f "${zfs_tm_conf}" ] && . "${zfs_tm_conf}"
[ "${zfs_tm_conf}" = "" ] && echo $usage && exit
[ "${my_zfs}" = "" ] && echo $usage && exit
[ "${my_backuppool}" = "" ] && echo $usage && exit

if [ ! "root" = `id -nu` ]; then
   echo "ERROR: Script has to run as root"
   exit
fi

my_localpool=${my_zfs%%/*}

last_snapshot=`zfs list -H -o name -t snapshot -r $my_zfs|tail -n1`
random_id=`dd if=/dev/random bs=512 count=79 |/sbin/sha256 2> /dev/null`

echo "zfs create -p $my_backuppool/$my_localpool"
echo "zfs send -R $last_snapshot  |zfs recv -dF $my_backuppool/$my_localpool"
echo "zfs create -p -o canmount=off $my_backuppool/.backupmark/${my_zfs}"
echo "zfs clone $my_backuppool/$last_snapshot $my_backuppool/.backupmark/${my_zfs}/latest"
echo "zfs set readonly=on $my_backuppool/$my_zfs"
echo "zfs set com.h3q:zfs-tm=$random_id $my_backuppool/$my_zfs"
echo "zfs set com.h3q:zfs-tm=$random_id $my_zfs"
echo "### Using ZFS delegation for zfs-tm ###"
echo "WARNING: This needs vfs.usermount=1"
echo "zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_zfs"
echo "zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_backuppool/$my_zfs"
echo "zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_backuppool/.backupmark/$my_zfs"
