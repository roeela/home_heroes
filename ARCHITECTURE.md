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
  type: 'weeklyPool' | 'specificDay'
  availablePerWeek: number                ← weeklyPool: 1–7; specificDay: scheduledDays.length
  scheduledDays: number[]                 ← specificDay only: weekday list (0=Sun … 6=Sat)
  choreWeekStart: timestamp | null        ← specificDay only: Sunday of the week it was created for
  isActive: boolean                       ← false = soft-deleted
  createdBy: string                       ← email of the parent who created it
  createdAt: timestamp

/family/{familyId}/choreInstances/{instanceId}
  choreId: string
  choreName: string                       ← denormalized so old records stay readable
  choreScore: number                      ← denormalized so score changes don't affect past records
  choreType: 'weeklyPool' | 'specificDay' ← denormalized for client-side filtering
  weekStart: timestamp                    ← Sunday 00:00 local time of the relevant week
  registeredDay: timestamp                ← midnight of the day the child registered for
  registeredBy: string                    ← email of the child who registered
  registeredAt: timestamp
  completedAt: timestamp | null
  approvedAt: timestamp | null
  approvedBy: string | null              ← email of the approving parent
  status: 'registered' | 'completed' | 'approved' | 'rejected' | 'cancelled'

/family/{familyId}/weeklyBalances/{userId_weekStartId}
  userId: string                          ← child's email
  weekStart: timestamp
  quota: number                           ← snapshot of child's quota for that week
  earned: number                          ← sum of choreScore for approved instances
  carryover: number                       ← positive = excess from prev week; negative = debt
  rewardedPoints: number                  ← excess consumed by parent rewards this week
  pendingClaim: boolean                   ← true when child has requested a bonus award
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

## Chore Types & Lifecycle

### Two chore types

| Type | Description | Persistence |
|---|---|---|
| **weeklyPool** | Parent defines once; children register for day(s) each week | Permanent — appears every week until deleted |
| **specificDay** | Parent defines for the current week with specific days | One-week only — filtered by `choreWeekStart` |

### Days convention
`scheduledDays` stores weekday integers with **0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat**.
Week starts on **Sunday** (Israel convention). `registeredDay` is midnight local time of the chosen calendar day.

### Instance status lifecycle
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
    → status = 'rejected'   (slot freed; no points; hidden from child)

Child unregisters (before day passes)
    → status = 'cancelled'  (slot freed)

Chore deleted by parent
    → all registered/completed instances → status = 'cancelled'
```

### Pool slot counting
A slot is **consumed** when `status ∈ {registered, completed, approved}` (`isActiveSlot` getter).
A slot is **free** when `status ∈ {rejected, cancelled}`.

```
usedSlots      = count of instances for choreId + weekStart where isActiveSlot == true
remainingSlots = chore.availablePerWeek - usedSlots
```

A given calendar day is **taken** if any active-slot instance exists for that chore + day.

### Registration — day locking
`registerForDay()` runs a Firestore **transaction** that checks for existing active-slot instances on the same `choreId + registeredDay` before creating the new instance. This prevents two children registering the same day even under concurrent taps.

### Delete cascade
When a parent deletes a chore:
1. `cancelActiveInstancesForChore()` batch-cancels all `registered`/`completed` instances
2. `chore.isActive` is set to `false`
3. Firestore real-time streams on all connected clients update instantly — chore card disappears from child home screen, instances disappear from child My Tasks tab, pending approvals disappear from parent Approvals tab

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
- `pendingClaim` — set to `true` when the child has tapped "נקודות לפרס" to request a bonus award

### Carryover calculation
When `ensureBalanceDoc()` creates a new week's doc, it reads the previous week's balance:
```
carryover = previousWeek.earned - previousWeek.quota + previousWeek.carryover - previousWeek.rewardedPoints
```
- Positive carryover = accumulated excess (banked points)
- Negative carryover = deficit that must be made up

### Bonus claim flow
```
Child sees "נקודות לפרס" row on home screen (excess > 0, pendingClaim == false)
    ↓
Child taps row → confirmation dialog
    ↓
balanceRepo.requestBonus() → sets pendingClaim = true
    ↓
Row changes to "בקשת פרס נשלחה להורה" (non-tappable)
    ↓
Parent sees "_BonusClaimCard" at top of Approvals tab
    ↓
Parent taps "תן פרס"
    ↓
balanceRepo.giveReward():
  - rewardedPoints += availableExcess
  - pendingClaim = false
    ↓
