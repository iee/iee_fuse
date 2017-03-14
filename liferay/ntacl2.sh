#!/bin/sh

if [ -d "$2" ]; then
tmp=`sudo samba-tool ntacl set "$1" "$2"`
fi
echo $tmp