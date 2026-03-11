# Pages — Feature Design Document

## What Pages Are

Pages are the primary long-form document format in Luma. They use a block-based editor where every paragraph, heading, image, and layout element is an independent block that can be dragged, reordered, and individually formatted. Pages support live inline transclusion of other Pages, Markdown-style input shortcuts, column layouts, and automatic revision history.

---

## Editor — appflowy_editor

The editor is implemented using `appflowy_editor` across all platforms (web, Android, iOS). The same editor component is used for Pages, Task descriptions, and Flow step content. Custom block types are registered once in `pkg/editor/blocks.dart` and available everywhere.

### Markdown Input Shortcuts

Typed shortcuts convert inline as the user types:

| Input | Result |
|-------|--------|
| `# ` (space after #) | Heading 1 |
| `## ` | Heading 2 |
| `### ` | Heading 3 |
| `#### ` | Heading 4 |
| `**text**` | Bold |
| `*text*` | Italic |
| `~~text~~` | Strikethrough |
| `` `text` `` | Inline code |
| `---` on empty line | Divider block |
| `- ` or `* ` | Bullet list item |
| `1. ` | Numbered list item |
| `> ` | Blockquote |
| ` ``` ` on empty line | Code block |
| `[ ]` | Unchecked checkbox |
| `[x]` | Checked checkbox |

### Copy/Paste Markdown Export

Copying any selection of blocks to the clipboard produces both:
- **Rich format** (for pasting back into Luma or other block editors)
- **Plain Markdown** (for pasting into any text editor, VS Code, GitHub, etc.)

The Markdown output is clean and standard — no custom syntax, no HTML fragments.

---

## Block Types

All block types are registered in `pkg/editor/blocks.dart` and available in Pages, Task descriptions, and Flow step content.

### Standard Blocks

| Block Type | Description |
|------------|-------------|
| `paragraph` | Default text block |
| `heading` | H1 through H4 |
| `bullet_list_item` | Unordered list item, nestable |
| `numbered_list_item` | Ordered list item, nestable |
| `checkbox` | Checklist item with checked/unchecked state |
| `blockquote` | Indented quoted text |
| `code` | Code block with syntax highlighting, language selector |
| `divider` | Horizontal rule |
| `callout` | Highlighted box with icon — info, warning, danger, tip |
| `image` | Uploaded or linked image with optional caption |

### Layout Blocks

Column layout blocks contain child block slots. Content is dragged into column slots.

| Block Type | Variants |
|------------|---------|
| `columns_2` | Equal (50/50), Left-heavy (66/34), Right-heavy (34/66) |
| `columns_3` | Equal (33/33/33), Left-heavy (50/25/25), Center-heavy (25/50/25), Right-heavy (25/25/50) |
| `columns_4` | Equal only (25/25/25/25) |
| `columns_5` | Equal only (20/20/20/20/20) |

Column variant is selectable via a toolbar that appears when the layout block is focused. Columns collapse to single-column stacked on mobile.

### Special Blocks

| Block Type | Description |
|------------|-------------|
| `transclusion` | Live embedded content from another Page — see Transclusion section |
| `mention` | Inline reference to a Page, Task, Flow, or User — see `mentions-design.md` |

---

## Transclusion

Transclusion allows embedding the live content of another Page inside the current Page. The embedded content renders fully inline and stays in sync — when the source Page is edited, all transclusions of it update on next render without any action from the reader.

### How It Works

```
Page A contains: [transclusion block → Page B short ID]
Page B is the source of truth

When Page A is rendered:
1. Renderer encounters transclusion block with shortId "XkBm9cPqTs"
2. Fetches current block content of Page B from luma.pages
3. Renders Page B's blocks inline within Page A
4. Marks the embedded section visually as transcluded (subtle border, source link)
```

### Inserting a Transclusion

Two methods:
- Type `/transclude` in an empty block to open a Page search picker
- Use the `@` mention system and select a Page — a prompt appears: "Insert as mention or embed?" Selecting embed creates a transclusion block

### Transclusion Block Storage

```json
{
  "type": "transclusion",
  "attrs": {
    "sourcePageShortId": "XkBm9cPqTs",
    "sourcePageTitle":   "Sign-in Instructions",
    "insertedAt":        "2025-03-01T10:00:00Z"
  }
}
```

The title is stored as a snapshot for rendering when the source is unavailable. Live content always fetched from the source at render time.

### Circular Transclusion Prevention

Before inserting a transclusion, the server checks for cycles:

```
Page A transcluding Page B:
1. Get all pages that Page B transcludesahead (recursively, max depth 10)
2. If Page A appears in that set: reject with error "Circular transclusion detected"
3. If depth exceeds 10: reject with error "Transclusion depth limit reached"
```

The check is performed server-side on save — the client shows the error inline.

### What Happens When Source Page Is Archived

The transclusion block renders as: *"[Sign-in Instructions — this page has been archived]"* with a link to the archived page for users with permission to view it. The transclusion block itself is not removed from the containing page.

---

## Auto-Save

Pages auto-save while the user is editing. Save behavior:

- Debounced: 2 seconds after the last keystroke
- Immediate save on: navigating away, closing tab, explicit Cmd+S / Ctrl+S
- Save indicator in the header: "Saving..." → "Saved" → timestamp of last save
- Offline: changes queued locally in SQLite, synced to server when connectivity returns
- Conflict resolution: last-write-wins per block (not per page) — two users editing different blocks simultaneously do not conflict

---

## Revision History

### Snapshot Policy

Hourly snapshots taken automatically — but only when changes have been made since the last snapshot. No change = no snapshot created. Manual snapshots can be created at any time via "Save version" in the page menu.

### Retention Policy (Default — Configurable in Admin UI)

| Period | What Is Kept |
|--------|-------------|
| Current month | All hourly snapshots |
| Previous months | One snapshot per month (the last one of each month) |
| All time | The first snapshot ever created for the page is never deleted |

Admin UI exposes:
- "Keep all revisions for:" 30 / 60 / 90 days (dropdown)
- "After that, keep:" one per day / one per week / one per month (dropdown)

A nightly cleanup job applies the retention policy. It never deletes the oldest surviving snapshot for any document.

### Revision Schema

```sql
CREATE TABLE luma.page_revisions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id     UUID        NOT NULL REFERENCES luma.pages(id) ON DELETE CASCADE,
    content     JSONB       NOT NULL,      -- full block tree snapshot
    created_by  TEXT        NOT NULL,      -- luma-auth user UUID
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_manual   BOOLEAN     NOT NULL DEFAULT false,  -- true = user-triggered
    label       TEXT                                  -- optional user label for manual saves
);
CREATE INDEX idx_revisions_page ON luma.page_revisions(page_id, created_at DESC);
```

### Revision UI

Accessed via "Page history" in the page menu. Shows a timeline list of snapshots with author, timestamp, and label (if manual). Clicking a revision shows a side-by-side diff against the current version. Restore button creates a new revision with the old content rather than overwriting history.

---

## Database Schema

```sql
CREATE TABLE luma.pages (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    short_id     TEXT        NOT NULL UNIQUE,
    vault_id     UUID        NOT NULL REFERENCES luma.vaults(id),
    title        TEXT        NOT NULL DEFAULT 'Untitled',
    content      JSONB       NOT NULL DEFAULT '{"blocks": []}',
    created_by   TEXT        NOT NULL,      -- luma-auth user UUID
    updated_by   TEXT        NOT NULL,
    is_archived  BOOLEAN     NOT NULL DEFAULT false,
    archived_at  TIMESTAMPTZ,
    archived_by  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pages_vault    ON luma.pages(vault_id);
CREATE INDEX idx_pages_short_id ON luma.pages(short_id);
CREATE INDEX idx_pages_title    ON luma.pages USING gin(to_tsvector('english', title));
CREATE INDEX idx_pages_content  ON luma.pages USING gin(content);
```

---

## API Endpoints

```
GET    /api/luma/pages                   list pages (filterable by vault)
POST   /api/luma/pages                   create page
GET    /api/luma/pages/{shortId}         get page with current content
PUT    /api/luma/pages/{shortId}         replace full content (auto-save)
PATCH  /api/luma/pages/{shortId}         update title or metadata only
DELETE /api/luma/pages/{shortId}         archive page

GET    /api/luma/pages/{shortId}/revisions          list revision history
GET    /api/luma/pages/{shortId}/revisions/{revId}  get specific revision
POST   /api/luma/pages/{shortId}/revisions          create manual snapshot
POST   /api/luma/pages/{shortId}/revisions/{revId}/restore   restore revision

GET    /api/luma/pages/{shortId}/transclusions      list pages that transclude this page
```

---

## Audit Events

| Event | Trigger |
|-------|---------|
| `page_created` | New page created |
| `page_updated` | Content saved |
| `page_archived` | Page archived |
| `page_restored` | Archived page restored |
| `page_revision_created` | Manual snapshot saved |
| `page_revision_restored` | Content rolled back to a revision |
| `page_transcluded` | This page was embedded in another |
