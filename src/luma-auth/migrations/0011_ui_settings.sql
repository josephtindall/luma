ALTER TABLE auth.instance
    ADD COLUMN IF NOT EXISTS show_github_button BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS show_donate_button BOOLEAN NOT NULL DEFAULT true;
