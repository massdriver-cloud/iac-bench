-- Run once against database_name as dbadmin, inside the VPC, with:
-- psql "$ADMIN_CONNECTION" -v ON_ERROR_STOP=1 -v app_user=checkout_app -f bootstrap.sql
-- Use the exact application_db_user value; do not give the service the admin secret.
-- Changes replicate to the secondary through Aurora Global Database.
BEGIN;
SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
GRANT rds_iam TO :"app_user";
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CONNECT, TEMPORARY ON DATABASE :"DBNAME" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"DBNAME" TO :"app_user";
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION dbadmin;
GRANT USAGE ON SCHEMA app TO :"app_user";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO :"app_user";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO :"app_user";
SELECT format('ALTER ROLE %I SET search_path = app, pg_catalog', :'app_user')
\gexec
COMMIT;
-- Run schema migrations with a separately authorized migration identity; the
-- application intentionally cannot CREATE/ALTER/DROP schema objects. If a
-- different migration owner creates objects, set its default privileges too.
