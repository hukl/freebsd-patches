#!/bin/sh

zfs='backup/data/home/cryx'
limit='2.0G'
current=`zfs list -H -o used $zfs`
data=`zfs list -H -o usedbydataset $zfs`

_limit=`echo "${limit}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`
_data=`echo "${data}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`

calc_bytesize () {
   _current=`echo "${current}"|tr GMKBWX gmkbwx|sed -Ees:g:km:g -es:m:kk:g -es:k:"*2b":g -es:b:"*128w":g -es:w:"*4 ":g -e"s:(^|[^0-9])0x:\1\0X:g" -ey:x:"*":|bc |sed "s:\.[0-9]*$::g"`
#   _current=`echo "${_current}+${_data}" |bc`
}

calc_bytesize

while [ "$_current" -gt "$_limit" ]; do
	delete=`zfs list -H -o name -t snapshot -r $zfs | grep ${zfs}'@' | head -n1`
	zfs get -H used $delete
	echo "zfs destroy $delete"
#	sudo zfs destroy $delete
	current=`zfs list -H -o used $zfs`
	calc_bytesize
	echo $_current $_limit
done
