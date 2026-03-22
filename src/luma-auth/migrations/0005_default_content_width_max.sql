-- Change default content_width from 'wide' to 'max' for new instances,
-- and update any existing instances that still have the old default.
ALTER TABLE auth.instance ALTER COLUMN content_width SET DEFAULT 'max';
UPDATE auth.instance SET content_width = 'max' WHERE content_width = 'wide';
