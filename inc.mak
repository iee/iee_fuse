CC=gcc

# for debugging
CFLAGS = -Wall -Werror -g -O0 -pthread
# for releasing
#CFLAGS = -Wall -O2

# redhat has libpq-fe.h and fuse.h in /usr/include, ok

# suse has libpq-fe.h in
CFLAGS += -I/usr/include/pgsql

# debianish systems have libpg-fe.h in
CFLAGS += -I/usr/include/postgresql

CFLAGSG += -O3 -I/usr/include/postgresql/9.5/server

# declare version of FUSE API we want to program against
CFLAGS += -DFUSE_USE_VERSION=29 -D_FILE_OFFSET_BITS=64

# get compilation flags for filesystem
CFLAGS += `getconf LFS_CFLAGS`

# debug
#CFLAGS += -I/usr/local/include/fuse
#LDFLAGS = -lpq /usr/local/lib/libfuse.a -pthread -ldl -lrt

# release
# use pkg-config to detemine compiler/linker flags for libfuse
CFLAGS += `pkg-config fuse --cflags`
LDFLAGSG = -shared -lwbclient -lpq -pthread -luuid
LDFLAGS = `pkg-config fuse --libs` -lcrypto -lpq -lcurl -pthread -lulockmgr -lwbclient -lhiredis -ljson-c
