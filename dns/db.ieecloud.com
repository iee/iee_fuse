@ SOA ieecloud.com. ieecloud-fp.ieecloud.com. 2007012000 (
                                                10h ; slave-server connection preiod
                                                1h  ; retry
                                                1w  ; lifetime
                                                1h ); negative ttl

@	    IN NS localhost.
@           IN  A 192.168.105.149
ieecloud-fp IN 	A 192.168.105.108
editorgrf   IN	A 192.168.105.149
egrfs	    IN	A 192.168.105.149
store	    IN	A 192.168.105.149
store-grf   IN  A 192.168.105.149
