#!/bin/sh

zfs='tank/home/joe'
limit='699M'
current=`zfs list -H -o usedbysnapshots $zfs`

_limit=`echo "${limit}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc`

calc_bytesize () {
   _current=`echo "${current}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc`
}

calc_bytesize

while [ "$_current" -gt "$_limit" ]; do
	delete=`zfs list -H -o name -t snapshot -r $zfs | grep ${zfs}'@' | head -n1`
	echo "zfs destroy $delete"
	sudo zfs destroy $delete
	sleep 1
	current=`zfs list -H -o usedbysnapshots $zfs`
	calc_bytesize
	echo $_current $_limit
done
