# Tasks — Feature Design Document

## What Tasks Are

Tasks are the action-tracking layer of Luma. A Task has a lifecycle (Status), a rich description, a threaded comment feed for updates, and automatic age tracking. Tasks can reference Pages and Flows, and can be mentioned in any editor context. They are simple enough to use as a household to-do list and structured enough to run a team's work queue.

---

## Task Anatomy

| Field | Type | Notes |
|-------|------|-------|
| Title | Text | Required. Short, action-oriented. 1–256 chars. |
| Status | Enum | Configurable per instance — see Status section |
| Description | Block content | Full block editor (same as Pages). Supports mentions, links, column layouts. |
| Assignee | User (optional) | Single user from instance members |
| Due Date | Date (optional) | Date only, no time component |
| Vault | Vault | Required. Set at creation, displayed in breadcrumb. |
| Comments | Threaded | Ordered chronologically, each comment is a block editor instance |
| Age | Computed | Time since `created_at`. Time since `updated_at`. Both displayed. |

---

## Status

Statuses are configurable at the instance level by the Owner. A set of default statuses is seeded on first run. Each status has a name, a color, and a category that drives sort order and completion logic.

### Default Statuses

| Name | Color | Category |
|------|-------|---------|
| Open | Blue | `active` |
| In Progress | Amber | `active` |
| Blocked | Red | `active` |
| Done | Green | `done` |
| Cancelled | Grey | `cancelled` |

### Status Categories

| Category | Behavior |
|----------|---------|
| `active` | Task is ongoing. Appears in default task views. |
| `done` | Task is complete. Hidden from default view, visible in "Completed" filter. `closed_at` set on transition. |
| `cancelled` | Task will not be completed. Hidden from default view. `closed_at` set on transition. |

### Status Configuration

Admin UI (instance Owner only) allows:
- Adding new statuses with custom name and color
- Assigning a category to each status
- Reordering statuses (affects display order in filters)
- Renaming existing statuses (existing tasks update automatically)
- Deleting a status only if no tasks currently use it

```sql
CREATE TABLE luma.task_statuses (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL,
    color      TEXT        NOT NULL DEFAULT '#6B7280',
    category   TEXT        NOT NULL DEFAULT 'active',
    position   INTEGER     NOT NULL DEFAULT 0,
    is_default BOOLEAN     NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT category_values CHECK (category IN ('active', 'done', 'cancelled'))
);
```

---

## Age Tracking

Age is computed from two timestamps and displayed as a human-readable duration:

- **Age:** Time since `created_at` — "3 days", "2 weeks", "4 months"
- **Idle:** Time since `updated_at` — "Last updated 5 hours ago"

Both shown on the task card in list/board views and in the task detail header. Color coding:

| Idle Duration | Color |
|---------------|-------|
| < 3 days | Default |
| 3–7 days | Amber |
| > 7 days | Red |

This makes neglected tasks visually prominent without requiring any configuration.

---

## Comments

Comments are the update feed for a task. Each comment is a block editor instance — supporting rich text, mentions, links, and inline code. Comments are append-only: editing is allowed within 5 minutes of posting, deletion requires Vault Admin permission.

```sql
CREATE TABLE luma.task_comments (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id      UUID        NOT NULL REFERENCES luma.tasks(id) ON DELETE CASCADE,
    author_id    TEXT        NOT NULL,  -- luma-auth user UUID
    content      JSONB       NOT NULL,
    is_edited    BOOLEAN     NOT NULL DEFAULT false,
    edited_at    TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_task_comments_task ON luma.task_comments(task_id, created_at ASC);
```

---

## Database Schema

```sql
CREATE TABLE luma.tasks (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    short_id     TEXT        NOT NULL UNIQUE,
    vault_id     UUID        NOT NULL REFERENCES luma.vaults(id),
    title        TEXT        NOT NULL,
    status_id    UUID        NOT NULL REFERENCES luma.task_statuses(id),
    description  JSONB       NOT NULL DEFAULT '{"blocks": []}',
    assignee_id  TEXT,                   -- luma-auth user UUID, nullable
    due_date     DATE,
    closed_at    TIMESTAMPTZ,
    created_by   TEXT        NOT NULL,   -- luma-auth user UUID
    updated_by   TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tasks_vault      ON luma.tasks(vault_id);
CREATE INDEX idx_tasks_status     ON luma.tasks(status_id);
CREATE INDEX idx_tasks_assignee   ON luma.tasks(assignee_id);
CREATE INDEX idx_tasks_due        ON luma.tasks(due_date) WHERE due_date IS NOT NULL;
CREATE INDEX idx_tasks_short_id   ON luma.tasks(short_id);
CREATE INDEX idx_tasks_title      ON luma.tasks USING gin(to_tsvector('english', title));
```

---

## Task Views

### List View

Default view. One row per task. Columns: Status badge, Title, Assignee avatar, Due date (amber if < 3 days, red if overdue), Age, Idle time. Sortable by any column. Filterable by Status, Assignee, Vault, Due date range.

### Board View

Kanban-style columns, one per Status. Task cards show title, assignee avatar, due date, and idle indicator. Cards are draggable between columns — dragging to a new column updates the Status. Within a column, cards ordered by due date ascending then created_at ascending.

### My Tasks View

Cross-vault view of all tasks assigned to the current user. Grouped by Status category: Active (all active statuses together) then Done (last 7 days). Default sort: overdue first, then by due date ascending, then by oldest created.

---

## API Endpoints

```
GET    /api/luma/tasks                      list tasks (filterable by vault, status, assignee)
POST   /api/luma/tasks                      create task
GET    /api/luma/tasks/{shortId}            get task with description and comments
PATCH  /api/luma/tasks/{shortId}            update title, status, assignee, due date, description
DELETE /api/luma/tasks/{shortId}            archive task

GET    /api/luma/tasks/{shortId}/comments   list comments
POST   /api/luma/tasks/{shortId}/comments   add comment
PATCH  /api/luma/tasks/{shortId}/comments/{id}   edit comment (within 5 min window)
DELETE /api/luma/tasks/{shortId}/comments/{id}   delete comment (vault admin only)

GET    /api/luma/tasks/mine                 tasks assigned to current user (cross-vault)

GET    /api/luma/task-statuses              list statuses
POST   /api/luma/task-statuses              create status (owner only)
PATCH  /api/luma/task-statuses/{id}         update status (owner only)
DELETE /api/luma/task-statuses/{id}         delete status (owner only, if unused)
```

---

## Audit Events

| Event | Trigger | Key Metadata |
|-------|---------|-------------|
| `task_created` | New task | `vault_id`, `title` |
| `task_status_changed` | Status transition | `from_status`, `to_status` |
| `task_assigned` | Assignee set or changed | `assigned_to`, `assigned_by` |
| `task_due_date_set` | Due date added or changed | `due_date` |
| `task_commented` | Comment added | `comment_id` |
| `task_comment_edited` | Comment edited | `comment_id` |
| `task_archived` | Task archived | |
| `task_closed` | Status moved to done/cancelled | `closed_at`, `status` |
