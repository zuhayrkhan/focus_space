# Branch focus, shape preferences, and selected notes

This refinement makes selection feel like entering a branch and lets the node language adapt without adding per-card visual administration.

## Branch focus

Selecting a node with descendants now animates the camera toward that complete branch. The new pose:

- preserves the current yaw and pitch, so the universe does not snap back to a front view
- moves closer than the current camera distance
- frames the selected node and its descendants
- biases the frame toward the selected parent so an expanded card remains comfortably visible

Selecting a leaf changes emphasis and opens its inspector without moving the camera. `Command-0` still returns to the canonical view, and **Frame Selected Branch** remains available explicitly.

Trackpad pinch/stretch remains a direct camera zoom. A native macOS magnification recogniser is attached to the Reality canvas, bypassing SwiftUI's competing tap and drag gesture arena while leaving the sidebar and inspector unaffected.

## Global shape preference

**Node shape** in the left sidebar is a persistent, app-wide preference. It applies immediately to every card while colour, glyph, urgency, and attention continue to carry their existing semantics.

The available visual languages are:

- **Distinct** — the original kind-specific silhouettes
- **Rounded** — consistent calm rounded rectangles
- **Capsule** — a softer pill-shaped family
- **Compact** — tighter cards with restrained corners

Shape is intentionally not stored on individual nodes. RealityKit consumes the global rendering preference without adding presentation detail to the domain model.

## Notes on selected cards

Nodes now have a persistent `notes` field. Existing version 1 and version 2 maps migrate it to an empty string; new saves use map schema version 3.

Notes are edited in the scrollable inspector. Editing is coalesced as one interaction for Undo and autosave. When a selected node has non-empty notes, its card expands and shows:

- the title in a distinct header area
- a quiet divider
- a concise, word-wrapped note preview

Unselected cards and selected cards without notes retain their normal dimensions. The full note remains editable in the inspector even when its on-card preview is shortened.

## Acceptance

Accepted live in the signed macOS bundle on 19 July 2026 using the deep hierarchy scene. Parent selection moved closer while retaining the existing orientation, the expanded root remained fully in frame, all four shape preferences updated the complete map, and live inspector edits appeared immediately on the selected card.
