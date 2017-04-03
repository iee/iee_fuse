--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.6
-- Dumped by pg_dump version 9.5.1

-- Started on 2017-04-03 13:47:58

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4694 (class 1262 OID 30344)
-- Name: portal; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE portal WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'ru_RU.UTF-8' LC_CTYPE = 'ru_RU.UTF-8';


ALTER DATABASE portal OWNER TO postgres;

\connect portal

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 1 (class 3079 OID 12397)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 4697 (class 0 OID 0)
-- Dependencies: 1
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- TOC entry 2 (class 3079 OID 32823)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 4698 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET search_path = public, pg_catalog;

--
-- TOC entry 459 (class 1255 OID 32858)
-- Name: copy_xattr_from_to(bigint, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION copy_xattr_from_to(from_id bigint, to_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO xattr( dir_id, name, val ) VALUES ( to_id, 'security.NTACL', (SELECT val FROM xattr WHERE dir_id = from_id AND name = 'security.NTACL'));
END;
$$;


ALTER FUNCTION public.copy_xattr_from_to(from_id bigint, to_id bigint) OWNER TO postgres;

--
-- TOC entry 471 (class 1255 OID 32851)
-- Name: dir_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION dir_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	BEGIN
	IF TG_OP = 'UPDATE' THEN
	UPDATE dlfolder SET size_=NEW.size, mode=NEW.mode, uid=NEW.uid, gid=NEW.gid, createdate=NEW.ctime, modifieddate=NEW.mtime, accessdate=NEW.atime WHERE folderid=OLD.id;
	UPDATE dlfileentry SET size_=NEW.size, mode=NEW.mode, uid=NEW.uid, gid=NEW.gid, createdate=NEW.ctime, modifieddate=NEW.mtime, accessdate=NEW.atime  WHERE fileentryid=OLD.id;
	UPDATE dir_fs SET parent_id=NEW.parent_id, name=NEW.name, size=NEW.size, mode=NEW.mode, uid=NEW.uid, gid=NEW.gid, ctime=NEW.ctime, mtime=NEW.mtime, atime=NEW.atime  WHERE id=OLD.id;
	RETURN NEW;
	END IF;
	IF TG_OP = 'DELETE' THEN
	DELETE FROM dir_fs WHERE id=OLD.id;
	DELETE FROM xattr WHERE dir_id=OLD.id;
	DELETE FROM data WHERE dir_id=OLD.id;
	RETURN NULL;
	END IF;
	IF TG_OP = 'INSERT' THEN
	INSERT INTO dir_fs ( parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES ( NEW.parent_id, NEW.name, NEW.size, NEW.mode, NEW.uid, NEW.gid, NEW.ctime, NEW.mtime, NEW.atime);
	RETURN NEW;
	END IF;
   END;
$$;


ALTER FUNCTION public.dir_update() OWNER TO postgres;

--
-- TOC entry 473 (class 1255 OID 33398)
-- Name: func_get_sddl_by_id(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_get_sddl_by_id(in_folder_id bigint) RETURNS text
    LANGUAGE sql
    AS $$
SELECT NULL::text AS sddl
   FROM group_ d WHERE d.groupid = in_folder_id
UNION ALL
 SELECT 
        CASE
            WHEN COALESCE(ev1.data_::boolean = FALSE, TRUE) THEN NULL::text
            ELSE getssdlbyid(d.folderid)
        END AS sddl
   FROM dlfolder d 
	LEFT OUTER JOIN expandovalue ev1 ON (d.folderid = ev1.classpk AND ev1.columnid=(SELECT columnid from expandocolumn WHERE name = 'IS_TMPL'))
   WHERE d.folderid = in_folder_id
UNION ALL
SELECT NULL::text AS sddl
   FROM dlfileentry d WHERE d.fileentryid = in_folder_id
UNION ALL
SELECT NULL::text AS sddl
   FROM dir_fs d WHERE d.id = in_folder_id
UNION ALL
select NULL::text AS sddl from expandovalue ev where ev.columnid = (select columnid from expandocolumn where name='FOLDER_ID') and ev.data_::bigint=in_folder_id
$$;


ALTER FUNCTION public.func_get_sddl_by_id(in_folder_id bigint) OWNER TO postgres;

--
-- TOC entry 465 (class 1255 OID 32847)
-- Name: func_get_tree(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_get_tree(root_folder_id bigint) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	result text;
BEGIN
	WITH RECURSIVE d AS (
	  SELECT id
	   FROM dir
	   WHERE parent_id = root_folder_id 
	 UNION ALL
	  SELECT c.id
	   FROM d JOIN dir c ON c.parent_id = d.id 
	)
	SELECT string_agg(CAST(id AS VARCHAR), ' ') into result FROM d;
	RETURN result;
END;
$$;


ALTER FUNCTION public.func_get_tree(root_folder_id bigint) OWNER TO postgres;

--
-- TOC entry 474 (class 1255 OID 33587)
-- Name: func_get_tree_dir_sddl(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_get_tree_dir_sddl(in_folder_id bigint) RETURNS TABLE(id bigint, sddl text)
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY
	WITH RECURSIVE d(id, sddl) AS (
	  SELECT b.id, func_get_sddl_by_id(b.id) AS sddl
	   FROM dir b
	   WHERE b.parent_id = in_folder_id 
	 UNION ALL
	  SELECT c.id, func_get_sddl_by_id(c.id)
	   FROM d JOIN dir c ON c.parent_id = d.id
	)
	SELECT * FROM d WHERE d.sddl IS NOT NULL;
END;
$$;


ALTER FUNCTION public.func_get_tree_dir_sddl(in_folder_id bigint) OWNER TO postgres;

--
-- TOC entry 470 (class 1255 OID 33161)
-- Name: func_insupd_ntacl(bigint, bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_insupd_ntacl(id_dir bigint, data_val bytea) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO xattr (dir_id, name, val)
    VALUES (id_dir, 'security.NTACL', data_val)
    ON CONFLICT (dir_id,name)
    DO UPDATE SET
    val = data_val;
END;
$$;


ALTER FUNCTION public.func_insupd_ntacl(id_dir bigint, data_val bytea) OWNER TO postgres;

--
-- TOC entry 475 (class 1255 OID 33589)
-- Name: func_update_child_ntacl(bigint, bytea, bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_update_child_ntacl(root_folder_id bigint, sd_sub_folder bytea, sd_file bytea) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	CREATE TEMPORARY TABLE rec_d (id BIGINT, mode INTEGER) ON COMMIT DROP;
	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id AND func_get_sddl_by_id(id) IS NULL
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id AND func_get_sddl_by_id(c.id) IS NULL
	)
	INSERT INTO rec_d (id,mode) SELECT id,mode FROM d;
		
	INSERT INTO xattr (dir_id, name, val)
	SELECT rec_d.id, 'security.NTACL', sd_sub_folder FROM rec_d WHERE rec_d.mode & 61440 = 16384
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_sub_folder;

	INSERT INTO xattr (dir_id, name, val)
	SELECT rec_d.id, 'security.NTACL', sd_file FROM rec_d WHERE rec_d.mode & 61440 = 32768
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_file;

	DROP TABLE rec_d;
END;
$$;


ALTER FUNCTION public.func_update_child_ntacl(root_folder_id bigint, sd_sub_folder bytea, sd_file bytea) OWNER TO postgres;

--
-- TOC entry 472 (class 1255 OID 32848)
-- Name: func_update_ntacl(bigint, bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION func_update_ntacl(root_folder_id bigint, sd_folder bytea, sd_sub_folder bytea, sd_file bytea) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	INSERT INTO xattr (dir_id, name, val)
	SELECT d.id, 'security.NTACL', sd_sub_folder FROM d WHERE d.mode & 61440 = 16384
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_sub_folder;
	
	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	INSERT INTO xattr (dir_id, name, val)
	SELECT d.id, 'security.NTACL', sd_file FROM d WHERE d.mode & 61440 = 32768
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_file;

	INSERT INTO xattr (dir_id, name, val)
	VALUES (root_folder_id, 'security.NTACL', sd_folder)
	ON CONFLICT (dir_id,name)
	DO UPDATE SET
	val = sd_folder;

END;
$$;


ALTER FUNCTION public.func_update_ntacl(root_folder_id bigint, sd_folder bytea, sd_sub_folder bytea, sd_file bytea) OWNER TO postgres;

--
-- TOC entry 462 (class 1255 OID 32988)
-- Name: get_gid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_gid(character varying) RETURNS integer
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_gid';


ALTER FUNCTION public.get_gid(character varying) OWNER TO postgres;

--
-- TOC entry 467 (class 1255 OID 33156)
-- Name: get_gid_from_sid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_gid_from_sid(character varying) RETURNS integer
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_gid_from_sid';


ALTER FUNCTION public.get_gid_from_sid(character varying) OWNER TO postgres;

--
-- TOC entry 464 (class 1255 OID 32990)
-- Name: get_screenname(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_screenname(integer) RETURNS text
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_screenname';


ALTER FUNCTION public.get_screenname(integer) OWNER TO postgres;

--
-- TOC entry 463 (class 1255 OID 32989)
-- Name: get_sid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_sid(character varying) RETURNS text
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_sid';


ALTER FUNCTION public.get_sid(character varying) OWNER TO postgres;

--
-- TOC entry 461 (class 1255 OID 32987)
-- Name: get_uid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_uid(character varying) RETURNS integer
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_uid';


ALTER FUNCTION public.get_uid(character varying) OWNER TO postgres;

--
-- TOC entry 466 (class 1255 OID 32991)
-- Name: get_uid_from_sid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_uid_from_sid(character varying) RETURNS integer
    LANGUAGE c STRICT
    AS 'libgetuid', 'get_uid_from_sid';


ALTER FUNCTION public.get_uid_from_sid(character varying) OWNER TO postgres;

--
-- TOC entry 469 (class 1255 OID 33312)
-- Name: getaclbyactionids(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION getaclbyactionids(bigint) RETURNS character varying
    LANGUAGE plpgsql
    AS $_$
DECLARE
BEGIN
	-- deny
	--IF ($1 = 1::BIGINT) THEN
	--	RETURN 'D;OICI;0x001f01ff;;;%s';
	-- read		
	IF ($1 = 0::BIGINT) THEN
		RETURN 'A;OICI;0x001200a9;;;%s';
	-- read		
	ELSEIF ($1 = 1::BIGINT) THEN
		RETURN 'A;OICI;0x001200a9;;;%s';
	-- write	
	ELSEIF ($1 = 73::BIGINT) THEN
		RETURN 'A;OICI;0x001201ff;;;%s';
	-- write	
	ELSEIF ($1 = 107::BIGINT) THEN
		RETURN 'A;OICI;0x001201ff;;;%s';	
	END IF;
END;
$_$;


ALTER FUNCTION public.getaclbyactionids(bigint) OWNER TO postgres;

--
-- TOC entry 476 (class 1255 OID 33341)
-- Name: getssdlbyid(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION getssdlbyid(bigint) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
rec record;
result text;
result2 text;
BEGIN
 result = '(A;OICI;0x001f01ff;;;SY)';
 result2 = 'O:SYG:S-1-5-21-3874029520-2253553080-878871061-1113D:PAI%s';
 FOR rec IN (
		-- portal roles for user groups
		SELECT getAclByActionids(rp.actionids) as acl, rp.actionids , r.name, r.roleid, ug.sid 
		from 
		resourcepermission rp, role_ r, groups_roles gr, group_ g, usergroup ug
			where 
		rp.roleid = r.roleid
		and gr.groupid=g.groupid and g.classpk=ug.usergroupid and gr.roleid=r.roleid 
		and r.type_ = 1 
		and rp.primkey = $1::varchar 
		and rp.actionids > 0
	UNION
		-- project roles, only 'Site Member', because it's default role
		select getAclByActionids(rp.actionids) as acl, rp.actionids , r.name, r.roleid, u.sid 
		from resourcepermission rp, role_ r, dlfolder dlf, users_groups ug, user_ u
		where 
		dlf.folderid=rp.primkey::bigint
		and ug.groupid=dlf.groupid
		and rp.roleid = r.roleid
		and  ug.userid = u.userid
		and r.type_ = 2 
		and r.name = 'Site Member'
		and rp.primkey = $1::varchar 
		and rp.actionids > 0
		and u.sid != 'NO_SID'
	UNION
		-- project roles, all roles except 'Site Member', because it's default role
		select getAclByActionids(rp.actionids) as acl, rp.actionids , r.name, r.roleid, u.sid
		from resourcepermission rp, role_ r, dlfolder dlf, usergrouprole ugr, user_ u
		where 
		dlf.folderid=rp.primkey::bigint
		and ugr.groupid=dlf.groupid
		and rp.roleid = r.roleid 
		and ugr.roleid = r.roleid
		and ugr.userid = u.userid
		and r.type_ = 2 
		and rp.primkey = $1::varchar 
		and rp.actionids > 0
	UNION
		-- organizatoin roles, all roles except 'Site Member', because it's default role
		SELECT getAclByActionids(rp.actionids) as acl, rp.actionids , r.name, r.roleid, 
			(SELECT ug.sid FROM expandovalue ev, usergroup ug WHERE ev.classpk=g.classpk and ev.data_::bigint=ug.usergroupid and ev.columnid=(SELECT columnid FROM expandocolumn WHERE name='UG_ID')) as sid
		from 
		resourcepermission rp, role_ r, groups_roles gr, group_ g, classname_ cn
			where 
		rp.roleid = r.roleid
		and gr.groupid=g.groupid and gr.roleid=r.roleid
		and g.classnameid = cn.classnameid 
		and cn.value = 'com.liferay.portal.kernel.model.Organization'
		and r.type_ = 1 
		and rp.primkey = $1::varchar 
		and rp.actionids > 0
		)
    LOOP
        -- can do some processing here
        --RETURN r.acl; -- return current row of SELECT
        result = result || '(' || replace(rec.acl, '%s', rec.sid) || ')';
    END LOOP;
    result2 = replace(result2, '%s', result);
    RETURN result2;
END;
$_$;


ALTER FUNCTION public.getssdlbyid(bigint) OWNER TO postgres;

--
-- TOC entry 457 (class 1255 OID 32850)
-- Name: group_descriptive_name(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION group_descriptive_name(bigint) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
	classname VARCHAR(75);
	classpk2 BIGINT;
BEGIN
	SELECT c.value, g.classpk INTO classname, classpk2 FROM group_ g,classname_ c WHERE g.classnameid=c.classnameid AND groupid=$1;
	IF classname = 'com.liferay.portal.kernel.model.Group' THEN
	RETURN (SELECT data_ FROM expandovalue WHERE columnid=(SELECT columnid FROM expandocolumn WHERE name='GROUP_SHORT_NAME') 
	AND columnid=(SELECT columnid FROM classname_ WHERE value='com.liferay.portal.kernel.model.Group') AND classpk=$1);
	ELSEIF classname = 'com.liferay.portal.kernel.model.User' THEN
	RETURN (SELECT  lastname || ' ' || firstname || ' ' || middlename FROM user_ WHERE userid=classpk2);
	ELSEIF classname = 'com.liferay.portal.kernel.model.Organization' THEN
	RETURN (SELECT name FROM organization_ WHERE organizationid=classpk2);
	ELSE 
	RETURN CAST( $1 AS TEXT );
	END IF;
END;
$_$;


ALTER FUNCTION public.group_descriptive_name(bigint) OWNER TO postgres;

--
-- TOC entry 460 (class 1255 OID 32849)
-- Name: group_parent_id(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION group_parent_id(bigint) RETURNS bigint
    LANGUAGE plpgsql
    AS $_$
DECLARE
	parent_id BIGINT;
	classname_id BIGINT;
	parent_classname_id BIGINT;
	classname VARCHAR(75);
BEGIN
	SELECT g.parentgroupid, g.classnameid, g2.classnameid, c.value INTO parent_id, classname_id, parent_classname_id, classname FROM group_ g LEFT OUTER JOIN group_ g2 ON g.parentgroupid = g2.groupid, classname_ c WHERE g.classnameid=c.classnameid AND g.groupid=$1;
	IF (parent_id != 0 AND classname_id = parent_classname_id ) THEN
	select ev.data_::bigint INTO parent_id from expandovalue ev where ev.columnid = (select columnid from expandocolumn where name='FOLDER_ID') and ev.classpk=parent_id;
	RETURN parent_id;
	END IF;
	IF classname='com.liferay.portal.kernel.model.User' THEN
	RETURN 3::BIGINT;
	ELSEIF classname='com.liferay.portal.kernel.model.Organization' THEN
	RETURN 2::BIGINT;
	ELSEIF classname='com.liferay.portal.kernel.model.Group' THEN
	RETURN 1::BIGINT;
	END IF;
END;
$_$;


ALTER FUNCTION public.group_parent_id(bigint) OWNER TO postgres;

--
-- TOC entry 468 (class 1255 OID 33157)
-- Name: set_sid_gid(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION set_sid_gid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    str VARCHAR (75);
    BEGIN
    str = CAST ( get_sid(NEW.name) AS VARCHAR (75) );
    NEW.sid = str;
    NEW.gid = get_gid_from_sid(str);
    RETURN NEW;
    END;
$$;


ALTER FUNCTION public.set_sid_gid() OWNER TO postgres;

--
-- TOC entry 458 (class 1255 OID 32857)
-- Name: set_sid_uid(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION set_sid_uid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    str VARCHAR (75);
    BEGIN
    str = CAST ( get_sid(NEW.screenname) AS VARCHAR (75) );
    NEW.sid = str;
    NEW.uid = get_uid_from_sid(str);
    RETURN NEW;
    END;
$$;


ALTER FUNCTION public.set_sid_uid() OWNER TO postgres;

--
-- TOC entry 456 (class 1255 OID 32859)
-- Name: set_uid_gid(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION set_uid_gid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	DECLARE
	scr VARCHAR (75);
	BEGIN
	scr = (SELECT u.screenname FROM user_ u WHERE u.userid=NEW.userid);
	NEW.uid = get_uid(scr);
	NEW.gid = get_gid(scr);
	RETURN NEW;
	END;
$$;


ALTER FUNCTION public.set_uid_gid() OWNER TO postgres;

SET default_with_oids = false;

--
-- TOC entry 204 (class 1259 OID 30453)
-- Name: account_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE account_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    accountid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentaccountid bigint,
    name character varying(75),
    legalname character varying(75),
    legalid character varying(75),
    legaltype character varying(75),
    siccode character varying(75),
    tickersymbol character varying(75),
    industry character varying(75),
    type_ character varying(75),
    size_ character varying(75)
);


ALTER TABLE account_ OWNER TO postgres;

--
-- TOC entry 205 (class 1259 OID 30462)
-- Name: address; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE address (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    addressid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    street1 character varying(75),
    street2 character varying(75),
    street3 character varying(75),
    city character varying(75),
    zip character varying(75),
    regionid bigint,
    countryid bigint,
    typeid bigint,
    mailing boolean,
    primary_ boolean
);


ALTER TABLE address OWNER TO postgres;

--
-- TOC entry 206 (class 1259 OID 30471)
-- Name: announcementsdelivery; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE announcementsdelivery (
    deliveryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    type_ character varying(75),
    email boolean,
    sms boolean,
    website boolean
);


ALTER TABLE announcementsdelivery OWNER TO postgres;

--
-- TOC entry 207 (class 1259 OID 30476)
-- Name: announcementsentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE announcementsentry (
    uuid_ character varying(75),
    entryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    title character varying(75),
    content text,
    url text,
    type_ character varying(75),
    displaydate timestamp without time zone,
    expirationdate timestamp without time zone,
    priority integer,
    alert boolean
);


ALTER TABLE announcementsentry OWNER TO postgres;

--
-- TOC entry 208 (class 1259 OID 30484)
-- Name: announcementsflag; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE announcementsflag (
    flagid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    createdate timestamp without time zone,
    entryid bigint,
    value integer
);


ALTER TABLE announcementsflag OWNER TO postgres;

--
-- TOC entry 209 (class 1259 OID 30489)
-- Name: assetcategory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetcategory (
    uuid_ character varying(75),
    categoryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentcategoryid bigint,
    leftcategoryid bigint,
    rightcategoryid bigint,
    name character varying(75),
    title text,
    description text,
    vocabularyid bigint,
    lastpublishdate timestamp without time zone
);


ALTER TABLE assetcategory OWNER TO postgres;

--
-- TOC entry 210 (class 1259 OID 30497)
-- Name: assetcategoryproperty; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetcategoryproperty (
    categorypropertyid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    categoryid bigint,
    key_ character varying(75),
    value character varying(75)
);


ALTER TABLE assetcategoryproperty OWNER TO postgres;

--
-- TOC entry 211 (class 1259 OID 30502)
-- Name: assetentries_assetcategories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetentries_assetcategories (
    companyid bigint NOT NULL,
    categoryid bigint NOT NULL,
    entryid bigint NOT NULL
);


ALTER TABLE assetentries_assetcategories OWNER TO postgres;

--
-- TOC entry 212 (class 1259 OID 30507)
-- Name: assetentries_assettags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetentries_assettags (
    companyid bigint NOT NULL,
    entryid bigint NOT NULL,
    tagid bigint NOT NULL
);


ALTER TABLE assetentries_assettags OWNER TO postgres;

--
-- TOC entry 213 (class 1259 OID 30512)
-- Name: assetentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetentry (
    entryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    classuuid character varying(75),
    classtypeid bigint,
    listable boolean,
    visible boolean,
    startdate timestamp without time zone,
    enddate timestamp without time zone,
    publishdate timestamp without time zone,
    expirationdate timestamp without time zone,
    mimetype character varying(75),
    title text,
    description text,
    summary text,
    url text,
    layoutuuid character varying(75),
    height integer,
    width integer,
    priority double precision,
    viewcount integer
);


ALTER TABLE assetentry OWNER TO postgres;

--
-- TOC entry 214 (class 1259 OID 30520)
-- Name: assetlink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetlink (
    linkid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    entryid1 bigint,
    entryid2 bigint,
    type_ integer,
    weight integer
);


ALTER TABLE assetlink OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 30525)
-- Name: assettag; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assettag (
    uuid_ character varying(75),
    tagid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(75),
    assetcount integer,
    lastpublishdate timestamp without time zone
);


ALTER TABLE assettag OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 30530)
-- Name: assettagstats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assettagstats (
    tagstatsid bigint NOT NULL,
    companyid bigint,
    tagid bigint,
    classnameid bigint,
    assetcount integer
);


ALTER TABLE assettagstats OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 30535)
-- Name: assetvocabulary; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE assetvocabulary (
    uuid_ character varying(75),
    vocabularyid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(75),
    title text,
    description text,
    settings_ text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE assetvocabulary OWNER TO postgres;

--
-- TOC entry 346 (class 1259 OID 31968)
-- Name: backgroundtask; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE backgroundtask (
    mvccversion bigint DEFAULT 0 NOT NULL,
    backgroundtaskid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(255),
    servletcontextnames character varying(255),
    taskexecutorclassname character varying(200),
    taskcontextmap text,
    completed boolean,
    completiondate timestamp without time zone,
    status integer,
    statusmessage text
);


ALTER TABLE backgroundtask OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 30543)
-- Name: blogsentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE blogsentry (
    uuid_ character varying(75),
    entryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    title character varying(150),
    subtitle text,
    urltitle character varying(150),
    description text,
    content text,
    displaydate timestamp without time zone,
    allowpingbacks boolean,
    allowtrackbacks boolean,
    trackbacks text,
    coverimagecaption text,
    coverimagefileentryid bigint,
    coverimageurl text,
    smallimage boolean,
    smallimagefileentryid bigint,
    smallimageid bigint,
    smallimageurl text,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE blogsentry OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 30551)
-- Name: blogsstatsuser; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE blogsstatsuser (
    statsuserid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    entrycount integer,
    lastpostdate timestamp without time zone,
    ratingstotalentries integer,
    ratingstotalscore double precision,
    ratingsaveragescore double precision
);


ALTER TABLE blogsstatsuser OWNER TO postgres;

--
-- TOC entry 374 (class 1259 OID 32328)
-- Name: bookmarksentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE bookmarksentry (
    uuid_ character varying(75),
    entryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    resourceblockid bigint,
    folderid bigint,
    treepath text,
    name character varying(255),
    url text,
    description text,
    visits integer,
    priority integer,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE bookmarksentry OWNER TO postgres;

--
-- TOC entry 375 (class 1259 OID 32336)
-- Name: bookmarksfolder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE bookmarksfolder (
    uuid_ character varying(75),
    folderid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    resourceblockid bigint,
    parentfolderid bigint,
    treepath text,
    name character varying(75),
    description text,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE bookmarksfolder OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 30556)
-- Name: browsertracker; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE browsertracker (
    mvccversion bigint DEFAULT 0 NOT NULL,
    browsertrackerid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    browserkey bigint
);


ALTER TABLE browsertracker OWNER TO postgres;

--
-- TOC entry 403 (class 1259 OID 32642)
-- Name: calendar; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE calendar (
    uuid_ character varying(75),
    calendarid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    resourceblockid bigint,
    calendarresourceid bigint,
    name text,
    description text,
    timezoneid character varying(75),
    color integer,
    defaultcalendar boolean,
    enablecomments boolean,
    enableratings boolean,
    lastpublishdate timestamp without time zone
);


ALTER TABLE calendar OWNER TO postgres;

--
-- TOC entry 404 (class 1259 OID 32650)
-- Name: calendarbooking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE calendarbooking (
    uuid_ character varying(75),
    calendarbookingid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    resourceblockid bigint,
    calendarid bigint,
    calendarresourceid bigint,
    parentcalendarbookingid bigint,
    veventuid character varying(255),
    title text,
    description text,
    location text,
    starttime bigint,
    endtime bigint,
    allday boolean,
    recurrence text,
    firstreminder bigint,
    firstremindertype character varying(75),
    secondreminder bigint,
    secondremindertype character varying(75),
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE calendarbooking OWNER TO postgres;

--
-- TOC entry 405 (class 1259 OID 32658)
-- Name: calendarnotificationtemplate; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE calendarnotificationtemplate (
    uuid_ character varying(75),
    calendarnotificationtemplateid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    calendarid bigint,
    notificationtype character varying(75),
    notificationtypesettings character varying(75),
    notificationtemplatetype character varying(75),
    subject character varying(75),
    body text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE calendarnotificationtemplate OWNER TO postgres;

--
-- TOC entry 406 (class 1259 OID 32666)
-- Name: calendarresource; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE calendarresource (
    uuid_ character varying(75),
    calendarresourceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    resourceblockid bigint,
    classnameid bigint,
    classpk bigint,
    classuuid character varying(75),
    code_ character varying(75),
    name text,
    description text,
    active_ boolean,
    lastpublishdate timestamp without time zone
);


ALTER TABLE calendarresource OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 30562)
-- Name: classname_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE classname_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    classnameid bigint NOT NULL,
    value character varying(200)
);


ALTER TABLE classname_ OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 30568)
-- Name: clustergroup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE clustergroup (
    mvccversion bigint DEFAULT 0 NOT NULL,
    clustergroupid bigint NOT NULL,
    name character varying(75),
    clusternodeids character varying(75),
    wholecluster boolean
);


ALTER TABLE clustergroup OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 30574)
-- Name: company; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE company (
    mvccversion bigint DEFAULT 0 NOT NULL,
    companyid bigint NOT NULL,
    accountid bigint,
    webid character varying(75),
    key_ text,
    mx character varying(75),
    homeurl text,
    logoid bigint,
    system boolean,
    maxusers integer,
    active_ boolean
);


ALTER TABLE company OWNER TO postgres;

--
-- TOC entry 192 (class 1259 OID 30345)
-- Name: configuration_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE configuration_ (
    configurationid character varying(255) NOT NULL,
    dictionary text
);


ALTER TABLE configuration_ OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 30583)
-- Name: contact_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE contact_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    contactid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    accountid bigint,
    parentcontactid bigint,
    emailaddress character varying(75),
    firstname character varying(75),
    middlename character varying(75),
    lastname character varying(75),
    prefixid bigint,
    suffixid bigint,
    male boolean,
    birthday timestamp without time zone,
    smssn character varying(75),
    facebooksn character varying(75),
    jabbersn character varying(75),
    skypesn character varying(75),
    twittersn character varying(75),
    employeestatusid character varying(75),
    employeenumber character varying(75),
    jobtitle character varying(100),
    jobclass character varying(75),
    hoursofoperation character varying(75)
);


ALTER TABLE contact_ OWNER TO postgres;

--
-- TOC entry 377 (class 1259 OID 32365)
-- Name: contacts_entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE contacts_entry (
    entryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    fullname character varying(75),
    emailaddress character varying(75),
    comments text
);


ALTER TABLE contacts_entry OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 30592)
-- Name: counter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE counter (
    name character varying(75) NOT NULL,
    currentid bigint
);


ALTER TABLE counter OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 30597)
-- Name: country; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE country (
    mvccversion bigint DEFAULT 0 NOT NULL,
    countryid bigint NOT NULL,
    name character varying(75),
    a2 character varying(75),
    a3 character varying(75),
    number_ character varying(75),
    idd_ character varying(75),
    ziprequired boolean,
    active_ boolean
);


ALTER TABLE country OWNER TO postgres;

--
-- TOC entry 417 (class 1259 OID 32803)
-- Name: data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE data (
    dir_id bigint NOT NULL,
    block_no bigint DEFAULT 0 NOT NULL,
    data bytea
);


ALTER TABLE data OWNER TO postgres;

--
-- TOC entry 378 (class 1259 OID 32374)
-- Name: ddlrecord; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddlrecord (
    uuid_ character varying(75),
    recordid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    versionuserid bigint,
    versionusername character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    ddmstorageid bigint,
    recordsetid bigint,
    version character varying(75),
    displayindex integer,
    lastpublishdate timestamp without time zone
);


ALTER TABLE ddlrecord OWNER TO postgres;

--
-- TOC entry 379 (class 1259 OID 32379)
-- Name: ddlrecordset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddlrecordset (
    uuid_ character varying(75),
    recordsetid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    ddmstructureid bigint,
    recordsetkey character varying(75),
    name text,
    description text,
    mindisplayrows integer,
    scope integer,
    settings_ text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE ddlrecordset OWNER TO postgres;

--
-- TOC entry 380 (class 1259 OID 32387)
-- Name: ddlrecordversion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddlrecordversion (
    recordversionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    ddmstorageid bigint,
    recordsetid bigint,
    recordid bigint,
    version character varying(75),
    displayindex integer,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE ddlrecordversion OWNER TO postgres;

--
-- TOC entry 360 (class 1259 OID 32162)
-- Name: ddmcontent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmcontent (
    uuid_ character varying(75),
    contentid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name text,
    description text,
    data_ text
);


ALTER TABLE ddmcontent OWNER TO postgres;

--
-- TOC entry 361 (class 1259 OID 32170)
-- Name: ddmdataproviderinstance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmdataproviderinstance (
    uuid_ character varying(75),
    dataproviderinstanceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name text,
    description text,
    definition text,
    type_ character varying(75)
);


ALTER TABLE ddmdataproviderinstance OWNER TO postgres;

--
-- TOC entry 362 (class 1259 OID 32178)
-- Name: ddmdataproviderinstancelink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmdataproviderinstancelink (
    dataproviderinstancelinkid bigint NOT NULL,
    companyid bigint,
    dataproviderinstanceid bigint,
    structureid bigint
);


ALTER TABLE ddmdataproviderinstancelink OWNER TO postgres;

--
-- TOC entry 363 (class 1259 OID 32183)
-- Name: ddmstoragelink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmstoragelink (
    uuid_ character varying(75),
    storagelinkid bigint NOT NULL,
    companyid bigint,
    classnameid bigint,
    classpk bigint,
    structureid bigint
);


ALTER TABLE ddmstoragelink OWNER TO postgres;

--
-- TOC entry 364 (class 1259 OID 32188)
-- Name: ddmstructure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmstructure (
    uuid_ character varying(75),
    structureid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    versionuserid bigint,
    versionusername character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentstructureid bigint,
    classnameid bigint,
    structurekey character varying(75),
    version character varying(75),
    name text,
    description text,
    definition text,
    storagetype character varying(75),
    type_ integer,
    lastpublishdate timestamp without time zone
);


ALTER TABLE ddmstructure OWNER TO postgres;

--
-- TOC entry 365 (class 1259 OID 32196)
-- Name: ddmstructurelayout; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmstructurelayout (
    uuid_ character varying(75),
    structurelayoutid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    structureversionid bigint,
    definition text
);


ALTER TABLE ddmstructurelayout OWNER TO postgres;

--
-- TOC entry 366 (class 1259 OID 32204)
-- Name: ddmstructurelink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmstructurelink (
    structurelinkid bigint NOT NULL,
    companyid bigint,
    classnameid bigint,
    classpk bigint,
    structureid bigint
);


ALTER TABLE ddmstructurelink OWNER TO postgres;

--
-- TOC entry 367 (class 1259 OID 32209)
-- Name: ddmstructureversion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmstructureversion (
    structureversionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    structureid bigint,
    version character varying(75),
    parentstructureid bigint,
    name text,
    description text,
    definition text,
    storagetype character varying(75),
    type_ integer,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE ddmstructureversion OWNER TO postgres;

--
-- TOC entry 368 (class 1259 OID 32217)
-- Name: ddmtemplate; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmtemplate (
    uuid_ character varying(75),
    templateid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    versionuserid bigint,
    versionusername character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    resourceclassnameid bigint,
    templatekey character varying(75),
    version character varying(75),
    name text,
    description text,
    type_ character varying(75),
    mode_ character varying(75),
    language character varying(75),
    script text,
    cacheable boolean,
    smallimage boolean,
    smallimageid bigint,
    smallimageurl character varying(75),
    lastpublishdate timestamp without time zone
);


ALTER TABLE ddmtemplate OWNER TO postgres;

--
-- TOC entry 369 (class 1259 OID 32225)
-- Name: ddmtemplatelink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmtemplatelink (
    templatelinkid bigint NOT NULL,
    companyid bigint,
    classnameid bigint,
    classpk bigint,
    templateid bigint
);


ALTER TABLE ddmtemplatelink OWNER TO postgres;

--
-- TOC entry 370 (class 1259 OID 32230)
-- Name: ddmtemplateversion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ddmtemplateversion (
    templateversionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    templateid bigint,
    version character varying(75),
    name text,
    description text,
    language character varying(75),
    script text,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE ddmtemplateversion OWNER TO postgres;

--
-- TOC entry 416 (class 1259 OID 32788)
-- Name: dir_fs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dir_fs (
    id bigint NOT NULL,
    parent_id bigint,
    name text,
    size bigint DEFAULT 0,
    mode integer DEFAULT 0 NOT NULL,
    uid integer DEFAULT 0 NOT NULL,
    gid integer DEFAULT 0 NOT NULL,
    ctime timestamp without time zone,
    mtime timestamp without time zone,
    atime timestamp without time zone,
    uuid character varying(75) DEFAULT uuid_generate_v4()
);


ALTER TABLE dir_fs OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 30610)
-- Name: dlfileentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileentry (
    uuid_ character varying(75),
    fileentryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    repositoryid bigint,
    folderid bigint,
    treepath text,
    name character varying(255),
    filename character varying(255),
    extension character varying(75),
    mimetype character varying(75),
    title character varying(255),
    description text,
    extrasettings text,
    fileentrytypeid bigint,
    version character varying(75),
    size_ bigint,
    readcount integer,
    smallimageid bigint,
    largeimageid bigint,
    custom1imageid bigint,
    custom2imageid bigint,
    manualcheckinrequired boolean,
    lastpublishdate timestamp without time zone,
    accessdate timestamp without time zone DEFAULT ('now'::text)::timestamp without time zone,
    mode integer DEFAULT 33206,
    uid integer,
    gid integer,
    del integer DEFAULT 0
);


ALTER TABLE dlfileentry OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 30657)
-- Name: dlfolder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfolder (
    uuid_ character varying(75),
    folderid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    repositoryid bigint,
    mountpoint boolean,
    parentfolderid bigint,
    treepath text,
    name character varying(255),
    description text,
    lastpostdate timestamp without time zone,
    defaultfileentrytypeid bigint,
    hidden_ boolean,
    restrictiontype integer,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone,
    accessdate timestamp without time zone DEFAULT ('now'::text)::timestamp without time zone,
    mode integer DEFAULT 16895,
    size_ bigint DEFAULT 0,
    uid integer,
    gid integer
);


ALTER TABLE dlfolder OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 30676)
-- Name: expandocolumn; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expandocolumn (
    columnid bigint NOT NULL,
    companyid bigint,
    tableid bigint,
    name character varying(75),
    type_ integer,
    defaultdata text,
    typesettings text
);


ALTER TABLE expandocolumn OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 30694)
-- Name: expandovalue; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expandovalue (
    valueid bigint NOT NULL,
    companyid bigint,
    tableid bigint,
    columnid bigint,
    rowid_ bigint,
    classnameid bigint,
    classpk bigint,
    data_ text
);


ALTER TABLE expandovalue OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 30711)
-- Name: group_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE group_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    groupid bigint NOT NULL,
    companyid bigint,
    creatoruserid bigint,
    classnameid bigint,
    classpk bigint,
    parentgroupid bigint,
    livegroupid bigint,
    treepath text,
    groupkey character varying(150),
    name text,
    description text,
    type_ integer,
    typesettings text,
    manualmembership boolean,
    membershiprestriction integer,
    friendlyurl character varying(255),
    site boolean,
    remotestaginggroupcount integer,
    inheritcontent boolean,
    active_ boolean
);


ALTER TABLE group_ OWNER TO postgres;

--
-- TOC entry 430 (class 1259 OID 33130)
-- Name: dir; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW dir AS
 SELECT o.groupid AS id,
    group_parent_id(o.groupid) AS parent_id,
    group_descriptive_name(o.groupid) AS name,
    (0)::bigint AS size,
    16895 AS mode,
    0 AS uid,
    0 AS gid,
    (now())::timestamp without time zone AS ctime,
    (now())::timestamp without time zone AS mtime,
    (now())::timestamp without time zone AS atime
   FROM group_ o
  WHERE ((o.classnameid IN ( SELECT classname_.classnameid
           FROM classname_
          WHERE ((classname_.value)::text = ANY (ARRAY[('com.liferay.portal.kernel.model.Group'::character varying)::text, ('com.liferay.portal.kernel.model.User'::character varying)::text, ('com.liferay.portal.kernel.model.Organization'::character varying)::text])))) AND (NOT (o.groupid IN ( SELECT expandovalue.classpk
           FROM expandovalue
          WHERE (expandovalue.data_ = 'PROJECT_TMP'::text)))) AND (btrim(group_descriptive_name(o.groupid)) <> ''::text))
UNION
 SELECT d.folderid AS id,
        CASE
            WHEN (d.parentfolderid = 0) THEN d.groupid
            ELSE d.parentfolderid
        END AS parent_id,
    d.name,
    d.size_ AS size,
    d.mode,
    d.uid,
    d.gid,
    d.createdate AS ctime,
    d.modifieddate AS mtime,
    d.accessdate AS atime
   FROM dlfolder d
  WHERE ((d.hidden_ = false) AND ((d.name)::text !~~ '/%'::text))
UNION
 SELECT (ev.data_)::bigint AS id,
    ev.classpk AS parent_id,
    'Подпроекты'::text AS name,
    (0)::bigint AS size,
    16895 AS mode,
    0 AS uid,
    0 AS gid,
    (now())::timestamp without time zone AS ctime,
    (now())::timestamp without time zone AS mtime,
    (now())::timestamp without time zone AS atime
   FROM expandovalue ev
  WHERE (ev.columnid = ( SELECT expandocolumn.columnid
           FROM expandocolumn
          WHERE ((expandocolumn.name)::text = 'FOLDER_ID'::text)))
UNION
 SELECT f.fileentryid AS id,
        CASE
            WHEN (f.folderid = 0) THEN f.groupid
            ELSE f.folderid
        END AS parent_id,
        CASE
            WHEN ("position"(lower((f.title)::text), ('.'::text || (f.extension)::text)) = 0) THEN ((((f.title)::text || '.'::text) || (f.extension)::text))::character varying
            ELSE f.title
        END AS name,
    f.size_ AS size,
    f.mode,
    f.uid,
    f.gid,
    f.createdate AS ctime,
    f.modifieddate AS mtime,
    f.accessdate AS atime
   FROM dlfileentry f
  WHERE (((f.extension)::text <> ''::text) AND ((f.title)::text !~~ '/%'::text) AND (f.del = 0))
UNION
 SELECT l.id,
    l.parent_id,
    l.name,
    l.size,
    l.mode,
    l.uid,
    l.gid,
    l.ctime,
    l.mtime,
    l.atime
   FROM dir_fs l;


ALTER TABLE dir OWNER TO postgres;

--
-- TOC entry 415 (class 1259 OID 32786)
-- Name: dir_fs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE dir_fs_id_seq
    START WITH 1
    INCREMENT BY -1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1;


ALTER TABLE dir_fs_id_seq OWNER TO postgres;

--
-- TOC entry 4699 (class 0 OID 0)
-- Dependencies: 415
-- Name: dir_fs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE dir_fs_id_seq OWNED BY dir_fs.id;


--
-- TOC entry 227 (class 1259 OID 30603)
-- Name: dlcontent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlcontent (
    contentid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    repositoryid bigint,
    path_ character varying(255),
    version character varying(75),
    data_ oid,
    size_ bigint
);


ALTER TABLE dlcontent OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 30618)
-- Name: dlfileentrymetadata; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileentrymetadata (
    uuid_ character varying(75),
    fileentrymetadataid bigint NOT NULL,
    companyid bigint,
    ddmstorageid bigint,
    ddmstructureid bigint,
    fileentryid bigint,
    fileversionid bigint
);


ALTER TABLE dlfileentrymetadata OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 30623)
-- Name: dlfileentrytype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileentrytype (
    uuid_ character varying(75),
    fileentrytypeid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    fileentrytypekey character varying(75),
    name text,
    description text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE dlfileentrytype OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 30631)
-- Name: dlfileentrytypes_dlfolders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileentrytypes_dlfolders (
    companyid bigint NOT NULL,
    fileentrytypeid bigint NOT NULL,
    folderid bigint NOT NULL
);


ALTER TABLE dlfileentrytypes_dlfolders OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 30636)
-- Name: dlfilerank; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfilerank (
    filerankid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate timestamp without time zone,
    fileentryid bigint,
    active_ boolean
);


ALTER TABLE dlfilerank OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 30641)
-- Name: dlfileshortcut; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileshortcut (
    uuid_ character varying(75),
    fileshortcutid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    repositoryid bigint,
    folderid bigint,
    tofileentryid bigint,
    treepath text,
    active_ boolean,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE dlfileshortcut OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 30649)
-- Name: dlfileversion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlfileversion (
    uuid_ character varying(75),
    fileversionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    repositoryid bigint,
    folderid bigint,
    fileentryid bigint,
    treepath text,
    filename character varying(255),
    extension character varying(75),
    mimetype character varying(75),
    title character varying(255),
    description text,
    changelog character varying(75),
    extrasettings text,
    fileentrytypeid bigint,
    version character varying(75),
    size_ bigint,
    checksum character varying(75),
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE dlfileversion OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 30665)
-- Name: dlsyncevent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE dlsyncevent (
    synceventid bigint NOT NULL,
    companyid bigint,
    modifiedtime bigint,
    event character varying(75),
    type_ character varying(75),
    typepk bigint
);


ALTER TABLE dlsyncevent OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 30670)
-- Name: emailaddress; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE emailaddress (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    emailaddressid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    address character varying(75),
    typeid bigint,
    primary_ boolean
);


