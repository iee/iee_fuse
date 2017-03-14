#!/bin/sh
service smbd stop
umount /data/mnt
service smbd start
service nmbd restart
service winbind restart
./pgfuse "host=localhost user=postgres dbname=lportal-project password=Qwertyu*" /data/mnt /data/portal-project /data/temp-project -v -o  allow_other,blocksize=204800,big_writes,direct_io,auto_cache,max_readahead=204800

