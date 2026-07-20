# Interaction refinements — Ibrahim review

This refinement pass responds to Ibrahim's review of selection, relationship persistence, layout, and spatial atmosphere.

![Accepted arranged deep hierarchy](reference/interaction-refinement-arranged.png)

## Selection and relationships

An empty-space click now clears selection and closes the inspector. Node clicks remain targeted, so deselection does not compete with selection, rename, or drag gestures.

Selection increases the emphasis of a branch; it no longer determines whether other relationships exist. Unrelated links keep a readable baseline and return to standard emphasis when selection clears. Parked and filtered relationships remain quieter, but are never removed from the scene snapshot.

## Arrange mind map

**Arrange Mind Map** is available in the toolbar, the View menu, and with `Command-Shift-L`. A renderer-independent bilateral mind-map layout:

- preserves attention and therefore semantic Z
- keeps each real root at the centre of its map
- balances first-level branches across the left and right sides
- grows descendants outward while centring parents across their own leaves
- separates siblings and overlapping cards
- packs several rooted maps as centred two-column islands
- uses a compact grid for a large set of independent thoughts
- frames the complete result in an overview camera pose
- records one Undo step

## Spatial web

The fixed rear-plane guide was replaced with a shallow volumetric web. Its nested rings occupy different Z depths and its spokes slope away through the universe, so orbiting reveals it as scene geometry. The renderer dynamically positions the web behind the furthest-back visible node, with a safety gap. No part of the web can therefore appear in front of a card, regardless of the map's attention range.

The persistent **Universe web** opacity slider now lives directly in the left sidebar instead of the floating navigation strip. Its readout shows the literal rendered opacity, and the renderer clamps the final value to a quiet maximum.

The former “FOCUS / YOU ARE HERE” caption and its luminous origin marker have both been removed.

## Colour key and starfield

A screen-space colour key now sits in the top-right corner by default. Because it is a SwiftUI overlay rather than RealityKit content, it remains fixed while the universe moves. Dragging the key toward another corner docks it there and persists the choice; the legend gesture is isolated from camera navigation.

The starfield is wider, deeper, and denser at every quality level. It now fills the peripheral workspace during overview and orbit views instead of clustering around the original central composition.

## Acceptance

Accepted live on 19 July 2026 in the signed release bundle. Empty-space deselection closed the inspector while preserving every hierarchy path. Arrange separated the full graph, framed all outer leaves, enabled Undo, and left attention unchanged. The web remained visibly three-dimensional while staying behind every card. The sidebar slider responded immediately, the denser starfield filled the window, and the colour key was docked between opposite corners without moving the universe beneath it.
