# manageBE is considered beer ware (http://en.wikipedia.org/wiki/Beerware)
# Written by Philipp Wuensche (cryx-manageBE@h3q.com)

This tool makes some assumptions about your system and filesystem layout
1. you use FreeBSD with ZFS root and zfsboot support
2. your boot-filesystems are located under pool/ROOT/boot-filesystemname, to convert to this setup take a look
   at convert-readme.txt
3. all your FreeBSD userland (base) is located on a single ZFS filesystem, no extra filesystem for e.g. /usr
4. you don't use freebsd-update but update from src (might be fixed)

NOTE: It is recommened to have seperate filesystems for /tmp, /var and any other diretory not populated by the
      FreeBSD userland.

The idea of using ZFS to create Boot-Environments (BE) and always to be able to got back to your old BE in case the 
new does not work is as follows:

- build kernel and world as described in the FreeBSD Handbook
- create a new BE cloning the old BE 'manageBE create -n <newBE> -s <oldBE> -p <pool>
- install your new kernel with DESTDIR=/<pool>/ROOT/<newBE>/ set
- activate your new BE with 'manageBE activate -n <newBE> -p <pool>'
- reboot into your new BE

if booting the new kernel works:
    - install the new FreeBSD userland as described in the FreeBSD Handbook
    - reboot into your new BE with the new userland
else
    - Escape to loader
      LOADER: boot -s /boot/kernel.old/kernel
    - Enable your old BE with 'zpool set bootfs=pool/ROOT/oldrootfs pool' or 'manageBE activate -n <oldBE> -p <pool>'
    - reboot into your old BE
    
if booting the new userland works:
    - DONE!
else
    - Escape to the loader
      LOADER: set vfs.root.mountfrom="zfs:<pool>/ROOT/<oldBE>"
      LOADER: boot -s
    - Enable your old BE with 'zpool set bootfs=pool/ROOT/oldrootfs pool' or 'manageBE activate -n <oldBE> -p <pool>'
    - reboot into your old BE




DISCLAIMER: Always make backups, don't blame me if this renders your system unusable or you lose any data!
