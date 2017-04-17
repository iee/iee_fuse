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
 http://srv-pgfuse.georec.spb.ru:8080/api/jsonws/sync2-notifications-portlet.ieefile
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <string.h> /* for strlen, memcpy, strcmp, strtok_r */
#include <libgen.h> /* for POSIX compliant basename */
#include <stdlib.h> /* for atoi */
#include <stdio.h> /* for fprintf */
#include <errno.h> /* for ENOENT and friends */
#include <arpa/inet.h> /* for htonl, ntohl */
#include <stdint.h> /* for uint64_t */
#include <inttypes.h> /* for PRIxxx macros */
#include <values.h> /* for INT_MAX */
#include <linux/xattr.h>
#include <curl/curl.h>
#include <wctype.h>
#include <ctype.h>
#include <stdbool.h>
#include <unistd.h>
#include <pthread.h>
#include <json-c/json.h>
#include <confuse.h>

#include <samba-4.0/wbclient.h>
#include "config.h" /* compiled in defaults */
#include "pgsql.h"

/* January 1, 2000, 00:00:00 UTC (in Unix epoch seconds) */

#define POSTGRES_EPOCH_DATE 946684800

typedef struct PgDataInfo
{
	int64_t from_block;
	off_t from_offset;
	size_t from_len;
	int64_t to_block;
	size_t to_len;
} PgDataInfo;

/* --- helper functions --- */

void md5_hash ( const char* path, char* dst )
{
	unsigned char result[MD5_DIGEST_LENGTH] = { '\0' };
	char res_out[MD5_BUF] = { '\0' };
	MD5 ( ( unsigned char* ) path, strlen ( path ), result );
	int i;
	for ( i = 0; i < MD5_DIGEST_LENGTH; i++ )
	{
		sprintf ( res_out + i * 2, "%02X", result[i] );
	}
	strcpy ( dst, res_out );
}

int64_t get_groupid_from_path ( const char* path )
{
	int64_t id;
	char* sep = "/";
	char* istr;
	char* str = calloc ( strlen ( path ) + 1, sizeof(char) );
	memcpy ( str, path, strlen ( path ) );
	istr = strtok ( str + 1, sep );
	id = atoi ( istr );
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Получение groupid = %"PRIi64" из path=%s", id, str );
	pgfuse_syslog ( LOG_ERR, format_str );

	free ( str );
	return id;
}

int64_t get_groupid_from_parent_id ( PGconn* conn, const int64_t parent_id )
{
	int64_t groupid;
	PGresult* res;
	int idx;
	char* data;
	int64_t param1 = be64toh( parent_id );
	const char* values[1] = { ( const char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };
	char format_str[LOG_LEN] = { '\0' };

	res = PQexecParams ( conn, "SELECT groupid FROM dlfolder WHERE folderid = $1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_get_meta for path %"PRIi64"", parent_id );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf ( format_str, "Expecting exactly one inode for path %"PRIi64" in psql_get_meta, data inconsistent!", parent_id );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "groupid" );
	data = PQgetvalue ( res, 0, idx );
	groupid = be64toh( * ( ( int64_t * ) data ) );

	PQclear ( res );
	
	sprintf ( format_str, "Получение groupid = %"PRIi64" из parentid=%"PRIi64"", groupid, parent_id );
	pgfuse_syslog ( LOG_ERR, format_str );

	return groupid;
}

const char* get_filename_ext ( const char* filename )
{
	const char* dot = strrchr ( filename, '.' );
	if ( !dot || dot == filename ) return "";
	return dot + 1;
}
/*
 int wbinfo_get_screenname ( uid_t uid, char *screenname )
 {
 char* domain;
 wbcErr res_c;
 char* name;
 struct wbcDomainSid sid;
 enum wbcSidType name_type;
 res_c = wbcUidToSid ( uid, &sid );
 if ( res_c == 0 )
 {
 res_c = wbcLookupSid ( &sid, ( char ** ) &domain, ( char ** ) &name, &name_type );
 }
 if ( res_c != 0 ) name = "test";
 int i;
 char* str = calloc ( strlen ( name ) + 1, sizeof(char) );
 for ( i = 0; i < strlen ( name ); i++ )
 {
 str[i] = tolower ( name[i] );
 }
 str[i] = 0;
 if ( res_c == 0 )
 {
 wbcFreeMemory ( domain );
 wbcFreeMemory ( name );
 }
 strcpy ( screenname, str );
 free ( str );

 return res_c;
 }
 */
