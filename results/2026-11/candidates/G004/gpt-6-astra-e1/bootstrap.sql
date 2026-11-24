-- Run once on the CURRENT WRITER from a trusted host inside its VPC, as dbadmin.
-- psql ... -v db_name=checkout -v app_user=checkout_app -f bootstrap.sql
-- Identifiers are quoted by psql/format, not interpolated as executable SQL.
\set ON_ERROR_STOP on
BEGIN;
SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
ALTER ROLE :"app_user" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
GRANT rds_iam TO :"app_user";
REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO :"app_user";
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION dbadmin;
GRANT USAGE ON SCHEMA app TO :"app_user";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO :"app_user";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO :"app_user";
ALTER ROLE :"app_user" IN DATABASE :"db_name" SET search_path = app, pg_catalog;
COMMIT;
-- The runtime identity intentionally cannot create schemas/tables, grant roles,
-- or read the administrator secret. Schema migrations are a privileged operation.
-- If a separate migration owner creates objects, configure that owner's default
-- privileges as above. Role creation and grants replicate to the DR cluster.
