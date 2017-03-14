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

#include <string.h> /* for strdup, strlen, memset */
#include <libgen.h> /* for POSIX compliant basename */
#include <unistd.h> /* for exit */
#include <stdlib.h> /* for EXIT_FAILURE, EXIT_SUCCESS, realpath */
#include <stdio.h> /* for fprintf */
#include <stddef.h> /* for offsetof */
#include <errno.h> /* for ENOENT and friends */
#include <sys/types.h> /* size_t */
#include <sys/stat.h> /* mode_t */
#include <values.h> /* for INT_MAX */
#include <stdint.h> /* for uint64_t */
#include <inttypes.h> /* for PRIxxx macros */
#include <mntent.h> /* for iterating mount entries */
#include <sys/vfs.h> /* for statfs */
#include <limits.h>
#include <linux/xattr.h>
#include <fuse.h> /* for user-land filesystem */
#include <fuse/fuse_opt.h> /* fuse command line parser */
#include <ulockmgr.h>
#include <sys/file.h>
#include <pthread.h> /* for pthread_self */
#include <fcntl.h>
#include <sys/mman.h>
#include <curl/curl.h>

#if FUSE_VERSION < 21
#error Currently only written for newer FUSE API (FUSE_VERSION at least 21)
#endif

#include "config.h" /* compiled in defaults */
#include "pgsql.h" /* implements Postgresql accessers */
#include "pool.h" /* implements the connection pool */

#define ACQUIRE( C ) \
	C = psql_acquire( data ); \
	if( C == NULL ) return -EIO;

#define RELEASE( C ) \
	if( psql_release( data, C ) < 0 ) return -EIO;

#define THREAD_ID (unsigned int)pthread_self( )

/* --- FUSE private context data --- */

typedef struct PgFuseData
{
	int verbose; /* whether we should be verbose */
	char* path_portal;
	char* path_temp;
	char* conninfo; /* connection info as used in PQconnectdb */
	char* mountpoint; /* where we mount the virtual filesystem */
	PGconn* conn; /* the database handle to operate on (single-thread only) */
	redisContext* Redisc;
	thredis_t* thredis;
	PgConnPool pool; /* the database pool to operate on (multi-thread only) */
	int read_only; /* whether the mount point is read-only */
	int noatime; /* be more efficient by not recording all access times */
	int multi_threaded; /* whether we run multi-threaded */
	size_t block_size; /* block size to use for storage of data in bytea fields */
} PgFuseData;
clock_t t1;
/*
time_t rawtime;
 clock_t t1, t2;

    t1 = clock();   

    int i;

    for(i = 0; i < 1000000; i++)   
    {   
        int x = 90;  
    }   

    t2 = clock();   

    float diff = ((float)(t2 - t1) / 1000000.0F ) * 1000;   
  
  printf("%f",diff);   
*/

void pgfuse_syslog (int facility_priority, const char *format )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	if ( data->verbose )
	{
	clock_t t2 = clock();
	
	float diff = ((float)(t2 - t1) / 1000000.0F ) * 1000;
	if (diff > 100)
		syslog( facility_priority, "%f <!!!!> %s", diff, format );
	else 
		syslog( facility_priority, "%f <===> %s", diff, format );
	
	t1 = clock();
	}
}

int copy_mmap ( PGconn* conn, const char* path_portal, const char* path_temp, thredis_t* thredis, const int64_t from_id, const int64_t to_id )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Копирование ДАННЫХ из ID=%"PRIi64" в ID=%"PRIi64"", from_id, to_id );
	pgfuse_syslog ( LOG_INFO, format_str );
	int res = 0;
	char path_r_to[1024] = { '0' };
	char path_r_from[1024] = { '0' };
	get_real_path_to_path ( conn, path_portal, path_temp, thredis, from_id, path_r_from );
	get_real_path_to_path ( conn, path_portal, path_temp, thredis, to_id, path_r_to );
	int fdin, fdout;
	void *src, *dst;
	struct stat statbuf;
	if ( ( res = ( fdin = open ( path_r_from, O_RDONLY ) ) ) < 0 )
	{
		return res;
	}

	if ( ( res = ( fdout = open ( path_r_to, O_RDWR | O_CREAT | O_TRUNC ) ) ) < 0 )
	{
		return res;
	}

	if ( ( res = fstat ( fdin, &statbuf ) ) < 0 )
	{
		return res;
	}

	if ( ( res = lseek ( fdout, statbuf.st_size - 1, SEEK_SET ) ) == -1 )
	{
		return res;
	}

	if ( ( res = write ( fdout, "", 1 ) ) != 1 )
	{
		return res;
	}

	if ( ( src = mmap ( 0, statbuf.st_size, PROT_READ, MAP_SHARED, fdin, 0 ) ) == MAP_FAILED )
	{
		return -1;
	}

	if ( ( dst = mmap ( 0, statbuf.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fdout, 0 ) ) == MAP_FAILED )
	{
		return -1;
	}
	memcpy ( dst, src, statbuf.st_size );
	close ( fdin );
	close ( fdout );
	return 0;
}
/*
int copy ( PGconn* conn, thredis_t* thredis, const int64_t from_id, const int64_t to_id, const char* from_path, const char* to_path )
{
	char format_str[LOG_LEN] = { '\0' };
	pgfuse_syslog ( LOG_INFO, "Копирование из %s в %s", from_path, to_path );

	int res = 0;
	int ret_in = 0;
	int fd_to;
	int fd_from;
	off_t offset = 0;
	char path_r_to[1024] = { '\0' };
	char path_r_from[1024] = { '\0' };
	char buf[BUF_SIZE] = { '\0' };

	get_real_path_to_path ( conn, thredis, from_id, path_r_from );
	fd_from = open ( path_r_from, O_RDONLY );
	get_real_path_to_path ( conn, thredis, to_id, path_r_to );
	fd_to = open ( path_r_to, O_WRONLY );

	if ( fd_to == -1 || fd_from == -1 )
	{
		return -errno;
	}

	while ( ( ret_in = pread ( fd_from, buf, BUF_SIZE, offset ) ) > 0 )
	{
		res = pwrite ( fd_to, buf, ret_in, offset );
		if ( res == -1 )
		{
			close ( fd_to );
			close ( fd_from );
			return -errno;
		}
	}

	close ( fd_from );
	close ( fd_to );

	return res;
}
*/

/* --- timestamp helpers --- */
static struct timespec now ( void )
{
	int res;
	struct timeval t;
	struct timezone tz;
	struct timespec s;

	res = gettimeofday ( &t, &tz );
	if ( res != 0 )
	{
		s.tv_sec = 0;
		s.tv_nsec = 0;
		return s;
	}

	s.tv_sec = t.tv_sec;
	s.tv_nsec = t.tv_usec * 1000;

	return s;
}

/* --- pool helpers --- */

static PGconn* psql_acquire ( PgFuseData* data )
{
	if ( !data->multi_threaded )
	{
		return data->conn;
	}

	return psql_pool_acquire ( &data->pool );
}

static int psql_release ( PgFuseData* data, PGconn* conn )
{
	if ( !data->multi_threaded )
	{
		return 0;
	}

	return psql_pool_release ( &data->pool, conn );
}

/* --- other helpers --- */

