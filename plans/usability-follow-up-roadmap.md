# Focus Space usability follow-up roadmap

Status: U1 and U2 completed on 21 July 2026; U3 awaits hands-on review

Scope: usability refinement only. Preserve the accepted bilateral arrangement, semantic colours, shapes, relationship curves, selection haze, and Z-as-attention model.

## Review basis

The signed app was exercised at its standard window size using the personal space, empty space, dense 32-thought map, and large 180-thought map. The review covered selection and the inspector, search, workspace guides, the spatial guide, filtering, arrangement, first-thought creation, and multi-root overview framing.

The strongest parts should remain quiet and intact:

- the empty-space invitation and first-thought rename flow
- selection and branch framing on small maps
- the bilateral map produced by Arrange
- the spatial guide's visual explanation of attention and connected movement
- direct manipulation with explicit Undo

The accessibility driver took roughly 109 seconds to expose the initial 180-thought scene and 102 seconds after arranging it. Those figures include driver and accessibility-tree overhead, so they are evidence of a scale boundary rather than app frame-time benchmarks. Instrumented measurements must establish the real cost.

## Observed friction

### 1. A whole-map view stops being useful before 180 thoughts

The unarranged large fixture opens as overlapping cards and equally prominent links. Arrange removes overlap, but eighteen rooted trees exceed the useful camera overview: cards become too small to read and outer islands fall beyond a meaningful single frame. The 32-thought scene has the same issue in milder form.

This is not primarily a spacing problem. A large map needs progressive disclosure and an explicit way to move between islands.

### 2. Search focus and selection disagree

Searching for `shared` correctly framed the single matching card, but the inspector continued to show the previously selected, now off-screen thought. The camera, visible card, selection state, and inspector therefore described different contexts.

### 3. Temporary UI can trap or obscure the workspace

- The spatial guide disables interactive dismissal and does not respond to Escape; reopening it requires progressing to **Enter Focus Space** before work can continue.
- The Workspace Guides popover remained open after selecting a thought and obscured both the canvas and inspector.
- The movable colour key can occupy the same corner as important cards, especially in dense and multi-island overviews.

### 4. Filters hide structure without enough acknowledgement

With **Near me** active, Arrange frames the complete X/Y result while parked nodes are absent or extremely subdued. There is no visible hidden-count cue, so a user can reasonably believe thoughts or branches were lost. Switching to **Everything** resolves the ambiguity, but the interface does not explain the difference at the moment it matters.

### 5. Overview chrome competes with the map

At the standard window size the permanent inspector, sidebar, colour key, toolbar, and navigation strip substantially reduce the usable universe. Some toolbar and bottom-strip icons become extremely low contrast when controls fade. The empty space does not need a colour key, while the large map needs more canvas and stronger orientation cues.

### 6. Native command and development surfaces need one polish pass

The menu bar currently exposes two **View** menus because the app adds a custom `CommandMenu("View")` alongside the standard menu. Experience previews are useful for development but occupy permanent everyday sidebar space.

## Principles for the follow-up

1. Do not solve scale by making every card smaller.
2. At any moment, the camera, visible emphasis, selection, inspector, and search result must describe the same context.
3. Temporary help must never block returning to the workspace.
4. When content is hidden, state how much is hidden and why.
5. Prefer revealing detail through zoom and branch focus over adding a minimap full of tiny unreadable cards.
6. Preserve direct manipulation and one-step Undo throughout.

## Milestone U1 — Coherent search and transient UI

Priority: first; small surface area and high confidence.

Completion: implemented and verified on 21 July 2026. Search now owns a reversible session containing its prior selection, camera, and navigation context. The active result drives selection, card emphasis, camera, and inspector; arrow keys traverse, Return commits, Clear restores the search origin, and Cancel or Escape restores and closes. The guide has independent Close and completion actions, while canvas and transient-surface interactions dismiss workspace guides predictably.

- Model search focus explicitly instead of moving only the camera.
- A single match becomes the active search result and drives the inspector; multiple matches support next/previous traversal and Return to select.
- Closing search restores the prior selection and camera unless the user commits a result.
- Add a clear no-results state without moving the camera.
- Make the spatial guide dismissible with Escape and an explicit close control. First-run completion remains distinct from dismissal.
- Close Workspace Guides when the user interacts with the canvas, selects a thought, opens search, or opens another transient surface.
- Define Escape consistently: dismiss transient UI first, then clear selection only when no transient UI is open.

Definition of done:

- Search, camera, card emphasis, and inspector never refer to different thoughts.
- Keyboard-only users can enter, traverse, commit, clear, and leave search.
- Every sheet and popover has a predictable route back to the workspace.

## Milestone U2 — Honest visibility and orientation

Priority: second; prevents users mistaking filtering for data loss.

Completion: implemented and verified on 21 July 2026. Every filter reports its count and the active filter reports the hidden total. Arrange discloses filtered content with a direct **Show Everything** action, while dimmed relationship paths retain structural continuity. Framed and committed-search contexts expose a return breadcrumb, and the reset control and `Command-0` now explicitly restore the canonical universe.

