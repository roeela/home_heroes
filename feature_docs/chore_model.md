# Chore Model — Feature Documentation

## Overview

HomeHeroes uses a **registration-based** chore model. Instead of a parent creating slots upfront and children claiming them, children actively choose which day they will perform each chore. This encourages ownership and prevents the "first-click wins" race that the old claim model had.

---

## Chore Types

There are two chore types, replacing the old daily / weekly / bonus system.

### Weekly Pool Chore (`weeklyPool`)

| Property | Details |
|---|---|
| **Defined by parent** | Once. The chore persists week after week automatically. |
| **Available per week** | 1–7 slots. Determines how many times the chore can be performed across the family in a single week. |
| **Child registration** | Child picks any day(s) of the week. Each day can have at most one child registered. Total registrations cannot exceed `availablePerWeek`. |
| **Multi-slot** | A single child can register for the same chore on multiple days, consuming multiple slots. |

**Example:** "כלים" (wash dishes), available 3× per week. Child A can take Monday + Wednesday (2 slots), leaving 1 slot for a sibling to take on any remaining day.

### Specific Day Chore (`specificDay`)

| Property | Details |
|---|---|
| **Defined by parent** | Each week the parent wants it available. It does **not** carry over to the next week. |
| **Scheduled days** | Parent picks one or more specific days (e.g. Thursday only). |
| **Child registration** | Child registers for one of the parent-defined days. First-come-first-served — one child per day slot. |
| **`availablePerWeek`** | Automatically equals the number of scheduled days. |

**Example:** "ניקוי חדר" (clean room) defined for Wednesday and Friday this week. Two children can each take one of those days.

---

## Firestore Data Model

### Chore Document (`/family/{familyId}/chores/{choreId}`)

```
name:             string
description:      string
score:            number
type:             'weeklyPool' | 'specificDay'
availablePerWeek: number          // weeklyPool: 1–7; specificDay: scheduledDays.length
scheduledDays:    number[]        // specificDay only: 0=Sun … 6=Sat
choreWeekStart:   timestamp|null  // specificDay only: Sunday of the week it was created for
isActive:         boolean
createdBy:        string          // parent email
createdAt:        timestamp
```

### Chore Instance Document (`/family/{familyId}/choreInstances/{instanceId}`)

Instances are created **only when a child registers** — never upfront.

```
choreId:       string
choreName:     string       // denormalized — stays readable if chore is edited
choreScore:    number       // denormalized — past records unaffected by score changes
choreType:     'weeklyPool' | 'specificDay'   // denormalized for client filtering
weekStart:     timestamp    // Sunday midnight of the relevant week
registeredDay: timestamp    // midnight of the specific day the child chose
registeredBy:  string       // child email
registeredAt:  timestamp
completedAt:   timestamp | null
approvedAt:    timestamp | null
approvedBy:    string | null
status:        'registered' | 'completed' | 'approved' | 'rejected' | 'cancelled'
```

### Instance Status Lifecycle

```
Child registers for a day
    → status = 'registered'
        ↓
Child taps "בוצע!" on that day
    → status = 'completed'
        ↓
Parent approves
    → status = 'approved'   (points credited to child's weekly balance)

Parent rejects
    → status = 'rejected'   (slot freed; no points)

Child unregisters (before day passes)
    → status = 'cancelled'  (slot freed)

Chore deleted by parent
    → all registered/completed instances → status = 'cancelled'
```

### Pool Slot Counting

A slot is **consumed** when `status ∈ {registered, completed, approved}`.
A slot is **free** when `status ∈ {rejected, cancelled}`.

```
usedSlots      = count of instances for choreId + weekStart with isActiveSlot == true
remainingSlots = chore.availablePerWeek - usedSlots
```

A given calendar day is **taken** if any active-slot instance exists for that chore + day.

---

## User-Facing Views

### Parent Side

#### Chores Tab
- Lists all active chores.
- **weeklyPool** shows: `עד X× בשבוע`
- **specificDay** shows: day abbreviations + the week date it was created for (e.g. `ד׳, ו׳ (25/6)`)
- Tap → edit chore form.
- Long-press → delete confirmation. Deleting cancels all open registrations in real-time across all connected devices.

#### Chore Form
- Type selector: **שבועי** (weeklyPool) | **יום ספציפי** (specificDay)
- weeklyPool: name, description, score, `כמה פעמים בשבוע` (1–7)
- specificDay: name, description, score, day checkboxes (א׳–ש׳)
- No instance creation happens on save — the pool is virtual.

#### Approvals Tab
- Shows instances with `status = completed` for the current week.
- Each card shows: chore name, score, child name, registered day, completion time.
- **אשר** → approves and credits points to the child's weekly balance.
- **דחה** → rejects; slot is freed and not counted in the pool.

### Child Side

#### Home Tab — Chore Cards

Each active chore appears as **a single card** regardless of how many slots it has. The card shows:
- Chore name + score badge
- Remaining slots or the child's own registered days (e.g. `שלי: ב׳ 23/6, ד׳ 25/6`)
- Icon: 🔁 for weeklyPool, 📅 for specificDay
- Tapping a full pool (no remaining + none mine) is disabled.

