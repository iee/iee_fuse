CREATE OR REPLACE FUNCTION func_get_tree_dir_sddl(root_folder_id bigint) RETURNS TABLE (
  id   bigint,
  sddl text,
  tree_leaf boolean) 
AS $function$
BEGIN
	RETURN QUERY
	WITH RECURSIVE dr(id, sddl, tree_leaf) AS (
	  SELECT l.id, l.sddl, l.tree_leaf
	   FROM dir_sddl l
	   WHERE parent_id = root_folder_id 
	 UNION ALL
	  SELECT c.id, c.sddl, c.tree_leaf
	   FROM dr d JOIN dir_sddl c ON c.parent_id = d.id 
	)
	SELECT * FROM dr;
END;
$function$ LANGUAGE plpgsql;
CREATE OR REPLACE VIEW dir_sddl AS (SELECT DISTINCT ON (id) 33401::BIGINT AS id, 33195::BIGINT AS parent_id, 'O:SYG:S-1-5-21-3874029520-2253553080-878871061-1118D:AI(A;OICIID;0x001f01ff;;;SY)(A;OICIID;0x001200a9;;;S-1-5-21-3874029520-2253553080-878871061-1118)'::TEXT AS sddl, 'True'::boolean  AS 
tree_leaf FROM dir_fs);

CREATE OR REPLACE FUNCTION func_update_child_ntacl(root_folder_id bigint, sd_sub_folder bytea, sd_file bytea) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	INSERT INTO xattr (dir_id, name, val)
	SELECT d.id, 'security.NTACL', sd_sub_folder FROM d WHERE d.mode & 61440 = 16384
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_sub_folder;


	WITH RECURSIVE d AS (
	SELECT id,mode
	FROM dir
	WHERE parent_id = root_folder_id 
	UNION ALL
	SELECT c.id,c.mode
	FROM d JOIN dir c ON c.parent_id = d.id
	)
	INSERT INTO xattr (dir_id, name, val)
	SELECT d.id, 'security.NTACL', sd_file FROM d WHERE d.mode & 61440 = 32768
	ON CONFLICT (dir_id, name)
	DO UPDATE SET
	val = sd_file;

END;
$function$;
