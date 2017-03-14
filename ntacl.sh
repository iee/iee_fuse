#!/bin/sh
a=$1
parentdir="${a%/*}"
#echo $parentdir
acl=`sudo samba-tool ntacl get "$parentdir" --as-sddl`
#echo $acl
tmp=sudo samba-tool ntacl set "$acl" "$a"
echo $tmp