ALTER TABLE emailaddress OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 30684)
-- Name: expandorow; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expandorow (
    rowid_ bigint NOT NULL,
    companyid bigint,
    modifieddate timestamp without time zone,
    tableid bigint,
    classpk bigint
);


ALTER TABLE expandorow OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 30689)
-- Name: expandotable; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expandotable (
    tableid bigint NOT NULL,
    companyid bigint,
    classnameid bigint,
    name character varying(75)
);


ALTER TABLE expandotable OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 30702)
-- Name: exportimportconfiguration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE exportimportconfiguration (
    mvccversion bigint DEFAULT 0 NOT NULL,
    exportimportconfigurationid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(200),
    description text,
    type_ integer,
    settings_ text,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE exportimportconfiguration OWNER TO postgres;

--
-- TOC entry 427 (class 1259 OID 33049)
-- Name: gantt_finance_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE gantt_finance_seq
    START WITH 5000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gantt_finance_seq OWNER TO postgres;

--
-- TOC entry 428 (class 1259 OID 33051)
-- Name: gantt_finance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_finance (
    id bigint DEFAULT nextval('gantt_finance_seq'::regclass) NOT NULL,
    gantt_task_id bigint NOT NULL,
    sum numeric DEFAULT 0.00 NOT NULL
);


ALTER TABLE gantt_finance OWNER TO postgres;

--
-- TOC entry 429 (class 1259 OID 33066)
-- Name: gantt_finance_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_finance_status (
    id bigint DEFAULT nextval('gantt_finance_seq'::regclass) NOT NULL,
    gantt_finance_id bigint NOT NULL,
    status integer
);


ALTER TABLE gantt_finance_status OWNER TO postgres;

--
-- TOC entry 420 (class 1259 OID 32995)
-- Name: gantt_links_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE gantt_links_seq
    START WITH 5000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gantt_links_seq OWNER TO postgres;

--
-- TOC entry 421 (class 1259 OID 32997)
-- Name: gantt_links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_links (
    id bigint DEFAULT nextval('gantt_links_seq'::regclass) NOT NULL,
    source bigint NOT NULL,
    target bigint NOT NULL,
    type character varying(1) NOT NULL
);


ALTER TABLE gantt_links OWNER TO postgres;

--
-- TOC entry 424 (class 1259 OID 33020)
-- Name: gantt_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_roles (
    role_id bigint NOT NULL,
    role_type integer NOT NULL,
    role_name character varying(255) NOT NULL
);


ALTER TABLE gantt_roles OWNER TO postgres;

--
-- TOC entry 422 (class 1259 OID 33003)
-- Name: gantt_tasks_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE gantt_tasks_seq
    START WITH 5000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gantt_tasks_seq OWNER TO postgres;

--
-- TOC entry 423 (class 1259 OID 33005)
-- Name: gantt_tasks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_tasks (
    id bigint DEFAULT nextval('gantt_tasks_seq'::regclass) NOT NULL,
    text character varying(255) NOT NULL,
    start_date timestamp with time zone NOT NULL,
    duration bigint NOT NULL,
    progress double precision DEFAULT 0 NOT NULL,
    sortorder bigint NOT NULL,
    parent bigint NOT NULL,
    site_id bigint NOT NULL,
    definition character varying(2048),
    type character varying(255) NOT NULL,
    org_id bigint,
    contract character varying(255),
    status character varying(1) NOT NULL,
    folder_id bigint NOT NULL,
    sync_store boolean DEFAULT false
);


ALTER TABLE gantt_tasks OWNER TO postgres;

--
-- TOC entry 425 (class 1259 OID 33025)
-- Name: gantt_tasks_users_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE gantt_tasks_users_seq
    START WITH 5000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gantt_tasks_users_seq OWNER TO postgres;

--
-- TOC entry 426 (class 1259 OID 33027)
-- Name: gantt_tasks_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE gantt_tasks_users (
    id bigint DEFAULT nextval('gantt_tasks_users_seq'::regclass) NOT NULL,
    gantt_task_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    responsible boolean DEFAULT false NOT NULL
);


ALTER TABLE gantt_tasks_users OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 30720)
-- Name: groups_orgs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE groups_orgs (
    companyid bigint NOT NULL,
    groupid bigint NOT NULL,
    organizationid bigint NOT NULL
);


ALTER TABLE groups_orgs OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 30725)
-- Name: groups_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE groups_roles (
    companyid bigint NOT NULL,
    groupid bigint NOT NULL,
    roleid bigint NOT NULL
);


ALTER TABLE groups_roles OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 30730)
-- Name: groups_usergroups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE groups_usergroups (
    companyid bigint NOT NULL,
    groupid bigint NOT NULL,
    usergroupid bigint NOT NULL
);


ALTER TABLE groups_usergroups OWNER TO postgres;

--
-- TOC entry 431 (class 1259 OID 33225)
-- Name: iee_tmpl; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE iee_tmpl (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE iee_tmpl OWNER TO postgres;

--
-- TOC entry 432 (class 1259 OID 33230)
-- Name: iee_tmpl_folders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE iee_tmpl_folders (
    id bigint NOT NULL,
    tmpl_id bigint,
    name character varying(255) NOT NULL,
    parent_id bigint,
    required boolean DEFAULT false,
    inherit_perms boolean DEFAULT false
);


ALTER TABLE iee_tmpl_folders OWNER TO postgres;

--
-- TOC entry 433 (class 1259 OID 33247)
-- Name: iee_tmpl_folders_perms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE iee_tmpl_folders_perms (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    folder_id bigint,
    liferay character varying(255) NOT NULL,
    smb character varying(255) NOT NULL
);


ALTER TABLE iee_tmpl_folders_perms OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 30735)
-- Name: image; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE image (
    mvccversion bigint DEFAULT 0 NOT NULL,
    imageid bigint NOT NULL,
    companyid bigint,
    modifieddate timestamp without time zone,
    type_ character varying(75),
    height integer,
    width integer,
    size_ integer
);


ALTER TABLE image OWNER TO postgres;

--
-- TOC entry 347 (class 1259 OID 31985)
-- Name: journalarticle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalarticle (
    uuid_ character varying(75),
    id_ bigint NOT NULL,
    resourceprimkey bigint,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    folderid bigint,
    classnameid bigint,
    classpk bigint,
    treepath text,
    articleid character varying(75),
    version double precision,
    title text,
    urltitle character varying(150),
    description text,
    content text,
    ddmstructurekey character varying(75),
    ddmtemplatekey character varying(75),
    layoutuuid character varying(75),
    displaydate timestamp without time zone,
    expirationdate timestamp without time zone,
    reviewdate timestamp without time zone,
    indexable boolean,
    smallimage boolean,
    smallimageid bigint,
    smallimageurl text,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE journalarticle OWNER TO postgres;

--
-- TOC entry 348 (class 1259 OID 31993)
-- Name: journalarticleimage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalarticleimage (
    articleimageid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    articleid character varying(75),
    version double precision,
    elinstanceid character varying(75),
    elname character varying(75),
    languageid character varying(75),
    tempimage boolean
);


ALTER TABLE journalarticleimage OWNER TO postgres;

--
-- TOC entry 349 (class 1259 OID 31998)
-- Name: journalarticleresource; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalarticleresource (
    uuid_ character varying(75),
    resourceprimkey bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    articleid character varying(75)
);


ALTER TABLE journalarticleresource OWNER TO postgres;

--
-- TOC entry 350 (class 1259 OID 32003)
-- Name: journalcontentsearch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalcontentsearch (
    contentsearchid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    privatelayout boolean,
    layoutid bigint,
    portletid character varying(200),
    articleid character varying(75)
);


ALTER TABLE journalcontentsearch OWNER TO postgres;

--
-- TOC entry 351 (class 1259 OID 32008)
-- Name: journalfeed; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalfeed (
    uuid_ character varying(75),
    id_ bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    feedid character varying(75),
    name character varying(75),
    description text,
    ddmstructurekey character varying(75),
    ddmtemplatekey character varying(75),
    ddmrenderertemplatekey character varying(75),
    delta integer,
    orderbycol character varying(75),
    orderbytype character varying(75),
    targetlayoutfriendlyurl character varying(255),
    targetportletid character varying(200),
    contentfield character varying(75),
    feedformat character varying(75),
    feedversion double precision,
    lastpublishdate timestamp without time zone
);


ALTER TABLE journalfeed OWNER TO postgres;

--
-- TOC entry 352 (class 1259 OID 32016)
-- Name: journalfolder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE journalfolder (
    uuid_ character varying(75),
    folderid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentfolderid bigint,
    treepath text,
    name character varying(100),
    description text,
    restrictiontype integer,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE journalfolder OWNER TO postgres;

--
-- TOC entry 330 (class 1259 OID 31786)
-- Name: kaleoaction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleoaction (
    kaleoactionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    kaleonodename character varying(200),
    name character varying(200),
    description text,
    executiontype character varying(20),
    script text,
    scriptlanguage character varying(75),
    scriptrequiredcontexts text,
    priority integer
);


ALTER TABLE kaleoaction OWNER TO postgres;

--
-- TOC entry 331 (class 1259 OID 31794)
-- Name: kaleocondition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleocondition (
    kaleoconditionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleonodeid bigint,
    script text,
    scriptlanguage character varying(75),
    scriptrequiredcontexts text
);


ALTER TABLE kaleocondition OWNER TO postgres;

--
-- TOC entry 332 (class 1259 OID 31802)
-- Name: kaleodefinition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleodefinition (
    kaleodefinitionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(200),
    title text,
    description text,
    content text,
    version integer,
    active_ boolean,
    startkaleonodeid bigint
);


ALTER TABLE kaleodefinition OWNER TO postgres;

--
-- TOC entry 333 (class 1259 OID 31810)
-- Name: kaleoinstance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleoinstance (
    kaleoinstanceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleodefinitionname character varying(200),
    kaleodefinitionversion integer,
    rootkaleoinstancetokenid bigint,
    classname character varying(200),
    classpk bigint,
    completed boolean,
    completiondate timestamp without time zone,
    workflowcontext text
);


ALTER TABLE kaleoinstance OWNER TO postgres;

--
-- TOC entry 334 (class 1259 OID 31818)
-- Name: kaleoinstancetoken; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleoinstancetoken (
    kaleoinstancetokenid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleoinstanceid bigint,
    parentkaleoinstancetokenid bigint,
    currentkaleonodeid bigint,
    currentkaleonodename character varying(200),
    classname character varying(200),
    classpk bigint,
    completed boolean,
    completiondate timestamp without time zone
);


ALTER TABLE kaleoinstancetoken OWNER TO postgres;

--
-- TOC entry 335 (class 1259 OID 31826)
-- Name: kaleolog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleolog (
    kaleologid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    kaleoinstanceid bigint,
    kaleoinstancetokenid bigint,
    kaleotaskinstancetokenid bigint,
    kaleonodename character varying(200),
    terminalkaleonode boolean,
    kaleoactionid bigint,
    kaleoactionname character varying(200),
    kaleoactiondescription text,
    previouskaleonodeid bigint,
    previouskaleonodename character varying(200),
    previousassigneeclassname character varying(200),
    previousassigneeclasspk bigint,
    currentassigneeclassname character varying(200),
    currentassigneeclasspk bigint,
    type_ character varying(50),
    comment_ text,
    startdate timestamp without time zone,
    enddate timestamp without time zone,
    duration bigint,
    workflowcontext text
);


ALTER TABLE kaleolog OWNER TO postgres;

--
-- TOC entry 336 (class 1259 OID 31834)
-- Name: kaleonode; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleonode (
    kaleonodeid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    name character varying(200),
    metadata text,
    description text,
    type_ character varying(20),
    initial_ boolean,
    terminal boolean
);


ALTER TABLE kaleonode OWNER TO postgres;

--
-- TOC entry 337 (class 1259 OID 31842)
-- Name: kaleonotification; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleonotification (
    kaleonotificationid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    kaleonodename character varying(200),
    name character varying(200),
    description text,
    executiontype character varying(20),
    template text,
    templatelanguage character varying(75),
    notificationtypes character varying(25)
);


ALTER TABLE kaleonotification OWNER TO postgres;

--
-- TOC entry 338 (class 1259 OID 31850)
-- Name: kaleonotificationrecipient; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleonotificationrecipient (
    kaleonotificationrecipientid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleonotificationid bigint,
    recipientclassname character varying(200),
    recipientclasspk bigint,
    recipientroletype integer,
    recipientscript text,
    recipientscriptlanguage character varying(75),
    recipientscriptcontexts text,
    address character varying(255),
    notificationreceptiontype character varying(3)
);


ALTER TABLE kaleonotificationrecipient OWNER TO postgres;

--
-- TOC entry 339 (class 1259 OID 31858)
-- Name: kaleotask; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotask (
    kaleotaskid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleonodeid bigint,
    name character varying(200),
    description text
);


ALTER TABLE kaleotask OWNER TO postgres;

--
-- TOC entry 340 (class 1259 OID 31866)
-- Name: kaleotaskassignment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotaskassignment (
    kaleotaskassignmentid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    kaleonodeid bigint,
    assigneeclassname character varying(200),
    assigneeclasspk bigint,
    assigneeactionid character varying(75),
    assigneescript text,
    assigneescriptlanguage character varying(75),
    assigneescriptrequiredcontexts text
);


ALTER TABLE kaleotaskassignment OWNER TO postgres;

--
-- TOC entry 341 (class 1259 OID 31874)
-- Name: kaleotaskassignmentinstance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotaskassignmentinstance (
    kaleotaskassignmentinstanceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleoinstanceid bigint,
    kaleoinstancetokenid bigint,
    kaleotaskinstancetokenid bigint,
    kaleotaskid bigint,
    kaleotaskname character varying(200),
    assigneeclassname character varying(200),
    assigneeclasspk bigint,
    completed boolean,
    completiondate timestamp without time zone
);


ALTER TABLE kaleotaskassignmentinstance OWNER TO postgres;

--
-- TOC entry 342 (class 1259 OID 31882)
-- Name: kaleotaskinstancetoken; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotaskinstancetoken (
    kaleotaskinstancetokenid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleoinstanceid bigint,
    kaleoinstancetokenid bigint,
    kaleotaskid bigint,
    kaleotaskname character varying(200),
    classname character varying(200),
    classpk bigint,
    completionuserid bigint,
    completed boolean,
    completiondate timestamp without time zone,
    duedate timestamp without time zone,
    workflowcontext text
);


ALTER TABLE kaleotaskinstancetoken OWNER TO postgres;

--
-- TOC entry 343 (class 1259 OID 31890)
-- Name: kaleotimer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotimer (
    kaleotimerid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    name character varying(75),
    blocking boolean,
    description text,
    duration double precision,
    scale character varying(75),
    recurrenceduration double precision,
    recurrencescale character varying(75)
);


ALTER TABLE kaleotimer OWNER TO postgres;

--
-- TOC entry 344 (class 1259 OID 31898)
-- Name: kaleotimerinstancetoken; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotimerinstancetoken (
    kaleotimerinstancetokenid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleoclassname character varying(200),
    kaleoclasspk bigint,
    kaleodefinitionid bigint,
    kaleoinstanceid bigint,
    kaleoinstancetokenid bigint,
    kaleotaskinstancetokenid bigint,
    kaleotimerid bigint,
    kaleotimername character varying(200),
    blocking boolean,
    completionuserid bigint,
    completed boolean,
    completiondate timestamp without time zone,
    workflowcontext text
);


ALTER TABLE kaleotimerinstancetoken OWNER TO postgres;

--
-- TOC entry 345 (class 1259 OID 31906)
-- Name: kaleotransition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kaleotransition (
    kaleotransitionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(200),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    kaleodefinitionid bigint,
    kaleonodeid bigint,
    name character varying(200),
    description text,
    sourcekaleonodeid bigint,
    sourcekaleonodename character varying(200),
    targetkaleonodeid bigint,
    targetkaleonodename character varying(200),
    defaulttransition boolean
);


ALTER TABLE kaleotransition OWNER TO postgres;

--
-- TOC entry 384 (class 1259 OID 32422)
-- Name: kbarticle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kbarticle (
    uuid_ character varying(75),
    kbarticleid bigint NOT NULL,
    resourceprimkey bigint,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    rootresourceprimkey bigint,
    parentresourceclassnameid bigint,
    parentresourceprimkey bigint,
    kbfolderid bigint,
    version integer,
    title text,
    urltitle character varying(75),
    content text,
    description text,
    priority double precision,
    sections text,
    viewcount integer,
    latest boolean,
    main boolean,
    sourceurl text,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE kbarticle OWNER TO postgres;

--
-- TOC entry 385 (class 1259 OID 32430)
-- Name: kbcomment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kbcomment (
    uuid_ character varying(75),
    kbcommentid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    content text,
    userrating integer,
    lastpublishdate timestamp without time zone,
    status integer
);


ALTER TABLE kbcomment OWNER TO postgres;

--
-- TOC entry 386 (class 1259 OID 32438)
-- Name: kbfolder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kbfolder (
    uuid_ character varying(75),
    kbfolderid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentkbfolderid bigint,
    name character varying(75),
    urltitle character varying(75),
    description text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE kbfolder OWNER TO postgres;

--
-- TOC entry 387 (class 1259 OID 32446)
-- Name: kbtemplate; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE kbtemplate (
    uuid_ character varying(75),
    kbtemplateid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    title text,
    content text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE kbtemplate OWNER TO postgres;

--
-- TOC entry 248 (class 1259 OID 30741)
-- Name: layout; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layout (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    plid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    privatelayout boolean,
    layoutid bigint,
    parentlayoutid bigint,
    name text,
    title text,
    description text,
    keywords text,
    robots text,
    type_ character varying(75),
    typesettings text,
    hidden_ boolean,
    friendlyurl character varying(255),
    iconimageid bigint,
    themeid character varying(75),
    colorschemeid character varying(75),
    css text,
    priority integer,
    layoutprototypeuuid character varying(75),
    layoutprototypelinkenabled boolean,
    sourceprototypelayoutuuid character varying(75),
    lastpublishdate timestamp without time zone
);


ALTER TABLE layout OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 30750)
-- Name: layoutbranch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutbranch (
    mvccversion bigint DEFAULT 0 NOT NULL,
    layoutbranchid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    layoutsetbranchid bigint,
    plid bigint,
    name character varying(75),
    description text,
    master boolean
);


ALTER TABLE layoutbranch OWNER TO postgres;

--
-- TOC entry 250 (class 1259 OID 30759)
-- Name: layoutfriendlyurl; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutfriendlyurl (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    layoutfriendlyurlid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    plid bigint,
    privatelayout boolean,
    friendlyurl character varying(255),
    languageid character varying(75),
    lastpublishdate timestamp without time zone
);


ALTER TABLE layoutfriendlyurl OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 30768)
-- Name: layoutprototype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutprototype (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    layoutprototypeid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name text,
    description text,
    settings_ text,
    active_ boolean
);


ALTER TABLE layoutprototype OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 30777)
-- Name: layoutrevision; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutrevision (
    mvccversion bigint DEFAULT 0 NOT NULL,
    layoutrevisionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    layoutsetbranchid bigint,
    layoutbranchid bigint,
    parentlayoutrevisionid bigint,
    head boolean,
    major boolean,
    plid bigint,
    privatelayout boolean,
    name text,
    title text,
    description text,
    keywords text,
    robots text,
    typesettings text,
    iconimageid bigint,
    themeid character varying(75),
    colorschemeid character varying(75),
    css text,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE layoutrevision OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 30786)
-- Name: layoutset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutset (
    mvccversion bigint DEFAULT 0 NOT NULL,
    layoutsetid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    privatelayout boolean,
    logoid bigint,
    themeid character varying(75),
    colorschemeid character varying(75),
    css text,
    pagecount integer,
    settings_ text,
    layoutsetprototypeuuid character varying(75),
    layoutsetprototypelinkenabled boolean
);


ALTER TABLE layoutset OWNER TO postgres;

--
-- TOC entry 254 (class 1259 OID 30795)
-- Name: layoutsetbranch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutsetbranch (
    mvccversion bigint DEFAULT 0 NOT NULL,
    layoutsetbranchid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    privatelayout boolean,
    name character varying(75),
    description text,
    master boolean,
    logoid bigint,
    themeid character varying(75),
    colorschemeid character varying(75),
    css text,
    settings_ text,
    layoutsetprototypeuuid character varying(75),
    layoutsetprototypelinkenabled boolean
);


ALTER TABLE layoutsetbranch OWNER TO postgres;

--
-- TOC entry 255 (class 1259 OID 30804)
-- Name: layoutsetprototype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE layoutsetprototype (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    layoutsetprototypeid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name text,
    description text,
    settings_ text,
    active_ boolean
);


ALTER TABLE layoutsetprototype OWNER TO postgres;

--
-- TOC entry 256 (class 1259 OID 30813)
-- Name: listtype; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE listtype (
    mvccversion bigint DEFAULT 0 NOT NULL,
    listtypeid bigint NOT NULL,
    name character varying(75),
    type_ character varying(75)
);


ALTER TABLE listtype OWNER TO postgres;

--
-- TOC entry 329 (class 1259 OID 31774)
-- Name: lock_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE lock_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    lockid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    classname character varying(75),
    key_ character varying(200),
    owner character varying(1024),
    inheritable boolean,
    expirationdate timestamp without time zone
);


ALTER TABLE lock_ OWNER TO postgres;

--
-- TOC entry 407 (class 1259 OID 32697)
-- Name: mail_account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mail_account (
    accountid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    address character varying(75),
    personalname character varying(75),
    protocol character varying(75),
    incominghostname character varying(75),
    incomingport integer,
    incomingsecure boolean,
    outgoinghostname character varying(75),
    outgoingport integer,
    outgoingsecure boolean,
    login character varying(75),
    password_ character varying(75),
    savepassword boolean,
    signature character varying(75),
    usesignature boolean,
    folderprefix character varying(75),
    inboxfolderid bigint,
    draftfolderid bigint,
    sentfolderid bigint,
    trashfolderid bigint,
    defaultsender boolean
);


ALTER TABLE mail_account OWNER TO postgres;

--
-- TOC entry 408 (class 1259 OID 32705)
-- Name: mail_attachment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mail_attachment (
    attachmentid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    accountid bigint,
    folderid bigint,
    messageid bigint,
    contentpath character varying(75),
    filename character varying(75),
    size_ bigint
);


ALTER TABLE mail_attachment OWNER TO postgres;

--
-- TOC entry 409 (class 1259 OID 32710)
-- Name: mail_folder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mail_folder (
    folderid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    accountid bigint,
    fullname character varying(75),
    displayname character varying(75),
    remotemessagecount integer
);


ALTER TABLE mail_folder OWNER TO postgres;

--
-- TOC entry 410 (class 1259 OID 32715)
-- Name: mail_message; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mail_message (
    messageid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    accountid bigint,
    folderid bigint,
    sender text,
    to_ text,
    cc text,
    bcc text,
    sentdate timestamp without time zone,
    subject text,
    preview character varying(75),
    body text,
    flags character varying(75),
    size_ bigint,
    remotemessageid bigint,
    contenttype character varying(75)
);


ALTER TABLE mail_message OWNER TO postgres;

--
-- TOC entry 372 (class 1259 OID 32303)
-- Name: marketplace_app; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE marketplace_app (
    uuid_ character varying(75),
    appid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    remoteappid bigint,
    title character varying(75),
    description text,
    category character varying(75),
    iconurl text,
    version character varying(75),
    required boolean
);


ALTER TABLE marketplace_app OWNER TO postgres;

--
-- TOC entry 373 (class 1259 OID 32311)
-- Name: marketplace_module; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE marketplace_module (
    uuid_ character varying(75),
    moduleid bigint NOT NULL,
    appid bigint,
    bundlesymbolicname character varying(500),
    bundleversion character varying(75),
    contextname character varying(75)
);


ALTER TABLE marketplace_module OWNER TO postgres;

--
-- TOC entry 257 (class 1259 OID 30819)
-- Name: mbban; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbban (
    uuid_ character varying(75),
    banid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    banuserid bigint,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mbban OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 30824)
-- Name: mbcategory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbcategory (
    uuid_ character varying(75),
    categoryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentcategoryid bigint,
    name character varying(75),
    description text,
    displaystyle character varying(75),
    threadcount integer,
    messagecount integer,
    lastpostdate timestamp without time zone,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE mbcategory OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 30832)
-- Name: mbdiscussion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbdiscussion (
    uuid_ character varying(75),
    discussionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    threadid bigint,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mbdiscussion OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 30837)
-- Name: mbmailinglist; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbmailinglist (
    uuid_ character varying(75),
    mailinglistid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    categoryid bigint,
    emailaddress character varying(75),
    inprotocol character varying(75),
    inservername character varying(75),
    inserverport integer,
    inusessl boolean,
    inusername character varying(75),
    inpassword character varying(75),
    inreadinterval integer,
    outemailaddress character varying(75),
    outcustom boolean,
    outservername character varying(75),
    outserverport integer,
    outusessl boolean,
    outusername character varying(75),
    outpassword character varying(75),
    allowanonymous boolean,
    active_ boolean
);


ALTER TABLE mbmailinglist OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 30845)
-- Name: mbmessage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbmessage (
    uuid_ character varying(75),
    messageid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    categoryid bigint,
    threadid bigint,
    rootmessageid bigint,
    parentmessageid bigint,
    subject character varying(75),
    body text,
    format character varying(75),
    anonymous boolean,
    priority double precision,
    allowpingbacks boolean,
    answer boolean,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE mbmessage OWNER TO postgres;

--
-- TOC entry 262 (class 1259 OID 30853)
-- Name: mbstatsuser; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbstatsuser (
    statsuserid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    messagecount integer,
    lastpostdate timestamp without time zone
);


ALTER TABLE mbstatsuser OWNER TO postgres;

--
-- TOC entry 263 (class 1259 OID 30858)
-- Name: mbthread; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbthread (
    uuid_ character varying(75),
    threadid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    categoryid bigint,
    rootmessageid bigint,
    rootmessageuserid bigint,
    messagecount integer,
    viewcount integer,
    lastpostbyuserid bigint,
    lastpostdate timestamp without time zone,
    priority double precision,
    question boolean,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE mbthread OWNER TO postgres;

--
-- TOC entry 264 (class 1259 OID 30863)
-- Name: mbthreadflag; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mbthreadflag (
    uuid_ character varying(75),
    threadflagid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    threadid bigint,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mbthreadflag OWNER TO postgres;

--
-- TOC entry 356 (class 1259 OID 32119)
-- Name: mdraction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mdraction (
    uuid_ character varying(75),
    actionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    rulegroupinstanceid bigint,
    name text,
    description text,
    type_ character varying(255),
    typesettings text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mdraction OWNER TO postgres;

--
-- TOC entry 357 (class 1259 OID 32127)
-- Name: mdrrule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mdrrule (
    uuid_ character varying(75),
    ruleid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    rulegroupid bigint,
    name text,
    description text,
    type_ character varying(255),
    typesettings text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mdrrule OWNER TO postgres;

--
-- TOC entry 358 (class 1259 OID 32135)
-- Name: mdrrulegroup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mdrrulegroup (
    uuid_ character varying(75),
    rulegroupid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name text,
    description text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mdrrulegroup OWNER TO postgres;

--
-- TOC entry 359 (class 1259 OID 32143)
-- Name: mdrrulegroupinstance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE mdrrulegroupinstance (
    uuid_ character varying(75),
    rulegroupinstanceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    rulegroupid bigint,
    priority integer,
    lastpublishdate timestamp without time zone
);


ALTER TABLE mdrrulegroupinstance OWNER TO postgres;

--
-- TOC entry 265 (class 1259 OID 30868)
-- Name: membershiprequest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE membershiprequest (
    mvccversion bigint DEFAULT 0 NOT NULL,
    membershiprequestid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate timestamp without time zone,
    comments text,
    replycomments text,
    replydate timestamp without time zone,
    replieruserid bigint,
    statusid bigint
);


ALTER TABLE membershiprequest OWNER TO postgres;

--
-- TOC entry 411 (class 1259 OID 32728)
-- Name: microblogsentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE microblogsentry (
    microblogsentryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    creatorclassnameid bigint,
    creatorclasspk bigint,
    content text,
    type_ integer,
    parentmicroblogsentryid bigint,
    socialrelationtype integer
);


ALTER TABLE microblogsentry OWNER TO postgres;

--
-- TOC entry 412 (class 1259 OID 32746)
-- Name: opensocial_gadget; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE opensocial_gadget (
    uuid_ character varying(75),
    gadgetid bigint NOT NULL,
    companyid bigint,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(75),
    url text,
    portletcategorynames text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE opensocial_gadget OWNER TO postgres;

--
-- TOC entry 413 (class 1259 OID 32754)
-- Name: opensocial_oauthconsumer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE opensocial_oauthconsumer (
    oauthconsumerid bigint NOT NULL,
    companyid bigint,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    gadgetkey character varying(75),
    servicename character varying(75),
    consumerkey character varying(75),
    consumersecret text,
    keytype character varying(75)
);


ALTER TABLE opensocial_oauthconsumer OWNER TO postgres;

--
-- TOC entry 414 (class 1259 OID 32762)
-- Name: opensocial_oauthtoken; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE opensocial_oauthtoken (
    oauthtokenid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    gadgetkey character varying(75),
    servicename character varying(75),
    moduleid bigint,
    accesstoken character varying(75),
    tokenname character varying(75),
    tokensecret character varying(75),
    sessionhandle character varying(75),
    expiration bigint
);


ALTER TABLE opensocial_oauthtoken OWNER TO postgres;

--
-- TOC entry 266 (class 1259 OID 30877)
-- Name: organization_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE organization_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    organizationid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentorganizationid bigint,
    treepath text,
    name character varying(100),
    type_ character varying(75),
    recursable boolean,
    regionid bigint,
    countryid bigint,
    statusid bigint,
    comments text,
    logoid bigint
);


ALTER TABLE organization_ OWNER TO postgres;

--
-- TOC entry 267 (class 1259 OID 30886)
-- Name: orggrouprole; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE orggrouprole (
    mvccversion bigint DEFAULT 0 NOT NULL,
    organizationid bigint NOT NULL,
    groupid bigint NOT NULL,
    roleid bigint NOT NULL,
    companyid bigint
);


ALTER TABLE orggrouprole OWNER TO postgres;

--
-- TOC entry 268 (class 1259 OID 30892)
-- Name: orglabor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE orglabor (
    mvccversion bigint DEFAULT 0 NOT NULL,
    orglaborid bigint NOT NULL,
    companyid bigint,
    organizationid bigint,
    typeid bigint,
    sunopen integer,
    sunclose integer,
    monopen integer,
    monclose integer,
    tueopen integer,
    tueclose integer,
    wedopen integer,
    wedclose integer,
    thuopen integer,
    thuclose integer,
    friopen integer,
    friclose integer,
    satopen integer,
    satclose integer
);


ALTER TABLE orglabor OWNER TO postgres;

--
-- TOC entry 269 (class 1259 OID 30898)
-- Name: passwordpolicy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE passwordpolicy (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    passwordpolicyid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    defaultpolicy boolean,
    name character varying(75),
    description text,
    changeable boolean,
    changerequired boolean,
    minage bigint,
    checksyntax boolean,
    allowdictionarywords boolean,
    minalphanumeric integer,
    minlength integer,
    minlowercase integer,
    minnumbers integer,
    minsymbols integer,
    minuppercase integer,
    regex character varying(75),
    history boolean,
    historycount integer,
    expireable boolean,
    maxage bigint,
    warningtime bigint,
    gracelimit integer,
    lockout boolean,
    maxfailure integer,
    lockoutduration bigint,
    requireunlock boolean,
    resetfailurecount bigint,
    resetticketmaxage bigint
);


ALTER TABLE passwordpolicy OWNER TO postgres;

--
-- TOC entry 270 (class 1259 OID 30907)
-- Name: passwordpolicyrel; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE passwordpolicyrel (
    mvccversion bigint DEFAULT 0 NOT NULL,
    passwordpolicyrelid bigint NOT NULL,
    companyid bigint,
    passwordpolicyid bigint,
    classnameid bigint,
    classpk bigint
);


ALTER TABLE passwordpolicyrel OWNER TO postgres;

--
-- TOC entry 271 (class 1259 OID 30913)
-- Name: passwordtracker; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE passwordtracker (
    mvccversion bigint DEFAULT 0 NOT NULL,
    passwordtrackerid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    createdate timestamp without time zone,
    password_ character varying(75)
);


ALTER TABLE passwordtracker OWNER TO postgres;

--
-- TOC entry 272 (class 1259 OID 30919)
-- Name: phone; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE phone (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    phoneid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    number_ character varying(75),
    extension character varying(75),
    typeid bigint,
    primary_ boolean
);


ALTER TABLE phone OWNER TO postgres;

--
-- TOC entry 273 (class 1259 OID 30925)
-- Name: pluginsetting; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pluginsetting (
    mvccversion bigint DEFAULT 0 NOT NULL,
    pluginsettingid bigint NOT NULL,
    companyid bigint,
    pluginid character varying(75),
    plugintype character varying(75),
    roles text,
    active_ boolean
);


ALTER TABLE pluginsetting OWNER TO postgres;

--
-- TOC entry 391 (class 1259 OID 32524)
-- Name: pm_userthread; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pm_userthread (
    userthreadid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    mbthreadid bigint,
    topmbmessageid bigint,
    read_ boolean,
    deleted boolean
);


ALTER TABLE pm_userthread OWNER TO postgres;

--
-- TOC entry 400 (class 1259 OID 32611)
-- Name: pollschoice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pollschoice (
    uuid_ character varying(75),
    choiceid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    questionid bigint,
    name character varying(75),
    description text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE pollschoice OWNER TO postgres;

--
-- TOC entry 401 (class 1259 OID 32619)
-- Name: pollsquestion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pollsquestion (
    uuid_ character varying(75),
    questionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    title text,
    description text,
    expirationdate timestamp without time zone,
    lastpublishdate timestamp without time zone,
    lastvotedate timestamp without time zone
);


ALTER TABLE pollsquestion OWNER TO postgres;

--
-- TOC entry 402 (class 1259 OID 32627)
-- Name: pollsvote; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pollsvote (
    uuid_ character varying(75),
    voteid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    questionid bigint,
    choiceid bigint,
    lastpublishdate timestamp without time zone,
    votedate timestamp without time zone
);


ALTER TABLE pollsvote OWNER TO postgres;

--
-- TOC entry 274 (class 1259 OID 30934)
-- Name: portalpreferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE portalpreferences (
    mvccversion bigint DEFAULT 0 NOT NULL,
    portalpreferencesid bigint NOT NULL,
    ownerid bigint,
    ownertype integer,
    preferences text
);


ALTER TABLE portalpreferences OWNER TO postgres;

--
-- TOC entry 275 (class 1259 OID 30943)
-- Name: portlet; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE portlet (
    mvccversion bigint DEFAULT 0 NOT NULL,
    id_ bigint NOT NULL,
    companyid bigint,
    portletid character varying(200),
    roles text,
    active_ boolean
);


ALTER TABLE portlet OWNER TO postgres;

--
-- TOC entry 276 (class 1259 OID 30952)
-- Name: portletitem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE portletitem (
    mvccversion bigint DEFAULT 0 NOT NULL,
    portletitemid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(75),
    portletid character varying(200),
    classnameid bigint
);


ALTER TABLE portletitem OWNER TO postgres;

--
-- TOC entry 277 (class 1259 OID 30958)
-- Name: portletpreferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE portletpreferences (
    mvccversion bigint DEFAULT 0 NOT NULL,
    portletpreferencesid bigint NOT NULL,
    companyid bigint,
    ownerid bigint,
    ownertype integer,
    plid bigint,
    portletid character varying(200),
    preferences text
);


ALTER TABLE portletpreferences OWNER TO postgres;

--
-- TOC entry 371 (class 1259 OID 32293)
-- Name: pushnotificationsdevice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE pushnotificationsdevice (
    pushnotificationsdeviceid bigint NOT NULL,
    userid bigint,
    createdate timestamp without time zone,
    platform character varying(75),
    token text
);


ALTER TABLE pushnotificationsdevice OWNER TO postgres;

--
-- TOC entry 193 (class 1259 OID 30353)
-- Name: quartz_blob_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_blob_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    blob_data bytea
);


ALTER TABLE quartz_blob_triggers OWNER TO postgres;

--
-- TOC entry 194 (class 1259 OID 30361)
-- Name: quartz_calendars; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_calendars (
    sched_name character varying(120) NOT NULL,
    calendar_name character varying(200) NOT NULL,
    calendar bytea NOT NULL
);


ALTER TABLE quartz_calendars OWNER TO postgres;

--
-- TOC entry 195 (class 1259 OID 30369)
-- Name: quartz_cron_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_cron_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    cron_expression character varying(200) NOT NULL,
    time_zone_id character varying(80)
);


ALTER TABLE quartz_cron_triggers OWNER TO postgres;

--
-- TOC entry 196 (class 1259 OID 30377)
-- Name: quartz_fired_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_fired_triggers (
    sched_name character varying(120) NOT NULL,
    entry_id character varying(95) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    instance_name character varying(200) NOT NULL,
    fired_time bigint NOT NULL,
    priority integer NOT NULL,
    state character varying(16) NOT NULL,
    job_name character varying(200),
    job_group character varying(200),
    is_nonconcurrent boolean,
    requests_recovery boolean
);


ALTER TABLE quartz_fired_triggers OWNER TO postgres;

--
-- TOC entry 197 (class 1259 OID 30385)
-- Name: quartz_job_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_job_details (
    sched_name character varying(120) NOT NULL,
    job_name character varying(200) NOT NULL,
    job_group character varying(200) NOT NULL,
    description character varying(250),
    job_class_name character varying(250) NOT NULL,
    is_durable boolean NOT NULL,
    is_nonconcurrent boolean NOT NULL,
    is_update_data boolean NOT NULL,
    requests_recovery boolean NOT NULL,
    job_data bytea
);


ALTER TABLE quartz_job_details OWNER TO postgres;

--
-- TOC entry 198 (class 1259 OID 30393)
-- Name: quartz_locks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_locks (
    sched_name character varying(120) NOT NULL,
    lock_name character varying(40) NOT NULL
);


ALTER TABLE quartz_locks OWNER TO postgres;

--
-- TOC entry 199 (class 1259 OID 30398)
-- Name: quartz_paused_trigger_grps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_paused_trigger_grps (
    sched_name character varying(120) NOT NULL,
    trigger_group character varying(200) NOT NULL
);


ALTER TABLE quartz_paused_trigger_grps OWNER TO postgres;

--
-- TOC entry 200 (class 1259 OID 30403)
-- Name: quartz_scheduler_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_scheduler_state (
    sched_name character varying(120) NOT NULL,
    instance_name character varying(200) NOT NULL,
    last_checkin_time bigint NOT NULL,
    checkin_interval bigint NOT NULL
);


ALTER TABLE quartz_scheduler_state OWNER TO postgres;

--
-- TOC entry 201 (class 1259 OID 30408)
-- Name: quartz_simple_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_simple_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    repeat_count bigint NOT NULL,
    repeat_interval bigint NOT NULL,
    times_triggered bigint NOT NULL
);


ALTER TABLE quartz_simple_triggers OWNER TO postgres;

--
-- TOC entry 202 (class 1259 OID 30416)
-- Name: quartz_simprop_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_simprop_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    str_prop_1 character varying(512),
    str_prop_2 character varying(512),
    str_prop_3 character varying(512),
    int_prop_1 integer,
    int_prop_2 integer,
    long_prop_1 bigint,
    long_prop_2 bigint,
    dec_prop_1 numeric(13,4),
    dec_prop_2 numeric(13,4),
    bool_prop_1 boolean,
    bool_prop_2 boolean
);


ALTER TABLE quartz_simprop_triggers OWNER TO postgres;

--
-- TOC entry 203 (class 1259 OID 30424)
-- Name: quartz_triggers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE quartz_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    job_name character varying(200) NOT NULL,
    job_group character varying(200) NOT NULL,
    description character varying(250),
    next_fire_time bigint,
    prev_fire_time bigint,
    priority integer,
    trigger_state character varying(16) NOT NULL,
    trigger_type character varying(8) NOT NULL,
    start_time bigint NOT NULL,
    end_time bigint,
    calendar_name character varying(200),
    misfire_instr integer,
    job_data bytea
);


ALTER TABLE quartz_triggers OWNER TO postgres;

--
-- TOC entry 278 (class 1259 OID 30967)
-- Name: ratingsentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ratingsentry (
    uuid_ character varying(75),
    entryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    score double precision
);


ALTER TABLE ratingsentry OWNER TO postgres;

--
-- TOC entry 279 (class 1259 OID 30972)
-- Name: ratingsstats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ratingsstats (
    statsid bigint NOT NULL,
    companyid bigint,
    classnameid bigint,
    classpk bigint,
    totalentries integer,
    totalscore double precision,
    averagescore double precision
);


ALTER TABLE ratingsstats OWNER TO postgres;

--
-- TOC entry 280 (class 1259 OID 30977)
-- Name: recentlayoutbranch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE recentlayoutbranch (
    mvccversion bigint DEFAULT 0 NOT NULL,
    recentlayoutbranchid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    layoutbranchid bigint,
    layoutsetbranchid bigint,
    plid bigint
);


ALTER TABLE recentlayoutbranch OWNER TO postgres;

--
-- TOC entry 281 (class 1259 OID 30983)
-- Name: recentlayoutrevision; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE recentlayoutrevision (
    mvccversion bigint DEFAULT 0 NOT NULL,
    recentlayoutrevisionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    layoutrevisionid bigint,
    layoutsetbranchid bigint,
    plid bigint
);


ALTER TABLE recentlayoutrevision OWNER TO postgres;

--
-- TOC entry 282 (class 1259 OID 30989)
-- Name: recentlayoutsetbranch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE recentlayoutsetbranch (
    mvccversion bigint DEFAULT 0 NOT NULL,
    recentlayoutsetbranchid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    layoutsetbranchid bigint,
    layoutsetid bigint
);


ALTER TABLE recentlayoutsetbranch OWNER TO postgres;

--
-- TOC entry 283 (class 1259 OID 30995)
-- Name: region; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE region (
    mvccversion bigint DEFAULT 0 NOT NULL,
    regionid bigint NOT NULL,
    countryid bigint,
    regioncode character varying(75),
    name character varying(75),
    active_ boolean
);


ALTER TABLE region OWNER TO postgres;

--
-- TOC entry 284 (class 1259 OID 31001)
-- Name: release_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE release_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    releaseid bigint NOT NULL,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    servletcontextname character varying(75),
    schemaversion character varying(75),
    buildnumber integer,
    builddate timestamp without time zone,
    verified boolean,
    state_ integer,
    teststring character varying(1024)
);


ALTER TABLE release_ OWNER TO postgres;

--
-- TOC entry 285 (class 1259 OID 31010)
-- Name: repository; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE repository (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    repositoryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    name character varying(75),
    description text,
    portletid character varying(200),
    typesettings text,
    dlfolderid bigint,
    lastpublishdate timestamp without time zone
);


ALTER TABLE repository OWNER TO postgres;

--
-- TOC entry 286 (class 1259 OID 31019)
-- Name: repositoryentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE repositoryentry (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    repositoryentryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    repositoryid bigint,
    mappedid character varying(255),
    manualcheckinrequired boolean,
    lastpublishdate timestamp without time zone
);


ALTER TABLE repositoryentry OWNER TO postgres;

--
-- TOC entry 287 (class 1259 OID 31025)
-- Name: resourceaction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE resourceaction (
    mvccversion bigint DEFAULT 0 NOT NULL,
    resourceactionid bigint NOT NULL,
    name character varying(255),
    actionid character varying(75),
    bitwisevalue bigint
);


ALTER TABLE resourceaction OWNER TO postgres;

--
-- TOC entry 288 (class 1259 OID 31031)
-- Name: resourceblock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE resourceblock (
    mvccversion bigint DEFAULT 0 NOT NULL,
    resourceblockid bigint NOT NULL,
    companyid bigint,
    groupid bigint,
    name character varying(75),
    permissionshash character varying(75),
    referencecount bigint
);


ALTER TABLE resourceblock OWNER TO postgres;

--
-- TOC entry 289 (class 1259 OID 31037)
-- Name: resourceblockpermission; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE resourceblockpermission (
    mvccversion bigint DEFAULT 0 NOT NULL,
    resourceblockpermissionid bigint NOT NULL,
    companyid bigint,
    resourceblockid bigint,
    roleid bigint,
    actionids bigint
);


ALTER TABLE resourceblockpermission OWNER TO postgres;

--
-- TOC entry 290 (class 1259 OID 31043)
-- Name: resourcepermission; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE resourcepermission (
    mvccversion bigint DEFAULT 0 NOT NULL,
    resourcepermissionid bigint NOT NULL,
    companyid bigint,
    name character varying(255),
    scope integer,
    primkey character varying(255),
    primkeyid bigint,
    roleid bigint,
    ownerid bigint,
    actionids bigint,
    viewactionid boolean
);


ALTER TABLE resourcepermission OWNER TO postgres;

--
-- TOC entry 291 (class 1259 OID 31052)
-- Name: resourcetypepermission; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE resourcetypepermission (
    mvccversion bigint DEFAULT 0 NOT NULL,
    resourcetypepermissionid bigint NOT NULL,
    companyid bigint,
    groupid bigint,
    name character varying(75),
    roleid bigint,
    actionids bigint
);


ALTER TABLE resourcetypepermission OWNER TO postgres;

--
-- TOC entry 292 (class 1259 OID 31058)
-- Name: role_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE role_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    roleid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    name character varying(75),
    title text,
    description text,
    type_ integer,
    subtype character varying(75)
);


