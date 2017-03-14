DROP TRIGGER dir_trig ON dir;
DROP FUNCTION IF EXISTS dir_update();
DROP FUNCTION IF EXISTS get_screenname(INTEGER);
DROP VIEW dir;
CREATE FUNCTION get_screenname(INTEGER) RETURNS TEXT
AS 'libgetuid', 'get_screenname'
LANGUAGE C STRICT;
CREATE VIEW dir AS (
(SELECT DISTINCT ON (o.groupid) o.groupid::BIGINT AS id, 0::BIGINT AS parent_id, CAST( o.groupid AS TEXT ) AS name, o.size_ AS size, o.mode AS mode, o.uid::INTEGER AS  uid, o.gid::INTEGER AS gid, o.createdate AS ctime, o.modifieddate AS mtime, o.accessdate AS atime FROM dlfolder o WHERE o.name NOT LIKE '/%') UNION
(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.name NOT LIKE '/%') UNION
--(SELECT 0 AS id, 0 AS parent_id, '/' AS name, 0 AS size, 16895 AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW() AS ctime, NOW( ) AS mtime, NOW( ) AS atime ) UNION
(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, f.title AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.title NOT LIKE '/%') UNION
(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS  uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));
CREATE OR REPLACE FUNCTION dir_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
   DECLARE
   scr VARCHAR (75);
   usid INTEGER;
   lname VARCHAR (75);
   fname VARCHAR (75);
   BEGIN
	IF TG_OP = 'UPDATE' THEN
	scr = get_screenname(NEW.uid);
	SELECT u.userid, u.lastname, u.firstname INTO usid, lname, fname  FROM user_ u WHERE u.screenname=scr;
	UPDATE dlfolder SET userid=usid, username=fname || ' ' || lname, size_=NEW.size, mode=NEW.mode, uid=NEW.uid, gid=NEW.gid, createdate=NEW.ctime, modifieddate=NEW.mtime, accessdate=NEW.atime WHERE folderid=OLD.id;
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
CREATE TRIGGER dir_trig INSTEAD OF INSERT OR UPDATE OR DELETE ON dir FOR EACH ROW EXECUTE PROCEDURE dir_update();
