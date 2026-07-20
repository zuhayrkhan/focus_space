# Focus Space visual experience roadmap

Status: Milestones 0–8 complete; Milestone 9 next

North star: the polished Focus Space concept supplied on 18 July 2026

Starting point: the initial SwiftUI and RealityKit experience slice on `main`

## Outcome

Evolve the working prototype into a calm spatial environment in which depth is immediately readable as attention. The concept image is the visual target, not a literal requirement to display every explanatory panel at all times.

The everyday workspace should feel spacious and quiet. Legends, diagrams, depth explanations, and gravity/time guidance belong in onboarding or contextual help and should disappear once understood.

## Product rules to preserve

1. Z always means attention. Camera navigation must never undermine that meaning.
2. X/Y expresses hierarchy and relationships rather than arbitrary decoration.
3. Direct manipulation is primary; controls explain or refine it rather than replace it.
4. The camera and scene animate between states instead of jumping.
5. Distance must remain legible through several cues: perspective, scale, light, contrast, blur, and motion.
6. RealityKit remains behind the renderer boundary. Domain and application code never depend on RealityKit types.
7. The interface is visually quiet during normal use. Complexity is progressively disclosed.
8. Every milestone must be reviewable in the running app before the next layer is added.

## Milestone 0 — Preserve the visual contract

Status: complete on 18 July 2026

Goal: make the intended direction durable and measurable before changing the renderer.

- Add the supplied north-star image to a repository-owned `docs/reference` location once its redistribution status is confirmed.
- Extract reusable design tokens for the background, glass, node families, glow, typography, spacing, and motion.
- Define representative scene fixtures: shallow hierarchy, deep hierarchy, dense map, parked work, overdue work, and empty space.
- Add a debug/demo map selector so the same scenes can be reviewed repeatedly.
- Capture baseline screenshots of the current implementation.

Definition of done:

- The reference and tokens are versioned.
- A reviewer can open deterministic demo scenes without altering their own saved map.
- Current and target screenshots can be compared at the same window size.

## Milestone 1 — Build the spatial atmosphere

Status: complete on 18 July 2026

Goal: make an empty Focus Space feel like the concept before polishing individual nodes.

- Replace the flat background with a restrained procedural depth field.
- Add subtle orbital/grid guides that strengthen perspective without resembling a chart.
- Establish a luminous focus origin and a soft falloff into parked space.
- Tune the RealityKit camera, key/fill lighting, tone, and depth range as one composition.
- Introduce a renderer-owned quality profile so expensive effects can degrade gracefully.
- Keep background motion extremely slow and respect Reduce Motion.

Definition of done:

- Depth remains readable with labels temporarily hidden.
- The scene feels dimensional in a still screenshot and more convincing in motion.
- Idle rendering is stable and does not create distracting shimmer or excessive GPU load.

## Milestone 2 — Establish the node visual language

Status: complete on 19 July 2026

Goal: make node meaning and attention readable before the user reads a label.

- Add a renderer-independent `FocusNodeKind` domain concept with a backward-compatible JSON migration:
  - project or area
  - group or subcategory
  - task or item
  - reference or note
  - someday or maybe
- Create a material/style system mapping node kind, attention, selection, urgency, and disabled state to visuals.
- Use brighter edges and controlled bloom near focus; reduce saturation, contrast, and solidity with distance.
- Establish hierarchy cues: broader concepts sit higher, detail sits lower.
- Improve label layout, truncation, contrast, and occlusion behaviour.
- Replace hard selection scaling with a calm light/halo response.

Definition of done:

- Kind, hierarchy, attention, and selection are distinguishable without opening the inspector.
- Colour is never the only carrier of meaning.
- Long, short, and multilingual labels remain readable.

## Milestone 3 — Make relationships feel spatial

Status: complete on 19 July 2026

Goal: turn the current straight connectors into a coherent living structure.

- Render curved, softly illuminated parent-child paths.
- Differentiate hierarchy links from cross-links without adding visual noise.
- Fade links by depth and context; emphasise the selected path and nearby family.
- Add branch-level hover/selection previews.
- Prevent dense maps from becoming a web of equally prominent lines.
- Validate connection geometry behind, beside, and in front of nodes.

Definition of done:

- A selected node’s ancestry and immediate children are obvious.
- Parked relationships recede without disappearing completely.
- Dense demo scenes remain navigable.

## Milestone 4 — Camera and navigation

Status: complete on 19 July 2026

Goal: deliver the pan, orbit, zoom, frame-selected, and reset interactions promised by the vision pack.

- Introduce a renderer-independent camera intent API.
- Implement trackpad/mouse pan, restrained orbit, zoom, frame selected, and reset view.
- Let the user frame a selected branch independently of where that branch sits on the semantic Z axis.
- Use `Command-0` as the predictable animated return to the canonical focus-origin view.
- Evaluate a gentle idle return to the canonical view, but never recenter while a branch focus or direct manipulation remains active.
- Animate every programmatic camera transition with interruption-safe motion.
- Add a minimal, auto-hiding navigation control strip inspired by the concept.
- Keep camera movement within bounds that preserve Z as attention.
- Provide keyboard equivalents and Reduce Motion behaviour.

