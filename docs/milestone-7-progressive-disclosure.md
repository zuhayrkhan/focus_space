# Milestone 7 — Progressive disclosure and onboarding

Completed on 20 July 2026.

## First-run spatial guide

A four-step guided scene opens on first run and teaches the complete spatial
grammar:

1. near and bright means attention now; far and quiet means deliberately parked;
2. X/Y hierarchy places broader parents above their detail;
3. a vertical two-finger drag carries a branch in depth, with Option-drag and
   Command-Option available as pointer alternatives;
4. time signals may suggest a pull, but a manual move wins for seven days.

The guide uses quiet animated spatial illustrations, respects Reduce Motion, and
never changes the user's map. It records completion in app preferences and can
always be reopened from the toolbar's **?** button.

## Progressive disclosure

The permanent instruction footer is gone. A small contextual hint advances from
selection, to depth change, to universe navigation, then disappears permanently
as each interaction succeeds.

The **Workspace guides** popover keeps four panels collapsed by default:

- Legend, including the switch for the movable floating colour key;
- Depth scale with the five semantic attention stops;
- View filter with Near me, Everything, and Parked;
- Time flow with its explanation and workspace gravity switch.

The inspector, native sidebar, floating colour key, and selected-branch controls
can all be hidden or appear only when relevant. Camera controls continue to fade
at rest. An experienced user can therefore leave the spatial canvas almost free
of chrome without losing a route back to help.

## Spatial search and focus

Search matches both titles and notes. While a query is active it temporarily
looks beyond the current view filter, dims non-matches, reports the result count,
and animates the camera to frame the matching spatial region without changing
any attention values. Closing search removes its dimming while retaining the
new viewpoint.

With a selected thought, **Focus selected branch** quiets unrelated branches.
The selected thought, its ancestors, descendants, and immediate siblings remain
readable. Deselecting restores the whole space automatically.

## Acceptance evidence

- `swift test`: 45 tests passed, including the four-part guide contract,
  contextual-hint completion, search framing without attention mutation, and
  focus-mode branch isolation.
- `Scripts/package-app.sh`: produced an ad-hoc signed application bundle that
  passed strict deep signature verification.
- Signed-app review completed the first-run guide, reopened the low-chrome
  workspace, inspected all four collapsed guide panels, expanded the semantic
  depth scale, and hid the floating colour key.
- Searching **spikes** returned one result and animated **Investigate spikes**
  into the centre of the view despite its previous depth and the active
  **Near me** filter.