ALTER TABLE role_ OWNER TO postgres;

--
-- TOC entry 328 (class 1259 OID 31763)
-- Name: sapentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE sapentry (
    uuid_ character varying(75),
    sapentryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    allowedservicesignatures text,
    defaultsapentry boolean,
    enabled boolean,
    name character varying(75),
    title text
);


ALTER TABLE sapentry OWNER TO postgres;

--
-- TOC entry 293 (class 1259 OID 31067)
-- Name: servicecomponent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE servicecomponent (
    mvccversion bigint DEFAULT 0 NOT NULL,
    servicecomponentid bigint NOT NULL,
    buildnamespace character varying(75),
    buildnumber bigint,
    builddate bigint,
    data_ text
);


ALTER TABLE servicecomponent OWNER TO postgres;

--
-- TOC entry 392 (class 1259 OID 32533)
-- Name: shoppingcart; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingcart (
    cartid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    itemids text,
    couponcodes character varying(75),
    altshipping integer,
    insure boolean
);


ALTER TABLE shoppingcart OWNER TO postgres;

--
-- TOC entry 393 (class 1259 OID 32541)
-- Name: shoppingcategory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingcategory (
    categoryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentcategoryid bigint,
    name character varying(75),
    description text
);


ALTER TABLE shoppingcategory OWNER TO postgres;

--
-- TOC entry 394 (class 1259 OID 32549)
-- Name: shoppingcoupon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingcoupon (
    couponid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    code_ character varying(75),
    name character varying(75),
    description text,
    startdate timestamp without time zone,
    enddate timestamp without time zone,
    active_ boolean,
    limitcategories text,
    limitskus text,
    minorder double precision,
    discount double precision,
    discounttype character varying(75)
);


ALTER TABLE shoppingcoupon OWNER TO postgres;

--
-- TOC entry 395 (class 1259 OID 32557)
-- Name: shoppingitem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingitem (
    itemid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    categoryid bigint,
    sku character varying(75),
    name character varying(200),
    description text,
    properties text,
    fields_ boolean,
    fieldsquantities text,
    minquantity integer,
    maxquantity integer,
    price double precision,
    discount double precision,
    taxable boolean,
    shipping double precision,
    useshippingformula boolean,
    requiresshipping boolean,
    stockquantity integer,
    featured_ boolean,
    sale_ boolean,
    smallimage boolean,
    smallimageid bigint,
    smallimageurl text,
    mediumimage boolean,
    mediumimageid bigint,
    mediumimageurl text,
    largeimage boolean,
    largeimageid bigint,
    largeimageurl text
);


ALTER TABLE shoppingitem OWNER TO postgres;

--
-- TOC entry 396 (class 1259 OID 32565)
-- Name: shoppingitemfield; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingitemfield (
    itemfieldid bigint NOT NULL,
    companyid bigint,
    itemid bigint,
    name character varying(75),
    values_ text,
    description text
);


ALTER TABLE shoppingitemfield OWNER TO postgres;

--
-- TOC entry 397 (class 1259 OID 32573)
-- Name: shoppingitemprice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingitemprice (
    itempriceid bigint NOT NULL,
    companyid bigint,
    itemid bigint,
    minquantity integer,
    maxquantity integer,
    price double precision,
    discount double precision,
    taxable boolean,
    shipping double precision,
    useshippingformula boolean,
    status integer
);


ALTER TABLE shoppingitemprice OWNER TO postgres;

--
-- TOC entry 398 (class 1259 OID 32578)
-- Name: shoppingorder; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingorder (
    orderid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    number_ character varying(75),
    tax double precision,
    shipping double precision,
    altshipping character varying(75),
    requiresshipping boolean,
    insure boolean,
    insurance double precision,
    couponcodes character varying(75),
    coupondiscount double precision,
    billingfirstname character varying(75),
    billinglastname character varying(75),
    billingemailaddress character varying(75),
    billingcompany character varying(75),
    billingstreet character varying(75),
    billingcity character varying(75),
    billingstate character varying(75),
    billingzip character varying(75),
    billingcountry character varying(75),
    billingphone character varying(75),
    shiptobilling boolean,
    shippingfirstname character varying(75),
    shippinglastname character varying(75),
    shippingemailaddress character varying(75),
    shippingcompany character varying(75),
    shippingstreet character varying(75),
    shippingcity character varying(75),
    shippingstate character varying(75),
    shippingzip character varying(75),
    shippingcountry character varying(75),
    shippingphone character varying(75),
    ccname character varying(75),
    cctype character varying(75),
    ccnumber character varying(75),
    ccexpmonth integer,
    ccexpyear integer,
    ccvernumber character varying(75),
    comments text,
    pptxnid character varying(75),
    pppaymentstatus character varying(75),
    pppaymentgross double precision,
    ppreceiveremail character varying(75),
    pppayeremail character varying(75),
    sendorderemail boolean,
    sendshippingemail boolean
);


ALTER TABLE shoppingorder OWNER TO postgres;

--
-- TOC entry 399 (class 1259 OID 32586)
-- Name: shoppingorderitem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE shoppingorderitem (
    orderitemid bigint NOT NULL,
    companyid bigint,
    orderid bigint,
    itemid text,
    sku character varying(75),
    name character varying(200),
    description text,
    properties text,
    price double precision,
    quantity integer,
    shippeddate timestamp without time zone
);


ALTER TABLE shoppingorderitem OWNER TO postgres;

--
-- TOC entry 381 (class 1259 OID 32401)
-- Name: sn_meetupsentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE sn_meetupsentry (
    meetupsentryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    title character varying(75),
    description character varying(75),
    startdate timestamp without time zone,
    enddate timestamp without time zone,
    totalattendees integer,
    maxattendees integer,
    price double precision,
    thumbnailid bigint
);


ALTER TABLE sn_meetupsentry OWNER TO postgres;

--
-- TOC entry 382 (class 1259 OID 32406)
-- Name: sn_meetupsregistration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE sn_meetupsregistration (
    meetupsregistrationid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    meetupsentryid bigint,
    status integer,
    comments character varying(75)
);


ALTER TABLE sn_meetupsregistration OWNER TO postgres;

--
-- TOC entry 383 (class 1259 OID 32411)
-- Name: sn_wallentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE sn_wallentry (
    wallentryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    comments character varying(75)
);


ALTER TABLE sn_wallentry OWNER TO postgres;

--
-- TOC entry 376 (class 1259 OID 32357)
-- Name: so_memberrequest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE so_memberrequest (
    memberrequestid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    key_ character varying(75),
    receiveruserid bigint,
    invitedroleid bigint,
    invitedteamid bigint,
    status integer
);


ALTER TABLE so_memberrequest OWNER TO postgres;

--
-- TOC entry 294 (class 1259 OID 31076)
-- Name: socialactivity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivity (
    activityid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate bigint,
    activitysetid bigint,
    mirroractivityid bigint,
    classnameid bigint,
    classpk bigint,
    parentclassnameid bigint,
    parentclasspk bigint,
    type_ integer,
    extradata text,
    receiveruserid bigint
);


ALTER TABLE socialactivity OWNER TO postgres;

--
-- TOC entry 295 (class 1259 OID 31084)
-- Name: socialactivityachievement; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivityachievement (
    activityachievementid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate bigint,
    name character varying(75),
    firstingroup boolean
);


ALTER TABLE socialactivityachievement OWNER TO postgres;

--
-- TOC entry 296 (class 1259 OID 31089)
-- Name: socialactivitycounter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivitycounter (
    activitycounterid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    classnameid bigint,
    classpk bigint,
    name character varying(75),
    ownertype integer,
    currentvalue integer,
    totalvalue integer,
    gracevalue integer,
    startperiod integer,
    endperiod integer,
    active_ boolean
);


ALTER TABLE socialactivitycounter OWNER TO postgres;

--
-- TOC entry 297 (class 1259 OID 31094)
-- Name: socialactivitylimit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivitylimit (
    activitylimitid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    classnameid bigint,
    classpk bigint,
    activitytype integer,
    activitycountername character varying(75),
    value character varying(75)
);


ALTER TABLE socialactivitylimit OWNER TO postgres;

--
-- TOC entry 298 (class 1259 OID 31099)
-- Name: socialactivityset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivityset (
    activitysetid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate bigint,
    modifieddate bigint,
    classnameid bigint,
    classpk bigint,
    type_ integer,
    extradata text,
    activitycount integer
);


ALTER TABLE socialactivityset OWNER TO postgres;

--
-- TOC entry 299 (class 1259 OID 31107)
-- Name: socialactivitysetting; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialactivitysetting (
    activitysettingid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    classnameid bigint,
    activitytype integer,
    name character varying(75),
    value character varying(1024)
);


ALTER TABLE socialactivitysetting OWNER TO postgres;

--
-- TOC entry 300 (class 1259 OID 31115)
-- Name: socialrelation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialrelation (
    uuid_ character varying(75),
    relationid bigint NOT NULL,
    companyid bigint,
    createdate bigint,
    userid1 bigint,
    userid2 bigint,
    type_ integer
);


ALTER TABLE socialrelation OWNER TO postgres;

--
-- TOC entry 301 (class 1259 OID 31120)
-- Name: socialrequest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE socialrequest (
    uuid_ character varying(75),
    requestid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    createdate bigint,
    modifieddate bigint,
    classnameid bigint,
    classpk bigint,
    type_ integer,
    extradata text,
    receiveruserid bigint,
    status integer
);


ALTER TABLE socialrequest OWNER TO postgres;

--
-- TOC entry 302 (class 1259 OID 31128)
-- Name: subscription; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE subscription (
    mvccversion bigint DEFAULT 0 NOT NULL,
    subscriptionid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    frequency character varying(75)
);


ALTER TABLE subscription OWNER TO postgres;

--
-- TOC entry 390 (class 1259 OID 32505)
-- Name: syncdevice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE syncdevice (
    uuid_ character varying(75),
    syncdeviceid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    type_ character varying(75),
    buildnumber bigint,
    featureset integer,
    hostname character varying(75),
    status integer
);


ALTER TABLE syncdevice OWNER TO postgres;

--
-- TOC entry 388 (class 1259 OID 32492)
-- Name: syncdlfileversiondiff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE syncdlfileversiondiff (
    syncdlfileversiondiffid bigint NOT NULL,
    fileentryid bigint,
    sourcefileversionid bigint,
    targetfileversionid bigint,
    datafileentryid bigint,
    size_ bigint,
    expirationdate timestamp without time zone
);


ALTER TABLE syncdlfileversiondiff OWNER TO postgres;

--
-- TOC entry 389 (class 1259 OID 32497)
-- Name: syncdlobject; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE syncdlobject (
    syncdlobjectid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createtime bigint,
    modifiedtime bigint,
    repositoryid bigint,
    parentfolderid bigint,
    treepath text,
    name character varying(255),
    extension character varying(75),
    mimetype character varying(75),
    description text,
    changelog character varying(75),
    extrasettings text,
    version character varying(75),
    versionid bigint,
    size_ bigint,
    checksum character varying(75),
    event character varying(75),
    lastpermissionchangedate timestamp without time zone,
    lockexpirationdate timestamp without time zone,
    lockuserid bigint,
    lockusername character varying(75),
    type_ character varying(75),
    typepk bigint,
    typeuuid character varying(75)
);


ALTER TABLE syncdlobject OWNER TO postgres;

--
-- TOC entry 303 (class 1259 OID 31134)
-- Name: systemevent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE systemevent (
    mvccversion bigint DEFAULT 0 NOT NULL,
    systemeventid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    classuuid character varying(75),
    referrerclassnameid bigint,
    parentsystemeventid bigint,
    systemeventsetkey bigint,
    type_ integer,
    extradata text
);


ALTER TABLE systemevent OWNER TO postgres;

--
-- TOC entry 304 (class 1259 OID 31143)
-- Name: team; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE team (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    teamid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    groupid bigint,
    name character varying(75),
    description text,
    lastpublishdate timestamp without time zone
);


ALTER TABLE team OWNER TO postgres;

--
-- TOC entry 305 (class 1259 OID 31152)
-- Name: ticket; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE ticket (
    mvccversion bigint DEFAULT 0 NOT NULL,
    ticketid bigint NOT NULL,
    companyid bigint,
    createdate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    key_ character varying(75),
    type_ integer,
    extrainfo text,
    expirationdate timestamp without time zone
);


ALTER TABLE ticket OWNER TO postgres;

--
-- TOC entry 306 (class 1259 OID 31161)
-- Name: trashentry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE trashentry (
    entryid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    systemeventsetkey bigint,
    typesettings text,
    status integer
);


ALTER TABLE trashentry OWNER TO postgres;

--
-- TOC entry 307 (class 1259 OID 31169)
-- Name: trashversion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE trashversion (
    versionid bigint NOT NULL,
    companyid bigint,
    entryid bigint,
    classnameid bigint,
    classpk bigint,
    typesettings text,
    status integer
);


ALTER TABLE trashversion OWNER TO postgres;

--
-- TOC entry 309 (class 1259 OID 31183)
-- Name: user_; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE user_ (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    userid bigint NOT NULL,
    companyid bigint,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    defaultuser boolean,
    contactid bigint,
    password_ character varying(75),
    passwordencrypted boolean,
    passwordreset boolean,
    passwordmodifieddate timestamp without time zone,
    digest character varying(255),
    reminderqueryquestion character varying(75),
    reminderqueryanswer character varying(75),
    gracelogincount integer,
    screenname character varying(75),
    emailaddress character varying(75),
    facebookid bigint,
    googleuserid character varying(75),
    ldapserverid bigint,
    openid character varying(1024),
    portraitid bigint,
    languageid character varying(75),
    timezoneid character varying(75),
    greeting character varying(255),
    comments text,
    firstname character varying(75),
    middlename character varying(75),
    lastname character varying(75),
    jobtitle character varying(100),
    logindate timestamp without time zone,
    loginip character varying(75),
    lastlogindate timestamp without time zone,
    lastloginip character varying(75),
    lastfailedlogindate timestamp without time zone,
    failedloginattempts integer,
    lockout boolean,
    lockoutdate timestamp without time zone,
    agreedtotermsofuse boolean,
    emailaddressverified boolean,
    status integer,
    sid character varying(75) DEFAULT 'NO_SID'::character varying,
    uid integer DEFAULT 0
);


ALTER TABLE user_ OWNER TO postgres;

--
-- TOC entry 310 (class 1259 OID 31192)
-- Name: usergroup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usergroup (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    usergroupid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    parentusergroupid bigint,
    name character varying(75),
    description text,
    addedbyldapimport boolean,
    sid character varying(75) DEFAULT 'NO_SID'::character varying,
    gid integer DEFAULT 0
);


ALTER TABLE usergroup OWNER TO postgres;

--
-- TOC entry 311 (class 1259 OID 31201)
-- Name: usergroupgrouprole; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usergroupgrouprole (
    mvccversion bigint DEFAULT 0 NOT NULL,
    usergroupid bigint NOT NULL,
    groupid bigint NOT NULL,
    roleid bigint NOT NULL,
    companyid bigint
);


ALTER TABLE usergroupgrouprole OWNER TO postgres;

--
-- TOC entry 312 (class 1259 OID 31207)
-- Name: usergrouprole; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usergrouprole (
    mvccversion bigint DEFAULT 0 NOT NULL,
    userid bigint NOT NULL,
    groupid bigint NOT NULL,
    roleid bigint NOT NULL,
    companyid bigint
);


ALTER TABLE usergrouprole OWNER TO postgres;

--
-- TOC entry 313 (class 1259 OID 31213)
-- Name: usergroups_teams; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usergroups_teams (
    companyid bigint NOT NULL,
    teamid bigint NOT NULL,
    usergroupid bigint NOT NULL
);


ALTER TABLE usergroups_teams OWNER TO postgres;

--
-- TOC entry 314 (class 1259 OID 31218)
-- Name: useridmapper; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE useridmapper (
    mvccversion bigint DEFAULT 0 NOT NULL,
    useridmapperid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    type_ character varying(75),
    description character varying(75),
    externaluserid character varying(75)
);


ALTER TABLE useridmapper OWNER TO postgres;

--
-- TOC entry 308 (class 1259 OID 31177)
-- Name: usernotificationdelivery; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usernotificationdelivery (
    mvccversion bigint DEFAULT 0 NOT NULL,
    usernotificationdeliveryid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    portletid character varying(200),
    classnameid bigint,
    notificationtype integer,
    deliverytype integer,
    deliver boolean
);


ALTER TABLE usernotificationdelivery OWNER TO postgres;

--
-- TOC entry 315 (class 1259 OID 31224)
-- Name: usernotificationevent; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usernotificationevent (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    usernotificationeventid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    type_ character varying(200),
    "timestamp" bigint,
    deliverytype integer,
    deliverby bigint,
    delivered boolean,
    payload text,
    actionrequired boolean,
    archived boolean
);


ALTER TABLE usernotificationevent OWNER TO postgres;

--
-- TOC entry 316 (class 1259 OID 31233)
-- Name: users_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE users_groups (
    companyid bigint NOT NULL,
    groupid bigint NOT NULL,
    userid bigint NOT NULL
);


ALTER TABLE users_groups OWNER TO postgres;

--
-- TOC entry 317 (class 1259 OID 31238)
-- Name: users_orgs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE users_orgs (
    companyid bigint NOT NULL,
    organizationid bigint NOT NULL,
    userid bigint NOT NULL
);


ALTER TABLE users_orgs OWNER TO postgres;

--
-- TOC entry 318 (class 1259 OID 31243)
-- Name: users_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE users_roles (
    companyid bigint NOT NULL,
    roleid bigint NOT NULL,
    userid bigint NOT NULL
);


ALTER TABLE users_roles OWNER TO postgres;

--
-- TOC entry 319 (class 1259 OID 31248)
-- Name: users_teams; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE users_teams (
    companyid bigint NOT NULL,
    teamid bigint NOT NULL,
    userid bigint NOT NULL
);


ALTER TABLE users_teams OWNER TO postgres;

--
-- TOC entry 320 (class 1259 OID 31253)
-- Name: users_usergroups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE users_usergroups (
    companyid bigint NOT NULL,
    userid bigint NOT NULL,
    usergroupid bigint NOT NULL
);


ALTER TABLE users_usergroups OWNER TO postgres;

--
-- TOC entry 321 (class 1259 OID 31258)
-- Name: usertracker; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usertracker (
    mvccversion bigint DEFAULT 0 NOT NULL,
    usertrackerid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    modifieddate timestamp without time zone,
    sessionid character varying(200),
    remoteaddr character varying(75),
    remotehost character varying(75),
    useragent character varying(200)
);


ALTER TABLE usertracker OWNER TO postgres;

--
-- TOC entry 322 (class 1259 OID 31267)
-- Name: usertrackerpath; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE usertrackerpath (
    mvccversion bigint DEFAULT 0 NOT NULL,
    usertrackerpathid bigint NOT NULL,
    companyid bigint,
    usertrackerid bigint,
    path_ text,
    pathdate timestamp without time zone
);


ALTER TABLE usertrackerpath OWNER TO postgres;

--
-- TOC entry 323 (class 1259 OID 31276)
-- Name: virtualhost; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE virtualhost (
    mvccversion bigint DEFAULT 0 NOT NULL,
    virtualhostid bigint NOT NULL,
    companyid bigint,
    layoutsetid bigint,
    hostname character varying(75)
);


ALTER TABLE virtualhost OWNER TO postgres;

--
-- TOC entry 324 (class 1259 OID 31282)
-- Name: webdavprops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE webdavprops (
    mvccversion bigint DEFAULT 0 NOT NULL,
    webdavpropsid bigint NOT NULL,
    companyid bigint,
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    props text
);


ALTER TABLE webdavprops OWNER TO postgres;

--
-- TOC entry 325 (class 1259 OID 31291)
-- Name: website; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE website (
    mvccversion bigint DEFAULT 0 NOT NULL,
    uuid_ character varying(75),
    websiteid bigint NOT NULL,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    url text,
    typeid bigint,
    primary_ boolean,
    lastpublishdate timestamp without time zone
);


ALTER TABLE website OWNER TO postgres;

