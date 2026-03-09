# Flows — Feature Design Document

## What Flows Are

Flows are conditional branching playbooks. They guide a reader through a structured process where each Step contains rich content (using the same block editor as Pages) and zero or more exit paths leading to the next Step. A Step with no exits is the terminal point of a path through the Flow.

Flows are built last because they are a superset of everything that comes before them: they use the block editor from Pages, they support mentions from the mention system, they generate audit events, and they can link to Tasks. Build order: luma-auth → Vaults → Pages → Tasks → Flows.

---

## Core Concepts

### Flow

A Flow is a directed graph of Steps. It has a title, an optional description, a Vault, and a publication state. Flows exist in one of two modes at any time: **Edit mode** (author view) and **Reader mode** (execution view).

### Step

A Step is a node in the graph. It contains:
- A title (short, describes what this step is)
- Block content (full editor — paragraphs, headings, callouts, mentions, links, column layouts)
- Zero or more Exit Paths leading to other Steps

### Exit Path

An Exit Path is a labeled directed edge from one Step to another. The label is the button text the reader sees. A Step's exits determine what the reader can do next.

| Exit Count | Behavior |
|------------|---------|
| 0 exits | Terminal step — the path ends here |
| 1 exit | Linear — one "Next" button, reader continues automatically |
| 2+ exits | Branching — reader sees multiple buttons and chooses |

Exit path button labels are freeform text. Examples:
- `Next`
- `Yes` / `No`
- `Do you see any IP?` → `Yes`, `No`, `How do I know`
- `I fixed it` / `Still broken`

---

## The Graph Model

### Data Structure

Flows are stored as an adjacency list — one row per edge (exit path).

```sql
CREATE TABLE luma.flows (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    short_id     TEXT        NOT NULL UNIQUE,
    vault_id     UUID        NOT NULL REFERENCES luma.vaults(id),
    title        TEXT        NOT NULL,
    description  TEXT,
    is_published BOOLEAN     NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    published_by TEXT,
    created_by   TEXT        NOT NULL,
    updated_by   TEXT        NOT NULL,
    is_archived  BOOLEAN     NOT NULL DEFAULT false,
    archived_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE luma.flow_steps (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id      UUID        NOT NULL REFERENCES luma.flows(id) ON DELETE CASCADE,
    title        TEXT        NOT NULL DEFAULT 'New Step',
    content      JSONB       NOT NULL DEFAULT '{"blocks": []}',
    is_start     BOOLEAN     NOT NULL DEFAULT false,  -- exactly one per flow
    position_x   FLOAT,                               -- canvas X for editor layout
    position_y   FLOAT,                               -- canvas Y for editor layout
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_flow_steps_flow ON luma.flow_steps(flow_id);

CREATE TABLE luma.flow_edges (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id       UUID        NOT NULL REFERENCES luma.flows(id) ON DELETE CASCADE,
    from_step_id  UUID        NOT NULL REFERENCES luma.flow_steps(id) ON DELETE CASCADE,
    to_step_id    UUID        NOT NULL REFERENCES luma.flow_steps(id) ON DELETE CASCADE,
    label         TEXT        NOT NULL DEFAULT 'Next',
    position      INTEGER     NOT NULL DEFAULT 0,  -- button order when multiple exits
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT no_self_loop CHECK (from_step_id != to_step_id)
);
CREATE INDEX idx_flow_edges_from ON luma.flow_edges(from_step_id);
CREATE INDEX idx_flow_edges_flow ON luma.flow_edges(flow_id);
```

### Invariants

- Exactly one Step per Flow has `is_start = true`
- A new Flow is created with one start Step automatically
- `to_step_id` must belong to the same `flow_id` as `from_step_id` — enforced at application layer
- Deleted Steps cascade-delete their outgoing edges; incoming edges pointing to the deleted Step become dangling and are cleaned up by the deletion handler

---

## Cycle Detection

Cycles are allowed by design — a Flow can loop back to a previous Step (e.g. "Try again" loops back to the attempt step). However, infinite loops with no exit must be prevented or flagged.

### Cycle Policy

Cycles are **permitted** if at least one path through the cycle eventually reaches a terminal Step (a Step with no exits). Cycles that form a closed loop with no reachable terminal Step are **flagged** at publish time with a warning:

> "This flow has a loop with no exit. Readers following this path will have no way to complete the flow. Publish anyway?"

The author can choose to publish with the warning acknowledged.

### Detection Algorithm

At publish time, a depth-first search from the start Step tracks visited nodes. If DFS reaches a node already in the current path stack AND there is no terminal Step reachable from that cycle, flag the warning. This runs server-side on `POST /api/luma/flows/{id}/publish`.

---

## Author Experience (Edit Mode)

### Canvas View

The Flow editor shows a visual canvas with Steps as cards connected by labeled arrows. Steps can be dragged to reposition on the canvas (updates `position_x`, `position_y`). The canvas is the primary authoring view for understanding the overall structure.

### Step Editor