availableExcess becomes 0; child's row disappears
```

Unspent excess (parent never awards) carries forward to next week via the carryover formula above.

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
- `features/parent/providers/parent_providers.dart` — repository providers + parent streams + actions
- `features/child/providers/child_providers.dart` — child-specific streams

No code generation (no `riverpod_annotation` / `build_runner`). All providers are written manually using `Provider`, `StreamProvider`, and `FutureProvider`.

### Key providers

| Provider | Type | Description |
|---|---|---|
| `firebaseAuthProvider` | `Provider<FirebaseAuth>` | singleton |
| `firestoreProvider` | `Provider<FirebaseFirestore>` | singleton |
| `authStateProvider` | `StreamProvider<User?>` | Firebase auth state changes |
| `currentFamilyUserProvider` | `FutureProvider<FamilyUser?>` | resolved Firestore user for current auth |
| `currentWeekStartProvider` | `Provider<DateTime>` | Sunday midnight of the current week |
| `choreListProvider` | `StreamProvider<List<Chore>>` | all active chores for the family |
| `pendingApprovalProvider` | `StreamProvider<List<ChoreInstance>>` | completed instances awaiting approval (current week) |
| `pendingBonusClaimsProvider` | `Provider<List<WeeklyBalance>>` | balances with `pendingClaim == true` this week |
| `childrenProvider` | `StreamProvider<List<FamilyUser>>` | active child users |
| `childrenBalancesProvider` | `StreamProvider<List<WeeklyBalance>>` | all children's balances this week |
| `weekAllInstancesProvider` | `StreamProvider<List<ChoreInstance>>` | all instances this week (all children, all statuses) — used for pool availability computation |
| `myRegistrationsProvider` | `StreamProvider<List<ChoreInstance>>` | current child's registrations this week |
| `visibleChoresProvider` | `Provider<List<Chore>>` | weeklyPool chores always; specificDay chores only if `choreWeekStart` matches current week |
| `myBalanceStreamProvider` | `StreamProvider<WeeklyBalance?>` | current child's balance this week |

Client-side filtering (no extra Firestore queries):
- `visibleChoresProvider` filters specificDay chores by `choreWeekStart`
- `weekAllInstancesProvider` result is used in `_HomeTab` and `_DayPickerSheet` to compute per-chore slot availability and per-day chip states

---

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| User doc ID | email address | Enables O(1) lookup on sign-in without knowing familyId first |
| Multi-family support | No (single family) | Simpler data model; app is private per household |
| Registration-based instances | Created only on child registration | Eliminates upfront slot creation; pool availability computed client-side |
| Pool availability | Client-side count of active instances per choreId per week | Family scale makes this trivial; avoids composite Firestore indexes on type/date |
| specificDay week scoping | `choreWeekStart` field on Chore | Parent must redefine each week; old chores don't bleed into new weeks |
| Day locking | Firestore transaction in `registerForDay` | Prevents two children booking the same day under concurrent taps |
| Rejected instances free the slot | `status = rejected` excluded from `isActiveSlot` | If parent says "you didn't do it", the day slot returns to the family pool |
| Missed registrations | Client-side filter (hide if `registeredDay < today` and `status == registered`) | No background job needed |
| Delete cascade | Batch-cancel instances → deactivate chore | Real-time streams propagate instantly to all connected devices |
| `choreType` on instances | Denormalized | Enables type-based display without a Firestore join |
| Days convention | 0=Sun…6=Sat | Natural for Israel week (Sun start); avoids Dart's Mon=1…Sun=7 awkwardness |
| Score history | Denormalized `choreName` + `choreScore` on each instance | Past records stay accurate if chore is later edited |
| Bonus claim | Child-initiated via tap; parent approves in Approvals tab | Child feels agency; parent has final control; `pendingClaim` flag on balance doc is the simplest possible state machine |
| Reward system | `rewardedPoints` + `pendingClaim` on `WeeklyBalance` | Cleanly separates "consumed" excess from carry-forward; no separate claim collection needed |
| Sub-screen navigation | Navigator.push (not GoRouter) | Simpler for modal forms; GoRouter handles top-level role routing |
| Notifications | None (in-app only) | Intentionally excluded; avoids FCM setup complexity |

---

## Firestore Composite Indexes

Defined in `firestore.indexes.json` and deployed via `firebase deploy --only firestore:indexes`.

| Collection | Fields | Scope |
|---|---|---|
| `users` | `email`, `isActive` | Collection group |
| `users` | `role`, `isActive` | Collection |
| `choreInstances` | `weekStart`, `status` | Collection |
| `choreInstances` | `registeredBy`, `weekStart` | Collection |
| `choreInstances` | `choreId`, `registeredDay`, `weekStart` | Collection |

No indexes are needed for `choreType` or day-of-week filtering — all such filtering is done client-side after the base queries return.

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