--
-- TOC entry 353 (class 1259 OID 32068)
-- Name: wikinode; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE wikinode (
    uuid_ character varying(75),
    nodeid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    name character varying(75),
    description text,
    lastpostdate timestamp without time zone,
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE wikinode OWNER TO postgres;

--
-- TOC entry 354 (class 1259 OID 32076)
-- Name: wikipage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE wikipage (
    uuid_ character varying(75),
    pageid bigint NOT NULL,
    resourceprimkey bigint,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    nodeid bigint,
    title character varying(255),
    version double precision,
    minoredit boolean,
    content text,
    summary text,
    format character varying(75),
    head boolean,
    parenttitle character varying(255),
    redirecttitle character varying(255),
    lastpublishdate timestamp without time zone,
    status integer,
    statusbyuserid bigint,
    statusbyusername character varying(75),
    statusdate timestamp without time zone
);


ALTER TABLE wikipage OWNER TO postgres;

--
-- TOC entry 355 (class 1259 OID 32084)
-- Name: wikipageresource; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE wikipageresource (
    uuid_ character varying(75),
    resourceprimkey bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    nodeid bigint,
    title character varying(255)
);


ALTER TABLE wikipageresource OWNER TO postgres;

--
-- TOC entry 326 (class 1259 OID 31300)
-- Name: workflowdefinitionlink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE workflowdefinitionlink (
    mvccversion bigint DEFAULT 0 NOT NULL,
    workflowdefinitionlinkid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    typepk bigint,
    workflowdefinitionname character varying(75),
    workflowdefinitionversion integer
);


ALTER TABLE workflowdefinitionlink OWNER TO postgres;

--
-- TOC entry 327 (class 1259 OID 31306)
-- Name: workflowinstancelink; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE workflowinstancelink (
    mvccversion bigint DEFAULT 0 NOT NULL,
    workflowinstancelinkid bigint NOT NULL,
    groupid bigint,
    companyid bigint,
    userid bigint,
    username character varying(75),
    createdate timestamp without time zone,
    modifieddate timestamp without time zone,
    classnameid bigint,
    classpk bigint,
    workflowinstanceid bigint
);


ALTER TABLE workflowinstancelink OWNER TO postgres;

--
-- TOC entry 419 (class 1259 OID 32814)
-- Name: xattr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE xattr (
    id bigint NOT NULL,
    dir_id bigint,
    name character varying(1024),
    val bytea
);


ALTER TABLE xattr OWNER TO postgres;

--
-- TOC entry 418 (class 1259 OID 32812)
-- Name: xattr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE xattr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE xattr_id_seq OWNER TO postgres;

--
-- TOC entry 4700 (class 0 OID 0)
-- Dependencies: 418
-- Name: xattr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE xattr_id_seq OWNED BY xattr.id;


--
-- TOC entry 3228 (class 2604 OID 32791)
-- Name: id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dir_fs ALTER COLUMN id SET DEFAULT nextval('dir_fs_id_seq'::regclass);


--
-- TOC entry 3235 (class 2604 OID 32817)
-- Name: id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY xattr ALTER COLUMN id SET DEFAULT nextval('xattr_id_seq'::regclass);


--
-- TOC entry 3292 (class 2606 OID 30461)
-- Name: account__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY account_
    ADD CONSTRAINT account__pkey PRIMARY KEY (accountid);


--
-- TOC entry 3294 (class 2606 OID 30470)
-- Name: address_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY address
    ADD CONSTRAINT address_pkey PRIMARY KEY (addressid);


--
-- TOC entry 3300 (class 2606 OID 30475)
-- Name: announcementsdelivery_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY announcementsdelivery
    ADD CONSTRAINT announcementsdelivery_pkey PRIMARY KEY (deliveryid);


--
-- TOC entry 3303 (class 2606 OID 30483)
-- Name: announcementsentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY announcementsentry
    ADD CONSTRAINT announcementsentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3308 (class 2606 OID 30488)
-- Name: announcementsflag_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY announcementsflag
    ADD CONSTRAINT announcementsflag_pkey PRIMARY KEY (flagid);


--
-- TOC entry 3312 (class 2606 OID 30496)
-- Name: assetcategory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetcategory
    ADD CONSTRAINT assetcategory_pkey PRIMARY KEY (categoryid);


--
-- TOC entry 3324 (class 2606 OID 30501)
-- Name: assetcategoryproperty_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetcategoryproperty
    ADD CONSTRAINT assetcategoryproperty_pkey PRIMARY KEY (categorypropertyid);


--
-- TOC entry 3328 (class 2606 OID 30506)
-- Name: assetentries_assetcategories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetentries_assetcategories
    ADD CONSTRAINT assetentries_assetcategories_pkey PRIMARY KEY (categoryid, entryid);


--
-- TOC entry 3333 (class 2606 OID 30511)
-- Name: assetentries_assettags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetentries_assettags
    ADD CONSTRAINT assetentries_assettags_pkey PRIMARY KEY (entryid, tagid);


--
-- TOC entry 3338 (class 2606 OID 30519)
-- Name: assetentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetentry
    ADD CONSTRAINT assetentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3347 (class 2606 OID 30524)
-- Name: assetlink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetlink
    ADD CONSTRAINT assetlink_pkey PRIMARY KEY (linkid);


--
-- TOC entry 3352 (class 2606 OID 30529)
-- Name: assettag_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assettag
    ADD CONSTRAINT assettag_pkey PRIMARY KEY (tagid);


--
-- TOC entry 3357 (class 2606 OID 30534)
-- Name: assettagstats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assettagstats
    ADD CONSTRAINT assettagstats_pkey PRIMARY KEY (tagstatsid);


--
-- TOC entry 3361 (class 2606 OID 30542)
-- Name: assetvocabulary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY assetvocabulary
    ADD CONSTRAINT assetvocabulary_pkey PRIMARY KEY (vocabularyid);


--
-- TOC entry 4086 (class 2606 OID 31976)
-- Name: backgroundtask_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY backgroundtask
    ADD CONSTRAINT backgroundtask_pkey PRIMARY KEY (backgroundtaskid);


--
-- TOC entry 3367 (class 2606 OID 30550)
-- Name: blogsentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY blogsentry
    ADD CONSTRAINT blogsentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3380 (class 2606 OID 30555)
-- Name: blogsstatsuser_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY blogsstatsuser
    ADD CONSTRAINT blogsstatsuser_pkey PRIMARY KEY (statsuserid);


--
-- TOC entry 4292 (class 2606 OID 32335)
-- Name: bookmarksentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY bookmarksentry
    ADD CONSTRAINT bookmarksentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 4302 (class 2606 OID 32343)
-- Name: bookmarksfolder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY bookmarksfolder
    ADD CONSTRAINT bookmarksfolder_pkey PRIMARY KEY (folderid);


--
-- TOC entry 3386 (class 2606 OID 30561)
-- Name: browsertracker_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY browsertracker
    ADD CONSTRAINT browsertracker_pkey PRIMARY KEY (browsertrackerid);


--
-- TOC entry 4465 (class 2606 OID 32649)
-- Name: calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_pkey PRIMARY KEY (calendarid);


--
-- TOC entry 4471 (class 2606 OID 32657)
-- Name: calendarbooking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY calendarbooking
    ADD CONSTRAINT calendarbooking_pkey PRIMARY KEY (calendarbookingid);


--
-- TOC entry 4481 (class 2606 OID 32665)
-- Name: calendarnotificationtemplate_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY calendarnotificationtemplate
    ADD CONSTRAINT calendarnotificationtemplate_pkey PRIMARY KEY (calendarnotificationtemplateid);


--
-- TOC entry 4486 (class 2606 OID 32673)
-- Name: calendarresource_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY calendarresource
    ADD CONSTRAINT calendarresource_pkey PRIMARY KEY (calendarresourceid);


--
-- TOC entry 3389 (class 2606 OID 30567)
-- Name: classname__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY classname_
    ADD CONSTRAINT classname__pkey PRIMARY KEY (classnameid);


--
-- TOC entry 3392 (class 2606 OID 30573)
-- Name: clustergroup_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY clustergroup
    ADD CONSTRAINT clustergroup_pkey PRIMARY KEY (clustergroupid);


--
-- TOC entry 3394 (class 2606 OID 30582)
-- Name: company_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY company
    ADD CONSTRAINT company_pkey PRIMARY KEY (companyid);


--
-- TOC entry 3248 (class 2606 OID 30352)
-- Name: configuration__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY configuration_
    ADD CONSTRAINT configuration__pkey PRIMARY KEY (configurationid);


--
-- TOC entry 3400 (class 2606 OID 30591)
-- Name: contact__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY contact_
    ADD CONSTRAINT contact__pkey PRIMARY KEY (contactid);


--
-- TOC entry 4314 (class 2606 OID 32372)
-- Name: contacts_entry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY contacts_entry
    ADD CONSTRAINT contacts_entry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3405 (class 2606 OID 30596)
-- Name: counter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY counter
    ADD CONSTRAINT counter_pkey PRIMARY KEY (name);


--
-- TOC entry 3407 (class 2606 OID 30602)
-- Name: country_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY country
    ADD CONSTRAINT country_pkey PRIMARY KEY (countryid);


--
-- TOC entry 4535 (class 2606 OID 32811)
-- Name: data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY data
    ADD CONSTRAINT data_pkey PRIMARY KEY (dir_id, block_no);


--
-- TOC entry 4317 (class 2606 OID 32378)
-- Name: ddlrecord_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddlrecord
    ADD CONSTRAINT ddlrecord_pkey PRIMARY KEY (recordid);


--
-- TOC entry 4323 (class 2606 OID 32386)
-- Name: ddlrecordset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddlrecordset
    ADD CONSTRAINT ddlrecordset_pkey PRIMARY KEY (recordsetid);


--
-- TOC entry 4328 (class 2606 OID 32391)
-- Name: ddlrecordversion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddlrecordversion
    ADD CONSTRAINT ddlrecordversion_pkey PRIMARY KEY (recordversionid);


--
-- TOC entry 4210 (class 2606 OID 32169)
-- Name: ddmcontent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmcontent
    ADD CONSTRAINT ddmcontent_pkey PRIMARY KEY (contentid);


--
-- TOC entry 4216 (class 2606 OID 32177)
-- Name: ddmdataproviderinstance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmdataproviderinstance
    ADD CONSTRAINT ddmdataproviderinstance_pkey PRIMARY KEY (dataproviderinstanceid);


--
-- TOC entry 4222 (class 2606 OID 32182)
-- Name: ddmdataproviderinstancelink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmdataproviderinstancelink
    ADD CONSTRAINT ddmdataproviderinstancelink_pkey PRIMARY KEY (dataproviderinstancelinkid);


--
-- TOC entry 4226 (class 2606 OID 32187)
-- Name: ddmstoragelink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmstoragelink
    ADD CONSTRAINT ddmstoragelink_pkey PRIMARY KEY (storagelinkid);


--
-- TOC entry 4231 (class 2606 OID 32195)
-- Name: ddmstructure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmstructure
    ADD CONSTRAINT ddmstructure_pkey PRIMARY KEY (structureid);


--
-- TOC entry 4241 (class 2606 OID 32203)
-- Name: ddmstructurelayout_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmstructurelayout
    ADD CONSTRAINT ddmstructurelayout_pkey PRIMARY KEY (structurelayoutid);


--
-- TOC entry 4246 (class 2606 OID 32208)
-- Name: ddmstructurelink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmstructurelink
    ADD CONSTRAINT ddmstructurelink_pkey PRIMARY KEY (structurelinkid);


--
-- TOC entry 4250 (class 2606 OID 32216)
-- Name: ddmstructureversion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmstructureversion
    ADD CONSTRAINT ddmstructureversion_pkey PRIMARY KEY (structureversionid);


--
-- TOC entry 4254 (class 2606 OID 32224)
-- Name: ddmtemplate_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmtemplate
    ADD CONSTRAINT ddmtemplate_pkey PRIMARY KEY (templateid);


--
-- TOC entry 4267 (class 2606 OID 32229)
-- Name: ddmtemplatelink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmtemplatelink
    ADD CONSTRAINT ddmtemplatelink_pkey PRIMARY KEY (templatelinkid);


--
-- TOC entry 4271 (class 2606 OID 32237)
-- Name: ddmtemplateversion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ddmtemplateversion
    ADD CONSTRAINT ddmtemplateversion_pkey PRIMARY KEY (templateversionid);


--
-- TOC entry 4528 (class 2606 OID 32802)
-- Name: dir_fs_name_parent_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dir_fs
    ADD CONSTRAINT dir_fs_name_parent_id_key UNIQUE (name, parent_id);


--
-- TOC entry 4530 (class 2606 OID 32800)
-- Name: dir_fs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dir_fs
    ADD CONSTRAINT dir_fs_pkey PRIMARY KEY (id);


--
-- TOC entry 3413 (class 2606 OID 30607)
-- Name: dlcontent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlcontent
    ADD CONSTRAINT dlcontent_pkey PRIMARY KEY (contentid);


--
-- TOC entry 3416 (class 2606 OID 30617)
-- Name: dlfileentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileentry
    ADD CONSTRAINT dlfileentry_pkey PRIMARY KEY (fileentryid);


--
-- TOC entry 3432 (class 2606 OID 30622)
-- Name: dlfileentrymetadata_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileentrymetadata
    ADD CONSTRAINT dlfileentrymetadata_pkey PRIMARY KEY (fileentrymetadataid);


--
-- TOC entry 3438 (class 2606 OID 30630)
-- Name: dlfileentrytype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileentrytype
    ADD CONSTRAINT dlfileentrytype_pkey PRIMARY KEY (fileentrytypeid);


--
-- TOC entry 3443 (class 2606 OID 30635)
-- Name: dlfileentrytypes_dlfolders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileentrytypes_dlfolders
    ADD CONSTRAINT dlfileentrytypes_dlfolders_pkey PRIMARY KEY (fileentrytypeid, folderid);


--
-- TOC entry 3448 (class 2606 OID 30640)
-- Name: dlfilerank_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfilerank
    ADD CONSTRAINT dlfilerank_pkey PRIMARY KEY (filerankid);


--
-- TOC entry 3454 (class 2606 OID 30648)
-- Name: dlfileshortcut_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileshortcut
    ADD CONSTRAINT dlfileshortcut_pkey PRIMARY KEY (fileshortcutid);


--
-- TOC entry 3461 (class 2606 OID 30656)
-- Name: dlfileversion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfileversion
    ADD CONSTRAINT dlfileversion_pkey PRIMARY KEY (fileversionid);


--
-- TOC entry 3471 (class 2606 OID 30664)
-- Name: dlfolder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlfolder
    ADD CONSTRAINT dlfolder_pkey PRIMARY KEY (folderid);


--
-- TOC entry 3482 (class 2606 OID 30669)
-- Name: dlsyncevent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY dlsyncevent
    ADD CONSTRAINT dlsyncevent_pkey PRIMARY KEY (synceventid);


--
-- TOC entry 3486 (class 2606 OID 30675)
-- Name: emailaddress_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY emailaddress
    ADD CONSTRAINT emailaddress_pkey PRIMARY KEY (emailaddressid);


--
-- TOC entry 3491 (class 2606 OID 30683)
-- Name: expandocolumn_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expandocolumn
    ADD CONSTRAINT expandocolumn_pkey PRIMARY KEY (columnid);


--
-- TOC entry 3494 (class 2606 OID 30688)
-- Name: expandorow_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expandorow
    ADD CONSTRAINT expandorow_pkey PRIMARY KEY (rowid_);


--
-- TOC entry 3498 (class 2606 OID 30693)
-- Name: expandotable_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expandotable
    ADD CONSTRAINT expandotable_pkey PRIMARY KEY (tableid);


--
-- TOC entry 3501 (class 2606 OID 30701)
-- Name: expandovalue_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expandovalue
    ADD CONSTRAINT expandovalue_pkey PRIMARY KEY (valueid);


--
-- TOC entry 3509 (class 2606 OID 30710)
-- Name: exportimportconfiguration_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY exportimportconfiguration
    ADD CONSTRAINT exportimportconfiguration_pkey PRIMARY KEY (exportimportconfigurationid);


--
-- TOC entry 4550 (class 2606 OID 33060)
-- Name: gantt_finance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_finance
    ADD CONSTRAINT gantt_finance_pkey PRIMARY KEY (id);


--
-- TOC entry 4552 (class 2606 OID 33071)
-- Name: gantt_finance_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_finance_status
    ADD CONSTRAINT gantt_finance_status_pkey PRIMARY KEY (id);


--
-- TOC entry 4542 (class 2606 OID 33002)
-- Name: gantt_links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_links
    ADD CONSTRAINT gantt_links_pkey PRIMARY KEY (id);


--
-- TOC entry 4546 (class 2606 OID 33024)
-- Name: gantt_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_roles
    ADD CONSTRAINT gantt_roles_pkey PRIMARY KEY (role_id);


--
-- TOC entry 4544 (class 2606 OID 33014)
-- Name: gantt_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks
    ADD CONSTRAINT gantt_tasks_pkey PRIMARY KEY (id);


--
-- TOC entry 4548 (class 2606 OID 33033)
-- Name: gantt_tasks_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks_users
    ADD CONSTRAINT gantt_tasks_users_pkey PRIMARY KEY (id);


--
-- TOC entry 3514 (class 2606 OID 30719)
-- Name: group__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY group_
    ADD CONSTRAINT group__pkey PRIMARY KEY (groupid);


--
-- TOC entry 3531 (class 2606 OID 30724)
-- Name: groups_orgs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY groups_orgs
    ADD CONSTRAINT groups_orgs_pkey PRIMARY KEY (groupid, organizationid);


--
-- TOC entry 3536 (class 2606 OID 30729)
-- Name: groups_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY groups_roles
    ADD CONSTRAINT groups_roles_pkey PRIMARY KEY (groupid, roleid);


--
-- TOC entry 3541 (class 2606 OID 30734)
-- Name: groups_usergroups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY groups_usergroups
    ADD CONSTRAINT groups_usergroups_pkey PRIMARY KEY (groupid, usergroupid);


--
-- TOC entry 4537 (class 2606 OID 33163)
-- Name: id_data; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY xattr
    ADD CONSTRAINT id_data UNIQUE (dir_id, name);


--
-- TOC entry 4558 (class 2606 OID 33254)
-- Name: iee_tmpl_folders_perms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl_folders_perms
    ADD CONSTRAINT iee_tmpl_folders_perms_pkey PRIMARY KEY (id);


--
-- TOC entry 4556 (class 2606 OID 33236)
-- Name: iee_tmpl_folders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl_folders
    ADD CONSTRAINT iee_tmpl_folders_pkey PRIMARY KEY (id);


--
-- TOC entry 4554 (class 2606 OID 33229)
-- Name: iee_tmpl_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl
    ADD CONSTRAINT iee_tmpl_pkey PRIMARY KEY (id);


--
-- TOC entry 3546 (class 2606 OID 30740)
-- Name: image_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY image
    ADD CONSTRAINT image_pkey PRIMARY KEY (imageid);


--
-- TOC entry 4121 (class 2606 OID 31992)
-- Name: journalarticle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalarticle
    ADD CONSTRAINT journalarticle_pkey PRIMARY KEY (id_);


--
-- TOC entry 4125 (class 2606 OID 31997)
-- Name: journalarticleimage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalarticleimage
    ADD CONSTRAINT journalarticleimage_pkey PRIMARY KEY (articleimageid);


--
-- TOC entry 4130 (class 2606 OID 32002)
-- Name: journalarticleresource_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalarticleresource
    ADD CONSTRAINT journalarticleresource_pkey PRIMARY KEY (resourceprimkey);


--
-- TOC entry 4137 (class 2606 OID 32007)
-- Name: journalcontentsearch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalcontentsearch
    ADD CONSTRAINT journalcontentsearch_pkey PRIMARY KEY (contentsearchid);


--
-- TOC entry 4142 (class 2606 OID 32015)
-- Name: journalfeed_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalfeed
    ADD CONSTRAINT journalfeed_pkey PRIMARY KEY (id_);


--
-- TOC entry 4150 (class 2606 OID 32023)
-- Name: journalfolder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY journalfolder
    ADD CONSTRAINT journalfolder_pkey PRIMARY KEY (folderid);


--
-- TOC entry 4003 (class 2606 OID 31793)
-- Name: kaleoaction_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleoaction
    ADD CONSTRAINT kaleoaction_pkey PRIMARY KEY (kaleoactionid);


--
-- TOC entry 4008 (class 2606 OID 31801)
-- Name: kaleocondition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleocondition
    ADD CONSTRAINT kaleocondition_pkey PRIMARY KEY (kaleoconditionid);


--
-- TOC entry 4013 (class 2606 OID 31809)
-- Name: kaleodefinition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleodefinition
    ADD CONSTRAINT kaleodefinition_pkey PRIMARY KEY (kaleodefinitionid);


--
-- TOC entry 4019 (class 2606 OID 31817)
-- Name: kaleoinstance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleoinstance
    ADD CONSTRAINT kaleoinstance_pkey PRIMARY KEY (kaleoinstanceid);


--
-- TOC entry 4024 (class 2606 OID 31825)
-- Name: kaleoinstancetoken_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleoinstancetoken
    ADD CONSTRAINT kaleoinstancetoken_pkey PRIMARY KEY (kaleoinstancetokenid);


--
-- TOC entry 4032 (class 2606 OID 31833)
-- Name: kaleolog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleolog
    ADD CONSTRAINT kaleolog_pkey PRIMARY KEY (kaleologid);


--
-- TOC entry 4036 (class 2606 OID 31841)
-- Name: kaleonode_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleonode
    ADD CONSTRAINT kaleonode_pkey PRIMARY KEY (kaleonodeid);


--
-- TOC entry 4041 (class 2606 OID 31849)
-- Name: kaleonotification_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleonotification
    ADD CONSTRAINT kaleonotification_pkey PRIMARY KEY (kaleonotificationid);


--
-- TOC entry 4046 (class 2606 OID 31857)
-- Name: kaleonotificationrecipient_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleonotificationrecipient
    ADD CONSTRAINT kaleonotificationrecipient_pkey PRIMARY KEY (kaleonotificationrecipientid);


--
-- TOC entry 4051 (class 2606 OID 31865)
-- Name: kaleotask_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotask
    ADD CONSTRAINT kaleotask_pkey PRIMARY KEY (kaleotaskid);


--
-- TOC entry 4056 (class 2606 OID 31873)
-- Name: kaleotaskassignment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotaskassignment
    ADD CONSTRAINT kaleotaskassignment_pkey PRIMARY KEY (kaleotaskassignmentid);


--
-- TOC entry 4064 (class 2606 OID 31881)
-- Name: kaleotaskassignmentinstance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotaskassignmentinstance
    ADD CONSTRAINT kaleotaskassignmentinstance_pkey PRIMARY KEY (kaleotaskassignmentinstanceid);


--
-- TOC entry 4070 (class 2606 OID 31889)
-- Name: kaleotaskinstancetoken_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotaskinstancetoken
    ADD CONSTRAINT kaleotaskinstancetoken_pkey PRIMARY KEY (kaleotaskinstancetokenid);


--
-- TOC entry 4073 (class 2606 OID 31897)
-- Name: kaleotimer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotimer
    ADD CONSTRAINT kaleotimer_pkey PRIMARY KEY (kaleotimerid);


--
-- TOC entry 4078 (class 2606 OID 31905)
-- Name: kaleotimerinstancetoken_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotimerinstancetoken
    ADD CONSTRAINT kaleotimerinstancetoken_pkey PRIMARY KEY (kaleotimerinstancetokenid);


--
-- TOC entry 4084 (class 2606 OID 31913)
-- Name: kaleotransition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kaleotransition
    ADD CONSTRAINT kaleotransition_pkey PRIMARY KEY (kaleotransitionid);


--
-- TOC entry 4369 (class 2606 OID 32429)
-- Name: kbarticle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kbarticle
    ADD CONSTRAINT kbarticle_pkey PRIMARY KEY (kbarticleid);


--
-- TOC entry 4377 (class 2606 OID 32437)
-- Name: kbcomment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kbcomment
    ADD CONSTRAINT kbcomment_pkey PRIMARY KEY (kbcommentid);


--
-- TOC entry 4383 (class 2606 OID 32445)
-- Name: kbfolder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kbfolder
    ADD CONSTRAINT kbfolder_pkey PRIMARY KEY (kbfolderid);


--
-- TOC entry 4388 (class 2606 OID 32453)
-- Name: kbtemplate_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY kbtemplate
    ADD CONSTRAINT kbtemplate_pkey PRIMARY KEY (kbtemplateid);


--
-- TOC entry 3560 (class 2606 OID 30749)
-- Name: layout_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layout
    ADD CONSTRAINT layout_pkey PRIMARY KEY (plid);


--
-- TOC entry 3564 (class 2606 OID 30758)
-- Name: layoutbranch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutbranch
    ADD CONSTRAINT layoutbranch_pkey PRIMARY KEY (layoutbranchid);


--
-- TOC entry 3572 (class 2606 OID 30767)
-- Name: layoutfriendlyurl_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutfriendlyurl
    ADD CONSTRAINT layoutfriendlyurl_pkey PRIMARY KEY (layoutfriendlyurlid);


--
-- TOC entry 3576 (class 2606 OID 30776)
-- Name: layoutprototype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutprototype
    ADD CONSTRAINT layoutprototype_pkey PRIMARY KEY (layoutprototypeid);


--
-- TOC entry 3585 (class 2606 OID 30785)
-- Name: layoutrevision_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutrevision
    ADD CONSTRAINT layoutrevision_pkey PRIMARY KEY (layoutrevisionid);


--
-- TOC entry 3589 (class 2606 OID 30794)
-- Name: layoutset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutset
    ADD CONSTRAINT layoutset_pkey PRIMARY KEY (layoutsetid);


--
-- TOC entry 3593 (class 2606 OID 30803)
-- Name: layoutsetbranch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutsetbranch
    ADD CONSTRAINT layoutsetbranch_pkey PRIMARY KEY (layoutsetbranchid);


--
-- TOC entry 3597 (class 2606 OID 30812)
-- Name: layoutsetprototype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY layoutsetprototype
    ADD CONSTRAINT layoutsetprototype_pkey PRIMARY KEY (layoutsetprototypeid);


--
-- TOC entry 3601 (class 2606 OID 30818)
-- Name: listtype_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY listtype
    ADD CONSTRAINT listtype_pkey PRIMARY KEY (listtypeid);


--
-- TOC entry 3998 (class 2606 OID 31782)
-- Name: lock__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY lock_
    ADD CONSTRAINT lock__pkey PRIMARY KEY (lockid);


--
-- TOC entry 4497 (class 2606 OID 32704)
-- Name: mail_account_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mail_account
    ADD CONSTRAINT mail_account_pkey PRIMARY KEY (accountid);


--
-- TOC entry 4500 (class 2606 OID 32709)
-- Name: mail_attachment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mail_attachment
    ADD CONSTRAINT mail_attachment_pkey PRIMARY KEY (attachmentid);


--
-- TOC entry 4503 (class 2606 OID 32714)
-- Name: mail_folder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mail_folder
    ADD CONSTRAINT mail_folder_pkey PRIMARY KEY (folderid);


--
-- TOC entry 4507 (class 2606 OID 32722)
-- Name: mail_message_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mail_message
    ADD CONSTRAINT mail_message_pkey PRIMARY KEY (messageid);


--
-- TOC entry 4283 (class 2606 OID 32310)
-- Name: marketplace_app_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY marketplace_app
    ADD CONSTRAINT marketplace_app_pkey PRIMARY KEY (appid);


--
-- TOC entry 4290 (class 2606 OID 32318)
-- Name: marketplace_module_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY marketplace_module
    ADD CONSTRAINT marketplace_module_pkey PRIMARY KEY (moduleid);


--
-- TOC entry 3608 (class 2606 OID 30823)
-- Name: mbban_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbban
    ADD CONSTRAINT mbban_pkey PRIMARY KEY (banid);


--
-- TOC entry 3616 (class 2606 OID 30831)
-- Name: mbcategory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbcategory
    ADD CONSTRAINT mbcategory_pkey PRIMARY KEY (categoryid);


--
-- TOC entry 3622 (class 2606 OID 30836)
-- Name: mbdiscussion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbdiscussion
    ADD CONSTRAINT mbdiscussion_pkey PRIMARY KEY (discussionid);


--
-- TOC entry 3628 (class 2606 OID 30844)
-- Name: mbmailinglist_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbmailinglist
    ADD CONSTRAINT mbmailinglist_pkey PRIMARY KEY (mailinglistid);


--
-- TOC entry 3644 (class 2606 OID 30852)
-- Name: mbmessage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbmessage
    ADD CONSTRAINT mbmessage_pkey PRIMARY KEY (messageid);


--
-- TOC entry 3648 (class 2606 OID 30857)
-- Name: mbstatsuser_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbstatsuser
    ADD CONSTRAINT mbstatsuser_pkey PRIMARY KEY (statsuserid);


--
-- TOC entry 3658 (class 2606 OID 30862)
-- Name: mbthread_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbthread
    ADD CONSTRAINT mbthread_pkey PRIMARY KEY (threadid);


--
-- TOC entry 3664 (class 2606 OID 30867)
-- Name: mbthreadflag_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mbthreadflag
    ADD CONSTRAINT mbthreadflag_pkey PRIMARY KEY (threadflagid);


--
-- TOC entry 4191 (class 2606 OID 32126)
-- Name: mdraction_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mdraction
    ADD CONSTRAINT mdraction_pkey PRIMARY KEY (actionid);


--
-- TOC entry 4196 (class 2606 OID 32134)
-- Name: mdrrule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mdrrule
    ADD CONSTRAINT mdrrule_pkey PRIMARY KEY (ruleid);


--
-- TOC entry 4201 (class 2606 OID 32142)
-- Name: mdrrulegroup_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mdrrulegroup
    ADD CONSTRAINT mdrrulegroup_pkey PRIMARY KEY (rulegroupid);


--
-- TOC entry 4208 (class 2606 OID 32147)
-- Name: mdrrulegroupinstance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY mdrrulegroupinstance
    ADD CONSTRAINT mdrrulegroupinstance_pkey PRIMARY KEY (rulegroupinstanceid);


--
-- TOC entry 3669 (class 2606 OID 30876)
-- Name: membershiprequest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY membershiprequest
    ADD CONSTRAINT membershiprequest_pkey PRIMARY KEY (membershiprequestid);


--
-- TOC entry 4515 (class 2606 OID 32735)
-- Name: microblogsentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY microblogsentry
    ADD CONSTRAINT microblogsentry_pkey PRIMARY KEY (microblogsentryid);


--
-- TOC entry 4519 (class 2606 OID 32753)
-- Name: opensocial_gadget_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY opensocial_gadget
    ADD CONSTRAINT opensocial_gadget_pkey PRIMARY KEY (gadgetid);


--
-- TOC entry 4522 (class 2606 OID 32761)
-- Name: opensocial_oauthconsumer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY opensocial_oauthconsumer
    ADD CONSTRAINT opensocial_oauthconsumer_pkey PRIMARY KEY (oauthconsumerid);


--
-- TOC entry 4526 (class 2606 OID 32769)
-- Name: opensocial_oauthtoken_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY opensocial_oauthtoken
    ADD CONSTRAINT opensocial_oauthtoken_pkey PRIMARY KEY (oauthtokenid);


--
-- TOC entry 3674 (class 2606 OID 30885)
-- Name: organization__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY organization_
    ADD CONSTRAINT organization__pkey PRIMARY KEY (organizationid);


--
-- TOC entry 3678 (class 2606 OID 30891)
-- Name: orggrouprole_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY orggrouprole
    ADD CONSTRAINT orggrouprole_pkey PRIMARY KEY (organizationid, groupid, roleid);


--
-- TOC entry 3681 (class 2606 OID 30897)
-- Name: orglabor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY orglabor
    ADD CONSTRAINT orglabor_pkey PRIMARY KEY (orglaborid);


--
-- TOC entry 3686 (class 2606 OID 30906)
-- Name: passwordpolicy_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY passwordpolicy
    ADD CONSTRAINT passwordpolicy_pkey PRIMARY KEY (passwordpolicyid);


--
-- TOC entry 3690 (class 2606 OID 30912)
-- Name: passwordpolicyrel_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY passwordpolicyrel
    ADD CONSTRAINT passwordpolicyrel_pkey PRIMARY KEY (passwordpolicyrelid);


--
-- TOC entry 3693 (class 2606 OID 30918)
-- Name: passwordtracker_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY passwordtracker
    ADD CONSTRAINT passwordtracker_pkey PRIMARY KEY (passwordtrackerid);


--
-- TOC entry 3698 (class 2606 OID 30924)
-- Name: phone_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY phone
    ADD CONSTRAINT phone_pkey PRIMARY KEY (phoneid);


--
-- TOC entry 3701 (class 2606 OID 30933)
-- Name: pluginsetting_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pluginsetting
    ADD CONSTRAINT pluginsetting_pkey PRIMARY KEY (pluginsettingid);


--
-- TOC entry 4414 (class 2606 OID 32528)
-- Name: pm_userthread_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pm_userthread
    ADD CONSTRAINT pm_userthread_pkey PRIMARY KEY (userthreadid);


--
-- TOC entry 4452 (class 2606 OID 32618)
-- Name: pollschoice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pollschoice
    ADD CONSTRAINT pollschoice_pkey PRIMARY KEY (choiceid);


--
-- TOC entry 4457 (class 2606 OID 32626)
-- Name: pollsquestion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pollsquestion
    ADD CONSTRAINT pollsquestion_pkey PRIMARY KEY (questionid);


--
-- TOC entry 4463 (class 2606 OID 32631)
-- Name: pollsvote_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pollsvote
    ADD CONSTRAINT pollsvote_pkey PRIMARY KEY (voteid);


--
-- TOC entry 3704 (class 2606 OID 30942)
-- Name: portalpreferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY portalpreferences
    ADD CONSTRAINT portalpreferences_pkey PRIMARY KEY (portalpreferencesid);


--
-- TOC entry 3707 (class 2606 OID 30951)
-- Name: portlet_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY portlet
    ADD CONSTRAINT portlet_pkey PRIMARY KEY (id_);


--
-- TOC entry 3712 (class 2606 OID 30957)
-- Name: portletitem_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY portletitem
    ADD CONSTRAINT portletitem_pkey PRIMARY KEY (portletitemid);


--
-- TOC entry 3720 (class 2606 OID 30966)
-- Name: portletpreferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY portletpreferences
    ADD CONSTRAINT portletpreferences_pkey PRIMARY KEY (portletpreferencesid);


--
-- TOC entry 4277 (class 2606 OID 32300)
-- Name: pushnotificationsdevice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY pushnotificationsdevice
    ADD CONSTRAINT pushnotificationsdevice_pkey PRIMARY KEY (pushnotificationsdeviceid);


--
-- TOC entry 3250 (class 2606 OID 30360)
-- Name: quartz_blob_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_blob_triggers
    ADD CONSTRAINT quartz_blob_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3252 (class 2606 OID 30368)
-- Name: quartz_calendars_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_calendars
    ADD CONSTRAINT quartz_calendars_pkey PRIMARY KEY (sched_name, calendar_name);


--
-- TOC entry 3254 (class 2606 OID 30376)
-- Name: quartz_cron_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_cron_triggers
    ADD CONSTRAINT quartz_cron_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3262 (class 2606 OID 30384)
-- Name: quartz_fired_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_fired_triggers
    ADD CONSTRAINT quartz_fired_triggers_pkey PRIMARY KEY (sched_name, entry_id);


--
-- TOC entry 3266 (class 2606 OID 30392)
-- Name: quartz_job_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_job_details
    ADD CONSTRAINT quartz_job_details_pkey PRIMARY KEY (sched_name, job_name, job_group);


--
-- TOC entry 3268 (class 2606 OID 30397)
-- Name: quartz_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_locks
    ADD CONSTRAINT quartz_locks_pkey PRIMARY KEY (sched_name, lock_name);


--
-- TOC entry 3270 (class 2606 OID 30402)
-- Name: quartz_paused_trigger_grps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_paused_trigger_grps
    ADD CONSTRAINT quartz_paused_trigger_grps_pkey PRIMARY KEY (sched_name, trigger_group);


--
-- TOC entry 3272 (class 2606 OID 30407)
-- Name: quartz_scheduler_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_scheduler_state
    ADD CONSTRAINT quartz_scheduler_state_pkey PRIMARY KEY (sched_name, instance_name);


--
-- TOC entry 3274 (class 2606 OID 30415)
-- Name: quartz_simple_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_simple_triggers
    ADD CONSTRAINT quartz_simple_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3276 (class 2606 OID 30423)
-- Name: quartz_simprop_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_simprop_triggers
    ADD CONSTRAINT quartz_simprop_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3290 (class 2606 OID 30431)
-- Name: quartz_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY quartz_triggers
    ADD CONSTRAINT quartz_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3725 (class 2606 OID 30971)
-- Name: ratingsentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ratingsentry
    ADD CONSTRAINT ratingsentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3728 (class 2606 OID 30976)
-- Name: ratingsstats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ratingsstats
    ADD CONSTRAINT ratingsstats_pkey PRIMARY KEY (statsid);


--
-- TOC entry 3733 (class 2606 OID 30982)
-- Name: recentlayoutbranch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY recentlayoutbranch
    ADD CONSTRAINT recentlayoutbranch_pkey PRIMARY KEY (recentlayoutbranchid);


--
-- TOC entry 3738 (class 2606 OID 30988)
-- Name: recentlayoutrevision_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY recentlayoutrevision
    ADD CONSTRAINT recentlayoutrevision_pkey PRIMARY KEY (recentlayoutrevisionid);


--
-- TOC entry 3743 (class 2606 OID 30994)
-- Name: recentlayoutsetbranch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY recentlayoutsetbranch
    ADD CONSTRAINT recentlayoutsetbranch_pkey PRIMARY KEY (recentlayoutsetbranchid);


--
-- TOC entry 3748 (class 2606 OID 31000)
-- Name: region_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY region
    ADD CONSTRAINT region_pkey PRIMARY KEY (regionid);


--
-- TOC entry 3751 (class 2606 OID 31009)
-- Name: release__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY release_
    ADD CONSTRAINT release__pkey PRIMARY KEY (releaseid);


--
-- TOC entry 3756 (class 2606 OID 31018)
-- Name: repository_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY repository
    ADD CONSTRAINT repository_pkey PRIMARY KEY (repositoryid);


--
-- TOC entry 3761 (class 2606 OID 31024)
-- Name: repositoryentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY repositoryentry
    ADD CONSTRAINT repositoryentry_pkey PRIMARY KEY (repositoryentryid);


--
-- TOC entry 3764 (class 2606 OID 31030)
-- Name: resourceaction_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY resourceaction
    ADD CONSTRAINT resourceaction_pkey PRIMARY KEY (resourceactionid);


--
-- TOC entry 3768 (class 2606 OID 31036)
-- Name: resourceblock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY resourceblock
    ADD CONSTRAINT resourceblock_pkey PRIMARY KEY (resourceblockid);


--
-- TOC entry 3772 (class 2606 OID 31042)
-- Name: resourceblockpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY resourceblockpermission
    ADD CONSTRAINT resourceblockpermission_pkey PRIMARY KEY (resourceblockpermissionid);


--
-- TOC entry 3781 (class 2606 OID 31051)
-- Name: resourcepermission_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY resourcepermission
    ADD CONSTRAINT resourcepermission_pkey PRIMARY KEY (resourcepermissionid);


--
-- TOC entry 3786 (class 2606 OID 31057)
-- Name: resourcetypepermission_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY resourcetypepermission
    ADD CONSTRAINT resourcetypepermission_pkey PRIMARY KEY (resourcetypepermissionid);


--
-- TOC entry 3795 (class 2606 OID 31066)
-- Name: role__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY role_
    ADD CONSTRAINT role__pkey PRIMARY KEY (roleid);


--
-- TOC entry 3993 (class 2606 OID 31770)
-- Name: sapentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY sapentry
    ADD CONSTRAINT sapentry_pkey PRIMARY KEY (sapentryid);


--
-- TOC entry 3798 (class 2606 OID 31075)
-- Name: servicecomponent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY servicecomponent
    ADD CONSTRAINT servicecomponent_pkey PRIMARY KEY (servicecomponentid);


--
-- TOC entry 4418 (class 2606 OID 32540)
-- Name: shoppingcart_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingcart
    ADD CONSTRAINT shoppingcart_pkey PRIMARY KEY (cartid);


--
-- TOC entry 4422 (class 2606 OID 32548)
-- Name: shoppingcategory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingcategory
    ADD CONSTRAINT shoppingcategory_pkey PRIMARY KEY (categoryid);


--
-- TOC entry 4426 (class 2606 OID 32556)
-- Name: shoppingcoupon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingcoupon
    ADD CONSTRAINT shoppingcoupon_pkey PRIMARY KEY (couponid);


--
-- TOC entry 4433 (class 2606 OID 32564)
-- Name: shoppingitem_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingitem
    ADD CONSTRAINT shoppingitem_pkey PRIMARY KEY (itemid);


--
-- TOC entry 4436 (class 2606 OID 32572)
-- Name: shoppingitemfield_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingitemfield
    ADD CONSTRAINT shoppingitemfield_pkey PRIMARY KEY (itemfieldid);


--
-- TOC entry 4439 (class 2606 OID 32577)
-- Name: shoppingitemprice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingitemprice
    ADD CONSTRAINT shoppingitemprice_pkey PRIMARY KEY (itempriceid);


--
-- TOC entry 4444 (class 2606 OID 32585)
-- Name: shoppingorder_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingorder
    ADD CONSTRAINT shoppingorder_pkey PRIMARY KEY (orderid);


--
-- TOC entry 4447 (class 2606 OID 32593)
-- Name: shoppingorderitem_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY shoppingorderitem
    ADD CONSTRAINT shoppingorderitem_pkey PRIMARY KEY (orderitemid);


--
-- TOC entry 4334 (class 2606 OID 32405)
-- Name: sn_meetupsentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY sn_meetupsentry
    ADD CONSTRAINT sn_meetupsentry_pkey PRIMARY KEY (meetupsentryid);


--
-- TOC entry 4338 (class 2606 OID 32410)
-- Name: sn_meetupsregistration_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY sn_meetupsregistration
    ADD CONSTRAINT sn_meetupsregistration_pkey PRIMARY KEY (meetupsregistrationid);


--
-- TOC entry 4342 (class 2606 OID 32415)
-- Name: sn_wallentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY sn_wallentry
    ADD CONSTRAINT sn_wallentry_pkey PRIMARY KEY (wallentryid);


--
-- TOC entry 4312 (class 2606 OID 32361)
-- Name: so_memberrequest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY so_memberrequest
    ADD CONSTRAINT so_memberrequest_pkey PRIMARY KEY (memberrequestid);


--
-- TOC entry 3808 (class 2606 OID 31083)
-- Name: socialactivity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivity
    ADD CONSTRAINT socialactivity_pkey PRIMARY KEY (activityid);


--
-- TOC entry 3814 (class 2606 OID 31088)
-- Name: socialactivityachievement_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivityachievement
    ADD CONSTRAINT socialactivityachievement_pkey PRIMARY KEY (activityachievementid);


--
-- TOC entry 3820 (class 2606 OID 31093)
-- Name: socialactivitycounter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivitycounter
    ADD CONSTRAINT socialactivitycounter_pkey PRIMARY KEY (activitycounterid);


--
-- TOC entry 3825 (class 2606 OID 31098)
-- Name: socialactivitylimit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivitylimit
    ADD CONSTRAINT socialactivitylimit_pkey PRIMARY KEY (activitylimitid);


--
-- TOC entry 3831 (class 2606 OID 31106)
-- Name: socialactivityset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivityset
    ADD CONSTRAINT socialactivityset_pkey PRIMARY KEY (activitysetid);


--
-- TOC entry 3835 (class 2606 OID 31114)
-- Name: socialactivitysetting_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialactivitysetting
    ADD CONSTRAINT socialactivitysetting_pkey PRIMARY KEY (activitysettingid);


--
-- TOC entry 3843 (class 2606 OID 31119)
-- Name: socialrelation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialrelation
    ADD CONSTRAINT socialrelation_pkey PRIMARY KEY (relationid);


--
-- TOC entry 3853 (class 2606 OID 31127)
-- Name: socialrequest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY socialrequest
    ADD CONSTRAINT socialrequest_pkey PRIMARY KEY (requestid);


--
-- TOC entry 3859 (class 2606 OID 31133)
-- Name: subscription_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subscription
    ADD CONSTRAINT subscription_pkey PRIMARY KEY (subscriptionid);


--
-- TOC entry 4408 (class 2606 OID 32509)
-- Name: syncdevice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY syncdevice
    ADD CONSTRAINT syncdevice_pkey PRIMARY KEY (syncdeviceid);


--
-- TOC entry 4392 (class 2606 OID 32496)
-- Name: syncdlfileversiondiff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY syncdlfileversiondiff
    ADD CONSTRAINT syncdlfileversiondiff_pkey PRIMARY KEY (syncdlfileversiondiffid);


--
-- TOC entry 4403 (class 2606 OID 32504)
-- Name: syncdlobject_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY syncdlobject
    ADD CONSTRAINT syncdlobject_pkey PRIMARY KEY (syncdlobjectid);


--
-- TOC entry 3863 (class 2606 OID 31142)
-- Name: systemevent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY systemevent
    ADD CONSTRAINT systemevent_pkey PRIMARY KEY (systemeventid);


--
-- TOC entry 3868 (class 2606 OID 31151)
-- Name: team_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY team
    ADD CONSTRAINT team_pkey PRIMARY KEY (teamid);


--
-- TOC entry 3872 (class 2606 OID 31160)
-- Name: ticket_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY ticket
    ADD CONSTRAINT ticket_pkey PRIMARY KEY (ticketid);


--
-- TOC entry 3878 (class 2606 OID 31168)
-- Name: trashentry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY trashentry
    ADD CONSTRAINT trashentry_pkey PRIMARY KEY (entryid);


--
-- TOC entry 3882 (class 2606 OID 31176)
-- Name: trashversion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY trashversion
    ADD CONSTRAINT trashversion_pkey PRIMARY KEY (versionid);


--
-- TOC entry 3901 (class 2606 OID 31191)
-- Name: user__pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY user_
    ADD CONSTRAINT user__pkey PRIMARY KEY (userid);


--
-- TOC entry 3906 (class 2606 OID 31200)
-- Name: usergroup_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usergroup
    ADD CONSTRAINT usergroup_pkey PRIMARY KEY (usergroupid);


--
-- TOC entry 3911 (class 2606 OID 31206)
-- Name: usergroupgrouprole_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usergroupgrouprole
    ADD CONSTRAINT usergroupgrouprole_pkey PRIMARY KEY (usergroupid, groupid, roleid);


--
-- TOC entry 3916 (class 2606 OID 31212)
-- Name: usergrouprole_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usergrouprole
    ADD CONSTRAINT usergrouprole_pkey PRIMARY KEY (userid, groupid, roleid);


--
-- TOC entry 3921 (class 2606 OID 31217)
-- Name: usergroups_teams_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usergroups_teams
    ADD CONSTRAINT usergroups_teams_pkey PRIMARY KEY (teamid, usergroupid);


--
-- TOC entry 3925 (class 2606 OID 31223)
-- Name: useridmapper_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY useridmapper
    ADD CONSTRAINT useridmapper_pkey PRIMARY KEY (useridmapperid);


--
-- TOC entry 3885 (class 2606 OID 31182)
-- Name: usernotificationdelivery_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usernotificationdelivery
    ADD CONSTRAINT usernotificationdelivery_pkey PRIMARY KEY (usernotificationdeliveryid);


--
-- TOC entry 3936 (class 2606 OID 31232)
-- Name: usernotificationevent_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usernotificationevent
    ADD CONSTRAINT usernotificationevent_pkey PRIMARY KEY (usernotificationeventid);


--
-- TOC entry 3941 (class 2606 OID 31237)
-- Name: users_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY users_groups
    ADD CONSTRAINT users_groups_pkey PRIMARY KEY (groupid, userid);


--
-- TOC entry 3946 (class 2606 OID 31242)
-- Name: users_orgs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY users_orgs
    ADD CONSTRAINT users_orgs_pkey PRIMARY KEY (organizationid, userid);


--
-- TOC entry 3951 (class 2606 OID 31247)
-- Name: users_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY users_roles
    ADD CONSTRAINT users_roles_pkey PRIMARY KEY (roleid, userid);


--
-- TOC entry 3956 (class 2606 OID 31252)
-- Name: users_teams_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY users_teams
    ADD CONSTRAINT users_teams_pkey PRIMARY KEY (teamid, userid);


--
-- TOC entry 3961 (class 2606 OID 31257)
-- Name: users_usergroups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY users_usergroups
    ADD CONSTRAINT users_usergroups_pkey PRIMARY KEY (userid, usergroupid);


--
-- TOC entry 3966 (class 2606 OID 31266)
-- Name: usertracker_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usertracker
    ADD CONSTRAINT usertracker_pkey PRIMARY KEY (usertrackerid);


--
-- TOC entry 3969 (class 2606 OID 31275)
-- Name: usertrackerpath_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY usertrackerpath
    ADD CONSTRAINT usertrackerpath_pkey PRIMARY KEY (usertrackerpathid);


--
-- TOC entry 3973 (class 2606 OID 31281)
-- Name: virtualhost_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY virtualhost
    ADD CONSTRAINT virtualhost_pkey PRIMARY KEY (virtualhostid);


--
-- TOC entry 3976 (class 2606 OID 31290)
-- Name: webdavprops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY webdavprops
    ADD CONSTRAINT webdavprops_pkey PRIMARY KEY (webdavpropsid);


--
-- TOC entry 3981 (class 2606 OID 31299)
-- Name: website_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY website
    ADD CONSTRAINT website_pkey PRIMARY KEY (websiteid);


--
-- TOC entry 4157 (class 2606 OID 32075)
-- Name: wikinode_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY wikinode
    ADD CONSTRAINT wikinode_pkey PRIMARY KEY (nodeid);


--
-- TOC entry 4181 (class 2606 OID 32083)
-- Name: wikipage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY wikipage
    ADD CONSTRAINT wikipage_pkey PRIMARY KEY (pageid);


--
-- TOC entry 4186 (class 2606 OID 32088)
-- Name: wikipageresource_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY wikipageresource
    ADD CONSTRAINT wikipageresource_pkey PRIMARY KEY (resourceprimkey);


--
-- TOC entry 3985 (class 2606 OID 31305)
-- Name: workflowdefinitionlink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY workflowdefinitionlink
    ADD CONSTRAINT workflowdefinitionlink_pkey PRIMARY KEY (workflowdefinitionlinkid);


--
-- TOC entry 3988 (class 2606 OID 31311)
-- Name: workflowinstancelink_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY workflowinstancelink
    ADD CONSTRAINT workflowinstancelink_pkey PRIMARY KEY (workflowinstancelinkid);


--
-- TOC entry 4540 (class 2606 OID 32822)
-- Name: xattr_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY xattr
    ADD CONSTRAINT xattr_pkey PRIMARY KEY (id);


--
-- TOC entry 4532 (class 1259 OID 32835)
-- Name: data_block_no_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX data_block_no_idx ON data USING btree (block_no);


--
-- TOC entry 4533 (class 1259 OID 32834)
-- Name: data_dir_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX data_dir_id_idx ON data USING btree (dir_id);


--
-- TOC entry 4531 (class 1259 OID 32837)
-- Name: dir_parent_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX dir_parent_id_idx ON dir_fs USING btree (parent_id);


--
-- TOC entry 4122 (class 1259 OID 32049)
-- Name: ix_103d6207; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_103d6207 ON journalarticleimage USING btree (groupid, articleid, version, elinstanceid, elname, languageid);


--
-- TOC entry 4052 (class 1259 OID 31948)
-- Name: ix_1087068e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1087068e ON kaleotaskassignment USING btree (kaleoclassname, kaleoclasspk, assigneeclassname);


--
-- TOC entry 3334 (class 1259 OID 31337)
-- Name: ix_112337b8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_112337b8 ON assetentries_assettags USING btree (companyid);


--
-- TOC entry 4472 (class 1259 OID 32678)
-- Name: ix_113a264e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_113a264e ON calendarbooking USING btree (calendarid, parentcalendarbookingid);


--
-- TOC entry 3752 (class 1259 OID 31613)
-- Name: ix_11641e26; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_11641e26 ON repository USING btree (uuid_, groupid);


--
-- TOC entry 4440 (class 1259 OID 32607)
-- Name: ix_119b5630; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_119b5630 ON shoppingorder USING btree (groupid, userid, pppaymentstatus);


--
-- TOC entry 3744 (class 1259 OID 31608)
-- Name: ix_11fb3e42; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_11fb3e42 ON region USING btree (countryid, active_);


--
-- TOC entry 3799 (class 1259 OID 31646)
-- Name: ix_121ca3cb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_121ca3cb ON socialactivity USING btree (receiveruserid);


--
-- TOC entry 3395 (class 1259 OID 31377)
-- Name: ix_12566ec2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_12566ec2 ON company USING btree (mx);


--
-- TOC entry 4255 (class 1259 OID 32272)
-- Name: ix_127a35b0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_127a35b0 ON ddmtemplate USING btree (smallimageid);


--
-- TOC entry 3854 (class 1259 OID 31681)
-- Name: ix_1290b81; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1290b81 ON subscription USING btree (groupid, userid);


--
-- TOC entry 3836 (class 1259 OID 31668)
-- Name: ix_12a92145; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_12a92145 ON socialrelation USING btree (userid1, userid2, type_);


--
-- TOC entry 3705 (class 1259 OID 31584)
-- Name: ix_12b5e51d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_12b5e51d ON portlet USING btree (companyid, portletid);


--
-- TOC entry 4182 (class 1259 OID 32117)
-- Name: ix_13319367; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_13319367 ON wikipageresource USING btree (uuid_, companyid);


--
-- TOC entry 4217 (class 1259 OID 32243)
-- Name: ix_1333a2a7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1333a2a7 ON ddmdataproviderinstance USING btree (groupid);


--
-- TOC entry 3577 (class 1259 OID 31504)
-- Name: ix_13984800; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_13984800 ON layoutrevision USING btree (layoutsetbranchid, layoutbranchid, plid);


--
-- TOC entry 3439 (class 1259 OID 31408)
-- Name: ix_1399d844; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1399d844 ON dlfileentrytype USING btree (uuid_, groupid);


--
-- TOC entry 4074 (class 1259 OID 31963)
-- Name: ix_13a5ba2c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_13a5ba2c ON kaleotimerinstancetoken USING btree (kaleoinstancetokenid, kaleotimerid);


--
-- TOC entry 3609 (class 1259 OID 31526)
-- Name: ix_13df4e6d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_13df4e6d ON mbcategory USING btree (uuid_, companyid);


--
-- TOC entry 3864 (class 1259 OID 31685)
-- Name: ix_143dc786; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_143dc786 ON team USING btree (groupid, name);


--
-- TOC entry 4293 (class 1259 OID 32345)
-- Name: ix_146382f2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_146382f2 ON bookmarksentry USING btree (groupid, folderid, status);


--
-- TOC entry 4508 (class 1259 OID 32737)
-- Name: ix_14acfa9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_14acfa9 ON microblogsentry USING btree (creatorclassnameid, creatorclasspk, type_);


--
-- TOC entry 3348 (class 1259 OID 31348)
-- Name: ix_14d5a20d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_14d5a20d ON assetlink USING btree (entryid1, type_);


--
-- TOC entry 3967 (class 1259 OID 31723)
-- Name: ix_14d8bcc0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_14d8bcc0 ON usertrackerpath USING btree (usertrackerid);


--
-- TOC entry 3304 (class 1259 OID 31317)
-- Name: ix_14f06a6b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_14f06a6b ON announcementsentry USING btree (classnameid, classpk, alert);


--
-- TOC entry 3515 (class 1259 OID 31467)
-- Name: ix_16218a38; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_16218a38 ON group_ USING btree (livegroupid);


--
-- TOC entry 4504 (class 1259 OID 32726)
-- Name: ix_163ebd83; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_163ebd83 ON mail_message USING btree (companyid);


--
-- TOC entry 4308 (class 1259 OID 32364)
-- Name: ix_16475447; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_16475447 ON so_memberrequest USING btree (receiveruserid, status);


--
-- TOC entry 4487 (class 1259 OID 32690)
-- Name: ix_16a12327; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_16a12327 ON calendarresource USING btree (classnameid, classpk);


--
-- TOC entry 4158 (class 1259 OID 32112)
-- Name: ix_1725355c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1725355c ON wikipage USING btree (resourceprimkey, status);


--
-- TOC entry 4247 (class 1259 OID 32263)
-- Name: ix_17692b58; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_17692b58 ON ddmstructurelink USING btree (structureid);


--
-- TOC entry 4404 (class 1259 OID 32521)
-- Name: ix_176df87b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_176df87b ON syncdevice USING btree (companyid, username);


--
-- TOC entry 4095 (class 1259 OID 32024)
-- Name: ix_17806804; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_17806804 ON journalarticle USING btree (ddmstructurekey);


--
-- TOC entry 4251 (class 1259 OID 32264)
-- Name: ix_17b3c96c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_17b3c96c ON ddmstructureversion USING btree (structureid, status);


--
-- TOC entry 3455 (class 1259 OID 31417)
-- Name: ix_17ee3098; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_17ee3098 ON dlfileshortcut USING btree (groupid, folderid, active_, status);


--
-- TOC entry 3510 (class 1259 OID 31453)
-- Name: ix_1827a2e5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1827a2e5 ON exportimportconfiguration USING btree (companyid);


--
-- TOC entry 3277 (class 1259 OID 30440)
-- Name: ix_186442a4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_186442a4 ON quartz_triggers USING btree (sched_name, trigger_name, trigger_group, trigger_state);


--
-- TOC entry 3408 (class 1259 OID 31386)
-- Name: ix_19da007b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_19da007b ON country USING btree (name);


--
-- TOC entry 3548 (class 1259 OID 31486)
-- Name: ix_1a1b61d2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1a1b61d2 ON layout USING btree (groupid, privatelayout, type_);


--
-- TOC entry 4071 (class 1259 OID 31960)
-- Name: ix_1a479f32; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1a479f32 ON kaleotimer USING btree (kaleoclassname, kaleoclasspk, blocking);


--
-- TOC entry 3977 (class 1259 OID 31756)
-- Name: ix_1aa07a6d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1aa07a6d ON website USING btree (companyid, classnameid, classpk, primary_);


--
-- TOC entry 4256 (class 1259 OID 32276)
-- Name: ix_1aa75ce3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1aa75ce3 ON ddmtemplate USING btree (uuid_, groupid);


--
-- TOC entry 3629 (class 1259 OID 31537)
-- Name: ix_1ad93c16; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1ad93c16 ON mbmessage USING btree (companyid, status);


--
-- TOC entry 3368 (class 1259 OID 31369)
-- Name: ix_1b1040fd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1b1040fd ON blogsentry USING btree (uuid_, groupid);


--
-- TOC entry 3362 (class 1259 OID 31358)
-- Name: ix_1b2b8792; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1b2b8792 ON assetvocabulary USING btree (uuid_, groupid);


--
-- TOC entry 3417 (class 1259 OID 31398)
-- Name: ix_1b352f4a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1b352f4a ON dlfileentry USING btree (repositoryid, folderid);


--
-- TOC entry 3815 (class 1259 OID 31653)
-- Name: ix_1b7e3b67; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1b7e3b67 ON socialactivitycounter USING btree (groupid, classnameid, classpk, name, ownertype, endperiod);


--
-- TOC entry 3278 (class 1259 OID 30441)
-- Name: ix_1ba1f9dc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1ba1f9dc ON quartz_triggers USING btree (sched_name, trigger_group);


--
-- TOC entry 4458 (class 1259 OID 32639)
-- Name: ix_1bbfd4d3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1bbfd4d3 ON pollsvote USING btree (questionid, userid);


--
-- TOC entry 3502 (class 1259 OID 31450)
-- Name: ix_1bd3f4c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1bd3f4c ON expandovalue USING btree (tableid, classpk);


--
-- TOC entry 4427 (class 1259 OID 32600)
-- Name: ix_1c717ca6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1c717ca6 ON shoppingitem USING btree (companyid, sku);


--
-- TOC entry 4393 (class 1259 OID 32520)
-- Name: ix_1cca3b5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1cca3b5 ON syncdlobject USING btree (version, type_);


--
-- TOC entry 3907 (class 1259 OID 31700)
-- Name: ix_1cdf88c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1cdf88c ON usergroupgrouprole USING btree (roleid);


--
-- TOC entry 3886 (class 1259 OID 31727)
-- Name: ix_1d731f03; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1d731f03 ON user_ USING btree (companyid, facebookid);


--
-- TOC entry 4343 (class 1259 OID 32467)
-- Name: ix_1dcc5f79; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1dcc5f79 ON kbarticle USING btree (parentresourceprimkey, main);


--
-- TOC entry 4419 (class 1259 OID 32597)
-- Name: ix_1e6464f5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1e6464f5 ON shoppingcategory USING btree (groupid, parentcategoryid);


--
-- TOC entry 3869 (class 1259 OID 31688)
-- Name: ix_1e8dfb2e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1e8dfb2e ON ticket USING btree (classnameid, classpk, type_);


--
-- TOC entry 3339 (class 1259 OID 31340)
-- Name: ix_1e9d371d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1e9d371d ON assetentry USING btree (classnameid, classpk);


--
-- TOC entry 3340 (class 1259 OID 31343)
-- Name: ix_1eba6821; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1eba6821 ON assetentry USING btree (groupid, classuuid);


--
-- TOC entry 4159 (class 1259 OID 32104)
-- Name: ix_1ecc7656; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1ecc7656 ON wikipage USING btree (nodeid, redirecttitle);


--
-- TOC entry 3369 (class 1259 OID 31364)
-- Name: ix_1efd8ee9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1efd8ee9 ON blogsentry USING btree (groupid, status);


--
-- TOC entry 3800 (class 1259 OID 31645)
-- Name: ix_1f00c374; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1f00c374 ON socialactivity USING btree (mirroractivityid, classnameid, classpk);


--
-- TOC entry 3279 (class 1259 OID 30449)
-- Name: ix_1f92813c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1f92813c ON quartz_triggers USING btree (sched_name, next_fire_time, misfire_instr);


--
-- TOC entry 4378 (class 1259 OID 32488)
-- Name: ix_1fd022a1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_1fd022a1 ON kbfolder USING btree (uuid_, groupid);


--
-- TOC entry 3433 (class 1259 OID 31404)
-- Name: ix_1fe9c04; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_1fe9c04 ON dlfileentrymetadata USING btree (fileversionid);


--
-- TOC entry 3313 (class 1259 OID 31325)
-- Name: ix_2008facb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2008facb ON assetcategory USING btree (groupid, vocabularyid);


--
-- TOC entry 4505 (class 1259 OID 32727)
-- Name: ix_200d262a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_200d262a ON mail_message USING btree (folderid, remotemessageid);


--
-- TOC entry 3255 (class 1259 OID 30436)
-- Name: ix_204d31e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_204d31e8 ON quartz_fired_triggers USING btree (sched_name, instance_name);


--
-- TOC entry 3769 (class 1259 OID 31621)
-- Name: ix_20a2e3d9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_20a2e3d9 ON resourceblockpermission USING btree (roleid);


--
-- TOC entry 4278 (class 1259 OID 32321)
-- Name: ix_20f14d93; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_20f14d93 ON marketplace_app USING btree (remoteappid);


--
-- TOC entry 4232 (class 1259 OID 32256)
-- Name: ix_20fde04c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_20fde04c ON ddmstructure USING btree (structurekey);


--
-- TOC entry 4183 (class 1259 OID 32116)
-- Name: ix_21277664; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_21277664 ON wikipageresource USING btree (nodeid, title);


--
-- TOC entry 4309 (class 1259 OID 32363)
-- Name: ix_212fa0ec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_212fa0ec ON so_memberrequest USING btree (key_);


--
-- TOC entry 3994 (class 1259 OID 31783)
-- Name: ix_228562ad; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_228562ad ON lock_ USING btree (classname, key_);


--
-- TOC entry 4202 (class 1259 OID 32158)
-- Name: ix_22dab85c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_22dab85c ON mdrrulegroupinstance USING btree (groupid, classnameid, classpk);


--
-- TOC entry 4473 (class 1259 OID 32683)
-- Name: ix_22dfdb49; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_22dfdb49 ON calendarbooking USING btree (resourceblockid);


--
-- TOC entry 4151 (class 1259 OID 32091)
-- Name: ix_23325358; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_23325358 ON wikinode USING btree (groupid, status);


--
-- TOC entry 3549 (class 1259 OID 31487)
-- Name: ix_23922f7d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_23922f7d ON layout USING btree (iconimageid);


--
-- TOC entry 3902 (class 1259 OID 31696)
-- Name: ix_23ead0d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_23ead0d ON usergroup USING btree (companyid, name);


--
-- TOC entry 3739 (class 1259 OID 31605)
-- Name: ix_23ff0700; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_23ff0700 ON recentlayoutsetbranch USING btree (layoutsetbranchid);


--
-- TOC entry 4203 (class 1259 OID 32160)
-- Name: ix_25c9d1f7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_25c9d1f7 ON mdrrulegroupinstance USING btree (uuid_, companyid);


--
-- TOC entry 3409 (class 1259 OID 31385)
-- Name: ix_25d734cd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_25d734cd ON country USING btree (active_);


--
-- TOC entry 3418 (class 1259 OID 31399)
-- Name: ix_25f5cab9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_25f5cab9 ON dlfileentry USING btree (smallimageid, largeimageid, custom1imageid, custom2imageid);


--
-- TOC entry 3773 (class 1259 OID 31624)
-- Name: ix_26284944; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_26284944 ON resourcepermission USING btree (companyid, primkey);


--
-- TOC entry 3370 (class 1259 OID 31362)
-- Name: ix_2672f77f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2672f77f ON blogsentry USING btree (displaydate, status);


--
-- TOC entry 3873 (class 1259 OID 31691)
-- Name: ix_2674f2a8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2674f2a8 ON trashentry USING btree (companyid);


--
-- TOC entry 3516 (class 1259 OID 31469)
-- Name: ix_26cc761a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_26cc761a ON group_ USING btree (uuid_, companyid);


--
-- TOC entry 4324 (class 1259 OID 32398)
-- Name: ix_270ba5e1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_270ba5e1 ON ddlrecordset USING btree (uuid_, groupid);


--
-- TOC entry 4294 (class 1259 OID 32344)
-- Name: ix_276c8c13; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_276c8c13 ON bookmarksentry USING btree (companyid, status);


--
-- TOC entry 3314 (class 1259 OID 31331)
-- Name: ix_287b1f89; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_287b1f89 ON assetcategory USING btree (vocabularyid);


--
-- TOC entry 4303 (class 1259 OID 32354)
-- Name: ix_28a49bb9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_28a49bb9 ON bookmarksfolder USING btree (resourceblockid);


--
-- TOC entry 3381 (class 1259 OID 31371)
-- Name: ix_28c78d5c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_28c78d5c ON blogsstatsuser USING btree (groupid, entrycount);


--
-- TOC entry 4394 (class 1259 OID 32519)
-- Name: ix_28cd54bb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_28cd54bb ON syncdlobject USING btree (type_, version);


--
-- TOC entry 3598 (class 1259 OID 31516)
-- Name: ix_2932dd37; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2932dd37 ON listtype USING btree (type_);


--
-- TOC entry 3456 (class 1259 OID 31419)
-- Name: ix_29ae81c4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_29ae81c4 ON dlfileshortcut USING btree (uuid_, companyid);


--
-- TOC entry 3962 (class 1259 OID 31720)
-- Name: ix_29ba1cf5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_29ba1cf5 ON usertracker USING btree (companyid);


--
-- TOC entry 3419 (class 1259 OID 31392)
-- Name: ix_29d0af28; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_29d0af28 ON dlfileentry USING btree (groupid, folderid, fileentrytypeid);


--
-- TOC entry 3487 (class 1259 OID 31440)
-- Name: ix_2a2cb130; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2a2cb130 ON emailaddress USING btree (companyid, classnameid, classpk, primary_);


--
-- TOC entry 3602 (class 1259 OID 31521)
-- Name: ix_2a3b68f6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_2a3b68f6 ON mbban USING btree (uuid_, groupid);


--
-- TOC entry 3917 (class 1259 OID 31705)
-- Name: ix_2ac5356c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2ac5356c ON usergroups_teams USING btree (companyid);


--
-- TOC entry 4344 (class 1259 OID 32457)
-- Name: ix_2b11f674; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2b11f674 ON kbarticle USING btree (groupid, kbfolderid, latest);


--
-- TOC entry 4345 (class 1259 OID 32468)
-- Name: ix_2b6103f2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2b6103f2 ON kbarticle USING btree (parentresourceprimkey, status);


--
-- TOC entry 3682 (class 1259 OID 31573)
-- Name: ix_2c1142e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2c1142e ON passwordpolicy USING btree (companyid, defaultpolicy);


--
-- TOC entry 3995 (class 1259 OID 31785)
-- Name: ix_2c418eae; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2c418eae ON lock_ USING btree (uuid_, companyid);


--
-- TOC entry 4042 (class 1259 OID 31941)
-- Name: ix_2c8c4af4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2c8c4af4 ON kaleonotificationrecipient USING btree (companyid);


--
-- TOC entry 4160 (class 1259 OID 32111)
-- Name: ix_2cd67c81; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_2cd67c81 ON wikipage USING btree (resourceprimkey, nodeid, version);


--
-- TOC entry 3550 (class 1259 OID 31490)
-- Name: ix_2ce4be84; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2ce4be84 ON layout USING btree (uuid_, companyid);


--
-- TOC entry 3765 (class 1259 OID 31619)
-- Name: ix_2d4cc782; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2d4cc782 ON resourceblock USING btree (companyid, name);


--
-- TOC entry 3745 (class 1259 OID 31607)
-- Name: ix_2d9a426f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2d9a426f ON region USING btree (active_);


--
-- TOC entry 3855 (class 1259 OID 31680)
-- Name: ix_2e1a92d4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_2e1a92d4 ON subscription USING btree (companyid, userid, classnameid, classpk);


--
-- TOC entry 3341 (class 1259 OID 31345)
-- Name: ix_2e4e3885; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2e4e3885 ON assetentry USING btree (publishdate);


--
-- TOC entry 3444 (class 1259 OID 31409)
-- Name: ix_2e64d9f9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2e64d9f9 ON dlfileentrytypes_dlfolders USING btree (companyid);


--
-- TOC entry 3335 (class 1259 OID 31338)
-- Name: ix_2ed82cad; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2ed82cad ON assetentries_assettags USING btree (entryid);


--
-- TOC entry 4274 (class 1259 OID 32301)
-- Name: ix_2f3edc9f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_2f3edc9f ON pushnotificationsdevice USING btree (token);


--
-- TOC entry 4275 (class 1259 OID 32302)
-- Name: ix_2fbf066b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2fbf066b ON pushnotificationsdevice USING btree (userid, platform);


--
-- TOC entry 4087 (class 1259 OID 31984)
-- Name: ix_2fcfe748; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_2fcfe748 ON backgroundtask USING btree (taskexecutorclassname, status);


--
-- TOC entry 4096 (class 1259 OID 32040)
-- Name: ix_301d024b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_301d024b ON journalarticle USING btree (groupid, status);


--
-- TOC entry 3537 (class 1259 OID 31476)
-- Name: ix_3103ef3d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3103ef3d ON groups_roles USING btree (roleid);


--
-- TOC entry 3420 (class 1259 OID 31400)
-- Name: ix_31079de8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_31079de8 ON dlfileentry USING btree (uuid_, companyid);


--
-- TOC entry 4501 (class 1259 OID 32725)
-- Name: ix_310e554a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_310e554a ON mail_folder USING btree (accountid, fullname);


--
-- TOC entry 4233 (class 1259 OID 32251)
-- Name: ix_31817a62; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_31817a62 ON ddmstructure USING btree (classnameid);


--
-- TOC entry 4097 (class 1259 OID 32031)
-- Name: ix_31b74f51; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_31b74f51 ON journalarticle USING btree (groupid, ddmtemplatekey);


--
-- TOC entry 3918 (class 1259 OID 31706)
-- Name: ix_31fb0b08; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_31fb0b08 ON usergroups_teams USING btree (teamid);


--
-- TOC entry 3542 (class 1259 OID 31478)
-- Name: ix_31fb749a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_31fb749a ON groups_usergroups USING btree (groupid);


--
-- TOC entry 4098 (class 1259 OID 32027)
-- Name: ix_323df109; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_323df109 ON journalarticle USING btree (companyid, status);


--
-- TOC entry 4423 (class 1259 OID 32599)
-- Name: ix_3251af16; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3251af16 ON shoppingcoupon USING btree (groupid);


--
-- TOC entry 3565 (class 1259 OID 31499)
-- Name: ix_326525d6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_326525d6 ON layoutfriendlyurl USING btree (uuid_, groupid);


--
-- TOC entry 3691 (class 1259 OID 31578)
-- Name: ix_326f75bd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_326f75bd ON passwordtracker USING btree (userid);


--
-- TOC entry 4379 (class 1259 OID 32487)
-- Name: ix_32d1105f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_32d1105f ON kbfolder USING btree (uuid_, companyid);


--
-- TOC entry 4033 (class 1259 OID 31937)
-- Name: ix_32e94dd6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_32e94dd6 ON kaleonode USING btree (kaleodefinitionid);


--
-- TOC entry 4257 (class 1259 OID 32267)
-- Name: ix_32f83d16; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_32f83d16 ON ddmtemplate USING btree (classpk);


--
-- TOC entry 3630 (class 1259 OID 31547)
-- Name: ix_3321f142; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3321f142 ON mbmessage USING btree (userid, classnameid, status);


--
-- TOC entry 3659 (class 1259 OID 31561)
-- Name: ix_33781904; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_33781904 ON mbthreadflag USING btree (userid, threadid);


--
-- TOC entry 3256 (class 1259 OID 30437)
-- Name: ix_339e078m; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_339e078m ON quartz_fired_triggers USING btree (sched_name, instance_name, requests_recovery);


--
-- TOC entry 3617 (class 1259 OID 31528)
-- Name: ix_33a4de38; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_33a4de38 ON mbdiscussion USING btree (classnameid, classpk);


--
-- TOC entry 4258 (class 1259 OID 32271)
-- Name: ix_33bef579; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_33bef579 ON ddmtemplate USING btree (language);


--
-- TOC entry 4099 (class 1259 OID 32048)
-- Name: ix_3463d95b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3463d95b ON journalarticle USING btree (uuid_, groupid);


--
-- TOC entry 3937 (class 1259 OID 31738)
-- Name: ix_3499b657; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3499b657 ON users_groups USING btree (companyid);


--
-- TOC entry 3801 (class 1259 OID 31647)
-- Name: ix_3504b8bc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3504b8bc ON socialactivity USING btree (userid);


--
-- TOC entry 3729 (class 1259 OID 31599)
-- Name: ix_351e86e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_351e86e8 ON recentlayoutbranch USING btree (layoutbranchid);


--
-- TOC entry 4100 (class 1259 OID 32034)
-- Name: ix_353bd560; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_353bd560 ON journalarticle USING btree (groupid, classnameid, ddmstructurekey);


--
-- TOC entry 3757 (class 1259 OID 31616)
-- Name: ix_354aa664; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_354aa664 ON repositoryentry USING btree (uuid_, groupid);


--
-- TOC entry 3665 (class 1259 OID 31565)
-- Name: ix_35aa8fa6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_35aa8fa6 ON membershiprequest USING btree (groupid, userid, statusid);


--
-- TOC entry 3396 (class 1259 OID 31378)
-- Name: ix_35e3e7c6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_35e3e7c6 ON company USING btree (system);


--
-- TOC entry 4020 (class 1259 OID 31927)
-- Name: ix_360d34d9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_360d34d9 ON kaleoinstancetoken USING btree (companyid, parentkaleoinstancetokenid, completiondate);


--
-- TOC entry 3844 (class 1259 OID 31674)
-- Name: ix_36a90ca7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_36a90ca7 ON socialrequest USING btree (userid, classnameid, classpk, type_, receiveruserid);


--
-- TOC entry 3816 (class 1259 OID 31654)
-- Name: ix_374b35ae; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_374b35ae ON socialactivitycounter USING btree (groupid, classnameid, classpk, name, ownertype, startperiod);


--
-- TOC entry 3499 (class 1259 OID 31446)
-- Name: ix_37562284; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_37562284 ON expandotable USING btree (companyid, classnameid, name);


--
-- TOC entry 3631 (class 1259 OID 31542)
-- Name: ix_377858d2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_377858d2 ON mbmessage USING btree (groupid, userid, status);


--
-- TOC entry 4346 (class 1259 OID 32459)
-- Name: ix_379fd6bc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_379fd6bc ON kbarticle USING btree (groupid, kbfolderid, urltitle, status);


--
-- TOC entry 3832 (class 1259 OID 31663)
-- Name: ix_384788cd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_384788cd ON socialactivitysetting USING btree (groupid, activitytype);


--
-- TOC entry 4318 (class 1259 OID 32394)
-- Name: ix_384ab6f7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_384ab6f7 ON ddlrecord USING btree (uuid_, companyid);


--
-- TOC entry 3632 (class 1259 OID 31540)
-- Name: ix_385e123e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_385e123e ON mbmessage USING btree (groupid, categoryid, threadid, status);


--
-- TOC entry 4037 (class 1259 OID 31938)
-- Name: ix_38829497; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38829497 ON kaleonotification USING btree (companyid);


--
-- TOC entry 4057 (class 1259 OID 31952)
-- Name: ix_38a47b17; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38a47b17 ON kaleotaskassignmentinstance USING btree (groupid, assigneeclasspk);


--
-- TOC entry 3329 (class 1259 OID 31335)
-- Name: ix_38a65b55; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38a65b55 ON assetentries_assetcategories USING btree (companyid);


--
-- TOC entry 4395 (class 1259 OID 32514)
-- Name: ix_38c38a09; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38c38a09 ON syncdlobject USING btree (repositoryid, event);


--
-- TOC entry 3397 (class 1259 OID 31376)
-- Name: ix_38efe3fd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38efe3fd ON company USING btree (logoid);


--
-- TOC entry 3449 (class 1259 OID 31412)
-- Name: ix_38f0315; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38f0315 ON dlfilerank USING btree (companyid, userid, fileentryid);


--
-- TOC entry 3511 (class 1259 OID 31454)
-- Name: ix_38fa468d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_38fa468d ON exportimportconfiguration USING btree (groupid, status);


--
-- TOC entry 4138 (class 1259 OID 32061)
-- Name: ix_39031f51; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_39031f51 ON journalfeed USING btree (uuid_, groupid);


--
-- TOC entry 3551 (class 1259 OID 31489)
-- Name: ix_39a18ecc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_39a18ecc ON layout USING btree (sourceprototypelayoutuuid);


--
-- TOC entry 3865 (class 1259 OID 31687)
-- Name: ix_39f69e79; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_39f69e79 ON team USING btree (uuid_, groupid);


--
-- TOC entry 3649 (class 1259 OID 31559)
-- Name: ix_3a200b7b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3a200b7b ON mbthread USING btree (uuid_, groupid);


--
-- TOC entry 4211 (class 1259 OID 32240)
-- Name: ix_3a9c0626; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3a9c0626 ON ddmcontent USING btree (uuid_, companyid);


--
-- TOC entry 4466 (class 1259 OID 32677)
-- Name: ix_3ae311a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3ae311a ON calendar USING btree (uuid_, groupid);


--
-- TOC entry 3543 (class 1259 OID 31479)
-- Name: ix_3b69160f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3b69160f ON groups_usergroups USING btree (usergroupid);


--
-- TOC entry 4058 (class 1259 OID 31950)
-- Name: ix_3bd436fd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3bd436fd ON kaleotaskassignmentinstance USING btree (assigneeclassname, assigneeclasspk);


--
-- TOC entry 4396 (class 1259 OID 32515)
-- Name: ix_3be7bb8d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3be7bb8d ON syncdlobject USING btree (repositoryid, parentfolderid, type_);


--
-- TOC entry 4101 (class 1259 OID 32039)
-- Name: ix_3c028c1e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3c028c1e ON journalarticle USING btree (groupid, layoutuuid);


--
-- TOC entry 4516 (class 1259 OID 32771)
-- Name: ix_3c79316e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3c79316e ON opensocial_gadget USING btree (uuid_, companyid);


--
-- TOC entry 4335 (class 1259 OID 32419)
-- Name: ix_3cbe4c36; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3cbe4c36 ON sn_meetupsregistration USING btree (userid, meetupsentryid);


--
-- TOC entry 3472 (class 1259 OID 31437)
-- Name: ix_3cc1ded2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3cc1ded2 ON dlfolder USING btree (uuid_, groupid);


--
-- TOC entry 4161 (class 1259 OID 32108)
-- Name: ix_3d4af476; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3d4af476 ON wikipage USING btree (nodeid, title, version);


--
-- TOC entry 3483 (class 1259 OID 31438)
-- Name: ix_3d8e1607; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3d8e1607 ON dlsyncevent USING btree (modifiedtime);


--
-- TOC entry 3926 (class 1259 OID 31713)
-- Name: ix_3dbb361a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3dbb361a ON usernotificationevent USING btree (userid, archived);


--
-- TOC entry 4102 (class 1259 OID 32045)
-- Name: ix_3e2765fc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3e2765fc ON journalarticle USING btree (resourceprimkey, status);


--
-- TOC entry 4103 (class 1259 OID 32043)
-- Name: ix_3f1ea19e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3f1ea19e ON journalarticle USING btree (layoutuuid);


--
-- TOC entry 3837 (class 1259 OID 31669)
-- Name: ix_3f9c2fa8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3f9c2fa8 ON socialrelation USING btree (userid2, type_);


--
-- TOC entry 4380 (class 1259 OID 32485)
-- Name: ix_3fa4415c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3fa4415c ON kbfolder USING btree (groupid, parentkbfolderid, name);


--
-- TOC entry 3683 (class 1259 OID 31574)
-- Name: ix_3fbfa9f4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_3fbfa9f4 ON passwordpolicy USING btree (companyid, name);


--
-- TOC entry 4047 (class 1259 OID 31945)
-- Name: ix_3ffa633; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_3ffa633 ON kaleotask USING btree (kaleodefinitionid);


--
-- TOC entry 4482 (class 1259 OID 32688)
-- Name: ix_4012e97f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4012e97f ON calendarnotificationtemplate USING btree (uuid_, groupid);


--
-- TOC entry 3887 (class 1259 OID 31737)
-- Name: ix_405cc0e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_405cc0e ON user_ USING btree (uuid_, companyid);


--
-- TOC entry 4488 (class 1259 OID 32692)
-- Name: ix_40678371; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_40678371 ON calendarresource USING btree (groupid, active_);


--
-- TOC entry 4009 (class 1259 OID 31920)
-- Name: ix_408542ba; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_408542ba ON kaleodefinition USING btree (companyid, active_);


--
-- TOC entry 4384 (class 1259 OID 32491)
-- Name: ix_40aa25ed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_40aa25ed ON kbtemplate USING btree (uuid_, groupid);


--
-- TOC entry 4162 (class 1259 OID 32101)
-- Name: ix_40f94f68; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_40f94f68 ON wikipage USING btree (nodeid, head, redirecttitle, status);


--
-- TOC entry 3986 (class 1259 OID 31761)
-- Name: ix_415a7007; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_415a7007 ON workflowinstancelink USING btree (groupid, companyid, classnameid, classpk);


--
-- TOC entry 4295 (class 1259 OID 32346)
-- Name: ix_416ad7d5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_416ad7d5 ON bookmarksentry USING btree (groupid, status);


--
-- TOC entry 3670 (class 1259 OID 31571)
-- Name: ix_418e4522; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_418e4522 ON organization_ USING btree (companyid, parentorganizationid);


--
-- TOC entry 3922 (class 1259 OID 31708)
-- Name: ix_41a32e0d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_41a32e0d ON useridmapper USING btree (type_, externaluserid);


--
-- TOC entry 4079 (class 1259 OID 31964)
-- Name: ix_41d6c6d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_41d6c6d ON kaleotransition USING btree (companyid);


--
-- TOC entry 3650 (class 1259 OID 31552)
-- Name: ix_41f6dc8a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_41f6dc8a ON mbthread USING btree (categoryid, priority);


--
-- TOC entry 3633 (class 1259 OID 31538)
-- Name: ix_4257db85; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4257db85 ON mbmessage USING btree (groupid, categoryid, status);


--
-- TOC entry 3970 (class 1259 OID 31754)
-- Name: ix_431a3960; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_431a3960 ON virtualhost USING btree (hostname);


--
-- TOC entry 4163 (class 1259 OID 32102)
-- Name: ix_432f0ab0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_432f0ab0 ON wikipage USING btree (nodeid, head, status);


--
-- TOC entry 4234 (class 1259 OID 32254)
-- Name: ix_43395316; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_43395316 ON ddmstructure USING btree (groupid, parentstructureid);


--
-- TOC entry 4409 (class 1259 OID 32530)
-- Name: ix_434ee852; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_434ee852 ON pm_userthread USING btree (userid, deleted);


--
-- TOC entry 4104 (class 1259 OID 32042)
-- Name: ix_43a0f80f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_43a0f80f ON journalarticle USING btree (groupid, userid, classnameid);


--
-- TOC entry 3578 (class 1259 OID 31502)
-- Name: ix_43e8286a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_43e8286a ON layoutrevision USING btree (head, plid);


--
-- TOC entry 3826 (class 1259 OID 31659)
-- Name: ix_4460fa14; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4460fa14 ON socialactivityset USING btree (classnameid, classpk, type_);


--
-- TOC entry 4489 (class 1259 OID 32691)
-- Name: ix_4470a59d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4470a59d ON calendarresource USING btree (companyid, code_, active_);


--
-- TOC entry 4105 (class 1259 OID 32044)
-- Name: ix_451d63ec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_451d63ec ON journalarticle USING btree (resourceprimkey, indexable, status);


--
-- TOC entry 3309 (class 1259 OID 31321)
-- Name: ix_4539a99c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4539a99c ON announcementsflag USING btree (userid, entryid, value);


--
-- TOC entry 3740 (class 1259 OID 31606)
-- Name: ix_4654d204; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4654d204 ON recentlayoutsetbranch USING btree (userid, layoutsetid);


--
-- TOC entry 4197 (class 1259 OID 32156)
-- Name: ix_46665cc4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_46665cc4 ON mdrrulegroup USING btree (uuid_, groupid);


--
-- TOC entry 4410 (class 1259 OID 32531)
-- Name: ix_466f2985; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_466f2985 ON pm_userthread USING btree (userid, mbthreadid);


--
-- TOC entry 3963 (class 1259 OID 31721)
-- Name: ix_46b0ae8e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_46b0ae8e ON usertracker USING btree (sessionid);


--
-- TOC entry 4164 (class 1259 OID 32103)
-- Name: ix_46eef3c8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_46eef3c8 ON wikipage USING btree (nodeid, parenttitle);


--
-- TOC entry 4474 (class 1259 OID 32679)
-- Name: ix_470170b4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_470170b4 ON calendarbooking USING btree (calendarid, status);


--
-- TOC entry 4025 (class 1259 OID 31934)
-- Name: ix_470b9ff8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_470b9ff8 ON kaleolog USING btree (kaleoinstancetokenid, type_);


--
-- TOC entry 4080 (class 1259 OID 31965)
-- Name: ix_479f3063; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_479f3063 ON kaleotransition USING btree (kaleodefinitionid);


--
-- TOC entry 3512 (class 1259 OID 31455)
-- Name: ix_47cc6234; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_47cc6234 ON exportimportconfiguration USING btree (groupid, type_, status);


--
-- TOC entry 4370 (class 1259 OID 32479)
-- Name: ix_47d3ae89; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_47d3ae89 ON kbcomment USING btree (classnameid, classpk, status);


--
-- TOC entry 3586 (class 1259 OID 31509)
-- Name: ix_48550691; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_48550691 ON layoutset USING btree (groupid, privatelayout);


--
-- TOC entry 3651 (class 1259 OID 31554)
-- Name: ix_485f7e98; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_485f7e98 ON mbthread USING btree (groupid, categoryid, status);


--
-- TOC entry 3603 (class 1259 OID 31519)
-- Name: ix_48814bba; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_48814bba ON mbban USING btree (userid);


--
-- TOC entry 4347 (class 1259 OID 32471)
-- Name: ix_49630fa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_49630fa ON kbarticle USING btree (resourceprimkey, groupid, status);


--
-- TOC entry 3774 (class 1259 OID 31623)
-- Name: ix_49aec6f3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_49aec6f3 ON resourcepermission USING btree (companyid, name, scope, primkeyid, roleid, viewactionid);


--
-- TOC entry 3371 (class 1259 OID 31367)
-- Name: ix_49e15a23; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_49e15a23 ON blogsentry USING btree (groupid, userid, status);


--
-- TOC entry 3495 (class 1259 OID 31444)
-- Name: ix_49eb3118; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_49eb3118 ON expandorow USING btree (classpk);


--
-- TOC entry 3634 (class 1259 OID 31546)
-- Name: ix_4a4bb4ed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4a4bb4ed ON mbmessage USING btree (userid, classnameid, classpk, status);


--
-- TOC entry 3675 (class 1259 OID 31567)
-- Name: ix_4a527dd3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4a527dd3 ON orggrouprole USING btree (groupid);


--
-- TOC entry 3579 (class 1259 OID 31505)
-- Name: ix_4a84af43; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4a84af43 ON layoutrevision USING btree (layoutsetbranchid, parentlayoutrevisionid, plid);


--
-- TOC entry 4490 (class 1259 OID 32696)
-- Name: ix_4abd2bc8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4abd2bc8 ON calendarresource USING btree (uuid_, groupid);


--
-- TOC entry 3999 (class 1259 OID 31915)
-- Name: ix_4b2545e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4b2545e8 ON kaleoaction USING btree (kaleoclassname, kaleoclasspk, executiontype);


--
-- TOC entry 3838 (class 1259 OID 31667)
-- Name: ix_4b52be89; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4b52be89 ON socialrelation USING btree (userid1, type_);


--
-- TOC entry 3457 (class 1259 OID 31418)
-- Name: ix_4b7247f6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4b7247f6 ON dlfileshortcut USING btree (tofileentryid);


--
-- TOC entry 4038 (class 1259 OID 31940)
-- Name: ix_4b968e8d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4b968e8d ON kaleonotification USING btree (kaleodefinitionid);


--
-- TOC entry 3257 (class 1259 OID 30435)
-- Name: ix_4bd722bm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4bd722bm ON quartz_fired_triggers USING btree (sched_name, trigger_group);


--
-- TOC entry 4010 (class 1259 OID 31921)
-- Name: ix_4c23f11b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4c23f11b ON kaleodefinition USING btree (companyid, name, active_);


--
-- TOC entry 3734 (class 1259 OID 31603)
-- Name: ix_4c600bd0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4c600bd0 ON recentlayoutrevision USING btree (userid, layoutsetbranchid, plid);


--
-- TOC entry 3912 (class 1259 OID 31704)
-- Name: ix_4d040680; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4d040680 ON usergrouprole USING btree (userid, groupid);


--
-- TOC entry 3952 (class 1259 OID 31748)
-- Name: ix_4d06ad51; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4d06ad51 ON users_teams USING btree (teamid);


--
-- TOC entry 4106 (class 1259 OID 32032)
-- Name: ix_4d5cd982; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4d5cd982 ON journalarticle USING btree (groupid, articleid, status);


--
-- TOC entry 4483 (class 1259 OID 32687)
-- Name: ix_4d7d97bd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4d7d97bd ON calendarnotificationtemplate USING btree (uuid_, companyid);


--
-- TOC entry 4348 (class 1259 OID 32477)
-- Name: ix_4e87d659; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4e87d659 ON kbarticle USING btree (uuid_, companyid);


--
-- TOC entry 4349 (class 1259 OID 32475)
-- Name: ix_4e89983c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4e89983c ON kbarticle USING btree (resourceprimkey, status);


--
-- TOC entry 3450 (class 1259 OID 31414)
-- Name: ix_4e96195b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4e96195b ON dlfilerank USING btree (groupid, userid, active_);


--
-- TOC entry 3796 (class 1259 OID 31639)
-- Name: ix_4f0315b8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4f0315b8 ON servicecomponent USING btree (buildnamespace, buildnumber);


--
-- TOC entry 3434 (class 1259 OID 31403)
-- Name: ix_4f40fe5e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4f40fe5e ON dlfileentrymetadata USING btree (fileentryid);


--
-- TOC entry 4192 (class 1259 OID 32151)
-- Name: ix_4f4293f1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4f4293f1 ON mdrrule USING btree (rulegroupid);


--
-- TOC entry 3604 (class 1259 OID 31520)
-- Name: ix_4f841574; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4f841574 ON mbban USING btree (uuid_, companyid);


--
-- TOC entry 3845 (class 1259 OID 31678)
-- Name: ix_4f973efe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_4f973efe ON socialrequest USING btree (uuid_, groupid);


--
-- TOC entry 4235 (class 1259 OID 32252)
-- Name: ix_4fbac092; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_4fbac092 ON ddmstructure USING btree (companyid, classnameid);


--
-- TOC entry 3258 (class 1259 OID 30438)
-- Name: ix_5005e3af; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5005e3af ON quartz_fired_triggers USING btree (sched_name, job_name, job_group);


--
-- TOC entry 3358 (class 1259 OID 31353)
-- Name: ix_50702693; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_50702693 ON assettagstats USING btree (classnameid);


--
-- TOC entry 3382 (class 1259 OID 31373)
-- Name: ix_507ba031; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_507ba031 ON blogsstatsuser USING btree (userid, lastpostdate);


--
-- TOC entry 4212 (class 1259 OID 32239)
-- Name: ix_50bf1038; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_50bf1038 ON ddmcontent USING btree (groupid);


--
-- TOC entry 4000 (class 1259 OID 31914)
-- Name: ix_50e9112c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_50e9112c ON kaleoaction USING btree (companyid);


--
-- TOC entry 3652 (class 1259 OID 31553)
-- Name: ix_50f1904a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_50f1904a ON mbthread USING btree (groupid, categoryid, lastpostdate);


--
-- TOC entry 3473 (class 1259 OID 31433)
-- Name: ix_51556082; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_51556082 ON dlfolder USING btree (parentfolderid, name);


--
-- TOC entry 3325 (class 1259 OID 31333)
-- Name: ix_52340033; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_52340033 ON assetcategoryproperty USING btree (companyid, key_);


--
-- TOC entry 3421 (class 1259 OID 31394)
-- Name: ix_5391712; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5391712 ON dlfileentry USING btree (groupid, folderid, name);


--
-- TOC entry 4415 (class 1259 OID 32595)
-- Name: ix_54101cc8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_54101cc8 ON shoppingcart USING btree (userid);


--
-- TOC entry 3422 (class 1259 OID 31388)
-- Name: ix_5444c427; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5444c427 ON dlfileentry USING btree (companyid, fileentrytypeid);


--
-- TOC entry 4165 (class 1259 OID 32105)
-- Name: ix_546f2d5c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_546f2d5c ON wikipage USING btree (nodeid, status);


--
-- TOC entry 4304 (class 1259 OID 32355)
-- Name: ix_54f0ed65; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_54f0ed65 ON bookmarksfolder USING btree (uuid_, companyid);


--
-- TOC entry 4143 (class 1259 OID 32066)
-- Name: ix_54f89e1f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_54f89e1f ON journalfolder USING btree (uuid_, companyid);


--
-- TOC entry 3573 (class 1259 OID 31500)
-- Name: ix_557a639f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_557a639f ON layoutprototype USING btree (companyid, active_);


--
-- TOC entry 3538 (class 1259 OID 31474)
-- Name: ix_557d8550; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_557d8550 ON groups_roles USING btree (companyid);


--
-- TOC entry 4350 (class 1259 OID 32464)
-- Name: ix_55a38cf2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_55a38cf2 ON kbarticle USING btree (groupid, parentresourceprimkey, status);


--
-- TOC entry 4491 (class 1259 OID 32693)
-- Name: ix_55c2f8aa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_55c2f8aa ON calendarresource USING btree (groupid, code_);


--
-- TOC entry 3359 (class 1259 OID 31354)
-- Name: ix_56682cc4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_56682cc4 ON assettagstats USING btree (tagid, classnameid);


--
-- TOC entry 4492 (class 1259 OID 32695)
-- Name: ix_56a06bc6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_56a06bc6 ON calendarresource USING btree (uuid_, companyid);


--
-- TOC entry 4325 (class 1259 OID 32396)
-- Name: ix_56dab121; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_56dab121 ON ddlrecordset USING btree (groupid, recordsetkey);


--
-- TOC entry 4351 (class 1259 OID 32454)
-- Name: ix_571c019e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_571c019e ON kbarticle USING btree (companyid, latest);


--
-- TOC entry 4053 (class 1259 OID 31949)
-- Name: ix_575c03a6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_575c03a6 ON kaleotaskassignment USING btree (kaleodefinitionid);


--
-- TOC entry 4088 (class 1259 OID 31979)
-- Name: ix_579c63b0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_579c63b0 ON backgroundtask USING btree (groupid, name, taskexecutorclassname, completed);


--
-- TOC entry 3635 (class 1259 OID 31548)
-- Name: ix_57ca9fec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_57ca9fec ON mbmessage USING btree (uuid_, companyid);


--
-- TOC entry 3484 (class 1259 OID 31439)
-- Name: ix_57d82b06; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_57d82b06 ON dlsyncevent USING btree (typepk);


--
-- TOC entry 4397 (class 1259 OID 32516)
-- Name: ix_57f62914; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_57f62914 ON syncdlobject USING btree (repositoryid, type_);


--
-- TOC entry 4284 (class 1259 OID 32323)
-- Name: ix_5848f52d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5848f52d ON marketplace_module USING btree (appid, bundlesymbolicname, bundleversion);


--
-- TOC entry 4198 (class 1259 OID 32154)
-- Name: ix_5849891c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5849891c ON mdrrulegroup USING btree (groupid);


--
-- TOC entry 4014 (class 1259 OID 31923)
-- Name: ix_58d85ecb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_58d85ecb ON kaleoinstance USING btree (classname, classpk);


--
-- TOC entry 3566 (class 1259 OID 31496)
-- Name: ix_59051329; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_59051329 ON layoutfriendlyurl USING btree (plid, friendlyurl);


--
-- TOC entry 4326 (class 1259 OID 32397)
-- Name: ix_5938c39f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5938c39f ON ddlrecordset USING btree (uuid_, companyid);


--
-- TOC entry 4352 (class 1259 OID 32455)
-- Name: ix_5a381890; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5a381890 ON kbarticle USING btree (companyid, main);


--
-- TOC entry 3888 (class 1259 OID 31734)
-- Name: ix_5adbe171; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5adbe171 ON user_ USING btree (contactid);


--
-- TOC entry 3440 (class 1259 OID 31407)
-- Name: ix_5b03e942; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5b03e942 ON dlfileentrytype USING btree (uuid_, companyid);


--
-- TOC entry 3839 (class 1259 OID 31670)
-- Name: ix_5b30f663; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5b30f663 ON socialrelation USING btree (uuid_, companyid);


--
-- TOC entry 3441 (class 1259 OID 31406)
-- Name: ix_5b6bef5f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5b6bef5f ON dlfileentrytype USING btree (groupid, fileentrytypekey);


--
-- TOC entry 3445 (class 1259 OID 31410)
-- Name: ix_5bb6ad6c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5bb6ad6c ON dlfileentrytypes_dlfolders USING btree (fileentrytypeid);


--
-- TOC entry 4026 (class 1259 OID 31933)
-- Name: ix_5bc6ab16; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5bc6ab16 ON kaleolog USING btree (kaleoinstanceid);


--
-- TOC entry 3295 (class 1259 OID 31314)
-- Name: ix_5bc8b0d4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5bc8b0d4 ON address USING btree (userid);


--
-- TOC entry 3517 (class 1259 OID 31462)
-- Name: ix_5bddb872; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5bddb872 ON group_ USING btree (companyid, friendlyurl);


--
-- TOC entry 4353 (class 1259 OID 32478)
-- Name: ix_5c941f1b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5c941f1b ON kbarticle USING btree (uuid_, groupid);


--
-- TOC entry 3927 (class 1259 OID 31712)
-- Name: ix_5ce95f03; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5ce95f03 ON usernotificationevent USING btree (userid, actionrequired, archived);


--
-- TOC entry 3866 (class 1259 OID 31686)
-- Name: ix_5d47f637; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5d47f637 ON team USING btree (uuid_, companyid);


--
-- TOC entry 4166 (class 1259 OID 32114)
-- Name: ix_5dc4bd39; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5dc4bd39 ON wikipage USING btree (uuid_, companyid);


--
-- TOC entry 3372 (class 1259 OID 31368)
-- Name: ix_5e8307bb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5e8307bb ON blogsentry USING btree (uuid_, companyid);


--
-- TOC entry 3787 (class 1259 OID 31636)
-- Name: ix_5eb4e2fb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5eb4e2fb ON role_ USING btree (subtype);


--
-- TOC entry 3942 (class 1259 OID 31741)
-- Name: ix_5fbb883c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5fbb883c ON users_orgs USING btree (companyid);


--
-- TOC entry 4354 (class 1259 OID 32469)
-- Name: ix_5fef5f4f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5fef5f4f ON kbarticle USING btree (resourceprimkey, groupid, latest);


--
-- TOC entry 3590 (class 1259 OID 31512)
-- Name: ix_5ff18552; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_5ff18552 ON layoutsetbranch USING btree (groupid, privatelayout, name);


--
-- TOC entry 4167 (class 1259 OID 32098)
-- Name: ix_5ff21ce6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_5ff21ce6 ON wikipage USING btree (groupid, nodeid, title, head);


--
-- TOC entry 4065 (class 1259 OID 31958)
-- Name: ix_608e9519; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_608e9519 ON kaleotaskinstancetoken USING btree (kaleodefinitionid);


--
-- TOC entry 3753 (class 1259 OID 31611)
-- Name: ix_60c8634c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_60c8634c ON repository USING btree (groupid, name, portletid);


--
-- TOC entry 4054 (class 1259 OID 31947)
-- Name: ix_611732b0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_611732b0 ON kaleotaskassignment USING btree (companyid);


--
-- TOC entry 3889 (class 1259 OID 31726)
-- Name: ix_615e9f7a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_615e9f7a ON user_ USING btree (companyid, emailaddress);


--
-- TOC entry 3827 (class 1259 OID 31662)
-- Name: ix_62ac101a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_62ac101a ON socialactivityset USING btree (userid, classnameid, classpk, type_);


--
-- TOC entry 3879 (class 1259 OID 31694)
-- Name: ix_630a643b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_630a643b ON trashversion USING btree (classnameid, classpk);


--
-- TOC entry 3518 (class 1259 OID 31466)
-- Name: ix_63a2aabd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_63a2aabd ON group_ USING btree (companyid, site);


--
-- TOC entry 3574 (class 1259 OID 31501)
-- Name: ix_63ed2532; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_63ed2532 ON layoutprototype USING btree (uuid_, companyid);


--
-- TOC entry 3802 (class 1259 OID 31642)
-- Name: ix_64b1bc66; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_64b1bc66 ON socialactivity USING btree (companyid);


--
-- TOC entry 4252 (class 1259 OID 32265)
-- Name: ix_64c3c42; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_64c3c42 ON ddmstructureversion USING btree (structureid, version);


--
-- TOC entry 4144 (class 1259 OID 32064)
-- Name: ix_65026705; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_65026705 ON journalfolder USING btree (groupid, parentfolderid, name);


--
-- TOC entry 4139 (class 1259 OID 32059)
-- Name: ix_65576cbc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_65576cbc ON journalfeed USING btree (groupid, feedid);


--
-- TOC entry 4236 (class 1259 OID 32255)
-- Name: ix_657899a8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_657899a8 ON ddmstructure USING btree (parentstructureid);


--
-- TOC entry 4272 (class 1259 OID 32279)
-- Name: ix_66382fc6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_66382fc6 ON ddmtemplateversion USING btree (templateid, status);


--
-- TOC entry 3401 (class 1259 OID 31382)
-- Name: ix_66d496a3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_66d496a3 ON contact_ USING btree (companyid);


--
-- TOC entry 3666 (class 1259 OID 31566)
-- Name: ix_66d70879; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_66d70879 ON membershiprequest USING btree (userid);


--
-- TOC entry 3957 (class 1259 OID 31751)
-- Name: ix_66ff2503; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_66ff2503 ON users_usergroups USING btree (usergroupid);


--
-- TOC entry 3474 (class 1259 OID 31435)
-- Name: ix_6747b2bc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6747b2bc ON dlfolder USING btree (repositoryid, parentfolderid);


--
-- TOC entry 3544 (class 1259 OID 31477)
-- Name: ix_676fc818; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_676fc818 ON groups_usergroups USING btree (companyid);


--
-- TOC entry 4059 (class 1259 OID 31954)
-- Name: ix_67a9ee93; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_67a9ee93 ON kaleotaskassignmentinstance USING btree (kaleoinstanceid);


--
-- TOC entry 4131 (class 1259 OID 32055)
-- Name: ix_6838e427; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6838e427 ON journalcontentsearch USING btree (groupid, articleid);


--
-- TOC entry 4355 (class 1259 OID 32460)
-- Name: ix_694ea2e0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_694ea2e0 ON kbarticle USING btree (groupid, latest);


--
-- TOC entry 3903 (class 1259 OID 31697)
-- Name: ix_69771487; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_69771487 ON usergroup USING btree (companyid, parentusergroupid);


--
-- TOC entry 3605 (class 1259 OID 31517)
-- Name: ix_69951a25; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_69951a25 ON mbban USING btree (banuserid);


--
-- TOC entry 4356 (class 1259 OID 32474)
-- Name: ix_69c17e43; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_69c17e43 ON kbarticle USING btree (resourceprimkey, main);


--
-- TOC entry 4319 (class 1259 OID 32392)
-- Name: ix_6a6c1c85; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6a6c1c85 ON ddlrecord USING btree (companyid);


--
-- TOC entry 4420 (class 1259 OID 32596)
-- Name: ix_6a84467d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6a84467d ON shoppingcategory USING btree (groupid, name);


--
-- TOC entry 3547 (class 1259 OID 31480)
-- Name: ix_6a925a4d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6a925a4d ON image USING btree (size_);


--
-- TOC entry 4509 (class 1259 OID 32738)
-- Name: ix_6aa6b164; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6aa6b164 ON microblogsentry USING btree (creatorclassnameid, type_);


--
-- TOC entry 3679 (class 1259 OID 31569)
-- Name: ix_6af0d434; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6af0d434 ON orglabor USING btree (organizationid);


--
-- TOC entry 4495 (class 1259 OID 32723)
-- Name: ix_6b92f85f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6b92f85f ON mail_account USING btree (userid, address);


--
-- TOC entry 3532 (class 1259 OID 31473)
-- Name: ix_6bbb7682; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6bbb7682 ON groups_orgs USING btree (organizationid);


--
-- TOC entry 4510 (class 1259 OID 32739)
-- Name: ix_6bd29b9c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6bd29b9c ON microblogsentry USING btree (type_, parentmicroblogsentryid);


--
-- TOC entry 4027 (class 1259 OID 31932)
-- Name: ix_6c64b7d4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6c64b7d4 ON kaleolog USING btree (kaleodefinitionid);


--
-- TOC entry 4523 (class 1259 OID 32773)
-- Name: ix_6c8ccc3d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6c8ccc3d ON opensocial_oauthtoken USING btree (gadgetkey, servicename);


--
-- TOC entry 3874 (class 1259 OID 31693)
-- Name: ix_6caae2e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6caae2e8 ON trashentry USING btree (groupid, createdate);


--
-- TOC entry 4371 (class 1259 OID 32483)
-- Name: ix_6cb72942; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6cb72942 ON kbcomment USING btree (uuid_, companyid);


--
-- TOC entry 4434 (class 1259 OID 32605)
-- Name: ix_6d5f9b87; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6d5f9b87 ON shoppingitemfield USING btree (itemid);


--
-- TOC entry 3989 (class 1259 OID 31771)
-- Name: ix_6d669d6f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6d669d6f ON sapentry USING btree (companyid, defaultsapentry);


--
-- TOC entry 3446 (class 1259 OID 31411)
-- Name: ix_6e00a2ec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6e00a2ec ON dlfileentrytypes_dlfolders USING btree (folderid);


--
-- TOC entry 4060 (class 1259 OID 31951)
-- Name: ix_6e3cda1b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6e3cda1b ON kaleotaskassignmentinstance USING btree (companyid);


--
-- TOC entry 4107 (class 1259 OID 32035)
-- Name: ix_6e801bf5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6e801bf5 ON journalarticle USING btree (groupid, classnameid, ddmtemplatekey);


--
-- TOC entry 4331 (class 1259 OID 32417)
-- Name: ix_6ea9eea5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6ea9eea5 ON sn_meetupsentry USING btree (userid);


--
-- TOC entry 4268 (class 1259 OID 32277)
-- Name: ix_6f3b3e9c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_6f3b3e9c ON ddmtemplatelink USING btree (classnameid, classpk);


--
-- TOC entry 3475 (class 1259 OID 31434)
-- Name: ix_6f63f140; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6f63f140 ON dlfolder USING btree (repositoryid, mountpoint);


--
-- TOC entry 3821 (class 1259 OID 31658)
-- Name: ix_6f9ede9f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_6f9ede9f ON socialactivitylimit USING btree (userid);


--
-- TOC entry 4227 (class 1259 OID 32248)
-- Name: ix_702d1ad5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_702d1ad5 ON ddmstoragelink USING btree (classpk);


--
-- TOC entry 3982 (class 1259 OID 31760)
-- Name: ix_705b40ee; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_705b40ee ON workflowdefinitionlink USING btree (groupid, companyid, classnameid, classpk, typepk);


--
-- TOC entry 3580 (class 1259 OID 31506)
-- Name: ix_70da9ecb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_70da9ecb ON layoutrevision USING btree (layoutsetbranchid, plid, status);


--
-- TOC entry 3741 (class 1259 OID 31604)
-- Name: ix_711995a5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_711995a5 ON recentlayoutsetbranch USING btree (groupid);


--
-- TOC entry 3978 (class 1259 OID 31758)
-- Name: ix_712bcd35; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_712bcd35 ON website USING btree (uuid_, companyid);


--
-- TOC entry 4108 (class 1259 OID 32047)
-- Name: ix_71520099; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_71520099 ON journalarticle USING btree (uuid_, companyid);


--
-- TOC entry 3552 (class 1259 OID 31483)
-- Name: ix_7162c27c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_7162c27c ON layout USING btree (groupid, privatelayout, layoutid);


--
-- TOC entry 3699 (class 1259 OID 31582)
-- Name: ix_7171b2e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_7171b2e8 ON pluginsetting USING btree (companyid, pluginid, plugintype);


--
-- TOC entry 3410 (class 1259 OID 31383)
-- Name: ix_717b97e1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_717b97e1 ON country USING btree (a2);


--
-- TOC entry 3411 (class 1259 OID 31384)
-- Name: ix_717b9ba2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_717b9ba2 ON country USING btree (a3);


--
-- TOC entry 3904 (class 1259 OID 31698)
-- Name: ix_72394f8e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_72394f8e ON usergroup USING btree (uuid_, companyid);


--
-- TOC entry 4381 (class 1259 OID 32486)
-- Name: ix_729a89fa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_729a89fa ON kbfolder USING btree (groupid, parentkbfolderid, urltitle);


--
-- TOC entry 3587 (class 1259 OID 31510)
-- Name: ix_72bba8b7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_72bba8b7 ON layoutset USING btree (layoutsetprototypeuuid);


--
-- TOC entry 3880 (class 1259 OID 31695)
-- Name: ix_72d58d37; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_72d58d37 ON trashversion USING btree (entryid, classnameid);


--
-- TOC entry 3342 (class 1259 OID 31341)
-- Name: ix_7306c60; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7306c60 ON assetentry USING btree (companyid);


--
-- TOC entry 3435 (class 1259 OID 31402)
-- Name: ix_7332b44f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_7332b44f ON dlfileentrymetadata USING btree (ddmstructureid, fileversionid);


--
-- TOC entry 3553 (class 1259 OID 31484)
-- Name: ix_7399b71e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7399b71e ON layout USING btree (groupid, privatelayout, parentlayoutid, priority);


--
-- TOC entry 4028 (class 1259 OID 31930)
-- Name: ix_73b5f4de; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_73b5f4de ON kaleolog USING btree (companyid);


--
-- TOC entry 3908 (class 1259 OID 31701)
-- Name: ix_73c52252; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_73c52252 ON usergroupgrouprole USING btree (usergroupid, groupid);


--
-- TOC entry 3533 (class 1259 OID 31472)
-- Name: ix_75267dca; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_75267dca ON groups_orgs USING btree (groupid);


--
-- TOC entry 3519 (class 1259 OID 31470)
-- Name: ix_754fbb1c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_754fbb1c ON group_ USING btree (uuid_, groupid);


--
-- TOC entry 4089 (class 1259 OID 31983)
-- Name: ix_75638cdf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_75638cdf ON backgroundtask USING btree (status);


--
-- TOC entry 4187 (class 1259 OID 32150)
-- Name: ix_75be36ad; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_75be36ad ON mdraction USING btree (uuid_, groupid);


--
-- TOC entry 4109 (class 1259 OID 32025)
-- Name: ix_75cca4d1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_75cca4d1 ON journalarticle USING btree (ddmtemplatekey);


--
-- TOC entry 3343 (class 1259 OID 31342)
-- Name: ix_75d42ff9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_75d42ff9 ON assetentry USING btree (expirationdate);


--
-- TOC entry 4152 (class 1259 OID 32093)
-- Name: ix_7609b2ae; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_7609b2ae ON wikinode USING btree (uuid_, groupid);


--
-- TOC entry 4329 (class 1259 OID 32399)
-- Name: ix_762adc7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_762adc7 ON ddlrecordversion USING btree (recordid, status);


--
-- TOC entry 3890 (class 1259 OID 31735)
-- Name: ix_762f63c6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_762f63c6 ON user_ USING btree (emailaddress);


--
-- TOC entry 3623 (class 1259 OID 31533)
-- Name: ix_76ce9cdd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_76ce9cdd ON mbmailinglist USING btree (groupid, categoryid);


--
-- TOC entry 4493 (class 1259 OID 32689)
-- Name: ix_76ddd0f7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_76ddd0f7 ON calendarresource USING btree (active_);


--
-- TOC entry 4484 (class 1259 OID 32686)
-- Name: ix_7727a482; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7727a482 ON calendarnotificationtemplate USING btree (calendarid, notificationtype, notificationtemplatetype);


--
-- TOC entry 3423 (class 1259 OID 31389)
-- Name: ix_772ecde7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_772ecde7 ON dlfileentry USING btree (fileentrytypeid);


--
-- TOC entry 3599 (class 1259 OID 31515)
-- Name: ix_77729718; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_77729718 ON listtype USING btree (name, type_);


--
-- TOC entry 3263 (class 1259 OID 30433)
-- Name: ix_779bca37; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_779bca37 ON quartz_job_details USING btree (sched_name, requests_recovery);


--
-- TOC entry 4048 (class 1259 OID 31946)
-- Name: ix_77b3f1a2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_77b3f1a2 ON kaleotask USING btree (kaleonodeid);


--
-- TOC entry 3856 (class 1259 OID 31679)
-- Name: ix_786d171a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_786d171a ON subscription USING btree (companyid, classnameid, classpk);


--
-- TOC entry 3402 (class 1259 OID 31381)
-- Name: ix_791914fa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_791914fa ON contact_ USING btree (classnameid, classpk);


--
-- TOC entry 4372 (class 1259 OID 32484)
-- Name: ix_791d1844; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_791d1844 ON kbcomment USING btree (uuid_, groupid);


--
-- TOC entry 3953 (class 1259 OID 31747)
-- Name: ix_799f8283; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_799f8283 ON users_teams USING btree (companyid);


--
-- TOC entry 4090 (class 1259 OID 31981)
-- Name: ix_7a9ff471; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7a9ff471 ON backgroundtask USING btree (groupid, taskexecutorclassname, completed);


--
-- TOC entry 3488 (class 1259 OID 31441)
-- Name: ix_7b43cd8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7b43cd8 ON emailaddress USING btree (userid);


--
-- TOC entry 3520 (class 1259 OID 31468)
-- Name: ix_7b590a7a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7b590a7a ON group_ USING btree (type_, active_);


--
-- TOC entry 4021 (class 1259 OID 31928)
-- Name: ix_7bdb04b4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7bdb04b4 ON kaleoinstancetoken USING btree (kaleodefinitionid);


--
-- TOC entry 4132 (class 1259 OID 32056)
-- Name: ix_7cc7d73e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7cc7d73e ON journalcontentsearch USING btree (groupid, privatelayout, articleid);


--
-- TOC entry 3782 (class 1259 OID 31630)
-- Name: ix_7d81f66f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7d81f66f ON resourcetypepermission USING btree (companyid, name, roleid);


--
-- TOC entry 4459 (class 1259 OID 32640)
-- Name: ix_7d8e92b8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7d8e92b8 ON pollsvote USING btree (uuid_, companyid);


--
-- TOC entry 4193 (class 1259 OID 32152)
-- Name: ix_7dea8df1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7dea8df1 ON mdrrule USING btree (uuid_, companyid);


--
-- TOC entry 4091 (class 1259 OID 31982)
-- Name: ix_7e757d70; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7e757d70 ON backgroundtask USING btree (groupid, taskexecutorclassname, status);


--
-- TOC entry 3618 (class 1259 OID 31530)
-- Name: ix_7e965757; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7e965757 ON mbdiscussion USING btree (uuid_, companyid);


--
-- TOC entry 3943 (class 1259 OID 31742)
-- Name: ix_7ef4ec0e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7ef4ec0e ON users_orgs USING btree (organizationid);


--
-- TOC entry 3919 (class 1259 OID 31707)
-- Name: ix_7f187e63; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7f187e63 ON usergroups_teams USING btree (usergroupid);


--
-- TOC entry 4043 (class 1259 OID 31943)
-- Name: ix_7f4fed02; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7f4fed02 ON kaleonotificationrecipient USING btree (kaleonotificationid);


--
-- TOC entry 3581 (class 1259 OID 31507)
-- Name: ix_7ffae700; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_7ffae700 ON layoutrevision USING btree (layoutsetbranchid, status);


--
-- TOC entry 4204 (class 1259 OID 32157)
-- Name: ix_808a0036; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_808a0036 ON mdrrulegroupinstance USING btree (classnameid, classpk, rulegroupid);


--
-- TOC entry 3694 (class 1259 OID 31579)
-- Name: ix_812ce07a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_812ce07a ON phone USING btree (companyid, classnameid, classpk, primary_);


--
-- TOC entry 4228 (class 1259 OID 32249)
-- Name: ix_81776090; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_81776090 ON ddmstoragelink USING btree (structureid);


--
-- TOC entry 3496 (class 1259 OID 31445)
-- Name: ix_81efbff5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_81efbff5 ON expandorow USING btree (tableid, classpk);


--
-- TOC entry 3383 (class 1259 OID 31372)
-- Name: ix_82254c25; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_82254c25 ON blogsstatsuser USING btree (groupid, userid);


--
-- TOC entry 3521 (class 1259 OID 31456)
-- Name: ix_8257e37b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8257e37b ON group_ USING btree (classnameid, classpk);


--
-- TOC entry 4373 (class 1259 OID 32481)
-- Name: ix_828ba082; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_828ba082 ON kbcomment USING btree (groupid, status);


--
-- TOC entry 4511 (class 1259 OID 32736)
-- Name: ix_837c013d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_837c013d ON microblogsentry USING btree (companyid);


--
-- TOC entry 4385 (class 1259 OID 32489)
-- Name: ix_83d9cc13; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_83d9cc13 ON kbtemplate USING btree (groupid);


--
-- TOC entry 3809 (class 1259 OID 31648)
-- Name: ix_83e16f2f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_83e16f2f ON socialactivityachievement USING btree (groupid, firstingroup);


--
-- TOC entry 3539 (class 1259 OID 31475)
-- Name: ix_84471fd2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_84471fd2 ON groups_roles USING btree (groupid);


--
-- TOC entry 3645 (class 1259 OID 31551)
-- Name: ix_847f92b5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_847f92b5 ON mbstatsuser USING btree (userid);


--
-- TOC entry 4126 (class 1259 OID 32053)
-- Name: ix_84ab0309; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_84ab0309 ON journalarticleresource USING btree (uuid_, groupid);


--
-- TOC entry 3353 (class 1259 OID 31351)
-- Name: ix_84c501e4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_84c501e4 ON assettag USING btree (uuid_, companyid);


--
-- TOC entry 4081 (class 1259 OID 31967)
-- Name: ix_85268a11; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_85268a11 ON kaleotransition USING btree (kaleonodeid, name);


--
-- TOC entry 4269 (class 1259 OID 32278)
-- Name: ix_85278170; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_85278170 ON ddmtemplatelink USING btree (templateid);


--
-- TOC entry 3315 (class 1259 OID 31323)
-- Name: ix_852ea801; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_852ea801 ON assetcategory USING btree (groupid, parentcategoryid, name, vocabularyid);


--
-- TOC entry 4386 (class 1259 OID 32490)
-- Name: ix_853770ab; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_853770ab ON kbtemplate USING btree (uuid_, companyid);


--
-- TOC entry 3458 (class 1259 OID 31416)
-- Name: ix_8571953e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8571953e ON dlfileshortcut USING btree (companyid, status);


--
-- TOC entry 4110 (class 1259 OID 32033)
-- Name: ix_85c52eec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_85c52eec ON journalarticle USING btree (groupid, articleid, version);


--
-- TOC entry 4237 (class 1259 OID 32258)
-- Name: ix_85c7ebe2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_85c7ebe2 ON ddmstructure USING btree (uuid_, groupid);


--
-- TOC entry 4279 (class 1259 OID 32320)
-- Name: ix_865b7bd5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_865b7bd5 ON marketplace_app USING btree (companyid);


--
-- TOC entry 4357 (class 1259 OID 32466)
-- Name: ix_86ba3247; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_86ba3247 ON kbarticle USING btree (parentresourceprimkey, latest);


--
-- TOC entry 4004 (class 1259 OID 31919)
-- Name: ix_86cbd4c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_86cbd4c ON kaleocondition USING btree (kaleonodeid);


--
-- TOC entry 3913 (class 1259 OID 31702)
-- Name: ix_871412df; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_871412df ON usergrouprole USING btree (groupid, roleid);


--
-- TOC entry 3316 (class 1259 OID 31324)
-- Name: ix_87603842; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_87603842 ON assetcategory USING btree (groupid, parentcategoryid, vocabularyid);


--
-- TOC entry 3264 (class 1259 OID 30432)
-- Name: ix_88328984; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_88328984 ON quartz_job_details USING btree (sched_name, job_group);


--
-- TOC entry 4273 (class 1259 OID 32280)
-- Name: ix_8854a128; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8854a128 ON ddmtemplateversion USING btree (templateid, version);


--
-- TOC entry 3914 (class 1259 OID 31703)
-- Name: ix_887a2c95; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_887a2c95 ON usergrouprole USING btree (roleid);


--
-- TOC entry 4127 (class 1259 OID 32051)
-- Name: ix_88df994a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_88df994a ON journalarticleresource USING btree (groupid, articleid);


--
-- TOC entry 3891 (class 1259 OID 31730)
-- Name: ix_89509087; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_89509087 ON user_ USING btree (companyid, openid);


--
-- TOC entry 4168 (class 1259 OID 32115)
-- Name: ix_899d3dfb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_899d3dfb ON wikipage USING btree (uuid_, groupid);


--
-- TOC entry 4296 (class 1259 OID 32350)
-- Name: ix_89bedc4f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_89bedc4f ON bookmarksentry USING btree (uuid_, companyid);


--
-- TOC entry 3280 (class 1259 OID 30445)
-- Name: ix_8aa50be1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8aa50be1 ON quartz_triggers USING btree (sched_name, job_group);


--
-- TOC entry 3606 (class 1259 OID 31518)
-- Name: ix_8abc4e3b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8abc4e3b ON mbban USING btree (groupid, banuserid);


--
-- TOC entry 4448 (class 1259 OID 32633)
-- Name: ix_8ae746ef; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8ae746ef ON pollschoice USING btree (uuid_, companyid);


--
-- TOC entry 4475 (class 1259 OID 32680)
-- Name: ix_8b23da0e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8b23da0e ON calendarbooking USING btree (calendarid, veventuid);


--
-- TOC entry 3883 (class 1259 OID 31710)
-- Name: ix_8b6e3ace; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8b6e3ace ON usernotificationdelivery USING btree (userid, portletid, classnameid, notificationtype, deliverytype);


--
-- TOC entry 4494 (class 1259 OID 32694)
-- Name: ix_8bcb4d38; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8bcb4d38 ON calendarresource USING btree (resourceblockid);


--
-- TOC entry 3749 (class 1259 OID 31610)
-- Name: ix_8bd6bca7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8bd6bca7 ON release_ USING btree (servletcontextname);


--
-- TOC entry 3534 (class 1259 OID 31471)
-- Name: ix_8bfd4548; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8bfd4548 ON groups_orgs USING btree (companyid);


--
-- TOC entry 4223 (class 1259 OID 32246)
-- Name: ix_8c878342; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8c878342 ON ddmdataproviderinstancelink USING btree (dataproviderinstanceid, structureid);


--
-- TOC entry 3660 (class 1259 OID 31560)
-- Name: ix_8cb0a24a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8cb0a24a ON mbthreadflag USING btree (threadid);


--
-- TOC entry 3554 (class 1259 OID 31485)
-- Name: ix_8ce8c0d9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8ce8c0d9 ON layout USING btree (groupid, privatelayout, sourceprototypelayoutuuid);


--
-- TOC entry 3636 (class 1259 OID 31549)
-- Name: ix_8d12316e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8d12316e ON mbmessage USING btree (uuid_, groupid);


--
-- TOC entry 3846 (class 1259 OID 31677)
-- Name: ix_8d42897c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8d42897c ON socialrequest USING btree (uuid_, companyid);


--
-- TOC entry 4398 (class 1259 OID 32512)
-- Name: ix_8d4fdc9f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8d4fdc9f ON syncdlobject USING btree (modifiedtime, repositoryid, event);


--
-- TOC entry 3775 (class 1259 OID 31622)
-- Name: ix_8d83d0ce; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8d83d0ce ON resourcepermission USING btree (companyid, name, scope, primkey, roleid);


--
-- TOC entry 3735 (class 1259 OID 31601)
-- Name: ix_8d8a2724; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8d8a2724 ON recentlayoutrevision USING btree (groupid);


--
-- TOC entry 4133 (class 1259 OID 32058)
-- Name: ix_8daf8a35; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8daf8a35 ON journalcontentsearch USING btree (portletid);


--
-- TOC entry 3713 (class 1259 OID 31593)
-- Name: ix_8e6da3a1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8e6da3a1 ON portletpreferences USING btree (portletid);


--
-- TOC entry 4520 (class 1259 OID 32772)
-- Name: ix_8e715bf8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8e715bf8 ON opensocial_oauthconsumer USING btree (gadgetkey, servicename);


--
-- TOC entry 3582 (class 1259 OID 31508)
-- Name: ix_8ec3d2bc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8ec3d2bc ON layoutrevision USING btree (plid, status);


--
-- TOC entry 4358 (class 1259 OID 32470)
-- Name: ix_8ef92e81; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8ef92e81 ON kbarticle USING btree (resourceprimkey, groupid, main);


--
-- TOC entry 4512 (class 1259 OID 32740)
-- Name: ix_8f04fc09; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8f04fc09 ON microblogsentry USING btree (userid, createdate, type_, socialrelationtype);


--
-- TOC entry 3803 (class 1259 OID 31644)
-- Name: ix_8f32dec9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8f32dec9 ON socialactivity USING btree (groupid, userid, createdate, classnameid, classpk, type_, receiveruserid);


--
-- TOC entry 3349 (class 1259 OID 31347)
-- Name: ix_8f542794; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_8f542794 ON assetlink USING btree (entryid1, entryid2, type_);


--
-- TOC entry 3810 (class 1259 OID 31649)
-- Name: ix_8f6408f0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8f6408f0 ON socialactivityachievement USING btree (groupid, name);


--
-- TOC entry 3424 (class 1259 OID 31390)
-- Name: ix_8f6c75d0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8f6c75d0 ON dlfileentry USING btree (folderid, name);


--
-- TOC entry 3928 (class 1259 OID 31718)
-- Name: ix_8fb65ec1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8fb65ec1 ON usernotificationevent USING btree (userid, type_, deliverytype, delivered);


--
-- TOC entry 3296 (class 1259 OID 31315)
-- Name: ix_8fcb620e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_8fcb620e ON address USING btree (uuid_, companyid);


--
-- TOC entry 3344 (class 1259 OID 31346)
-- Name: ix_9029e15a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9029e15a ON assetentry USING btree (visible);


--
-- TOC entry 3476 (class 1259 OID 31432)
-- Name: ix_902fd874; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_902fd874 ON dlfolder USING btree (groupid, parentfolderid, name);


--
-- TOC entry 4428 (class 1259 OID 32602)
-- Name: ix_903dc750; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_903dc750 ON shoppingitem USING btree (largeimageid);


--
-- TOC entry 3990 (class 1259 OID 31772)
-- Name: ix_90740311; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_90740311 ON sapentry USING btree (companyid, name);


--
-- TOC entry 3384 (class 1259 OID 31370)
-- Name: ix_90cda39a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_90cda39a ON blogsstatsuser USING btree (companyid, entrycount);


--
-- TOC entry 3503 (class 1259 OID 31449)
-- Name: ix_9112a7a0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9112a7a0 ON expandovalue USING btree (rowid_);


--
-- TOC entry 3646 (class 1259 OID 31550)
-- Name: ix_9168e2c9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_9168e2c9 ON mbstatsuser USING btree (groupid, userid);


--
-- TOC entry 3594 (class 1259 OID 31513)
-- Name: ix_9178fc71; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9178fc71 ON layoutsetprototype USING btree (companyid, active_);


--
-- TOC entry 3281 (class 1259 OID 30442)
-- Name: ix_91ca7cce; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_91ca7cce ON quartz_triggers USING btree (sched_name, trigger_group, next_fire_time, trigger_state, misfire_instr);


--
-- TOC entry 3350 (class 1259 OID 31349)
-- Name: ix_91f132c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_91f132c ON assetlink USING btree (entryid2, type_);


--
-- TOC entry 4134 (class 1259 OID 32054)
-- Name: ix_9207cb31; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9207cb31 ON journalcontentsearch USING btree (articleid);


--
-- TOC entry 4153 (class 1259 OID 32090)
-- Name: ix_920cd8b1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_920cd8b1 ON wikinode USING btree (groupid, name);


--
-- TOC entry 3297 (class 1259 OID 31313)
-- Name: ix_9226dbb4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9226dbb4 ON address USING btree (companyid, classnameid, classpk, primary_);


--
-- TOC entry 3298 (class 1259 OID 31312)
-- Name: ix_923bd178; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_923bd178 ON address USING btree (companyid, classnameid, classpk, mailing);


--
-- TOC entry 3817 (class 1259 OID 31655)
-- Name: ix_926cdd04; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_926cdd04 ON socialactivitycounter USING btree (groupid, classnameid, classpk, ownertype);


--
-- TOC entry 4513 (class 1259 OID 32741)
-- Name: ix_92ba6f0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_92ba6f0 ON microblogsentry USING btree (userid, type_);


--
-- TOC entry 4169 (class 1259 OID 32097)
-- Name: ix_941e429c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_941e429c ON wikipage USING btree (groupid, nodeid, status);


--
-- TOC entry 4280 (class 1259 OID 32319)
-- Name: ix_94a7ef25; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_94a7ef25 ON marketplace_app USING btree (category);


--
-- TOC entry 4170 (class 1259 OID 32110)
-- Name: ix_94d1054d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_94d1054d ON wikipage USING btree (resourceprimkey, nodeid, status);


--
-- TOC entry 3840 (class 1259 OID 31665)
-- Name: ix_95135d1c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_95135d1c ON socialrelation USING btree (companyid, type_);


--
-- TOC entry 3462 (class 1259 OID 31427)
-- Name: ix_95e9e44e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_95e9e44e ON dlfileversion USING btree (uuid_, companyid);


--
-- TOC entry 3708 (class 1259 OID 31585)
-- Name: ix_96bdd537; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_96bdd537 ON portletitem USING btree (groupid, classnameid);


--
-- TOC entry 4467 (class 1259 OID 32676)
-- Name: ix_97656498; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_97656498 ON calendar USING btree (uuid_, companyid);


--
-- TOC entry 3892 (class 1259 OID 31733)
-- Name: ix_9782ad88; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_9782ad88 ON user_ USING btree (companyid, userid);


--
-- TOC entry 4359 (class 1259 OID 32461)
-- Name: ix_97c62252; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_97c62252 ON kbarticle USING btree (groupid, main);


--
-- TOC entry 3974 (class 1259 OID 31755)
-- Name: ix_97dfa146; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_97dfa146 ON webdavprops USING btree (classnameid, classpk);


--
-- TOC entry 4468 (class 1259 OID 32674)
-- Name: ix_97fc174e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_97fc174e ON calendar USING btree (groupid, calendarresourceid, defaultcalendar);


--
-- TOC entry 3282 (class 1259 OID 30450)
-- Name: ix_99108b6e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_99108b6e ON quartz_triggers USING btree (sched_name, trigger_state);


--
-- TOC entry 4075 (class 1259 OID 31962)
-- Name: ix_9932524c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9932524c ON kaleotimerinstancetoken USING btree (kaleoinstancetokenid, completed, blocking);


--
-- TOC entry 4066 (class 1259 OID 31957)
-- Name: ix_997fe723; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_997fe723 ON kaleotaskinstancetoken USING btree (companyid);


--
-- TOC entry 3758 (class 1259 OID 31614)
-- Name: ix_9bdcf489; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_9bdcf489 ON repositoryentry USING btree (repositoryid, mappedid);


--
-- TOC entry 3828 (class 1259 OID 31660)
-- Name: ix_9be30ddf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9be30ddf ON socialactivityset USING btree (groupid, userid, classnameid, type_);


--
-- TOC entry 3463 (class 1259 OID 31425)
-- Name: ix_9be769ed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9be769ed ON dlfileversion USING btree (groupid, folderid, title, version);


--
-- TOC entry 3310 (class 1259 OID 31320)
-- Name: ix_9c7eb9f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9c7eb9f ON announcementsflag USING btree (entryid);


--
-- TOC entry 4205 (class 1259 OID 32161)
-- Name: ix_9cbc6a39; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_9cbc6a39 ON mdrrulegroupinstance USING btree (uuid_, groupid);


--
-- TOC entry 4111 (class 1259 OID 32036)
-- Name: ix_9ce6e0fa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9ce6e0fa ON journalarticle USING btree (groupid, classnameid, classpk);


--
-- TOC entry 3637 (class 1259 OID 31543)
-- Name: ix_9d7c3b23; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9d7c3b23 ON mbmessage USING btree (threadid, answer);


--
-- TOC entry 4297 (class 1259 OID 32348)
-- Name: ix_9d9cf70f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9d9cf70f ON bookmarksentry USING btree (groupid, userid, status);


--
-- TOC entry 3638 (class 1259 OID 31545)
-- Name: ix_9dc8e57; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9dc8e57 ON mbmessage USING btree (threadid, status);


--
-- TOC entry 3504 (class 1259 OID 31448)
-- Name: ix_9ddd21e5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_9ddd21e5 ON expandovalue USING btree (columnid, rowid_);


--
-- TOC entry 3721 (class 1259 OID 31596)
-- Name: ix_9f242df6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9f242df6 ON ratingsentry USING btree (uuid_, companyid);


--
-- TOC entry 4171 (class 1259 OID 32100)
-- Name: ix_9f7655da; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9f7655da ON wikipage USING btree (nodeid, head, parenttitle, status);


--
-- TOC entry 4453 (class 1259 OID 32635)
-- Name: ix_9ff342ea; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_9ff342ea ON pollsquestion USING btree (groupid);


--
-- TOC entry 3971 (class 1259 OID 31753)
-- Name: ix_a083d394; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a083d394 ON virtualhost USING btree (companyid, layoutsetid);


--
-- TOC entry 3954 (class 1259 OID 31749)
-- Name: ix_a098efbf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a098efbf ON users_teams USING btree (userid);


--
-- TOC entry 3464 (class 1259 OID 31421)
-- Name: ix_a0a283f4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a0a283f4 ON dlfileversion USING btree (companyid, status);


--
-- TOC entry 4411 (class 1259 OID 32532)
-- Name: ix_a16ef3c7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a16ef3c7 ON pm_userthread USING btree (userid, read_, deleted);


--
-- TOC entry 3893 (class 1259 OID 31736)
-- Name: ix_a18034a4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a18034a4 ON user_ USING btree (portraitid);


--
-- TOC entry 3330 (class 1259 OID 31334)
-- Name: ix_a188f560; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a188f560 ON assetentries_assetcategories USING btree (categoryid);


--
-- TOC entry 4405 (class 1259 OID 32522)
-- Name: ix_a18eddb1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a18eddb1 ON syncdevice USING btree (userid);


--
-- TOC entry 3860 (class 1259 OID 31684)
-- Name: ix_a19c89ff; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a19c89ff ON systemevent USING btree (groupid, systemeventsetkey);


--
-- TOC entry 3722 (class 1259 OID 31594)
-- Name: ix_a1a8cb8b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a1a8cb8b ON ratingsentry USING btree (classnameid, classpk, score);


--
-- TOC entry 4172 (class 1259 OID 32094)
-- Name: ix_a2001730; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a2001730 ON wikipage USING btree (format);


--
-- TOC entry 4476 (class 1259 OID 32684)
-- Name: ix_a21d9fd5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a21d9fd5 ON calendarbooking USING btree (uuid_, companyid);


--
-- TOC entry 4112 (class 1259 OID 32037)
-- Name: ix_a2534ac2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a2534ac2 ON journalarticle USING btree (groupid, classnameid, layoutuuid);


--
-- TOC entry 3746 (class 1259 OID 31609)
-- Name: ix_a2635f5c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a2635f5c ON region USING btree (countryid, regioncode);


--
-- TOC entry 4067 (class 1259 OID 31956)
-- Name: ix_a3271995; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a3271995 ON kaleotaskinstancetoken USING btree (classname, classpk);


--
-- TOC entry 3776 (class 1259 OID 31627)
-- Name: ix_a37a0588; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a37a0588 ON resourcepermission USING btree (roleid);


--
-- TOC entry 4082 (class 1259 OID 31966)
-- Name: ix_a38e2194; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a38e2194 ON kaleotransition USING btree (kaleonodeid, defaulttransition);


--
-- TOC entry 4399 (class 1259 OID 32513)
-- Name: ix_a3ace372; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a3ace372 ON syncdlobject USING btree (modifiedtime, repositoryid, parentfolderid);


--
-- TOC entry 3714 (class 1259 OID 31591)
-- Name: ix_a3b2a80c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a3b2a80c ON portletpreferences USING btree (ownertype, portletid);


--
-- TOC entry 3818 (class 1259 OID 31652)
-- Name: ix_a4b9a23b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a4b9a23b ON socialactivitycounter USING btree (classnameid, classpk);


--
-- TOC entry 3983 (class 1259 OID 31759)
-- Name: ix_a4db1f0f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a4db1f0f ON workflowdefinitionlink USING btree (companyid, workflowdefinitionname, workflowdefinitionversion);


--
-- TOC entry 4332 (class 1259 OID 32416)
-- Name: ix_a56e51dd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a56e51dd ON sn_meetupsentry USING btree (companyid);


--
-- TOC entry 3373 (class 1259 OID 31361)
-- Name: ix_a5f57b61; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a5f57b61 ON blogsentry USING btree (companyid, userid, status);


--
-- TOC entry 3451 (class 1259 OID 31413)
-- Name: ix_a65a1f8b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a65a1f8b ON dlfilerank USING btree (fileentryid);


--
-- TOC entry 4517 (class 1259 OID 32770)
-- Name: ix_a6a89eb1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a6a89eb1 ON opensocial_gadget USING btree (companyid, url);


--
-- TOC entry 3929 (class 1259 OID 31719)
-- Name: ix_a6bafdfe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a6bafdfe ON usernotificationevent USING btree (uuid_, companyid);


--
-- TOC entry 3726 (class 1259 OID 31597)
-- Name: ix_a6e99284; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a6e99284 ON ratingsstats USING btree (classnameid, classpk);


--
-- TOC entry 3930 (class 1259 OID 31717)
-- Name: ix_a6f83617; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a6f83617 ON usernotificationevent USING btree (userid, deliverytype, delivered, actionrequired);


--
-- TOC entry 3567 (class 1259 OID 31495)
-- Name: ix_a6fc2b28; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a6fc2b28 ON layoutfriendlyurl USING btree (groupid, privatelayout, friendlyurl, languageid);


--
-- TOC entry 3639 (class 1259 OID 31544)
-- Name: ix_a7038cd7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a7038cd7 ON mbmessage USING btree (threadid, parentmessageid);


--
-- TOC entry 3561 (class 1259 OID 31492)
-- Name: ix_a705ff94; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a705ff94 ON layoutbranch USING btree (layoutsetbranchid, plid, master);


--
-- TOC entry 3522 (class 1259 OID 31460)
-- Name: ix_a729e3a6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a729e3a6 ON group_ USING btree (companyid, classnameid, livegroupid, groupkey);


--
-- TOC entry 4281 (class 1259 OID 32322)
-- Name: ix_a7807da7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a7807da7 ON marketplace_app USING btree (uuid_, companyid);


--
-- TOC entry 4285 (class 1259 OID 32327)
-- Name: ix_a7efd80e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a7efd80e ON marketplace_module USING btree (uuid_);


--
-- TOC entry 4412 (class 1259 OID 32529)
-- Name: ix_a821854b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a821854b ON pm_userthread USING btree (mbthreadid);


--
-- TOC entry 3783 (class 1259 OID 31631)
-- Name: ix_a82690e2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a82690e2 ON resourcetypepermission USING btree (roleid);


--
-- TOC entry 3283 (class 1259 OID 30444)
-- Name: ix_a85822a0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a85822a0 ON quartz_triggers USING btree (sched_name, job_name, job_group);


--
-- TOC entry 3931 (class 1259 OID 31716)
-- Name: ix_a87a585c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a87a585c ON usernotificationevent USING btree (userid, deliverytype, archived);


--
-- TOC entry 4460 (class 1259 OID 32641)
-- Name: ix_a88c673a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a88c673a ON pollsvote USING btree (uuid_, groupid);


--
-- TOC entry 3788 (class 1259 OID 31632)
-- Name: ix_a88e424e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_a88e424e ON role_ USING btree (companyid, classnameid, classpk);


--
-- TOC entry 3847 (class 1259 OID 31672)
-- Name: ix_a90fe5a0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a90fe5a0 ON socialrequest USING btree (companyid);


--
-- TOC entry 4242 (class 1259 OID 32260)
-- Name: ix_a90ff72a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a90ff72a ON ddmstructurelayout USING btree (uuid_, companyid);


--
-- TOC entry 4389 (class 1259 OID 32510)
-- Name: ix_a9b43c55; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a9b43c55 ON syncdlfileversiondiff USING btree (expirationdate);


--
-- TOC entry 3671 (class 1259 OID 31572)
-- Name: ix_a9d85ba6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a9d85ba6 ON organization_ USING btree (uuid_, companyid);


--
-- TOC entry 4360 (class 1259 OID 32473)
-- Name: ix_a9e2c691; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_a9e2c691 ON kbarticle USING btree (resourceprimkey, latest);


--
-- TOC entry 4361 (class 1259 OID 32476)
-- Name: ix_aa304772; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_aa304772 ON kbarticle USING btree (resourceprimkey, version);


--
-- TOC entry 4044 (class 1259 OID 31942)
-- Name: ix_aa6697ea; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_aa6697ea ON kaleonotificationrecipient USING btree (kaleodefinitionid);


--
-- TOC entry 3991 (class 1259 OID 31773)
-- Name: ix_aaaeba0a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_aaaeba0a ON sapentry USING btree (uuid_, companyid);


--
-- TOC entry 3811 (class 1259 OID 31650)
-- Name: ix_aabc18e9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_aabc18e9 ON socialactivityachievement USING btree (groupid, userid, firstingroup);


--
-- TOC entry 4320 (class 1259 OID 32393)
-- Name: ix_aac564d3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_aac564d3 ON ddlrecord USING btree (recordsetid, userid);


--
-- TOC entry 3523 (class 1259 OID 31464)
-- Name: ix_aacd15f0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_aacd15f0 ON group_ USING btree (companyid, livegroupid, groupkey);


--
-- TOC entry 3676 (class 1259 OID 31568)
-- Name: ix_ab044d1c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ab044d1c ON orggrouprole USING btree (roleid);


--
-- TOC entry 3848 (class 1259 OID 31676)
-- Name: ix_ab5906a8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ab5906a8 ON socialrequest USING btree (userid, status);


--
-- TOC entry 3524 (class 1259 OID 31461)
-- Name: ix_abe2d54; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_abe2d54 ON group_ USING btree (companyid, classnameid, parentgroupid);


--
-- TOC entry 4390 (class 1259 OID 32511)
-- Name: ix_ac4c7667; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ac4c7667 ON syncdlfileversiondiff USING btree (fileentryid, sourcefileversionid, targetfileversionid);


--
-- TOC entry 3525 (class 1259 OID 31463)
-- Name: ix_acd2b296; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_acd2b296 ON group_ USING btree (companyid, groupkey);


--
-- TOC entry 4015 (class 1259 OID 31926)
-- Name: ix_acf16238; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_acf16238 ON kaleoinstance USING btree (kaleodefinitionid, completed);


--
-- TOC entry 4406 (class 1259 OID 32523)
-- Name: ix_ae38deab; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ae38deab ON syncdevice USING btree (uuid_, companyid);


--
-- TOC entry 3653 (class 1259 OID 31556)
-- Name: ix_aedd9cb5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_aedd9cb5 ON mbthread USING btree (lastpostdate, priority);


--
-- TOC entry 3766 (class 1259 OID 31618)
-- Name: ix_aeea209c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_aeea209c ON resourceblock USING btree (companyid, groupid, name, permissionshash);


--
-- TOC entry 4029 (class 1259 OID 31935)
-- Name: ix_b0cdca38; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b0cdca38 ON kaleolog USING btree (kaleotaskinstancetokenid);


--
-- TOC entry 4362 (class 1259 OID 32462)
-- Name: ix_b0fcbb47; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b0fcbb47 ON kbarticle USING btree (groupid, parentresourceprimkey, latest);


--
-- TOC entry 3822 (class 1259 OID 31656)
-- Name: ix_b15863fa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b15863fa ON socialactivitylimit USING btree (classnameid, classpk);


--
-- TOC entry 3317 (class 1259 OID 31328)
-- Name: ix_b185e980; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b185e980 ON assetcategory USING btree (parentcategoryid, vocabularyid);


--
-- TOC entry 4477 (class 1259 OID 32681)
-- Name: ix_b198ffc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b198ffc ON calendarbooking USING btree (calendarresourceid);


--
-- TOC entry 4259 (class 1259 OID 32270)
-- Name: ix_b1c33ea6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b1c33ea6 ON ddmtemplate USING btree (groupid, classpk);


--
-- TOC entry 3363 (class 1259 OID 31355)
-- Name: ix_b22d908c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b22d908c ON assetvocabulary USING btree (companyid);


--
-- TOC entry 3870 (class 1259 OID 31689)
-- Name: ix_b2468446; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b2468446 ON ticket USING btree (key_);


--
-- TOC entry 3695 (class 1259 OID 31581)
-- Name: ix_b271fa88; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b271fa88 ON phone USING btree (uuid_, companyid);


--
-- TOC entry 3390 (class 1259 OID 31375)
-- Name: ix_b27a301f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b27a301f ON classname_ USING btree (value);


--
-- TOC entry 3505 (class 1259 OID 31447)
-- Name: ix_b29fef17; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b29fef17 ON expandovalue USING btree (classnameid, classpk);


--
-- TOC entry 3336 (class 1259 OID 31339)
-- Name: ix_b2a61b55; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b2a61b55 ON assetentries_assettags USING btree (tagid);


--
-- TOC entry 3875 (class 1259 OID 31690)
-- Name: ix_b35f73d5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b35f73d5 ON trashentry USING btree (classnameid, classpk);


--
-- TOC entry 4321 (class 1259 OID 32395)
-- Name: ix_b4328f39; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b4328f39 ON ddlrecord USING btree (uuid_, groupid);


--
-- TOC entry 3723 (class 1259 OID 31595)
-- Name: ix_b47e3c11; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b47e3c11 ON ratingsentry USING btree (userid, classnameid, classpk);


--
-- TOC entry 4218 (class 1259 OID 32245)
-- Name: ix_b4e180d9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b4e180d9 ON ddmdataproviderinstance USING btree (uuid_, groupid);


--
-- TOC entry 3555 (class 1259 OID 31488)
-- Name: ix_b529bfd3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b529bfd3 ON layout USING btree (layoutprototypeuuid);


--
-- TOC entry 4154 (class 1259 OID 32089)
-- Name: ix_b54332d6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b54332d6 ON wikinode USING btree (companyid, status);


--
-- TOC entry 4363 (class 1259 OID 32472)
-- Name: ix_b5b6c674; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b5b6c674 ON kbarticle USING btree (resourceprimkey, groupid, version);


--
-- TOC entry 3619 (class 1259 OID 31529)
-- Name: ix_b5ca2dc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b5ca2dc ON mbdiscussion USING btree (threadid);


--
-- TOC entry 4445 (class 1259 OID 32610)
-- Name: ix_b5f82c7a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b5f82c7a ON shoppingorderitem USING btree (orderid);


--
-- TOC entry 4260 (class 1259 OID 32266)
-- Name: ix_b6356f93; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b6356f93 ON ddmtemplate USING btree (classnameid, classpk, type_);


--
-- TOC entry 3354 (class 1259 OID 31352)
-- Name: ix_b6acb166; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b6acb166 ON assettag USING btree (uuid_, groupid);


--
-- TOC entry 3894 (class 1259 OID 31728)
-- Name: ix_b6e3ae1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b6e3ae1 ON user_ USING btree (companyid, googleuserid);


--
-- TOC entry 4243 (class 1259 OID 32259)
-- Name: ix_b7158c0a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_b7158c0a ON ddmstructurelayout USING btree (structureversionid);


--
-- TOC entry 3506 (class 1259 OID 31452)
-- Name: ix_b71e92d5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b71e92d5 ON expandovalue USING btree (tableid, rowid_);


--
-- TOC entry 4068 (class 1259 OID 31959)
-- Name: ix_b857a115; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b857a115 ON kaleotaskinstancetoken USING btree (kaleoinstanceid, kaleotaskid);


--
-- TOC entry 3403 (class 1259 OID 31380)
-- Name: ix_b8c28c53; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b8c28c53 ON contact_ USING btree (accountid);


--
-- TOC entry 3730 (class 1259 OID 31598)
-- Name: ix_b91f79bd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b91f79bd ON recentlayoutbranch USING btree (groupid);


--
-- TOC entry 3789 (class 1259 OID 31638)
-- Name: ix_b9ff6043; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_b9ff6043 ON role_ USING btree (uuid_, companyid);


--
-- TOC entry 3301 (class 1259 OID 31316)
-- Name: ix_ba4413d5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ba4413d5 ON announcementsdelivery USING btree (userid, type_);


--
-- TOC entry 3784 (class 1259 OID 31629)
-- Name: ix_ba497163; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ba497163 ON resourcetypepermission USING btree (companyid, groupid, name, roleid);


--
-- TOC entry 4173 (class 1259 OID 32095)
-- Name: ix_ba72b89a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ba72b89a ON wikipage USING btree (groupid, nodeid, head, parenttitle, status);


--
-- TOC entry 3425 (class 1259 OID 31391)
-- Name: ix_baf654e5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_baf654e5 ON dlfileentry USING btree (groupid, fileentrytypeid);


--
-- TOC entry 3374 (class 1259 OID 31359)
-- Name: ix_bb0c2905; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bb0c2905 ON blogsentry USING btree (companyid, displaydate, status);


--
-- TOC entry 3958 (class 1259 OID 31750)
-- Name: ix_bb65040c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bb65040c ON users_usergroups USING btree (companyid);


--
-- TOC entry 3318 (class 1259 OID 31329)
-- Name: ix_bbaf6928; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bbaf6928 ON assetcategory USING btree (uuid_, companyid);


--
-- TOC entry 3556 (class 1259 OID 31482)
-- Name: ix_bc2c4231; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_bc2c4231 ON layout USING btree (groupid, privatelayout, friendlyurl);


--
-- TOC entry 3426 (class 1259 OID 31401)
-- Name: ix_bc2e7e6a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_bc2e7e6a ON dlfileentry USING btree (uuid_, groupid);


--
-- TOC entry 3259 (class 1259 OID 30439)
-- Name: ix_bc2f03b0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bc2f03b0 ON quartz_fired_triggers USING btree (sched_name, job_group);


--
-- TOC entry 4336 (class 1259 OID 32418)
-- Name: ix_bceb16e2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bceb16e2 ON sn_meetupsregistration USING btree (meetupsentryid, status);


--
-- TOC entry 3895 (class 1259 OID 31724)
-- Name: ix_bcfda257; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bcfda257 ON user_ USING btree (companyid, createdate, modifieddate);


--
-- TOC entry 3526 (class 1259 OID 31457)
-- Name: ix_bd3cb13a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bd3cb13a ON group_ USING btree (classnameid, groupid, companyid, parentgroupid);


--
-- TOC entry 3260 (class 1259 OID 30434)
-- Name: ix_be3835e5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_be3835e5 ON quartz_fired_triggers USING btree (sched_name, trigger_name, trigger_group);


--
-- TOC entry 3319 (class 1259 OID 31327)
-- Name: ix_be4df2bf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_be4df2bf ON assetcategory USING btree (parentcategoryid, name, vocabularyid);


--
-- TOC entry 3959 (class 1259 OID 31752)
-- Name: ix_be8102d6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_be8102d6 ON users_usergroups USING btree (userid);


--
-- TOC entry 4174 (class 1259 OID 32107)
-- Name: ix_bea33ab8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bea33ab8 ON wikipage USING btree (nodeid, title, status);


--
-- TOC entry 3932 (class 1259 OID 31711)
-- Name: ix_bf29100b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bf29100b ON usernotificationevent USING btree (type_);


--
-- TOC entry 4206 (class 1259 OID 32159)
-- Name: ix_bf3e642b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bf3e642b ON mdrrulegroupinstance USING btree (rulegroupid);


--
-- TOC entry 4016 (class 1259 OID 31924)
-- Name: ix_bf5839f8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bf5839f8 ON kaleoinstance USING btree (companyid, kaleodefinitionname, kaleodefinitionversion, completiondate);


--
-- TOC entry 3624 (class 1259 OID 31532)
-- Name: ix_bfeb984f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_bfeb984f ON mbmailinglist USING btree (active_);


--
-- TOC entry 3364 (class 1259 OID 31356)
-- Name: ix_c0aad74d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c0aad74d ON assetvocabulary USING btree (groupid, name);


--
-- TOC entry 3947 (class 1259 OID 31745)
-- Name: ix_c19e5f31; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c19e5f31 ON users_roles USING btree (roleid);


--
-- TOC entry 3948 (class 1259 OID 31746)
-- Name: ix_c1a01806; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c1a01806 ON users_roles USING btree (userid);


--
-- TOC entry 4449 (class 1259 OID 32634)
-- Name: ix_c222bd31; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c222bd31 ON pollschoice USING btree (uuid_, groupid);


--
-- TOC entry 4315 (class 1259 OID 32373)
-- Name: ix_c257de32; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c257de32 ON contacts_entry USING btree (userid, emailaddress);


--
-- TOC entry 4305 (class 1259 OID 32352)
-- Name: ix_c27c9dbd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c27c9dbd ON bookmarksfolder USING btree (companyid, status);


--
-- TOC entry 3731 (class 1259 OID 31600)
-- Name: ix_c27d6369; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c27d6369 ON recentlayoutbranch USING btree (userid, layoutsetbranchid, plid);


--
-- TOC entry 3667 (class 1259 OID 31564)
-- Name: ix_c28c72ec; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c28c72ec ON membershiprequest USING btree (groupid, statusid);


--
-- TOC entry 3610 (class 1259 OID 31524)
-- Name: ix_c295dbee; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c295dbee ON mbcategory USING btree (groupid, parentcategoryid, status);


--
-- TOC entry 3841 (class 1259 OID 31666)
-- Name: ix_c31a64c6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c31a64c6 ON socialrelation USING btree (type_);


--
-- TOC entry 4145 (class 1259 OID 32062)
-- Name: ix_c36b0443; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c36b0443 ON journalfolder USING btree (companyid, status);


--
-- TOC entry 3687 (class 1259 OID 31576)
-- Name: ix_c3a17327; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c3a17327 ON passwordpolicyrel USING btree (classnameid, classpk);


--
-- TOC entry 4135 (class 1259 OID 32057)
-- Name: ix_c3aa93b8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c3aa93b8 ON journalcontentsearch USING btree (groupid, privatelayout, layoutid, portletid, articleid);


--
-- TOC entry 4339 (class 1259 OID 32421)
-- Name: ix_c46194c4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c46194c4 ON sn_wallentry USING btree (userid);


--
-- TOC entry 3365 (class 1259 OID 31357)
-- Name: ix_c4e6fd10; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c4e6fd10 ON assetvocabulary USING btree (uuid_, companyid);


--
-- TOC entry 3933 (class 1259 OID 31715)
-- Name: ix_c4efbd45; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c4efbd45 ON usernotificationevent USING btree (userid, deliverytype, actionrequired, archived);


--
-- TOC entry 4261 (class 1259 OID 32274)
-- Name: ix_c4f283c8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c4f283c8 ON ddmtemplate USING btree (type_);


--
-- TOC entry 3938 (class 1259 OID 31739)
-- Name: ix_c4f9e699; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c4f9e699 ON users_groups USING btree (groupid);


--
-- TOC entry 3568 (class 1259 OID 31497)
-- Name: ix_c5762e72; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c5762e72 ON layoutfriendlyurl USING btree (plid, languageid);


--
-- TOC entry 3896 (class 1259 OID 31731)
-- Name: ix_c5806019; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c5806019 ON user_ USING btree (companyid, screenname);


--
-- TOC entry 4188 (class 1259 OID 32149)
-- Name: ix_c58a516b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c58a516b ON mdraction USING btree (uuid_, companyid);


--
-- TOC entry 4092 (class 1259 OID 31977)
-- Name: ix_c5a6c78f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c5a6c78f ON backgroundtask USING btree (companyid);


--
-- TOC entry 4286 (class 1259 OID 32324)
-- Name: ix_c6938724; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c6938724 ON marketplace_module USING btree (appid, contextname);


--
-- TOC entry 4017 (class 1259 OID 31925)
-- Name: ix_c6d7a867; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c6d7a867 ON kaleoinstance USING btree (companyid, userid);


--
-- TOC entry 3897 (class 1259 OID 31725)
-- Name: ix_c6ea4f34; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c6ea4f34 ON user_ USING btree (companyid, defaultuser, status);


--
-- TOC entry 3715 (class 1259 OID 31588)
-- Name: ix_c7057ff7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c7057ff7 ON portletpreferences USING btree (ownerid, ownertype, plid, portletid);


--
-- TOC entry 4093 (class 1259 OID 31980)
-- Name: ix_c71c3b7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c71c3b7 ON backgroundtask USING btree (groupid, status);


--
-- TOC entry 4113 (class 1259 OID 32026)
-- Name: ix_c761b675; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c761b675 ON journalarticle USING btree (classnameid, ddmtemplatekey);


--
-- TOC entry 4298 (class 1259 OID 32347)
-- Name: ix_c78b61ac; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c78b61ac ON bookmarksentry USING btree (groupid, userid, folderid, status);


--
-- TOC entry 4330 (class 1259 OID 32400)
-- Name: ix_c79e347; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c79e347 ON ddlrecordversion USING btree (recordid, version);


--
-- TOC entry 3320 (class 1259 OID 31322)
-- Name: ix_c7f39fca; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c7f39fca ON assetcategory USING btree (groupid, name, vocabularyid);


--
-- TOC entry 3557 (class 1259 OID 31481)
-- Name: ix_c7fbc998; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c7fbc998 ON layout USING btree (companyid);


--
-- TOC entry 4061 (class 1259 OID 31953)
-- Name: ix_c851011; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c851011 ON kaleotaskassignmentinstance USING btree (kaleodefinitionid);


--
-- TOC entry 4238 (class 1259 OID 32253)
-- Name: ix_c8785130; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c8785130 ON ddmstructure USING btree (groupid, classnameid, structurekey);


--
-- TOC entry 3477 (class 1259 OID 31430)
-- Name: ix_c88430ab; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c88430ab ON dlfolder USING btree (groupid, mountpoint, parentfolderid, hidden_, status);


--
-- TOC entry 4219 (class 1259 OID 32244)
-- Name: ix_c903c097; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c903c097 ON ddmdataproviderinstance USING btree (uuid_, companyid);


--
-- TOC entry 3465 (class 1259 OID 31428)
-- Name: ix_c99b2650; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c99b2650 ON dlfileversion USING btree (uuid_, groupid);


--
-- TOC entry 4244 (class 1259 OID 32261)
-- Name: ix_c9a0402c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_c9a0402c ON ddmstructurelayout USING btree (uuid_, groupid);


--
-- TOC entry 3716 (class 1259 OID 31589)
-- Name: ix_c9a3fce2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_c9a3fce2 ON portletpreferences USING btree (ownerid, ownertype, portletid);


--
-- TOC entry 4175 (class 1259 OID 32099)
-- Name: ix_caa451d6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_caa451d6 ON wikipage USING btree (groupid, userid, nodeid, status);


--
-- TOC entry 3909 (class 1259 OID 31699)
-- Name: ix_cab0ccc8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cab0ccc8 ON usergroupgrouprole USING btree (groupid, roleid);


--
-- TOC entry 4262 (class 1259 OID 32273)
-- Name: ix_cae41a28; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cae41a28 ON ddmtemplate USING btree (templatekey);


--
-- TOC entry 4140 (class 1259 OID 32060)
-- Name: ix_cb37a10f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cb37a10f ON journalfeed USING btree (uuid_, companyid);


--
-- TOC entry 4224 (class 1259 OID 32247)
-- Name: ix_cb823541; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cb823541 ON ddmdataproviderinstancelink USING btree (structureid);


--
-- TOC entry 3790 (class 1259 OID 31637)
-- Name: ix_cbe204; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cbe204 ON role_ USING btree (type_, subtype);


--
-- TOC entry 3640 (class 1259 OID 31539)
-- Name: ix_cbfdbf0a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cbfdbf0a ON mbmessage USING btree (groupid, categoryid, threadid, answer);


--
-- TOC entry 4199 (class 1259 OID 32155)
-- Name: ix_cc14dc2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cc14dc2 ON mdrrulegroup USING btree (uuid_, companyid);


--
-- TOC entry 4128 (class 1259 OID 32052)
-- Name: ix_cc7576c7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cc7576c7 ON journalarticleresource USING btree (uuid_, companyid);


--
-- TOC entry 3849 (class 1259 OID 31675)
-- Name: ix_cc86a444; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cc86a444 ON socialrequest USING btree (userid, classnameid, classpk, type_, status);


--
-- TOC entry 3654 (class 1259 OID 31557)
-- Name: ix_cc993ecb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cc993ecb ON mbthread USING btree (rootmessageid);


--
-- TOC entry 3591 (class 1259 OID 31511)
-- Name: ix_ccf0da29; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ccf0da29 ON layoutsetbranch USING btree (groupid, privatelayout, master);


--
-- TOC entry 3688 (class 1259 OID 31577)
-- Name: ix_cd25266e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cd25266e ON passwordpolicyrel USING btree (passwordpolicyid);


--
-- TOC entry 3284 (class 1259 OID 30451)
-- Name: ix_cd7132d0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cd7132d0 ON quartz_triggers USING btree (sched_name, calendar_name);


--
-- TOC entry 4524 (class 1259 OID 32774)
-- Name: ix_cdd35402; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cdd35402 ON opensocial_oauthtoken USING btree (userid, gadgetkey, servicename, moduleid, tokenname);


--
-- TOC entry 3478 (class 1259 OID 31431)
-- Name: ix_ce360bf6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ce360bf6 ON dlfolder USING btree (groupid, parentfolderid, hidden_, status);


--
-- TOC entry 4364 (class 1259 OID 32458)
-- Name: ix_cfb8c81f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_cfb8c81f ON kbarticle USING btree (groupid, kbfolderid, status);


--
-- TOC entry 3527 (class 1259 OID 31459)
-- Name: ix_d0d5e397; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d0d5e397 ON group_ USING btree (companyid, classnameid, classpk);


--
-- TOC entry 3804 (class 1259 OID 31641)
-- Name: ix_d0e9029e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d0e9029e ON socialactivity USING btree (classnameid, classpk, type_);


--
-- TOC entry 4306 (class 1259 OID 32353)
-- Name: ix_d16018a6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d16018a6 ON bookmarksfolder USING btree (groupid, parentfolderid, status);


--
-- TOC entry 3611 (class 1259 OID 31522)
-- Name: ix_d1642361; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d1642361 ON mbcategory USING btree (categoryid, groupid, parentcategoryid, status);


--
-- TOC entry 3923 (class 1259 OID 31709)
-- Name: ix_d1c44a6e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d1c44a6e ON useridmapper USING btree (userid, type_);


--
-- TOC entry 3702 (class 1259 OID 31583)
-- Name: ix_d1f795f1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d1f795f1 ON portalpreferences USING btree (ownerid, ownertype);


--
-- TOC entry 3427 (class 1259 OID 31396)
-- Name: ix_d20c434d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d20c434d ON dlfileentry USING btree (groupid, userid, folderid);


--
-- TOC entry 4429 (class 1259 OID 32603)
-- Name: ix_d217ab30; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d217ab30 ON shoppingitem USING btree (mediumimageid);


--
-- TOC entry 3285 (class 1259 OID 30443)
-- Name: ix_d219afde; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d219afde ON quartz_triggers USING btree (sched_name, trigger_group, trigger_state);


--
-- TOC entry 3507 (class 1259 OID 31451)
-- Name: ix_d27b03e7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d27b03e7 ON expandovalue USING btree (tableid, columnid, classpk);


--
-- TOC entry 4114 (class 1259 OID 32041)
-- Name: ix_d2d249e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d2d249e8 ON journalarticle USING btree (groupid, urltitle, status);


--
-- TOC entry 3717 (class 1259 OID 31592)
-- Name: ix_d340db76; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d340db76 ON portletpreferences USING btree (plid, portletid);


--
-- TOC entry 3850 (class 1259 OID 31671)
-- Name: ix_d3425487; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d3425487 ON socialrequest USING btree (classnameid, classpk, type_, receiveruserid, status);


--
-- TOC entry 4310 (class 1259 OID 32362)
-- Name: ix_d34593c1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d34593c1 ON so_memberrequest USING btree (groupid, receiveruserid, status);


--
-- TOC entry 3759 (class 1259 OID 31615)
-- Name: ix_d3b9af62; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d3b9af62 ON repositoryentry USING btree (uuid_, companyid);


--
-- TOC entry 4123 (class 1259 OID 32050)
-- Name: ix_d4121315; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d4121315 ON journalarticleimage USING btree (tempimage);


--
-- TOC entry 3812 (class 1259 OID 31651)
-- Name: ix_d4390caa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d4390caa ON socialactivityachievement USING btree (groupid, userid, name);


--
-- TOC entry 3466 (class 1259 OID 31422)
-- Name: ix_d47bb14d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d47bb14d ON dlfileversion USING btree (fileentryid, status);


--
-- TOC entry 3305 (class 1259 OID 31318)
-- Name: ix_d49c2e66; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d49c2e66 ON announcementsentry USING btree (userid);


--
-- TOC entry 3528 (class 1259 OID 31465)
-- Name: ix_d4bff38b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d4bff38b ON group_ USING btree (companyid, parentgroupid, site, inheritcontent);


--
-- TOC entry 4062 (class 1259 OID 31955)
-- Name: ix_d4c2235b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d4c2235b ON kaleotaskassignmentinstance USING btree (kaleotaskinstancetokenid);


--
-- TOC entry 4263 (class 1259 OID 32275)
-- Name: ix_d4c2c221; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d4c2c221 ON ddmtemplate USING btree (uuid_, companyid);


--
-- TOC entry 4461 (class 1259 OID 32638)
-- Name: ix_d5df7b54; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d5df7b54 ON pollsvote USING btree (choiceid);


--
-- TOC entry 3718 (class 1259 OID 31590)
-- Name: ix_d5eda3a1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d5eda3a1 ON portletpreferences USING btree (ownertype, plid, portletid);


--
-- TOC entry 3777 (class 1259 OID 31626)
-- Name: ix_d5f1e2a2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d5f1e2a2 ON resourcepermission USING btree (name);


--
-- TOC entry 3321 (class 1259 OID 31326)
-- Name: ix_d61abe08; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d61abe08 ON assetcategory USING btree (name, vocabularyid);


--
-- TOC entry 3355 (class 1259 OID 31350)
-- Name: ix_d63322f9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d63322f9 ON assettag USING btree (groupid, name);


--
-- TOC entry 3770 (class 1259 OID 31620)
-- Name: ix_d63d20bb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d63d20bb ON resourceblockpermission USING btree (resourceblockid, roleid);


--
-- TOC entry 3709 (class 1259 OID 31586)
-- Name: ix_d699243f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d699243f ON portletitem USING btree (groupid, name, portletid, classnameid);


--
-- TOC entry 4450 (class 1259 OID 32632)
-- Name: ix_d76dd2cf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d76dd2cf ON pollschoice USING btree (questionid, name);


--
-- TOC entry 4441 (class 1259 OID 32608)
-- Name: ix_d7d6e87a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_d7d6e87a ON shoppingorder USING btree (number_);


--
-- TOC entry 4115 (class 1259 OID 32030)
-- Name: ix_d8eb0d84; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d8eb0d84 ON journalarticle USING btree (groupid, ddmstructurekey);


--
-- TOC entry 4365 (class 1259 OID 32463)
-- Name: ix_d91d2879; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d91d2879 ON kbarticle USING btree (groupid, parentresourceprimkey, main);


--
-- TOC entry 3851 (class 1259 OID 31673)
-- Name: ix_d9380cb7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d9380cb7 ON socialrequest USING btree (receiveruserid, status);


--
-- TOC entry 3428 (class 1259 OID 31397)
-- Name: ix_d9492cf6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d9492cf6 ON dlfileentry USING btree (mimetype);


--
-- TOC entry 3833 (class 1259 OID 31664)
-- Name: ix_d984aaba; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d984aaba ON socialactivitysetting USING btree (groupid, classnameid, activitytype, name);


--
-- TOC entry 3595 (class 1259 OID 31514)
-- Name: ix_d9ffca84; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_d9ffca84 ON layoutsetprototype USING btree (uuid_, companyid);


--
-- TOC entry 3375 (class 1259 OID 31366)
-- Name: ix_da04f689; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_da04f689 ON blogsentry USING btree (groupid, userid, displaydate, status);


--
-- TOC entry 3736 (class 1259 OID 31602)
-- Name: ix_da0788da; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_da0788da ON recentlayoutrevision USING btree (layoutrevisionid);


--
-- TOC entry 3479 (class 1259 OID 31436)
-- Name: ix_da448450; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_da448450 ON dlfolder USING btree (uuid_, companyid);


--
-- TOC entry 3612 (class 1259 OID 31525)
-- Name: ix_da84a9f7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_da84a9f7 ON mbcategory USING btree (groupid, status);


--
-- TOC entry 4220 (class 1259 OID 32242)
-- Name: ix_db54a6e5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_db54a6e5 ON ddmdataproviderinstance USING btree (companyid);


--
-- TOC entry 3376 (class 1259 OID 31365)
-- Name: ix_db780a20; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_db780a20 ON blogsentry USING btree (groupid, urltitle);


--
-- TOC entry 4229 (class 1259 OID 32250)
-- Name: ix_db81eb42; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_db81eb42 ON ddmstoragelink USING btree (uuid_, companyid);


--
-- TOC entry 4076 (class 1259 OID 31961)
-- Name: ix_db96c55b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_db96c55b ON kaleotimerinstancetoken USING btree (kaleoinstanceid);


--
-- TOC entry 3326 (class 1259 OID 31332)
-- Name: ix_dbd111aa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_dbd111aa ON assetcategoryproperty USING btree (categoryid, key_);


--
-- TOC entry 4307 (class 1259 OID 32356)
-- Name: ix_dc2f8927; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_dc2f8927 ON bookmarksfolder USING btree (uuid_, groupid);


--
-- TOC entry 4424 (class 1259 OID 32598)
-- Name: ix_dc60cfae; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_dc60cfae ON shoppingcoupon USING btree (code_);


--
-- TOC entry 4005 (class 1259 OID 31918)
-- Name: ix_dc978a5d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_dc978a5d ON kaleocondition USING btree (kaleodefinitionid);


--
-- TOC entry 3661 (class 1259 OID 31562)
-- Name: ix_dce308c5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_dce308c5 ON mbthreadflag USING btree (uuid_, companyid);


--
-- TOC entry 4287 (class 1259 OID 32325)
-- Name: ix_dd03d499; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_dd03d499 ON marketplace_module USING btree (bundlesymbolicname);


--
-- TOC entry 3529 (class 1259 OID 31458)
-- Name: ix_ddc91a87; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ddc91a87 ON group_ USING btree (companyid, active_);


--
-- TOC entry 3429 (class 1259 OID 31393)
-- Name: ix_df37d92e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_df37d92e ON dlfileentry USING btree (groupid, folderid, filename);


--
-- TOC entry 4366 (class 1259 OID 32465)
-- Name: ix_df5748b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_df5748b ON kbarticle USING btree (groupid, status);


--
-- TOC entry 3467 (class 1259 OID 31424)
-- Name: ix_dfd809d3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_dfd809d3 ON dlfileversion USING btree (groupid, folderid, status);


--
-- TOC entry 4146 (class 1259 OID 32067)
-- Name: ix_e002061; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e002061 ON journalfolder USING btree (uuid_, groupid);


--
-- TOC entry 4176 (class 1259 OID 32096)
-- Name: ix_e0092ff0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e0092ff0 ON wikipage USING btree (groupid, nodeid, head, status);


--
-- TOC entry 4155 (class 1259 OID 32092)
-- Name: ix_e0e6d12c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e0e6d12c ON wikinode USING btree (uuid_, companyid);


--
-- TOC entry 3583 (class 1259 OID 31503)
-- Name: ix_e10ac39; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e10ac39 ON layoutrevision USING btree (layoutsetbranchid, head, plid);


--
-- TOC entry 3558 (class 1259 OID 31491)
-- Name: ix_e118c537; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e118c537 ON layout USING btree (uuid_, groupid, privatelayout);


--
-- TOC entry 3331 (class 1259 OID 31336)
-- Name: ix_e119938a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e119938a ON assetentries_assetcategories USING btree (entryid);


--
-- TOC entry 3613 (class 1259 OID 31523)
-- Name: ix_e15a5db5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e15a5db5 ON mbcategory USING btree (companyid, status);


--
-- TOC entry 3655 (class 1259 OID 31555)
-- Name: ix_e1e7142b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e1e7142b ON mbthread USING btree (groupid, status);


--
-- TOC entry 4177 (class 1259 OID 32109)
-- Name: ix_e1f55fb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e1f55fb ON wikipage USING btree (resourceprimkey, nodeid, head);


--
-- TOC entry 4049 (class 1259 OID 31944)
-- Name: ix_e1f8b23d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e1f8b23d ON kaleotask USING btree (companyid);


--
-- TOC entry 3468 (class 1259 OID 31423)
-- Name: ix_e2815081; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e2815081 ON dlfileversion USING btree (fileentryid, version);


--
-- TOC entry 3672 (class 1259 OID 31570)
-- Name: ix_e301bdf5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e301bdf5 ON organization_ USING btree (companyid, name);


--
-- TOC entry 3934 (class 1259 OID 31714)
-- Name: ix_e32cc19; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e32cc19 ON usernotificationevent USING btree (userid, delivered, actionrequired);


--
-- TOC entry 4213 (class 1259 OID 32238)
-- Name: ix_e3baf436; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e3baf436 ON ddmcontent USING btree (companyid);


--
-- TOC entry 3996 (class 1259 OID 31784)
-- Name: ix_e3f1286b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e3f1286b ON lock_ USING btree (expirationdate);


--
-- TOC entry 4400 (class 1259 OID 32518)
-- Name: ix_e3f57bd6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e3f57bd6 ON syncdlobject USING btree (type_, typepk);


--
-- TOC entry 4248 (class 1259 OID 32262)
-- Name: ix_e43143a3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e43143a3 ON ddmstructurelink USING btree (classnameid, classpk, structureid);


--
-- TOC entry 3684 (class 1259 OID 31575)
-- Name: ix_e4d7ef87; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e4d7ef87 ON passwordpolicy USING btree (uuid_, companyid);


--
-- TOC entry 3964 (class 1259 OID 31722)
-- Name: ix_e4efba8d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e4efba8d ON usertracker USING btree (userid);


--
-- TOC entry 4030 (class 1259 OID 31931)
-- Name: ix_e66a153a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e66a153a ON kaleolog USING btree (kaleoclassname, kaleoclasspk, kaleoinstancetokenid, type_);


--
-- TOC entry 3436 (class 1259 OID 31405)
-- Name: ix_e69431b7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e69431b7 ON dlfileentrymetadata USING btree (uuid_, companyid);


--
-- TOC entry 4264 (class 1259 OID 32269)
-- Name: ix_e6dfab84; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e6dfab84 ON ddmtemplate USING btree (groupid, classnameid, templatekey);


--
-- TOC entry 4178 (class 1259 OID 32106)
-- Name: ix_e745ea26; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e745ea26 ON wikipage USING btree (nodeid, title, head);


--
-- TOC entry 3480 (class 1259 OID 31429)
-- Name: ix_e79be432; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e79be432 ON dlfolder USING btree (companyid, status);


--
-- TOC entry 3387 (class 1259 OID 31374)
-- Name: ix_e7b95510; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e7b95510 ON browsertracker USING btree (userid);


--
-- TOC entry 4116 (class 1259 OID 32028)
-- Name: ix_e82f322b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e82f322b ON journalarticle USING btree (companyid, version, status);


--
-- TOC entry 4299 (class 1259 OID 32349)
-- Name: ix_e848278f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e848278f ON bookmarksentry USING btree (resourceblockid);


--
-- TOC entry 3625 (class 1259 OID 31535)
-- Name: ix_e858f170; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e858f170 ON mbmailinglist USING btree (uuid_, groupid);


--
-- TOC entry 3322 (class 1259 OID 31330)
-- Name: ix_e8d019aa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_e8d019aa ON assetcategory USING btree (uuid_, groupid);


--
-- TOC entry 4374 (class 1259 OID 32480)
-- Name: ix_e8d43932; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e8d43932 ON kbcomment USING btree (groupid, classnameid);


--
-- TOC entry 3857 (class 1259 OID 31682)
-- Name: ix_e8f34171; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e8f34171 ON subscription USING btree (userid, classnameid);


--
-- TOC entry 3710 (class 1259 OID 31587)
-- Name: ix_e922d6c0; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e922d6c0 ON portletitem USING btree (groupid, portletid, classnameid);


--
-- TOC entry 4147 (class 1259 OID 32063)
-- Name: ix_e988689e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_e988689e ON journalfolder USING btree (groupid, name);


--
-- TOC entry 4117 (class 1259 OID 32029)
-- Name: ix_ea05e9e1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ea05e9e1 ON journalarticle USING btree (displaydate, status);


--
-- TOC entry 4437 (class 1259 OID 32606)
-- Name: ix_ea6fd516; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ea6fd516 ON shoppingitemprice USING btree (itemid);


--
-- TOC entry 4300 (class 1259 OID 32351)
-- Name: ix_eaa02a91; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_eaa02a91 ON bookmarksentry USING btree (uuid_, groupid);


--
-- TOC entry 3569 (class 1259 OID 31494)
-- Name: ix_eab317c8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_eab317c8 ON layoutfriendlyurl USING btree (companyid);


--
-- TOC entry 3377 (class 1259 OID 31360)
-- Name: ix_eb2dce27; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_eb2dce27 ON blogsentry USING btree (companyid, status);


--
-- TOC entry 4214 (class 1259 OID 32241)
-- Name: ix_eb9bde28; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_eb9bde28 ON ddmcontent USING btree (uuid_, groupid);


--
-- TOC entry 3791 (class 1259 OID 31633)
-- Name: ix_ebc931b8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ebc931b8 ON role_ USING btree (companyid, name);


--
-- TOC entry 3398 (class 1259 OID 31379)
-- Name: ix_ec00543c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ec00543c ON company USING btree (webid);


--
-- TOC entry 4011 (class 1259 OID 31922)
-- Name: ix_ec14f81a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ec14f81a ON kaleodefinition USING btree (companyid, name, version);


--
-- TOC entry 3641 (class 1259 OID 31541)
-- Name: ix_ed39ac98; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ed39ac98 ON mbmessage USING btree (groupid, status);


--
-- TOC entry 3430 (class 1259 OID 31395)
-- Name: ix_ed5ca615; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_ed5ca615 ON dlfileentry USING btree (groupid, folderid, title);


--
-- TOC entry 3762 (class 1259 OID 31617)
-- Name: ix_edb9986e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_edb9986e ON resourceaction USING btree (name, actionid);


--
-- TOC entry 4401 (class 1259 OID 32517)
-- Name: ix_ee41cbeb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ee41cbeb ON syncdlobject USING btree (treepath, event);


--
-- TOC entry 3898 (class 1259 OID 31729)
-- Name: ix_ee8abd19; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ee8abd19 ON user_ USING btree (companyid, modifieddate);


--
-- TOC entry 3452 (class 1259 OID 31415)
-- Name: ix_eed06670; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_eed06670 ON dlfilerank USING btree (userid);


--
-- TOC entry 3286 (class 1259 OID 30446)
-- Name: ix_eefe382a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_eefe382a ON quartz_triggers USING btree (sched_name, next_fire_time);


--
-- TOC entry 4118 (class 1259 OID 32046)
-- Name: ix_ef9b7028; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ef9b7028 ON journalarticle USING btree (smallimageid);


--
-- TOC entry 4148 (class 1259 OID 32065)
-- Name: ix_efd9cac; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_efd9cac ON journalfolder USING btree (groupid, parentfolderid, status);


--
-- TOC entry 3287 (class 1259 OID 30447)
-- Name: ix_f026cf4c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f026cf4c ON quartz_triggers USING btree (sched_name, next_fire_time, trigger_state);


--
-- TOC entry 4265 (class 1259 OID 32268)
-- Name: ix_f0c3449; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f0c3449 ON ddmtemplate USING btree (groupid, classnameid, classpk, type_, mode_);


--
-- TOC entry 3378 (class 1259 OID 31363)
-- Name: ix_f0e73383; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f0e73383 ON blogsentry USING btree (groupid, displaydate, status);


--
-- TOC entry 4469 (class 1259 OID 32675)
-- Name: ix_f0faf226; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f0faf226 ON calendar USING btree (resourceblockid);


--
-- TOC entry 3939 (class 1259 OID 31740)
-- Name: ix_f10b6c6b; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f10b6c6b ON users_groups USING btree (userid);


--
-- TOC entry 3823 (class 1259 OID 31657)
-- Name: ix_f1c1a617; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f1c1a617 ON socialactivitylimit USING btree (groupid, userid, classnameid, classpk, activitytype, activitycountername);


--
-- TOC entry 3696 (class 1259 OID 31580)
-- Name: ix_f202b9ce; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f202b9ce ON phone USING btree (userid);


--
-- TOC entry 4034 (class 1259 OID 31936)
-- Name: ix_f28c443e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f28c443e ON kaleonode USING btree (companyid, kaleodefinitionid);


--
-- TOC entry 3306 (class 1259 OID 31319)
-- Name: ix_f2949120; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f2949120 ON announcementsentry USING btree (uuid_, companyid);


--
-- TOC entry 3288 (class 1259 OID 30448)
-- Name: ix_f2dd7c7e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f2dd7c7e ON quartz_triggers USING btree (sched_name, next_fire_time, trigger_state, misfire_instr);


--
-- TOC entry 4288 (class 1259 OID 32326)
-- Name: ix_f2f1e964; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f2f1e964 ON marketplace_module USING btree (contextname);


--
-- TOC entry 4340 (class 1259 OID 32420)
-- Name: ix_f2f6c19a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f2f6c19a ON sn_wallentry USING btree (groupid, userid);


--
-- TOC entry 4039 (class 1259 OID 31939)
-- Name: ix_f3362e93; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f3362e93 ON kaleonotification USING btree (kaleoclassname, kaleoclasspk, executiontype);


--
-- TOC entry 4119 (class 1259 OID 32038)
-- Name: ix_f35391e8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f35391e8 ON journalarticle USING btree (groupid, folderid, status);


--
-- TOC entry 4454 (class 1259 OID 32637)
-- Name: ix_f3c9f36; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f3c9f36 ON pollsquestion USING btree (uuid_, groupid);


--
-- TOC entry 3792 (class 1259 OID 31634)
-- Name: ix_f3e1c6fc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f3e1c6fc ON role_ USING btree (companyid, type_);


--
-- TOC entry 4194 (class 1259 OID 32153)
-- Name: ix_f3efdcb3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f3efdcb3 ON mdrrule USING btree (uuid_, groupid);


--
-- TOC entry 4022 (class 1259 OID 31929)
-- Name: ix_f42aaff6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f42aaff6 ON kaleoinstancetoken USING btree (kaleoinstanceid);


--
-- TOC entry 3570 (class 1259 OID 31498)
-- Name: ix_f4321a54; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f4321a54 ON layoutfriendlyurl USING btree (uuid_, companyid);


--
-- TOC entry 3793 (class 1259 OID 31635)
-- Name: ix_f436ec8e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f436ec8e ON role_ USING btree (name);


--
-- TOC entry 3778 (class 1259 OID 31628)
-- Name: ix_f4555981; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f4555981 ON resourcepermission USING btree (scope);


--
-- TOC entry 4442 (class 1259 OID 32609)
-- Name: ix_f474fd89; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f474fd89 ON shoppingorder USING btree (pptxnid);


--
-- TOC entry 4478 (class 1259 OID 32685)
-- Name: ix_f4c61797; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f4c61797 ON calendarbooking USING btree (uuid_, groupid);


--
-- TOC entry 3805 (class 1259 OID 31640)
-- Name: ix_f542e9bc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f542e9bc ON socialactivity USING btree (activitysetid);


--
-- TOC entry 3754 (class 1259 OID 31612)
-- Name: ix_f543ea4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f543ea4 ON repository USING btree (uuid_, companyid);


--
-- TOC entry 3899 (class 1259 OID 31732)
-- Name: ix_f6039434; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f6039434 ON user_ USING btree (companyid, status);


--
-- TOC entry 4498 (class 1259 OID 32724)
-- Name: ix_f661d061; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f661d061 ON mail_attachment USING btree (messageid);


--
-- TOC entry 3642 (class 1259 OID 31536)
-- Name: ix_f6687633; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f6687633 ON mbmessage USING btree (classnameid, classpk, status);


--
-- TOC entry 3779 (class 1259 OID 31625)
-- Name: ix_f6bae86a; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f6bae86a ON resourcepermission USING btree (companyid, scope, primkey);


--
-- TOC entry 4184 (class 1259 OID 32118)
-- Name: ix_f705c7a9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f705c7a9 ON wikipageresource USING btree (uuid_, groupid);


--
-- TOC entry 3829 (class 1259 OID 31661)
-- Name: ix_f71071bd; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f71071bd ON socialactivityset USING btree (groupid, userid, type_);


--
-- TOC entry 3489 (class 1259 OID 31442)
-- Name: ix_f74ab912; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f74ab912 ON emailaddress USING btree (uuid_, companyid);


--
-- TOC entry 3979 (class 1259 OID 31757)
-- Name: ix_f75690bb; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f75690bb ON website USING btree (userid);


--
-- TOC entry 3620 (class 1259 OID 31531)
-- Name: ix_f7aac799; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f7aac799 ON mbdiscussion USING btree (uuid_, groupid);


--
-- TOC entry 4479 (class 1259 OID 32682)
-- Name: ix_f7b8a941; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f7b8a941 ON calendarbooking USING btree (parentcalendarbookingid, status);


--
-- TOC entry 3614 (class 1259 OID 31527)
-- Name: ix_f7d28c2f; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_f7d28c2f ON mbcategory USING btree (uuid_, groupid);


--
-- TOC entry 3656 (class 1259 OID 31558)
-- Name: ix_f8ca2ab9; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f8ca2ab9 ON mbthread USING btree (uuid_, companyid);


--
-- TOC entry 4455 (class 1259 OID 32636)
-- Name: ix_f910bbb4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f910bbb4 ON pollsquestion USING btree (uuid_, companyid);


--
-- TOC entry 4001 (class 1259 OID 31916)
-- Name: ix_f95a622; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f95a622 ON kaleoaction USING btree (kaleodefinitionid);


--
-- TOC entry 3949 (class 1259 OID 31744)
-- Name: ix_f987a0dc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f987a0dc ON users_roles USING btree (companyid);


--
-- TOC entry 4239 (class 1259 OID 32257)
-- Name: ix_f9fb8d60; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_f9fb8d60 ON ddmstructure USING btree (uuid_, companyid);


--
-- TOC entry 3806 (class 1259 OID 31643)
-- Name: ix_fb604dc7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fb604dc7 ON socialactivity USING btree (groupid, userid, classnameid, classpk, type_, receiveruserid);


--
-- TOC entry 3944 (class 1259 OID 31743)
-- Name: ix_fb646ca6; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fb646ca6 ON users_orgs USING btree (userid);


--
-- TOC entry 4179 (class 1259 OID 32113)
-- Name: ix_fbbe7c96; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fbbe7c96 ON wikipage USING btree (userid, nodeid, status);


--
-- TOC entry 4367 (class 1259 OID 32456)
-- Name: ix_fbc2d349; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fbc2d349 ON kbarticle USING btree (companyid, status);


--
-- TOC entry 4094 (class 1259 OID 31978)
-- Name: ix_fbf5faa2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fbf5faa2 ON backgroundtask USING btree (completed);


--
-- TOC entry 4416 (class 1259 OID 32594)
-- Name: ix_fc46fe16; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_fc46fe16 ON shoppingcart USING btree (groupid, userid);


--
-- TOC entry 3876 (class 1259 OID 31692)
-- Name: ix_fc4eea64; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fc4eea64 ON trashentry USING btree (groupid, classnameid);


--
-- TOC entry 3626 (class 1259 OID 31534)
-- Name: ix_fc61676e; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fc61676e ON mbmailinglist USING btree (uuid_, companyid);


--
-- TOC entry 4375 (class 1259 OID 32482)
-- Name: ix_fd56a55d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fd56a55d ON kbcomment USING btree (userid, classnameid, classpk);


--
-- TOC entry 3562 (class 1259 OID 31493)
-- Name: ix_fd57097d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_fd57097d ON layoutbranch USING btree (layoutsetbranchid, plid, name);


--
-- TOC entry 4189 (class 1259 OID 32148)
-- Name: ix_fd90786c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fd90786c ON mdraction USING btree (rulegroupinstanceid);


--
-- TOC entry 3459 (class 1259 OID 31420)
-- Name: ix_fdb4a946; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_fdb4a946 ON dlfileshortcut USING btree (uuid_, groupid);


--
-- TOC entry 3414 (class 1259 OID 31387)
-- Name: ix_fdd1aaa8; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_fdd1aaa8 ON dlcontent USING btree (companyid, repositoryid, path_, version);


--
-- TOC entry 3662 (class 1259 OID 31563)
-- Name: ix_feb0fc87; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_feb0fc87 ON mbthreadflag USING btree (uuid_, groupid);


--
-- TOC entry 3345 (class 1259 OID 31344)
-- Name: ix_fec4a201; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fec4a201 ON assetentry USING btree (layoutuuid);


--
-- TOC entry 4006 (class 1259 OID 31917)
-- Name: ix_fee46067; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fee46067 ON kaleocondition USING btree (companyid);


--
-- TOC entry 3492 (class 1259 OID 31443)
-- Name: ix_fefc8da7; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ix_fefc8da7 ON expandocolumn USING btree (tableid, name);


--
-- TOC entry 4430 (class 1259 OID 32601)
-- Name: ix_fefe7d76; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_fefe7d76 ON shoppingitem USING btree (groupid, categoryid);


--
-- TOC entry 4431 (class 1259 OID 32604)
-- Name: ix_ff203304; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ff203304 ON shoppingitem USING btree (smallimageid);


--
-- TOC entry 3469 (class 1259 OID 31426)
-- Name: ix_ffb3395c; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ffb3395c ON dlfileversion USING btree (mimetype);


--
-- TOC entry 3861 (class 1259 OID 31683)
-- Name: ix_ffcbb747; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ffcbb747 ON systemevent USING btree (groupid, classnameid, classpk, type_);


--
-- TOC entry 4538 (class 1259 OID 32836)
-- Name: xattr_dir_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX xattr_dir_id_idx ON xattr USING btree (dir_id);


--
-- TOC entry 4687 (class 2618 OID 30608)
-- Name: delete_dlcontent_data_; Type: RULE; Schema: public; Owner: postgres
--

CREATE RULE delete_dlcontent_data_ AS
    ON DELETE TO dlcontent DO  SELECT
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM pg_largeobject
              WHERE (pg_largeobject.loid = old.data_))) THEN lo_unlink(old.data_)
            ELSE NULL::integer
        END AS "case"
   FROM dlcontent
  WHERE (dlcontent.data_ = old.data_);