int64_t get_userid_from_uid ( PGconn* conn, thredis_t* thredis, uid_t uid )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	int64_t userid;
	char group[15] = { '\0' };
	sprintf ( group, "%d", uid );
	reply = thredis_command ( thredis, "GET %s:userid", group );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		int64_t* val = ( int64_t * ) calloc ( 1, sizeof(int64_t) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			userid = *val;
			free ( val );
			sprintf ( format_str, "GET %s:userid id=%d userid=%"PRIi64" : %lld ", group, uid, userid, reply->integer );
			pgfuse_syslog ( LOG_ERR, format_str );
		}
		freeReplyObject ( reply );
		return userid;
	}
	freeReplyObject ( reply );

	if(uid < 10000)
	{
		uid = 0;
	}
	PGresult* res;
	int idx;
	char* data;
	int32_t param1 = htonl ( uid );
	const char* values[1] = { ( char* ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };

	res = PQexecParams ( conn, "SELECT userid FROM user_ WHERE uid=$1::integer", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Нет такого пользователя в базе %d", uid );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		sprintf ( format_str, "Нет такого пользователя в базе %d", uid );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf ( format_str, "Есть больше одного пользователь %d", uid );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "userid" );
	data = PQgetvalue ( res, 0, idx );
	userid = htobe64( * ( ( int64_t * ) data ) );

	sprintf ( format_str, "Имя пользователя %d userid=%"PRIi64"", uid, userid );
	pgfuse_syslog ( LOG_ERR, format_str );

	PQclear ( res );

	reply = thredis_command ( thredis, "SET %s:userid %b", group, &userid, ( size_t ) sizeof ( userid ) );
	sprintf ( format_str, "SET %s:userid userid=%"PRIi64" : %lld ", group, userid, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return userid;
}

int get_real_path_to_path ( PGconn* conn, const char* path_portal, const char* path_temp, thredis_t* thredis, const int64_t id, char* real_path )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HGET %s %s", group, "path" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf ( real_path, "%s", reply->str );
		sprintf ( format_str, "HGET path=%s : %lld", real_path, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
		return 0;
	}
	freeReplyObject ( reply );

	if ( id < MAX_ID_PORTAL )
	{
		char* data;
		int64_t CompanyId;
		int64_t FolderId;
		int64_t GroupId;
		char* Name;
		char* Version;
		int idx;
		int64_t param1 = htobe64( id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "SELECT groupid, companyid, folderid FROM dlfileentry WHERE fileentryid=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
		{
			sprintf ( format_str, "Error in get_path_to_id for path id = %"PRIi64" : %s", param1, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}
		if ( PQntuples ( res ) == 0 )
		{
			PQclear ( res );
			return -ENOENT;
		}
		if ( PQntuples ( res ) > 1 )
		{
			sprintf ( format_str, "Error in get_path_to_id for id = %"PRIi64"", id );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		idx = PQfnumber ( res, "groupid" );
		data = PQgetvalue ( res, 0, idx );
		GroupId = htobe64( * ( ( int64_t * ) data ) );

		idx = PQfnumber ( res, "companyid" );
		data = PQgetvalue ( res, 0, idx );
		CompanyId = htobe64( * ( ( int64_t * ) data ) );

		idx = PQfnumber ( res, "folderid" );
		data = PQgetvalue ( res, 0, idx );
		FolderId = htobe64( * ( ( int64_t * ) data ) );

		PQclear ( res );

		res = PQexecParams ( conn, "SELECT name, version FROM dlfileentry WHERE fileentryid=$1::bigint", 1, NULL, values, lengths, binary, 0 );
		if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
		{
			sprintf ( format_str, "Error in get_path_to_id for path id = %"PRIi64" : %s", param1, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		if ( PQntuples ( res ) == 0 )
		{
			PQclear ( res );
			return -ENOENT;
		}

		if ( PQntuples ( res ) > 1 )
		{
			sprintf ( format_str, "Error in get_path_to_id for id = %"PRIi64"", id );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		idx = PQfnumber ( res, "name" );
		Name = PQgetvalue ( res, 0, idx );

		idx = PQfnumber ( res, "version" );
		Version = PQgetvalue ( res, 0, idx );

		sprintf ( real_path, "%s/%"PRIi64"/%"PRIi64"/%s/%s", path_portal, CompanyId, ( FolderId == 0 ? GroupId : FolderId ), Name, Version );

		PQclear ( res );
	}
	else
	{
		char* Name;
		int idx;

		int64_t param1 = htobe64( id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "SELECT uuid FROM dir_fs WHERE id=$1::bigint", 1, NULL, values, lengths, binary, 0 );
		if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
		{
			sprintf ( format_str, "Error in get_path_to_id for path id = %"PRIi64" : %s", param1, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		if ( PQntuples ( res ) == 0 )
		{
			sprintf ( format_str, "Error in PQntuples( res ) == 0 get_path_to_id for path id = %"PRIi64" : %s", param1, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -ENOENT;
		}

		if ( PQntuples ( res ) > 1 )
		{
			sprintf ( format_str, "Error in get_path_to_id for id = %"PRIi64"", id );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		idx = PQfnumber ( res, "uuid" );
		Name = PQgetvalue ( res, 0, idx );

		sprintf ( real_path, "%s/%s", path_temp, Name );

		PQclear ( res );
	}

	reply = thredis_command ( thredis, "HSET %s %s %s", group, "path", real_path );
	sprintf ( format_str, "R-PATH-HSET: %s %lld ", real_path, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

char* get_file_name ( const char* new_file )
{
	char* str;
	CURL* curl = curl_easy_init ();
	if ( curl )
	{
		char* output = curl_easy_escape ( curl, new_file, strlen ( new_file ) );
		if ( output )
		{
			str = calloc ( strlen ( output ) + 1, sizeof(char) );
			if ( str )
			{
				sprintf ( str, "%s", output );
				curl_free ( output );
			}
		}
		curl_easy_cleanup ( curl );
	}
	return str;
}

size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp)
{
	size_t realsize = size * nmemb;
	curl_fetch_st *mem = (struct curl_fetch_st *)userp;
	char format_str[LOG_LEN] = { '\0' };

	mem->memory = realloc(mem->memory, mem->size + realsize + 1);
	if(mem->memory == NULL)
	{
		/* out of memory! */ 
		sprintf ( format_str, "Out of memory in write_callback!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		return 0;
	}

	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;

	return realsize;
}

int64_t curl_http_get ( const char* str, cfg_t* cfg )
{
	char format_str[LOG_LEN] = { '\0' };
	CURL* curl;
	CURLcode res;
	int64_t id = 0;
	curl_fetch_st chunk;
	chunk.memory = calloc ( 1, 1 );		/* will be grown as needed by the realloc above */ 
	chunk.size = 0;					/* no data at this point */ 
	char url[URL_SIZE] = { '\0' };
	strcpy ( url, cfg_getstr ( cfg, "url") ); //"http://test:test@localhost:8080/o/rest/fuse" );
	strcat ( url, str );
	curl = curl_easy_init ();
	if ( curl )
	{
		curl_easy_setopt( curl, CURLOPT_URL, url );
		curl_easy_setopt( curl, CURLOPT_WRITEFUNCTION, write_callback );
		curl_easy_setopt( curl, CURLOPT_WRITEDATA, (void *)&chunk );
		curl_easy_setopt( curl, CURLOPT_USERAGENT, "libcurl-agent/1.0");
		res = curl_easy_perform ( curl );
		if ( res != CURLE_OK )
		{
			sprintf ( format_str, "curl ERROR failed: %s", curl_easy_strerror ( res ) );
			pgfuse_syslog ( LOG_ERR, format_str );
		}
		else
		{
			sprintf ( format_str, "curl OK url: %s", url);
			pgfuse_syslog ( LOG_ERR, format_str );
			struct json_object *object, *folderID, *fileID;
			object = json_tokener_parse(chunk.memory);
			if (json_object_object_get_ex(object, "fileEntryId", &fileID))
			{
				id = json_object_get_int64(fileID);
				sprintf ( format_str, "curl OK url: %s id=%"PRIi64"", url, id );
				pgfuse_syslog ( LOG_ERR, format_str );
			}
			else
			if (json_object_object_get_ex(object, "folderId", &folderID))
			{
				id = json_object_get_int64(folderID);
				sprintf ( format_str, "curl OK url: %s id=%"PRIi64"", url, id );
				pgfuse_syslog ( LOG_ERR, format_str );
			}
			json_object_put(object);
		}
		curl_easy_cleanup ( curl );
	}
	free(chunk.memory);

	return id;
}

static uint64_t convert_to_timestamp ( struct timespec t )
{
	return htobe64( ( ( uint64_t ) t.tv_sec - POSTGRES_EPOCH_DATE ) * 1000000 + t.tv_nsec / 1000 );
}

static struct timespec convert_from_timestamp ( uint64_t raw )
{
	uint64_t t;
	struct timespec ts;

	t = be64toh( raw );

	ts.tv_sec = POSTGRES_EPOCH_DATE + t / 1000000;
	ts.tv_nsec = ( t % 1000000 ) * 1000;

	return ts;
}

/* block information for read/write/truncate */

static PgDataInfo compute_block_info ( size_t block_size, off_t offset, size_t len )
{
	PgDataInfo info;
	int nof_blocks;

	info.from_block = offset / block_size;
	info.from_offset = offset % block_size;

	nof_blocks = ( info.from_offset + len ) / block_size;
	if ( nof_blocks == 0 )
	{
		info.from_len = len;
	}
	else
	{
		info.from_len = block_size - info.from_offset;
	}

	info.to_block = info.from_block + nof_blocks;
	info.to_len = ( info.from_offset + len ) % block_size;

	if ( info.to_len == 0 )
	{
		info.to_block--;
		if ( info.to_block < 0 )
		{
			info.to_block = 0;
		}
		info.to_len = block_size;
	}

	return info;
}

int psql_set_id_by_hash_to_redis ( thredis_t* thredis, const char* path, int64_t id )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	char Hash[MD5_BUF] = { '\0' };
	md5_hash ( path, Hash );
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%s", Hash );
	char ID[MD5_BUF] = { '\0' };
	reply = thredis_command ( thredis, "SET %s:path %b", group, &id, ( size_t ) sizeof(int64_t) );
	sprintf ( format_str, "SET %s:path id=%"PRIi64" path=%s : res=%lld ", group, be64toh( id ), path, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );
	sprintf ( ID, "%"PRIi64"", be64toh( id ) );
	reply = thredis_command ( thredis, "HSET %s %s %s", ID, "hashcode", group );
	sprintf ( format_str, "HSET %s hashcode=%s : res=%lld", ID, group, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}
int64_t psql_get_id_from_redis ( thredis_t* thredis, const char* path )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	int64_t id = htobe64( 0 );
	char group[MD5_BUF] = { '\0' };
	char Hash[MD5_BUF] = { '\0' };
	md5_hash ( path, Hash );
	sprintf ( group, "%s", Hash );
	reply = thredis_command ( thredis, "GET %s:path", group );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		int64_t* val = ( int64_t * ) calloc ( 1, sizeof(int64_t) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			id = *val;
			free ( val );
			sprintf ( format_str, "GET %s:path id=%"PRIi64" path=%s : %lld ", group, be64toh( id ), path, reply->integer );
			pgfuse_syslog ( LOG_ERR, format_str );
		}
	}
	else
	{
		freeReplyObject ( reply );
		return -ENOENT;
	}
	freeReplyObject ( reply );

	return id;
}
int64_t get_id_from_db ( PGconn* conn, int64_t parent_id, const char* name, int* dir )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Поиск в BD %s", name );
	pgfuse_syslog ( LOG_ERR, format_str );
	PGresult* res;
	int idx;
	int64_t id = htobe64( 0 );
	int mode;
	char* data;
	const char* values[2] = { name, ( const char * ) &parent_id };
	int lengths[2] = { strlen ( name ), sizeof ( parent_id ) };
	int binary[2] = { 0, 1 };

	res = PQexecParams ( conn, "SELECT id, mode FROM dir WHERE name = $1::varchar and parent_id = $2::bigint", 2, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Запрос не вернул результата name=%s parent_id=%"PRIi64" message=%s", name, be64toh( parent_id ), PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		sprintf ( format_str, "Имя в BD не найдено name=%s parent_id=%"PRIi64"", name, be64toh( parent_id ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf ( format_str, "Найдено больше одного варианта name=%s parent_id=%"PRIi64"", name, be64toh( parent_id ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "id" );
	data = PQgetvalue ( res, 0, idx );
	id = * ( ( int64_t * ) data );

	idx = PQfnumber ( res, "mode" );
	data = PQgetvalue ( res, 0, idx );
	mode = ntohl ( * ( ( uint32_t * ) data ) );

	if ( S_ISDIR( mode ) ) *dir = 1;
	sprintf ( format_str, "Из базы id=%"PRIi64" name = %s and parent_id = %"PRIi64" dir=%d", be64toh( id ), name, be64toh( parent_id ), *dir );
	pgfuse_syslog ( LOG_ERR, format_str );

	PQclear ( res );

	return id;
}
int64_t psql_path_to_id ( PGconn* conn, thredis_t* thredis, const char* path )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = htobe64( 0 );
	id = psql_get_id_from_redis ( thredis, path );
	if ( id != -ENOENT )
	{
		return be64toh( id );
	}
	else
	{
		char* copy_path = strdup ( path );
		if ( copy_path == NULL )
		{
			sprintf ( format_str, "Out of memory in Mkdir '%s'!", path );
			pgfuse_syslog ( LOG_ERR, format_str );
			return -ENOMEM;
		}
		char* parent_path = dirname ( copy_path );
		char* copy_path_name = strdup ( path );
		if ( copy_path_name == NULL )
		{
			sprintf ( format_str, "Out of memory in Mkdir '%s'!", path );
			pgfuse_syslog ( LOG_ERR, format_str );
			return -ENOMEM;
		}
		char* name = basename ( copy_path_name );
		if ( strcmp ( path, name ) == 0 )
		{
			id = be64toh( 0 );
			psql_set_id_by_hash_to_redis ( thredis, path, id );
			free ( copy_path );
			free ( copy_path_name );
			return id;
		}
		sprintf ( format_str, "parent_path=%s name=%s path=%s", parent_path, name, path );
		pgfuse_syslog ( LOG_ERR, format_str );
		int64_t parent_id = psql_get_id_from_redis ( thredis, parent_path );
		if ( parent_id != -ENOENT )
		{
			int dir;
			id = get_id_from_db ( conn, parent_id, name, &dir );
			if ( id != -ENOENT )
			{
				psql_set_id_by_hash_to_redis ( thredis, path, id );
				free ( copy_path );
				free ( copy_path_name );
				return be64toh( id );
			}
			else
			{
				free ( copy_path );
				free ( copy_path_name );
				return id;
			}
		}
		else
		{
			char* str_path = calloc ( 1, strlen ( path ) );
			if ( str_path == NULL )
			{
				sprintf ( format_str, "Out of memory in str_path %s!", path );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -ENOMEM;
			}
			int dir = 1;
			char* ptr = NULL;
			parent_id = htobe64( 0 );
			name = strtok_r ( copy_path, "/", &ptr );
			while ( dir && name != NULL )
			{
				strncat ( str_path, "/", 1 );
				strncat ( str_path, name, strlen ( name ) );
				id = psql_get_id_from_redis ( thredis, str_path );
				if ( id == -ENOENT )
				{
					id = get_id_from_db ( conn, parent_id, name, &dir );
					if ( id != -ENOENT )
					{
						psql_set_id_by_hash_to_redis ( thredis, str_path, id );
					}
					else
					{
						if ( id == -ENOENT )
						{
							free ( copy_path );
							free ( str_path );
							free ( copy_path_name );
							return id;
						}
					}
				}
				parent_id = id;
				name = strtok_r ( NULL, "/", &ptr );
			}
			free ( copy_path );
			free ( copy_path_name );
			free ( str_path );
		}
	}
	return be64toh( id );
}
int64_t psql_read_meta ( PGconn* conn, thredis_t* thredis, const int64_t id, const char* path, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HGET %s %s", group, "meta" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf ( format_str, "read-HGET-META: %lld %d", reply->integer, reply->len );
		pgfuse_syslog( LOG_ERR, format_str );
		PgMeta* val = ( PgMeta * ) calloc ( 1, sizeof(PgMeta) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			meta->size = val->size;
			meta->mode = val->mode;
			meta->uid = val->uid;
			meta->gid = val->gid;
			meta->ctime = val->ctime;
			meta->mtime = val->mtime;
			meta->atime = val->atime;
			meta->parent_id = val->parent_id;
			free ( val );
		}
		freeReplyObject ( reply );
		return id;
	}
	freeReplyObject ( reply );

	PGresult* res;
	int idx;
	char* data;
	int64_t param1 = be64toh( id );
	const char* values[1] = { ( const char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };

	res = PQexecParams ( conn, "SELECT size, mode, uid, gid, ctime, mtime, atime, parent_id FROM dir WHERE id = $1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_get_meta for path '%s'", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf ( format_str, "Expecting exactly one inode for path '%s' in psql_get_meta, data inconsistent!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "size" );
	data = PQgetvalue ( res, 0, idx );
	meta->size = be64toh( * ( ( int64_t * ) data ) );

	idx = PQfnumber ( res, "mode" );
	data = PQgetvalue ( res, 0, idx );
	meta->mode = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "uid" );
	data = PQgetvalue ( res, 0, idx );
	meta->uid = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "gid" );
	data = PQgetvalue ( res, 0, idx );
	meta->gid = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "ctime" );
	data = PQgetvalue ( res, 0, idx );
	meta->ctime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "mtime" );
	data = PQgetvalue ( res, 0, idx );
	meta->mtime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "atime" );
	data = PQgetvalue ( res, 0, idx );
	meta->atime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "parent_id" );
	data = PQgetvalue ( res, 0, idx );
	meta->parent_id = be64toh( * ( ( int64_t * ) data ) );

	PQclear ( res );

	reply = thredis_command ( thredis, "HSET %s %s %b", group, "meta", meta, ( size_t ) sizeof(PgMeta) );
	sprintf ( format_str, "META-HSET: %lld ",  reply->integer );
	pgfuse_syslog( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return id;
}

int64_t psql_read_meta_from_path ( PGconn* conn, thredis_t* thredis, const char* path, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = psql_path_to_id ( conn, thredis, path );
	if ( id < 0 )
	{
		return id;
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HGET %s %s", group, "meta" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf ( format_str, "read-HGET-META: ID=%"PRIi64" len=%d", id, reply->len );
		pgfuse_syslog( LOG_ERR, format_str );
		PgMeta* val = ( PgMeta * ) calloc ( 1, sizeof(PgMeta) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			meta->size = val->size;
			meta->mode = val->mode;
			meta->uid = val->uid;
			meta->gid = val->gid;
			meta->ctime = val->ctime;
			meta->mtime = val->mtime;
			meta->atime = val->atime;
			meta->parent_id = val->parent_id;
			free ( val );
		}
		freeReplyObject ( reply );
		return id;
	}
	freeReplyObject ( reply );

	PGresult* res;
	int idx;
	char* data;
	int64_t param1 = be64toh( id );
	const char* values[1] = { ( const char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };

	res = PQexecParams ( conn, "SELECT size, mode, uid, gid, ctime, mtime, atime, parent_id FROM dir WHERE id = $1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_get_meta for path '%s'", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf ( format_str, "Expecting exactly one inode for path '%s' in psql_get_meta, data inconsistent!", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "size" );
	data = PQgetvalue ( res, 0, idx );
	meta->size = be64toh( * ( ( int64_t * ) data ) );

	idx = PQfnumber ( res, "mode" );
	data = PQgetvalue ( res, 0, idx );
	meta->mode = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "uid" );
	data = PQgetvalue ( res, 0, idx );
	meta->uid = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "gid" );
	data = PQgetvalue ( res, 0, idx );
	meta->gid = ntohl ( * ( ( uint32_t * ) data ) );

	idx = PQfnumber ( res, "ctime" );
	data = PQgetvalue ( res, 0, idx );
	meta->ctime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "mtime" );
	data = PQgetvalue ( res, 0, idx );
	meta->mtime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "atime" );
	data = PQgetvalue ( res, 0, idx );
	meta->atime = convert_from_timestamp ( * ( ( uint64_t * ) data ) );

	idx = PQfnumber ( res, "parent_id" );
	data = PQgetvalue ( res, 0, idx );
	meta->parent_id = be64toh( * ( ( int64_t * ) data ) );

	PQclear ( res );

	reply = thredis_command ( thredis, "HSET %s %s %b", group, "meta", meta, ( size_t ) sizeof(PgMeta) );
	sprintf ( format_str, "META-HSET: %lld ", reply->integer );
	pgfuse_syslog( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return id;
}

int psql_write_meta ( PGconn* conn, thredis_t* thredis, const int64_t id, const char* path, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HSET %s %s %b", group, "meta", meta, ( size_t ) sizeof(PgMeta) );
	freeReplyObject ( reply );

	int event = 0;
	reply = thredis_command ( thredis, "HGET %s %s", group, "event" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		int* val = ( int * ) calloc ( 1, sizeof(int) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			event = *val;
			free ( val );
		}
	sprintf ( format_str, "HGET %s event=%d : %lld %d", group, event, reply->integer, reply->len );
	pgfuse_syslog( LOG_ERR, format_str );
	}
	freeReplyObject ( reply );

	if ( event == 0 )
	{
		sprintf ( format_str, "Запись МЕТА в BD id=%"PRIi64" size=%zu uid=%d gid=%d", id, meta->size, meta->uid, meta->gid );
		pgfuse_syslog ( LOG_ERR, format_str );

		int64_t param1 = htobe64( id );
		int64_t param2 = htobe64( meta->size );
		int param3 = htonl ( meta->mode );
		int param4 = htonl ( meta->uid );
		int param5 = htonl ( meta->gid );
		uint64_t param6 = convert_to_timestamp ( meta->ctime );
		uint64_t param7 = convert_to_timestamp ( meta->mtime );
		uint64_t param8 = convert_to_timestamp ( meta->atime );
		const char* values[8] = { ( const char * ) &param1, ( const char * ) &param2, ( const char * ) &param3, ( const char * ) &param4, ( const char * ) &param5, ( const char * ) &param6, ( const char * ) &param7, ( const char * ) &param8 };
		int lengths[8] = { sizeof ( param1 ), sizeof ( param2 ), sizeof ( param3 ), sizeof ( param4 ), sizeof ( param5 ), sizeof ( param6 ), sizeof ( param7 ), sizeof ( param8 ) };
		int binary[8] = { 1, 1, 1, 1, 1, 1, 1, 1 };
		PGresult* res;

		res = PQexecParams ( conn, "UPDATE dir SET size=$2::bigint, mode=$3::integer, uid=$4::integer, gid=$5::integer, ctime=$6::timestamp, mtime=$7::timestamp, atime=$8::timestamp WHERE id=$1::bigint", 8, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf ( format_str, "Error in psql_write_meta for file '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
	}

	return 0;
}

int psql_write_meta_to_path ( PGconn* conn, thredis_t* thredis, const char* path, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	const int64_t id = psql_path_to_id ( conn, thredis, path );
	if ( id < 0 )
	{
		return id;
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HSET %s %s %b", group, "meta", meta, ( size_t ) sizeof(PgMeta) );
	freeReplyObject ( reply );

	int event = 0;
	reply = thredis_command ( thredis, "HGET %s %s", group, "event" );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		int* val = ( int * ) calloc ( 1, sizeof(int) );
		if ( val )
		{
			memcpy ( val, reply->str, reply->len );
			event = *val;
			free ( val );
		}
	sprintf ( format_str, "HGET %s event=%d : %lld %d", group, event, reply->integer, reply->len );
	pgfuse_syslog( LOG_ERR, format_str );
	}
	freeReplyObject ( reply );

	if ( event == 0 )
	{
		sprintf ( format_str, "Запись мета по path в BD id=%"PRIi64" size=%zu uid=%d gid=%d", id, meta->size, meta->uid, meta->gid );
		pgfuse_syslog ( LOG_ERR, format_str );

		int64_t param1 = htobe64( id );
		int64_t param2 = htobe64( meta->size );
		int param3 = htonl ( meta->mode );
		int param4 = htonl ( meta->uid );
		int param5 = htonl ( meta->gid );
		uint64_t param6 = convert_to_timestamp ( meta->ctime );
		uint64_t param7 = convert_to_timestamp ( meta->mtime );
		uint64_t param8 = convert_to_timestamp ( meta->atime );
		const char* values[8] = { ( const char * ) &param1, ( const char * ) &param2, ( const char * ) &param3, ( const char * ) &param4, ( const char * ) &param5, ( const char * ) &param6, ( const char * ) &param7, ( const char * ) &param8 };
		int lengths[8] = { sizeof ( param1 ), sizeof ( param2 ), sizeof ( param3 ), sizeof ( param4 ), sizeof ( param5 ), sizeof ( param6 ), sizeof ( param7 ), sizeof ( param8 ) };
		int binary[8] = { 1, 1, 1, 1, 1, 1, 1, 1 };
		PGresult* res;

		res = PQexecParams ( conn, "UPDATE dir SET size=$2::bigint, mode=$3::integer, uid=$4::integer, gid=$5::integer, ctime=$6::timestamp, mtime=$7::timestamp, atime=$8::timestamp WHERE id=$1::bigint", 8, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf ( format_str, "Error in psql_write_meta for file '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
	}

	return 0;
}

int psql_create_symlink ( PGconn* conn, const int64_t parent_id, const char* path, const char* new_file, PgMeta meta )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t param1 = htobe64( parent_id );
	int64_t param2 = htobe64( meta.size );
	int param3 = htonl ( meta.mode );
	int param4 = htonl ( meta.uid );
	int param5 = htonl ( meta.gid );
	uint64_t param6 = convert_to_timestamp ( meta.ctime );
	uint64_t param7 = convert_to_timestamp ( meta.mtime );
	uint64_t param8 = convert_to_timestamp ( meta.atime );
	const char* values[9] = { ( const char * ) &param1, new_file, ( const char * ) &param2, ( const char * ) &param3, ( const char * ) &param4, ( const char * ) &param5, ( const char * ) &param6, ( const char * ) &param7, ( const char * ) &param8 };
	int lengths[9] = { sizeof ( param1 ), strlen ( new_file ), sizeof ( param2 ), sizeof ( param3 ), sizeof ( param4 ), sizeof ( param5 ), sizeof ( param6 ), sizeof ( param7 ), sizeof ( param8 ) };
	int binary[9] = { 1, 0, 1, 1, 1, 1, 1, 1, 1 };
	PGresult* res;

	res = PQexecParams ( conn, "INSERT INTO dir( parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES ($1::bigint, $2::varchar, $3::bigint, $4::integer, $5::integer, $6::integer, $7::timestamp, $8::timestamp, $9::timestamp )", 9, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf ( format_str, "Error in psql_create_file for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( atoi ( PQcmdTuples ( res ) ) != 1 )
	{
		sprintf ( format_str, "Expecting one new row in psql_create_file, not %d!", atoi ( PQcmdTuples ( res ) ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

int name_file_is_temp ( const char* new_file , cfg_t* cfg )
{
	char format_str[LOG_LEN] = { '\0' };
	int nu = strcmp ( new_file, "null" ) == 0 ? 1 : 0;
	int nul = strcmp ( get_filename_ext ( new_file ), "" ) == 0 ? 1 : 0;
	int m = cfg_size ( cfg, "file_extension" );
	int j;
	int bak = 0;
	for ( j = 0; j < m; j++)
	{
		bak += strcmp ( get_filename_ext ( new_file ), cfg_getnstr ( cfg, "file_extension", j ) ) == 0 ? 1 : 0;
	}
	/*
	int tmp = strcmp ( get_filename_ext ( new_file ), "tmp" ) == 0 ? 1 : 0;
	int db = strcmp ( get_filename_ext ( new_file ), "db" ) == 0 ? 1 : 0;
	int TMP = strcmp ( get_filename_ext ( new_file ), "TMP" ) == 0 ? 1 : 0;
	int bak = strcmp ( get_filename_ext ( new_file ), "bak" ) == 0 ? 1 : 0;
	int dwl = strcmp ( get_filename_ext ( new_file ), "dwl" ) == 0 ? 1 : 0;
	int dwl2 = strcmp ( get_filename_ext ( new_file ), "dwl2" ) == 0 ? 1 : 0;
	*/
	if ( ( ispunct ( *new_file ) && ispunct( * ( new_file + 1 ) ) ) || ( nul ) || ( bak ) || ( nu ) )
	{
		sprintf ( format_str, "Файл %s временный", new_file );
		pgfuse_syslog ( LOG_ERR, format_str );
		return 1;
	}
	else 
	{
		sprintf ( format_str, "Файл %s портальный", new_file );
		pgfuse_syslog ( LOG_ERR, format_str );
	}
	return 0;
}

int64_t psql_create_file ( PGconn* conn, thredis_t* thredis, cfg_t* cfg, const int64_t parent_id, const char* path, const char* new_file, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Создание файла %s имя %s", path, new_file );
	pgfuse_syslog ( LOG_ERR, format_str );
	int64_t id = 0;
	if ( name_file_is_temp ( new_file, cfg ) )
	{
		int64_t param1 = htobe64( parent_id );
		int64_t param2 = htobe64( meta->size );
		int param3 = htonl ( meta->mode );
		int param4 = htonl ( meta->uid );
		int param5 = htonl ( meta->gid );
		uint64_t param6 = convert_to_timestamp ( meta->ctime );
		uint64_t param7 = convert_to_timestamp ( meta->mtime );
		uint64_t param8 = convert_to_timestamp ( meta->atime );
		const char* values[9] = { ( const char * ) &param1, new_file, ( const char * ) &param2, ( const char * ) &param3, ( const char * ) &param4, ( const char * ) &param5, ( const char * ) &param6, ( const char * ) &param7, ( const char * ) &param8 };
		int lengths[9] = { sizeof ( param1 ), strlen ( new_file ), sizeof ( param2 ), sizeof ( param3 ), sizeof ( param4 ), sizeof ( param5 ), sizeof ( param6 ), sizeof ( param7 ), sizeof ( param8 ) };
		int binary[9] = { 1, 0, 1, 1, 1, 1, 1, 1, 1 };
		PGresult* res;

		res = PQexecParams ( conn, "INSERT INTO dir( parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES ($1::bigint, $2::varchar, $3::bigint, $4::integer, $5::integer, $6::integer, $7::timestamp, $8::timestamp, $9::timestamp )", 9, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf ( format_str, "Error in psql_create_file for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		if ( atoi ( PQcmdTuples ( res ) ) != 1 )
		{
			sprintf ( format_str, "Expecting one new row in psql_create_file, not %d!", atoi ( PQcmdTuples ( res ) ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
	}
	else
	{
		id = exist_name_dlfileentry ( conn, parent_id, new_file );
		if ( id == -ENOENT )
		{
			char str[URL_SIZE] = { '\0' };
			char* name = get_file_name ( new_file );
			int64_t groupid = get_groupid_from_parent_id ( conn, parent_id );
			uint64_t userid = get_userid_from_uid ( conn, thredis, meta->uid );
			sprintf ( str,"/add-file-entry/repository-id/%"PRIi64"/folder-id/%"PRIi64"/source-file-name/%s/user-id/%zu/size/%"PRIi64"/", groupid, ( groupid == parent_id ? ( int64_t ) 0 : parent_id ), name, userid, meta->size );
			id = htobe64( curl_http_get ( str, cfg ) );
			free ( name );
			psql_set_id_by_hash_to_redis ( thredis, path, id );
			/*
			if ( psql_write_meta ( conn, thredis, be64toh(id), path, meta ) < 0 )
			{
				sprintf ( format_str, "Error in path '%s': for id=%"PRIi64"", path, be64toh(id) );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -EIO;
			}
			*/
		}
		else
		{
			set_del_dlfileentry ( conn, thredis, id, 0 );
			redisReply* reply;
			char group[MD5_BUF] = { '\0' };
			sprintf ( group, "%"PRIi64"", parent_id );
			reply = thredis_command ( thredis, "DEL %s:dir", group );
			sprintf ( format_str, "DEL %s:dir : %lld ", group, reply->integer );
			pgfuse_syslog ( LOG_ERR, format_str );
			freeReplyObject ( reply );
			
			return id;
		}
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", parent_id );
	reply = thredis_command ( thredis, "DEL %s:dir", group );
	sprintf ( format_str, "DEL %s:dir : %lld ", group, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return be64toh(id);
}

int psql_read_buf ( PGconn* conn, thredis_t* thredis, const size_t block_size, const int64_t id, const char* path, char* buf, const off_t offset, const size_t len, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	PgDataInfo info;
	int64_t param1;
	int64_t param2;
	int64_t param3;
	const char* values[3] = { ( const char * ) &param1, ( const char * ) &param2, ( const char * ) &param3 };
	int lengths[3] = { sizeof ( param1 ), sizeof ( param2 ), sizeof ( param3 ) };
	int binary[3] = { 1, 1, 1 };
	PGresult* res;
	char* zero_block;
	int64_t block_no;
	char* iptr;
	char* data;
	size_t copied;
	int64_t db_block_no = 0;
	int idx;
	char* dst;
	PgMeta meta;
	size_t size;
	int64_t tmp;

	tmp = psql_read_meta ( conn, thredis, id, path, &meta );
	if ( tmp < 0 )
	{
		return tmp;
	}

	if ( meta.size == 0 )
	{
		return 0;
	}

	size = len;
	if ( offset + size > meta.size )
	{
		size = meta.size - offset;
	}

	info = compute_block_info ( block_size, offset, size );

	param1 = htobe64( id );
	param2 = htobe64( info.from_block );
	param3 = htobe64( info.to_block );

	res = PQexecParams ( conn, "SELECT block_no, data FROM data WHERE dir_id=$1::bigint AND block_no>=$2::bigint AND block_no<=$3::bigint ORDER BY block_no ASC", 3, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_read_buf for path '%s'", path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	zero_block = ( char * ) calloc ( 1, block_size );
	if ( zero_block == NULL )
	{
		PQclear ( res );
		return -ENOMEM;
	}

	dst = buf;
	copied = 0;
	for ( block_no = info.from_block, idx = 0; block_no <= info.to_block; block_no++ )
	{
		/* handle sparse files */
		if ( idx < PQntuples ( res ) )
		{
			iptr = PQgetvalue ( res, idx, 0 );
			db_block_no = ntohl ( * ( ( int64_t * ) iptr ) );

			if ( block_no < db_block_no )
			{
				data = zero_block;
			}
			else
			{
				data = PQgetvalue ( res, idx, 1 );
				idx++;
			}
		}
		else
		{
			data = zero_block;
		}

		/* first block */
		if ( block_no == info.from_block )
		{
			memcpy ( dst, data + info.from_offset, info.from_len - info.from_offset );

			dst += info.from_len;
			copied += info.from_len;

			/* last block */
		}
		else if ( block_no == info.to_block )
		{
			memcpy ( dst, data, info.to_len );
			copied += info.to_len;

			/* intermediary blocks, are copied completly */
		}
		else
		{
			memcpy ( dst, data, block_size );
			dst += block_size;
			copied += block_size;
		}

		if ( verbose )
		{
			sprintf ( format_str, "File '%s', reading block '%"PRIi64"', copied: '%zu', DB block: '%"PRIi64"'", path, block_no, copied, db_block_no );
			pgfuse_syslog ( LOG_DEBUG, format_str );
		}
	}

	PQclear ( res );

	free ( zero_block );

	if ( copied != size )
	{
		sprintf ( format_str, "File '%s', reading block '%"PRIi64"', copied '%zu' bytes but expecting '%zu'!", path, block_no, copied, size );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	return copied;
}

int psql_readdir ( PGconn* conn, thredis_t* thredis, const int64_t parent_id, void* buf, fuse_fill_dir_t filler )
{
	char format_str[LOG_LEN] = { '\0' };
	redisReply* reply;
	char* name;
	int count = 0;
	int i;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64":dir", parent_id );
	reply = thredis_command ( thredis, "LLEN %s", group );
	if ( reply->integer != 0 )
	{
		sprintf ( format_str, "LLEN-%s: %lld", group, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		count = reply->integer;
		freeReplyObject ( reply );
		reply = thredis_command ( thredis, "LRANGE %s %d %d", group, 0, count - 1 );
		sprintf ( format_str, "LRANGE-%s: %zu", group, reply->elements );
		pgfuse_syslog ( LOG_ERR, format_str );
		for ( i = 0; i < reply->elements; i++ )
		{
			name = reply->element[i]->str;
			if ( strcmp ( name, "/" ) == 0 ) continue;
			filler ( buf, name, NULL, 0 );
		}
		freeReplyObject ( reply );
		return 0;
	}
	else
	{
		freeReplyObject ( reply );
	}

	int64_t param1 = htobe64( parent_id );
	const char* values[1] = { ( char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };
	PGresult* res;
	int i_name;

	res = PQexecParams ( conn, "SELECT name FROM dir WHERE parent_id = $1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_readdir for dir with id '%20"PRIu64"': %s", parent_id, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	i_name = PQfnumber ( res, "name" );
	for ( i = 0; i < PQntuples ( res ); i++ )
	{
		name = PQgetvalue ( res, i, i_name );
		if ( strcmp ( name, "/" ) == 0 ) continue;
		filler ( buf, name, NULL, 0 );
		reply = thredis_command ( thredis, "RPUSH %s %s", group, name );
		sprintf ( format_str, "RPUSH-%s: %lld", group, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
	}

	PQclear ( res );

	return 0;
}

int psql_create_dir ( PGconn* conn, thredis_t* thredis, cfg_t* cfg, const int64_t parent_id, const char* path, const char* new_dir, PgMeta* meta )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Создание каталога %s", path );
	pgfuse_syslog ( LOG_ERR, format_str );

	int64_t id = exist_name_dlfileentry ( conn, parent_id, new_dir );
	if ( id == -ENOENT )
	{
		char str[URL_SIZE] = { '\0' };
		char* name = get_file_name ( new_dir );
		int64_t id = get_groupid_from_parent_id ( conn, parent_id );
		uint64_t userid = get_userid_from_uid ( conn, thredis, meta->uid );
		sprintf ( str, "/add-folder/repository-id/%"PRIi64"/parent-folder-id/%"PRIi64"/name/%s/user-id/%zu/", id, ( id == parent_id ? ( int64_t ) 0 : parent_id ), name, userid );
		id = htobe64( curl_http_get ( str, cfg ) );
		free ( name );
		psql_set_id_by_hash_to_redis ( thredis, path, id );
	}
	else
	{
		redisReply* reply;
		char group[MD5_BUF] = { '\0' };
		sprintf ( group, "%"PRIi64"", id );
		reply = thredis_command ( thredis, "DEL %s", group );
		sprintf ( format_str, "DEL: %lld ", reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );

		int64_t param1 = htobe64( id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "DELETE FROM dir WHERE id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf ( format_str, "Error in psql_delete_dir for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );

		char str[URL_SIZE] = { '\0' };
		sprintf ( str, "/delete-file-entry/file-entry-id/%"PRIi64"/", id );
		curl_http_get ( str, cfg );
		char* name = get_file_name ( new_dir );
		int64_t id = get_groupid_from_parent_id ( conn, parent_id );
		uint64_t userid = get_userid_from_uid ( conn, thredis, meta->uid );
		sprintf ( str, "/add-folder/repository-id/%"PRIi64"/parent-folder-id/%"PRIi64"/name/%s/user-id/%zu/", id, ( id == parent_id ? ( int64_t ) 0 : parent_id ), name, userid );
		id = htobe64( curl_http_get ( str, cfg ) );
		free ( name );
		psql_set_id_by_hash_to_redis ( thredis, path, id );
	}

	return 0;
}

int psql_delete_dir ( PGconn* conn, thredis_t* thredis, cfg_t* cfg, const int64_t id, const char* path )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf ( format_str, "Удаление каталога %s ID=%"PRIi64"", path, id );
	pgfuse_syslog ( LOG_ERR, format_str );

	int64_t param1 = htobe64( id );
	const char* values[1] = { ( char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };
	PGresult* res;
	char* iptr;
	int count;

	res = PQexecParams ( conn, "SELECT COUNT(*) FROM dir where parent_id=$1::bigint", 1, NULL, values, lengths, binary, 0 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf ( format_str, "Error in psql_delete_dir for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) != 1 )
	{
		sprintf ( format_str, "Expecting COUNT(*) to return 1 tupel, weird!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	iptr = PQgetvalue ( res, 0, 0 );
	count = atoi ( iptr );

	if ( count > 0 )
	{
		PQclear ( res );
		return -ENOTEMPTY;
	}

	PQclear ( res );

	res = PQexecParams ( conn, "DELETE FROM dir where id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf ( format_str, "Error in psql_delete_dir for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	if ( id < MAX_ID_PORTAL )
	{
		char str[URL_SIZE] = { '\0' };
		sprintf ( str, "/delete-folder/folder-id/%"PRIi64"/", id );
		curl_http_get ( str, cfg );
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "DEL %s %s:dir", group, group );
	sprintf ( format_str, "DEL %s %s:dir: %lld", group, group, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

int psql_delete_file ( PGconn* conn, const char* path_portal, const char* path_temp, thredis_t* thredis, cfg_t* cfg, const int64_t id, const char* path )
{
	char format_str[LOG_LEN] = { '\0' };
	if ( id < MAX_ID_PORTAL )
	{
		sprintf( format_str, "Удаление файла id=%"PRIi64" путь=%s", id, path );
		pgfuse_syslog ( LOG_ERR, format_str );
		int64_t param1 = htobe64( id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "DELETE FROM dir WHERE id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_delete_file for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}
		
		PQclear ( res );
		
		sprintf( format_str, "Удаление файла перед Curl id=%"PRIi64" путь=%s", id, path );
		pgfuse_syslog ( LOG_ERR, format_str );

		char str[URL_SIZE] = { '\0' };
		sprintf ( str, "/delete-file-entry/file-entry-id/%"PRIi64"/", id );
		curl_http_get ( str, cfg );
	}
	else
	{
		char path_r[URL_SIZE] = { '\0' };
		get_real_path_to_path ( conn, path_portal, path_temp, thredis, id, path_r );

		int dr = unlink ( path_r );
		if ( dr == 0 ) 
		{
			sprintf( format_str, "Удаление временного файла id=%"PRIi64" путь=%s - УСПЕШНО", id, path_r );
			pgfuse_syslog ( LOG_ERR, format_str );
		}
		else 
		{
			sprintf( format_str, "Удаление временного файла id=%"PRIi64" путь=%s - ERROR (%d)", id, path_r, dr );
			pgfuse_syslog ( LOG_ERR, format_str );
		}

		int64_t param1 = htobe64( id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "DELETE FROM dir WHERE id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_delete_dir for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "DEL %s", group );
	sprintf( format_str, "DEL %s : %lld", group, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

int psql_get_xattr ( PGconn* conn, thredis_t* thredis, const char* path, const char* name, char* value, size_t size )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = psql_path_to_id ( conn, thredis, path );
	
	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HGET %s %s", group, name );
	if ( reply->type != REDIS_REPLY_NIL )
	{
		sprintf( format_str, "xattr-HGET-%s: %lld %d", name, reply->integer, reply->len );
		pgfuse_syslog ( LOG_ERR, format_str );
		size_t len = reply->len;
		if ( size > len )
		{
			memcpy ( value, reply->str, len );
			size = len;
		}
		else size = len;
		freeReplyObject ( reply );
		return ( int ) size;
	}
	else
	{
		freeReplyObject ( reply );
	}

	int64_t param1 = htobe64( id );
	const char* values[2] = { ( char * ) &param1, name };
	int lengths[2] = { sizeof ( param1 ), strlen ( name ) };
	int binary[2] = { 1, 0 };
	char* val;
	PGresult* res;

	res = PQexecParams ( conn, "SELECT val FROM xattr where dir_id=$1::bigint and name=$2::varchar", 2, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_get_xattr for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) != 1 )
	{
		sprintf( format_str, "Expecting SELECT to return 1 tupel, weird! '%s'", name );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -ENODATA;
	}

	val = PQgetvalue ( res, 0, 0 );
	size_t len = PQgetlength ( res, 0, 0 );

	if ( size > len )
	{
		memcpy ( value, val, len );
		size = len;
		reply = thredis_command ( thredis, "HSET %s %s %b", group, name, value, size );
		sprintf( format_str, "xattr-HSET: %lld ", reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
	}
	else size = len;

	PQclear ( res );

	return ( int ) size;
}
int psql_copy_xattr_from_to(PGconn* conn, const int64_t from_id, const int64_t to_id)
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t param1 = htobe64( from_id );
	int64_t param2 = htobe64( to_id );
	const char* values[2] = { ( const char * ) &param1, ( const char * ) &param2 };
	int lengths[2] = { sizeof ( param1 ), sizeof ( param2 ) };
	int binary[2] = { 1, 1 };
	PGresult* res;

	res = PQexecParams ( conn, "SELECT copy_xattr_from_to( $1::bigint, $2::bigint )", 2, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Ошибка при копировании XATTR from_id=%"PRIi64" to_id=%"PRIi64" %s", from_id, to_id, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	sprintf( format_str, "Копировании безопастности XATTR from_id=%"PRIi64" to_id=%"PRIi64" выполнено", from_id, to_id );
	pgfuse_syslog ( LOG_ERR, format_str );

	PQclear ( res );

	return 0;
}
int psql_set_xattr_replace ( PGconn* conn, thredis_t* thredis, const char* path, const char* name, const char* value, size_t size )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = psql_path_to_id ( conn, thredis, path );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HSET %s %s %b", group, name, value, size );
	sprintf( format_str, "xattr-HSET-%s: %lld ", name, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	int64_t param1 = htobe64( id );
	const char* values[3] = { ( char * ) &param1, name, value };
	int lengths[3] = { sizeof ( param1 ), strlen ( name ), size };
	int binary[3] = { 1, 0, 1 };
	PGresult* res;

	res = PQexecParams ( conn, "UPDATE xattr SET val=$3::bytea where dir_id=$1::bigint and name=$2::varchar", 3, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Error in psql_set_xattr_replace for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

int psql_set_xattr_create ( PGconn* conn, thredis_t* thredis, const char* path, const char* name, const char* value, size_t size )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = psql_path_to_id ( conn, thredis, path );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );

	reply = thredis_command ( thredis, "HSET %s %s %b", group, name, value, size );
	sprintf( format_str, "xattr-HSET-%s: %lld ", name, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	int64_t param1 = htobe64( id );
	const char* values[3] = { ( char * ) &param1, name, value };
	int lengths[3] = { sizeof ( param1 ), strlen ( name ), size };
	int binary[3] = { 1, 0, 1 };
	const char* values2[2] = { ( char * ) &param1, name };
	int lengths2[2] = { sizeof ( param1 ), strlen ( name ) };
	int binary2[2] = { 1, 0 };
	PGresult* res;

	res = PQexecParams ( conn, "SELECT id FROM xattr WHERE dir_id=$1::bigint and name=$2::varchar", 2, NULL, values2, lengths2, binary2, 1 );
	if ( PQntuples ( res ) != 0 )
	{
		PQclear ( res );

		res = PQexecParams ( conn, "UPDATE xattr SET val=$3::bytea where dir_id=$1::bigint and name=$2::varchar", 3, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in UPDATE psql_set_xattr_create for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}
	}
	else
	{
		PQclear ( res );

		res = PQexecParams ( conn, "INSERT INTO xattr( dir_id, name, val) VALUES ($1::bigint, $2::varchar, $3::bytea)", 3, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in INSERT psql_set_xattr_create for path '%s': %s", path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}
	}

	PQclear ( res );

	return 0;
}

int psql_list_xattr ( PGconn* conn, thredis_t* thredis, const char* path, char* list, size_t size )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t param1 = htobe64( psql_path_to_id ( conn, thredis, path ) );
	const char* values[1] = { ( char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };
	PGresult* res;
	size_t len;
	char* val;
	int i;

	res = PQexecParams ( conn, "SELECT name FROM xattr where dir_id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_list_xattr for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	int n = PQntuples ( res );
	len = n;
	for ( i = 0; i < n; i++ )
	{
		len += PQgetlength ( res, i, 0 );
	}
	if ( size == 0 )
	{
		PQclear ( res );
		return len;
	}
	if ( size < len )
	{
		PQclear ( res );
		return -ERANGE;
	}
	len = 0;
	for ( i = 0; i < n; i++ )
	{
		val = PQgetvalue ( res, i, 0 );
		strcpy ( list + len, val );
		len += strlen ( val );
		list[len] = '\0';
		len++;
	}
	PQclear ( res );

	return ( int ) len;
}

int psql_delete_xattr ( PGconn* conn, thredis_t* thredis, const char* path, const char* name )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t id = psql_path_to_id ( conn, thredis, path );

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", id );
	reply = thredis_command ( thredis, "HDEL %s %s", group, name );
	sprintf( format_str, "xattr-HDEL-%s: %lld ", name, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	int64_t param1 = htobe64( id );
	const char* values[2] = { ( char * ) &param1, name };
	int lengths[2] = { sizeof ( param1 ), strlen ( name ) };
	int binary[2] = { 1, 0 };
	PGresult* res;

	res = PQexecParams ( conn, "DELETE FROM xattr where dir_id=$1::bigint and name=$2::varchar", 2, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Error in psql_delete_xattr for path '%s': %s", path, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

static int psql_write_block ( PGconn* conn, const size_t block_size, const int64_t id, const char* path, const char* buf, const int64_t block_no, const off_t offset, const size_t len, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	int64_t param1 = htobe64( id );
	int64_t param2 = htobe64( block_no );
	const char* values[3] = { ( const char * ) &param1, ( const char * ) &param2, buf };
	int lengths[3] = { sizeof ( param1 ), sizeof ( param2 ), len };
	int binary[3] = { 1, 1, 1 };
	PGresult* res;
	char sql[256] = { '\0' };

	/* could actually be an assertion, as this can never happen */
	if ( offset + len > block_size )
	{
		sprintf( format_str, "Got a too big block write for file '%s', block '%20"PRIi64"': %20jd + %20zu > %zu!", path, block_no, offset, len, block_size );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	update_again:

	/* write a complete block, old data in the database doesn't bother us */
	if ( offset == 0 && len == block_size )
	{
		strcpy ( sql, "UPDATE data set data = $3::bytea WHERE dir_id=$1::bigint AND block_no=$2::bigint" );

		/* keep data on the right */
	}
	else if ( offset == 0 && len < block_size )
	{
		sprintf ( sql, "UPDATE data set data = $3::bytea || substring( data from %zu for %zu ) WHERE dir_id=$1::bigint AND block_no=$2::bigint", len + 1, block_size - len );

		/* keep data on the left */
	}
	else if ( offset > 0 && offset + len == block_size )
	{
		sprintf ( sql, "UPDATE data set data = substring( data from %d for %jd ) || $3::bytea WHERE dir_id=$1::bigint AND block_no=$2::bigint", 1, offset );

		/* small in the middle write, keep data on both sides */
	}
	else if ( offset > 0 && offset + len < block_size )
	{
		sprintf ( sql, "UPDATE data set data = substring( data from %d for %jd ) || $3::bytea || substring( data from %jd for %jd ) WHERE dir_id=$1::bigint AND block_no=$2::bigint", 1, offset, offset + len + 1, block_size - ( offset + len ) );

		/* we should never get here */
	}
	else
	{
		sprintf( format_str, "Unhandled write case for file '%s' in block '%"PRIi64"': offset: %jd, len: %zu, blocksize: %zu", path, block_no, offset, len, block_size );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	if ( verbose )
	{
		sprintf( format_str, "%s, block: %"PRIi64", offset: %jd, len: %zu => %s\n", path, block_no, offset, len, sql );
		pgfuse_syslog ( LOG_DEBUG, format_str );
	}

	res = PQexecParams ( conn, sql, 3, NULL, values, lengths, binary, 1 );

	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Error in psql_write_block(%"PRIi64",%jd,%zu) for file '%s' (%s): %s", block_no, offset, len, path, sql, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	/* ok, one block updated */
	if ( atoi ( PQcmdTuples ( res ) ) == 1 )
	{
		PQclear ( res );
		return len;
	}

	/* funny problems */
	if ( atoi ( PQcmdTuples ( res ) ) != 0 )
	{
		sprintf( format_str, "Unable to update block '%"PRIi64"' of file '%s'! Data consistency problems!", block_no, path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	/* the block didn't exist, so create one */
	sprintf ( sql, "INSERT INTO data( dir_id, block_no, data ) VALUES ( $1::bigint, $2::bigint, repeat(E'\\\\000',%zu)::bytea )", block_size );
	res = PQexecParams ( conn, sql, 2, NULL, values, lengths, binary, 1 );

	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Error in psql_write_block(%"PRIi64",%jd,%zu) for file '%s' allocating new block '%"PRIi64"': %s", block_no, offset, len, path, block_no, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( atoi ( PQcmdTuples ( res ) ) != 1 )
	{
		sprintf( format_str, "Unable to add new block '%"PRIi64"' of file '%s'! Data consistency problems!", block_no, path );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	PQclear ( res );

	goto update_again;
}

int psql_write_buf ( PGconn* conn, const size_t block_size, const int64_t id, const char* path, const char* buf, const off_t offset, const size_t len, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	PgDataInfo info;
	int res;
	int64_t block_no;

	if ( len == 0 )
	{
		return 0;
	}

	info = compute_block_info ( block_size, offset, len );

	/* first (partial) block */
	res = psql_write_block ( conn, block_size, id, path, buf, info.from_block, info.from_offset, info.from_len, verbose );
	if ( res < 0 )
	{
		return res;
	}
	if ( res != info.from_len )
	{
		sprintf( format_str, "Partial write in file '%s' in first block '%"PRIi64"' (%u instead of %zu octets)", path, info.from_block, res, info.from_len );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	/* special case of one block */
	if ( info.from_block == info.to_block )
	{
		return res;
	}

	buf += info.from_len;

	/* all full blocks */
	for ( block_no = info.from_block + 1; block_no < info.to_block; block_no++ )
	{
		res = psql_write_block ( conn, block_size, id, path, buf, block_no, 0, block_size, verbose );
		if ( res < 0 )
		{
			return res;
		}
		if ( res != block_size )
		{
			sprintf( format_str, "Partial write in file '%s' in block '%"PRIi64"' (%u instead of %zu octets)", path, block_no, res, block_size );
			pgfuse_syslog ( LOG_ERR, format_str );
			return -EIO;
		}
		buf += block_size;
	}

	/* last partial block */
	res = psql_write_block ( conn, block_size, id, path, buf, info.to_block, 0, info.to_len, verbose );
	if ( res < 0 )
	{
		return res;
	}
	if ( res != info.to_len )
	{
		sprintf( format_str, "Partial write in file '%s' in last block '%"PRIi64"' (%u instead of %zu octets)", path, block_no, res, info.to_len );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	return len;
}

int psql_begin ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;

	res = PQexec ( conn, "BEGIN" );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Begin of transaction failed!!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

int psql_commit ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;

	res = PQexec ( conn, "COMMIT" );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Commit of transaction failed!!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

int psql_rollback ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;

	res = PQexec ( conn, "ROLLBACK" );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Rollback of transaction failed!!" );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	PQclear ( res );

	return 0;
}

int psql_rename_to_existing_file ( PGconn* conn, const char* path_portal, const char* path_temp, thredis_t* thredis, cfg_t* cfg, const int64_t from_id, const int64_t to_id, const char* from_path, const char* to_path )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf( format_str, "Переименование существующего файла из ID=%"PRIi64" в ID=%"PRIi64"", from_id, to_id );
	pgfuse_syslog ( LOG_ERR, format_str );

	PgMeta meta;
	PgMeta from_meta;

	if ( ( from_id > MAX_ID_PORTAL ) && ( to_id > MAX_ID_PORTAL ) )
	{
		int64_t param1 = htobe64( to_id );
		int64_t param2 = htobe64( from_id );
		const char* values[2] = { ( char * ) &param1, ( char * ) &param2 };
		int lengths[2] = { sizeof ( param1 ), sizeof ( param2 ) };
		int binary[2] = { 1, 1 };
		PGresult* res;

		res = PQexecParams ( conn, "DELETE FROM xattr WHERE dir_id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_rename_to_existing_file to remove data of the destination file '%s': %s", to_path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );

		res = PQexecParams ( conn, "UPDATE xattr SET dir_id=$1::bigint WHERE dir_id=$2::bigint", 2, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_rename_to_existing_file to move data from '%s' to '%s': %s", from_path, to_path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );

		copy_mmap ( conn, path_portal, path_temp, thredis, from_id, to_id );

		PgMeta meta;
		psql_read_meta ( conn, thredis, from_id, from_path, &meta );
		psql_write_meta ( conn, thredis, to_id, to_path, &meta );

		values[0] = ( char * ) &param2;

		res = PQexecParams ( conn, "DELETE FROM dir where id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_renamc_existing_file when deleting dir entry for path '%s': %s", from_path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );

		redisReply* reply;
		char group[MD5_BUF] = { '\0' };
		char group1[MD5_BUF] = { '\0' };
		sprintf ( group1, "%"PRIi64"", to_id );
		sprintf ( group, "%"PRIi64"", from_id );
		reply = thredis_command ( thredis, "DEL %s %s", group, group1 );
		sprintf( format_str, "DEL %s %s : %lld ", group, group1, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );

		return 0;
	}

	if ( ( from_id < MAX_ID_PORTAL ) && ( to_id < MAX_ID_PORTAL ) )
	{
		int id = psql_read_meta ( conn, thredis, to_id, to_path, &meta );
		if ( id < 0 )
		{
		return id;
		}

		int64_t param1 = htobe64( to_id );
		const char* values[1] = { ( char * ) &param1 };
		int lengths[1] = { sizeof ( param1 ) };
		int binary[1] = { 1 };
		PGresult* res;

		res = PQexecParams ( conn, "DELETE FROM xattr where dir_id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_renamc_existing_file when deleting dir entry for path '%s': %s", from_path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
		
		char str[URL_SIZE] = { '\0' };
		sprintf ( str, "/delete-file-entry/file-entry-id/%"PRIi64"/", to_id );
		curl_http_get ( str, cfg );
		sprintf ( str, "/move-file-entry/file-entry-id/%"PRIi64"/new-folder-id/%"PRIi64"/", from_id, meta.parent_id );
		curl_http_get ( str, cfg );

		redisReply* reply;
		char group[MD5_BUF] = { '\0' };
		sprintf ( group, "%"PRIi64"", to_id );
		char group1[MD5_BUF] = { '\0' };
		sprintf ( group1, "%"PRIi64"", from_id );
		reply = thredis_command ( thredis, "DEL %s %s", group, group1 );
		sprintf( format_str, "DEL %s %s : %lld ", group, group1, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );

		return 0;
	}

	copy_mmap ( conn, path_portal, path_temp, thredis, from_id, to_id );

	int id = psql_read_meta ( conn, thredis, to_id, to_path, &meta );
	if ( id < 0 )
	{
		return id;
	}

	id = psql_read_meta ( conn, thredis, from_id, from_path, &from_meta );
	if ( id < 0 )
	{
		return id;
	}

	meta.mode = from_meta.mode;
	meta.ctime = from_meta.ctime;
	meta.mtime = from_meta.mtime;
	meta.atime = from_meta.atime;
	meta.size = from_meta.size;
	meta.uid = from_meta.uid;
	meta.gid = from_meta.gid;

	psql_write_meta ( conn, thredis, to_id, to_path, &meta );

	if ( from_id > MAX_ID_PORTAL )
	{
		PGresult* res;
		int64_t param = htobe64( from_id );
		const char* values[1] = { ( char * ) &param };
		int lengths[1] = { sizeof ( param ) };
		int binary[1] = { 1 };

		res = PQexecParams ( conn, "DELETE FROM dir where id=$1::bigint", 1, NULL, values, lengths, binary, 1 );
		if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
		{
			sprintf( format_str, "Error in psql_renamc_existing_file when deleting dir entry for path %s : %s", from_path, PQerrorMessage ( conn ) );
			pgfuse_syslog ( LOG_ERR, format_str );
			PQclear ( res );
			return -EIO;
		}

		PQclear ( res );
	}
	else
	{
		set_del_dlfileentry ( conn, thredis, from_id, 1 );
	}

	redisReply* reply;
	char group[MD5_BUF] = { '\0' };
	sprintf ( group, "%"PRIi64"", from_id );
	char group1[MD5_BUF] = { '\0' };
	sprintf ( group1, "%"PRIi64"", to_id );
	reply = thredis_command ( thredis, "DEL %s %s", group, group1 );
	sprintf( format_str, "DEL %s %s : %lld ", group, group1, reply->integer );
	pgfuse_syslog ( LOG_ERR, format_str );
	freeReplyObject ( reply );

	return 0;
}

int psql_rename ( PGconn* conn, const char* path_portal, const char* path_temp, cfg_t* cfg, thredis_t* thredis, const int64_t from_id, const int64_t from_parent_id, const int64_t to_parent_id, const char* rename_to, const char* from, const char* to )
{
	char format_str[LOG_LEN] = { '\0' };
	sprintf( format_str, "Переименование файла id=%"PRIi64" из %s в %s to_parent_id=%"PRIi64" from_parent_id=%"PRIi64"", from_id, from, to, to_parent_id, from_parent_id );
	pgfuse_syslog ( LOG_ERR, format_str );

	PgMeta from_id_meta;
	int64_t id;

	id = psql_read_meta_from_path ( conn, thredis, from, &from_id_meta );
	if ( id < 0 )
	{
		return id;
	}

	if ( S_ISDIR( from_id_meta.mode ) )
	{
		char str[URL_SIZE] = { '\0' };
		char* name = get_file_name ( rename_to ); //rename-folder/folder-id/24501
		sprintf ( str, "/rename-folder/folder-id/%"PRIi64"/new-name/%s/", from_id, name );
		curl_http_get ( str, cfg );
		free ( name );

		if ( from_parent_id != to_parent_id )
		{
			sprintf ( str, "/move-folder/folder-id/%"PRIi64"/parent-folder-id/%"PRIi64"/", from_id, to_parent_id );
			curl_http_get ( str, cfg );
		}

		redisReply* reply;
		char group[MD5_BUF] = { '\0' };
		sprintf ( group, "%"PRIi64"", from_id );
		reply = thredis_command ( thredis, "DEL %s", group );
		sprintf( format_str, "DEL %s : %lld ", group, reply->integer );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
	}
	else
	{
		if ( ( from_id > MAX_ID_PORTAL ) && ( name_file_is_temp ( rename_to, cfg ) == 1 ) )
		{
			PgMeta from_parent_meta;
			PgMeta to_parent_meta;
			int64_t id;
			int64_t param1 = htobe64( to_parent_id );
			int64_t param3 = htobe64( from_id );
			const char* values[3] = { ( const char * ) &param1, rename_to, ( const char * ) &param3 };
			int lengths[3] = { sizeof ( param1 ), strlen ( rename_to ), sizeof ( param3 ) };
			int binary[3] = { 1, 0, 1 };
			PGresult* res;

			id = psql_read_meta ( conn, thredis, from_parent_id, from, &from_parent_meta );
			if ( id < 0 )
			{
				return id;
			}

			if ( !S_ISDIR( from_parent_meta.mode ) )
			{
				sprintf( format_str, "Expecting parent with id '%"PRIi64"' of '%s' (id '%"PRIi64"') to be a directory in psql_rename, but mode is '%o'!", from_parent_id, from, from_id, from_parent_meta.mode );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -EIO;
			}

			id = psql_read_meta ( conn, thredis, to_parent_id, to, &to_parent_meta );
			if ( id < 0 )
			{
				return id;
			}

			if ( !S_ISDIR( to_parent_meta.mode ) )
			{
				sprintf( format_str, "Expecting parent with id '%"PRIi64"' of '%s' to be a directory in psql_rename, but mode is '%o'!", to_parent_id, to, to_parent_meta.mode );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -EIO;
			}

			res = PQexecParams ( conn, "UPDATE dir SET parent_id=$1::bigint, name=$2::varchar WHERE id=$3::bigint", 3, NULL, values, lengths, binary, 1 );
			if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
			{
				sprintf( format_str, "Error in psql_rename for '%s' to '%s': %s", from, to, PQerrorMessage ( conn ) );
				pgfuse_syslog ( LOG_ERR, format_str );
				PQclear ( res );
				return -EIO;
			}

			if ( atoi ( PQcmdTuples ( res ) ) != 1 )
			{
				sprintf( format_str, "Expecting one new row in psql_rename from '%s' to '%s', not %d!", from, to, atoi ( PQcmdTuples ( res ) ) );
				pgfuse_syslog ( LOG_ERR, format_str );
				PQclear ( res );
				return -EIO;
			}

			PQclear ( res );

			redisReply* reply;
			char group[MD5_BUF] = { '\0' };
			sprintf ( group, "%"PRIi64"", from_id );
			reply = thredis_command ( thredis, "DEL %s", group );
			sprintf( format_str, "DEL %s : %lld ", group, reply->integer );
			pgfuse_syslog ( LOG_ERR, format_str );
			freeReplyObject ( reply );

			return 0;
		}

		if ( ( from_id < MAX_ID_PORTAL ) && ( name_file_is_temp ( rename_to, cfg ) == 0 ) )
		{
			PgMeta from_parent_meta;
			PgMeta to_parent_meta;

			id = psql_read_meta ( conn, thredis, from_parent_id, from, &from_parent_meta );
			if ( id < 0 )
			{
				return id;
			}

			if ( !S_ISDIR( from_parent_meta.mode ) )
			{
				sprintf( format_str, "Expecting parent with id '%"PRIi64"' of '%s' (id '%"PRIi64"') to be a directory in psql_rename, but mode is '%o'!", from_parent_id, from, from_id, from_parent_meta.mode );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -EIO;
			}

			id = psql_read_meta ( conn, thredis, to_parent_id, to, &to_parent_meta );
			if ( id < 0 )
			{
				return id;
			}

			if ( !S_ISDIR( to_parent_meta.mode ) )
			{
				sprintf( format_str, "Expecting parent with id '%"PRIi64"' of '%s' to be a directory in psql_rename, but mode is '%o'!", to_parent_id, to, to_parent_meta.mode );
				pgfuse_syslog ( LOG_ERR, format_str );
				return -EIO;
			}

			if ( from_parent_id != to_parent_id )
			{
				char str[URL_SIZE] = { '\0' };
				sprintf ( str, "/move-file-entry/file-entry-id/%"PRIi64"/new-folder-id/%"PRIi64"/", from_id, to_parent_id );
				curl_http_get ( str, cfg );
			}

			char str[URL_SIZE] = { '\0' };
			char* name = get_file_name ( rename_to );
			sprintf ( str, "/rename-file/file-entry-id/%"PRIi64"/new-name/%s/", from_id, name );
			curl_http_get ( str, cfg );
			free ( name );

			return 0;
		}

		int64_t id = 0;
		if ( name_file_is_temp ( rename_to, cfg ) == 0 )
		{
			id = exist_name_dlfileentry ( conn, to_parent_id, rename_to );
			if ( id == -ENOENT )
			{
				int res = psql_create_file ( conn, thredis, cfg, to_parent_id, to, rename_to, &from_id_meta );
				if ( res < 0 ) return res;
			}
			else
			{
				set_del_dlfileentry ( conn, thredis, id, 0 );
				psql_write_meta ( conn, thredis, id, to, &from_id_meta );
			}
		}
		else
		{
			int res = psql_create_file ( conn, thredis, cfg, to_parent_id, to, rename_to, &from_id_meta );
			if ( res < 0 ) return res;
			//psql_copy_xattr_from_to( conn, from_id, to_id );
			//if ( res < 0 ) return res;
		}

		int64_t to_id = psql_path_to_id ( conn, thredis, to );
		copy_mmap ( conn, path_portal, path_temp, thredis, from_id, to_id );
		if ( id == -ENOENT || id == 0 )
		{
		psql_copy_xattr_from_to( conn, from_id, to_id );
		}

		if ( from_id < MAX_ID_PORTAL )
		{
			set_del_dlfileentry ( conn, thredis, from_id, 1 );
			redisReply* reply;
			char group[MD5_BUF] = { '\0' };
			sprintf ( group, "%"PRIi64"", from_id );
			reply = thredis_command ( thredis, "DEL %s", group );
			sprintf( format_str, "DEL %s : %lld ", group, reply->integer );
			pgfuse_syslog ( LOG_ERR, format_str );
			freeReplyObject ( reply );
		}
		else
		{
			if ( to_id < MAX_ID_PORTAL )
			{
				uid_t uid = from_id_meta.uid; //from_id_meta.uid;
				
				redisReply* reply;
				char group[MD5_BUF] = { '\0' };
				sprintf ( group, "%"PRIi64"", from_id );
				reply = thredis_command ( thredis, "HGET %s %s", group, "uid" );
				if ( reply->type != REDIS_REPLY_NIL )
				{
					sprintf( format_str, "UID-HGET: %lld %d", reply->integer, reply->len );
					pgfuse_syslog ( LOG_ERR, format_str );
					uid_t* val = ( uid_t * ) calloc ( 1, sizeof(uid_t) );
					if ( val )
					{
						memcpy ( val, reply->str, reply->len );
						uid = *val;
						free ( val );
					}
				}
				freeReplyObject ( reply );

				if ( uid >= 0 )
				{
					uint64_t userid = get_userid_from_uid ( conn, thredis, uid );
					char str[URL_SIZE] = { '\0' };
					sprintf ( str, "/update-file-last-updated/file-entry-id/%"PRIi64"/user-id/%"PRIi64"/size/%zu/", to_id, userid, from_id_meta.size );
					curl_http_get ( str, cfg );
				}
				psql_delete_file ( conn, path_portal, path_temp, thredis, cfg, from_id, from );
			}
		}
	}
	return 0;
}

int64_t exist_name_dlfileentry ( PGconn* conn, const int64_t parent_id, const char* name )
{
	char format_str[LOG_LEN] = { '\0' };
	int idx;
	int64_t del;
	char* data;
	int64_t param1 = htobe64( parent_id );
	const char* values[2] = { ( const char * ) &param1, name };
	int lengths[2] = { sizeof ( param1 ), strlen ( name ) };
	int binary[2] = { 1, 0 };
	PGresult* res;

	res = PQexecParams ( conn, "SELECT fileentryid FROM dlfileentry WHERE folderid = $1::bigint AND title = $2::varchar AND del = 1", 2, NULL, values, lengths, binary, 1 );

	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in exist_name_dlfileentry parent_id=%"PRIi64" for name=%s %s", parent_id, name, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );
		sprintf( format_str, "Файл не скрытый ID=%"PRIi64" в каталоге ID=%"PRIi64" его нет с именем %s", ( int64_t ) -ENOENT, parent_id, name );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -ENOENT;
	}

	if ( PQntuples ( res ) > 1 )
	{
		sprintf( format_str, "Expecting exactly one inode for name '%s' in exist_name_dlfileentry, data inconsistent!", name );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	idx = PQfnumber ( res, "fileentryid" );
	data = PQgetvalue ( res, 0, idx );
	del = be64toh( * ( ( int64_t * ) data ) );

	PQclear ( res );

	sprintf( format_str, "Файл является скрытым ID=%"PRIi64" в каталоге ID=%"PRIi64" под именем %s", del, parent_id, name );
	pgfuse_syslog ( LOG_ERR, format_str );

	return del;
}

void set_del_dlfileentry ( PGconn* conn, thredis_t* thredis, const int64_t from_id, const int del )
{
	char format_str[LOG_LEN] = { '\0' };
	int param1 = htonl ( del );
	int64_t param2 = htobe64( from_id );
	const char* values[2] = { ( const char * ) &param1, ( const char * ) &param2 };
	int lengths[2] = { sizeof ( param1 ), sizeof ( param2 ) };
	int binary[2] = { 1, 1 };
	PGresult* res;

	res = PQexecParams ( conn, "UPDATE dlfileentry SET del=$1::integer WHERE fileentryid=$2::bigint", 2, NULL, values, lengths, binary, 1 );
	if ( PQresultStatus ( res ) != PGRES_COMMAND_OK )
	{
		sprintf( format_str, "Error in set_del_dlfileentry ID=%"PRIi64" del=%d %s", from_id, del, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
	}

	PQclear ( res );

	sprintf( format_str, "Установка признак удалённости файла ID=%"PRIi64" в %d", from_id, del );
	pgfuse_syslog ( LOG_ERR, format_str );

	if ( del )
	{
		redisReply* reply;
		char group[MD5_BUF] = { '\0' };
		sprintf ( group, "%"PRIi64"", from_id );
		reply = thredis_command ( thredis, "DEL %s", group );
		sprintf( format_str, "DEL %lld ID=%"PRIi64"", reply->integer, from_id );
		pgfuse_syslog ( LOG_ERR, format_str );
		freeReplyObject ( reply );
	}
}

size_t psql_get_block_size ( PGconn* conn, const size_t block_size )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;
	size_t db_block_size;

	res = PQexec ( conn, "SELECT distinct octet_length(data) FROM data" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_get_block_size: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	/* empty, this is ok, any blocksize acceptable after initialization */
	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );
		return block_size;
	}

	data = PQgetvalue ( res, 0, 0 );
	db_block_size = atoi ( data );

	PQclear ( res );

	return db_block_size;
}

int64_t psql_get_fs_blocks_used ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;
	int64_t used;

	/* we calculate the number of blocks occuppied by all data entries
	 * plus all "indoes" (in our case entries in dir),
	 * more like a filesystem would do it. Returning blocks as this is
	 * harder to overflow a size_t (in case it's MD5_BUF-bit, modern
	 * systems shouldn't care). It's not so fast though, otherwise we
	 * must consider a 'stats' table which is periodically updated
	 * (not constantly in order to avoid a hot-spot in the database!)
	 */
	res = PQexec ( conn, "SELECT (SELECT COUNT(*) FROM data) + (SELECT COUNT(*) FROM dir)" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_get_fs_blocks_used: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	data = PQgetvalue ( res, 0, 0 );
	used = atoi ( data );

	PQclear ( res );

	return used;
}

static int get_default_tablespace ( PGconn* conn, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;
	int oid;

	res = PQexec ( conn, "select dattablespace::int4 from pg_database where datname=current_database( )" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in get_default_tablespace: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	data = PQgetvalue ( res, 0, 0 );
	oid = atoi ( data );

	if ( verbose )
	{
		sprintf( format_str, "Free blocks calculation, seen default tablespace is OID %d", oid );
		pgfuse_syslog ( LOG_DEBUG, format_str );
	}

	PQclear ( res );

	return oid;
}

static char* get_data_directory ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;

	/* in the questionable case we have super user rights we
	 * can ask the server for the default path */
	res = PQexec ( conn, "select setting from pg_settings where name = 'data_directory'" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error getting data_directory: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return NULL;
	}

	/* No permissions results in an empty result set */
	if ( PQntuples ( res ) == 0 )
	{
		PQclear ( res );

		/* No location, tablespace resides in PGDATA,
		 * usually it lies in /var/lib/postgres,
		 * /var/lib/postgresql,
		 * /var/lib/pgsql or  /var/lib/postgresql/9.1/main
		 */
#ifdef __linux__
		data = strdup ( "/var/lib/postgres" );
#else
		/* TODO, but usually BSD stores it on /usr/local, MacOs
		 * would be different, but there a lot else is also different..
		 */
		data = strdup ( "/usr/local" );
#endif
		return data;
	}

	data = strdup ( PQgetvalue ( res, 0, 0 ) );

	PQclear ( res );

	return data;
}

static char* get_tablespace_location ( PGconn* conn, const int oid, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	int param1 = htonl ( oid );
	const char* values[1] = { ( const char * ) &param1 };
	int lengths[1] = { sizeof ( param1 ) };
	int binary[1] = { 1 };
	char* data;
	int version;

	version = PQserverVersion ( conn );
	if ( version >= 90200 )
	{
		res = PQexecParams ( conn, "select pg_tablespace_location($1)", 1, NULL, values, lengths, binary, 1 );
	}
	else
	{
		res = PQexecParams ( conn, "select spclocation from pg_tablespace where oid = $1", 1, NULL, values, lengths, binary, 1 );
	}

	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in get_tablespace_location for OID %d: %s", oid, PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return NULL;
	}

	data = strdup ( PQgetvalue ( res, 0, 0 ) );

	PQclear ( res );

	/* no direct information in the catalog about the table space location, try
	 * other means */
	if ( strcmp ( data, "" ) == 0 )
	{
		data = get_data_directory ( conn );
	}

	return data;
}

int psql_get_tablespace_locations ( PGconn* conn, char** location, size_t* nof_oids, int verbose )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;
	int i;
	int oid[MAX_TABLESPACE_OIDS];

	if ( *nof_oids > MAX_TABLESPACE_OIDS )
	{
		sprintf( format_str, "Error in psql_get_fs_blocks_free, called with location array bigger than MAX_TABLESPACE_OIDS" );
		pgfuse_syslog ( LOG_ERR, format_str );
		return -EIO;
	}

	/* Get a list of oids containing the tablespaces of PgFuse tables and indexes */
	res = PQexec ( conn, "select distinct reltablespace::int4 FROM pg_class WHERE relname in ( 'dir', 'data', 'data_dir_id_idx', 'data_block_no_idx', 'dir_parent_id_idx' )" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_get_fs_blocks_free: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	/* weird, no tablespaces? There is something wrong here, bail out */
	if ( PQntuples ( res ) == 0 )
	{
		sprintf( format_str, "Error in psql_get_fs_blocks_free, no tablespace OIDs found" );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	*nof_oids = PQntuples ( res );
	if ( *nof_oids > MAX_TABLESPACE_OIDS )
	{
		sprintf( format_str, "Error in psql_get_fs_blocks_free, too many tablespace OIDs found, increase MAX_TABLESPACE_OIDS" );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	for ( i = 0; i < *nof_oids; i++ )
	{
		data = PQgetvalue ( res, i, 0 );
		oid[i] = atoi ( data );
	}

	PQclear ( res );

	/* we have a OID = 0 in the list, so have a look at the default
	 * tablespace of the current database and replace the value
	 */
	for ( i = 0; i < *nof_oids; i++ )
	{
		if ( oid[i] == 0 )
		{
			int res = get_default_tablespace ( conn, verbose );
			if ( res < 0 )
			{
				return res;
			}
			oid[i] = res;
		}
	}

	/* Get table space locations, since 9.2 there is a function for
	 * this, before we must hunt system tables for the information
	 */
	for ( i = 0; i < *nof_oids; i++ )
	{
		location[i] = get_tablespace_location ( conn, oid[i], verbose );
	}

	for ( i = 0; i < *nof_oids; i++ )
	{
		if ( verbose )
		{
			sprintf( format_str, "Free blocks calculation, seen tablespace OID %d, %s", oid[i], location[i] );
			pgfuse_syslog ( LOG_DEBUG, format_str );
		}
	}

	return 0;
}

int64_t psql_get_fs_files_used ( PGconn* conn )
{
	char format_str[LOG_LEN] = { '\0' };
	PGresult* res;
	char* data;
	int64_t used;

	res = PQexec ( conn, "SELECT COUNT(*) FROM dir" );
	if ( PQresultStatus ( res ) != PGRES_TUPLES_OK )
	{
		sprintf( format_str, "Error in psql_get_fs_files_used: %s", PQerrorMessage ( conn ) );
		pgfuse_syslog ( LOG_ERR, format_str );
		PQclear ( res );
		return -EIO;
	}

	data = PQgetvalue ( res, 0, 0 );
	used = atol ( data );

	PQclear ( res );

	return used;
}
