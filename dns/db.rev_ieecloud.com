$TTL    3600
@  IN      SOA     ieecloud.com.  ieecloud-fp.ieecloud.com (
                   20060204        ; Serial
                   3600            ; Refresh
                   900             ; Retry
                   3600000         ; Expire
                   3600 )          ; Minimum

@   IN      NS      localhost.
108 IN      PTR     ieecloud-fp.
149 IN      PTR     store-grf.