--
-- TOC entry 4688 (class 2618 OID 30609)
-- Name: update_dlcontent_data_; Type: RULE; Schema: public; Owner: postgres
--

CREATE RULE update_dlcontent_data_ AS
    ON UPDATE TO dlcontent
   WHERE ((old.data_ IS DISTINCT FROM new.data_) AND (old.data_ IS NOT NULL)) DO  SELECT
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM pg_largeobject
              WHERE (pg_largeobject.loid = old.data_))) THEN lo_unlink(old.data_)
            ELSE NULL::integer
        END AS "case"
   FROM dlcontent
  WHERE (dlcontent.data_ = old.data_);


--
-- TOC entry 4572 (class 2620 OID 41791)
-- Name: dir_trig; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER dir_trig INSTEAD OF INSERT OR DELETE OR UPDATE ON dir FOR EACH ROW EXECUTE PROCEDURE dir_update();


--
-- TOC entry 4571 (class 2620 OID 33158)
-- Name: group_trig; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER group_trig BEFORE INSERT ON usergroup FOR EACH ROW EXECUTE PROCEDURE set_sid_gid();


--
-- TOC entry 4568 (class 2620 OID 32861)
-- Name: set_dlfileentry_uid_gid_trig; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_dlfileentry_uid_gid_trig BEFORE INSERT ON dlfileentry FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();


