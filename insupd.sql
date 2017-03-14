CREATE OR REPLACE FUNCTION func_insupd_ntacl(id_dir bigint, data_val bytea) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
INSERT INTO xattr (dir_id, name, val)
VALUES (id_dir, 'security.NTACL', data_val)
ON CONFLICT (dir_id, name)
DO UPDATE SET
val = data_val ;
END;
$function$;