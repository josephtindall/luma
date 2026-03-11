-- Migration 0014: Remove the coarse group:manage and role:manage permissions.
-- These were replaced in 0013 by the granular group:* and role:* permissions.
-- This migration is a no-op if 0013 was applied cleanly before any data was
-- inserted with the coarse names.

DELETE FROM auth.custom_role_permissions
WHERE action IN ('group:manage', 'role:manage');