--
-- TOC entry 4569 (class 2620 OID 32860)
-- Name: set_dlfolder_uid_gid_trig; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_dlfolder_uid_gid_trig BEFORE INSERT ON dlfolder FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();


--
-- TOC entry 4570 (class 2620 OID 32862)
-- Name: user_trig; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER user_trig BEFORE INSERT ON user_ FOR EACH ROW EXECUTE PROCEDURE set_sid_uid();


--
-- TOC entry 4563 (class 2606 OID 33061)
-- Name: gantt_finance_gantt_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_finance
    ADD CONSTRAINT gantt_finance_gantt_task_id_fkey FOREIGN KEY (gantt_task_id) REFERENCES gantt_tasks(id);


--
-- TOC entry 4564 (class 2606 OID 33072)
-- Name: gantt_finance_status_gantt_finance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_finance_status
    ADD CONSTRAINT gantt_finance_status_gantt_finance_id_fkey FOREIGN KEY (gantt_finance_id) REFERENCES gantt_finance(id);


--
-- TOC entry 4559 (class 2606 OID 33015)
-- Name: gantt_tasks_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks
    ADD CONSTRAINT gantt_tasks_org_id_fkey FOREIGN KEY (org_id) REFERENCES organization_(organizationid);


--
-- TOC entry 4562 (class 2606 OID 33034)
-- Name: gantt_tasks_users_gantt_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks_users
    ADD CONSTRAINT gantt_tasks_users_gantt_task_id_fkey FOREIGN KEY (gantt_task_id) REFERENCES gantt_tasks(id);


