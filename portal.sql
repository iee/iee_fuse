CREATE TABLE dir_fs (
	id BIGSERIAL,
	parent_id BIGINT,
	name TEXT,
	size BIGINT DEFAULT 0,
	mode INTEGER NOT NULL DEFAULT 0,
	uid INTEGER NOT NULL DEFAULT 0,
	gid INTEGER NOT NULL DEFAULT 0,
	ctime TIMESTAMP,
	mtime TIMESTAMP,
	atime TIMESTAMP,
	PRIMARY KEY( id ),
	UNIQUE( name, parent_id )
);
CREATE TABLE data (
	dir_id BIGINT,
	block_no BIGINT NOT NULL DEFAULT 0,
	data BYTEA,
	PRIMARY KEY( dir_id, block_no )
);
CREATE TABLE xattr (
	id BIGSERIAL,
	dir_id BIGINT,
	name VARCHAR( 1024 ),
	val BYTEA,
	PRIMARY KEY( id )
);
CREATE EXTENSION "uuid-ossp";
CREATE INDEX data_dir_id_idx ON data( dir_id );
CREATE INDEX data_block_no_idx ON data( block_no );
CREATE INDEX xattr_dir_id_idx ON xattr( dir_id );
CREATE INDEX dir_parent_id_idx ON dir_fs( parent_id );
ALTER TABLE xattr ADD CONSTRAINT id_data UNIQUE (dir_id,name);
ALTER TABLE dlfileentry ADD accessdate TIMESTAMP;
ALTER TABLE dlfileentry ALTER accessdate SET DEFAULT localtimestamp;
ALTER TABLE dlfolder ADD accessdate TIMESTAMP;
ALTER TABLE dlfolder ALTER accessdate SET DEFAULT localtimestamp;
ALTER TABLE dlfileentry ADD mode INTEGER;
ALTER TABLE dlfileentry ALTER mode SET DEFAULT 33206;
ALTER TABLE dlfolder ADD mode INTEGER;
ALTER TABLE dlfolder ALTER mode SET DEFAULT 16895;
ALTER TABLE dlfolder ADD size_ BIGINT;
ALTER TABLE dlfolder ALTER size_ SET DEFAULT 0;
ALTER TABLE dlfolder ADD uid INTEGER;
ALTER TABLE dlfolder ADD gid INTEGER;
ALTER TABLE dlfileentry ADD uid INTEGER;
ALTER TABLE user_ ADD sid VARCHAR ( 75 );
ALTER TABLE user_ ALTER sid SET DEFAULT 'NO_SID';
ALTER TABLE user_ ADD uid INTEGER;
ALTER TABLE user_ ALTER uid SET DEFAULT 0;
ALTER TABLE dlfileentry ADD gid INTEGER;
ALTER TABLE dlfileentry ADD del INTEGER;
ALTER TABLE dlfileentry ALTER del SET DEFAULT 0;
ALTER TABLE dir_fs ADD COLUMN uuid VARCHAR ( 75 );
ALTER TABLE dir_fs ALTER uuid set DEFAULT uuid_generate_v4();
ALTER TABLE usergroup ADD sid VARCHAR ( 75 );
ALTER TABLE usergroup ALTER sid SET DEFAULT 'NO_SID';
ALTER TABLE usergroup ADD gid INTEGER;
ALTER TABLE usergroup ALTER gid SET DEFAULT 0;
CREATE OR REPLACE FUNCTION get_gid_from_sid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_gid_from_sid'
LANGUAGE C STRICT;
CREATE OR REPLACE FUNCTION set_sid_gid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
    DECLARE
    str VARCHAR (75);
    BEGIN
    str = CAST ( get_sid(NEW.name) AS VARCHAR (75) );
    NEW.sid = str;
    NEW.gid = get_gid_from_sid(str);
    RETURN NEW;
    END;