#### Home Tab — Day Picker (bottom sheet)

Opens when the child taps a chore card. Shows a grid of day chips for the week:

| Chip state | Appearance | Meaning |
|---|---|---|
| **Available** | Outlined | Child can register |
| **Mine** | Filled (primary) + checkmark | Child is already registered; tap to unregister |
| **Taken** | Grey + lock icon | Another child is registered for this day |
| **Disabled** | Grey | Past day, or pool is full |

- For **specificDay** chores: only the parent-defined days are shown.
- For **weeklyPool** chores: all 7 days are shown.
- Remaining slot count is shown at the top of the sheet.

#### My Tasks Tab — 4 Sections

| Section (Hebrew) | Filter | Actions |
|---|---|---|
| **היום** | `registered` + `registeredDay == today` | "בוצע!" button |
| **הקרוב** | `registered` + `registeredDay > today` | "בטל" (unregister) button |
| **ממתין לאישור הורה** | `completed` | Read-only |
| **הושלם ✓** | `approved` | Read-only, score shown in green |

Expired registrations (`registered` + `registeredDay < today`) are silently hidden — no credit, no notification.
Cancelled and rejected instances are never shown.

---

## Key Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Instances created on registration | Not upfront | Eliminates the "open slot pool" concept; cleaner model |
| Pool availability computed client-side | Count active instances per choreId per week | Family scale makes this trivial; avoids extra Firestore indexes |
| specificDay scoped to a weekStart | `choreWeekStart` field on Chore | Parent must redefine each week; old chores don't bleed into new weeks |
| Day locking per child | One active-slot instance per chore+day | Prevents two children registering the same day |
| Rejected instances free the slot | `status = rejected` excluded from pool count | If parent says "you didn't do it," the day slot goes back to the family |
| Delete cascade | Cancel all registered/completed instances in a batch | Firestore real-time streams propagate the cancellation to all open devices instantly |
| Missed registrations | Client-side filter (hide if registeredDay < today) | No background job or server function needed |

---

## Implementation Steps

The changes below were applied to the codebase in this order.

### 1. Models
- **`lib/features/shared/models/chore.dart`** — `ChoreType` enum changed to `weeklyPool | specificDay`; replaced `frequency` / `days` fields with `availablePerWeek`, `scheduledDays`, `choreWeekStart`.
- **`lib/features/shared/models/chore_instance.dart`** — `InstanceStatus` enum changed to `registered | completed | approved | rejected | cancelled`; renamed `claimedBy/At → registeredBy/At`; renamed `scheduledDate → registeredDay` (now required, not nullable); added `isActiveSlot` computed getter.

### 2. Repositories
- **`lib/features/shared/repositories/chore_repository.dart`** — Updated `createChore` signature; renamed `deleteChore → deactivateChore` (cascade logic moved to the action layer); removed `getActiveChores` (no longer needed after removing week init).
- **`lib/features/shared/repositories/instance_repository.dart`** — Full rewrite. Removed all upfront instance creation methods (`ensureWeekInitialized`, `createDailyInstancesForWeek`, `createWeeklyInstancesForWeek`, `createBonusInstance`, `releaseUserInstances`). Added: `registerForDay` (Firestore transaction to prevent double-registration), `unregister`, `watchWeekInstances`, `watchMyRegistrations`, `watchPendingApproval` (now scoped to current week), `cancelActiveInstancesForChore`, `cancelUserRegistrations`.

### 3. Firestore Indexes
- **`firestore.indexes.json`** — Replaced `claimedBy` index with `registeredBy`; added `choreId + registeredDay + weekStart` composite index; kept `weekStart + status` and user indexes.

### 4. Providers
- **`lib/features/parent/providers/parent_providers.dart`** — Added `deleteChore` action (cancels instances then deactivates chore); updated `approveChore` to use `registeredBy`; `pendingApprovalProvider` now filters by current week.
- **`lib/features/child/providers/child_providers.dart`** — Replaced `openInstancesProvider` with `weekAllInstancesProvider` (all week instances, all statuses); replaced `myInstancesProvider` with `myRegistrationsProvider`; added `visibleChoresProvider` (filters specificDay chores by current weekStart).

### 5. Parent Screens
- **`lib/features/parent/screens/chore_form_screen.dart`** — Two-type form (weeklyPool / specificDay); removed bonus type and frequency field; no instance creation on save.
- **`lib/features/parent/screens/parent_dashboard.dart`** — Removed `initState` week initialization; delete action now calls `deleteChore` action (cascade); approvals card updated to show `registeredDay` and use `registeredBy`; member reset calls `cancelUserRegistrations`.

### 6. Child Screens
- **`lib/features/child/screens/child_dashboard.dart`** — Complete rewrite of both tabs:
  - Home tab: one card per chore (from `visibleChoresProvider`); availability computed from `weekAllInstancesProvider`; day-picker bottom sheet with `_DayChip` states (available / mine / taken / disabled).
  - My Tasks tab: 4-section layout (היום / הקרוב / ממתין לאישור / הושלם); expired and cancelled instances silently filtered; "בוצע!" on today's tasks, "בטל" on upcoming tasks.
