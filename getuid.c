#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <postgres.h>
#include <fmgr.h>
#include <samba-4.0/wbclient.h>
#include <uuid/uuid.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC
;
#endif

PG_FUNCTION_INFO_V1 (get_screenname);

Datum get_screenname ( PG_FUNCTION_ARGS )
{
	int32 arg = PG_GETARG_INT32 ( 0 );
	uid_t uid = arg;
	text* new_text;
	wbcErr res;
	int32 text_size;
	struct wbcDomainSid sid;
	enum wbcSidType name_type;
	char* domain;
	char* screenname;
	res = wbcUidToSid ( uid, &sid );
	if ( res == 0 ) res = wbcLookupSid ( &sid, ( char ** ) &domain, ( char ** ) &screenname, &name_type );
	if ( res == 0 )
	{
		syslog ( LOG_ERR, "После получения sceenname=%s uid=%d", screenname, uid );
		text_size = strlen ( screenname );
		new_text = ( text * ) palloc ( text_size + VARHDRSZ );
		SET_VARSIZE ( new_text, text_size + VARHDRSZ );
		memcpy ( VARDATA ( new_text ), screenname, text_size );
		wbcFreeMemory ( domain );
		wbcFreeMemory ( screenname );
	}

	PG_RETURN_TEXT_P ( new_text );
}

PG_FUNCTION_INFO_V1 (get_uid);

Datum get_uid ( PG_FUNCTION_ARGS )
{
	char* screenname;
	VarChar* name = PG_GETARG_VARCHAR_P ( 0 );
	screenname = ( char* ) palloc ( VARSIZE ( name ) + 1 + VARHDRSZ );
	bzero ( screenname, VARSIZE ( name ) + 1 + VARHDRSZ );
	memcpy ( screenname, VARDATA ( name ), VARSIZE ( name ) - VARHDRSZ );
	//syslog( LOG_ERR, "До запроса %s",screenname);
	int32 uid = 0;
	wbcErr res;
	struct wbcDomainSid sid;
	uid_t puid;
	enum wbcSidType name_type;
	char* domain_name = "GEOREC";
	res = wbcLookupName ( domain_name, screenname, &sid, &name_type );
	if ( res == 0 ) res = wbcSidToUid ( &sid, &puid );
	if ( res == 0 )
	{
		uid = puid;
		syslog ( LOG_ERR, "После получения uid=%d name=%s", uid, screenname );
	}

	PG_RETURN_INT32 ( uid );
}

PG_FUNCTION_INFO_V1 (get_gid);

Datum get_gid ( PG_FUNCTION_ARGS )
{
	char* screenname;
	VarChar* name = PG_GETARG_VARCHAR_P ( 0 );
	screenname = ( char* ) palloc ( VARSIZE ( name ) + 1 + VARHDRSZ );
	bzero ( screenname, VARSIZE ( name ) + 1 + VARHDRSZ );
	memcpy ( screenname, VARDATA ( name ), VARSIZE ( name ) - VARHDRSZ );
	//syslog( LOG_ERR, "До запроса %s",screenname);
	int32 gid = 0;
	gid_t* _groups;
	uint32_t num_groups;
	wbcErr res;
	res = wbcGetGroups ( screenname, &num_groups, ( gid_t ** ) &_groups );
	if ( res == 0 )
	{
		gid = _groups[0];
		syslog ( LOG_ERR, "После получения gid=%d name=%s", gid, screenname );
		wbcFreeMemory ( _groups );
	}

	PG_RETURN_INT32 ( gid );
}

PG_FUNCTION_INFO_V1 (get_sid);

Datum get_sid ( PG_FUNCTION_ARGS )
{
	char* screenname;
	VarChar* name = PG_GETARG_VARCHAR_P ( 0 );
	screenname = ( char* ) palloc ( VARSIZE ( name ) + 1 + VARHDRSZ );
	bzero ( screenname, VARSIZE ( name ) + 1 + VARHDRSZ );
	memcpy ( screenname, VARDATA ( name ), VARSIZE ( name ) - VARHDRSZ );
	//syslog( LOG_ERR, "До запроса %s",screenname);
	wbcErr res;
	char buf[512] = { '0' };
	char* str = "NO_SID";
	struct wbcDomainSid sid;
	int32 text_size;
	enum wbcSidType name_type;
	char* domain_name = "GEOREC";
	text* new_text;
	res = wbcLookupName ( domain_name, screenname, &sid, &name_type );
	if ( res == 0 )
	{
		text_size = wbcSidToStringBuf ( &sid, buf, 512 );
		new_text = ( text * ) palloc ( text_size + VARHDRSZ );
		SET_VARSIZE ( new_text, text_size + VARHDRSZ );
		memcpy ( VARDATA ( new_text ), buf, text_size );
		syslog ( LOG_ERR, "После получения sid=%s name=%s, len=%d", buf, screenname, text_size );
	}
	else
	{
		text_size = strlen ( str );
		new_text = ( text * ) palloc ( text_size + VARHDRSZ );
		SET_VARSIZE ( new_text, text_size + VARHDRSZ );
		memcpy ( VARDATA ( new_text ), str, text_size );
		syslog ( LOG_ERR, "После получения sid=%s name=%s len=%d", str, screenname, text_size );
	}
	syslog ( LOG_ERR, "В итоге new_text=%s ", VARDATA ( new_text ) );

	PG_RETURN_TEXT_P ( new_text );
}

PG_FUNCTION_INFO_V1 (get_uid_from_sid);

Datum get_uid_from_sid ( PG_FUNCTION_ARGS )
{
	char* sid_str;
	VarChar* name = PG_GETARG_VARCHAR_P ( 0 );
	sid_str = ( char* ) palloc ( VARSIZE ( name ) + 1 + VARHDRSZ );
	bzero ( sid_str, VARSIZE ( name ) + 1 + VARHDRSZ );
	memcpy ( sid_str, VARDATA ( name ), VARSIZE ( name ) - VARHDRSZ );
	wbcErr res;
	int32 uid = 0;
	uid_t puid;
	struct wbcDomainSid sid;
	res = wbcStringToSid( sid_str, &sid );
	if ( res == 0 ) res = wbcSidToUid ( &sid, &puid );
	if ( res == 0 )
	{
		uid = puid;
		syslog ( LOG_ERR, "Получения uid=%d из sid=%s", uid, sid_str );
	}
	else syslog ( LOG_ERR, "ERROR Получения uid=%d из sid=%s", uid, sid_str );
	PG_RETURN_INT32 ( uid );
}

PG_FUNCTION_INFO_V1 (get_gid_from_sid);

Datum get_gid_from_sid ( PG_FUNCTION_ARGS )
{
	char* sid_str;
	VarChar* name = PG_GETARG_VARCHAR_P ( 0 );
	sid_str = ( char* ) palloc ( VARSIZE ( name ) + 1 + VARHDRSZ );
	bzero ( sid_str, VARSIZE ( name ) + 1 + VARHDRSZ );
	memcpy ( sid_str, VARDATA ( name ), VARSIZE ( name ) - VARHDRSZ );
	wbcErr res;
	int32 gid = 0;
	uid_t puid;
	struct wbcDomainSid sid;
	res = wbcStringToSid( sid_str, &sid );
	if ( res == 0 ) res = wbcSidToGid ( &sid, &puid );
	if ( res == 0 )
	{
		gid = puid;
		syslog ( LOG_ERR, "Получения gid=%d из sid=%s", gid, sid_str );
	}
	else syslog ( LOG_ERR, "ERROR Получения gid=%d из sid=%s", gid, sid_str );
	PG_RETURN_INT32 ( gid );
}