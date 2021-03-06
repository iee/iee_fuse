DROP TRIGGER dir_trig ON dir;
DROP TRIGGER set_dlfolder_uid_gid_trig ON dlfolder;
DROP TRIGGER set_dlfileentry_uid_gid_trig ON dlfileentry;
DROP TRIGGER user_trig ON user_;
DROP FUNCTION IF EXISTS dir_update();
DROP FUNCTION IF EXISTS get_uid(VARCHAR);
DROP FUNCTION IF EXISTS get_gid(VARCHAR);
DROP FUNCTION IF EXISTS get_sid(VARCHAR);
DROP FUNCTION IF EXISTS set_uid_gid();
DROP FUNCTION IF EXISTS get_screenname(INTEGER);
DROP VIEW dir;
DROP TABLE data;
DROP TABLE xattr;
DROP TABLE dir_fs;
ALTER TABLE dlfileentry DROP IF EXISTS accessdate;
ALTER TABLE dlfolder DROP IF EXISTS accessdate;
ALTER TABLE dlfileentry DROP IF EXISTS mode;
ALTER TABLE dlfolder DROP IF EXISTS mode;
ALTER TABLE dlfolder DROP IF EXISTS size_;
ALTER TABLE dlfolder DROP IF EXISTS uid;
ALTER TABLE dlfolder DROP IF EXISTS gid;
ALTER TABLE dlfileentry DROP IF EXISTS uid;
ALTER TABLE dlfileentry DROP IF EXISTS del;
ALTER TABLE dlfileentry DROP IF EXISTS gid;
ALTER TABLE user_ DROP IF EXISTS sid;
DELETE FROM dlfolder;
DELETE FROM dlfileentry;
DELETE FROM dlcontent;
DELETE FROM dlfileentrymetadata;
DELETE FROM dlfileentrytypes_ddmstructures;
DELETE FROM dlfileentrytypes_dlfolders;
DELETE FROM dlfilerank;
DELETE FROM dlfileshortcut;
DELETE FROM dlfileversion;
DELETE FROM dlsyncevent;
