ALTER TABLE user_ DROP IF EXISTS uid;
DROP FUNCTION IF EXISTS get_uid_from_sid();
DROP FUNCTION IF EXISTS set_sid();
DROP TRIGGER user_trig ON user_;
ALTER TABLE dlfileentry ALTER COLUMN uid SET DEFAULT 0;
ALTER TABLE dlfileentry ALTER COLUMN gid SET DEFAULT 0;
ALTER TABLE dlfolder ALTER COLUMN uid SET DEFAULT 0;
ALTER TABLE dlfolder ALTER COLUMN gid SET DEFAULT 0;
ALTER TABLE user_ ADD uid INTEGER;
ALTER TABLE user_ ALTER uid SET DEFAULT 0;
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
CREATE TRIGGER user_trig BEFORE INSERT ON user_ FOR EACH ROW EXECUTE PROCEDURE set_sid_uid();
CREATE OR REPLACE FUNCTION copy_xattr_from_to(from_id bigint, to_id bigint) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO xattr( dir_id, name, val ) VALUES ( to_id, 'security.NTACL', (SELECT val FROM xattr WHERE dir_id = from_id AND name = 'security.NTACL'));
END;
$function$;