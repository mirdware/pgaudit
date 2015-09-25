﻿CREATE SCHEMA IF NOT EXISTS pgaudit;

--@install
CREATE OR REPLACE FUNCTION pgaudit.trail(integer) RETURNS VOID
LANGUAGE plpgsql AS $install$
DECLARE
	session_value ALIAS FOR $1;
BEGIN
	PERFORM relname
	FROM pg_class
	WHERE relname = 'tbl_session'
	AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
		THEN pg_table_is_visible(oid) ELSE false END;

	IF not found THEN
		CREATE TEMPORARY TABLE tbl_session (name TEXT, value TEXT);
	ELSE
		DELETE FROM tbl_session WHERE name = 'log_id';
	END IF;

	INSERT INTO tbl_session VALUES ('log_id', session_value);
END
$install$;

--@table
CREATE OR REPLACE FUNCTION pgaudit.table(name, name) RETURNS VARCHAR
LANGUAGE plpgsql AS $audit_table$
DECLARE
	trigger_auditor TEXT;
	table_name ALIAS FOR $2;
	table_origin TEXT;
	schema_audit TEXT;
	table_log TEXT;
BEGIN
	table_origin := $1||'.'||$2;
	schema_audit := 'pgaudit';
	table_log := schema_audit||'.'||$1||'$'||$2;

	-- INSERTA LA TABLA PARA EL HISTÓRICO
	EXECUTE 'CREATE TABLE IF NOT EXISTS '||table_log||' ('||
			'id             serial NOT NULL'||
			',register_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp'||
			',user_db       TEXT NOT NULL DEFAULT USER'
			',log_id        bigint'||
			',comando       char(1) NOT NULL CHECK( comando IN (''I'', ''U'', ''D''))'||
			',old           '||table_origin||
			',new           '||table_origin||
			',CONSTRAINT    '||schema_audit||'_'||table_name||'_pk PRIMARY KEY (id))';

	trigger_auditor := $FUNCTION$
		CREATE OR REPLACE FUNCTION TG_TABLE_NAME_audit() RETURNS TRIGGER STRICT LANGUAGE plpgsql
		AS $PROC$
		DECLARE
			log_id BIGINT;
		BEGIN
			PERFORM relname
			FROM pg_class
			WHERE relname = 'tbl_session'
			AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
				THEN pg_table_is_visible(oid) ELSE false END;

			IF not found THEN
				log_id := NULL;
			ELSE
				log_id := (SELECT value FROM tbl_session WHERE name = 'log_id');
			END IF;

			IF TG_OP = 'INSERT' THEN
				INSERT INTO TG_TABLE_NAME (log_id, comando, new) VALUES (log_id, 'I', NEW);
			ELSIF (TG_OP = 'DELETE') THEN
				INSERT INTO TG_TABLE_NAME (log_id, comando, old) VALUES (log_id, 'D', OLD);
			ELSIF (TG_OP = 'UPDATE') THEN
				INSERT INTO TG_TABLE_NAME (log_id, comando, old, new) VALUES (log_id, 'U', OLD, NEW);
			END IF;

			RETURN NULL;
		END
		$PROC$;
	$FUNCTION$;

	trigger_auditor := replace(trigger_auditor, 'TG_TABLE_NAME', table_log);
	EXECUTE trigger_auditor;

	-- CREA EL TRIGGER SOBRE LA TABLA
	EXECUTE 'DROP TRIGGER IF EXISTS audit ON '||table_origin||';CREATE TRIGGER audit '||
		' AFTER INSERT OR UPDATE OR DELETE ON '||table_origin||
		' FOR EACH ROW EXECUTE PROCEDURE '||table_log||'_audit();';

	RETURN table_origin||' table being audited.';
END
$audit_table$;