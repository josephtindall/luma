ALTER TABLE auth.instance ALTER COLUMN content_width SET DEFAULT 'wide';
UPDATE auth.instance SET content_width = 'wide' WHERE content_width = 'max';
