// Package migrations embeds all SQL migration files so they are baked into
// the server binary and available without a filesystem at runtime.
package migrations

import "embed"

// FS contains every *.sql file in this directory, including .down.sql files.
// The migrate package reads from this FS directly.
//
//go:embed *.sql
var FS embed.FS
