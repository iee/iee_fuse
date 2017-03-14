ALTER TABLE dlfileentry DROP IF EXISTS last_event;
ALTER TABLE dir_fs ADD uuid VARCHAR ( 75 );
CREATE FUNCTION get_uuid() RETURNS TEXT
AS 'libgetuid', 'get_uuid'
LANGUAGE C STRICT;
CREATE OR REPLACE FUNCTION set_uuid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
	DECLARE
	uuid VARCHAR (75);
	BEGIN
	uuid = CAST ( get_uuid() AS VARCHAR (75) );
	NEW.uuid = uuid;
	RETURN NEW;
	END;
$function$;
CREATE TRIGGER set_uuid_trig BEFORE INSERT ON dir_fs FOR EACH ROW EXECUTE PROCEDURE set_uuid();