static int check_mountpoint ( char** old_mountpoint )
{
	int res = 0;
	struct stat stat_buf;
	char* abs_mountpoint;

	/* use absolute mountpoints, not relative ones */
	if ( ( abs_mountpoint = realpath ( *old_mountpoint, NULL ) ) == NULL )
	{
		fprintf ( stderr, "unable to call realpath on mountpoint '%s': %s\n", *old_mountpoint, strerror ( errno ) );
		return -1;
	}

	if ( ( res = stat ( abs_mountpoint, &stat_buf ) ) < 0 )
	{
		fprintf ( stderr, "unable to stat mountpoint '%s': %s\n", abs_mountpoint, strerror ( errno ) );
		return res;
	}

	/* don't allow anything but a directory as a mount point */
	if ( ! ( S_ISDIR( stat_buf.st_mode ) ) )
	{
		fprintf ( stderr, "mountpoint '%s' is not a directory\n", abs_mountpoint );
		return -1;
	}

	*old_mountpoint = abs_mountpoint;

	return res;
}

/* --- implementation of FUSE hooks --- */

static void* pgfuse_init ( struct fuse_conn_info* conn )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;

	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Mounting file system on '%s' ('%s', %s, %s), thread #%u", data->mountpoint, data->conninfo, data->read_only ? "read-only" : "read-write", data->noatime ? "noatime" : "atime", THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	curl_global_init(CURL_GLOBAL_ALL);
	data->Redisc = redisConnectUnix ( "/var/run/redis/redis.sock" );
	data->thredis = thredis_new ( data->Redisc );
	if ( !data->thredis )
	{
		sprintf ( format_str, "ERROR REDIS не подключен!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		exit ( EXIT_FAILURE );
	}
	/* in single-threaded case we just need one shared PostgreSQL connection */
	if ( !data->multi_threaded )
	{
		data->conn = PQconnectdb ( data->conninfo );
		if ( PQstatus ( data->conn ) != CONNECTION_OK )
		{
			sprintf ( format_str, "Connection to database failed: %s", PQerrorMessage ( data->conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQfinish ( data->conn );
			exit ( EXIT_FAILURE );
		}
	}
	else
	{
		int res;

		res = psql_pool_init ( &data->pool, data->conninfo, MAX_DB_CONNECTIONS );
		if ( res < 0 )
		{
			sprintf ( format_str, "Allocating database connection pool failed!" );
			pgfuse_syslog ( LOG_ERR, format_str );
			exit ( EXIT_FAILURE );
		}
	}

	return data;
}

static void pgfuse_destroy ( void* userdata )
{
	PgFuseData* data = ( PgFuseData * ) userdata;

	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Unmounting file system on '%s' (%s), thread #%u", data->mountpoint, data->conninfo, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	if ( !data->multi_threaded )
	{
		PQfinish ( data->conn );
	}
	else
	{
		( void ) psql_pool_destroy ( &data->pool );
	}

	redisReply* reply;
	reply = thredis_command ( data->thredis, "FLUSHALL" );
	sprintf ( format_str, "FLUSHALL: %lld ", reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );
	thredis_close ( data->thredis );
	redisFree ( data->Redisc );
	curl_global_cleanup();
}

static void convert_meta_to_stbuf ( struct stat* stbuf, PgMeta* meta, PgFuseData* data, int64_t id )
{
	/* TODO: check bits of inodes of the kernel */
	stbuf->st_ino = id;
	stbuf->st_blocks = 0;
	stbuf->st_mode = meta->mode;
	stbuf->st_size = meta->size;
	stbuf->st_blksize = data->block_size;
	stbuf->st_blocks = ( meta->size + data->block_size - 1 ) / data->block_size;
	/* TODO: set correctly from table */
	stbuf->st_nlink = 1;
	stbuf->st_uid = meta->uid;
	stbuf->st_gid = meta->gid;
	stbuf->st_atime = meta->atime.tv_sec;
	stbuf->st_mtime = meta->mtime.tv_sec;
	stbuf->st_ctime = meta->ctime.tv_sec;
}

static int pgfuse_fgetattr ( const char* path, struct stat* stbuf, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "FgetAttrs '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	memset ( stbuf, 0, sizeof(struct stat) );

	id = psql_read_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	sprintf ( format_str, "Id for %s '%s' is %"PRIi64", thread #%u", S_ISDIR(meta.mode) ? "dir" : "file", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	convert_meta_to_stbuf ( stbuf, &meta, data, id );

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_getattr ( const char* path, struct stat* stbuf )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "GetAttrs '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	memset ( stbuf, 0, sizeof(struct stat) );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
	sprintf ( format_str, "GetAttrs ERROR '%s' on id=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_INFO, format_str );
		
		return id;
	}

	sprintf ( format_str, "Id for %s '%s' is %"PRIi64", thread #%u", S_ISDIR(meta.mode) ? "dir" : "file", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	convert_meta_to_stbuf ( stbuf, &meta, data, id );

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_access ( const char* path, int mode )
{
	//PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Access on '%s' and mode '%o, thread #%u", path, ( unsigned int ) mode, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	// TODO: check access, but not now. grant always access 
	return 0;
}

static char* flags_to_string ( int flags )
{
	char* s;
	char* mode_s = "";

	if ( ( flags & O_ACCMODE ) == O_WRONLY ) mode_s = "O_WRONLY";
	else if ( ( flags & O_ACCMODE ) == O_RDWR ) mode_s = "O_RDWR";
	else if ( ( flags & O_ACCMODE ) == O_RDONLY ) mode_s = "O_RDONLY";

	s = ( char * ) malloc ( 100 );
	if ( s == NULL ) return "<memory allocation failed>";

	snprintf ( s, 100, "access_mode=%s, flags=%s%s%s%s%s%s%s", mode_s, ( flags & O_CREAT ) ? "O_CREAT " : "", ( flags & O_TRUNC ) ? "O_TRUNC " : "", ( flags & O_EXCL ) ? "O_EXCL " : "", ( flags & O_NOFOLLOW ) ? "O_NOFOLLOW " : "", ( flags & O_CLOEXEC ) ? "O_CLOEXEC " : "",
			( flags & O_DIRECTORY ) ? "O_DIRECTORY " : "", ( flags & O_APPEND ) ? "O_APPEND " : "" );

	return s;
}

static int pgfuse_create ( const char* path, mode_t mode, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	char* copy_path;
	char* parent_path;
	char* new_file;
	int64_t parent_id;
	int64_t res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Создание %s ", path );
	pgfuse_syslog ( LOG_INFO, format_str );

	char* s = flags_to_string ( fi->flags );
	sprintf ( format_str, "Create '%s' in mode '%o' on '%s' with flags '%s', thread #%u", path, mode, data->mountpoint, s, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );
	if ( *s != '<' ) free ( s );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 && id != -ENOENT )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( id >= 0 )
	{
		sprintf ( format_str, "Id for dir '%s' is %"PRIi64", thread #%u", path, id, THREAD_ID );
		pgfuse_syslog ( LOG_DEBUG, format_str );

		if ( S_ISDIR( meta.mode ) )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return -EISDIR;
		}

		if ( ( fi->flags & O_CREAT ) && ( fi->flags & O_EXCL ) )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return -EEXIST;
		}

		int fd;
		char path_r[1024] = { '\0' };
		get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, id, path_r );
		fd = open ( path_r, O_RDWR );
		if ( fd == -1 )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return -errno;
		}
		res = ftruncate ( fd, 0 );
		if ( res == -1 )
		{
			close ( fd );
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return -errno;
		}
		close ( fd );

		meta.size = 0;

		res = psql_write_meta ( conn, data->thredis, id, path, &meta );
		if ( res < 0 )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return res;
		}
	}

	copy_path = strdup ( path );
	if ( copy_path == NULL )
	{
		sprintf ( format_str, "Out of memory in Create '%s'!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	parent_path = dirname ( copy_path );

	parent_id = psql_read_meta_from_path ( conn, data->thredis, parent_path, &meta );

	if ( parent_id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return parent_id;
	}

	if ( !S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOENT;
	}

	sprintf ( format_str, "Parent_id for new file '%s' in dir '%s' is %"PRIi64", thread #%u", path, parent_path, parent_id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	free ( copy_path );
	copy_path = strdup ( path );
	if ( copy_path == NULL )
	{
		sprintf ( format_str, "Out of memory in Create '%s'!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	new_file = basename ( copy_path );

	meta.size = 0;
	meta.mode = mode;
	meta.uid = fuse_get_context ()->uid;
	meta.gid = fuse_get_context ()->gid;
	meta.ctime = now ();
	meta.mtime = meta.ctime;
	meta.atime = meta.ctime;
	meta.parent_id = parent_id;

	id = psql_create_file ( conn, data->thredis, parent_id, path, new_file, &meta );
	if ( id < 0 )
	{
		free ( copy_path );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	free ( copy_path );

	if ( id == 0 )
	{
	id = psql_path_to_id ( conn, data->thredis, path );
	if ( id < 0 )
	{
		sprintf ( format_str, "ERROR при создании не %s ID=%"PRIi64"", path, id );
		pgfuse_syslog ( LOG_INFO, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}
	}

	sprintf ( format_str, "Id for new file '%s' is %"PRIi64", thread #%u", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	sprintf ( format_str, "Файл создан %s ID=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_INFO, format_str );

	fi->fh = id;

	if ( id > MAX_ID_PORTAL )
	{
		char path_r[1024] = { '\0' };
		get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, id, path_r );
		int fd;
		fd = open ( path_r, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH );
		if ( fd == -1 )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			sprintf ( format_str, "ERROR CREATE '%s' errno=%d is %"PRIi64", thread #%u", path, errno, id, THREAD_ID );
			pgfuse_syslog ( LOG_DEBUG, format_str );
			return -errno;
		}
		close ( fd );
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_open ( const char* path, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	PgMeta meta;
	int64_t id;
	int64_t res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	if ( data->verbose )
	{
		char* s = flags_to_string ( fi->flags );
		sprintf ( format_str, "Open '%s' on '%s' with flags '%s', thread #%u", path, data->mountpoint, s, THREAD_ID );
		pgfuse_syslog ( LOG_INFO, format_str );
		if ( *s != '<' ) free ( s );
	}

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	sprintf ( format_str, "Открытие %s id=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_INFO, format_str );

	sprintf ( format_str, "Id for file '%s' to open is %"PRIi64", thread #%u", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	if ( S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EISDIR;
	}

	if ( data->read_only )
	{
		if ( ( fi->flags & O_ACCMODE ) != O_RDONLY )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return -EROFS;
		}
	}

	if ( !data->noatime )
	{
		meta.atime = now ();
	}

	res = psql_write_meta ( conn, data->thredis, id, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	fi->fh = id;

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_opendir ( const char* path, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Opendir '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	sprintf ( format_str, "pgfuse_opendir %s", path );
	pgfuse_syslog ( LOG_INFO, format_str );

	int64_t id = psql_path_to_id ( conn, data->thredis, path );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOENT;
	}

	fi->fh = id;

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_readdir ( const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* fi )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "pgfuse_readdir %s", path );
	pgfuse_syslog ( LOG_INFO, format_str );
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id = fi->fh;
	int res;
	PGconn* conn;

	sprintf ( format_str, "Readdir '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	filler ( buf, ".", NULL, 0 );
	filler ( buf, "..", NULL, 0 );

	res = psql_readdir ( conn, data->thredis, id, buf, filler );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}
/*
static int pgfuse_releasedir(const char* path, struct fuse_file_info* fi)
{
	char format_str[LOG_LEN] = { '\0' };
	pgfuse_syslog(LOG_INFO, "pgfuse_releasedir %s", path);
	//nothing to do, everything is done in pgfuse_readdir currently
	return 0;
}

static int pgfuse_fsyncdir(const char* path, int datasync, struct fuse_file_info* fi)
{
	//nothing to do, everything is done in pgfuse_readdir currently
	return 0;
}
 */

static int pgfuse_mkdir ( const char* path, mode_t mode )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	char* copy_path;
	char* parent_path;
	char* new_dir;
	int64_t parent_id;
	int res;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Mkdir '%s' in mode '%o' on '%s', thread #%u", path, ( unsigned int ) mode, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	copy_path = strdup ( path );
	if ( copy_path == NULL )
	{
		sprintf ( format_str, "Out of memory in Mkdir '%s'!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	parent_path = dirname ( copy_path );

	parent_id = psql_read_meta_from_path ( conn, data->thredis, parent_path, &meta );
	if ( parent_id < 0 )
	{
		free ( copy_path );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return parent_id;
	}

	if ( !S_ISDIR( meta.mode ) )
	{
		free ( copy_path );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOENT;
	}

	sprintf ( format_str, "Parent_id for new dir '%s' is %"PRIi64", thread #%u", path, parent_id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );


	free ( copy_path );
	copy_path = strdup ( path );
	if ( copy_path == NULL )
	{
		sprintf ( format_str, "Out of memory in Mkdir '%s'!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	new_dir = basename ( copy_path );

	meta.size = 0;
	meta.mode = mode | S_IFDIR; /* S_IFDIR is not set by fuse */
	meta.uid = fuse_get_context ()->uid;
	meta.gid = fuse_get_context ()->gid;
	meta.ctime = now ();
	meta.mtime = meta.ctime;
	meta.atime = meta.ctime;
	meta.parent_id = parent_id;

	res = psql_create_dir ( conn, data->thredis, parent_id, path, new_dir, &meta );
	if ( res < 0 )
	{
		free ( copy_path );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	free ( copy_path );

	PSQL_COMMIT( conn );
	RELEASE( conn );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", parent_id );
	reply = thredis_command ( data->thredis, "DEL %s:dir", group );
	sprintf ( format_str, "DEL %s:dir : %lld ", group, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

static int pgfuse_rmdir ( const char* path )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	int res;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Rmdir '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( !S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOTDIR;
	}

	sprintf ( format_str, "Id of dir '%s' to be removed is %"PRIi64", thread #%u", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	res = psql_delete_dir ( conn, data->thredis, id, path );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	redisReply* reply;
	char Hash[MD5_BUF] = { '\0' };
	md5_hash ( path, Hash );
	char group_id[MD5_BUF] = { '\0' };
	sprintf ( group_id, "%s", Hash );
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64":dir", meta.parent_id );
	reply = thredis_command ( data->thredis, "DEL %s:path %s", group_id, group );
	sprintf ( format_str, "DEL %s %s:path: %lld ", group, group_id, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

static int pgfuse_unlink ( const char* path )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	int res;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Remove file '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EPERM;
	}

	sprintf ( format_str, "Id of file '%s' to be removed is %"PRIi64", thread #%u", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	res = psql_delete_file ( conn, data->path_portal, data->path_temp, data->thredis, id, path );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	redisReply* reply;
	char Hash[MD5_BUF] = { '\0' };
	md5_hash ( path, Hash );
	char group_id[MD5_BUF] = { '\0' };
	sprintf ( group_id, "%s:path", Hash );
	char group_dir[MD5_BUF] = { '\0' };
	sprintf ( group_dir, "%"PRIi64":dir", meta.parent_id );
	sprintf ( format_str, "PARENT=%"PRIi64" s=%s", meta.parent_id, group_dir );
	pgfuse_syslog ( LOG_ERR, format_str );
	reply = thredis_command ( data->thredis, "DEL %s %s", group_id, group_dir );
	sprintf ( format_str, "DEL %s %s: %lld ", group_id, group_dir, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}
/*
 static int pgfuse_flush(const char* path, struct fuse_file_info* fi)
 {
 PgFuseData* data = (PgFuseData *)fuse_get_context()->private_data;
	char format_str[LOG_LEN] = { '\0' };

 if (data->verbose)
 {
 pgfuse_syslog(LOG_INFO, "Flush to '%s' , on '%s', thread #%u", path, data->mountpoint, THREAD_ID);
 }

 pgfuse_syslog(LOG_ERR, "Сброс %s ID=%zu", path, fi->fh);

 return 0;
 }

 static int pgfuse_fsync(const char* path, int isdatasync, struct fuse_file_info* fi)
 {
	char format_str[LOG_LEN] = { '\0' };
 pgfuse_syslog(LOG_INFO, "Синхронизация буфер %s isdatasync=%d", path, isdatasync);

 PgFuseData* data = (PgFuseData *)fuse_get_context()->private_data;

 if (data->verbose)
 {
 pgfuse_syslog(LOG_INFO, "%s on file '%s' on '%s', thread #%u", isdatasync ? "FDataSync" : "FSync", path, data->mountpoint, THREAD_ID);
 }

 if (data->read_only)
 {
 return -EROFS;
 }

 if (fi->fh == 0)
 {
 return -EBADF;
 }

 nothing to do, data is always persistent in database

 TODO: if we have a per transaction/file transaction policy, we must change this here!

 return 0;
 }
 */
static int pgfuse_release ( const char* path, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;

	int res_meta;
	PgMeta meta;
	PGconn* conn;
	uid_t uid = 0;
	int event = 0;
	char format_str[LOG_LEN] = { '\0' };

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	sprintf ( format_str, "Закрытие %s, thread #%u ID=%"PRIi64"", path, THREAD_ID, fi->fh );
	pgfuse_syslog ( LOG_INFO, format_str );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", fi->fh );
	reply = thredis_command ( data->thredis, "HGET %s %s", group, "uid" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		uid_t* val = ( uid_t * ) calloc ( 1, sizeof(uid_t) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			uid = *val;
			free ( val );
		}
		sprintf ( format_str, "HGET %s uid=%d : %lld %d", group, uid, reply->integer, reply->len );
		pgfuse_syslog ( LOG_ERR, format_str );
	}
	freeReplyObject ( reply );

	reply = thredis_command ( data->thredis, "HGET %s %s", group, "event" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf ( format_str, "EVENT-HGET: %lld %d", reply->integer, reply->len );
		pgfuse_syslog ( LOG_ERR, format_str );
		int* val = ( int * ) calloc ( 1, sizeof(int) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			event = *val;
			free ( val );
		}
	}
	freeReplyObject ( reply );

	sprintf ( format_str, "EVENT %d path=%s", event, path );
	pgfuse_syslog ( LOG_INFO, format_str );

	int64_t tmp = psql_read_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( tmp < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
	sprintf ( format_str, "pgfuse_release ERROR tmp=%"PRIi64" path=%s", tmp, path );
	pgfuse_syslog ( LOG_INFO, format_str );
		return tmp;
	}

	sprintf ( format_str, "Releasing '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	if ( event == 1 && fi->fh < MAX_ID_PORTAL )
	{
		uint64_t userid = get_userid_from_uid ( conn, data->thredis, uid );
		char str[URL_SIZE] = { '\0' };
		sprintf ( str, "/update-file-last-updated/file-entry-id/%"PRIi64"/user-id/%"PRIi64"/size/%zu/", fi->fh, userid, meta.size );
		curl_http_get ( str );
	}

	reply = thredis_command ( data->thredis, "DEL %s %s", group, "event" );
	freeReplyObject ( reply );

	res_meta = psql_write_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( res_meta < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res_meta;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );
	
	return 0;
}

static int pgfuse_write ( const char* path, const char* buf, size_t size, off_t offset, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t tmp;
	int res;
	int res_meta;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Write to '%s' from offset %jd, size %zu on '%s', thread #%u", path, offset, size, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( fi->fh == 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EBADF;
	}

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EBADF;
	}

	tmp = psql_read_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( tmp < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return tmp;
	}

	if ( offset + size > meta.size )
	{
		meta.size = offset + size;
	}

	meta.mtime = now ();

	int fd;
	char path_r[1024] = { '\0' };
	get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, fi->fh, path_r );

	fd = open ( path_r, O_WRONLY );
	if ( fd == -1 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	res = pwrite ( fd, buf, size, offset );
	if ( res == -1 )
	{
		close ( fd );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	close ( fd );

	uid_t uid = fuse_get_context ()->uid;

	sprintf ( format_str, "Запись %s id=%"PRIi64" UID=%d buf_size=%zu, thread #%u", path, fi->fh, uid, size, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	res_meta = psql_write_meta ( conn, data->thredis, fi->fh, path, &meta );

	if ( res_meta < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res_meta;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", fi->fh );
	int event = 1;
	reply = thredis_command ( data->thredis, "HSET %s %s %b", group, "event", &event, ( size_t ) sizeof(int) );
	freeReplyObject ( reply );
	reply = thredis_command ( data->thredis, "HSET %s %s %b", group, "uid", &uid, ( size_t ) sizeof(uid_t) );
	freeReplyObject ( reply );

	return res;
}

static int pgfuse_read ( const char* path, char* buf, size_t size, off_t offset, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;
	PGconn* conn;
	int64_t tmp;
	PgMeta meta;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Read to '%s' from offset %jd, size %zu on '%s', thread #%u", path, offset, size, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	sprintf ( format_str, "Чтение %s id=%"PRIi64" buf_size=%zu, thread #%u", path, fi->fh, size, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( fi->fh == 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EBADF;
	}

	int fd;
	char path_r[1024] = { '\0' };
	get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, fi->fh, path_r );

	fd = open ( path_r, O_RDONLY );
	if ( fd == -1 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	res = pread ( fd, buf, size, offset );
	if ( res == -1 )
	{
		close ( fd );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	close ( fd );

	if ( !data->noatime )
	{
		tmp = psql_read_meta ( conn, data->thredis, fi->fh, path, &meta );
		if ( tmp < 0 )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return tmp;
		}

		meta.atime = now ();

		tmp = psql_write_meta ( conn, data->thredis, fi->fh, path, &meta );
		if ( tmp < 0 )
		{
			PSQL_ROLLBACK( conn );
			RELEASE( conn );
			return tmp;
		}
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	redisReply* reply;
	int event = 2;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", fi->fh );

	reply = thredis_command ( data->thredis, "HGET %s %s", group, "event" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf ( format_str, "EVENT-HGET: %lld %d", reply->integer, reply->len );
		pgfuse_syslog ( LOG_ERR, format_str );
		int* val = ( int * ) calloc ( 1, sizeof(int) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			event = *val;
			free ( val );
		}
	}
	freeReplyObject ( reply );

	if ( event!=1 )
	{
		reply = thredis_command ( data->thredis, "HSET %s %s %b", group, "event", &event, ( size_t ) sizeof(int) );
		sprintf ( format_str, "READ-HSET-EVENT: %lld %d", reply->integer, event );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
	}

	return res;
}

static int pgfuse_truncate ( const char* path, off_t offset )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Truncate of '%s' to size '%jd' on '%s', thread #%u", path, offset, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	sprintf ( format_str, "Обрезание файла %s id=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_INFO, format_str );

	if ( S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EISDIR;
	}

	sprintf ( format_str, "Id of file '%s' to be truncated is %"PRIi64", thread #%u", path, id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );


	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	char path_r[1024] = { '\0' };
	get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, id, path_r );

	res = truncate ( path_r, offset );
	if ( res == -1 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	meta.size = offset;

	res = psql_write_meta ( conn, data->thredis, id, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_ftruncate ( const char* path, off_t offset, struct fuse_file_info* fi )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	int res;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Truncate of '%s' to size '%jd' on '%s', thread #%u", path, offset, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( fi->fh == 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EBADF;
	}

	id = psql_read_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	id = fi->fh;

	sprintf ( format_str, "Обрезание %s id=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_INFO, format_str );

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	int fd;
	char path_r[1024] = { '\0' };
	get_real_path_to_path ( conn, data->path_portal, data->path_temp, data->thredis, fi->fh, path_r );

	fd = open ( path_r, O_RDWR );

	if ( fd == -1 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}

	res = ftruncate ( fd, offset );
	if ( res == -1 )
	{
		close ( fd );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -errno;
	}
	close ( fd );

	meta.size = offset;
	meta.mtime = now ();

	res = psql_write_meta ( conn, data->thredis, fi->fh, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_statfs ( const char* path, struct statvfs* buf )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;

	res = statvfs("/data", buf);
	if (res == -1)
		return -errno;
	
	buf->f_fsid = 0x4FE3A364;
	if ( data->read_only )
	{
		buf->f_flag |= ST_RDONLY;
	}
	
	buf->f_namemax = MAX_FILENAME_LENGTH;
	
	return 0;
	/*
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	PGconn* conn;
	int64_t blocks_total, blocks_used, blocks_free, blocks_avail;
	int64_t files_total, files_used, files_free, files_avail;
	int res;
	int i;
	size_t nof_locations = MAX_TABLESPACE_OIDS;
	char* location[MAX_TABLESPACE_OIDS];
	FILE* mtab;
	struct mntent* m;
	struct mntent mnt;
	char strings[MTAB_BUFFER_SIZE];
	char* prefix;
	int prefix_len;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Statfs called on '%s', thread #%u", data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	memset ( buf, 0, sizeof(struct statvfs) );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	
	res = psql_get_tablespace_locations ( conn, location, &nof_locations, data->verbose );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	for ( i = 0; i < nof_locations; i++ )
	{
		char* old_path = location[i];
		char* new_path = realpath ( old_path, NULL );
		if ( new_path == NULL )
		{
			sprintf ( format_str, "realpath for '%s' failed: %s, pgfuse mount point '%s', thread #%u", old_path, strerror ( errno ), data->mountpoint, THREAD_ID );
			pgfuse_syslog ( LOG_ERR, format_str );
		}
		else
		{
			location[i] = new_path;
			free ( old_path );
		}
	}

	blocks_free = INT64_MAX;
	blocks_avail = INT64_MAX;

	mtab = setmntent ( MTAB_FILE, "r" );
	while ( ( m = getmntent_r ( mtab, &mnt, strings, sizeof ( strings ) ) ) != NULL )
	{
		struct statfs fs;

		if ( mnt.mnt_dir == NULL ) continue;

		prefix = NULL;
		prefix_len = 0;
		for ( i = 0; i < nof_locations; i++ )
		{
			if ( strncmp ( mnt.mnt_dir, location[i], strlen ( mnt.mnt_dir ) ) == 0 )
			{
				if ( strlen ( mnt.mnt_dir ) > prefix_len )
				{
					prefix_len = strlen ( mnt.mnt_dir );
					prefix = strdup ( mnt.mnt_dir );
					blocks_free = INT64_MAX;
					blocks_avail = INT64_MAX;
				}
			}
		}
		if ( prefix == NULL ) continue;

		res = statfs ( prefix, &fs );
		if ( res < 0 )
		{
			sprintf ( format_str, "statfs on MTAB_FILE='%s' , '%s' failed: %s,  pgfuse mount point '%s', thread #%u", MTAB_FILE, prefix, strerror ( errno ), data->mountpoint, THREAD_ID );
			pgfuse_syslog ( LOG_ERR, format_str );
			return res;
		}

		sprintf ( format_str, "Checking mount point MTAB_FILE='%s' ,'%s' for free disk space, now %jd, was %jd, pgfuse mount point '%s', thread #%u", MTAB_FILE, prefix, fs.f_bfree, blocks_free, data->mountpoint, THREAD_ID );
		pgfuse_syslog ( LOG_DEBUG, format_str );

		if ( fs.f_bfree * fs.f_frsize < blocks_free * data->block_size )
		{
			blocks_free = fs.f_bfree * fs.f_frsize / data->block_size;
		}
		if ( fs.f_bavail * fs.f_frsize < blocks_avail * data->block_size )
		{
			blocks_avail = fs.f_bavail * fs.f_frsize / data->block_size;
		}

		if ( prefix ) free ( prefix );
	}
	endmntent ( mtab );

	for ( i = 0; i < nof_locations; i++ )
	{
		if ( location[i] ) free ( location[i] );
	}

	blocks_used = psql_get_fs_blocks_used ( conn );
	if ( blocks_used < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return blocks_used;
	}

	blocks_total = blocks_avail + blocks_used;
	blocks_free = blocks_avail;

	files_total = INT64_MAX;

	files_used = psql_get_fs_files_used ( conn );
	if ( files_used < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return files_used;
	}

	files_free = files_total - files_used;
	files_avail = files_free;
	
	buf->f_bsize = data->block_size;
	buf->f_frsize = data->block_size;
	buf->f_blocks = blocks_total;
	buf->f_bfree = blocks_free;
	buf->f_bavail = blocks_avail;
	buf->f_files = files_total;
	buf->f_ffree = files_free;
	buf->f_favail = files_avail;
	buf->f_fsid = 0x4FE3A364;
	if ( data->read_only )
	{
		buf->f_flag |= ST_RDONLY;
	}
	buf->f_namemax = MAX_FILENAME_LENGTH;

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
	*/
}

static int pgfuse_chmod ( const char* path, mode_t mode )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Смена режима %s mode=%d", path, mode );
	pgfuse_syslog ( LOG_INFO, format_str );

	sprintf ( format_str, "Chmod on '%s' to mode '%o' on '%s', thread #%u", path, ( unsigned int ) mode, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	meta.mode = mode;
	meta.ctime = now ();

	res = psql_write_meta ( conn, data->thredis, id, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_chown ( const char* path, uid_t uid, gid_t gid )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Chown on '%s' to uid '%d' and gid '%d' on '%s', thread #%u", path, ( unsigned int ) uid, ( unsigned int ) gid, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	sprintf ( format_str, "Смена владельца и группы %s uid=%d gid=%d", path, uid, gid );
	pgfuse_syslog ( LOG_INFO, format_str );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( data->read_only )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	meta.uid = uid;
	meta.gid = gid;
	meta.ctime = now ();

	res = psql_write_meta ( conn, data->thredis, id, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	if ( id < MAX_ID_PORTAL )
	{
		uint64_t userid = get_userid_from_uid ( conn, data->thredis, meta.uid );
		if ( userid > 0 )
		{
			if ( S_ISDIR( meta.mode ) )
			{
				char str[URL_SIZE] = { '\0' };
				sprintf ( str, "/update-folder-owner/folder-id/%"PRIi64"/user-id/%"PRIi64"/", id, userid );
				curl_http_get ( str );
			}
			else
			{
				char str[URL_SIZE] = { '\0' };
				sprintf ( str, "/update-file-owner/file-entry-id/%"PRIi64"/user-id/%"PRIi64"/", id, userid );
				curl_http_get ( str );
			}
		}
	}

	return res;
}

static int pgfuse_symlink ( const char* from, const char* to )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	char* copy_to;
	char* parent_path;
	char* symlink;
	int64_t parent_id;
	int res;
	int64_t id;
	PgMeta meta;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Symlink from '%s' to '%s' on '%s', thread #%u", from, to, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	copy_to = strdup ( to );
	if ( copy_to == NULL )
	{
		sprintf ( format_str, "Out of memory in Symlink '%s'!", to );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	parent_path = dirname ( copy_to );

	parent_id = psql_read_meta_from_path ( conn, data->thredis, parent_path, &meta );
	if ( parent_id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return parent_id;
	}
	if ( !S_ISDIR( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOENT;
	}

	sprintf ( format_str, "Parent_id for symlink '%s' is %"PRIi64", thread #%u", to, parent_id, THREAD_ID );
	pgfuse_syslog ( LOG_DEBUG, format_str );


	free ( copy_to );
	copy_to = strdup ( to );
	if ( copy_to == NULL )
	{
		sprintf ( format_str, "Out of memory in Symlink '%s'!", to );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	if ( data->read_only )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	symlink = basename ( copy_to );

	meta.size = strlen ( from ); /* size = length of path */
	meta.mode = 0777 | S_IFLNK; /* symlinks have no modes per se */
	/* TODO: use FUSE context */
	meta.uid = fuse_get_context ()->uid;
	meta.gid = fuse_get_context ()->gid;
	meta.ctime = now ();
	meta.mtime = meta.ctime;
	meta.atime = meta.ctime;

	res = psql_create_symlink ( conn, parent_id, to, symlink, meta );
	if ( res < 0 )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	id = psql_read_meta_from_path ( conn, data->thredis, to, &meta );
	if ( id < 0 )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	res = psql_write_buf ( conn, data->block_size, id, to, from, 0, strlen ( from ), data->verbose );
	if ( res < 0 )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	if ( res != strlen ( from ) )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EIO;
	}

	free ( copy_to );

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_rename ( const char* from, const char* to )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	PGconn* conn;
	int res;
	int64_t from_id;
	int64_t to_id;
	PgMeta from_meta;
	PgMeta to_meta;
	char* copy_to;
	char* parent_path;
	int64_t to_parent_id;
	PgMeta to_parent_meta;
	char* rename_to;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Renaming '%s' to '%s' on '%s', thread #%u", from, to, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );


	sprintf ( format_str, "Переименование из %s в %s", from, to );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	from_id = psql_read_meta_from_path ( conn, data->thredis, from, &from_meta );
	if ( from_id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return from_id;
	}

	to_id = psql_read_meta_from_path ( conn, data->thredis, to, &to_meta );
	if ( to_id < 0 && to_id != -ENOENT )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return to_id;
	}

	/* destination already exists */
	if ( to_id > 0 )
	{
		/* destination is a file */
		if ( S_ISREG( to_meta.mode ) )
		{
			if ( strcmp ( from, to ) == 0 )
			{
				/* source equal to destination? This should succeed */
				PSQL_ROLLBACK( conn );
				RELEASE( conn );
				return 0;
			}
			else
			{
				/* otherwise make source file disappear and
				 * destination file contain the same data
				 * as the source one (preferably atomic because
				 * of rename/lockfile tricks)
				 */
				res = psql_rename_to_existing_file ( conn, data->path_portal, data->path_temp, data->thredis, from_id, to_id, from, to );
				if ( res < 0 )
				{
					PSQL_ROLLBACK( conn );
					RELEASE( conn );
					return res;
				}

				PSQL_COMMIT( conn );
				RELEASE( conn );

				redisReply* reply;
				char Hash[MD5_BUF] = { '\0' };
				md5_hash ( from, Hash );
				char group1[MD5_BUF] = { '\0' };
				sprintf ( group1, "%"PRIi64":dir", from_meta.parent_id );
				char group_id[MD5_BUF+10] = { '\0' };
				sprintf ( group_id, "%s:path", Hash );
				reply = thredis_command ( data->thredis, "DEL %s %s", group_id, group1 );
				sprintf ( format_str, "DEL %s %s : %lld ", group1, group_id, reply->integer );
				pgfuse_syslog ( LOG_ERR, format_str );
				freeReplyObject ( reply );

				return res;
			}
		}
		/* TODO: handle all other cases */
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EINVAL;
	}

	copy_to = strdup ( to );
	if ( copy_to == NULL )
	{
		sprintf ( format_str, "Out of memory in Rename '%s'!", to );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	parent_path = dirname ( copy_to );

	to_parent_id = psql_read_meta_from_path ( conn, data->thredis, parent_path, &to_parent_meta );
	if ( to_parent_id < 0 )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return to_parent_id;
	}

	if ( !S_ISDIR( to_parent_meta.mode ) )
	{
		sprintf ( format_str, "Weird situation in Rename, '%s' expected to be a directory!", parent_path );
		pgfuse_syslog ( LOG_ERR, format_str );
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EIO;
	}

	free ( copy_to );
	copy_to = strdup ( to );
	if ( copy_to == NULL )
	{
		sprintf ( format_str, "Out of memory in Rename '%s'!", to );
		pgfuse_syslog ( LOG_ERR, format_str );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	if ( data->read_only )
	{
		free ( copy_to );
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -EROFS;
	}

	rename_to = basename ( copy_to );

	res = psql_rename ( conn, data->path_portal, data->path_temp, data->thredis, from_id, from_meta.parent_id, to_parent_id, rename_to, from, to );

	PSQL_COMMIT( conn );
	RELEASE( conn );

	free ( copy_to );
	redisReply* reply;
	char Hash[MD5_BUF] = { '\0' };
	md5_hash ( from, Hash );
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64":dir", to_parent_id );
	char group1[MD5_BUF] = { '\0' };
	sprintf ( group1, "%"PRIi64":dir", from_meta.parent_id );
	char group_id[MD5_BUF+10] = { '\0' };
	sprintf ( group_id, "%s:path", Hash );
	reply = thredis_command ( data->thredis, "DEL %s %s %s", group_id, group, group1 );
	sprintf ( format_str, "DEL %s %s %s : %lld ", group, group1, group_id, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return res;
}

static int pgfuse_readlink ( const char* path, char* buf, size_t size )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Dereferencing symlink '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}
	if ( !S_ISLNK( meta.mode ) )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOENT;
	}

	if ( size < meta.size + 1 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return -ENOMEM;
	}

	res = psql_read_buf ( conn, data->thredis, data->block_size, id, path, buf, 0, meta.size, data->verbose );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	buf[meta.size] = '\0';

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_utimens ( const char* path, const struct timespec tv[2] )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int64_t id;
	PgMeta meta;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Utimens on '%s' to access time '%d' and modification time '%d' on '%s', thread #%u", path, ( unsigned int ) tv[0].tv_sec, ( unsigned int ) tv[1].tv_sec, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	id = psql_read_meta_from_path ( conn, data->thredis, path, &meta );
	if ( id < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return id;
	}

	if ( !data->noatime )
	{
		meta.atime = tv[0];
	}

	meta.mtime = tv[1];

	res = psql_write_meta ( conn, data->thredis, id, path, &meta );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}

static int pgfuse_setxattr ( const char* path, const char* name, const char* value, size_t size, int flags )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Set xattr '%s' on '%s' with name '%s' and value '%s', thread #%u", path, data->mountpoint, name, value, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	if ( flags & XATTR_REPLACE )
	{
		res = psql_set_xattr_replace ( conn, data->thredis, path, name, value, size );
	}
	else
	{
		res = psql_set_xattr_create ( conn, data->thredis, path, name, value, size );
	}

	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return res;
}

static int pgfuse_getxattr ( const char* path, const char* name, char* value, size_t size )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Get xattr '%s' on '%s' with name '%s', thread #%u", path, data->mountpoint, name, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	res = psql_get_xattr ( conn, data->thredis, path, name, value, size );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return res;
}

static int pgfuse_listxattr ( const char* path, char* list, size_t size )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "List xattr '%s' on '%s', thread #%u", path, data->mountpoint, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	res = psql_list_xattr ( conn, data->thredis, path, list, size );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return res;
}

static int pgfuse_removexattr ( const char* path, const char* name )
{
	PgFuseData* data = ( PgFuseData * ) fuse_get_context ()->private_data;
	int res;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

	sprintf ( format_str, "Remove xattr '%s' on '%s' with name '%s', thread #%u", path, data->mountpoint, name, THREAD_ID );
	pgfuse_syslog ( LOG_INFO, format_str );

	ACQUIRE( conn );
	PSQL_BEGIN( conn );

	res = psql_delete_xattr ( conn, data->thredis, path, name );
	if ( res < 0 )
	{
		PSQL_ROLLBACK( conn );
		RELEASE( conn );
		return res;
	}

	PSQL_COMMIT( conn );
	RELEASE( conn );

	return 0;
}
/*
static int pgfuse_lock(const char* path, struct fuse_file_info* fi, int cmd, struct flock* lock)
{
	PgFuseData* data = (PgFuseData *)fuse_get_context()->private_data;
	PGconn* conn;
	char format_str[LOG_LEN] = { '\0' };

 ACQUIRE( conn );
 PSQL_BEGIN( conn );

 //fi->fh = psql_path_to_id(conn, data->thredis, path);

 pgfuse_syslog(LOG_INFO, "Блокировка %s ID=%"PRIi64"", path, fi->fh);

 int res = 0;


 pgfuse_syslog(LOG_INFO, "pgfuse_lock with name %s ", path);


 int fd;
 char path_r[1024] = {'0'};
 get_real_path_to_path(conn, data->thredis, fi->fh, path_r);

 fd = open(path_r, O_RDWR);

 if (fd == -1)
 {
 PSQL_ROLLBACK( conn );
 RELEASE( conn );
 return -errno;
 }

 res = ulockmgr_op(fd, cmd, lock, &fi->lock_owner, sizeof(fi->lock_owner));

 PSQL_COMMIT( conn );
 RELEASE( conn );

 close(fd);

 return res;
 }

 static int pgfuse_flock(const char* path, struct fuse_file_info* fi, int op)
 {
 PgFuseData* data = (PgFuseData *)fuse_get_context()->private_data;
 int res = 0;
 PGconn* conn;

 ACQUIRE( conn );
 PSQL_BEGIN( conn );

 pgfuse_syslog(LOG_INFO, "Блокировка файла %s ID=%"PRIi64"", path, fi->fh);


 pgfuse_syslog(LOG_INFO, "pgfuse_lock with name %s ", path);

 int fd;
 char path_r[1024] = {'0'};
 get_real_path_to_path(conn, data->thredis, fi->fh, path_r);

 fd = open(path_r, O_RDWR);

 if (fd == -1)
 {
 PSQL_ROLLBACK( conn );
 RELEASE( conn );
 return -errno;
 }

 res = flock(fd, op);

 if (res == -1)
 {
 PSQL_ROLLBACK( conn );
 RELEASE( conn );
 close(fd);
 return -errno;
 }

 PSQL_COMMIT( conn );
 RELEASE( conn );

 close(fd);

 return 0;
 }
 */

static struct fuse_operations pgfuse_oper =
{
	.getattr = pgfuse_getattr,
	.readlink = pgfuse_readlink,
	.mknod = NULL, /* not used, we use 'create' */
	.mkdir = pgfuse_mkdir,
	.unlink = pgfuse_unlink,
	.rmdir = pgfuse_rmdir,
	.symlink = pgfuse_symlink,
	.rename = pgfuse_rename,
	.link = NULL,
	.chmod = pgfuse_chmod,
	.chown = pgfuse_chown,
	.utime = NULL,            /* deprecated in favour of 'utimes' */
	.open = pgfuse_open,
	.read = pgfuse_read,
	.write = pgfuse_write,
	.statfs = pgfuse_statfs,
	.flush = NULL,          //pgfuse_flush,
	.release = pgfuse_release,
	.fsync = NULL,          //pgfuse_fsync,
	.setxattr = pgfuse_setxattr,
	.getxattr = pgfuse_getxattr,
	.listxattr = pgfuse_listxattr,
	.removexattr = pgfuse_removexattr,
	.opendir = pgfuse_opendir,
	.readdir = pgfuse_readdir,
	.releasedir = NULL,          //pgfuse_releasedir,
	.fsyncdir = NULL,          //pgfuse_fsyncdir,
	.init = pgfuse_init,
	.destroy = pgfuse_destroy,
	.access = pgfuse_access,
	.create = pgfuse_create,
	.truncate = pgfuse_truncate,
	.ftruncate = pgfuse_ftruncate,
	.fgetattr = pgfuse_fgetattr,
	.lock = NULL,          //pgfuse_lock,
	.flock = NULL,          //pgfuse_flock,
	.utimens = pgfuse_utimens,
	.bmap = NULL,
	//.flag_nullpath_ok = 1,
#if FUSE_VERSION >= 28
	.ioctl = NULL,
	.poll = NULL
#endif
};

/* --- parse arguments --- */

typedef struct PgFuseOptions
{
	int print_help; /* whether we should print a help page */
	int print_version; /* whether we should print the version */
	int verbose; /* whether we should be verbose */
	char* path_portal; /* path portal DATA */
	char* path_temp; /* path temp DATA */
	char* conninfo; /* connection info as used in PQconnectdb */
	char* mountpoint; /* where we mount the virtual filesystem */
	int read_only; /* whether to mount read-only */
	int noatime; /* be more efficient by not recording all access times */
	int multi_threaded; /* whether we run multi-threaded */
	size_t block_size; /* block size to use to store data in BYTEA fields */
} PgFuseOptions;

#define PGFUSE_OPT( t, p, v ) { t, offsetof( PgFuseOptions, p ), v }

enum
{
	KEY_HELP, KEY_VERBOSE, KEY_VERSION
};

static struct fuse_opt pgfuse_opts[] = {
PGFUSE_OPT( "ro", read_only, 1 ),
PGFUSE_OPT( "noatime", noatime, 1 ),
PGFUSE_OPT( "blocksize=%d", block_size, DEFAULT_BLOCK_SIZE ), FUSE_OPT_KEY ( "-h", KEY_HELP ), FUSE_OPT_KEY ( "--help", KEY_HELP ), FUSE_OPT_KEY ( "-v", KEY_VERBOSE ), FUSE_OPT_KEY ( "--verbose", KEY_VERBOSE ), FUSE_OPT_KEY ( "-V", KEY_VERSION ), FUSE_OPT_KEY ( "--version", KEY_VERSION ), FUSE_OPT_END };

static int pgfuse_opt_proc ( void* data, const char* arg, int key, struct fuse_args* outargs )
{
	PgFuseOptions* pgfuse = ( PgFuseOptions * ) data;

	switch ( key )
	{
	case FUSE_OPT_KEY_OPT:
		if ( strcmp ( arg, "-s" ) == 0 )
		{
			pgfuse->multi_threaded = 0;
		}
		return 1;

	case FUSE_OPT_KEY_NONOPT:
		if ( pgfuse->conninfo == NULL )
		{
			char *str = strdup ( arg );
			char* tok = strtok ( str, ";" );
	                pgfuse->conninfo = strdup ( tok );
			tok = strtok ( NULL, ";" );
                        pgfuse->path_portal = strdup( tok );
                        tok = strtok ( NULL, ";" );
			pgfuse->path_temp = strdup ( tok );
        	        if ( strstr ( str, "-s" ) != NULL )
	                {
                        pgfuse->multi_threaded = 0;
                	}
	                if ( strstr ( str, "-v" ) != NULL )
        	        {
                        pgfuse->verbose = 1;
                	}
			free ( str );
			return 0;
		}
//		else if ( pgfuse->path_portal == NULL )
//		{
//			pgfuse->path_portal = strdup ( arg );
//			return 0;
//		}
//		else if ( pgfuse->path_temp == NULL )
//		{
//			pgfuse->path_temp = strdup ( arg );
//			return 0;
//		}
                else if ( pgfuse->mountpoint == NULL )
                {
                        pgfuse->mountpoint = strdup ( arg );
                        return 1;
                }
		else
		{
			fprintf ( stderr, "%s, only two arguments allowed: Postgresql connection data and mountpoint\n", basename ( outargs->argv[0] ) );
			return -1;
		}

	case KEY_HELP:
		pgfuse->print_help = 1;
		return -1;

	case KEY_VERBOSE:
		pgfuse->verbose = 1;
		return 0;

	case KEY_VERSION:
		pgfuse->print_version = 1;
		return -1;

	default:
		return -1;
	}
}

static void print_usage ( char* progname )
{
	printf ( "Usage: %s <Postgresql Connection String> <mountpoint> <portal data path> <temp data path>\n"
			"\n"
			"Postgresql Connection String (key=value separated with whitespaces) :\n"
			"\n"
			"    host                   optional (ommit for Unix domain sockets), e.g. 'localhost'\n"
			"    port                   default is 5432\n"
			"    dbname                 database to connect to\n"
			"    user                   database user to connect with\n"
			"    password               for password credentials (or rather use ~/.pgpass)\n"
			"    ...\n"
			"    for more options see libpq, PQconnectdb\n"
			"\n"
			"Example: \"dbname=test user=test password=xx\"\n"
			"\n"
			"Options:\n"
			"    -o opt,[opt...]        pgfuse options\n"
			"    -v   --verbose         make FUSE print verbose debug\n"
			"    -h   --help            print help\n"
			"    -V   --version         print version\n"
			"\n"
			"PgFuse options:\n"
			"    ro                     mount filesystem read-only, do not change data in database\n"
			"    noatime                do not try to keep access time up to date on every read (only on close)\n"
			"    blocksize=<bytes>      block size to use for storage of data\n"
			"\n", progname );
}

/* --- main --- */

int main ( int argc, char* argv[] )
{
	int res;
	PGconn* conn;
	struct fuse_args args = FUSE_ARGS_INIT ( argc, argv );
	PgFuseOptions pgfuse;
	PgFuseData userdata;
	const char* value;
	/*
	 struct timeval timeout = { 1, 500000 }; // 1.5 seconds
	 Redisc = redisConnectUnixWithTimeout( "/tmp/redis.sock", timeout );
	 if (Redisc == NULL || Redisc->err) {
	 if (Redisc) {
	 printf("Connection error: %s\n", Redisc->errstr);
	 redisFree(Redisc);
	 } else {
	 printf("Connection error: can't allocate redis context\n");
	 }
	 exit(1);
	 }
	 */
	memset ( &pgfuse, 0, sizeof ( pgfuse ) );
	pgfuse.multi_threaded = 1;
	pgfuse.block_size = DEFAULT_BLOCK_SIZE;

	if ( fuse_opt_parse ( &args, &pgfuse, pgfuse_opts, pgfuse_opt_proc ) == -1 )
	{
		if ( pgfuse.print_help )
		{
			/* print our options */
			print_usage ( basename ( argv[0] ) );
			fflush ( stdout );
			/* print options of FUSE itself */
			argv[1] = "-ho";
			argv[2] = "mountpoint";
			( void ) dup2 ( STDOUT_FILENO, STDERR_FILENO ); /* force fuse help to stdout */
			fuse_main ( 2, argv, &pgfuse_oper, NULL );
			exit ( EXIT_SUCCESS );
		}
		if ( pgfuse.print_version )
		{
			printf ( "%s\n", PGFUSE_VERSION );
			exit ( EXIT_SUCCESS );
		}
		exit ( EXIT_FAILURE );
	}

	if ( pgfuse.conninfo == NULL )
	{
		fprintf ( stderr, "Missing Postgresql connection data\n" );
		fprintf ( stderr, "See '%s -h' for usage\n", basename ( argv[0] ) );
		exit ( EXIT_FAILURE );
	}

	if ( pgfuse.path_portal == NULL )
	{
		fprintf ( stderr, "Missing portal data path\n" );
		fprintf ( stderr, "See '%s -h' for usage\n", basename ( argv[0] ) );
		exit ( EXIT_FAILURE );
	}

	if ( pgfuse.path_temp == NULL )
	{
		fprintf ( stderr, "Missing path for temp data\n" );
		fprintf ( stderr, "See '%s -h' for usage\n", basename ( argv[0] ) );
		exit ( EXIT_FAILURE );
	}else


	/* just test if the connection can be established, do the
	 * real connection in the fuse init function!
	 */
	conn = PQconnectdb ( pgfuse.conninfo );
	if ( PQstatus ( conn ) != CONNECTION_OK )
	{
		fprintf ( stderr, "Connection to database failed: %s", PQerrorMessage ( conn ) );
		PQfinish ( conn );
		exit ( EXIT_FAILURE );
	}

	/* test storage of timestamps (expecting uint64 as it is the
	 * standard for PostgreSQL 8.4 or newer). Otherwise bail out
	 * currently..
	 */

	value = PQparameterStatus ( conn, "integer_datetimes" );
	if ( value == NULL )
	{
		fprintf ( stderr, "PQ param integer_datetimes not available?\n"
				"You use a too old version of PostgreSQL..can't continue.\n" );
		PQfinish ( conn );
		exit ( EXIT_FAILURE );
	}

	if ( strcmp ( value, "on" ) != 0 )
	{
		fprintf ( stderr, "Expecting UINT64 for timestamps, not doubles. You may use an old version of PostgreSQL (<8.4)\n"
				"or PostgreSQL has been compiled with the deprecated compile option '--disable-integer-datetimes'\n" );
		PQfinish ( conn );
		exit ( EXIT_FAILURE );
	}

	openlog ( basename ( argv[0] ), LOG_PID, LOG_USER );

	/* Compare blocksize given as parameter and blocksize in database */
	res = psql_get_block_size ( conn, pgfuse.block_size );
	if ( res < 0 )
	{
		PQfinish ( conn );
		exit ( EXIT_FAILURE );
	}

	if ( res != pgfuse.block_size )
	{
		fprintf ( stderr, "Blocksize parameter mismatch (is '%zu', in database we have '%zu') taking the later one!\n", pgfuse.block_size, ( size_t ) res );
		PQfinish ( conn );
		exit ( EXIT_FAILURE );
	}

	PQfinish ( conn );

	/* check sanity of the mount point, remember it's permission and owner in
	 * case we want to inherit them or overrule them
	 */
	res = check_mountpoint ( &pgfuse.mountpoint );
	if ( res < 0 )
	{
		/* something is fishy, bail out, check_mountpointed reported errors already */
		exit ( EXIT_FAILURE );
	}

	memset ( &userdata, 0, sizeof(PgFuseData) );
	userdata.conninfo       = pgfuse.conninfo;
	userdata.path_temp      = pgfuse.path_temp;
	userdata.path_portal    = pgfuse.path_portal;
	userdata.mountpoint     = pgfuse.mountpoint;
	userdata.verbose        = pgfuse.verbose;
	userdata.read_only      = pgfuse.read_only;
	userdata.noatime        = pgfuse.noatime;
	userdata.multi_threaded = pgfuse.multi_threaded;
	userdata.block_size     = pgfuse.block_size;

	res = fuse_main ( args.argc, args.argv, &pgfuse_oper, &userdata );

	closelog ();

	exit ( res );
}
