# Usability milestone U3 — semantic zoom and island navigation

Implemented on 22 July 2026 and ready for hands-on review.

## What changed

- **Atlas** replaces the wall of cards in large multi-root spaces with one summary per hierarchy root.
- Each summary reports its thought count, attention range, and urgent-thought count.
- Selecting a summary moves directly into that island without changing any attention values.
- The toolbar **Islands** menu provides a concise, graph-derived route to every hierarchy root.
- **Branch** and **Detail** presentation levels are derived outside RealityKit.
- The focused thought, its ancestors, and its immediate children remain full cards.
- Descendants taper through five labelled visual levels: full, compact, reduced, miniature, and distant.
- Labels become progressively smaller, shorter, and dimmer over four to five generations rather than disappearing abruptly.
- Selecting a descendant promotes its local family smoothly to full cards.
- Compact nodes retain enlarged invisible hit targets.
- Option-dragging an Atlas summary moves its connected map, previews continuously, and remains one-step undoable.
- Command–F opens or refocuses Find in Focus Space.

## Suggested review

### Large map (180 thoughts)

1. Open **Experience previews → Large map (180 thoughts)**.
2. Confirm the opening view contains 18 readable island summaries rather than 180 full cards.
3. Confirm the top-left context reads **Atlas · 18 islands**.
4. Open **Islands** and choose any entry; the selected hierarchy should fill the useful canvas in one action.
5. Use **Previous view** to return to the Atlas.
6. Option-drag a summary and then Undo; the summary and connected map should move together and return together.

### Deep hierarchy

1. Open **Experience previews → Deep hierarchy**.
2. Select **Release Focus Space**.
3. Its immediate children should remain full cards. Later generations should step smoothly through compact, reduced, miniature, and distant cards.
4. Confirm every visible generation still has a readable label, with progressively smaller and quieter text.
5. Select **Semantic zoom**; it and **Focus selected branch** should promote to full cards without a visual pop.
6. Confirm every reduced shape remains easy to click despite its smaller visible size.

### Command–F

1. Press Command–F from the canvas.
2. Find should open with keyboard focus in the search field.
3. Press Command–F again after moving focus elsewhere; the existing search session should regain focus rather than being reset.

## Automated verification

The regression suite covers the 18-root Atlas, summary metadata, Atlas framing, island selection without attention mutation, generation-relative presentation, descendant promotion, compact hit targets, Command–F refocusing, Atlas Option-drag continuity, and one-step Undo.