$function$;
CREATE TRIGGER group_trig BEFORE INSERT ON usergroup FOR EACH ROW EXECUTE PROCEDURE set_sid_gid();
CREATE OR REPLACE FUNCTION func_insupd_ntacl(id_dir bigint, data_val bytea) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
INSERT INTO xattr (dir_id, name, val)
VALUES (id_dir, 'security.NTACL', data_val)
ON CONFLICT (dir_id, name)
DO UPDATE SET
val = data_val;
END;
$function$;
CREATE OR REPLACE FUNCTION func_get_tree(root_folder_id bigint) RETURNS text 
LANGUAGE plpgsql
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION func_update_ntacl(root_folder_id bigint, sd_folder bytea, sd_sub_folder bytea, sd_file bytea) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	UPDATE xattr b SET val = sd_sub_folder
	FROM d
	WHERE d.id = b.dir_id AND name = 'security.NTACL' AND d.mode & 61440 = 16384;

	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	UPDATE xattr b SET val = sd_file
	FROM d
	WHERE d.id = b.dir_id AND name = 'security.NTACL' AND d.mode & 61440 = 32768;
	
	UPDATE xattr SET val = sd_folder WHERE dir_id = root_folder_id AND name = 'security.NTACL';

END;
$function$;
CREATE OR REPLACE FUNCTION group_parent_id(BIGINT) RETURNS BIGINT 
LANGUAGE plpgsql
AS $function$
DECLARE
	parent_id BIGINT;
	classname_id BIGINT;
	parent_classname_id BIGINT;
	classname VARCHAR(75);
BEGIN
	SELECT g.parentgroupid, g.classnameid, g2.classnameid, c.value INTO parent_id, classname_id, parent_classname_id, classname FROM group_ g LEFT OUTER JOIN group_ g2 ON g.parentgroupid = g2.groupid, classname_ c WHERE g.classnameid=c.classnameid AND g.groupid=$1;
	IF (parent_id != 0 AND classname_id = parent_classname_id ) THEN
	RETURN parent_id;
	END IF;
	IF classname='com.liferay.portal.model.User' THEN
	RETURN 3::BIGINT;
	ELSEIF classname='com.liferay.portal.model.Organization' THEN
	RETURN 2::BIGINT;	
	ELSEIF classname='com.liferay.portal.model.Group' THEN
	RETURN 1::BIGINT;
	END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION group_descriptive_name(BIGINT) RETURNS TEXT 
LANGUAGE plpgsql
AS $function$
DECLARE
	classname VARCHAR(75);
	classpk2 BIGINT;
BEGIN
	SELECT c.value, g.classpk INTO classname, classpk2 FROM group_ g,classname_ c WHERE g.classnameid=c.classnameid AND groupid=$1;
	IF classname = 'com.liferay.portal.model.Group' THEN
	RETURN (SELECT data_ FROM expandovalue WHERE columnid=(SELECT columnid FROM expandocolumn WHERE name='GROUP_SHORT_NAME')
	AND columnid=(SELECT columnid FROM classname_ WHERE value='com.liferay.portal.model.Group') AND classpk=$1);
	ELSEIF classname = 'com.liferay.portal.model.User' THEN
	RETURN (SELECT  lastname || ' ' || firstname || ' ' || middlename FROM user_ WHERE userid=classpk2);
	ELSEIF classname = 'com.liferay.portal.model.Organization' THEN
	RETURN (SELECT name FROM organization_ WHERE organizationid=classpk2);
	ELSE 
	RETURN CAST( $1 AS TEXT );
	END IF;
END;
$function$;

