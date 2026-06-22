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
  type: 'daily' | 'weekly' | 'bonus'
  frequency: number                       ← weekly: slots per week; daily: days.length; bonus: 1
  days: number[]                          ← daily only: weekday list (0=Sun … 6=Sat)
  isActive: boolean                       ← false = soft-deleted
  createdBy: string                       ← email of the parent who created it
  createdAt: timestamp

/family/{familyId}/choreInstances/{instanceId}
  choreId: string
  choreName: string                       ← denormalized so old records stay readable
  choreScore: number                      ← denormalized so score changes don't affect past records
  choreType: 'daily' | 'weekly' | 'bonus' ← denormalized from chore for client-side filtering
  weekStart: timestamp                    ← Sunday 00:00 local time of the relevant week
  scheduledDate: timestamp | null         ← daily instances only: the specific calendar day
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
  rewardedPoints: number                  ← excess consumed by parent rewards this week
```

### Document ID conventions
- Family: auto-generated Firestore ID
- Users: email address (e.g. `kid@gmail.com`)
- Chores: auto-generated Firestore ID
- ChoreInstances: auto-generated Firestore ID
- WeeklyBalances: `{email}_{YYYY-MM-DD}` (e.g. `kid@gmail.com_2024-06-03`)

### Backward compatibility
Old documents with `type: "recurring"` are read as `weekly`; `type: "adhoc"` as `bonus`.
Old `choreInstances` without `choreType` default to `weekly`; without `scheduledDate` default to `null`.
No migration script is needed — `fromFirestore` handles both shapes.

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

## Chore Types & Lifecycle

### Three chore types

| Type | Description | Instance creation |
|---|---|---|
| **daily** | Tied to specific days of the week (e.g. Feed dog every Sun/Wed) | One instance per selected day, with `scheduledDate` set |
| **weekly** | Flexible — child picks when to do it during the week | `frequency` instances per week, no `scheduledDate` |
| **bonus** | Optional ad-hoc tasks the parent offers during the week | One instance created immediately on parent save |

### Days convention (daily chores)
`days` stores weekday integers with **0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat**.
Week starts on **Sunday** (Israel convention). `scheduledDate` is midnight of the calendar day.

### Instance workflow
```
Parent creates chore
    ↓
Instance(s) created immediately on save:
  daily  → one instance per day in chore.days, scheduledDate set to each day's date
  weekly → frequency instances, scheduledDate null
  bonus  → one instance, scheduledDate null
    ↓
Child opens "הבית" tab:
  daily  → appears in "משימות היום" if scheduledDate matches today
  weekly/bonus → appears in "זמין השבוע"
    ↓
Child taps "קח" → Firestore transaction:
  checks status == 'open' → sets status='claimed', claimedBy=email
    ↓
Child goes to "המשימות שלי" tab → taps "בוצע!"
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
Child's home tab shows updated progress

Parent taps "דחה" (Reject):
  - instance reset to status='open' (claimedBy/claimedAt cleared)
  - instance returns to available pool
