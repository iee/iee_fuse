CREATE OR REPLACE FUNCTION get_uid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_uid'
LANGUAGE C STRICT;
CREATE OR REPLACE FUNCTION get_gid(VARCHAR) RETURNS INTEGER
AS 'libgetuid', 'get_gid'
LANGUAGE C STRICT;
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
CREATE TRIGGER set_dlfolder_uid_gid_trig BEFORE INSERT ON dlfolder FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();
CREATE TRIGGER set_dlfileentry_uid_gid_trig BEFORE INSERT ON dlfileentry FOR EACH ROW EXECUTE PROCEDURE set_uid_gid();