--
-- TOC entry 4560 (class 2606 OID 33044)
-- Name: gantt_tasks_users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks_users
    ADD CONSTRAINT gantt_tasks_users_role_id_fkey FOREIGN KEY (role_id) REFERENCES gantt_roles(role_id);


--
-- TOC entry 4561 (class 2606 OID 33039)
-- Name: gantt_tasks_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY gantt_tasks_users
    ADD CONSTRAINT gantt_tasks_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_(userid);


--
-- TOC entry 4565 (class 2606 OID 33242)
-- Name: iee_tmpl_folders_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl_folders
    ADD CONSTRAINT iee_tmpl_folders_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES iee_tmpl_folders(id);


--
-- TOC entry 4567 (class 2606 OID 33255)
-- Name: iee_tmpl_folders_perms_folder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl_folders_perms
    ADD CONSTRAINT iee_tmpl_folders_perms_folder_id_fkey FOREIGN KEY (folder_id) REFERENCES iee_tmpl_folders(id);


--
-- TOC entry 4566 (class 2606 OID 33237)
-- Name: iee_tmpl_folders_tmpl_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY iee_tmpl_folders
    ADD CONSTRAINT iee_tmpl_folders_tmpl_id_fkey FOREIGN KEY (tmpl_id) REFERENCES iee_tmpl(id);


--
-- TOC entry 4696 (class 0 OID 0)
-- Dependencies: 7
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2017-04-03 13:48:00

--
-- PostgreSQL database dump complete
--

