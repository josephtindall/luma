-- Create the luma schema and restrict the luma_user to it.
-- Haven has its own database/user — no cross-schema access.
CREATE SCHEMA IF NOT EXISTS luma;
GRANT ALL ON SCHEMA luma TO luma_user;
ALTER ROLE luma_user SET search_path TO luma;

-- Create Haven's database and user so both services share one Postgres instance.
CREATE USER haven_app WITH PASSWORD 'devpass';
CREATE DATABASE haven OWNER haven_app;
GRANT ALL PRIVILEGES ON DATABASE haven TO haven_app;
