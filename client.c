#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h> 
#include <stdio.h>
#include <string.h>
#include <samba-4.0/wbclient.h>
#include <curl/curl.h>
#include <json-c/json.h>

struct curl_fetch_st {
    char *payload;
    size_t size;
};

size_t curl_callback (void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;               
    struct curl_fetch_st *p = (struct curl_fetch_st *) userp;
	free(p->payload);
    p->payload = (char *) malloc(p->size + realsize + 1);
    if (p->payload == NULL) {
      fprintf(stderr, "ERROR: Failed to expand buffer in curl_callback");
      free(p->payload);
      return -1;
    }
    memcpy(p->payload, contents, realsize);
    p->size += realsize+1;
    p->payload[p->size] = 0;
    return realsize;
}

int curl_http_get_id( const char *str )
{
	CURL *curl;
	CURLcode res;
	int id;
	//json_object *json;
	//json = json_object_new_object();
    //enum json_tokener_error jerr = json_tokener_success;
	char url[2048];
	strcpy(url,"http://test:test@srv-fuse.georec.spb.ru:8080/");
	strcat(url,str);
	struct curl_fetch_st curl_fetch;
    struct curl_fetch_st *fetch = &curl_fetch;
	fetch->size = 0;
	curl_global_init(CURL_GLOBAL_ALL);
	curl = curl_easy_init();
	if(curl)
	{
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_callback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *) fetch);
	res = curl_easy_perform(curl);
	if(res != CURLE_OK)
	printf("curl_file() failed: %s", curl_easy_strerror(res));
	else
	if (fetch->payload != NULL){
    id = atoi(fetch->payload);
	//json = json_tokener_parse_verbose(fetch->payload, &jerr);
	fetch->size=0;
	free(fetch->payload);
	//printf("CURL Returned: \n%s\n", json_object_to_json_string(json));
	//struct json_object* altitudeObj = json_object_new_object();;
	//altitudeObj = json_object_object_get(json, "screenName");
	//if(json_object_object_get_ex(json, "screenName",(struct json_object**)&altitudeObj))
	//printf("%s\n",json_object_get_string(altitudeObj));
	//json_object_put(altitudeObj);
	//json_object_put(json);
	//printf("CURL Returned: \n%s\n", json_object_to_json_string(val));
    }
	curl_easy_cleanup(curl);
	}
	curl_global_cleanup();
	return id; //atoi(fetch->payload);
}

int curl_http_get_screenname(const char *str, char *screenname)
{
	CURL *curl;
	CURLcode res;
	struct json_object *json;
	json = json_object_new_object();
    enum json_tokener_error jerr = json_tokener_success;
	char url[2048];
	strcpy(url,"http://test:test@srv-fuse.georec.spb.ru:8080/");
	strcat(url,str);
	struct curl_fetch_st curl_fetch;
    struct curl_fetch_st *fetch = &curl_fetch;
	fetch->size = 0;
	curl_global_init(CURL_GLOBAL_ALL);
	curl = curl_easy_init();
	if(curl)
	{
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_callback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *) fetch);
	res = curl_easy_perform(curl);
	if(res != CURLE_OK)
	printf("curl_file() failed: %s", curl_easy_strerror(res));
	else
	if (fetch->payload != NULL)
	{
    json = json_tokener_parse_verbose(fetch->payload, &jerr);
	//printf("CURL Returned: %s \n %zu\n ",fetch->payload,strlen(fetch->payload));
	size_t t = strlen(fetch->payload);
	free(fetch->payload);
	//printf("CURL Returned: \n%s\n", json_object_to_json_string(json));
	struct json_object* altitudeObj;// = json_object_new_object();;
	//altitudeObj = json_object_object_get(json, "screenName");
	json_object_object_get_ex(json, "screenName", (struct json_object**)&altitudeObj);
	strcpy(screenname, json_object_get_string(altitudeObj));
	json_object_put(altitudeObj);
	json_object_put(json);
	//printf("CURL Returned: \n%s\n", json_object_to_json_string(val));
    
    }
	curl_easy_cleanup(curl);
	}
	curl_global_cleanup();
	return 0; //atoi(fetch->payload);
}

int get_userid_by_screen_name(const char *name)
{
	int company_id = 10154;
	char screenname[25]={'0'};
	int userid;
	int uid = 13401;
	char str[1024]={'0'};
	sprintf(str,"api/jsonws/user/get-user-id-by-screen-name/company-id/%d/screen-name/%s/", company_id, name);
	userid = curl_http_get_id(str);
	printf("curl_http_get_id: userid = %d\n", userid);
	char id[1024]={'0'};
	sprintf(id,"api/jsonws/user/get-user-by-id/user-id/%d/", uid);
    curl_http_get_screenname( id, &screenname[0] );
	printf("curl_http_get_screenname: userid = %d screenname = %s\n", uid, screenname);
	return userid;
}

int main ( int arc, char **argv ) 
{
char  *domain_name="GEOREC";
uint32_t num_users=200;
const char *name="soldatovk";
uid_t puid;
struct wbcDomainSid sid;
struct wbcDomainSid sid_w;
enum wbcSidType name_type;
uint32_t num_groups;
gid_t *_groups;
char buf[512]={'0'};
wbcErr res;
int i;
//int m = 200;
//int n = 100;
char *domain;
//domain=(char *)calloc(n,sizeof(char));
char *name_out;
//name_out=(char *)calloc(n,sizeof(char));
char **users;
//users=(char **)calloc(num_users,sizeof(char *));
//for (i=0; i<=num_users; i++)
//users[i]=(char *)calloc(n,sizeof(char));
	//const char ***users=&a;
    //res = wbcPing();
    res = wbcLookupName(domain_name,name,&sid,&name_type);
    int len =  wbcSidToStringBuf(&sid, buf, 512);
    res = wbcSidToUid(&sid,&puid);
    //res = wbcLookupSid(&sid, (char **)&domain, (char **)&name_out, &name_type);
    res = wbcListUsers(domain_name,&num_users,(const char ***)&users);
	wbcUidToSid( puid, &sid_w);
    res = wbcLookupSid(&sid_w, (char **)&domain, (char **)&name_out, &name_type);
	res = wbcGetGroups( name, &num_groups, (gid_t **)&_groups);
	for (i=0; i<num_groups; i++)
    printf("res=%zu num_groups=%zu _groups[%i]=%zu\n",res,num_groups,i,_groups[i]);
    
    //wbcAllocateUid(&puid);
    //if(res ==  WBC_ERR_SUCCESS)
	//for (i=0; i<num_users; i++)
    printf("res=%zu num_users=%zu user[0]=%s\n",res,num_users,users[0]);
    printf("len=%d SID=%s UID=%zu\n",len,buf,puid);
    printf("res=%d  domain=%s name=%s type=%zu\n",res,domain,name_out,name_type);
	res = get_userid_by_screen_name(name_out);
    printf("Привет Мир res=%d\n",res);
	for (i=0; i<num_users; i++)
	{
	//printf("Пользователь №%d логин %s\n",i,users[i]);
	wbcFreeMemory(users[i]);
	//printf("Освобождение памяти=%d %s\n",i,users[i]);
	}
	wbcFreeMemory(users);
	wbcFreeMemory(domain);
	wbcFreeMemory(name_out);
	wbcFreeMemory(_groups);
	//free(domain);
	//free(name_out);
	
	return 0;
}
