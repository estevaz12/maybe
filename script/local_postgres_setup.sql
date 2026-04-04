-- Idempotent setup for local development (matches default .env POSTGRES_*).
--
-- `sudo -u postgres psql -f /path/in/your/home` often fails with "Permission denied"
-- because the postgres user cannot read files under your home directory. Use either:
--
--   cat script/local_postgres_setup.sql | sudo -u postgres psql -d postgres
--
-- Or copy to /tmp first:
--
--   cp script/local_postgres_setup.sql /tmp/ && sudo -u postgres psql -d postgres -f /tmp/local_postgres_setup.sql
--
-- Then: bin/rails db:prepare

DO
$body$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'maybe_user') THEN
    CREATE ROLE maybe_user LOGIN PASSWORD 'maybe_password' CREATEDB;
  ELSE
    ALTER ROLE maybe_user WITH LOGIN PASSWORD 'maybe_password' CREATEDB;
  END IF;
END
$body$;
