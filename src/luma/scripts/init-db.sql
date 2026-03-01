-- Create the luma schema and restrict the luma_user to it.
-- The auth service has its own database/user — no cross-schema access.
CREATE SCHEMA IF NOT EXISTS luma;
GRANT ALL ON SCHEMA luma TO luma_user;
ALTER ROLE luma_user SET search_path TO luma;

-- Create the auth service's database and user so both services share one Postgres instance.
CREATE USER auth_app WITH PASSWORD 'devpass';
CREATE DATABASE auth OWNER auth_app;
GRANT ALL PRIVILEGES ON DATABASE auth TO auth_app;
