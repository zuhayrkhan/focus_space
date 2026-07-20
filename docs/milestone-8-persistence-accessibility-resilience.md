# Milestone 8 — Persistence, accessibility, and resilience

Completed on 20 July 2026.

## Safe persistence

Schema version 4 remains the current domain format. Explicit migration fixtures
now cover every shipped version:

- version 1 gains visual, notes, and gravity defaults;
- version 2 preserves node kind, urgency, and enabled state while gaining notes;
- version 3 preserves notes and gains temporal/gravity defaults;
- version 4 round-trips all temporal and gravity state.

Unknown future versions are rejected rather than silently dropping fields.

Before each atomic JSON save, the repository validates the existing primary and
rotates it to `focus-space.recovery.json`. Startup automatically uses that last
valid copy if the primary is corrupt or missing and reports the recovery in
**Storage details**. Autosave still debounces ordinary edits by 350 ms; moving
the app out of the active state forces an immediate save.

The toolbar's drive menu provides **Import Space**, **Export Space**, **Save
Now**, and **Storage Details**. The diagnostics sheet displays the exact primary
and recovery paths, current session state, last save, and Finder access. Import
and export use the same version-aware codec as autosave.

## VoiceOver and keyboard

The RealityKit canvas has a SwiftUI accessibility representation. Every thought
announces:

- title and kind;
- effective attention percentage;
- parent, child count, and related thoughts;
- urgency, view-filter state, and gravity explanation when relevant.

Each hierarchy and cross-link is also a separate accessible element. Thoughts
provide adjustable Increment/Decrement depth plus named Pull Forward, Push Back,
and Add Child actions.

The **Navigate** menu provides keyboard shortcuts for previous/next thought,
parent/first child, X/Y movement, and attention movement. Rename, child creation,
undo/redo, camera navigation, framing, and reset retain their existing keyboard
routes.

## Accessible rendering

The 3D renderer responds to:

- Reduce Motion by pausing ambient motion and avoiding gravity/camera animation;
- Increase Contrast by strengthening node, text, and relationship opacity;
- Differentiate Without Colour by enforcing semantic node silhouettes;
- larger text sizes by regenerating RealityKit label meshes at a bounded scale.

A standard SwiftUI **Accessible map view** uses the same application snapshot
when the Mac has no Metal device, when launched with `--accessible-list`, or when
the user enables it in **Workspace guides → Accessibility & display**. It keeps
hierarchy, attention, urgency, selection, inspector editing, search, focus mode,
and keyboard operations usable without colour, precise pointing, animation, or
advanced 3D effects.

## Acceptance evidence

- `swift test`: 56 tests passed, including every schema migration, future-schema
  rejection, atomic recovery for corrupt and missing primaries, autosave,
  import/export, accessibility descriptions, keyboard traversal/manipulation,
  renderer fallback selection, Reduce Motion, increased contrast, and accessible
  RealityKit text scaling.
- `Scripts/package-app.sh`: produced an ad-hoc signed application bundle that
  passed strict deep signature verification.
- A signed `--accessible-list` run exposed all deterministic `north-star` nodes
  as standard accessible buttons. Control-Down changed selection and updated the
  persistent inspector without pointer input.
- The signed storage menu exposed import, export, manual save, and exact primary
  and recovery paths; the diagnostics correctly reported that experience
  previews do not autosave.
- A signed normal-renderer run exposed each node and every hierarchy/cross-link
  individually. Invoking the VoiceOver **Pull forward** action changed System
  Platform from 48% to 60%, updated link descriptions, and enabled Undo.
