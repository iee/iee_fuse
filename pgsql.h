/*
 Copyright (C) 2012 Andreas Baumann <abaumann@yahoo.com>

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef PGSQL_H
#define PGSQL_H

#include <syslog.h>		/* for openlog, syslog */
#include <sys/types.h>		/* size_t */
#include <sys/time.h>		/* for struct timespec */
#include <sys/stat.h>		/* mode_t */
#include <stdint.h>		/* for uint64_t */
#include <hiredis/hiredis.h>
#include <openssl/md5.h>

#include <fuse.h>		/* for user-land filesystem */

#include <libpq-fe.h>		/* for Postgresql database access */
#include "thredis.h"

#define MAX_ID_PORTAL 6148914691236517205
#define URL_SIZE 4048
#define BUF_SIZE 204800
#define SCR_NAME 125
#define LOG_LEN  2049

//redisContext *Redisc;

/* --- metadata stored about a file/directory/synlink --- */

#define MD5_BUF (MD5_DIGEST_LENGTH*2+1)

typedef struct PgMeta
{
	int64_t size; /* the size of the file (naturally the bigint on PostgreSQL) */
	mode_t mode; /* type and permissions of file/directory */
	uid_t uid; /* owner of the file/directory */
	gid_t gid; /* group owner of the file/directory */
	struct timespec ctime; /* last status change time */
	struct timespec mtime; /* last modification time */
	struct timespec atime; /* last access time */
	int64_t parent_id; /* id/inode_no of parenting directory */
} PgMeta;

typedef struct IdMode
{
	int64_t id;
	mode_t mode;
} IdMode;

typedef struct curl_fetch_st {
	char *memory;
	size_t size;
} curl_fetch_st;

//static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
//static pthread_mutex_t mutex_curl = PTHREAD_MUTEX_INITIALIZER;

/* --- transaction management and policies --- */

#define PSQL_BEGIN( T ) \
	{ \
		int __res; \
		__res = psql_begin( T ); \
		if( __res < 0 ) return __res; \
	}

#define PSQL_COMMIT( T ) \
	{ \
		int __res; \
		__res = psql_commit( T ); \
		if( __res < 0 ) return __res; \
	}

#define PSQL_ROLLBACK( T ) \
	{ \
		int __res; \
		__res = psql_rollback( T ); \
		if( __res < 0 ) return __res; \
	}

int psql_begin ( PGconn *conn );

int psql_commit ( PGconn *conn );

int psql_rollback ( PGconn *conn );

void pgfuse_syslog (int facility_priority, const char *format );

/* --- the filesystem functions --- */
int get_real_path_to_path ( PGconn *conn, const char* path_portal, const char* path_temp, thredis_t* thredis, const int64_t id, char *real_path );

int wbinfo_get_screenname ( uid_t uid, char *screenname );

void md5_hash ( const char *path, char *dst );

void set_del_dlfileentry ( PGconn *conn, thredis_t* thredis, const int64_t from_id, const int del );

int copy ( PGconn *conn, thredis_t* thredis, const int64_t from_id, const int64_t to_id, const char *from_path, const char *to_path );

int copy_mmap ( PGconn *conn, const char* path_portal, const char* path_temp, thredis_t* thredis, const int64_t from_id, const int64_t to_id );

int64_t curl_http_get ( const char *str, cfg_t* cfg );

int64_t exist_name_dlfileentry ( PGconn *conn, const int64_t parent_id, const char *name );

int64_t get_userid_from_uid ( PGconn* conn, thredis_t* thredis, uid_t uid );

int64_t psql_path_to_id ( PGconn *conn, thredis_t* thredis, const char *path );

int64_t psql_read_meta ( PGconn *conn, thredis_t* thredis, const int64_t id, const char *path, PgMeta *meta );

int64_t psql_read_meta_from_path ( PGconn *conn, thredis_t* thredis, const char *path, PgMeta *meta );

int psql_write_meta ( PGconn *conn, thredis_t* thredis, const int64_t id, const char *path, PgMeta* meta );

int psql_write_meta_to_path ( PGconn *conn, thredis_t* thredis, const char *path, PgMeta* meta );

int64_t psql_create_file ( PGconn *conn, thredis_t* thredis, cfg_t* cfg, const int64_t parent_id, const char *path, const char *new_file, PgMeta* meta );

int psql_create_symlink ( PGconn *conn, const int64_t parent_id, const char *path, const char *new_file, PgMeta meta );

int psql_read_buf ( PGconn *conn, thredis_t* thredis, const size_t block_size, const int64_t id, const char *path, char *buf, const off_t offset, const size_t len, int verbose );

int psql_readdir ( PGconn *conn, thredis_t* thredis, const int64_t parent_id, void *buf, fuse_fill_dir_t filler );

int psql_create_dir ( PGconn *conn, thredis_t* thredis, cfg_t* cfg, const int64_t parent_id, const char *path, const char *new_dir, PgMeta* meta );

int psql_delete_dir ( PGconn *conn, thredis_t* thredis, cfg_t* cfg, const int64_t id, const char *path );

int psql_delete_file ( PGconn *conn, const char* path_portal, const char* path_temp, thredis_t* thredis, cfg_t* cfg, const int64_t id, const char *path );

int psql_delete_xattr ( PGconn *conn, thredis_t* thredis, const char *path, const char *name );

int psql_list_xattr ( PGconn *conn, thredis_t* thredis, const char *path, char *list, size_t size );

int psql_set_xattr_create ( PGconn *conn, thredis_t* thredis, const char *path, const char *name, const char *value, size_t size );

int psql_set_xattr_replace ( PGconn *conn, thredis_t* thredis, const char *path, const char *name, const char *value, size_t size );

int psql_get_xattr ( PGconn *conn, thredis_t* thredis, const char *path, const char *name, char *value, size_t size );

int psql_write_buf ( PGconn *conn, const size_t block_size, const int64_t id, const char *path, const char *buf, const off_t offset, const size_t len, int verbose );

int psql_truncate ( PGconn *conn, const size_t block_size, const int64_t id, const char *path, const off_t offset );

int psql_rename ( PGconn *conn, const char* path_portal, const char* path_temp, cfg_t* cfg, thredis_t* thredis, const int64_t from_id, const int64_t from_parent_id, const int64_t to_parent_id, const char *rename_to, const char *from, const char *to );

int psql_rename_to_existing_file ( PGconn *conn, const char* path_portal, const char* path_temp, thredis_t* thredis, cfg_t* cfg, const int64_t from_id, const int64_t to_id, const char *from_path, const char *to_path );

size_t psql_get_block_size ( PGconn *conn, const size_t block_size );

int64_t psql_get_fs_blocks_used ( PGconn *conn );

int psql_get_tablespace_locations ( PGconn *conn, char **location, size_t *nof_oids, int verbose );

int64_t psql_get_fs_files_used ( PGconn *conn );

#endif
