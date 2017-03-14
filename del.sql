ALTER TABLE dlfileentry ADD  del INTEGER;
ALTER TABLE dlfileentry ALTER del SET DEFAULT 0;
UPDATE dlfileentry SET del = 0;
DROP VIEW dir;
CREATE VIEW dir AS (
(SELECT DISTINCT ON (o.groupid) o.groupid::BIGINT AS id, 0::BIGINT AS parent_id, CAST( o.groupid AS TEXT ) AS name, o.size_ AS size, o.mode AS mode, o.uid::INTEGER AS  uid, o.gid::INTEGER AS gid, o.createdate AS ctime, o.modifieddate AS mtime, o.accessdate AS atime FROM dlfolder o WHERE o.name NOT LIKE '/%') UNION
(SELECT d.folderid AS id, CASE WHEN (d.parentfolderid = 0) THEN d.groupid ELSE d.parentfolderid END AS parent_id, d.name AS name, d.size_ AS size, d.mode AS mode, d.uid::INTEGER AS  uid, d.gid::INTEGER AS gid, d.createdate AS ctime, d.modifieddate AS mtime, d.accessdate AS atime FROM dlfolder d WHERE d.name NOT LIKE '/%') UNION
(SELECT f.fileentryid AS id, CASE WHEN (f.folderid = 0) THEN f.groupid ELSE f.folderid END AS parent_id, f.title AS name, f.size_ AS size, f.mode AS mode, f.uid::INTEGER AS  uid, f.gid::INTEGER AS gid, f.createdate AS ctime, f.modifieddate  AS mtime, f.accessdate  AS atime FROM dlfileentry f WHERE f.title NOT LIKE '/%' AND f.del = 0) UNION
(SELECT l.id AS id, l.parent_id AS parent_id, l.name AS name, l.size AS size, l.mode AS mode, l.uid::INTEGER AS uid, l.gid::INTEGER AS gid, l.ctime AS ctime, l.mtime  AS mtime, l.atime  AS atime FROM dir_fs l));
