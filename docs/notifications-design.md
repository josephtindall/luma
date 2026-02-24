# Notifications — Design Document

## Overview

The notification system is the event layer that connects all of Luma and Haven into a coherent signal for users. Notifications are extensive by default and highly configurable — every event type can be toggled at the server level and at the per-user level, across two delivery channels: in-app (real-time via WebSocket) and email.

---

## Architecture

```
Event occurs (e.g. task status changed)
    │
    ▼
Service writes to luma.notification_events table
    │
    ▼
Notification dispatcher reads queue (Redis pub/sub)
    │
    ├──► In-app: push to WebSocket connections for online users
    │
    └──► Email: push to email queue → email delivery worker → SMTP
```

The dispatcher is a background goroutine within the Luma process. It does not require a separate service.

---

## Event Types

### Haven Events (Login & Security)

| Event | Default: Email | Default: In-App |
|-------|---------------|-----------------|
| Login from new device | ✅ | ✅ |
| Session revoked (by someone else) | ✅ | ✅ |
| Account locked | ✅ | ✅ |
| Password changed | ✅ | ✅ |
| Invitation accepted (notifies inviter) | ❌ | ✅ |

### Pages Events

| Event | Default: Email | Default: In-App |
|-------|---------------|-----------------|
| Page edited (watching) | ❌ | ✅ |
| Page mentioned me | ✅ | ✅ |
| Page comment added (watching) | ❌ | ✅ |
| Page shared with me | ❌ | ✅ |
| Page archived (watching) | ❌ | ✅ |

### Tasks Events

| Event | Default: Email | Default: In-App |
|-------|---------------|-----------------|
| Task assigned to me | ✅ | ✅ |
| Task status changed (assigned or watching) | ❌ | ✅ |
| Task commented (assigned or watching) | ❌ | ✅ |
| Task mentioned me | ✅ | ✅ |
| Task due date approaching (assigned, 24h) | ✅ | ✅ |
| Task overdue (assigned) | ✅ | ✅ |
| Task archived (assigned or watching) | ❌ | ✅ |

### Flows Events

| Event | Default: Email | Default: In-App |
|-------|---------------|-----------------|
| Flow published (watching vault) | ❌ | ✅ |
| Flow mentioned me | ✅ | ✅ |
| Flow execution completed (author) | ❌ | ✅ |
| Flow archived (watching) | ❌ | ✅ |

---

## "Watching" Concept

Users automatically watch content they create or are assigned to. Manual watching is available for any Page, Task, or Flow via a watch/unwatch toggle in the item menu. Watching state stored per user per resource.

```sql
CREATE TABLE luma.watches (
    user_id       TEXT        NOT NULL,
    resource_type TEXT        NOT NULL,  -- page | task | flow | vault
    resource_id   TEXT        NOT NULL,  -- short ID or vault UUID
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, resource_type, resource_id)
);
```

Watching a Vault watches all current and future content within it.

---

## Server-Level Configuration

Instance Owner can toggle event categories on/off for the entire instance. Disabled event categories produce no notifications for any user regardless of personal preferences.

```sql
-- Stored in haven.instance.features JSONB
{
  "notifications": {
    "pages_events":  true,
    "tasks_events":  true,
    "flows_events":  true,
    "email_enabled": false   -- false until SMTP configured
  }
}
```

Email notifications are globally disabled until SMTP settings are configured in the Admin panel. The admin panel shows a banner: "Email notifications are disabled — configure SMTP to enable them."

---

## Per-User Preferences

Each user can configure which events they receive and via which channel. Preferences are stored as a JSONB map of event type to channel settings.

