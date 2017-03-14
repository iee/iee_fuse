CREATE FUNCTION get_sid(VARCHAR) RETURNS TEXT
AS 'libgetuid', 'get_sid'
CREATE OR REPLACE FUNCTION set_uuid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
	DECLARE
	scr VARCHAR (75);
	BEGIN
	scr = get_sid(NEW.screenname);
	IF scr = 'NO_SID' THEN
	RETURN NEW;
	ELSE
	NEW.uuid_ = scr;
	RETURN NEW;
	END IF;
	END;
$function$;
CREATE TRIGGER user_trig BEFORE INSERT ON user_ FOR EACH ROW EXECUTE PROCEDURE set_uuid();
--CREATE TRIGGER dir_trig INSTEAD OF UPDATE ON dir FOR EACH ROW EXECUTE PROCEDURE dir_update();