Definition of done:

- Navigation feels predictable with both mouse and trackpad.
- Framing a node never changes its attention value.
- A user can always recover orientation with one action.

## Milestone 5 — Refine depth manipulation

Status: complete on 20 July 2026

Goal: make pulling work forward the signature interaction rather than a disguised slider.

- Replace the provisional Option-drag calculation with ray/plane-based spatial manipulation.
- Show a temporary depth guide only while changing attention.
- Add magnetic semantic stops such as now, this week, this sprint, this quarter, and someday without forcing scheduling metadata.
- Support moving a whole branch and explicitly pulling one child out of that branch.
- Tune spring, resistance, hover, and release behaviour.
- Preserve explicit inspector and keyboard controls as accessible alternatives.
- Keep one continuous manipulation as one undoable command.

Definition of done:

- Users can predict where an item will land before releasing it.
- Pulling forward feels materially different from moving in X/Y.
- Accidental reprioritisation is rare and easily undone.

## Milestone 6 — Gravity and time

Status: complete on 20 July 2026

Goal: implement the concept’s automatic pull without taking agency away from the user.

- Extend the domain with optional temporal signals: due date, milestone, reminder, and last manual override.
- Model gravity as pure application logic producing a suggested attention value and explanation.
- Keep manual attention separate from computed influence so the system is inspectable and reversible.
- Animate gradual changes; never silently teleport nodes.
- Add lightweight urgency markers for overdue or approaching work.
- Provide per-node and workspace-level gravity controls.

Definition of done:

- Every automatic movement has a human-readable reason.
- Manual override always wins for a clearly defined period.
- Opening an older JSON map produces no unexpected movement until the user enables gravity.

## Milestone 7 — Progressive disclosure and onboarding

Status: complete on 20 July 2026

Goal: teach the spatial grammar without leaving the instructional concept board permanently on screen.

- Create a first-run guided scene explaining depth, hierarchy, branch movement, and gravity.
- Add optional, collapsible legend, depth scale, view filter, and time-flow panels.
- Add contextual hints that disappear after the related interaction succeeds.
- Refine search so results are framed spatially rather than merely filtered.
- Add a focus mode that temporarily quiets unrelated branches.
- Ensure inspector and toolbar controls appear only when relevant.

Definition of done:

- A new user can explain the depth metaphor after the guided scene.
- An experienced user can work with almost no persistent chrome.
- Help can always be reopened.

## Milestone 8 — Persistence, accessibility, and resilience

Status: complete on 20 July 2026

Goal: make the evolved experience safe for real daily use.

- Version all domain changes and add migration tests for every shipped JSON schema.
- Add import, export, recovery, and explicit save-location diagnostics.
- Add VoiceOver descriptions and actions for nodes, links, depth, hierarchy, and urgency.
- Support keyboard-only traversal and manipulation.
- Respect Reduce Motion, Increase Contrast, Differentiate Without Colour, and text scaling.
- Add renderer failure fallbacks so data remains usable if advanced effects are unavailable.

Definition of done:

- Existing maps survive upgrades without loss.
- Core workflows are usable without colour, animation, precise pointing, or 3D rendering effects.
- Autosave and recovery have automated tests.

## Milestone 9 — Delight and release hardening

Goal: turn a convincing prototype into something enjoyable to open every morning.

- Profile frame time, memory, launch time, autosave, and large-map behaviour.
- Tune motion and sound as a unified system; keep sound subtle and optional.
- Add empty-space, loading, failure, and first-map experiences.
- Run repeated visual QA at standard window sizes and display scales.
- Package, sign, notarise, and document the application.
- Conduct a final pass that removes controls and effects which do not earn their visual weight.

Definition of done:

- Representative dense scenes remain fluid on the agreed minimum Mac.
- The application passes accessibility and persistence checks.
- Release packaging is reproducible from a clean checkout.

## Recommended working rhythm

For each milestone:

1. Agree on one representative interaction and one visual reference.
2. Implement the smallest vertical slice across domain, application, renderer, and UI.
3. Build and run automated tests.
4. Review the live app and capture a screenshot or short recording.
5. Tune the experience before expanding scope.
6. Commit the accepted milestone independently.

Avoid combining domain expansion, renderer redesign, and several new interactions in one review. The visual experience will benefit from short build–feel–adjust loops.

## Suggested first session

Start with Milestone 0 and the first half of Milestone 1:

- preserve the north-star reference
- add deterministic demo maps
- define visual tokens
- build the atmospheric depth field and focus light

This gives the largest immediate movement toward the concept without prematurely locking in node geometry or automatic prioritisation behaviour.
