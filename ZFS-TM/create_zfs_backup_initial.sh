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
my_remotezfs="${my_backuppool}/$my_backupzfs"

my_backup_zfs="tank/backup/aspire/data/home/cryx"
my_backup_mark_zfs="tank/backup/aspire/data/home/cryx"

last_snapshot=`zfs list -H -o name -s creation -t snapshot -r $my_zfs|tail -n1|cut -d '@' -f2`
random_id=`/sbin/zfs list -H -o com.h3q:zfs-tm:id $my_zfs 2> /dev/null`
if [ ! "$random_id" ]; then
  random_id=`dd if=/dev/random bs=512 count=79 |/sbin/sha256 2> /dev/null`
  echo "zfs set com.h3q:zfs-tm:id=$random_id $my_zfs"
fi

echo "$remote_command zfs create -p $my_backuppool/$my_backupzfs/$my_localpool"
echo "zfs send -R ${my_zfs}@${last_snapshot}  |$remote_command zfs recv -dF $my_backuppool/$my_backupzfs/$my_localpool"
echo "$remote_command zfs create -p -o canmount=off $my_backuppool/$my_backupzfs/.backupmark/${my_zfs}"
echo "$remote_command zfs clone $my_backuppool/$my_backupzfs/${my_zfs}@${last_snapshot} $my_backuppool/$my_backupzfs/.backupmark/${my_zfs}/latest"
echo "$remote_command zfs set readonly=on $my_backuppool/$my_backupzfs/$my_zfs"
echo "$remote_command zfs set com.h3q:zfs-tm:id=$random_id $my_backuppool/$my_backupzfs/$my_zfs"
echo "### Using ZFS delegation for zfs-tm ###"
echo "WARNING: This needs vfs.usermount=1"
echo "$remote_command zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_zfs"
echo "$remote_command zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_backuppool/$my_backupzfs/$my_zfs"
echo "$remote_command zfs allow -u $my_zfstm_user send,receive,snapshot,create,rename,destroy,clone,rollback,mount $my_backuppool/$my_backupzfs/.backupmark/$my_zfs"