```

### Week initialization (`ensureWeekInitialized`)
Called from both `ParentDashboard.initState()` and `ChildDashboard.initState()` on every app open.
Idempotency is enforced per-instance-slot:
- **daily**: tracks `(choreId, scheduledDate)` pairs — never creates a duplicate for the same day
- **weekly**: counts existing instances per choreId — creates only the missing ones up to `frequency`
- **bonus**: skipped entirely (managed at save time)

### Week boundaries
- Week starts on **Sunday 00:00 local time** (`getWeekStart()` in `week_utils.dart`)
- `weekStartId()` produces a stable `YYYY-MM-DD` string key used in balance doc IDs

---

## Points & Rewards

### Weekly balance
Each child has a `WeeklyBalance` doc for each week. Key computed properties:

```
availableExcess = max(0, earned + carryover - quota - rewardedPoints)
```

- `earned` — points approved this week
- `carryover` — net points carried in from previous week (positive = surplus, negative = debt)
- `rewardedPoints` — excess consumed by parent rewards this week (prevents double carry-over)

### Carryover calculation
When `ensureBalanceDoc()` creates a new week's doc, it reads the previous week's balance:
```
carryover = previousWeek.earned - previousWeek.quota + previousWeek.carryover - previousWeek.rewardedPoints
```
- Positive carryover = accumulated excess (banked points)
- Negative carryover = deficit that must be made up

### Reward flow
When a parent taps "תן פרס" on a child card in the Overview tab:
- `rewardedPoints` is incremented by the current `availableExcess`
- `availableExcess` becomes 0
- The rewarded points are excluded from next week's carryover (consumed in real life)
- The child sees "נקודות לפרס" on their home tab as motivation

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
| `openInstancesProvider` | `StreamProvider<List<ChoreInstance>>` | open instances this week; filtered client-side by choreType/scheduledDate for display |
| `myInstancesProvider` | `StreamProvider<List<ChoreInstance>>` | current child's claimed instances |
| `myBalanceStreamProvider` | `StreamProvider<WeeklyBalance?>` | current child's balance this week |

Client-side filtering (no extra Firestore queries or indexes):
- `openInstancesProvider` result is split in `_HomeTab` into daily-today vs. weekly/bonus lists

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| User doc ID | email address | Enables O(1) lookup on sign-in without knowing familyId first |
| Multi-family support | No (single family) | Simpler data model; app is private per household |
| Chore slot model | Open pool (any child can claim weekly/bonus) | Encourages healthy competition among siblings |
| Daily task filtering | Client-side on `scheduledDate` | Avoids new Firestore indexes; family-scale data makes this trivial |
| `choreType` on instances | Denormalized | Enables type-based display without a Firestore join |
| Days convention | 0=Sun…6=Sat | Natural for Israel week (Sun start); avoids Dart's Mon=1…Sun=7 awkwardness |
| Score history | Denormalized `choreName` + `choreScore` on each instance | Past records stay accurate if chore is later edited |
| Reward system | `rewardedPoints` field on `WeeklyBalance` | Cleanly separates "consumed" excess from carry-forward; parent gives real-life reward and zeroes the pool |
| Carryover | Computed at week-doc creation time | Simple; stored explicitly so parents and children can see it |
| Sub-screen navigation | Navigator.push (not GoRouter) | Simpler for modal forms; GoRouter handles top-level role routing |
| Notifications | None (in-app only) | Intentionally excluded; avoids FCM setup complexity |

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

No indexes are needed for `choreType` or `scheduledDate` — filtering on these fields is done client-side after the existing queries return.

---

## UI Conventions

- **RTL layout** — never use left/right positioning. Always use:
  - `EdgeInsetsDirectional` instead of `EdgeInsets.only(left/right)`
  - `AlignmentDirectional` instead of `Alignment.centerLeft/Right`
  - `BorderRadiusDirectional` instead of `BorderRadius.only(topLeft/Right)`
  - `TextAlign.start` instead of `TextAlign.left`
- **Numeric text fields** — use `textDirection: TextDirection.ltr` to fix cursor positioning in an RTL context.
- **Day display** — Hebrew day abbreviations: `{0:'א׳', 1:'ב׳', 2:'ג׳', 3:'ד׳', 4:'ה׳', 5:'ו׳', 6:'ש׳'}` (Sun–Sat).

---

## What's NOT implemented yet

- **Localization infrastructure** — strings are hardcoded in Hebrew. If you ever need English too, extract to ARB files.
- **Offline support** — Firestore's default offline cache helps, but no explicit offline-first design.
- **Photo display** — `photoUrl` is stored but avatars currently show first letter of name only.
- **Push notifications** — intentionally excluded; add `firebase_messaging` if needed later.
- **Release signing** — `android/app/build.gradle.kts` uses debug keys for release builds. Add a proper signing config before publishing.
- **Production Firestore rules** — test mode is wide open. Apply the rules in README.md before going live.
