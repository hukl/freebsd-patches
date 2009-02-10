How to convert your existing ZFS rootfs setup for using it with manageBE

With manageBE the root-filesystems are located at pool/ROOT, it is recommended to have seperate filesystems for /tmp and /var

1. Create a snapshot of your current bootfs, 
   e.g. zfs snapshot tank@manageBE

2. Create tank/ROOT
   e.g. zfs create tank/ROOT

3. Send and receive the snapshot to the new rootfs
   e.g. zfs send tank@manageBE |zfs receive tank/ROOT/mynew_rootfs
   The new rootfs should be mounted at /tank/ROOT/mynew_rootfs now

4. Edit /tank/ROOT/mynew_rootfs/boot/loader.conf and add 'vfs.root.mountfrom="zfs:tank/ROOT/mynew_rootfs"

5. Activate the new rootfs
   e.g. zpool set bootfs=tank/ROOT/mynew_rootfs tank

6. Reboot into the new rootfs

7. Delete everything in /tank except the ROOT directory, you can now also delete the tank@manageBE snapshot

DISCLAIMER: Always make backups, don't blame me if this renders your system unusable or you lose any data!