```sql
CREATE TABLE luma.notification_preferences (
    user_id     TEXT    PRIMARY KEY,
    preferences JSONB   NOT NULL DEFAULT '{}',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

```json
{
  "task_assigned":          { "in_app": true,  "email": true  },
  "task_mentioned":         { "in_app": true,  "email": true  },
  "task_status_changed":    { "in_app": true,  "email": false },
  "page_mentioned":         { "in_app": true,  "email": true  },
  "page_edited":            { "in_app": false, "email": false },
  "login_new_device":       { "in_app": true,  "email": true  }
}
```

Missing keys inherit the default for that event type. Users cannot enable event types that are disabled at the server level.

---

## Database Schema

```sql
CREATE TABLE luma.notifications (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       TEXT        NOT NULL,          -- recipient
    event_type    TEXT        NOT NULL,
    title         TEXT        NOT NULL,           -- "Ann commented on Emergency Contacts"
    body          TEXT,                           -- optional longer description
    resource_type TEXT,                           -- page | task | flow
    resource_id   TEXT,                           -- short ID
    resource_url  TEXT,                           -- /p/TIvsUANKJC
    actor_id      TEXT,                           -- Haven user UUID of who caused the event
    is_read       BOOLEAN     NOT NULL DEFAULT false,
    read_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notifications_user     ON luma.notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread   ON luma.notifications(user_id, is_read)
    WHERE is_read = false;
```

---

## In-App Delivery

### WebSocket

Users with an open Luma session receive notifications in real-time via WebSocket. The connection is established at login and maintained while the app is open.

```
Client connects: ws://luma.local/ws
Haven token passed as query param: ?token=<access_token>
Haven validates token — rejects if invalid or expired

Server sends notification frame:
{
  "type": "notification",
  "id": "uuid",
  "eventType": "task_assigned",
  "title": "J assigned you to Fix the garage door task",
  "resourceUrl": "/t/Rk2mBNwQpL",
  "createdAt": "2025-03-15T14:30:00Z"
}
```

### Notification Bell

Notification bell icon in the app header. Shows unread count badge (capped at display of "99+" beyond 99). Clicking opens the notification center panel.

### Notification Center

Slide-in panel from the right. Shows the last 50 notifications grouped by date (Today, Yesterday, Earlier). Each notification shows: actor avatar, event description, resource title (linked), relative time, read/unread indicator. "Mark all as read" button at the top.

### Badge Count

Unread count is fetched on app load and updated via WebSocket events. Badge disappears when count reaches zero.

---

## Email Delivery

### SMTP Configuration

Configured by Owner in Admin panel → Instance Settings → Email:

```
SMTP Host:     smtp.example.com
SMTP Port:     587
SMTP User:     notifications@example.com
SMTP Password: ***
From Name:     Luma Notifications
From Address:  notifications@example.com
```

Test email button sends a test message to the Owner's address before saving.

### Email Format

Plain text + HTML multipart. Subject line format: `[Luma] J assigned you to "Fix the garage door"`

Body includes:
- What happened (one sentence)
- Link to the resource
- "View in Luma →" button
- Footer: "You're receiving this because you have email notifications enabled. Manage preferences →"

### Digest vs Immediate

Phase 1: all email notifications are immediate (one email per event). Digest mode (daily summary) is a future enhancement. The `notification_preferences` schema supports a `digest` channel option for future use.

---

## Notification API Endpoints

```
GET    /api/luma/notifications              list notifications (paginated)
GET    /api/luma/notifications/unread-count unread count only
PATCH  /api/luma/notifications/{id}/read   mark one as read
POST   /api/luma/notifications/read-all    mark all as read
DELETE /api/luma/notifications/{id}        dismiss notification

GET    /api/luma/notifications/preferences         get user preferences
PATCH  /api/luma/notifications/preferences         update user preferences

GET    /api/luma/watches                           list what user is watching
POST   /api/luma/watches                           watch a resource
DELETE /api/luma/watches/{resourceType}/{id}       unwatch a resource

GET    /api/luma/admin/notifications/settings      get server-level settings (owner only)
PATCH  /api/luma/admin/notifications/settings      update server settings (owner only)
POST   /api/luma/admin/notifications/test-email    send test email (owner only)
```
