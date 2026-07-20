# Milestone 6 — Gravity and time

Completed on 20 July 2026.

## Behaviour

Gravity is deliberately opt-in at workspace level. Each thought can inherit that
choice, stay off, or enable gravity independently. Version 1–3 maps migrate with
workspace gravity disabled, so opening an existing space never moves anything.

A thought can carry an optional due date, milestone, and reminder. The pure
`GravityEngine` evaluates those signals and returns:

- a suggested effective attention value;
- an urgency state;
- a human-readable reason; and
- whether gravity is currently influencing the thought.

The engine only pulls work closer. It never overwrites the persisted manual
attention value. Due dates have the strongest pull, milestones are gentler, and
reminders begin pulling after they fire. The renderer animates computed changes
unless Reduce Motion is enabled, and existing urgency glyphs communicate overdue
or approaching work without relying on colour alone.

Any direct attention change starts a seven-day manual hold. The inspector states
the hold's end date and offers **Let gravity resume now**. This makes the user's
choice dominant, inspectable, and reversible.

## Persistence and architecture

Schema version 4 adds the three optional temporal signals, the last manual
override, a per-node gravity preference, and the workspace opt-in. Manual
attention remains domain state; effective attention and explanations are derived
in application logic and passed to the renderer in an immutable snapshot.

Gravity is refreshed every minute while the workspace is open. It does not
mutate or autosave nodes merely because time passed.

## Acceptance evidence

- `swift test`: 41 tests passed, including schema 1 migration, schema 4
  round-trip, overdue and competing-signal evaluation, the seven-day manual
  hold, opt-in behaviour, and separation of manual from effective attention.
- `Scripts/package-app.sh`: produced an ad-hoc signed application bundle that
  passed strict deep signature verification.
- Signed-app review with the deterministic `north-star` scene confirmed the
  workspace toggle, the collapsible per-node time controls, and the explanation
  path. A node manually placed at 68% with a due date seven days away stayed put
  during its hold; releasing the hold displayed **Gravity suggests 84%** with
  the reason **Due within 7 days**, while manual attention remained 68%.