- Add visible counts to **Near me**, **Everything**, and **Parked**, including a quiet `n hidden` indication when the current filter excludes thoughts.
- After Arrange, show a temporary explanation when nodes are outside the active depth filter, with one action to reveal Everything.
- Preserve faint relationship continuity toward hidden depth-filtered nodes without rendering full hidden cards.
- Add a compact current-context breadcrumb for framed branches and search results, with a one-click return to the previous or whole-map context.
- Make `Command-0` and the reset control communicate which view they will restore: canonical universe, current island, or whole map.

Definition of done:

- A reviewer can always explain why a known thought is absent.
- Arrange never appears to delete or lose a branch.
- Leaving a framed/search context is obvious without relying on gesture memory.

## Milestone U3 — Semantic zoom and island navigation

Priority: third; the main large-map usability investment.

Introduce renderer-independent presentation levels driven by camera distance and context:

1. **Atlas** — show each root island as a labelled summary with child count, attention range, and urgency count.
2. **Branch** — show the root, first-level branches, and compact summaries for deeper descendants.
3. **Detail** — show the current full cards, labels, notes expansion, badges, and direct manipulation.

Within Branch and Detail views, use focus-relative levels of detail rather than one fixed generation cut-off:

- the focused node and its immediate children normally remain full-size cards
- descendants two generations away become smaller, compact shapes with short labels
- descendants three or more generations away remain visible as still smaller semantic silhouettes, with labels revealed when space permits
- selecting, framing, or zooming into a descendant promotes it and its nearby family smoothly through those levels until they reach normal card size

The generation counts are defaults, not hard boundaries. Available screen space, projected card size, branch density, selection, urgency, and accessibility settings may keep a node at a richer level for longer. A card should compact before its title becomes illegible, and compact nodes should retain generous invisible hit targets rather than becoming difficult to select.

- Add an island navigator derived from the domain graph, not RealityKit entities. Selecting an island frames it without changing attention.
- Use smooth scale, label, and material transitions between presentation levels so descendants appear to come into focus rather than being replaced.
- Keep selected paths and urgent items discoverable at every level.
- Do not create a separate miniature universe that duplicates the same unreadability. The navigator should be a concise list, constellation of roots, or search-driven switcher.
- Define what Option-drag means at Atlas level: translate the island summary and commit the same delta to its connected component.

Definition of done:

- The 180-thought fixture opens to a readable atlas rather than a wall of cards.
- Every root is reachable in two actions or fewer.
- No full card is rendered at a scale where its title is illegible.
- A three- or four-generation branch remains structurally readable from its ancestor without giving every descendant equal visual weight.
- Traversing down that branch promotes the new local family to normal card size without a pop or camera jump.
- Zooming into one island reveals the accepted bilateral layout without a visual jump.

## Milestone U4 — Adaptive workspace chrome

Priority: fourth; tune after semantic zoom establishes the information hierarchy.

- Increase active-toolbar contrast while retaining calm disabled states.
- Keep the navigation strip legible when visible and fully remove it from hit testing when hidden.
- Hide the colour key in an empty space; allow it to collapse to a small key button in dense or Atlas views.
- When the key is expanded, choose the clearest docked corner and retain manual corner choice as an override.
- Offer a distraction-free workspace action that temporarily hides both sidebars and transient overlays, with a single reversible shortcut.
- Make the inspector width modestly adjustable and guarantee multi-line titles and notes remain readable at its minimum width.
- Move Experience Previews behind a development/Help surface for normal personal use.
- Merge custom commands into the native **View** menu instead of creating a duplicate.

Definition of done:

- The map retains the majority of the window at the compact supported size.
- Active controls are identifiable without hovering.
- Overlays do not cover the active card or inspector by default.
- The menu bar contains one View menu with predictable macOS grouping.

## Milestone U5 — Measured scale and interaction feel

Priority: continuous, completed after U3 and U4.

- Add signposts for launch-to-interactive, snapshot derivation, renderer reconciliation, relationship reconciliation, accessibility representation, Arrange, search framing, and Option-drag preview.
- Separate rendered performance from accessibility-tree construction in measurements.
- Virtualise or context-limit accessibility elements for very large maps while preserving a complete, searchable list representation.
- Exercise 32-, 65-, and 180-thought fixtures at compact, standard, and large window sizes.
- Add a manual trackpad checklist for pinch zoom, two-finger camera pan, two-finger branch depth, Option-drag island movement, selection framing, and Command-0 recovery.
- Capture a short screen recording for small-map and large-map acceptance; still screenshots cannot validate motion or continuous drag.

Provisional budgets, to be confirmed on the target Mac:

- small and medium fixtures interactive within 1 second after the window appears
- large fixture interactive within 2 seconds
- direct drag and camera previews sustain at least 30 fps, targeting display refresh where practical
- search feedback appears within 100 ms for 180 thoughts
- Arrange supplies visible progress if it cannot complete within 250 ms

Definition of done:

- Performance claims are backed by signposts rather than the automation driver's wall-clock time.
- The exact packaged app and physical gestures pass the checklist.
- Accessibility remains complete without forcing hundreds of off-context spatial elements into every update.

## Recommended order

1. U1 — fix state coherence and dismissal traps.
2. U2 — make filters and navigation state honest.
3. U3 — establish semantic zoom and island navigation.
4. U4 — tune chrome around the new presentation levels.
5. U5 — validate and harden the complete experience at scale.

Each milestone should be implemented and accepted independently. U3 should begin with a static 180-thought Atlas prototype before changing the live renderer so the information hierarchy can be judged visually first.
