-- Migration 0015: Add optional description field to groups and custom roles.

ALTER TABLE auth.groups ADD COLUMN description TEXT;
ALTER TABLE auth.custom_roles ADD COLUMN description TEXT;
