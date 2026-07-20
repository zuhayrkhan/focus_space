# Bilateral mind-map layout

Focus Space now arranges a connected hierarchy as a true bilateral mind map. The map's real root remains a normal, editable thought at the centre. Its first-level branches are balanced across the left and right, and every later generation grows further outward.

This changes only X/Y arrangement. Attention remains Z, and the existing semantic colours, card shapes, relationship curves, selection treatment, and direct manipulation remain unchanged.

## Behaviour

- **Arrange Mind Map** (`Command-Shift-L`) converts the current map to the bilateral layout and frames the result.
- Existing authored positions remain untouched until Arrange is invoked.
- Option-dragging any thought translates its complete connected island, including hierarchy and cross-link connections, while preserving relative layout and attention.
- A new child continues outward on its parent's side of the map. Children created from the central root alternate toward the less populated side.
- Separate rooted trees remain separate mind-map islands. They are packed in centred rows of no more than two islands so their branches remain readable.
- Large collections of unrelated thoughts retain the compact fallback grid.
- Arrange remains one Undo operation and never changes attention.

## Architecture

`MindMapArranger` owns the renderer-independent layout. It consumes `FocusMap` and returns domain `SpatialPoint` values; RealityKit only renders the resulting snapshot. This keeps the layout replaceable without coupling application logic to the current 3D renderer.

The overview camera supports the wider span of bilateral maps, while preserving the user's current viewing angle when framing a branch.
