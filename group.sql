CREATE OR REPLACE VIEW dir AS (
(SELECT o.groupid::BIGINT AS id, CASE WHEN (o.parentgroupid = 0 AND classnameid = 20005) THEN 3 WHEN (o.parentgroupid = 0 AND classnameid = 20003) THEN 2 WHEN (o.parentgroupid = 0 AND classnameid = 20001) THEN 1 ELSE o.parentgroupid END AS parent_id, group_descriptive_name(o.groupid) AS name, 0::BIGINT AS size, 16895::INTEGER AS mode, 0::INTEGER AS  uid, 0::INTEGER AS gid, NOW()::TIMESTAMP AS ctime, NOW()::TIMESTAMP AS mtime, NOW()::TIMESTAMP AS atime FROM group_ o WHERE classnameid in (select classnameid from classname_ WHERE value in ('com.liferay.portal.model.Group','com.liferay.portal.model.User','com.liferay.portal.model.Organization')) and trim(group_descriptive_name(o.groupid)) != '') UNION
(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.name NOT LIKE '/%') UNION
(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, f.title AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.title NOT LIKE '/%' AND f.del = 0) UNION
(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));
CREATE OR REPLACE FUNCTION group_descriptive_name(BIGINT) RETURNS text 
LANGUAGE plpgsql
AS $function$
DECLARE
	classname VARCHAR(75);
	classpk2 BIGINT;
BEGIN
	select c.value, g.classpk INTO classname, classpk2 from group_ g,classname_ c where g.classnameid=c.classnameid and groupid=$1;
	IF classname = 'com.liferay.portal.model.Group' THEN
		return (select data_ from expandovalue where columnid=(select columnid from expandocolumn where name='GROUP_SHORT_NAME')
		and columnid=(select columnid from classname_ where value='com.liferay.portal.model.Group') and classpk=$1);
	ELSEIF classname = 'com.liferay.portal.model.User' THEN
		return (select  lastname|| ' ' || firstname from user_ where userid=classpk2);
	ELSEIF classname = 'com.liferay.portal.model.Organization' THEN
		return (select name from organization_ where organizationid=classpk2);
	ELSE 
		return CAST( $1 AS TEXT );
	END IF;
END;
$function$;