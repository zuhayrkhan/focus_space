# Milestone 5 — Depth manipulation

Completed on 20 July 2026.

## Interaction contract

- Dragging a node continues to arrange it on the hierarchy plane.
- A vertical two-finger drag begun over a node changes attention and carries its
  descendants while preserving their relative attention offsets. The gesture
  locks to depth movement until the fingers lift.
- Horizontal two-finger movement over a node, and two-finger movement over empty
  space, continues to pan the camera.
- Option-dragging changes attention on a camera-facing interaction plane, so the
  pointer alternative remains spatially consistent as camera distance changes.
- Command-Option-dragging explicitly isolates the grabbed node from its branch.
- A temporary guide previews the landing point and identifies whether one item
  or a branch is moving. It disappears when the manipulation ends.
- Now, This week, This sprint, This quarter, and Someday act as magnetic depth
  stops without adding scheduling metadata to the node.

The existing attention slider and toolbar nudges remain available. The inspector
also exposes every semantic stop directly, including a Custom state, for users
who prefer keyboard or accessibility controls.

One drag is grouped into one undoable store mutation. The renderer previews all
affected nodes and their relationships continuously; no node disappears while
it is being moved.

## Architecture

`AttentionBand` owns the renderer-independent semantic stops.
`DepthManipulation` converts screen translation through the camera field of view
and interaction-plane height into domain attention, then applies the magnetic
landing rule. RealityKit only receives immutable preview items and remains an
implementation detail.

## Acceptance evidence

- `swift test`: 36 tests passed, including camera-aware plane scaling, magnetic
  landing, branch offset preservation, unaffected-node isolation, and one-step
  undo.
- `Scripts/package-app.sh`: produced an ad-hoc signed application bundle that
  passed strict deep signature verification.
- Signed-app review with the deterministic `north-star` scene confirmed the
  persistent inspector's semantic-stop menu. Selecting **This week** moved the
  selected node to 74% attention and enabled one Undo command.

The automated macOS driver cannot fully reproduce physical trackpad or
modifier-held drags, so two-finger, Option-drag, and Command-Option-drag remain
short manual feel checks in addition to their deterministic application-logic
coverage.