Clicking a Step on the canvas opens the Step editor panel (slides in from the right or opens as a modal on mobile). The Step editor contains:
- Step title field
- Full block editor for Step content (same component as Pages)
- Exit Paths section at the bottom: list of current exits with their labels, draggable to reorder, delete button per exit, "Add exit" button to connect to an existing or new Step

### Adding a Step

Two methods:
- Click "Add exit" in the Step editor and choose "New step" — creates a new Step and edge simultaneously
- Drag from the canvas toolbar to create a free-floating Step, then connect by dragging an arrow from an exit point

### Connecting Steps

Drag from the exit dot on one Step card to another Step card on the canvas to create an edge. A label field appears immediately for the exit button text.

---

## Reader Experience (Execution Mode)

When a reader opens a Flow, they see the **Start Step** — no canvas, no structure overview. Readers navigate one Step at a time.

### Reader View Layout

```
┌─────────────────────────────────────────────────────┐
│  How to Set Up a New Device                    [✕]  │
│  Step 3 of ~7  ●●●○○○○                              │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Connect to the Network                             │
│                                                     │
│  Open Settings on your device and navigate to      │
│  Wi-Fi. Look for the network named "Home-5G".      │
│  Enter the password from the Emergency Contacts    │
│  page → [Emergency Contacts link]                  │
│                                                     │
│  Do you see the network in the list?               │
│                                                     │
│  ┌─────────────┐  ┌──────────────────────────────┐ │
│  │  Yes, I do  │  │  No, I don't see it          │ │
│  └─────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

- Step title shown prominently
- Progress indicator: "Step 3 of ~7" — tilde used because branching means total steps is indeterminate. Shows steps completed / estimated total along the current path.
- Full block content rendered (read-only)
- Exit buttons at the bottom — one per exit path of the current Step
- Terminal Steps show a completion message: "You've reached the end of this flow." with a "Start over" option

### Execution State

Reader progress through a Flow is tracked per user per Flow. This enables:
- "Resume where you left off" when reopening a Flow
- Execution history in audit events
- Future: Flow completion tracking across a team

```sql
CREATE TABLE luma.flow_executions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id         UUID        NOT NULL REFERENCES luma.flows(id) ON DELETE CASCADE,
    user_id         TEXT        NOT NULL,
    current_step_id UUID        REFERENCES luma.flow_steps(id),
    path_taken      JSONB       NOT NULL DEFAULT '[]',
    -- [{ "step_id": "uuid", "exit_label": "Yes", "at": "timestamp" }]
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    is_active       BOOLEAN     NOT NULL DEFAULT true
);
CREATE INDEX idx_flow_exec_user ON luma.flow_executions(flow_id, user_id);
```

---

## Publication States

| State | Behavior |
|-------|---------|
| Draft | Visible only to Vault members with `flow:edit` permission. Cannot be executed by Viewers. |
| Published | Readable and executable by anyone with `flow:read` permission in the Vault. |

Publishing records `published_at` and `published_by`. Unpublishing returns to draft. Published flows can still be edited — the published version is the current version, there is no separate "published snapshot" in Phase 1.

---

## API Endpoints

```
GET    /api/luma/flows                       list flows (filterable by vault)
POST   /api/luma/flows                       create flow (creates start step automatically)
GET    /api/luma/flows/{shortId}             get flow with all steps and edges
PATCH  /api/luma/flows/{shortId}             update title, description
DELETE /api/luma/flows/{shortId}             archive flow
POST   /api/luma/flows/{shortId}/publish     publish flow (runs cycle detection)
POST   /api/luma/flows/{shortId}/unpublish   return to draft

GET    /api/luma/flows/{shortId}/steps                    list steps
POST   /api/luma/flows/{shortId}/steps                    create step
PATCH  /api/luma/flows/{shortId}/steps/{stepId}           update step title/content/position
DELETE /api/luma/flows/{shortId}/steps/{stepId}           delete step

GET    /api/luma/flows/{shortId}/edges                    list edges
POST   /api/luma/flows/{shortId}/edges                    create edge
PATCH  /api/luma/flows/{shortId}/edges/{edgeId}           update label or position
DELETE /api/luma/flows/{shortId}/edges/{edgeId}           delete edge

GET    /api/luma/flows/{shortId}/execute                  get current execution state for user
POST   /api/luma/flows/{shortId}/execute                  start or restart execution
POST   /api/luma/flows/{shortId}/execute/step             advance to next step (body: {exitEdgeId})
DELETE /api/luma/flows/{shortId}/execute                  abandon execution
```

---

## Audit Events

| Event | Trigger | Key Metadata |
|-------|---------|-------------|
| `flow_created` | New flow | `vault_id`, `title` |
| `flow_updated` | Title or description changed | |
| `flow_published` | Published | `cycle_warning_acknowledged` |
| `flow_unpublished` | Returned to draft | |
| `flow_archived` | Archived | |
| `flow_execution_started` | Reader started a flow | `flow_id`, `user_id` |
| `flow_execution_advanced` | Reader chose an exit | `step_id`, `exit_label`, `next_step_id` |
| `flow_execution_completed` | Reader reached terminal step | `path_length` |
| `flow_execution_abandoned` | Reader closed mid-flow | `steps_completed` |
