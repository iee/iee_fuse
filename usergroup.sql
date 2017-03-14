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
