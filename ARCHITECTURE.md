# HomeHeroes — Architecture & Design

## Firestore Data Model

All data lives under a single top-level family document.
User email is used as the document ID for user docs (enables O(1) lookup on sign-in).

```
/family/{familyId}
  name: string
  createdAt: timestamp

/family/{familyId}/users/{userEmail}      ← email IS the doc ID
  displayName: string
  email: string                           ← same as doc ID, stored for collectionGroup queries
  role: 'parent' | 'child'
  weeklyQuota: number                     ← children only; 0 for parents
  photoUrl: string | null
  isPrimary: boolean                      ← true only on the first parent who created the family
  status: 'pending' | 'active'           ← pending until the user signs in for the first time
  isActive: boolean                       ← false = soft-deleted (by primary parent)
  uid: string | null                      ← Firebase Auth UID; null until first sign-in

/family/{familyId}/chores/{choreId}
  name: string
  description: string
  score: number
  type: 'recurring' | 'adhoc'
  frequency: number                       ← recurring: slots per week; adhoc: always 1
  isActive: boolean                       ← false = soft-deleted
  createdBy: string                       ← email of the parent who created it
  createdAt: timestamp

/family/{familyId}/choreInstances/{instanceId}
  choreId: string
  choreName: string                       ← denormalized so old records stay readable
  choreScore: number                      ← denormalized so score changes don't affect past records
  weekStart: timestamp                    ← Monday 00:00 local time of the relevant week
  claimedBy: string | null               ← email of the child who claimed it
  claimedAt: timestamp | null
  completedAt: timestamp | null
  approvedAt: timestamp | null
  approvedBy: string | null              ← email of the approving parent
  status: 'open' | 'claimed' | 'completed' | 'approved' | 'rejected'

/family/{familyId}/weeklyBalances/{userId_weekStartId}
  userId: string                          ← child's email
  weekStart: timestamp
  quota: number                           ← snapshot of child's quota for that week
  earned: number                          ← sum of choreScore for approved instances
  carryover: number                       ← positive = excess from prev week; negative = debt
```

### Document ID conventions
- Family: auto-generated Firestore ID
- Users: email address (e.g. `kid@gmail.com`)
- Chores: auto-generated Firestore ID
- ChoreInstances: auto-generated Firestore ID
- WeeklyBalances: `{email}_{YYYY-MM-DD}` (e.g. `kid@gmail.com_2024-06-03`)

---

## Auth & Registration Flow

### Sign-in (all users)
```
Google Sign-In
    ↓
Firebase Auth (gets email from Google account)
    ↓
collectionGroup query: users where email == signedInEmail && isActive == true
    ↓
Found?
  YES → if uid field is null (first sign-in): update doc with uid + status='active'
        → route to /parent or /child based on role
  NO  → route to /no-family
          ├── User can tap "צור משפחה חדשה" → /setup → becomes primary parent
          └── Or user sees message: "בקש מהוריך להוסיף אותך"
```

### Adding a family member (parent flow)
1. Parent goes to Family tab → taps "+"
2. Enters child's Gmail + display name + weekly quota + role
3. Creates user doc: `status: 'pending', isActive: true, uid: null`
4. Next time that Gmail signs in → doc found → activated automatically

### Removing a member
- Only the **primary parent** (`isPrimary: true`) sees the remove button
- Removal sets `isActive: false` (soft-delete) — history is preserved

---

## Weekly Chore Lifecycle

```
Parent creates chore (type: recurring, frequency: 3)
    ↓
createRecurringInstancesForWeek() called immediately on save
    ↓
3 open ChoreInstances created for current week (Monday–Sunday)
    ↓
Child sees instances in "Available" tab
    ↓
Child taps "הירשם" (Register) → Firestore transaction:
  checks status == 'open' → sets status='claimed', claimedBy=email
    ↓
Child goes to "My Chores" tab → taps "בוצע!" (Done)
  → status='completed'
    ↓
Parent sees instance in "Approvals" tab
    ↓
Parent taps "אשר" (Approve):
  1. ensureBalanceDoc() for child this week (creates doc if missing, computes carryover)
  2. Firestore batch:
     - instance: status='approved'
     - weeklyBalance.earned += choreScore
    ↓
Child's "My Week" tab shows updated progress

Parent taps "דחה" (Reject):
  - instance reset to status='open' (claimedBy/claimedAt cleared)
  - instance returns to available pool
```

### Week boundaries
- Week starts on **Monday 00:00 local time** (`getWeekStart()` in `week_utils.dart`)
- `ensureWeekInitialized()` is idempotent — checks per-chore which instances already exist for the week, and only creates missing ones
- Called from both `ParentDashboard.initState()` and `ChildDashboard.initState()` on every app open — week initialization is independent of which role opens first
- New recurring chores also get instances created immediately on save (via `createRecurringInstancesForWeek()`), so children see them without waiting for the next app open

### Carryover calculation
When `ensureBalanceDoc()` creates a new week's doc, it reads the previous week's balance:
```
carryover = previousWeek.earned - previousWeek.quota + previousWeek.carryover
```
- Positive carryover = accumulated excess (child can "bank" points)
- Negative carryover = debt (must make up deficit)
- Parent can reset carryover to 0 from the Overview tab

