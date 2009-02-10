#!/bin/sh

my_zfs='home/joe'
my_pool='tank'
my_backuppool='backup'

last_snapshot=`zfs list -H -o name -t snapshot -r $my_pool/$my_zfs|tail -n1`

echo "zfs create $my_backuppool/$my_pool"
echo "zfs send -R $last_snapshot  |zfs recv -d $my_backuppool/$my_pool"
echo "zfs clone $my_backuppool/$last_snapshot $my_backuppool/$my_pool/${my_zfs}_backupmark"