--CREATE OR REPLACE VIEW dir AS (
--(SELECT usergroup.usergroupid AS id, 0 AS parent_id, usergroup.name::text AS name, 0::BIGINT AS size, 16895 AS mode, 0 AS uid, 0 AS gid, now()::timestamp without time zone AS ctime, now()::timestamp without time zone AS mtime, now()::timestamp without time zone AS atime FROM usergroup WHERE NOT (usergroup.usergroupid IN ( SELECT expandovalue.classpk FROM expandovalue WHERE expandovalue.classnameid = (( SELECT classname_.classnameid FROM classname_ WHERE classname_.value::text = 'com.liferay.portal.kernel.model.UserGroup'::text)) AND expandovalue.columnid = (( SELECT expandocolumn.columnid FROM expandocolumn WHERE expandocolumn.name::text = 'IS_SYSTEM'::text)) AND expandovalue.data_ = 'true'::text))) UNION
--(SELECT gantt_tasks.site_id AS id, gantt_tasks.ug_id AS parent_id, gantt_tasks.text AS name, 0::BIGINT AS size, 16895 AS mode, 0 AS uid, 0 AS gid, now()::timestamp without time zone AS ctime, now()::timestamp without time zone AS mtime, now()::timestamp without time zone AS atime FROM gantt_tasks) UNION
--(SELECT d.folderid AS id, CASE WHEN d.parentfolderid = 0 THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name, d.size_ AS size, d.mode, d.uid, d.gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.hidden_ = false AND d.name::text !~~ '/%'::text) UNION
--(SELECT f.fileentryid AS id, CASE WHEN f.folderid = 0 THEN f.groupid ELSE f.folderid END AS parent_id, CASE WHEN "position"(lower(f.title::text), '.'::text || f.extension::text) = 0 THEN ((f.title::text || '.'::text) || f.extension::text)::character varying ELSE f.title END AS name, f.size_ AS size, f.mode, f.uid, f.gid, f.createdate AS ctime, f.modifieddate AS mtime, f.accessdate AS atime FROM dlfileentry f WHERE f.extension::text <> ''::text AND f.title::text !~~ '/%'::text AND f.del = 0) UNION
--(SELECT l.id, l.parent_id, l.name, l.size, l.mode, l.uid, l.gid, l.ctime, l.mtime, l.atime FROM dir_fs l));

CREATE OR REPLACE VIEW dir AS (
(select organizationid AS id, 0 AS parent_id, name::TEXT, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime from organization_) union
(select site_id AS id, org_id AS parent_id, text AS name, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime from gantt_tasks) union
(SELECT o.groupid::BIGINT AS id, group_parent_id(o.groupid) AS parent_id, group_descriptive_name(o.groupid) AS name, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime FROM group_ o WHERE classnameid in (select classnameid from classname_ WHERE value in ('com.liferay.portal.model.Group','com.liferay.portal.model.User','com.liferay.portal.model.Organization')) and trim(group_descriptive_name(o.groupid)) != '') UNION
(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.hidden_='f' AND d.name NOT LIKE '/%') UNION
(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, CASE WHEN position('.' || f.extension in lower(f.title))=0 THEN f.title || '.' || f.extension ELSE f.title END AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.extension != '' AND f.title NOT LIKE '/%' AND f.del = 0) UNION
(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));

--CREATE OR REPLACE VIEW dir AS (
--(SELECT o.groupid::BIGINT AS id, group_parent_id(o.groupid) AS parent_id, group_descriptive_name(o.groupid) AS name, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime FROM group_ o WHERE classnameid in (select classnameid from classname_ WHERE value in ('com.liferay.portal.model.Group','com.liferay.portal.model.User','com.liferay.portal.model.Organization')) and trim(group_descriptive_name(o.groupid)) != '') UNION
--(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.hidden_='f' AND d.name NOT LIKE '/%') UNION
--(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, CASE WHEN position('.' || f.extension in lower(f.title))=0 THEN f.title || '.' || f.extension ELSE f.title END AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.extension != '' AND f.title NOT LIKE '/%' AND f.del = 0) UNION
--(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));

--CREATE OR REPLACE VIEW dir AS (
--(SELECT o.groupid::BIGINT AS id, group_parent_id(o.groupid) AS parent_id, group_descriptive_name(o.groupid) AS name, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime FROM group_ o WHERE classnameid in (select classnameid from classname_ WHERE value in ('com.liferay.portal.model.Group','com.liferay.portal.model.User','com.liferay.portal.model.Organization')) and trim(group_descriptive_name(o.groupid)) != '') UNION
--(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.hidden_='f' AND d.name NOT LIKE '/%') UNION
--(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, f.title AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.title NOT LIKE '/%' AND f.del = 0) UNION
--(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));