---

## Routing

GoRouter with a `_RouterNotifier extends ChangeNotifier` that watches:
- `authStateProvider` (Firebase Auth stream)
- `currentFamilyUserProvider` (resolved FamilyUser future)

```
/login          → LoginScreen           (unauthenticated)
/no-family      → NoFamilyScreen        (authenticated, but email not in any family)
/setup          → FamilySetupScreen     (creating a new family)
/parent         → ParentDashboard       (authenticated, role=parent)
/child          → ChildDashboard        (authenticated, role=child)
```

Role guard: if a parent somehow lands on `/child` (or vice versa), the redirect pushes them back.

Sub-screens (chore form, add member) use `Navigator.of(context).push(MaterialPageRoute(...))` — not GoRouter routes — since they're modal overlays on top of the dashboard.

---

## State management patterns

All providers live in:
- `features/auth/providers/auth_provider.dart` — Firebase instances, auth state, current user
- `features/parent/providers/parent_providers.dart` — repository providers + parent streams
- `features/child/providers/child_providers.dart` — child-specific streams

No code generation (no `riverpod_annotation` / `build_runner`). All providers are written manually using `Provider`, `StreamProvider`, and `FutureProvider`.

### Key providers

| Provider | Type | Description |
|---|---|---|
| `firebaseAuthProvider` | `Provider<FirebaseAuth>` | singleton |
| `firestoreProvider` | `Provider<FirebaseFirestore>` | singleton |
| `authStateProvider` | `StreamProvider<User?>` | Firebase auth state changes |
| `currentFamilyUserProvider` | `FutureProvider<FamilyUser?>` | resolved Firestore user for current auth |
| `choreListProvider` | `StreamProvider<List<Chore>>` | active chores for the family |
| `pendingApprovalProvider` | `StreamProvider<List<ChoreInstance>>` | completed instances awaiting approval |
| `childrenProvider` | `StreamProvider<List<FamilyUser>>` | active child users |
| `childrenBalancesProvider` | `StreamProvider<List<WeeklyBalance>>` | all children's balances this week |
| `openInstancesProvider` | `StreamProvider<List<ChoreInstance>>` | open instances this week (child view) |
| `myInstancesProvider` | `StreamProvider<List<ChoreInstance>>` | current child's claimed instances |
| `myBalanceStreamProvider` | `StreamProvider<WeeklyBalance?>` | current child's balance this week |

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| User doc ID | email address | Enables O(1) lookup on sign-in without knowing familyId first |
| Multi-family support | No (single family) | Simpler data model; app is private per household |
| Chore slot model | Open pool (any child can claim) | Encourages competition among siblings |
| Recurring instance creation | Client-side, on chore save + both dashboards' initState | Avoids Cloud Functions; idempotent per-chore check means no duplicates; child-side init removes dependency on parent opening app first |
| Score history | Denormalized choreName + choreScore on each instance | Past records stay accurate if chore is later edited |
| Carryover | Computed at week-doc creation time | Simple; stored explicitly so parents can see and reset it |
| Sub-screen navigation | Navigator.push (not GoRouter) | Simpler for modal forms; GoRouter handles top-level role routing |
| Notifications | None (in-app only) | Requested by user; avoids FCM setup complexity |

---

## Firestore Composite Indexes

Defined in `firestore.indexes.json` and deployed via `firebase deploy --only firestore:indexes`.

| Collection | Fields | Scope |
|---|---|---|
| `users` | `email`, `isActive` | Collection group |
| `users` | `role`, `isActive` | Collection |
| `choreInstances` | `status`, `weekStart` | Collection |
| `choreInstances` | `claimedBy`, `weekStart` | Collection |
| `choreInstances` | `claimedBy`, `weekStart`, `status` | Collection |

---

## UI Conventions

- **RTL layout** — never use left/right positioning. Always use:
  - `EdgeInsetsDirectional` instead of `EdgeInsets.only(left/right)`
  - `AlignmentDirectional` instead of `Alignment.centerLeft/Right`
  - `BorderRadiusDirectional` instead of `BorderRadius.only(topLeft/Right)`
  - `TextAlign.start` instead of `TextAlign.left`
- **Design tokens** — all colors, spacing, radii, and elevations are defined as `static const` on `AppTheme`. Use `AppTheme.spaceM`, `AppTheme.radiusCard`, etc. rather than hardcoded values.
- **Numeric text fields** — use `textDirection: TextDirection.ltr` to fix cursor positioning in an RTL context.

---

## What's NOT implemented yet

- **Localization infrastructure** — strings are hardcoded in Hebrew. If you ever need English too, extract to ARB files.
- **Offline support** — Firestore's default offline cache helps, but no explicit offline-first design.
- **Photo display** — `photoUrl` is stored but avatars currently show first letter of name only.
- **Push notifications** — intentionally excluded; add `firebase_messaging` if needed later.
- **Release signing** — `android/app/build.gradle.kts` uses debug keys for release builds. Add a proper signing config before publishing.
- **Production Firestore rules** — test mode is wide open. Apply the rules in README.md before going live.
