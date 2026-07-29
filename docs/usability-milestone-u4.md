# Usability milestone U4 — adaptive workspace chrome

Completed: 29 July 2026

## Outcome

Focus Space now gives the universe the majority of the supported compact window while retaining useful controls when they are needed.

- Active toolbar controls use a clear foreground treatment; disabled Undo and Redo remain visibly quieter.
- The navigation strip is conditionally removed after four seconds of inactivity. It no longer leaves an invisible hit target over the canvas.
- The colour key is absent in an empty space, expanded for ordinary maps, and reduced to a key button for maps with at least 48 thoughts or an Atlas presentation.
- Before the user docks it, the key scores the visible nodes in each corner and chooses the clearest one. The Atlas context breadcrumb makes the top-left corner ineligible by default. Dragging the expanded key stores the user's corner as an explicit override.
- `Shift-Command-D` enters and leaves a distraction-free workspace. It hides the leading sidebar, inspector, colour key, navigation strip, depth guide, search and guide overlays as one reversible action.
- The inspector uses a native split divider and can be adjusted from 260 to 420 points. Multi-line titles retain their full vertical size at the minimum width.
- Experience Previews moved from the permanent sidebar to **Help → Experience Previews**.
- Arrange, framing, camera, inspector, colour-key and distraction-free commands now extend the native **View** menu. No second View menu is created.

## Verification

- `swift test`: 83 tests passed.
- The release app bundle built, received an ad-hoc signature and passed strict code-signature verification.
- The packaged app was inspected at the supported compact size with the personal space and the 65-thought Animal family Atlas.
- The compact personal space retained more width for the universe than either side panel; the inspector divider was moved through the live interface.
- The Atlas rendered five legible island summaries and used the compact key treatment without covering its context breadcrumb.
- The menu bar exposed one **View** menu, and **Help → Experience Previews** exposed every deterministic fixture plus Personal Space.
- `Shift-Command-D` removed both sidebars and all canvas chrome, and the same shortcut restored the prior workspace.

## Regression policy

`WorkspaceChromePolicy` is deliberately independent of RealityKit. Its tests cover empty, ordinary, dense/Atlas, expanded and distraction-free colour-key states so renderer work cannot accidentally reintroduce invisible or inappropriate overlay chrome.