CREATE OR REPLACE FUNCTION dir_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE FUNCTION get_uid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_uid'
LANGUAGE C STRICT;
CREATE FUNCTION get_gid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_gid'
LANGUAGE C STRICT;
CREATE FUNCTION get_sid(VARCHAR) RETURNS TEXT
AS 'libgetuid', 'get_sid'
LANGUAGE C STRICT;
CREATE FUNCTION get_screenname(INTEGER) RETURNS TEXT
AS 'libgetuid', 'get_screenname'
LANGUAGE C STRICT;
CREATE OR REPLACE FUNCTION get_uid_from_sid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_uid_from_sid'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION set_sid_uid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
    DECLARE
    str VARCHAR (75);
    BEGIN
    str = CAST ( get_sid(NEW.screenname) AS VARCHAR (75) );
    NEW.sid = str;
    NEW.uid = get_uid_from_sid(str);
    RETURN NEW;
    END;
$function$;

CREATE OR REPLACE FUNCTION copy_xattr_from_to(from_id bigint, to_id bigint) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO xattr( dir_id, name, val ) VALUES ( to_id, 'security.NTACL', (SELECT val FROM xattr WHERE dir_id = from_id AND name = 'security.NTACL'));
END;
$function$;

--CREATE OR REPLACE FUNCTION set_sid()
--RETURNS TRIGGER
--LANGUAGE plpgsql
--AS $function$
--	DECLARE
--	str VARCHAR (75);
--	BEGIN
--	str = CAST ( get_sid(NEW.screenname) AS VARCHAR (75) );
--	NEW.sid = str;
--	RETURN NEW;
--	END;
--$function$;
CREATE OR REPLACE FUNCTION set_uid_gid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
	DECLARE
	scr VARCHAR (75);
	BEGIN
	scr = (SELECT u.screenname FROM user_ u WHERE u.userid=NEW.userid);
	NEW.uid = get_uid(scr);
	NEW.gid = get_gid(scr);
	RETURN NEW;
	END;
$function$;

CREATE TRIGGER dir_trig INSTEAD OF INSERT OR UPDATE OR DELETE ON dir FOR EACH ROW EXECUTE PROCEDURE dir_update();
CREATE TRIGGER set_dlfolder_uid_gid_trig BEFORE INSERT ON dlfolder FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();
CREATE TRIGGER set_dlfileentry_uid_gid_trig BEFORE INSERT ON dlfileentry FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();
--CREATE TRIGGER user_trig BEFORE INSERT ON user_ FOR EACH ROW EXECUTE PROCEDURE set_sid();
CREATE TRIGGER user_trig BEFORE INSERT ON user_ FOR EACH ROW EXECUTE PROCEDURE set_sid_uid();
UPDATE user_ SET sid = 'NO_SID';
UPDATE dlfolder SET mode = 16895;
UPDATE dlfolder SET size_=0;
UPDATE dlfolder SET accessdate = localtimestamp;
UPDATE dlfileentry SET mode = 33188;
UPDATE dlfileentry SET del = 0;
UPDATE dlfileentry SET accessdate = localtimestamp;
--UPDATE dlfileentry SET last_event = 0;
INSERT INTO dir_fs ( id, parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES( 0, 0, '/', 0, 16895, 0, 0, localtimestamp, localtimestamp, localtimestamp );
INSERT INTO dir_fs ( id, parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES( 1, 0, 'Проекты', 0, 16895, 0, 0, localtimestamp, localtimestamp, localtimestamp );
INSERT INTO dir_fs ( id, parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES( 2, 0, 'Организации', 0, 16895, 0, 0, localtimestamp, localtimestamp, localtimestamp );
INSERT INTO dir_fs ( id, parent_id, name, size, mode, uid, gid, ctime, mtime, atime ) VALUES( 3, 0, 'Сотрудники', 0, 16895, 0, 0, localtimestamp, localtimestamp, localtimestamp );
ALTER SEQUENCE dir_fs_id_seq INCREMENT BY -1 RESTART WITH 9223372036854775807;
