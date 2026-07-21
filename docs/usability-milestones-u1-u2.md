# Usability milestones U1 and U2

Completed on 21 July 2026 following the signed-app usability review.

## U1 — coherent search and transient UI

- Search is an explicit, reversible session rather than a camera-only action.
- The active result is the selected thought, the inspector subject, and the camera target.
- Up and Down traverse multiple results; Return commits the active result.
- Clear restores the pre-search selection and camera while leaving search open.
- Cancel or Escape restores the pre-search context and closes search.
- A no-results query reports the empty result without moving the camera.
- The spatial guide has both a Close action and a distinct first-run completion action.
- Workspace Guides closes when the user selects or manipulates the canvas, opens search, or opens the spatial guide.
- Escape dismisses a transient surface before it clears the workspace selection.

## U2 — honest visibility and orientation

- Near me, Everything, and Parked show their current thought counts.
- The active filter reports how many thoughts it subdues.
- Arrange works over the complete map, then explains when the chosen depth filter is keeping thoughts quiet and offers **Show Everything**.
- Filtered branches retain faint relationship continuity instead of appearing severed.
- Framed branches and committed search results show their current context and a one-click route to the previous view or whole map.
- The reset control and `Command-0` explicitly describe their destination as the canonical universe.

## Verification

- The Swift test suite includes search traversal, commit, cancellation, no-result camera stability, filter counts, Arrange disclosure, relationship continuity, and framed-context return coverage.
- The release gate builds the packaged app, validates its property list, and verifies its ad-hoc signature.
- Hands-on acceptance was performed against the packaged app, not a SwiftUI preview.
